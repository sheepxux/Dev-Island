import Foundation
import Hummingbird
import HTTPTypes

/// User-visible health of the loopback listener that receives local Agent
/// events. This is deliberately transport-level only: it never exposes a
/// session, payload, path, command, or vendor-specific value.
public enum LocalHookServiceStatus: Sendable, Equatable {
    /// The server is being armed or is waiting for its private readiness
    /// endpoint to prove that this process owns the port.
    case starting
    /// Dev Island's own tokenized readiness endpoint answered on loopback.
    case listening
    /// Binding failed and the bounded automatic retry loop is waiting.
    case retrying(attempt: Int, limit: Int)
    /// Every automatic bind attempt failed. A manual retry or wake can rearm.
    case unavailable
    /// The service has not started or was intentionally shut down.
    case stopped
}

/// Retry timing is injectable only inside the module so lifecycle recovery
/// can be exercised deterministically without shortening production backoff.
struct LocalHookServerRetryPolicy: Sendable {
    static let production = LocalHookServerRetryPolicy(
        maxConsecutiveFailures: 5,
        delayAfterFailure: { failure in
            .seconds(min(30, failure * 5))
        }
    )

    let maxConsecutiveFailures: Int
    let delayAfterFailure: @Sendable (Int) -> Duration

    init(
        maxConsecutiveFailures: Int,
        delayAfterFailure: @escaping @Sendable (Int) -> Duration
    ) {
        precondition(maxConsecutiveFailures > 0)
        self.maxConsecutiveFailures = maxConsecutiveFailures
        self.delayAfterFailure = delayAfterFailure
    }
}

/// Orders normalized lifecycle delivery independently for each Agent source.
///
/// Passive Hook requests must return within their short fail-open budget, but
/// spawning one unstructured task per request allows unbounded work and lets a
/// later snapshot overtake an earlier one. This queue keeps at most one drain
/// task per source, coalesces pending passive state for the same session, and
/// gives a synchronous action a barrier behind all earlier lifecycle events.
actor LocalHookEventDelivery {
    static let maximumQueuedEventsPerSource = 256

    private struct Entry {
        let event: LocalAgentEvent?
        let completion: CheckedContinuation<Bool, Never>?

        var isPassive: Bool { completion == nil }
    }

    private struct SourceState {
        var queue: [Entry] = []
        var isDraining = false
    }

    private let maximumQueuedEventsPerSource: Int
    private let onEvent: @Sendable (String, LocalAgentEvent) async -> Void
    private let isLive: @Sendable () async -> Bool
    private var states: [String: SourceState] = [:]

    init(
        maximumQueuedEventsPerSource: Int = LocalHookEventDelivery.maximumQueuedEventsPerSource,
        onEvent: @escaping @Sendable (String, LocalAgentEvent) async -> Void,
        isLive: @escaping @Sendable () async -> Bool
    ) {
        precondition(maximumQueuedEventsPerSource > 0)
        self.maximumQueuedEventsPerSource = maximumQueuedEventsPerSource
        self.onEvent = onEvent
        self.isLive = isLive
    }

    /// Queue a passive event without waiting for MainActor or persistence.
    /// A newer pending state for the same session replaces the older state in
    /// place; cross-session arrival order remains stable.
    func enqueuePassive(source: String, event: LocalAgentEvent) {
        var state = states[source, default: SourceState()]
        if let index = state.queue.lastIndex(where: {
            $0.isPassive && $0.event?.sessionId == event.sessionId
        }) {
            state.queue[index] = Entry(event: event, completion: nil)
            states[source] = state
            return
        }
        guard state.queue.count < maximumQueuedEventsPerSource else {
            IslandLogger.webhook.warning(
                "Dropped passive local Hook event at bounded delivery capacity"
            )
            return
        }
        state.queue.append(Entry(event: event, completion: nil))
        startDrainIfNeeded(source: source, state: state)
    }

    /// Insert an action barrier after every earlier event from this source and
    /// wait until its paired lifecycle snapshot has been delivered. When the
    /// bounded queue is full, an older passive entry yields to the actionable
    /// request; an all-action queue fails neutral instead of growing.
    func deliverBeforeAction(
        source: String,
        event: LocalAgentEvent?
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            var state = states[source, default: SourceState()]
            if state.queue.count >= maximumQueuedEventsPerSource {
                guard let passiveIndex = state.queue.firstIndex(where: \.isPassive) else {
                    continuation.resume(returning: false)
                    return
                }
                state.queue.remove(at: passiveIndex)
                IslandLogger.webhook.warning(
                    "Evicted passive local Hook event for bounded action delivery"
                )
            }
            state.queue.append(Entry(event: event, completion: continuation))
            startDrainIfNeeded(source: source, state: state)
        }
    }

    func queuedEventCount(source: String) -> Int {
        states[source]?.queue.count ?? 0
    }

    func queuedActionBarrierCount(source: String) -> Int {
        states[source]?.queue.lazy.filter { !$0.isPassive }.count ?? 0
    }

    private func startDrainIfNeeded(source: String, state initial: SourceState) {
        var state = initial
        guard !state.isDraining else {
            states[source] = state
            return
        }
        state.isDraining = true
        states[source] = state
        Task { await drain(source: source) }
    }

    private func drain(source: String) async {
        while let entry = nextEntry(source: source) {
            guard await isLive() else {
                entry.completion?.resume(returning: false)
                continue
            }
            if let event = entry.event {
                await onEvent(source, event)
            }
            entry.completion?.resume(returning: await isLive())
        }
    }

    private func nextEntry(source: String) -> Entry? {
        guard var state = states[source] else { return nil }
        guard !state.queue.isEmpty else {
            state.isDraining = false
            states[source] = state
            return nil
        }
        let entry = state.queue.removeFirst()
        states[source] = state
        return entry
    }
}

/// Localhost-only HTTP server that receives lifecycle events from local
/// agent CLIs and editors — one route per `LocalAgentDescriptor`.
///
/// Deliberately separate from `WebhookServer`: that one is exposed to the
/// public internet through the cloudflared tunnel for Manus, while this one
/// must never leave 127.0.0.1. The numeric bind is paired with Origin rejection,
/// a fixed custom Header that deliberately forces browser CORS preflight, and
/// a per-listener random credential stored outside Agent configuration. The
/// private file separates other macOS users; current-login processes remain
/// inside the explicit local-user trust boundary.
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
    private let retryPolicy: LocalHookServerRetryPolicy
    private let makeAuthorization: @Sendable () throws -> LocalHookAuthorization
    private let suppressFrameworkLogs: Bool

    private var agents: [LocalAgentDescriptor] = []
    private var onEvent: (@Sendable (String, LocalAgentEvent) async -> Void)?
    private var onActionRequest: (@Sendable (AgentActionRequest) async -> AgentActionResponse?)?
    private var onStatusChange: (@Sendable (LocalHookServiceStatus) -> Void)?
    private var serverTask: Task<Void, Never>?
    private var readinessTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    /// True while a serve loop (or its retry backoff) is in flight.
    private var isServing = false
    private var status: LocalHookServiceStatus = .stopped
    /// Lifecycle token: bumped on every start/stop/re-arm so callbacks from
    /// a cancelled serve loop can never mutate the state of its successor.
    private var epoch = 0

    public init(port: Int = LocalHooksInstaller.defaultPort) {
        self.port = port
        retryPolicy = .production
        makeAuthorization = { try LocalHookAuthorizationStore.rotate() }
        suppressFrameworkLogs = false
    }

    init(
        port: Int = LocalHooksInstaller.defaultPort,
        retryPolicy: LocalHookServerRetryPolicy,
        authorization: LocalHookAuthorization,
        suppressFrameworkLogs: Bool = false
    ) {
        self.port = port
        self.retryPolicy = retryPolicy
        makeAuthorization = { authorization }
        self.suppressFrameworkLogs = suppressFrameworkLogs
    }

    init(
        port: Int = LocalHooksInstaller.defaultPort,
        retryPolicy: LocalHookServerRetryPolicy,
        authorizationProvider: @escaping @Sendable () throws -> LocalHookAuthorization,
        suppressFrameworkLogs: Bool = false
    ) {
        self.port = port
        self.retryPolicy = retryPolicy
        makeAuthorization = authorizationProvider
        self.suppressFrameworkLogs = suppressFrameworkLogs
    }

    /// Start serving the given agents' endpoints. `onEvent` receives the
    /// agent's `source` plus the normalized event.
    public func start(
        agents: [LocalAgentDescriptor],
        onActionRequest: (@Sendable (AgentActionRequest) async -> AgentActionResponse?)? = nil,
        onStatusChange: (@Sendable (LocalHookServiceStatus) -> Void)? = nil,
        onEvent: @escaping @Sendable (String, LocalAgentEvent) async -> Void
    ) {
        epoch += 1
        serverTask?.cancel()
        readinessTask?.cancel()
        self.agents = agents
        self.onActionRequest = onActionRequest
        self.onStatusChange = onStatusChange
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

    /// User-initiated recovery. Unlike `ensureRunning`, this deliberately
    /// interrupts an in-flight retry backoff and starts a fresh bounded cycle.
    public func restart() {
        guard onEvent != nil else { return }
        IslandLogger.webhook.info("LocalHookServer manual restart requested")
        epoch += 1
        serverTask?.cancel()
        readinessTask?.cancel()
        serverTask = nil
        readinessTask = nil
        consecutiveFailures = 0
        isServing = false
        launchServeLoop(epoch: epoch)
    }

    public func statusSnapshot() -> LocalHookServiceStatus {
        status
    }

    public func stop() {
        epoch += 1
        serverTask?.cancel()
        readinessTask?.cancel()
        serverTask = nil
        readinessTask = nil
        agents = []
        onEvent = nil
        onActionRequest = nil
        isServing = false
        publishStatus(.stopped)
        onStatusChange = nil
        IslandLogger.webhook.info("LocalHookServer stopped")
    }

    // MARK: - Serve loop

    private func currentEpoch() -> Int { epoch }

    private func launchServeLoop(epoch: Int) {
        guard epoch == self.epoch, let onEvent else { return }
        let authorization: LocalHookAuthorization
        do {
            authorization = try makeAuthorization()
        } catch {
            isServing = false
            publishStatus(.unavailable)
            IslandLogger.webhook.error(
                "LocalHookServer authorization boundary unavailable"
            )
            return
        }
        let agents = self.agents
        let onActionRequest = self.onActionRequest
        let readinessToken = UUID().uuidString.lowercased()
        readinessTask?.cancel()
        isServing = true
        publishStatus(.starting)
        // Route closures re-check this before delivering: a superseded serve
        // loop may still be draining in-flight requests after cancellation
        // (cancel is non-awaiting), and those must not reach the handlers.
        let isLive: @Sendable () async -> Bool = { [weak self] in
            guard let self else { return false }
            return await self.currentEpoch() == epoch
        }
        serverTask = Task {
            do {
                try await Self.serve(
                    port: port,
                    agents: agents,
                    readinessToken: readinessToken,
                    authorization: authorization,
                    suppressFrameworkLogs: suppressFrameworkLogs,
                    onActionRequest: onActionRequest,
                    onEvent: onEvent,
                    isLive: isLive
                )
                // app.run() only returns on graceful shutdown.
                self.markStopped(epoch: epoch)
            } catch is CancellationError {
                self.markStopped(epoch: epoch)
            } catch {
                await self.handleServeFailure(error, epoch: epoch)
            }
        }
        readinessTask = Task {
            await probeReadiness(token: readinessToken, epoch: epoch)
        }
    }

    private func markStopped(epoch: Int) {
        guard epoch == self.epoch else { return }
        readinessTask?.cancel()
        readinessTask = nil
        isServing = false
        publishStatus(.unavailable)
    }

    private func handleServeFailure(_ error: Error, epoch: Int) async {
        guard epoch == self.epoch else { return }
        readinessTask?.cancel()
        readinessTask = nil
        consecutiveFailures += 1
        guard consecutiveFailures < retryPolicy.maxConsecutiveFailures else {
            isServing = false
            publishStatus(.unavailable)
            IslandLogger.webhook.error(
                "LocalHookServer gave up after \(self.consecutiveFailures) failed attempts; loopback port unavailable; will retry on next wake"
            )
            return
        }
        publishStatus(.retrying(
            attempt: consecutiveFailures,
            limit: retryPolicy.maxConsecutiveFailures
        ))
        let delay = retryPolicy.delayAfterFailure(consecutiveFailures)
        IslandLogger.webhook.error(
            "LocalHookServer serve loop failed — attempt \(self.consecutiveFailures)/\(self.retryPolicy.maxConsecutiveFailures), retrying after bounded backoff"
        )
        try? await Task.sleep(for: delay)
        guard epoch == self.epoch, !Task.isCancelled, onEvent != nil else {
            markStopped(epoch: epoch)
            return
        }
        launchServeLoop(epoch: epoch)
    }

    /// A successful TCP connection alone is insufficient: another process
    /// may own port 7824. The random per-epoch route proves that the response
    /// came from this exact Dev Island serve loop before Settings says Ready.
    private func probeReadiness(token: String, epoch: Int) async {
        for _ in 0..<50 {
            guard epoch == self.epoch, !Task.isCancelled else { return }
            if await Self.readinessEndpointResponds(port: port, token: token) {
                guard epoch == self.epoch, !Task.isCancelled else { return }
                publishStatus(.listening)
                return
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    private nonisolated static func readinessEndpointResponds(
        port: Int,
        token: String
    ) async -> Bool {
        await LoopbackHTTPReadinessProbe.responds(
            port: port,
            path: "/_dev-island/ready/\(token)",
            expectedResponse: Data(token.utf8)
        )
    }

    private func publishStatus(_ next: LocalHookServiceStatus) {
        guard status != next else { return }
        status = next
        onStatusChange?(next)
    }

    private static func serve(
        port: Int,
        agents: [LocalAgentDescriptor],
        readinessToken: String,
        authorization: LocalHookAuthorization,
        suppressFrameworkLogs: Bool,
        onActionRequest: (@Sendable (AgentActionRequest) async -> AgentActionResponse?)?,
        onEvent: @escaping @Sendable (String, LocalAgentEvent) async -> Void,
        isLive: @escaping @Sendable () async -> Bool
    ) async throws {
        let router = Router()
        let eventDelivery = LocalHookEventDelivery(
            onEvent: onEvent,
            isLive: isLive
        )

        router.get(RouterPath("/_dev-island/ready/\(readinessToken)")) { _, _ -> String in
            readinessToken
        }

        router.post(RouterPath(LocalHookListenerReadinessProbe.endpointPath)) { request, _ -> String in
            // This explicit CLI-only proof must not become a localhost
            // software oracle for web pages. A custom header forces browser
            // preflight and Origin-bearing requests are rejected regardless.
            let originName = HTTPField.Name("Origin")
            let challengeName = HTTPField.Name(
                LocalHookListenerReadinessProbe.challengeHeader
            )
            guard originName.flatMap({ request.headers[$0] }) == nil,
                  let challengeName,
                  let challenge = request.headers[challengeName],
                  LocalHookListenerReadinessProbe.isValid(challenge: challenge)
            else { return "{}" }
            return LocalHookListenerReadinessProbe.response(for: challenge)
        }

        for descriptor in agents {
            router.post(RouterPath(descriptor.endpointPath)) { request, _ -> String in
                // Browser-originated POSTs are never legitimate agent hooks.
                // The required non-simple header forces fetch/XHR through a
                // CORS preflight that this server never authorizes; rejecting
                // Origin as well protects clients that can attach the header.
                let originName = HTTPField.Name("Origin")
                let hookHeaderName = HTTPField.Name(LocalHooksInstaller.requestHeaderName)
                let authorizationHeaderName = HTTPField.Name(LocalHookAuthorization.headerName)
                guard originName.flatMap({ request.headers[$0] }) == nil,
                      let hookHeaderName,
                      request.headers[hookHeaderName] == LocalHooksInstaller.requestHeaderValue,
                      let authorizationHeaderName,
                      authorization.matches(request.headers[authorizationHeaderName])
                else {
                    IslandLogger.webhook.warning("Rejected untrusted local hook request")
                    return "{}"
                }
                guard let data = await Self.readBody(of: request), await isLive() else {
                    return "{}"
                }

                let decodedEvent = descriptor.decodeEvent(data).map {
                    $0.withJumpContext(
                        descriptor.usesTerminalFallback
                            ? Self.sessionJumpContext(from: request.headers)
                            : nil
                    )
                }
                let decodedActionRequest = descriptor.decodeActionRequest?(data)

                guard let actionRequest = decodedActionRequest,
                      let encodeActionResponse = descriptor.encodeActionResponse,
                      let onActionRequest else {
                    // Passive hooks have a two-second fail-open curl budget.
                    // Queueing is bounded and source-ordered, but the response
                    // never waits for MainActor/SQLite work. Only synchronous
                    // decision hooks wait at the ordering barrier below.
                    if let event = decodedEvent {
                        IslandLogger.webhook.info(
                            "\(descriptor.displayName) hook event received"
                        )
                        await eventDelivery.enqueuePassive(
                            source: descriptor.source,
                            event: event
                        )
                    }
                    return "{}"
                }
                guard actionRequest.source == descriptor.source,
                      decodedEvent?.sessionId == nil
                        || decodedEvent?.sessionId == actionRequest.sessionId else {
                    IslandLogger.webhook.warning(
                        "Rejected mismatched local action identity"
                    )
                    return "{}"
                }

                if decodedEvent != nil {
                    IslandLogger.webhook.info(
                        "\(descriptor.displayName) hook event received"
                    )
                }
                // A synchronous request may decode into both a lifecycle
                // Waiting event and an actionable approval/question. Its
                // barrier also waits for every earlier event from this source,
                // preventing both same-request and cross-request rollback.
                guard await eventDelivery.deliverBeforeAction(
                    source: descriptor.source,
                    event: decodedEvent
                ) else { return "{}" }

                guard await isLive() else { return "{}" }
                let response = await onActionRequest(actionRequest)
                guard await isLive() else { return "{}" }
                return encodeActionResponse(response)
            }
        }

        let frameworkLogger = suppressFrameworkLogs
            ? IslandLogger.silentFramework
            : nil
        let app = Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: port)),
            logger: frameworkLogger
        )
        let sources = agents.map(\.source).joined(separator: ", ")
        IslandLogger.webhook.info("LocalHookServer listening on 127.0.0.1:\(port) (\(sources))")
        try await app.run()
    }

    /// Read one bounded hook payload. Decoding happens per descriptor so the
    /// same bytes can drive both lifecycle state and a synchronous action.
    private static func readBody(of request: Request) async -> Data? {
        guard let buffer = try? await request.body.collect(upTo: 1_048_576) else { return nil }
        return Data(buffer.readableBytesView)
    }

    private static func sessionJumpContext(from headers: HTTPFields) -> SessionJumpContext? {
        SessionJumpContext(
            terminalBundleIdentifier: header("X-Dev-Island-Terminal-Bundle", from: headers),
            terminalProgram: header("X-Dev-Island-Terminal-Program", from: headers),
            tty: header("X-Dev-Island-TTY", from: headers),
            tmuxEnvironment: header("X-Dev-Island-Tmux", from: headers),
            tmuxPane: header("X-Dev-Island-Tmux-Pane", from: headers)
        )
    }

    private static func header(_ rawName: String, from headers: HTTPFields) -> String? {
        guard let name = HTTPField.Name(rawName) else { return nil }
        return headers[name]
    }
}
