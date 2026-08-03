import Foundation
import Hummingbird

/// Localhost-only HTTP server that receives lifecycle events from local
/// agent CLIs and editors — one route per `LocalAgentDescriptor`.
///
/// Deliberately separate from `WebhookServer`: that one is exposed to the
/// public internet through the cloudflared tunnel for Manus, while this one
/// must never leave 127.0.0.1. No signature verification is needed — the
/// bind address is the trust boundary.
///
/// Always returns 200 (even for undecodable bodies) so a hook misfire can
/// never surface as an error inside the user's agent session.
///
/// Resilience: a failed serve loop (typically "address already in use" from
/// a lingering process) no longer dies silently — it retries with backoff a
/// bounded number of times, and `ensureRunning()` (called on system wake)
/// re-arms a server that exhausted its retries.
public actor LocalHookServer {
    public let port: Int

    /// Total serve attempts per arming (1 initial + 4 retries).
    private static let maxConsecutiveFailures = 5

    private var agents: [LocalAgentDescriptor] = []
    private var onEvent: (@Sendable (String, LocalAgentEvent) -> Void)?
    private var serverTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    /// True while a serve loop (or its retry backoff) is in flight.
    private var isServing = false
    /// Lifecycle token: bumped on every start/stop/re-arm so callbacks from
    /// a cancelled serve loop can never mutate the state of its successor.
    private var epoch = 0

    public init(port: Int = LocalHooksInstaller.defaultPort) {
        self.port = port
    }

    /// Start serving the given agents' endpoints. `onEvent` receives the
    /// agent's `source` plus the normalized event.
    public func start(
        agents: [LocalAgentDescriptor],
        onEvent: @escaping @Sendable (String, LocalAgentEvent) -> Void
    ) {
        epoch += 1
        serverTask?.cancel()
        self.agents = agents
        self.onEvent = onEvent
        consecutiveFailures = 0
        launchServeLoop(epoch: epoch)
    }

    /// Health check for the wake path: relaunch if the serve loop died
    /// (e.g. port was busy at boot and retries ran out; the offender is
    /// often gone by the time the machine wakes again).
    public func ensureRunning() {
        guard onEvent != nil, !isServing else { return }
        IslandLogger.webhook.info("LocalHookServer health check: serve loop dead — relaunching")
        epoch += 1
        consecutiveFailures = 0
        launchServeLoop(epoch: epoch)
    }

    public func stop() {
        epoch += 1
        serverTask?.cancel()
        serverTask = nil
        agents = []
        onEvent = nil
        isServing = false
        IslandLogger.webhook.info("LocalHookServer stopped")
    }

    // MARK: - Serve loop

    private func currentEpoch() -> Int { epoch }

    private func launchServeLoop(epoch: Int) {
        guard epoch == self.epoch, let onEvent else { return }
        let agents = self.agents
        isServing = true
        // Route closures re-check this before delivering: a superseded serve
        // loop may still be draining in-flight requests after cancellation
        // (cancel is non-awaiting), and those must not reach the handlers.
        let isLive: @Sendable () async -> Bool = { [weak self] in
            guard let self else { return false }
            return await self.currentEpoch() == epoch
        }
        serverTask = Task {
            do {
                try await Self.serve(port: port, agents: agents, onEvent: onEvent, isLive: isLive)
                // app.run() only returns on graceful shutdown.
                self.markStopped(epoch: epoch)
            } catch is CancellationError {
                self.markStopped(epoch: epoch)
            } catch {
                await self.handleServeFailure(error, epoch: epoch)
            }
        }
    }

    private func markStopped(epoch: Int) {
        guard epoch == self.epoch else { return }
        isServing = false
    }

    private func handleServeFailure(_ error: Error, epoch: Int) async {
        guard epoch == self.epoch else { return }
        consecutiveFailures += 1
        guard consecutiveFailures < Self.maxConsecutiveFailures else {
            isServing = false
            IslandLogger.webhook.error("""
                LocalHookServer gave up after \(self.consecutiveFailures) failed attempts \
                (last: \(error)). Port \(self.port) likely held by another process. \
                Will retry on next wake.
                """)
            return
        }
        let delay = min(30, consecutiveFailures * 5)
        IslandLogger.webhook.error(
            "LocalHookServer serve loop failed (\(error)) — attempt \(self.consecutiveFailures)/\(Self.maxConsecutiveFailures), retrying in \(delay)s"
        )
        try? await Task.sleep(for: .seconds(delay))
        guard epoch == self.epoch, !Task.isCancelled, onEvent != nil else {
            markStopped(epoch: epoch)
            return
        }
        launchServeLoop(epoch: epoch)
    }

    private static func serve(
        port: Int,
        agents: [LocalAgentDescriptor],
        onEvent: @escaping @Sendable (String, LocalAgentEvent) -> Void,
        isLive: @escaping @Sendable () async -> Bool
    ) async throws {
        let router = Router()

        for descriptor in agents {
            router.post(RouterPath(descriptor.endpointPath)) { request, _ -> HTTPResponse.Status in
                if let event = await Self.decodeBody(of: request, descriptor: descriptor),
                   await isLive() {
                    onEvent(descriptor.source, event)
                }
                return .ok
            }
        }

        let app = Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: port))
        )
        let sources = agents.map(\.source).joined(separator: ", ")
        IslandLogger.webhook.info("LocalHookServer listening on 127.0.0.1:\(port) (\(sources))")
        try await app.run()
    }

    /// Decode a hook payload via the descriptor's mapping; undecodable
    /// bodies are dropped silently (the endpoint answers 200 either way).
    private static func decodeBody(
        of request: Request,
        descriptor: LocalAgentDescriptor
    ) async -> LocalAgentEvent? {
        guard let buffer = try? await request.body.collect(upTo: 1_048_576) else { return nil }
        guard let event = descriptor.decodeEvent(Data(buffer.readableBytesView)) else {
            IslandLogger.webhook.debug("Ignoring undecodable \(descriptor.displayName) hook payload")
            return nil
        }
        IslandLogger.webhook.info("\(descriptor.displayName) hook event received")
        return event
    }
}
