import Foundation
import Hummingbird
import HTTPTypes
import ServiceLifecycle

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

    private struct DrainOperation {
        let identity: LocalHookDeliveryDrainIdentity
        let task: Task<Void, Never>
    }

    private struct Entry {
        let event: LocalAgentEvent?
        let completion: CheckedContinuation<Bool, Never>?

        var isPassive: Bool { completion == nil }
    }

    private struct SourceState {
        var queue: [Entry] = []
    }

    private let maximumQueuedEventsPerSource: Int
    private let ownerServerToken: UInt64?
    private let onEvent: @Sendable (String, LocalAgentEvent) async -> Void
    private let isLive: @Sendable () async -> Bool
    private let deliveryID = UUID()
    private var states: [String: SourceState] = [:]
    /// One current drain is allowed per source. A stop or generation replacement
    /// moves every current handle into `retiringDrainOperations` before
    /// cancellation, so cancellation-unaware delivery can never be forgotten.
    private var currentDrainOperations: [String: DrainOperation] = [:]
    private var retiringDrainOperations: [UInt64: Task<Void, Never>] = [:]
    private var nextDrainToken: UInt64 = 0
    private var isAcceptingEvents = true

    init(
        maximumQueuedEventsPerSource: Int = LocalHookEventDelivery.maximumQueuedEventsPerSource,
        ownerServerToken: UInt64? = nil,
        onEvent: @escaping @Sendable (String, LocalAgentEvent) async -> Void,
        isLive: @escaping @Sendable () async -> Bool
    ) {
        precondition(maximumQueuedEventsPerSource > 0)
        self.maximumQueuedEventsPerSource = maximumQueuedEventsPerSource
        self.ownerServerToken = ownerServerToken
        self.onEvent = onEvent
        self.isLive = isLive
    }

    /// Queue a passive event without waiting for MainActor or persistence.
    /// A newer pending state for the same session replaces the older state in
    /// place; cross-session arrival order remains stable.
    func enqueuePassive(source: String, event: LocalAgentEvent) {
        guard isAcceptingEvents else { return }
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
        states[source] = state
        startDrainIfNeeded(source: source)
    }

    /// Insert an action barrier after every earlier event from this source and
    /// wait until its paired lifecycle snapshot has been delivered. When the
    /// bounded queue is full, an older passive entry yields to the actionable
    /// request; an all-action queue fails neutral instead of growing.
    func deliverBeforeAction(
        source: String,
        event: LocalAgentEvent?
    ) async -> Bool {
        guard isAcceptingEvents else { return false }
        return await withCheckedContinuation { continuation in
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
            states[source] = state
            startDrainIfNeeded(source: source)
        }
    }

    /// Stop accepting work, fail every queued action barrier neutral, then join
    /// all current and superseded drains. The explicit exclusion is only used
    /// when a delivery callback itself initiates listener shutdown; awaiting
    /// that exact task would self-deadlock. The callback is allowed to finish
    /// unwinding after this internal stop returns, while a subsequent external
    /// lifecycle stop still joins the retained drain strictly.
    func stop() async {
        await stop(excluding: LocalHookDeliveryDrainContext.identity)
    }

    fileprivate func stop(
        excluding callerIdentity: LocalHookDeliveryDrainIdentity?
    ) async {
        isAcceptingEvents = false

        let queuedEntries = states.values.flatMap(\.queue)
        states = [:]
        for entry in queuedEntries {
            entry.completion?.resume(returning: false)
        }

        for operation in currentDrainOperations.values {
            operation.task.cancel()
            retiringDrainOperations[operation.identity.token] = operation.task
        }
        currentDrainOperations = [:]

        let callerToken = callerIdentity?.deliveryID == deliveryID
            ? callerIdentity?.token
            : nil
        let operations = retiringDrainOperations.sorted { $0.key < $1.key }
        for (_, task) in operations {
            task.cancel()
        }
        for (token, task) in operations where token != callerToken {
            await task.value
        }
    }

    func queuedEventCount(source: String) -> Int {
        states[source]?.queue.count ?? 0
    }

    func queuedActionBarrierCount(source: String) -> Int {
        states[source]?.queue.lazy.filter { !$0.isPassive }.count ?? 0
    }

    private func startDrainIfNeeded(source: String) {
        guard isAcceptingEvents,
              currentDrainOperations[source] == nil,
              states[source]?.queue.isEmpty == false else { return }

        nextDrainToken &+= 1
        let identity = LocalHookDeliveryDrainIdentity(
            deliveryID: deliveryID,
            token: nextDrainToken,
            ownerServerToken: ownerServerToken
        )
        let task = Task { [weak self] in
            guard let self else { return }
            await LocalHookDeliveryDrainContext.$identity.withValue(identity) {
                await self.drain(source: source)
                await self.drainOperationDidFinish(
                    source: source,
                    identity: identity
                )
            }
        }
        currentDrainOperations[source] = DrainOperation(
            identity: identity,
            task: task
        )
    }

    private func drain(source: String) async {
        while !Task.isCancelled, let entry = nextEntry(source: source) {
            guard await canDeliver() else {
                entry.completion?.resume(returning: false)
                continue
            }
            if let event = entry.event {
                await onEvent(source, event)
            }
            entry.completion?.resume(returning: await canDeliver())
        }
    }

    private func canDeliver() async -> Bool {
        guard isAcceptingEvents, !Task.isCancelled else { return false }
        let externallyLive = await isLive()
        return externallyLive && isAcceptingEvents && !Task.isCancelled
    }

    private func nextEntry(source: String) -> Entry? {
        guard var state = states[source] else { return nil }
        guard !state.queue.isEmpty else { return nil }
        let entry = state.queue.removeFirst()
        states[source] = state
        return entry
    }

    private func drainOperationDidFinish(
        source: String,
        identity: LocalHookDeliveryDrainIdentity
    ) {
        if currentDrainOperations[source]?.identity == identity {
            currentDrainOperations[source] = nil
            startDrainIfNeeded(source: source)
        } else {
            retiringDrainOperations[identity.token] = nil
        }
    }
}

private struct LocalHookDeliveryDrainIdentity: Hashable, Sendable {
    let deliveryID: UUID
    let token: UInt64
    let ownerServerToken: UInt64?
}

private enum LocalHookDeliveryDrainContext {
    @TaskLocal static var identity: LocalHookDeliveryDrainIdentity?
}

/// Synchronously records a shutdown request even when the Hummingbird service
/// group has not finished installing yet. Real listeners use graceful
/// quiescence so an in-flight action route can write its neutral response;
/// deterministic test overrides continue to use direct task cancellation.
private final class LocalHookServeShutdownControl: @unchecked Sendable {
    private let lock = NSLock()
    private var serviceGroup: ServiceGroup?
    private var isShutdownRequested = false
    private var didServiceGroupFinish = false
    /// Retained for the same lifetime as the owning server operation. This is
    /// lifecycle work, not an unowned fire-and-forget trigger.
    private var shutdownTask: Task<Void, Never>?

    func install(_ serviceGroup: ServiceGroup) {
        lock.lock()
        self.serviceGroup = serviceGroup
        armShutdownIfNeededLocked()
        lock.unlock()
    }

    /// Returns true when no live service group remains, so the owning
    /// operation may be in retry/backoff code and should also be cancelled.
    func requestShutdown() -> Bool {
        lock.lock()
        isShutdownRequested = true
        armShutdownIfNeededLocked()
        let shouldCancelOperation = didServiceGroupFinish
        lock.unlock()
        return shouldCancelOperation
    }

    /// Records that `ServiceGroup.run()` has returned. The result lets the
    /// serve path translate a raced bind failure into intentional shutdown
    /// instead of entering another retry cycle.
    func serviceGroupDidFinish() -> Bool {
        lock.lock()
        didServiceGroupFinish = true
        let wasShutdownRequested = isShutdownRequested
        lock.unlock()
        return wasShutdownRequested
    }

    private func armShutdownIfNeededLocked() {
        guard isShutdownRequested,
              shutdownTask == nil,
              let serviceGroup else { return }
        shutdownTask = Task {
            await serviceGroup.triggerGracefulShutdown()
        }
    }
}

struct LocalHookServerLifecycleOperationCounts: Equatable, Sendable {
    let currentServer: Int
    let currentReadiness: Int
    let currentEventDelivery: Int
    let retiringServers: Int
    let retiringReadiness: Int
    let retiringEventDeliveries: Int
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
    private struct LifecycleOperation {
        let token: UInt64
        let task: Task<Void, Never>
        let gracefulShutdownControl: LocalHookServeShutdownControl?

        func requestStop() {
            if let gracefulShutdownControl {
                if gracefulShutdownControl.requestShutdown() {
                    task.cancel()
                }
            } else {
                task.cancel()
            }
        }
    }

    private struct EventDeliveryLifecycle {
        let token: UInt64
        let delivery: LocalHookEventDelivery
    }

    public let port: Int
    private let retryPolicy: LocalHookServerRetryPolicy
    private let makeAuthorization: @Sendable () throws -> LocalHookAuthorization
    private let suppressFrameworkLogs: Bool
    /// Deterministic lifecycle seams used by strict-join tests. Production
    /// instances always execute the concrete Hummingbird/readiness paths.
    private let serveOperationOverride: (@Sendable () async throws -> Void)?
    private let readinessOperationOverride: (@Sendable () async -> Void)?

    private var agents: [LocalAgentDescriptor] = []
    private var onEvent: (@Sendable (String, LocalAgentEvent) async -> Void)?
    private var onActionRequest: (@Sendable (AgentActionRequest) async -> AgentActionResponse?)?
    private var onStatusChange: (@Sendable (LocalHookServiceStatus) -> Void)?
    private var serverOperation: LifecycleOperation?
    private var readinessOperation: LifecycleOperation?
    private var eventDelivery: EventDeliveryLifecycle?
    /// Superseded cancellation-unaware work remains owned until its task
    /// actually exits. Tokenized completion removes finished entries, so
    /// these dictionaries never retain historical completed operations.
    private var retiringServerOperations: [UInt64: LifecycleOperation] = [:]
    private var retiringReadinessOperations: [UInt64: Task<Void, Never>] = [:]
    private var retiringEventDeliveryOperations: [UInt64: Task<Void, Never>] = [:]
    private var nextOperationToken: UInt64 = 0
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
        serveOperationOverride = nil
        readinessOperationOverride = nil
    }

    init(
        port: Int = LocalHooksInstaller.defaultPort,
        retryPolicy: LocalHookServerRetryPolicy,
        authorization: LocalHookAuthorization,
        suppressFrameworkLogs: Bool = false,
        serveOperation: (@Sendable () async throws -> Void)? = nil,
        readinessOperation: (@Sendable () async -> Void)? = nil
    ) {
        self.port = port
        self.retryPolicy = retryPolicy
        makeAuthorization = { authorization }
        self.suppressFrameworkLogs = suppressFrameworkLogs
        serveOperationOverride = serveOperation
        readinessOperationOverride = readinessOperation
    }

    init(
        port: Int = LocalHooksInstaller.defaultPort,
        retryPolicy: LocalHookServerRetryPolicy,
        authorizationProvider: @escaping @Sendable () throws -> LocalHookAuthorization,
        suppressFrameworkLogs: Bool = false,
        serveOperation: (@Sendable () async throws -> Void)? = nil,
        readinessOperation: (@Sendable () async -> Void)? = nil
    ) {
        self.port = port
        self.retryPolicy = retryPolicy
        makeAuthorization = authorizationProvider
        self.suppressFrameworkLogs = suppressFrameworkLogs
        serveOperationOverride = serveOperation
        readinessOperationOverride = readinessOperation
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
        retireCurrentServerOperation()
        retireCurrentReadinessOperation()
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
        retireCurrentServerOperation()
        retireCurrentReadinessOperation()
        consecutiveFailures = 0
        isServing = false
        launchServeLoop(epoch: epoch)
    }

    public func statusSnapshot() -> LocalHookServiceStatus {
        status
    }

    func lifecycleOperationCounts() -> LocalHookServerLifecycleOperationCounts {
        LocalHookServerLifecycleOperationCounts(
            currentServer: serverOperation == nil ? 0 : 1,
            currentReadiness: readinessOperation == nil ? 0 : 1,
            currentEventDelivery: eventDelivery == nil ? 0 : 1,
            retiringServers: retiringServerOperations.count,
            retiringReadiness: retiringReadinessOperations.count,
            retiringEventDeliveries: retiringEventDeliveryOperations.count
        )
    }

    public func stop() async {
        let callerServerToken = LocalHookDeliveryDrainContext.identity?.ownerServerToken
        epoch += 1
        retireCurrentEventDelivery()
        retireCurrentServerOperation()
        retireCurrentReadinessOperation()
        let serverTasks = retiringServerOperations.sorted { $0.key < $1.key }
        let readinessTasks = Array(retiringReadinessOperations.values)
        let eventDeliveryTasks = retiringEventDeliveryOperations.sorted { $0.key < $1.key }
        for (_, operation) in serverTasks {
            operation.requestStop()
        }
        readinessTasks.forEach { $0.cancel() }
        agents = []
        onEvent = nil
        onActionRequest = nil
        isServing = false
        publishStatus(.stopped)
        onStatusChange = nil
        for task in readinessTasks {
            await task.value
        }
        // A synchronous action route waits for its delivery drain. If that
        // drain's callback initiates stop, awaiting the exact delivery/server
        // generation that owns the caller would form
        // route -> drain -> stop -> app.run -> route. Keep both operations in
        // the retiring sets and request graceful listener shutdown, but let
        // this one caller finish unwinding. The internal stop return is not a
        // no-more-callback-side-effects boundary. Any external or later stop
        // has no TaskLocal token and therefore joins both operations fully.
        for (token, task) in eventDeliveryTasks where token != callerServerToken {
            await task.value
        }
        for (token, operation) in serverTasks where token != callerServerToken {
            await operation.task.value
        }
        IslandLogger.webhook.info("LocalHookServer stopped")
    }

    // MARK: - Serve loop

    private func currentEpoch() -> Int { epoch }

    private func launchServeLoop(
        epoch: Int,
        replacingServerToken: UInt64? = nil
    ) {
        guard epoch == self.epoch, let onEvent else { return }
        if let replacingServerToken {
            guard serverOperation?.token == replacingServerToken else { return }
            retireCurrentEventDelivery(ifMatching: replacingServerToken)
            retireCurrentServerOperation(cancel: false)
        } else {
            retireCurrentEventDelivery()
            retireCurrentServerOperation()
        }

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
        retireCurrentReadinessOperation()
        isServing = true
        publishStatus(.starting)
        // Route closures re-check this before delivering: a superseded serve
        // loop may still be draining in-flight requests after cancellation
        // (cancel is non-awaiting), and those must not reach the handlers.
        let isLive: @Sendable () async -> Bool = { [weak self] in
            guard let self else { return false }
            return await self.currentEpoch() == epoch
        }

        let serveOperationOverride = self.serveOperationOverride
        let serverToken = takeOperationToken()
        let gracefulShutdownControl = serveOperationOverride == nil
            ? LocalHookServeShutdownControl()
            : nil
        let eventDelivery = LocalHookEventDelivery(
            ownerServerToken: serverToken,
            onEvent: onEvent,
            isLive: isLive
        )
        self.eventDelivery = EventDeliveryLifecycle(
            token: serverToken,
            delivery: eventDelivery
        )
        let serverTask = Task { [weak self] in
            guard let self else { return }
            do {
                if let serveOperationOverride {
                    try await serveOperationOverride()
                } else {
                    try await Self.serve(
                        port: port,
                        agents: agents,
                        readinessToken: readinessToken,
                        authorization: authorization,
                        suppressFrameworkLogs: suppressFrameworkLogs,
                        onActionRequest: onActionRequest,
                        eventDelivery: eventDelivery,
                        isLive: isLive,
                        gracefulShutdownControl: gracefulShutdownControl!
                    )
                }
                // app.run() only returns on graceful shutdown.
                await self.markStopped(epoch: epoch, serverToken: serverToken)
            } catch is CancellationError {
                await self.markStopped(epoch: epoch, serverToken: serverToken)
            } catch {
                await self.handleServeFailure(
                    error,
                    epoch: epoch,
                    serverToken: serverToken
                )
            }
            await self.serverOperationDidFinish(token: serverToken)
        }
        serverOperation = LifecycleOperation(
            token: serverToken,
            task: serverTask,
            gracefulShutdownControl: gracefulShutdownControl
        )

        let readinessOperationOverride = self.readinessOperationOverride
        let readinessOperationToken = takeOperationToken()
        let readinessTask = Task { [weak self] in
            guard let self else { return }
            if let readinessOperationOverride {
                await readinessOperationOverride()
            } else {
                await self.probeReadiness(
                    token: readinessToken,
                    epoch: epoch,
                    operationToken: readinessOperationToken
                )
            }
            await self.readinessOperationDidFinish(token: readinessOperationToken)
        }
        readinessOperation = LifecycleOperation(
            token: readinessOperationToken,
            task: readinessTask,
            gracefulShutdownControl: nil
        )
    }

    private func markStopped(epoch: Int, serverToken: UInt64) {
        guard epoch == self.epoch,
              serverOperation?.token == serverToken else { return }
        retireCurrentEventDelivery(ifMatching: serverToken)
        retireCurrentReadinessOperation()
        isServing = false
        publishStatus(.unavailable)
    }

    private func handleServeFailure(
        _ error: Error,
        epoch: Int,
        serverToken: UInt64
    ) async {
        guard epoch == self.epoch,
              serverOperation?.token == serverToken else { return }
        retireCurrentReadinessOperation()
        consecutiveFailures += 1
        guard consecutiveFailures < retryPolicy.maxConsecutiveFailures else {
            retireCurrentEventDelivery(ifMatching: serverToken)
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
        guard epoch == self.epoch,
              serverOperation?.token == serverToken,
              !Task.isCancelled,
              onEvent != nil else {
            markStopped(epoch: epoch, serverToken: serverToken)
            return
        }
        launchServeLoop(epoch: epoch, replacingServerToken: serverToken)
    }

    /// A successful TCP connection alone is insufficient: another process
    /// may own port 7824. The random per-epoch route proves that the response
    /// came from this exact Dev Island serve loop before Settings says Ready.
    private func probeReadiness(
        token: String,
        epoch: Int,
        operationToken: UInt64
    ) async {
        for _ in 0..<50 {
            guard isCurrentReadinessOperation(
                token: operationToken,
                epoch: epoch
            ) else { return }
            if await Self.readinessEndpointResponds(port: port, token: token) {
                guard isCurrentReadinessOperation(
                    token: operationToken,
                    epoch: epoch
                ) else { return }
                publishStatus(.listening)
                return
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    private func takeOperationToken() -> UInt64 {
        nextOperationToken &+= 1
        return nextOperationToken
    }

    private func retireCurrentServerOperation(cancel: Bool = true) {
        guard let operation = serverOperation else { return }
        if cancel {
            operation.requestStop()
        }
        retiringServerOperations[operation.token] = operation
        serverOperation = nil
    }

    private func retireCurrentReadinessOperation(cancel: Bool = true) {
        guard let operation = readinessOperation else { return }
        if cancel {
            operation.task.cancel()
        }
        retiringReadinessOperations[operation.token] = operation.task
        readinessOperation = nil
    }

    private func serverOperationDidFinish(token: UInt64) {
        retireCurrentEventDelivery(ifMatching: token)
        if serverOperation?.token == token {
            serverOperation = nil
        } else {
            retiringServerOperations.removeValue(forKey: token)
        }
    }

    private func readinessOperationDidFinish(token: UInt64) {
        if readinessOperation?.token == token {
            readinessOperation = nil
        } else {
            retiringReadinessOperations.removeValue(forKey: token)
        }
    }

    private func retireCurrentEventDelivery(ifMatching token: UInt64? = nil) {
        guard let current = eventDelivery,
              token == nil || current.token == token else { return }
        eventDelivery = nil
        let task = Task { [weak self] in
            // This retained operation always joins the full delivery. A stop
            // invoked by one of its own drains skips awaiting this exact server
            // token at the LocalHookServer layer, leaving the operation visible
            // for a subsequent external strict join.
            await current.delivery.stop(excluding: nil)
            await self?.eventDeliveryOperationDidFinish(token: current.token)
        }
        retiringEventDeliveryOperations[current.token] = task
    }

    private func eventDeliveryOperationDidFinish(token: UInt64) {
        retiringEventDeliveryOperations[token] = nil
    }

    private func isCurrentReadinessOperation(
        token: UInt64,
        epoch: Int
    ) -> Bool {
        epoch == self.epoch
            && readinessOperation?.token == token
            && !Task.isCancelled
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
        eventDelivery: LocalHookEventDelivery,
        isLive: @escaping @Sendable () async -> Bool,
        gracefulShutdownControl: LocalHookServeShutdownControl
    ) async throws {
        let router = Router()

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
        // Keep a separately controllable service group around `Application`.
        // Task cancellation closes active HTTP channels immediately, which can
        // tear down an action response when its own callback calls stop(). A
        // graceful shutdown first quiesces the listener, lets that request
        // write its neutral response, and then releases the port.
        let serviceGroup = ServiceGroup(
            services: [app],
            logger: app.logger
        )
        gracefulShutdownControl.install(serviceGroup)
        do {
            try await serviceGroup.run()
        } catch {
            if gracefulShutdownControl.serviceGroupDidFinish() {
                throw CancellationError()
            }
            throw error
        }
        _ = gracefulShutdownControl.serviceGroupDidFinish()
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
