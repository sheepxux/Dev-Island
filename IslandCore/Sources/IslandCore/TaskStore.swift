import Foundation
import Observation
import AppKit

/// Low-cardinality state for the user-opened local history surface. Error
/// details stay in private logs so Settings never renders database paths or
/// raw SQLite messages.
public enum StoredTaskHistoryStatus: Equatable, Sendable {
    case loading
    case available
    case unavailable
}

/// A successful polling request proves the API is reachable, but it cannot
/// prove that public webhook registration exists. Keep the two facts separate
/// so polling never upgrades a failed realtime lifecycle to `connected`.
enum ManusConnectionStatusPolicy {
    static func restoredStatus(pollingOnlyReason: String?) -> ConnectionStatus {
        if let pollingOnlyReason {
            return .degraded(reason: pollingOnlyReason)
        }
        return .connected
    }
}

/// A failed remote cleanup is recoverable only while the credential and the
/// manager that owns the persisted webhook ID are retained for another
/// explicit Disconnect attempt. The existing degraded state carries that
/// distinction without adding a second account-state model.
public enum ManusCredentialRemovalPolicy {
    public static let cleanupPendingReason =
        "Remote callback cleanup pending; retry disconnect"
}

/// Bounded outcome reported to the app-termination coordinator. Detailed
/// transport failures remain private; the caller only needs to know whether
/// a persisted remote callback still requires a later cleanup retry.
public enum TaskStoreShutdownResult: Equatable, Sendable {
    case completed
    case cleanupPending
}

/// Internal dependency boundary for deterministic Manus account-lifecycle
/// tests. Shipping construction always uses the live API client and the
/// device-only Keychain store.
struct TaskStoreManusDependencies: Sendable {
    let makeClient: @Sendable (String) -> any ManusServiceClientProtocol
    let saveAPIKey: @Sendable (String) throws -> Void
    let loadAPIKey: @Sendable () throws -> String?
    let deleteAPIKey: @Sendable () throws -> Void
    /// Test-only launch boundary for the interval after a Disconnect operation
    /// is registered but before its cleanup body begins.
    let awaitCredentialRemovalPermission: @Sendable () async -> Void
    /// Test-only suspension boundary for proving that immediate Quit owns an
    /// in-flight cold bootstrap. Shipping construction uses the no-op default.
    let awaitBootstrapPermission: @Sendable () async -> Void
    /// `nil` keeps inert tests away from the shipping preferences domain.
    /// Live construction shares the same ledger with every TunnelManager.
    let webhookPreferencesSuiteName: String?

    init(
        makeClient: @escaping @Sendable (String) -> any ManusServiceClientProtocol,
        saveAPIKey: @escaping @Sendable (String) throws -> Void,
        loadAPIKey: @escaping @Sendable () throws -> String?,
        deleteAPIKey: @escaping @Sendable () throws -> Void,
        awaitCredentialRemovalPermission: @escaping @Sendable () async -> Void = {},
        awaitBootstrapPermission: @escaping @Sendable () async -> Void = {},
        webhookPreferencesSuiteName: String? = nil
    ) {
        self.makeClient = makeClient
        self.saveAPIKey = saveAPIKey
        self.loadAPIKey = loadAPIKey
        self.deleteAPIKey = deleteAPIKey
        self.awaitCredentialRemovalPermission = awaitCredentialRemovalPermission
        self.awaitBootstrapPermission = awaitBootstrapPermission
        self.webhookPreferencesSuiteName = webhookPreferencesSuiteName
    }

    static let live = TaskStoreManusDependencies(
        makeClient: { ManusAPIClient(apiKey: $0) },
        saveAPIKey: { try KeychainStore.save($0) },
        loadAPIKey: { try KeychainStore.load() },
        deleteAPIKey: { try KeychainStore.delete() },
        webhookPreferencesSuiteName: "app.devisland.Island"
    )
}

@MainActor
@Observable
public final class TaskStore {
    /// A broken or hostile local Hook must not retain unbounded synchronous
    /// continuations or flood the island. Overflow fails neutral so the Agent
    /// immediately falls back to its native prompt.
    static let maximumPendingActionRequests = 32
    static let maximumPendingActionRequestsPerSession = 4

    public static let shared: TaskStore = {
        #if DEV_ISLAND_PERFORMANCE_QA
        let store = TaskStore(bootstrap: false)
        store.tasks = PerformanceFixture.makeTasks()
        store.connectionStatus = .connected
        store.apiKeyStatus = .notConfigured
        if let request = PerformanceFixture.makeActionRequest() {
            Task { @MainActor [weak store] in
                guard let store else { return }
                _ = await store.awaitActionResponse(for: request)
            }
        }
        return store
        #else
        if HermeticAppLaunchMode.isEnabledForCurrentProcess {
            // The repository-owned Production launch smoke renders the real
            // shipping surfaces from a frozen App snapshot, but must not read
            // Keychain/SQLite or create a listener/authorization file. The
            // exact argument + environment pair is validated centrally and
            // grants no capability; it only selects this inert store.
            return TaskStore(bootstrap: false)
        }
        return TaskStore()
        #endif
    }()

    // MARK: - Public state (observed by C's SwiftUI views)

    public private(set) var tasks: [AgentTask] = []
    /// User decisions currently blocking a local agent. The array preserves
    /// arrival order so the island can present a stable attention queue.
    public private(set) var pendingActionRequests: [AgentActionRequest] = []
    public private(set) var connectionStatus: ConnectionStatus = .disconnected
    public private(set) var apiKeyStatus: APIKeyStatus = .notConfigured
    /// Read-only persisted snapshots. These records are deliberately separate
    /// from `tasks`: reopening history can never create notifications, reorder
    /// the island, or resurrect a stale Waiting state.
    public private(set) var storedTaskHistory: [AgentTask] = []
    public private(set) var storedTaskHistoryTotalCount = 0
    public private(set) var storedTaskHistoryStatus: StoredTaskHistoryStatus = .loading
    /// Health of the local-only HTTP listener shared by every CLI connector.
    /// This is separate from `connectionStatus`, which describes Manus.
    public private(set) var localHookServiceStatus: LocalHookServiceStatus = .stopped

    /// Task status-transition callback (contract v1.4.0, J1). B side assigns
    /// once at app startup and maps transitions to notifications.
    /// Fires on the main actor after `tasks` is already updated; one call per
    /// changed task; newly appeared tasks fire with `oldStatus == nil`;
    /// removals don't fire. Debug mutators fire too (Debug Sandbox testing).
    public var onTaskTransition: ((TaskTransition) -> Void)?

    // MARK: - Private internals

    private var connectors: [any AgentConnector] = []
    private var tunnelManager: (any ManusTunnelLifecycleProtocol)?
    private var pollingFallback: PollingFallback?
    private var sqliteStore: SQLiteStore?
    private var pollingOnlyReason: String?
    /// Invalidates delayed tunnel callbacks from a prior Manus configuration.
    /// Main-actor isolation makes this a cheap lifecycle token rather than a
    /// second synchronization primitive.
    private var manusServiceGeneration: UInt64 = 0
    /// Orders user-owned configure/disconnect operations across their network
    /// suspension points. The most recent operation is the only one allowed
    /// to persist a key or publish account state.
    private var manusConfigurationGeneration: UInt64 = 0
    /// Concurrent Disconnect requests share the complete removal transaction.
    /// Without this barrier, a second request could observe a detached manager
    /// and erase the credential while the first deletion is unresolved.
    private struct ManusCredentialRemovalOperation {
        let id: UUID
        let task: Task<Void, Error>
    }
    private var manusCredentialRemovalOperation: ManusCredentialRemovalOperation?
    /// App termination is a terminal, single-flight transaction. Retaining
    /// the completed task makes every later caller observe the exact same
    /// result without stopping a resource twice.
    private struct ShutdownOperation {
        let task: Task<TaskStoreShutdownResult, Never>
    }
    private var shutdownOperation: ShutdownOperation?
    /// Set before the first cleanup suspension so an already-running
    /// Disconnect can preserve its original tunnel failure for the shutdown
    /// barrier instead of converting it to an obsolete-generation cancel.
    private var shutdownRequested = false
    private let manusDependencies: TaskStoreManusDependencies
    /// The only boundary allowed to hand a validated destination to Launch
    /// Services. Injectable only through inert DEBUG fixtures.
    private let openDestination: (URL) -> Bool
    /// Actor hop used by manual local-listener recovery. Injectable only by an
    /// inert lifecycle fixture so shutdown ordering can be proven without
    /// binding a real port.
    private let restartLocalHookServer: @Sendable (LocalHookServer) async -> Void

    // Local agent pipeline (Claude Code, Codex, Cursor) — independent of the
    // Manus API key and of the tunnel/polling lifecycle: it runs for the
    // app's lifetime.
    private var localHookServer: LocalHookServer?
    /// Both cold-bootstrap ownership and the actor hop that arms the local
    /// listener are retained so Quit can prove neither can outlive its barrier.
    private var bootstrapTask: Task<Void, Never>?
    private var localHookStartTask: Task<Void, Never>?
    private var localConnectors: [String: LocalAgentConnector] = [:]
    private var actionContinuations: [
        UUID: CheckedContinuation<AgentActionResponse?, Never>
    ] = [:]
    private var actionTimeoutTasks: [UUID: Task<Void, Never>] = [:]

    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    /// A wake must never overtake the suspend launched by the preceding sleep
    /// notification. The task is retained until exactly one current wake has
    /// observed its completion; duplicate wakes remain idempotent.
    private struct ManusSleepSuspension {
        let id: UUID
        let task: Task<Void, Never>
    }
    private var manusSleepSuspension: ManusSleepSuspension?
    /// Supersedes wake recovery when a newer sleep/shutdown arrives while an
    /// async tunnel or polling operation is still in flight.
    private var systemPowerGeneration: UInt64 = 0

    // MARK: - Init

    /// `bootstrap: false` builds an inert store (previews / unit tests) that
    /// never touches SQLite, Keychain, or the local hook server.
    private init(
        bootstrap: Bool = true,
        manusDependencies: TaskStoreManusDependencies = .live,
        openDestination: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        restartLocalHookServer: @escaping @Sendable (LocalHookServer) async -> Void = {
            $0.restart()
        }
    ) {
        self.manusDependencies = manusDependencies
        self.openDestination = openDestination
        self.restartLocalHookServer = restartLocalHookServer
        if bootstrap {
            localHookServiceStatus = .starting
            bootstrapTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.bootstrap()
            }
        }
    }

    #if DEBUG
    /// Inert state container for SwiftUI previews and visual snapshot tests.
    /// It never opens SQLite, Keychain, ports, tunnels, or provider clients.
    public static func presentationFixture(
        tasks: [AgentTask] = [],
        storedTaskHistory: [AgentTask] = [],
        storedTaskHistoryStatus: StoredTaskHistoryStatus = .available
    ) -> TaskStore {
        let store = TaskStore(bootstrap: false)
        store.tasks = tasks
        store.storedTaskHistory = storedTaskHistory
        store.storedTaskHistoryTotalCount = storedTaskHistory.count
        store.storedTaskHistoryStatus = storedTaskHistoryStatus
        store.localHookServiceStatus = .listening
        return store
    }

    /// Inert store with injected Manus boundaries for account-lifecycle tests.
    /// It never opens SQLite, Keychain, local ports, or real network clients.
    static func manusLifecycleFixture(
        dependencies: TaskStoreManusDependencies,
        tasks: [AgentTask] = []
    ) -> TaskStore {
        let store = TaskStore(
            bootstrap: false,
            manusDependencies: dependencies
        )
        store.tasks = tasks
        return store
    }

    /// Cold-start fixture whose injected bootstrap boundary prevents real
    /// SQLite, Keychain, listener, and network work until a test releases it.
    static func bootstrapLifecycleFixture(
        dependencies: TaskStoreManusDependencies
    ) -> TaskStore {
        TaskStore(bootstrap: true, manusDependencies: dependencies)
    }

    /// Inert listener-retry fixture. The injected operation replaces the
    /// actual actor restart so tests never bind a port.
    static func localHookLifecycleFixture(
        precedingLifecycle: Task<Void, Never>? = nil,
        restart: @escaping @Sendable (LocalHookServer) async -> Void
    ) -> TaskStore {
        let store = TaskStore(
            bootstrap: false,
            restartLocalHookServer: restart
        )
        store.localHookServer = LocalHookServer(port: 0)
        store.localHookStartTask = precedingLifecycle
        store.localHookServiceStatus = .listening
        return store
    }

    /// Inert power-lifecycle fixture. It owns no listener, storage, Keychain,
    /// API client, or network resource; the injected tunnel is a test actor.
    static func sleepWakeFixture(
        tunnel: any ManusTunnelLifecycleProtocol,
        dependencies: TaskStoreManusDependencies = .live,
        tasks: [AgentTask] = [],
        apiKeyStatus: APIKeyStatus = .notConfigured
    ) -> TaskStore {
        let store = TaskStore(
            bootstrap: false,
            manusDependencies: dependencies
        )
        store.tunnelManager = tunnel
        store.tasks = tasks
        store.connectionStatus = .connected
        store.apiKeyStatus = apiKeyStatus
        return store
    }

    /// Deterministic synchronization point for lifecycle tests. Becoming true
    /// means the complete synchronous shutdown prefix has already run and the
    /// shared async cleanup operation has been installed.
    var shutdownStartedForTesting: Bool {
        shutdownOperation != nil
    }

    var ownsRuntimeResourcesForTesting: Bool {
        localHookServer != nil ||
            tunnelManager != nil ||
            pollingFallback != nil ||
            sleepObserver != nil ||
            wakeObserver != nil ||
            !localConnectors.isEmpty
    }
    #endif

    // MARK: - Task mutation funnel

    /// Every `tasks` write goes through here so status transitions are
    /// detected exactly once, in one place (contract v1.4.0).
    private func setTasks(_ newTasks: [AgentTask]) {
        let transitions = TaskTransition.diff(old: tasks, new: newTasks)
        tasks = newTasks
        guard let onTaskTransition else { return }
        for transition in transitions {
            onTaskTransition(transition)
        }
    }

    // MARK: - Public API

    /// Validate key, persist to Keychain, then start all services.
    public func configureAPIKey(_ key: String) async throws {
        guard !shutdownRequested else { throw CancellationError() }
        // A Disconnect already owns the old credential until its provider
        // cleanup settles. Joining it before creating a new configuration
        // generation prevents a candidate key from overwriting the only key
        // that can still remove an old remote callback.
        if let removal = manusCredentialRemovalOperation {
            try await awaitManusCredentialRemoval(removal)
            guard !shutdownRequested else { throw CancellationError() }
        }

        manusConfigurationGeneration &+= 1
        let configurationGeneration = manusConfigurationGeneration
        let previousKeyStatus = apiKeyStatus
        let client = manusDependencies.makeClient(key)

        // Validate by fetching tasks
        do {
            _ = try await client.listTasks()
        } catch ManusError.unauthorized {
            guard configurationGeneration == manusConfigurationGeneration else {
                throw CancellationError()
            }
            apiKeyStatus = .invalid
            throw ManusError.unauthorized
        } catch ManusError.invalidURL {
            guard configurationGeneration == manusConfigurationGeneration else {
                throw CancellationError()
            }
            apiKeyStatus = .invalid
            throw ManusError.invalidURL
        } catch {
            guard configurationGeneration == manusConfigurationGeneration else {
                throw CancellationError()
            }
            throw error
        }

        guard configurationGeneration == manusConfigurationGeneration else {
            throw CancellationError()
        }

        // Replacing a configured key has the same delete-before-release
        // requirement as Disconnect. The old manager retains its credential in
        // memory and must confirm every persisted webhook deletion first.
        if let existingTunnel = tunnelManager {
            do {
                try await existingTunnel.stop()
            } catch {
                guard configurationGeneration == manusConfigurationGeneration else {
                    throw CancellationError()
                }
                pollingOnlyReason = ManusCredentialRemovalPolicy.cleanupPendingReason
                apiKeyStatus = previousKeyStatus
                connectionStatus = .degraded(
                    reason: ManusCredentialRemovalPolicy.cleanupPendingReason
                )
                IslandLogger.store.error(
                    "Remote callback cleanup failed — existing credential retained"
                )
                throw error
            }
        }
        guard configurationGeneration == manusConfigurationGeneration else {
            throw CancellationError()
        }

        // The old callback is now confirmed deleted. Retire every service that
        // belonged to the old credential before replacing it so a persistence
        // failure cannot leave a stopped manager, live poller, or stale cloud
        // snapshot represented as connected.
        let retiredServices = detachManusServices()
        setTasks(tasks.filter { $0.source != "manus" })
        connectionStatus = .disconnected
        // Publish the detached state before this suspension. Otherwise an
        // obsolete Configure could resume after a newer one and erase the
        // newer credential's snapshots/status before noticing its generation
        // had been superseded.
        await retiredServices.poller?.stop()

        guard configurationGeneration == manusConfigurationGeneration else {
            throw CancellationError()
        }

        // Persist
        do {
            try manusDependencies.saveAPIKey(key)
        } catch {
            // Read back the source of truth: an injected backend may fail
            // before or after changing its stored value. Services stay
            // detached, so Configure or Disconnect can recover deterministically.
            do {
                let persistedKey = try manusDependencies.loadAPIKey()
                apiKeyStatus = persistedKey == nil ? .notConfigured : .valid
            } catch {
                apiKeyStatus = previousKeyStatus
            }
            connectionStatus = .disconnected
            IslandLogger.store.error(
                "API key persistence failed after previous services were retired"
            )
            throw error
        }
        apiKeyStatus = .valid
        IslandLogger.store.info("Manus API key configured and validated")
        try await startServices(client: client)

        guard configurationGeneration == manusConfigurationGeneration else {
            throw CancellationError()
        }
        if apiKeyStatus == .invalid {
            throw ManusError.unauthorized
        }
    }

    public func clearAPIKey() async throws {
        guard !shutdownRequested else { throw CancellationError() }
        if let removal = manusCredentialRemovalOperation {
            try await awaitManusCredentialRemoval(removal)
            return
        }

        let id = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.manusDependencies.awaitCredentialRemovalPermission()
            guard !self.shutdownRequested else { throw CancellationError() }
            try await self.performClearAPIKey()
        }
        let removal = ManusCredentialRemovalOperation(id: id, task: task)
        manusCredentialRemovalOperation = removal
        try await awaitManusCredentialRemoval(removal)
    }

    private func awaitManusCredentialRemoval(
        _ removal: ManusCredentialRemovalOperation
    ) async throws {
        do {
            try await removal.task.value
            clearManusCredentialRemovalOperation(ifMatching: removal.id)
        } catch {
            clearManusCredentialRemovalOperation(ifMatching: removal.id)
            throw error
        }
    }

    private func performClearAPIKey() async throws {
        guard !shutdownRequested else { throw CancellationError() }
        manusConfigurationGeneration &+= 1
        let configurationGeneration = manusConfigurationGeneration
        let previousKeyStatus = apiKeyStatus

        // Detach callbacks first, then stop polling and delete the remote
        // callback while its credential is still available.
        let services = detachManusServices()
        // The provider transport is detached even if its remote callback
        // still needs cleanup. Remove only cloud-owned snapshots now; local
        // agent sessions remain live and must never inherit Manus lifecycle.
        setTasks(tasks.filter { $0.source != "manus" })
        connectionStatus = .disconnected

        do {
            await services.poller?.stop()
            try await services.tunnel?.stop()
        } catch {
            // Shutdown has already detached every resource and deliberately
            // invalidated this Disconnect generation. Preserve a real tunnel
            // cleanup failure so the shared shutdown operation can report
            // `cleanupPending`; the credential and persisted webhook ledger
            // remain untouched for recovery on the next launch.
            if shutdownRequested {
                throw error
            }
            guard configurationGeneration == manusConfigurationGeneration else {
                throw CancellationError()
            }
            if tunnelManager == nil {
                tunnelManager = services.tunnel
            }
            apiKeyStatus = previousKeyStatus
            connectionStatus = .degraded(
                reason: ManusCredentialRemovalPolicy.cleanupPendingReason
            )
            IslandLogger.store.error(
                "Remote callback cleanup failed — credential retained for retry"
            )
            throw error
        }

        // A newer Configure owns the Keychain now. Never let an older,
        // suspended Disconnect delete the newly validated credential.
        guard configurationGeneration == manusConfigurationGeneration else {
            throw CancellationError()
        }

        let deletionError: Error?
        do {
            try manusDependencies.deleteAPIKey()
            deletionError = nil
        } catch {
            deletionError = error
        }
        connectionStatus = .disconnected

        if let deletionError {
            // Network ownership is already detached, but the Keychain item
            // may remain. Keep the prior configured state visible so the UI
            // never claims the credential was removed and can offer Retry.
            apiKeyStatus = previousKeyStatus
            IslandLogger.store.error("API key removal failed after Manus disconnect")
            throw deletionError
        }

        apiKeyStatus = .notConfigured
        IslandLogger.store.info("API key cleared")
    }

    private func clearManusCredentialRemovalOperation(ifMatching id: UUID) {
        guard manusCredentialRemovalOperation?.id == id else { return }
        manusCredentialRemovalOperation = nil
    }

    /// Resolve a local-agent request from the island. Repeated clicks and
    /// decisions that arrive after timeout are harmless and return `false`.
    @discardableResult
    public func respond(
        to requestID: UUID,
        decision: AgentActionDecision
    ) -> Bool {
        guard let request = pendingActionRequests.first(where: { $0.id == requestID }) else {
            return false
        }
        let response: AgentActionResponse
        switch request.kind {
        case .permission:
            response = .permission(decision)
        case .planReview:
            guard let review = request.planReview else { return false }
            response = .planReview(decision, review)
        case .question:
            return false
        }
        return finishActionRequest(
            requestID,
            response: response,
            restoreSession: true
        )
    }

    /// Answer a structured question request. The store revalidates and
    /// canonicalizes selections against the queued request so a stale or
    /// malformed UI submission can never be sent to the agent.
    @discardableResult
    public func respond(
        to requestID: UUID,
        answers: [AgentQuestionAnswer]
    ) -> Bool {
        guard let request = pendingActionRequests.first(where: { $0.id == requestID }),
              request.kind == .question,
              let submission = validatedSubmission(for: request, answers: answers) else {
            return false
        }
        return finishActionRequest(
            requestID,
            response: .question(submission),
            restoreSession: true
        )
    }

    /// Return control immediately to the vendor's native prompt. This is the
    /// explicit escape hatch for question types Dev Island cannot or should
    /// not answer; the session remains waiting until the vendor reports a
    /// subsequent lifecycle event.
    @discardableResult
    public func deferActionRequestToAgent(_ requestID: UUID) -> Bool {
        finishActionRequest(requestID, response: nil, restoreSession: false)
    }

    /// Graceful app shutdown. The synchronous prefix detaches every ingress
    /// path and resolves in-flight hooks before the first suspension. The
    /// retained task then joins older account/power transactions and every
    /// owned service stop, so AppKit can hold termination until cleanup has a
    /// definitive bounded result.
    public func shutdown() async -> TaskStoreShutdownResult {
        if let shutdownOperation {
            return await shutdownOperation.task.value
        }

        shutdownRequested = true
        cancelAllActionRequests()
        manusConfigurationGeneration &+= 1
        systemPowerGeneration &+= 1
        let credentialRemoval = manusCredentialRemovalOperation
        let sleepSuspension = manusSleepSuspension
        manusSleepSuspension = nil
        let manusServices = detachManusServices()

        let server = localHookServer
        let serverStart = localHookStartTask
        let bootstrap = bootstrapTask
        localHookServer = nil
        localHookStartTask = nil
        bootstrapTask = nil
        localConnectors = [:]
        localHookServiceStatus = .stopped
        bootstrap?.cancel()

        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }

        let task = Task<TaskStoreShutdownResult, Never> {
            var cleanupPending = false

            // A Disconnect that detached the manager before Quit still owns
            // the only in-memory cleanup transaction. Join it before stopping
            // resources captured directly by shutdown. Cancellation here is
            // the expected consequence of the generation advanced above; a
            // concrete error means remote callback cleanup did not complete.
            if let credentialRemoval {
                do {
                    try await credentialRemoval.task.value
                } catch is CancellationError {
                    // Tunnel cleanup completed, but shutdown prevented the
                    // obsolete Disconnect from deleting the credential.
                } catch {
                    cleanupPending = true
                }
            }

            // A tunnel must never be stopped while its pre-sleep suspension
            // is still mutating the same process/session state.
            await sleepSuspension?.task.value
            await manusServices.poller?.stop()
            do {
                try await manusServices.tunnel?.stop()
            } catch {
                cleanupPending = true
            }
            // If the actor hop that starts the local listener had not run yet,
            // stopping first would let it bind after the termination barrier.
            // Let that hop settle, then stop the concrete server it armed.
            await serverStart?.value
            await server?.stop()
            // Bootstrap may be suspended in storage or provider I/O. Terminal
            // guards after each await prevent it from publishing state or
            // creating resources, while this join proves it has actually left.
            await bootstrap?.value

            return cleanupPending ? .cleanupPending : .completed
        }
        shutdownOperation = ShutdownOperation(task: task)
        return await task.value
    }

    /// Re-arm the local Agent listener immediately, cancelling any current
    /// retry backoff. Safe to call repeatedly from Settings.
    public func retryLocalHookService() {
        guard !shutdownRequested, let server = localHookServer else { return }
        let precedingLifecycle = localHookStartTask
        localHookStartTask = Task { @MainActor [weak self] in
            await precedingLifecycle?.value
            guard let self,
                  !self.shutdownRequested,
                  self.localHookServer === server else { return }
            await self.restartLocalHookServer(server)
        }
    }

    /// Refresh the bounded, read-only local history page. The page is capped
    /// for predictable Settings performance while totalCount tells the user
    /// when older rows exist beyond the current view.
    @discardableResult
    public func refreshStoredTaskHistory() async -> Bool {
        guard let store = sqliteStore else {
            storedTaskHistoryStatus = .unavailable
            return false
        }
        storedTaskHistoryStatus = .loading
        do {
            let page = try await store.loadTaskHistory(limit: 200)
            storedTaskHistory = page.tasks
            storedTaskHistoryTotalCount = page.totalCount
            storedTaskHistoryStatus = .available
            return true
        } catch {
            storedTaskHistoryStatus = .unavailable
            IslandLogger.storage.error("Couldn't load stored history")
            return false
        }
    }

    /// Delete persisted task/progress rows without disturbing the current
    /// in-memory sessions. Returns false when storage is unavailable or the
    /// transaction fails, allowing Settings to present a recoverable error.
    @discardableResult
    public func clearStoredTaskHistory() async -> Bool {
        guard let store = sqliteStore else {
            IslandLogger.storage.error("Couldn't clear history: storage unavailable")
            return false
        }
        do {
            try await store.clearStoredHistory()
            storedTaskHistory = []
            storedTaskHistoryTotalCount = 0
            storedTaskHistoryStatus = .available
            return true
        } catch {
            IslandLogger.storage.error("Couldn't clear stored history")
            return false
        }
    }

    /// Resolve one task without assuming session IDs are globally unique.
    public func task(with identity: TaskIdentity) -> AgentTask? {
        tasks.first(where: { $0.identity == identity })
    }

    public func openTask(_ task: AgentTask) {
        guard let url = TaskDestinationPolicy.destination(for: task) else {
            IslandLogger.store.warning("Rejected unsafe task destination")
            return
        }
        _ = openDestination(url)
    }

    public func openTaskInBrowser(source: String, id: String) {
        guard let task = task(with: TaskIdentity(source: source, id: id)) else { return }
        openTask(task)
    }

    /// Compatibility entry point for the v1.4 contract. It refuses an
    /// ambiguous cross-agent ID instead of opening an arbitrary task.
    public func openTaskInBrowser(id: String) {
        guard let task = uniquelyMatchingTask(id: id) else { return }
        openTask(task)
    }

    /// Jump back to the session behind a task (contract v1.4.0, J2).
    /// Managed terminal Hooks prefer the actual host that emitted the event;
    /// tmux sessions select their original window and pane before activation.
    /// Without live context, falls back to the source app / running terminal,
    /// then to `openTaskInBrowser` (local task → Finder, Manus → browser).
    public func jumpToTask(_ task: AgentTask) {
        if SourceAppResolver.activateApp(for: task) {
            IslandLogger.store.debug(
                "Activated host app for \(task.source, privacy: .public) session"
            )
            return
        }
        openTask(task)
    }

    public func jumpToTask(source: String, id: String) {
        guard let task = task(with: TaskIdentity(source: source, id: id)) else { return }
        jumpToTask(task)
    }

    /// Compatibility entry point for the v1.4 contract. New UI code should
    /// pass the task (or source + id) so cross-agent collisions are impossible.
    public func jumpToTask(id: String) {
        guard let task = uniquelyMatchingTask(id: id) else { return }
        jumpToTask(task)
    }

    public func stopTask(id: String) async throws {
        // Only Manus tasks can be stopped remotely; local sessions
        // (Claude Code) are driven by their own CLI.
        guard tasks.contains(where: { $0.source == "manus" && $0.id == id }),
              let connector = connectors.first else { return }
        try await connector.stop(taskId: id)
        // Optimistically update status
        setTasks(tasks.map { t in
            guard t.source == "manus", t.id == id else { return t }
            var updated = t
            updated.status = .completed
            updated.updatedAt = Date.now
            return updated
        })
    }

    private func uniquelyMatchingTask(id: String) -> AgentTask? {
        let matches = tasks.filter { $0.id == id }
        guard matches.count == 1 else {
            if matches.count > 1 {
                IslandLogger.store.error("Ambiguous bare task id; caller must include source")
            }
            return nil
        }
        return matches[0]
    }

    // MARK: - Internal (called by TunnelManager / PollingFallback)

    internal func ingestWebhookEvent(_ event: WebhookPayload) async {
        setTasks(StateReconciler.apply(event: event, to: tasks))
        if let store = sqliteStore {
            do {
                try await store.insertOrReplace(tasks: tasks.filter { $0.source == "manus" })
            } catch {
                IslandLogger.storage.error("Couldn't persist Manus webhook update")
            }
        }
        IslandLogger.store.debug(
            "Ingested Manus event: \(event.event.rawValue, privacy: .public)"
        )
    }

    internal func applyPollingSnapshot(_ incoming: [AgentTask]) async {
        // Polling only covers Manus — scope the reconcile so local agent
        // sessions (claude-code) survive the snapshot merge.
        setTasks(StateReconciler.reconcile(local: tasks, incoming: incoming, source: "manus"))
        let snapshot = tasks.filter { $0.source == "manus" }
        guard let store = sqliteStore else { return }
        do {
            try await store.insertOrReplace(tasks: snapshot)
        } catch {
            IslandLogger.storage.error("Couldn't persist Manus snapshot")
        }
    }

    /// Replace all tasks of one local source with a fresh snapshot from its
    /// connector (event-sourced, so the connector state is authoritative).
    internal func applyLocalSnapshot(source: String, _ snapshot: [AgentTask]) async {
        let normalized = StateReconciler.normalizedSnapshot(snapshot, source: source)
        setTasks(tasks.filter { $0.source != source } + normalized)
        guard let store = sqliteStore else { return }
        do {
            try await store.insertOrReplace(tasks: normalized)
        } catch {
            IslandLogger.storage.error("Couldn't persist local Agent snapshot")
        }
    }

    // MARK: - Local action requests

    /// Suspend the synchronous vendor hook until the user decides or the
    /// request expires. Cancellation, timeout, duplicate IDs, and shutdown
    /// all resume exactly once with `nil`, which asks the vendor to fall back
    /// to its native approval UI.
    internal func awaitActionResponse(
        for request: AgentActionRequest
    ) async -> AgentActionResponse? {
        guard !shutdownRequested, request.expiresAt > .now else { return nil }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                registerActionRequest(request, continuation: continuation)
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                _ = self?.finishActionRequest(
                    request.id,
                    response: nil,
                    restoreSession: false
                )
            }
        }
    }

    private func registerActionRequest(
        _ request: AgentActionRequest,
        continuation: CheckedContinuation<AgentActionResponse?, Never>
    ) {
        guard !shutdownRequested,
              !Task.isCancelled,
              request.expiresAt > .now else {
            continuation.resume(returning: nil)
            return
        }
        guard actionContinuations[request.id] == nil else {
            IslandLogger.store.warning("Ignored duplicate local action request id")
            continuation.resume(returning: nil)
            return
        }
        guard pendingActionRequests.count < Self.maximumPendingActionRequests else {
            IslandLogger.store.warning("Local action queue is full; using Agent-native fallback")
            continuation.resume(returning: nil)
            return
        }
        let requestsForSession = pendingActionRequests.lazy.filter {
            $0.taskIdentity == request.taskIdentity
        }.count
        guard requestsForSession < Self.maximumPendingActionRequestsPerSession else {
            IslandLogger.store.warning(
                "Local session action queue is full; using Agent-native fallback"
            )
            continuation.resume(returning: nil)
            return
        }

        actionContinuations[request.id] = continuation
        pendingActionRequests.append(request)
        markSessionWaiting(for: request)
        #if DEV_ISLAND_PERFORMANCE_QA
        PerformanceFixture.signalActionQueued(request)
        #endif

        let timeout = max(0, request.expiresAt.timeIntervalSinceNow)
        actionTimeoutTasks[request.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            _ = self?.finishActionRequest(
                request.id,
                response: nil,
                restoreSession: false
            )
        }
        IslandLogger.store.info("Queued local action request for \(request.source, privacy: .public)")
    }

    @discardableResult
    private func finishActionRequest(
        _ requestID: UUID,
        response: AgentActionResponse?,
        restoreSession: Bool
    ) -> Bool {
        guard let continuation = actionContinuations.removeValue(forKey: requestID) else {
            return false
        }

        let request = pendingActionRequests.first(where: { $0.id == requestID })
        pendingActionRequests.removeAll(where: { $0.id == requestID })
        actionTimeoutTasks.removeValue(forKey: requestID)?.cancel()
        #if DEV_ISLAND_PERFORMANCE_QA
        if let request {
            PerformanceFixture.signalActionFinished(request, response: response)
        }
        #endif
        continuation.resume(returning: response)

        if restoreSession, let request {
            restoreSessionAfterDecision(request)
        }
        return true
    }

    /// Compatibility helper for existing permission-only unit tests and
    /// internal callers. New transports should await the typed response.
    internal func awaitActionDecision(
        for request: AgentActionRequest
    ) async -> AgentActionDecision? {
        guard case .permission(let decision) = await awaitActionResponse(for: request) else {
            return nil
        }
        return decision
    }

    private func markSessionWaiting(for request: AgentActionRequest) {
        setTasks(tasks.map { task in
            guard task.identity == request.taskIdentity else { return task }
            var updated = task
            updated.status = .waiting
            switch request.kind {
            case .permission:
                updated.currentPhase = "Needs approval"
            case .question:
                updated.currentPhase = "Needs input"
            case .planReview:
                updated.currentPhase = "Review plan"
            }
            updated.waitingMessage = request.message
            updated.updatedAt = .now
            return updated
        })
    }

    private func validatedSubmission(
        for request: AgentActionRequest,
        answers: [AgentQuestionAnswer]
    ) -> AgentQuestionSubmission? {
        guard !request.questions.isEmpty,
              answers.count == request.questions.count else { return nil }
        let grouped = Dictionary(grouping: answers, by: \.question)
        guard grouped.count == request.questions.count else { return nil }

        var canonical: [AgentQuestionAnswer] = []
        for question in request.questions {
            guard let submitted = grouped[question.question], submitted.count == 1 else {
                return nil
            }
            let labels = submitted[0].selectedLabels
            let selected = Set(labels)
            guard !selected.isEmpty,
                  selected.count == labels.count,
                  question.allowsMultipleSelection || selected.count == 1 else {
                return nil
            }
            let known = Set(question.options.map(\.label))
            guard selected.isSubset(of: known) else { return nil }
            canonical.append(AgentQuestionAnswer(
                question: question.question,
                selectedLabels: question.options
                    .map(\.label)
                    .filter(selected.contains)
            ))
        }
        return AgentQuestionSubmission(questions: request.questions, answers: canonical)
    }

    private func restoreSessionAfterDecision(_ request: AgentActionRequest) {
        // A second queued request for the same session is still blocking it.
        guard !pendingActionRequests.contains(where: {
            $0.taskIdentity == request.taskIdentity
        }) else { return }

        setTasks(tasks.map { task in
            guard task.identity == request.taskIdentity, task.status == .waiting else {
                return task
            }
            var updated = task
            updated.status = .running
            updated.currentPhase = nil
            updated.waitingMessage = nil
            updated.updatedAt = .now
            return updated
        })
    }

    internal func cancelActionRequests(for identity: TaskIdentity) {
        let ids = pendingActionRequests
            .filter { $0.taskIdentity == identity }
            .map(\.id)
        for id in ids {
            _ = finishActionRequest(id, response: nil, restoreSession: false)
        }
    }

    internal func cancelAllActionRequests() {
        let ids = pendingActionRequests.map(\.id)
        for id in ids {
            _ = finishActionRequest(id, response: nil, restoreSession: false)
        }
    }

    // MARK: - Bootstrap

    private func bootstrap() async {
        await manusDependencies.awaitBootstrapPermission()
        guard !shutdownRequested else { return }

        // Open SQLite
        let store = SQLiteStore()
        do {
            try await store.open()
            guard !shutdownRequested else { return }
            sqliteStore = store
            _ = await refreshStoredTaskHistory()
            guard !shutdownRequested else { return }
        } catch {
            guard !shutdownRequested else { return }
            sqliteStore = nil
            storedTaskHistoryStatus = .unavailable
            IslandLogger.storage.error("Couldn't open local history storage")
        }

        // Local agent pipeline runs regardless of Manus configuration.
        guard !shutdownRequested else { return }
        startLocalHookPipeline()

        // Sleep/wake observers guard the local pipeline too, so they must
        // register even when no Manus key is configured (previously they
        // were only registered at the end of the happy path).
        guard !shutdownRequested else { return }
        registerSleepWakeObservers()

        // Load API key from Keychain
        guard !shutdownRequested else { return }
        guard let apiKey = try? manusDependencies.loadAPIKey() else {
            guard !shutdownRequested else { return }
            apiKeyStatus = .notConfigured
            IslandLogger.store.info("No API key found in Keychain")
            return
        }

        // Validate key
        guard !shutdownRequested else { return }
        let client = manusDependencies.makeClient(apiKey)
        do {
            let initialTasks = try await client.listTasks()
            guard !shutdownRequested else { return }
            apiKeyStatus = .valid
            await applyPollingSnapshot(initialTasks)
            guard !shutdownRequested else { return }
        } catch ManusError.unauthorized {
            guard !shutdownRequested else { return }
            apiKeyStatus = .invalid
            IslandLogger.store.warning("Stored API key is invalid")
            return
        } catch ManusError.invalidURL {
            guard !shutdownRequested else { return }
            apiKeyStatus = .invalid
            IslandLogger.store.warning("Stored API key is not header-safe")
            return
        } catch {
            guard !shutdownRequested else { return }
            IslandLogger.store.error("Manus bootstrap validation failed")
            // Still try to start services — might be transient network error
        }

        guard !shutdownRequested else { return }
        do {
            try await startServices(client: client)
        } catch {
            guard !shutdownRequested else { return }
            IslandLogger.store.error("Manus services failed to start")
            connectionStatus = .degraded(reason: "Manus services unavailable; reconnect to retry")
        }
    }

    // MARK: - Local agent pipeline (registry-driven)

    private func startLocalHookPipeline() {
        guard !shutdownRequested else { return }
        // One generic connector per registered agent — the registry is the
        // single source of truth for which agents exist.
        let connectors = Dictionary(uniqueKeysWithValues: LocalAgentRegistry.all.map {
            ($0.source, LocalAgentConnector(descriptor: $0))
        })
        localConnectors = connectors
        let server = LocalHookServer()
        localHookServer = server

        let precedingLifecycle = localHookStartTask
        localHookStartTask = Task { @MainActor [weak self] in
            await precedingLifecycle?.value
            guard let self,
                  !self.shutdownRequested,
                  self.localHookServer === server else { return }
            await server.start(
                agents: LocalAgentRegistry.all,
                onActionRequest: { [weak self] request in
                    guard let self else { return nil }
                    return await self.awaitActionResponse(for: request)
                },
                onStatusChange: { [weak self] status in
                    Task { @MainActor [weak self] in
                        guard let self, !self.shutdownRequested else { return }
                        self.localHookServiceStatus = status
                    }
                }
            ) { [weak self] source, event in
                await self?.ingestLocalAgentEvent(source: source, event: event)
            }
        }
        let sources = LocalAgentRegistry.all.map(\.source).joined(separator: ", ")
        IslandLogger.store.info("Local hook pipeline started (\(sources))")
    }

    /// Keep the lifecycle half of a synchronous action Hook ordered before
    /// its decision queue. `LocalHookServer` awaits this method before it
    /// calls `onActionRequest`, preventing a late Waiting snapshot from
    /// overwriting the Running state restored after Allow/Deny.
    private func ingestLocalAgentEvent(
        source: String,
        event: LocalAgentEvent
    ) async {
        guard !shutdownRequested else { return }
        // Look up through the stored map (not a closure capture) so the
        // store's property is the single owner and a future pipeline restart
        // can swap connectors safely.
        guard let connector = localConnectors[source] else { return }

        switch event.action {
        case .completed, .failed, .sessionEnd:
            cancelActionRequests(for: TaskIdentity(
                source: source,
                id: event.sessionId
            ))
        case .running, .waiting, .ignored:
            break
        }

        let snapshot = await connector.apply(event)
        guard !shutdownRequested else { return }
        await applyLocalSnapshot(source: source, snapshot)
    }

    // MARK: - Service lifecycle

    private func startServices(
        client: any ManusServiceClientProtocol
    ) async throws {
        let previousServices = detachManusServices()
        let serviceGeneration = manusServiceGeneration
        await stopDetachedManusServices(previousServices)
        guard serviceGeneration == manusServiceGeneration else { return }

        let connector = ManusConnector(serviceClient: client)
        connectors = [connector]
        let webhookPreferences = manusDependencies.webhookPreferencesSuiteName
            .flatMap { UserDefaults(suiteName: $0) }
        // Even polling-only mode must retain a credential-backed cleanup owner.
        // A prior crash or failed delete can leave persisted webhook IDs that
        // must be removed before Disconnect is allowed to release the key.
        tunnelManager = TunnelManager(
            client: client,
            server: CleanupOnlyWebhookServer(),
            preferences: TunnelPreferencesHandle(webhookPreferences)
        )

        // The official v2 protocol is implemented, but public exposure stays
        // code-gated until a real account has passed registration, signed test
        // delivery, event delivery, and deletion. When enabled, trust material
        // comes only from Manus' authenticated hard-coded v2 endpoint.
        let trustAnchor: String?
        if ManusRealtimeTrust.liveV2AcceptanceComplete {
            do {
                trustAnchor = try await client.webhookPublicKey()
            } catch {
                trustAnchor = nil
                IslandLogger.store.warning("Manus webhook trust fetch failed")
            }
        } else {
            trustAnchor = nil
        }
        guard serviceGeneration == manusServiceGeneration else { return }

        if let trustAnchor,
           let server = WebhookServer(signaturePublicKeyPEM: trustAnchor) {
            let tunnel = TunnelManager(
                client: client,
                server: server,
                preferences: TunnelPreferencesHandle(webhookPreferences)
            )
            tunnelManager = tunnel

            do {
                try await tunnel.start(
                    onEvent: { [weak self] event in
                        Task { @MainActor [weak self] in
                            await self?.ingestManusWebhookEvent(
                                event,
                                serviceGeneration: serviceGeneration
                            )
                        }
                    },
                    onRealtimeUnavailable: { [weak self] in
                        await self?.handleManusRealtimeUnavailable(
                            serviceGeneration: serviceGeneration
                        )
                    }
                )
                guard serviceGeneration == manusServiceGeneration else {
                    try? await tunnel.stop()
                    return
                }
                pollingOnlyReason = nil
                connectionStatus = .connected
                IslandLogger.store.info("Services started (verified realtime + polling fallback)")
            } catch TunnelError.tooManyRestarts {
                try? await tunnel.stop()
                guard serviceGeneration == manusServiceGeneration else { return }
                IslandLogger.store.warning("Realtime unavailable — falling back to secure polling")
                enterPollingOnly(reason: ManusRealtimeTrust.pollingOnlyReason)
            } catch {
                try? await tunnel.stop()
                guard serviceGeneration == manusServiceGeneration else { return }
                IslandLogger.store.warning("Realtime start failed — secure polling only")
                enterPollingOnly(reason: ManusRealtimeTrust.pollingOnlyReason)
            }
        } else {
            enterPollingOnly(reason: ManusRealtimeTrust.pollingOnlyReason)
            IslandLogger.store.notice("Manus realtime disabled: live v2 acceptance incomplete")
        }

        // Always start polling (as primary in degraded mode, as fallback otherwise)
        guard serviceGeneration == manusServiceGeneration else { return }
        let poller = PollingFallback(connector: connector)
        pollingFallback = poller
        await poller.start(
            onSnapshot: { [weak self] snapshot in
                await self?.applyManusPollingSnapshot(
                    snapshot,
                    serviceGeneration: serviceGeneration
                )
            },
            onNetworkError: { [weak self] in
                await self?.handleManusPollingNetworkError(
                    serviceGeneration: serviceGeneration
                )
            },
            onNetworkRestored: { [weak self] in
                await self?.handleManusPollingNetworkRestored(
                    serviceGeneration: serviceGeneration
                )
            },
            onUnauthorized: { [weak self] in
                await self?.handleManusPollingUnauthorized(
                    serviceGeneration: serviceGeneration
                )
            }
        )
    }

    private func ingestManusWebhookEvent(
        _ event: WebhookPayload,
        serviceGeneration: UInt64
    ) async {
        guard serviceGeneration == manusServiceGeneration else { return }
        await ingestWebhookEvent(event)
    }

    private func applyManusPollingSnapshot(
        _ snapshot: [AgentTask],
        serviceGeneration: UInt64
    ) async {
        guard serviceGeneration == manusServiceGeneration else { return }
        await applyPollingSnapshot(snapshot)
    }

    private func handleManusPollingNetworkError(serviceGeneration: UInt64) {
        guard serviceGeneration == manusServiceGeneration else { return }
        switch connectionStatus {
        case .connected, .degraded:
            connectionStatus = .reconnecting
            IslandLogger.store.warning("Network lost — status: reconnecting")
        case .disconnected, .reconnecting:
            break
        }
    }

    private func handleManusPollingNetworkRestored(serviceGeneration: UInt64) {
        guard serviceGeneration == manusServiceGeneration else { return }
        connectionStatus = restoredManusConnectionStatus
        IslandLogger.store.info("Manus network connection restored")
    }

    private func handleManusPollingUnauthorized(serviceGeneration: UInt64) async {
        guard serviceGeneration == manusServiceGeneration else { return }
        manusServiceGeneration &+= 1
        apiKeyStatus = .invalid
        connectionStatus = .disconnected
        pollingOnlyReason = nil
        pollingFallback = nil
        connectors = []
        let tunnel = tunnelManager
        tunnelManager = nil
        IslandLogger.store.warning("Manus authorization expired — reconnect required")
        try? await tunnel?.stop()
    }

    private func enterPollingOnly(reason: String) {
        pollingOnlyReason = reason
        connectionStatus = .degraded(reason: reason)
    }

    /// A live cloudflared child is not a realtime connection unless its
    /// webhook registration is also live. Heartbeat failures arrive here and
    /// permanently downgrade this service generation until the user performs
    /// an explicit reconnect.
    private func handleManusRealtimeUnavailable(serviceGeneration: UInt64) async {
        guard serviceGeneration == manusServiceGeneration,
              let tunnel = tunnelManager else { return }
        enterPollingOnly(reason: ManusRealtimeTrust.pollingOnlyReason)
        IslandLogger.store.warning("Manus realtime unavailable — secure polling only")
        try? await tunnel.stop()
    }

    private var restoredManusConnectionStatus: ConnectionStatus {
        ManusConnectionStatusPolicy.restoredStatus(
            pollingOnlyReason: pollingOnlyReason
        )
    }

    private struct DetachedManusServices: Sendable {
        let poller: PollingFallback?
        let tunnel: (any ManusTunnelLifecycleProtocol)?
    }

    /// Invalidate callbacks and detach owned resources synchronously before
    /// any cleanup await. A newer configure operation can therefore never
    /// inherit or overwrite an older manager/poller reference.
    private func detachManusServices() -> DetachedManusServices {
        manusServiceGeneration &+= 1
        let services = DetachedManusServices(
            poller: pollingFallback,
            tunnel: tunnelManager
        )
        pollingFallback = nil
        tunnelManager = nil
        connectors = []
        pollingOnlyReason = nil
        return services
    }

    private func stopDetachedManusServices(
        _ services: DetachedManusServices
    ) async {
        await services.poller?.stop()
        try? await services.tunnel?.stop()
    }

    // MARK: - Sleep / wake

    /// Begin the system-sleep half of the lifecycle without blocking AppKit's
    /// notification callback. The retained task is the ordering barrier for
    /// the next wake; it is intentionally not detached or fire-and-forget.
    internal func handleSystemWillSleep() {
        guard !shutdownRequested else { return }
        systemPowerGeneration &+= 1
        cancelAllActionRequests()
        connectionStatus = .disconnected

        if manusSleepSuspension == nil {
            let tunnel = tunnelManager
            manusSleepSuspension = ManusSleepSuspension(
                id: UUID(),
                task: Task {
                    await tunnel?.suspend()
                }
            )
        }
        IslandLogger.store.info("System going to sleep")
    }

    /// Recover local and Manus services only after the matching suspend has
    /// completed. A newer sleep/shutdown invalidates every result across each
    /// await, and a duplicate wake without a pending sleep is a no-op for the
    /// public tunnel so it cannot consume the restart budget.
    internal func handleSystemDidWake() async {
        guard !shutdownRequested else { return }
        IslandLogger.store.info("System woke — health-checking services")

        // Local pipeline recovery is independently idempotent and remains
        // useful for a stray wake notification even without Manus configured.
        await localHookServer?.ensureRunning()
        guard !shutdownRequested else { return }

        guard let pendingSuspension = manusSleepSuspension else { return }
        systemPowerGeneration &+= 1
        let wakeGeneration = systemPowerGeneration
        await pendingSuspension.task.value
        guard wakeGeneration == systemPowerGeneration,
              manusSleepSuspension?.id == pendingSuspension.id else { return }
        manusSleepSuspension = nil

        // Manus side only applies when services are configured.
        guard tunnelManager != nil || !connectors.isEmpty else { return }
        let serviceGeneration = manusServiceGeneration
        connectionStatus = .reconnecting

        // Polling-only mode must not create or restart a public tunnel.
        if pollingOnlyReason == nil,
           let tunnel = tunnelManager {
            do {
                try await tunnel.handleSleepWake()
            } catch {
                guard wakeGeneration == systemPowerGeneration else { return }
                IslandLogger.store.warning(
                    "Manus realtime wake recovery failed — secure polling only"
                )
                await handleManusRealtimeUnavailable(
                    serviceGeneration: serviceGeneration
                )
            }
        }

        guard wakeGeneration == systemPowerGeneration,
              serviceGeneration == manusServiceGeneration else { return }

        // Immediate poll to sync state.
        if let connector = connectors.first {
            do {
                let snapshot = try await connector.fetchTasks()
                guard wakeGeneration == systemPowerGeneration,
                      serviceGeneration == manusServiceGeneration else { return }
                await applyManusPollingSnapshot(
                    snapshot,
                    serviceGeneration: serviceGeneration
                )
                guard wakeGeneration == systemPowerGeneration,
                      serviceGeneration == manusServiceGeneration else { return }
                connectionStatus = restoredManusConnectionStatus
            } catch ManusError.unauthorized {
                guard wakeGeneration == systemPowerGeneration else { return }
                await handleManusPollingUnauthorized(
                    serviceGeneration: serviceGeneration
                )
            } catch {
                if wakeGeneration == systemPowerGeneration,
                   serviceGeneration == manusServiceGeneration {
                    IslandLogger.store.error("Post-wake Manus poll failed")
                }
            }
        }
    }

    private func registerSleepWakeObservers() {
        guard !shutdownRequested else { return }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSystemWillSleep()
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleSystemDidWake()
            }
        }
    }
}

#if DEBUG
extension TaskStore {
    /// Build an in-memory store with mock data for SwiftUI Previews and the
    /// Debug Sandbox. C-side only — S, please preserve this `#if DEBUG` block
    /// when replacing the stubs above.
    public static func mock(
        tasks: [AgentTask] = TaskStore.previewTasks,
        connection: ConnectionStatus = .connected,
        apiKey: APIKeyStatus = .valid
    ) -> TaskStore {
        // bootstrap: false — previews and unit tests must never bind the
        // hook server port or touch SQLite/Keychain.
        let store = TaskStore(bootstrap: false)
        store.tasks = tasks
        store.connectionStatus = connection
        store.apiKeyStatus = apiKey
        return store
    }

    /// Exact storage-maintenance harness: proves privacy deletion does not
    /// erase active in-memory sessions. Internal and DEBUG-only so production
    /// callers cannot swap the persistence actor.
    internal static func maintenanceTestStore(
        sqliteStore: SQLiteStore,
        tasks: [AgentTask]
    ) -> TaskStore {
        let store = TaskStore(bootstrap: false)
        store.sqliteStore = sqliteStore
        store.tasks = tasks
        return store
    }

    /// Inert Launch Services boundary for destination-policy attack tests.
    /// Production construction cannot replace the opener.
    internal static func destinationTestStore(
        tasks: [AgentTask],
        openDestination: @escaping (URL) -> Bool
    ) -> TaskStore {
        let store = TaskStore(
            bootstrap: false,
            openDestination: openDestination
        )
        store.tasks = tasks
        return store
    }

    // MARK: - Debug Sandbox mutators (CLAUDE_CLIENT.md §6 task 10)
    //
    // The Debug Sandbox window drives `TaskStore.shared` directly so we can
    // exercise every UI path without Manus. These live in this file because
    // `tasks` / `connectionStatus` are `private(set)` — only same-file
    // extensions can mutate them, which is also exactly what we want: the
    // production setter contract stays untouched, the debug write surface
    // is physically scoped to one #if DEBUG block in one file.
    //
    // Naming: prefixed `debug…` so call sites read like sandbox plumbing,
    // not real domain logic. Production code MUST NOT call these.

    /// Visual and assistive-technology QA often pauses between a screenshot,
    /// an AX-tree read, and the next action. Use the model's validated
    /// two-minute ceiling in DEBUG without changing the 90-second production
    /// fallback contract or bypassing the bounded request invariant.
    private static let debugActionTimeout: TimeInterval = AgentActionRequest.maximumTimeout

    /// Replace the entire task list. Triggers an Observation update so
    /// every view bound to `tasks` re-renders (bar count, panel list).
    /// Routed through the transition funnel so `onTaskTransition` fires —
    /// the Debug Sandbox is how B tests notifications (contract v1.4.0).
    public func debugSetTasks(_ tasks: [AgentTask]) {
        setTasks(tasks)
    }

    /// Append a single task. Used by the "+ Running / + Waiting / …" row.
    public func debugAppend(_ task: AgentTask) {
        setTasks(tasks + [task])
    }

    /// Drop every task — also exercises the empty-state rendering path.
    public func debugClearTasks() {
        cancelAllActionRequests()
        setTasks([])
    }

    /// Exercise the real synchronous approval queue from the Debug Sandbox.
    /// The request is resolved by the same Allow/Deny buttons production
    /// Codex traffic uses; no preview-only UI path is involved.
    public func debugSpawnApprovalRequest() {
        let sessionID = "dbg-approval-\(UUID().uuidString.prefix(6))"
        let now = Date.now
        let task = AgentTask(
            id: sessionID,
            source: "codex",
            title: "DevLand release check",
            status: .waiting,
            currentPhase: "Needs approval",
            createdAt: now,
            updatedAt: now,
            taskURL: "file:///Users/dev/DevLand",
            waitingMessage: "Approval needed: Bash"
        )
        debugAppend(task)

        let request = AgentActionRequest(
            source: "codex",
            sessionId: sessionID,
            kind: .permission,
            title: "Approve Bash",
            message: "Codex wants to inspect the release working tree.",
            detail: "git status --short && swift test",
            timeout: Self.debugActionTimeout
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.awaitActionDecision(for: request)
        }
    }

    /// Exercise the production AskUserQuestion queue and progressive answer
    /// UI without spending Claude tokens or depending on a live CLI session.
    public func debugSpawnQuestionRequest() {
        let sessionID = "dbg-question-\(UUID().uuidString.prefix(6))"
        let now = Date.now
        debugAppend(AgentTask(
            id: sessionID,
            source: "claude-code",
            title: "Dev Island interaction review",
            status: .running,
            currentPhase: "Thinking",
            createdAt: now,
            updatedAt: now,
            taskURL: "file:///Users/dev/DevLand"
        ))

        let request = AgentActionRequest(
            source: "claude-code",
            sessionId: sessionID,
            kind: .question,
            title: "Claude Code needs input",
            message: "Answer two questions to continue.",
            questions: [
                AgentQuestion(
                    question: "Which surface should own approvals?",
                    header: "Surface",
                    options: [
                        AgentQuestionOption(
                            label: "Dev Island",
                            description: "Stay in the compact island workflow"
                        ),
                        AgentQuestionOption(
                            label: "Terminal",
                            description: "Return to Claude Code for every prompt"
                        ),
                    ]
                ),
                AgentQuestion(
                    question: "Which verification should run?",
                    header: "Checks",
                    options: [
                        AgentQuestionOption(label: "Unit tests"),
                        AgentQuestionOption(label: "Launch smoke"),
                        AgentQuestionOption(label: "Visual review"),
                    ],
                    allowsMultipleSelection: true
                ),
            ],
            timeout: Self.debugActionTimeout
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.awaitActionResponse(for: request)
        }
    }

    /// Exercise the production ExitPlanMode queue and Markdown surface
    /// without changing the user's Claude Code hooks or starting a session.
    public func debugSpawnPlanReview() {
        let sessionID = "dbg-plan-\(UUID().uuidString.prefix(6))"
        let now = Date.now
        debugAppend(AgentTask(
            id: sessionID,
            source: "claude-code",
            title: "Dev Island plan review",
            status: .running,
            currentPhase: "Planning",
            createdAt: now,
            updatedAt: now,
            taskURL: "file:///Users/dev/DevLand"
        ))

        let markdown = """
        ## Refine the attention flow

        1. Keep **approval requests** ahead of completed and running sessions.
        2. Preserve stable ordering inside the same priority tier.
        3. Verify keyboard focus, VoiceOver order, and Reduce Motion.

        ```swift
        priority = attention > completed > running > idle
        ```
        """
        let input: [String: Any] = [
            "plan": markdown,
            "planFilePath": "/Users/dev/.claude/plans/dev-island-attention.md",
        ]
        guard let inputJSON = try? JSONSerialization.data(
            withJSONObject: input,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ),
              let review = AgentPlanReview(
                markdown: markdown,
                originalInputJSON: inputJSON
              ) else { return }

        let request = AgentActionRequest(
            source: "claude-code",
            sessionId: sessionID,
            kind: .planReview,
            title: "Review Claude Code plan",
            message: "Claude Code is ready to begin implementation.",
            planReview: review,
            timeout: Self.debugActionTimeout
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.awaitActionResponse(for: request)
        }
    }

    /// Override the connection-status indicator (header dot + any future
    /// degraded-bar visuals).
    public func debugSetConnectionStatus(_ status: ConnectionStatus) {
        self.connectionStatus = status
    }

    /// Spawn a synthetic task in the given status with sensible defaults
    /// for the fields the sandbox doesn't care about. Returns the task so
    /// callers can mutate it further if they ever want to.
    @discardableResult
    public func debugSpawn(status: TaskStatus, title: String? = nil) -> AgentTask {
        let now = Date()
        let task = AgentTask(
            id: "dbg-\(UUID().uuidString.prefix(6))",
            source: "debug",
            title: title ?? Self.debugDefaultTitle(for: status),
            status: status,
            currentPhase: Self.debugDefaultPhase(for: status),
            createdAt: now,
            updatedAt: now,
            taskURL: "https://example.invalid/debug",
            waitingMessage: status == .waiting
                ? "Sandbox-injected waiting prompt"
                : nil
        )
        debugAppend(task)
        return task
    }

    private static func debugDefaultTitle(for status: TaskStatus) -> String {
        switch status {
        case .running:   return "Sandbox running task"
        case .waiting:   return "Sandbox waiting task"
        case .completed: return "Sandbox completed task"
        case .failed:    return "Sandbox failed task"
        }
    }

    private static func debugDefaultPhase(for status: TaskStatus) -> String? {
        switch status {
        case .running:   return "Doing fake work"
        case .waiting:   return "Awaiting fake input"
        case .completed: return nil
        case .failed:    return nil
        }
    }

    public static let previewTasks: [AgentTask] = [
        AgentTask(
            id: "t1",
            source: "manus",
            title: "Research competitive landscape for notch apps",
            status: .running,
            currentPhase: "Browsing GitHub trending",
            createdAt: Date(timeIntervalSinceNow: -180),
            updatedAt: Date(),
            taskURL: "https://manus.im/app/t1"
        ),
        AgentTask(
            id: "t2",
            source: "manus",
            title: "Draft launch tweet thread",
            status: .waiting,
            currentPhase: "Awaiting tone preference",
            createdAt: Date(timeIntervalSinceNow: -420),
            updatedAt: Date(timeIntervalSinceNow: -30),
            taskURL: "https://manus.im/app/t2",
            waitingMessage: "Should the thread be technical or playful?"
        ),
        AgentTask(
            id: "t3",
            source: "manus",
            title: "Summarize last week's PRs",
            status: .completed,
            currentPhase: nil,
            createdAt: Date(timeIntervalSinceNow: -3600),
            updatedAt: Date(timeIntervalSinceNow: -600),
            taskURL: "https://manus.im/app/t3"
        ),
    ]
}
#endif
