import Foundation
import Hummingbird

/// Localhost-only HTTP server that receives lifecycle events from local
/// agent CLIs and editors (Claude Code, Codex, Cursor).
///
/// Deliberately separate from `WebhookServer`: that one is exposed to the
/// public internet through the cloudflared tunnel for Manus, while this one
/// must never leave 127.0.0.1. No signature verification is needed — the
/// bind address is the trust boundary.
///
/// Always returns 200 (even for undecodable bodies) so a hook misfire can
/// never surface as an error inside the user's Claude Code session.
///
/// Resilience: a failed serve loop (typically "address already in use" from
/// a lingering process) no longer dies silently — it retries with backoff a
/// bounded number of times, and `ensureRunning()` (called on system wake)
/// re-arms a server that exhausted its retries.
public actor LocalHookServer {
    public let port: Int

    private struct Handlers {
        let onClaudeCode: @Sendable (ClaudeCodeEvent) -> Void
        let onCodex: @Sendable (CodexEvent) -> Void
        let onCursor: @Sendable (CursorEvent) -> Void
    }

    /// Total serve attempts per arming (1 initial + 4 retries).
    private static let maxConsecutiveFailures = 5

    private var handlers: Handlers?
    private var serverTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    /// True while a serve loop (or its retry backoff) is in flight.
    private var isServing = false
    /// Lifecycle token: bumped on every start/stop/re-arm so callbacks from
    /// a cancelled serve loop can never mutate the state of its successor.
    private var epoch = 0

    public init(port: Int = ClaudeHooksInstaller.defaultPort) {
        self.port = port
    }

    public func start(
        onClaudeCodeEvent: @escaping @Sendable (ClaudeCodeEvent) -> Void,
        onCodexEvent: @escaping @Sendable (CodexEvent) -> Void,
        onCursorEvent: @escaping @Sendable (CursorEvent) -> Void
    ) {
        epoch += 1
        serverTask?.cancel()
        handlers = Handlers(
            onClaudeCode: onClaudeCodeEvent,
            onCodex: onCodexEvent,
            onCursor: onCursorEvent
        )
        consecutiveFailures = 0
        launchServeLoop(epoch: epoch)
    }

    /// Health check for the wake path: relaunch if the serve loop died
    /// (e.g. port was busy at boot and retries ran out; the offender is
    /// often gone by the time the machine wakes again).
    public func ensureRunning() {
        guard handlers != nil, !isServing else { return }
        IslandLogger.webhook.info("LocalHookServer health check: serve loop dead — relaunching")
        epoch += 1
        consecutiveFailures = 0
        launchServeLoop(epoch: epoch)
    }

    public func stop() {
        epoch += 1
        serverTask?.cancel()
        serverTask = nil
        handlers = nil
        isServing = false
        IslandLogger.webhook.info("LocalHookServer stopped")
    }

    // MARK: - Serve loop

    private func launchServeLoop(epoch: Int) {
        guard epoch == self.epoch, let handlers else { return }
        isServing = true
        serverTask = Task {
            do {
                try await Self.serve(port: port, handlers: handlers)
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
        guard epoch == self.epoch, !Task.isCancelled, handlers != nil else {
            markStopped(epoch: epoch)
            return
        }
        launchServeLoop(epoch: epoch)
    }

    private static func serve(port: Int, handlers: Handlers) async throws {
        let router = Router()

        router.post("/hooks/claude-code") { request, _ -> HTTPResponse.Status in
            if let event: ClaudeCodeEvent = await Self.decodeBody(of: request, cli: "Claude Code") {
                handlers.onClaudeCode(event)
            }
            return .ok
        }

        router.post("/hooks/codex") { request, _ -> HTTPResponse.Status in
            if let event: CodexEvent = await Self.decodeBody(of: request, cli: "Codex") {
                handlers.onCodex(event)
            }
            return .ok
        }

        router.post("/hooks/cursor") { request, _ -> HTTPResponse.Status in
            if let event: CursorEvent = await Self.decodeBody(of: request, cli: "Cursor") {
                handlers.onCursor(event)
            }
            return .ok
        }

        let app = Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: port))
        )
        IslandLogger.webhook.info("LocalHookServer listening on 127.0.0.1:\(port)")
        try await app.run()
    }

    /// Decode a snake_case hook payload; undecodable bodies are dropped
    /// silently (the endpoint always answers 200 either way).
    private static func decodeBody<E: Decodable>(of request: Request, cli: String) async -> E? {
        guard let buffer = try? await request.body.collect(upTo: 1_048_576) else { return nil }
        let data = Data(buffer.readableBytesView)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let event = try? decoder.decode(E.self, from: data) else {
            IslandLogger.webhook.debug("Ignoring undecodable \(cli) hook payload")
            return nil
        }
        IslandLogger.webhook.info("\(cli) hook event received")
        return event
    }
}
