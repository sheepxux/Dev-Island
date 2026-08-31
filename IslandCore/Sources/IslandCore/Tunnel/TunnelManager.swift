import CryptoKit
import Foundation

enum TunnelError: Error {
    case tooManyRestarts
    case serverUnavailable
    case trustConfigurationFailed(underlying: Error)
    case registrationFailed(underlying: Error)
    case webhookCleanupFailed(underlying: Error)
    case lifecycleSuperseded
}

/// Narrow internal seams keep the public Manus, HTTP-server, and process
/// implementations intact while making the realtime lifecycle deterministic
/// under test. All conformers are actors in production.
protocol ManusWebhookClientProtocol: Sendable {
    func webhookPublicKey() async throws -> String
    func registerWebhook(publicURL: String) async throws -> String
    func listWebhooks() async throws -> [ManusWebhook]
    func deleteWebhook(id: String) async throws
    func registrationFailureDisposition(
        for error: any Error
    ) async -> WebhookRegistrationFailureDisposition
}

enum WebhookRegistrationFailureDisposition: Equatable, Sendable {
    case definitivelyRejected
    case outcomeUnknown
}

extension ManusWebhookClientProtocol {
    func listWebhooks() async throws -> [ManusWebhook] {
        throw ManusError.invalidResponse
    }

    func registrationFailureDisposition(
        for error: any Error
    ) async -> WebhookRegistrationFailureDisposition {
        .outcomeUnknown
    }
}

extension ManusAPIClient {
    nonisolated func registrationFailureDisposition(
        for error: any Error
    ) async -> WebhookRegistrationFailureDisposition {
        switch error {
        case ManusError.unauthorized,
             ManusError.invalidURL:
            return .definitivelyRejected
        case ManusError.httpError(let statusCode, _)
            where [400, 401, 403, 404, 405, 410, 422].contains(statusCode):
            return .definitivelyRejected
        default:
            // Cancellation, transport loss, timeout, a 5xx, or an undecodable
            // success response can all happen after the provider committed.
            return .outcomeUnknown
        }
    }
}

protocol WebhookServerProtocol: Sendable {
    func configure(externalURL: String, signaturePublicKeyPEM: String) async throws
    func start(onEvent: @escaping @Sendable (WebhookPayload) -> Void) async throws
    func isReady() async -> Bool
    func stop() async
}

protocol TunnelProcessProtocol: Sendable {
    var isRunning: Bool { get async }
    func start() async throws -> URL
    func stop() async
}

/// `UserDefaults` is documented as thread-safe, but Foundation does not mark
/// it `Sendable`. Crossing from TaskStore's MainActor into TunnelManager with
/// the raw reference therefore trips Swift 6 region-isolation diagnostics.
/// Keep the unchecked boundary narrow and explicit; all reads and writes stay
/// serialized by TunnelManager after construction.
struct TunnelPreferencesHandle: @unchecked Sendable {
    let defaults: UserDefaults?

    init(_ defaults: UserDefaults?) {
        self.defaults = defaults
    }

    static let shipping = TunnelPreferencesHandle(
        UserDefaults(suiteName: "app.devisland.Island")
    )
}

/// The narrow lifecycle surface TaskStore needs across system sleep/wake.
/// Keeping it protocol-backed makes notification ordering and late-result
/// behavior testable without opening a local server or public tunnel.
protocol ManusTunnelLifecycleProtocol: Sendable {
    func start(
        onEvent: @escaping @Sendable (WebhookPayload) -> Void,
        onRealtimeUnavailable: @escaping @Sendable () async -> Void
    ) async throws
    /// Stops every local transport and reports whether the remote webhook was
    /// actually deleted. Callers that are not releasing the credential may
    /// deliberately ignore the error; account removal must not.
    func stop() async throws
    func suspend() async
    func handleSleepWake() async throws
}

extension WebhookServer: WebhookServerProtocol {}
extension CloudflaredProcess: TunnelProcessProtocol {}

enum TunnelRuntimeStatus: Equatable, Sendable {
    case stopped
    case serverOnly
    case registered
}

/// Inert-by-default checkpoints for deterministic actor-reentrancy tests.
/// They expose only operation ownership, never credentials or provider data.
enum WebhookCleanupRaceCheckpoint: Equatable, Sendable {
    case listingWillAwait(joinedExisting: Bool)
    case listingDidReturn(joinedExisting: Bool)
    case deletionWillAwait(operationToken: UUID)
}

/// Polling-only mode still needs a credential-backed owner for webhook IDs
/// left by a crash or failed provider delete. This server can never expose a
/// listener; it exists only so the normal TunnelManager cleanup transaction is
/// available even when realtime trust/startup is disabled.
actor CleanupOnlyWebhookServer: WebhookServerProtocol {
    func configure(externalURL: String, signaturePublicKeyPEM: String) throws {
        throw TunnelError.serverUnavailable
    }

    func start(onEvent: @escaping @Sendable (WebhookPayload) -> Void) throws {
        throw TunnelError.serverUnavailable
    }

    func isReady() -> Bool { false }
    func stop() {}
}

/// A credential-releasing stop must never report success while the durable
/// webhook ledger still contains an ID. Keep the underlying invariant error
/// deliberately low-cardinality so logs cannot accidentally expose provider
/// identifiers.
private enum WebhookCleanupInvariantError: Error {
    case persistedWebhookIDsRemain
    case registrationOutcomeUnresolved
    case registrationAttemptPersistenceFailed
}

actor TunnelManager {
    @TaskLocal private static var lifecycleCallbackToken: UUID?

    private struct StopOperation: Sendable {
        let token: UUID
        let task: Task<Void, Error>
    }

    private struct RegisteredTransport: Sendable {
        let token: UUID
        let process: any TunnelProcessProtocol
        let webhookID: String
    }

    private struct HeartbeatOperation: Sendable {
        let token: UUID
        let task: Task<Void, Never>
    }

    private struct LifecycleCallbackOperation: Sendable {
        let token: UUID
        let task: Task<Void, Never>
    }

    /// Remote deletion is shared by every lifecycle branch that can discover
    /// the same accepted registration. Actor reentrancy must not turn a stop,
    /// wake and late registration into multiple competing delete requests.
    private struct WebhookDeletionOperation: Sendable {
        let token: UUID
        let webhookID: String
        let task: Task<Void, Error>
    }

    /// One provider request is recoverable after process death only when the
    /// durable marker identifies the exact callback without persisting its
    /// public URL. The provider timestamp is checked against `startedAt` before
    /// any listed webhook can enter the authoritative deletion ledger.
    private struct UnresolvedWebhookRegistrationAttempt:
        Codable, Equatable, Sendable {
        static let schemaVersion = 1

        let version: Int
        let token: String
        let callbackURLSHA256: String
        let startedAtUnixSeconds: Int64
        let discoveredWebhookIDs: [String]

        private enum CodingKeys: String, CodingKey {
            case version
            case token
            case callbackURLSHA256
            case startedAtUnixSeconds
            case discoveredWebhookIDs
        }

        init(
            version: Int,
            token: String,
            callbackURLSHA256: String,
            startedAtUnixSeconds: Int64,
            discoveredWebhookIDs: [String]
        ) {
            self.version = version
            self.token = token
            self.callbackURLSHA256 = callbackURLSHA256
            self.startedAtUnixSeconds = startedAtUnixSeconds
            self.discoveredWebhookIDs = discoveredWebhookIDs
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            token = try container.decode(String.self, forKey: .token)
            callbackURLSHA256 = try container.decode(
                String.self,
                forKey: .callbackURLSHA256
            )
            startedAtUnixSeconds = try container.decode(
                Int64.self,
                forKey: .startedAtUnixSeconds
            )
            // Early v1 development builds wrote the same schema before the
            // discovered-ID retry phase existed. Missing means "not bound yet";
            // every present value is still validated by the recovery decoder.
            discoveredWebhookIDs = try container.decodeIfPresent(
                [String].self,
                forKey: .discoveredWebhookIDs
            ) ?? []
        }
    }

    /// One authoritative, versioned persistence unit owns every capability
    /// needed to recover a remote webhook. Legacy keys remain diagnostic
    /// mirrors only; a crash can no longer split the ID ledger from its attempt
    /// marker across independent UserDefaults writes.
    private struct WebhookRecoveryStateEnvelope: Codable, Equatable, Sendable {
        static let schemaVersion = 1

        let version: Int
        let knownWebhookIDs: [String]
        let unresolvedRegistrationTokens: [String]
        let unresolvedRegistrationAttempts:
            [UnresolvedWebhookRegistrationAttempt]
    }

    /// Reconciliation is account-scoped and credential-bearing. Concurrent
    /// start/stop callers share one retained listing operation so actor
    /// reentrancy cannot issue parallel account inventory requests.
    private struct WebhookListingOperation: Sendable {
        let token: UUID
        let task: Task<[ManusWebhook], Error>
    }

    /// `stop()` must join registrations that are suspended inside the provider
    /// request. Otherwise account removal could release the API credential and
    /// only afterwards discover an accepted webhook that still needs it.
    private struct WebhookLaunchOperation: Sendable {
        let token: UUID
        let task: Task<Void, Error>
        var process: (any TunnelProcessProtocol)?
        var processStopRequested: Bool
    }

    private let client: any ManusWebhookClientProtocol
    private let server: any WebhookServerProtocol
    private let processFactory: @Sendable () -> any TunnelProcessProtocol
    private let preferences: UserDefaults?
    private let wakeDelay: Duration
    private let heartbeatDelay: Duration
    private let launchCancellationGrace: Duration
    static let webhookIDPreferenceKey = "webhookId"

    /// A process is never promoted to `activeTransport` until Manus has
    /// returned a webhook ID. This makes "process alive but no webhook"
    /// unrepresentable as a connected realtime state.
    private var activeTransport: RegisteredTransport?
    private var restartTimestamps: [Date] = []
    private var heartbeatOperation: HeartbeatOperation?
    private var retiringHeartbeatOperations: [UUID: HeartbeatOperation] = [:]
    private var lifecycleCallbackOperations: [UUID: LifecycleCallbackOperation] = [:]
    private var onEventReceived: (@Sendable (WebhookPayload) -> Void)?
    private var onRealtimeUnavailable: (@Sendable () async -> Void)?
    private var isServerStarted = false
    private var lifecycleGeneration: UInt64 = 0
    /// Remote registrations that are active or still awaiting a confirmed
    /// delete. Each is persisted before post-registration checks so a crash,
    /// cancellation or rate-limit failure cannot erase the IDs capable of
    /// cleaning up public callbacks.
    private var knownWebhookIDs: [String]
    private var webhookDeletionOperations: [String: WebhookDeletionOperation] = [:]
    /// Monotonic attempt ownership lets `stop()` distinguish an ID actually
    /// tried by a joined lifecycle from another persisted ID that merely
    /// happened to be present when that lifecycle failed. Without this, one
    /// failed launch cleanup could incorrectly suppress cleanup of every other
    /// known ID in the same explicit Disconnect.
    private var webhookDeletionAttemptSequence: UInt64 = 0
    private var latestWebhookDeletionAttemptByID: [String: UInt64] = [:]
    private var webhookLaunchOperations: [UUID: WebhookLaunchOperation] = [:]
    /// A registration request is durably marked before it crosses the network.
    /// If the provider outcome is not known, no later process lifetime may
    /// release the credential or create a replacement callback by guessing.
    private var unresolvedRegistrationTokens: Set<String>
    /// Versioned recovery metadata for tokens created by this build. Tokens
    /// from older builds remain in `unresolvedRegistrationTokens` without an
    /// attempt record and deliberately stay fail-closed because their callback
    /// identity cannot be reconstructed safely.
    private var unresolvedRegistrationAttempts:
        [String: UnresolvedWebhookRegistrationAttempt]
    /// Covers the complete authoritative recovery envelope, not only attempt
    /// rows. Any malformed ID ledger, token set or cross-reference keeps all
    /// credential-releasing operations fail closed.
    private var unresolvedRegistrationAttemptStateIsCorrupt: Bool
    private var webhookListingOperation: WebhookListingOperation?
    /// Credential release is single-flight. The retained task owns the full
    /// unwind, so cancelling an individual waiter cannot strand a callback or
    /// cause another caller to repeat process/server/provider teardown.
    private var stopOperation: StopOperation?
    private var stopWaiterCounts: [UUID: Int] = [:]
    /// Internal, inert-by-default seam used only to freeze a credential-release
    /// transaction at the exact actor-reentrancy boundary covered by tests.
    private var stopCleanupCheckpointForTesting: (@Sendable (String) async -> Void)?
    /// Reports whether a test caller joined an existing stop operation. The
    /// hook is absent in production and does not influence lifecycle behavior.
    private var stopJoinCheckpointForTesting: (@Sendable (Bool) async -> Void)?
    /// Coordinates the shared-list/late-delete reentrancy edge in tests. The
    /// nil production path adds no provider request or persisted state.
    private var webhookCleanupRaceCheckpointForTesting:
        (@Sendable (WebhookCleanupRaceCheckpoint) async -> Void)?

    /// `webhookId` is retained as a compatibility mirror for existing installs
    /// and diagnostics. The array is authoritative because two registrations
    /// can be accepted while an obsolete lifecycle call is unwinding across an
    /// actor suspension; every accepted ID must survive that overlap.
    static let webhookIDsPreferenceKey = "webhookIds"
    static let unresolvedRegistrationTokensPreferenceKey =
        "unresolvedWebhookRegistrationTokens"
    static let unresolvedRegistrationAttemptsPreferenceKey =
        "unresolvedWebhookRegistrationAttemptsV1"
    static let webhookRecoveryStatePreferenceKey =
        "webhookRecoveryStateV1"

    static let maxRestartsInWindow = 3
    static let restartWindowSeconds = 300.0  // 5 minutes
    static let heartbeatInterval = 300.0     // 5 minutes
    static let wakeNetworkDelay = 3.0
    private static let registrationTimestampToleranceSeconds: Int64 = 300
    private static let maximumKnownWebhookCount = 1_024
    private static let maximumRegistrationAttemptCount = 64
    private static let maximumRecoveryStateBytes = 512 * 1_024

    init(
        client: any ManusWebhookClientProtocol,
        server: any WebhookServerProtocol,
        processFactory: @escaping @Sendable () -> any TunnelProcessProtocol = {
            CloudflaredProcess()
        },
        preferences: TunnelPreferencesHandle? = .shipping,
        wakeDelay: Duration = .seconds(TunnelManager.wakeNetworkDelay),
        heartbeatDelay: Duration = .seconds(TunnelManager.heartbeatInterval),
        launchCancellationGrace: Duration = .milliseconds(250)
    ) {
        self.client = client
        self.server = server
        self.processFactory = processFactory
        self.preferences = preferences?.defaults
        self.wakeDelay = wakeDelay
        self.heartbeatDelay = heartbeatDelay
        self.launchCancellationGrace = launchCancellationGrace
        let restoredRecoveryState = Self.restoreWebhookRecoveryState(
            from: preferences?.defaults
        )
        self.knownWebhookIDs = restoredRecoveryState.knownWebhookIDs
        self.unresolvedRegistrationTokens =
            restoredRecoveryState.unresolvedRegistrationTokens
        self.unresolvedRegistrationAttempts =
            restoredRecoveryState.unresolvedRegistrationAttempts
        self.unresolvedRegistrationAttemptStateIsCorrupt =
            restoredRecoveryState.isCorrupt
        self.webhookListingOperation = nil
    }

    // MARK: - Public

    func start(
        onEvent: @escaping @Sendable (WebhookPayload) -> Void,
        onRealtimeUnavailable: @escaping @Sendable () async -> Void = {}
    ) async throws {
        guard stopOperation == nil else {
            // A credential-releasing stop owns a terminal epoch. No successor
            // may create a process or remote callback until that transaction
            // has completed and its caller has observed the result.
            throw TunnelError.lifecycleSuperseded
        }
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        _ = await cancelLaunchesAndJoinHeartbeat(
            excludingLifecycleCallback: Self.lifecycleCallbackToken
        )

        do {
            // A direct duplicate start is a replacement, not permission to
            // overwrite `activeTransport`. Stop the old process and confirm
            // deletion before a second registration can leave this actor.
            if activeTransport != nil {
                try await cleanupActiveTransport()
            }
            try requireCurrentLifecycle(generation)
            self.onEventReceived = onEvent
            self.onRealtimeUnavailable = onRealtimeUnavailable
            isServerStarted = true
            try await server.start(onEvent: onEvent)
            try requireCurrentLifecycle(generation)
            try await launchAndRegister(generation: generation)
            installHeartbeat()
        } catch {
            // `start` is transactional: a thrown start never leaves a local
            // server or public transport running behind the caller's back.
            if generation == lifecycleGeneration {
                await stopServerOnly()
            }
            throw error
        }
    }

    /// Full shutdown: stops cloudflared, deletes webhook, stops HTTP server.
    func stop() async throws {
        let callerCallbackToken = Self.lifecycleCallbackToken
        let operation: StopOperation
        let joinedExistingOperation: Bool
        if let existing = stopOperation {
            // An externally-owned stop may be joining this callback. Waiting
            // back on that same stop would form callback <-> stop deadlock.
            if let callerCallbackToken,
               lifecycleCallbackOperations[callerCallbackToken] != nil {
                // Returning Void here would look like a completed credential
                // release even though the externally-owned stop is unresolved.
                // The lifecycle callback intentionally treats this as a
                // deferred/superseded request and never releases credentials.
                throw TunnelError.lifecycleSuperseded
            }
            operation = existing
            joinedExistingOperation = true
            stopWaiterCounts[existing.token, default: 0] += 1
        } else {
            let token = UUID()
            let task = Task.detached { [self] in
                try await performStop(
                    excludingLifecycleCallback: callerCallbackToken
                )
            }
            let created = StopOperation(token: token, task: task)
            stopOperation = created
            stopWaiterCounts[token] = 1
            operation = created
            joinedExistingOperation = false
        }

        if let stopJoinCheckpointForTesting {
            await stopJoinCheckpointForTesting(joinedExistingOperation)
        }
        let stopError: (any Error)?
        do {
            try await operation.task.value
            stopError = nil
        } catch {
            stopError = error
        }
        if callerCallbackToken == nil {
            await joinLifecycleCallbacks()
        }
        releaseStopWaiter(ifMatching: operation.token)
        if let stopError {
            throw stopError
        }
    }

    /// The retained stop task is the only owner of this transaction. Keeping
    /// the implementation separate prevents it from recursively joining its
    /// own single-flight slot.
    private func performStop(
        excludingLifecycleCallback callbackToken: UUID?
    ) async throws {
        lifecycleGeneration &+= 1
        let launchOperations = await cancelLaunchesAndJoinHeartbeat(
            excludingLifecycleCallback: callbackToken
        )
        var firstCleanupError: Error?
        let deletionAttemptSequenceAtStart = webhookDeletionAttemptSequence
        let deletionOperationsAtStart = Array(webhookDeletionOperations.values)
        var attemptedWebhookIDs: Set<String> = []
        if let activeWebhookID = activeTransport?.webhookID {
            attemptedWebhookIDs.insert(activeWebhookID)
            do {
                try await cleanupActiveTransport()
            } catch {
                firstCleanupError = error
            }
        }
        // A heartbeat or suspend can already own a stored-ID delete when a
        // credential-releasing stop begins. Join that exact operation and its
        // result; merely skipping its ID could let stop return success while
        // the provider delete later fails after the credential is released.
        for operation in deletionOperationsAtStart
            where !attemptedWebhookIDs.contains(operation.webhookID) {
            attemptedWebhookIDs.insert(operation.webhookID)
            do {
                try await awaitWebhookDeletionOperation(operation)
            } catch {
                if firstCleanupError == nil {
                    firstCleanupError = error
                }
            }
        }
        for operation in launchOperations {
            let completed = await waitForLaunchCompletion(
                operation,
                timeout: launchCancellationGrace
            )
            guard completed else {
                if firstCleanupError == nil {
                    firstCleanupError = TunnelError.webhookCleanupFailed(
                        underlying: WebhookCleanupInvariantError.registrationOutcomeUnresolved
                    )
                }
                continue
            }
            do {
                try await operation.task.value
            } catch let error as TunnelError {
                if case .webhookCleanupFailed = error,
                   firstCleanupError == nil {
                    firstCleanupError = error
                }
            } catch {
                // A launch/process/registration failure before an accepted ID
                // needs no credential-backed cleanup.
            }
        }
        // Joined launch operations can expose a deletion that was not present
        // at stop entry. Drain every still-running unique operation once.
        while let operation = webhookDeletionOperations.values.first {
            attemptedWebhookIDs.insert(operation.webhookID)
            do {
                try await awaitWebhookDeletionOperation(operation)
            } catch {
                if firstCleanupError == nil {
                    firstCleanupError = error
                }
            }
        }
        // A superseded registration can finish while the active transport is
        // stopping. Attempt every other persisted ID once, but do not turn one
        // explicit stop into an unbounded retry loop for a failed provider call.
        for webhookID in knownWebhookIDs {
            guard knownWebhookIDs.contains(webhookID) else { continue }
            let attemptStartedDuringStop =
                latestWebhookDeletionAttemptByID[webhookID, default: 0]
                > deletionAttemptSequenceAtStart
            guard !attemptedWebhookIDs.contains(webhookID),
                  !attemptStartedDuringStop else { continue }
            attemptedWebhookIDs.insert(webhookID)
            do {
                try await deleteKnownWebhook(webhookID)
                if let stopCleanupCheckpointForTesting {
                    await stopCleanupCheckpointForTesting(webhookID)
                }
            } catch {
                if firstCleanupError == nil {
                    firstCleanupError = error
                }
            }
        }
        // A prior process can die after the provider accepted a registration
        // but before its ID reached this process. Once every still-live launch
        // owner has been joined or explicitly retained, use the durable URL
        // identity to recover only orphan callbacks owned by finished attempts.
        do {
            try await reconcileUnresolvedRegistrationOutcomes()
        } catch {
            if firstCleanupError == nil {
                firstCleanupError = error
            }
        }
        // `start()` and credential-releasing `stop()` can already be waiting
        // on the same account-level list operation. If the start waiter resumes
        // first, it can atomically bind a recovered ID and create its delete
        // operation after stop's entry-time drains, while stop's stale unbound
        // snapshot correctly declines to attribute the attempt a second time.
        // Join every such late operation before evaluating the terminal gate;
        // otherwise a successful provider delete can race with stop and be
        // misreported as `persistedWebhookIDsRemain`.
        while let operation = webhookDeletionOperations.values.first {
            do {
                try await awaitWebhookDeletionOperation(operation)
            } catch {
                if firstCleanupError == nil {
                    firstCleanupError = error
                }
            }
        }
        await stopServerOnly()
        onEventReceived = nil
        onRealtimeUnavailable = nil
        IslandLogger.tunnel.info("TunnelManager stopped")
        if let firstCleanupError {
            throw firstCleanupError
        }
        guard knownWebhookIDs.isEmpty,
              unresolvedRegistrationTokens.isEmpty,
              unresolvedRegistrationAttempts.isEmpty,
              !unresolvedRegistrationAttemptStateIsCorrupt,
              webhookLaunchOperations.isEmpty,
              webhookDeletionOperations.isEmpty,
              webhookListingOperation == nil else {
            IslandLogger.tunnel.warning(
                "TunnelManager stop retained unresolved webhook cleanup state"
            )
            throw TunnelError.webhookCleanupFailed(
                underlying: knownWebhookIDs.isEmpty
                    ? WebhookCleanupInvariantError.registrationOutcomeUnresolved
                    : WebhookCleanupInvariantError.persistedWebhookIDsRemain
            )
        }
    }

    /// Sleep-only suspend: stops cloudflared and cleans webhook,
    /// but keeps the local WebhookServer alive so it can accept connections on wake.
    func suspend() async {
        guard stopOperation == nil else { return }
        lifecycleGeneration &+= 1
        _ = await cancelLaunchesAndJoinHeartbeat(
            excludingLifecycleCallback: Self.lifecycleCallbackToken
        )
        if activeTransport != nil {
            try? await cleanupActiveTransport()
        } else {
            try? await cleanupStoredWebhook()
        }
        IslandLogger.tunnel.info("TunnelManager suspended (server kept alive)")
    }

    /// Called on system wake. Restarts cloudflared and re-registers webhook.
    /// The caller must handle failure by entering polling-only mode; a wake
    /// failure is never swallowed or represented as a healthy connection.
    func handleSleepWake() async throws {
        guard stopOperation == nil else {
            throw TunnelError.lifecycleSuperseded
        }
        IslandLogger.tunnel.info("Wake detected — restarting tunnel")
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        _ = await cancelLaunchesAndJoinHeartbeat(
            excludingLifecycleCallback: Self.lifecycleCallbackToken
        )
        if activeTransport != nil {
            try await cleanupActiveTransport()
        }
        try requireCurrentLifecycle(generation)
        try await Task.sleep(for: wakeDelay)
        do {
            try requireCurrentLifecycle(generation)
            try await launchAndRegister(generation: generation)
            installHeartbeat()
        } catch {
            try? await cleanupActiveTransport()
            throw error
        }
    }

    func statusSnapshot() -> TunnelRuntimeStatus {
        if activeTransport != nil { return .registered }
        if isServerStarted { return .serverOnly }
        return .stopped
    }

    /// Internal ordering probe for deterministic actor-reentrancy regression
    /// tests. It exposes no provider data or production capability.
    func lifecycleGenerationSnapshot() -> UInt64 {
        lifecycleGeneration
    }

    func setStopCleanupCheckpointForTesting(
        _ checkpoint: (@Sendable (String) async -> Void)?
    ) {
        stopCleanupCheckpointForTesting = checkpoint
    }

    func setStopJoinCheckpointForTesting(
        _ checkpoint: (@Sendable (Bool) async -> Void)?
    ) {
        stopJoinCheckpointForTesting = checkpoint
    }

    func setWebhookCleanupRaceCheckpointForTesting(
        _ checkpoint:
            (@Sendable (WebhookCleanupRaceCheckpoint) async -> Void)?
    ) {
        webhookCleanupRaceCheckpointForTesting = checkpoint
    }

    // MARK: - Lifecycle internals

    private func releaseStopWaiter(ifMatching token: UUID) {
        guard let count = stopWaiterCounts[token], count > 0 else { return }
        if count == 1 {
            stopWaiterCounts[token] = nil
            if stopOperation?.token == token {
                stopOperation = nil
            }
        } else {
            stopWaiterCounts[token] = count - 1
        }
    }

    private func launchAndRegister(generation: UInt64) async throws {
        try await reconcileUnresolvedRegistrationOutcomes()
        try requireCurrentLifecycle(generation)
        try requireNoUnresolvedRegistrationOutcome()
        let token = UUID()
        let task = Task { [self] in
            do {
                try await performLaunchAndRegister(
                    generation: generation,
                    operationToken: token
                )
                clearLaunchOperation(ifMatching: token)
            } catch {
                clearLaunchOperation(ifMatching: token)
                throw error
            }
        }
        let operation = WebhookLaunchOperation(
            token: token,
            task: task,
            process: nil,
            processStopRequested: false
        )
        webhookLaunchOperations[token] = operation

        try await withTaskCancellationHandler {
            // Waiting directly on `task.value` is not cancellation-aware when
            // a provider fixture ignores cancellation. Polling the actor-owned
            // slot lets a retired heartbeat leave immediately while the launch
            // owner remains retained for late-ID compensation.
            while webhookLaunchOperations[token] != nil {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(2))
            }
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func performLaunchAndRegister(
        generation: UInt64,
        operationToken: UUID
    ) async throws {
        try requireCurrentLaunch(operationToken, generation: generation)
        // A prior crash or failed delete may have left a public callback. A
        // replacement is forbidden until Manus confirms that exact ID is
        // gone; otherwise each retry can accumulate an unreachable webhook.
        try await cleanupStoredWebhook()
        try requireCurrentLaunch(operationToken, generation: generation)
        guard await server.isReady() else {
            IslandLogger.tunnel.error("WebhookServer readiness proof failed")
            throw TunnelError.serverUnavailable
        }
        try requireCurrentLaunch(operationToken, generation: generation)
        guard shouldAllowRestart() else {
            IslandLogger.tunnel.error("Too many tunnel restarts in the last 5 minutes")
            throw TunnelError.tooManyRestarts
        }

        restartTimestamps.append(Date.now)

        let process = processFactory()
        attachProcess(process, toLaunch: operationToken)
        IslandLogger.tunnel.info("Starting cloudflared tunnel")
        let publicURL: URL
        do {
            publicURL = try await process.start()
        } catch {
            // `start()` may fail after the child process was launched (for
            // example while waiting for its URL). Always close that process.
            await stopLaunchProcess(operationToken)
            IslandLogger.tunnel.error("cloudflared failed to start")
            throw error
        }
        do {
            try requireCurrentLaunch(operationToken, generation: generation)
        } catch {
            await stopLaunchProcess(operationToken)
            throw error
        }
        IslandLogger.tunnel.info("Cloudflare tunnel URL acquired")

        let webhookURL = publicURL.appendingPathComponent("/webhook").absoluteString
        let publicKey: String
        do {
            publicKey = try await client.webhookPublicKey()
        } catch {
            await stopLaunchProcess(operationToken)
            IslandLogger.tunnel.error("Manus webhook trust refresh failed")
            throw TunnelError.trustConfigurationFailed(underlying: error)
        }
        do {
            try requireCurrentLaunch(operationToken, generation: generation)
        } catch {
            await stopLaunchProcess(operationToken)
            throw error
        }
        do {
            try await server.configure(
                externalURL: webhookURL,
                signaturePublicKeyPEM: publicKey
            )
        } catch {
            await stopLaunchProcess(operationToken)
            IslandLogger.tunnel.error("Webhook verifier configuration failed")
            throw TunnelError.trustConfigurationFailed(underlying: error)
        }
        do {
            try requireCurrentLaunch(operationToken, generation: generation)
        } catch {
            await stopLaunchProcess(operationToken)
            throw error
        }
        let serverReadyBeforeRegistration = await server.isReady()
        do {
            try requireCurrentLaunch(operationToken, generation: generation)
        } catch {
            await stopLaunchProcess(operationToken)
            throw error
        }
        guard serverReadyBeforeRegistration else {
            await stopLaunchProcess(operationToken)
            IslandLogger.tunnel.error("WebhookServer became unavailable before registration")
            throw TunnelError.serverUnavailable
        }

        do {
            try beginRegistrationOutcomeTracking(
                operationToken,
                callbackURL: webhookURL
            )
        } catch {
            await stopLaunchProcess(operationToken)
            throw error
        }
        let webhookID: String
        do {
            webhookID = try await client.registerWebhook(publicURL: webhookURL)
        } catch {
            // The quick tunnel has no realtime value without a registered
            // webhook. Stop it immediately instead of letting heartbeat treat
            // a live process as a live Manus connection.
            let disposition = await client.registrationFailureDisposition(for: error)
            if disposition == .definitivelyRejected {
                do {
                    try resolveRegistrationOutcome(operationToken)
                } catch {
                    await stopLaunchProcess(operationToken)
                    throw error
                }
            }
            await stopLaunchProcess(operationToken)
            IslandLogger.tunnel.error("Manus webhook registration failed")
            throw TunnelError.registrationFailed(underlying: error)
        }

        // Persist the cleanup capability immediately. Every branch below
        // may suspend or fail, including lifecycle supersession and a local
        // readiness loss after Manus has already accepted the registration.
        do {
            try recordAcceptedWebhookID(
                webhookID,
                resolvingRegistrationToken: operationToken.uuidString
            )
        } catch {
            // The remote registration may be live, but the durable attempt
            // marker remains sufficient to recover it by exact callback URL.
            // Do not issue an unjournaled delete from this process.
            await stopLaunchProcess(operationToken)
            throw error
        }

        do {
            try requireCurrentLaunch(operationToken, generation: generation)
            // An obsolete registration can finish after this lifecycle already
            // passed its preflight cleanup. Drain every older accepted ID before
            // promoting the new callback so replacement remains fail-closed.
            try await cleanupKnownWebhooks(excluding: webhookID)
            try requireCurrentLifecycle(generation)
        } catch {
            // Stop/suspend can interleave while registration is in flight.
            // If Manus accepted that now-obsolete request, delete it before
            // returning so no orphan public endpoint survives the race.
            await stopLaunchProcess(operationToken)
            do {
                try await deleteKnownWebhook(webhookID)
            } catch {
                throw error
            }
            throw error
        }
        let serverReadyAfterRegistration = await server.isReady()
        do {
            try requireCurrentLaunch(operationToken, generation: generation)
        } catch {
            await stopLaunchProcess(operationToken)
            do {
                try await deleteKnownWebhook(webhookID)
            } catch {
                throw error
            }
            throw error
        }
        guard serverReadyAfterRegistration else {
            await stopLaunchProcess(operationToken)
            do {
                try await deleteKnownWebhook(webhookID)
            } catch {
                throw error
            }
            IslandLogger.tunnel.error("WebhookServer became unavailable after registration")
            throw TunnelError.serverUnavailable
        }

        detachProcessFromLaunch(operationToken)
        activeTransport = RegisteredTransport(
            token: UUID(),
            process: process,
            webhookID: webhookID
        )
        IslandLogger.tunnel.info("Manus webhook registered")
    }

    private func clearLaunchOperation(ifMatching token: UUID) {
        guard webhookLaunchOperations[token]?.token == token else { return }
        webhookLaunchOperations[token] = nil
    }

    private func requireCurrentLaunch(
        _ token: UUID,
        generation: UInt64
    ) throws {
        try Task.checkCancellation()
        try requireCurrentLifecycle(generation)
        guard webhookLaunchOperations[token]?.token == token else {
            throw TunnelError.lifecycleSuperseded
        }
    }

    private func attachProcess(
        _ process: any TunnelProcessProtocol,
        toLaunch token: UUID
    ) {
        guard var operation = webhookLaunchOperations[token] else { return }
        operation.process = process
        webhookLaunchOperations[token] = operation
    }

    private func detachProcessFromLaunch(_ token: UUID) {
        guard var operation = webhookLaunchOperations[token] else { return }
        operation.process = nil
        webhookLaunchOperations[token] = operation
    }

    private func stopLaunchProcess(_ token: UUID) async {
        guard var operation = webhookLaunchOperations[token],
              !operation.processStopRequested,
              let process = operation.process else { return }
        operation.processStopRequested = true
        webhookLaunchOperations[token] = operation
        await process.stop()
    }

    /// Atomically retires the current heartbeat, then interrupts every launch
    /// it could be awaiting before joining it. The ordering prevents a blocked,
    /// cancellation-unaware registration from turning strict heartbeat join
    /// into a self-sustaining deadlock.
    private func cancelLaunchesAndJoinHeartbeat(
        excludingLifecycleCallback callbackToken: UUID?
    ) async -> [WebhookLaunchOperation] {
        retireCurrentHeartbeat()
        let launches = await cancelLaunchOperationsAndStopProcesses()
        await joinRetiringHeartbeats()
        // A retiring heartbeat can publish its callback immediately before its
        // task returns. Snapshot only after the strict join, then drain until
        // no non-self callback remains so replacement cannot miss late publish.
        while let operation = lifecycleCallbackOperations.values.first(
            where: { $0.token != callbackToken }
        ) {
            operation.task.cancel()
            await operation.task.value
            if lifecycleCallbackOperations[operation.token]?.token == operation.token {
                lifecycleCallbackOperations[operation.token] = nil
            }
        }
        return launches
    }

    private func cancelLaunchOperationsAndStopProcesses() async
        -> [WebhookLaunchOperation] {
        let launches = Array(webhookLaunchOperations.values)
        for operation in launches {
            operation.task.cancel()
        }
        for operation in launches {
            await stopLaunchProcess(operation.token)
        }
        return launches
    }

    private func joinLifecycleCallbacks() async {
        while let operation = lifecycleCallbackOperations.values.first {
            await operation.task.value
            if lifecycleCallbackOperations[operation.token]?.token == operation.token {
                lifecycleCallbackOperations[operation.token] = nil
            }
        }
    }

    private func waitForLaunchCompletion(
        _ operation: WebhookLaunchOperation,
        timeout: Duration
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while webhookLaunchOperations[operation.token] != nil {
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return true
    }

    private func requireNoUnresolvedRegistrationOutcome() throws {
        guard unresolvedRegistrationTokens.isEmpty,
              unresolvedRegistrationAttempts.isEmpty,
              !unresolvedRegistrationAttemptStateIsCorrupt else {
            throw TunnelError.webhookCleanupFailed(
                underlying: WebhookCleanupInvariantError.registrationOutcomeUnresolved
            )
        }
    }

    private func beginRegistrationOutcomeTracking(
        _ token: UUID,
        callbackURL: String
    ) throws {
        guard !unresolvedRegistrationAttemptStateIsCorrupt,
              let callbackURLSHA256 = Self.callbackURLSHA256(callbackURL) else {
            throw TunnelError.webhookCleanupFailed(
                underlying: WebhookCleanupInvariantError.registrationAttemptPersistenceFailed
            )
        }
        let tokenString = token.uuidString
        let attempt = UnresolvedWebhookRegistrationAttempt(
            version: UnresolvedWebhookRegistrationAttempt.schemaVersion,
            token: tokenString,
            callbackURLSHA256: callbackURLSHA256,
            startedAtUnixSeconds: max(0, Int64(Date.now.timeIntervalSince1970)),
            discoveredWebhookIDs: []
        )
        try commitWebhookRecoveryState {
            unresolvedRegistrationTokens.insert(tokenString)
            unresolvedRegistrationAttempts[tokenString] = attempt
        }
    }

    private func resolveRegistrationOutcome(_ token: UUID) throws {
        try resolveRegistrationOutcome(token.uuidString)
    }

    private func resolveRegistrationOutcome(_ token: String) throws {
        try commitWebhookRecoveryState {
            unresolvedRegistrationAttempts[token] = nil
            unresolvedRegistrationTokens.remove(token)
        }
    }

    /// Commit every cleanup capability through one bounded envelope and verify
    /// the exact bytes can be decoded before any provider-side delete begins.
    /// If persistence is ambiguous, restore the prior in-memory view and mark
    /// the manager corrupt so the current process cannot release credentials.
    private func commitWebhookRecoveryState(
        _ mutation: () -> Void
    ) throws {
        guard !unresolvedRegistrationAttemptStateIsCorrupt else {
            throw TunnelError.webhookCleanupFailed(
                underlying: WebhookCleanupInvariantError.registrationAttemptPersistenceFailed
            )
        }

        let previousKnownWebhookIDs = knownWebhookIDs
        let previousTokens = unresolvedRegistrationTokens
        let previousAttempts = unresolvedRegistrationAttempts
        mutation()

        guard Self.validateWebhookRecoveryState(
            knownWebhookIDs: knownWebhookIDs,
            unresolvedRegistrationTokens: unresolvedRegistrationTokens,
            unresolvedRegistrationAttempts: unresolvedRegistrationAttempts
        ), persistWebhookRecoveryStateWithReadback() else {
            knownWebhookIDs = previousKnownWebhookIDs
            unresolvedRegistrationTokens = previousTokens
            unresolvedRegistrationAttempts = previousAttempts
            unresolvedRegistrationAttemptStateIsCorrupt = true
            throw TunnelError.webhookCleanupFailed(
                underlying: WebhookCleanupInvariantError.registrationAttemptPersistenceFailed
            )
        }
    }

    private func persistWebhookRecoveryStateWithReadback() -> Bool {
        guard let preferences else { return true }
        let envelope = WebhookRecoveryStateEnvelope(
            version: WebhookRecoveryStateEnvelope.schemaVersion,
            knownWebhookIDs: knownWebhookIDs,
            unresolvedRegistrationTokens: unresolvedRegistrationTokens.sorted(),
            unresolvedRegistrationAttempts:
                unresolvedRegistrationAttempts.values.sorted {
                    $0.token < $1.token
                }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(envelope),
              !data.isEmpty,
              data.count <= Self.maximumRecoveryStateBytes else {
            return false
        }

        preferences.set(data, forKey: Self.webhookRecoveryStatePreferenceKey)
        // This state is a crash-recovery journal, not ordinary UI preference
        // data. Force the pending CFPreferences write to its persistent domain
        // before readback and before any provider-side delete. The single Data
        // value remains the only authoritative transaction unit.
        guard preferences.synchronize() else { return false }
        guard let rawReadback = preferences.object(
            forKey: Self.webhookRecoveryStatePreferenceKey
        ) as? Data,
              let restored = Self.decodeWebhookRecoveryStateEnvelope(rawReadback),
              restored.knownWebhookIDs == knownWebhookIDs,
              restored.unresolvedRegistrationTokens
                == unresolvedRegistrationTokens,
              restored.unresolvedRegistrationAttempts
                == unresolvedRegistrationAttempts else {
            return false
        }

        // These keys are compatibility mirrors for diagnostics and existing
        // tests. Recovery never trusts them once the envelope exists.
        persistLegacyRecoveryMirrors(to: preferences)
        return true
    }

    private func persistLegacyRecoveryMirrors(to preferences: UserDefaults) {
        if let firstWebhookID = knownWebhookIDs.first {
            preferences.set(firstWebhookID, forKey: Self.webhookIDPreferenceKey)
            preferences.set(knownWebhookIDs, forKey: Self.webhookIDsPreferenceKey)
        } else {
            preferences.removeObject(forKey: Self.webhookIDPreferenceKey)
            preferences.removeObject(forKey: Self.webhookIDsPreferenceKey)
        }

        let sortedTokens = unresolvedRegistrationTokens.sorted()
        if sortedTokens.isEmpty {
            preferences.removeObject(
                forKey: Self.unresolvedRegistrationTokensPreferenceKey
            )
        } else {
            preferences.set(
                sortedTokens,
                forKey: Self.unresolvedRegistrationTokensPreferenceKey
            )
        }

        let sortedAttempts = unresolvedRegistrationAttempts.values.sorted {
            $0.token < $1.token
        }
        if sortedAttempts.isEmpty {
            preferences.removeObject(
                forKey: Self.unresolvedRegistrationAttemptsPreferenceKey
            )
        } else if let data = Self.encodeUnresolvedRegistrationAttempts(
            sortedAttempts
        ) {
            preferences.set(
                data,
                forKey: Self.unresolvedRegistrationAttemptsPreferenceKey
            )
        }
    }

    private static func encodeUnresolvedRegistrationAttempts(
        _ attempts: [UnresolvedWebhookRegistrationAttempt]
    ) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(attempts)
    }

    private static func decodeUnresolvedRegistrationAttempts(
        _ data: Data?
    ) -> (
        attempts: [String: UnresolvedWebhookRegistrationAttempt],
        isCorrupt: Bool
    ) {
        guard let data else { return ([:], false) }
        guard !data.isEmpty, data.count <= maximumRecoveryStateBytes,
              let decoded = try? JSONDecoder().decode(
                [UnresolvedWebhookRegistrationAttempt].self,
                from: data
              ),
              !decoded.isEmpty,
              decoded.count <= maximumRegistrationAttemptCount else {
            return ([:], true)
        }
        var attempts: [String: UnresolvedWebhookRegistrationAttempt] = [:]
        for attempt in decoded {
            guard attempt.version
                    == UnresolvedWebhookRegistrationAttempt.schemaVersion,
                  UUID(uuidString: attempt.token) != nil,
                  attempt.callbackURLSHA256.count == 64,
                  attempt.callbackURLSHA256.allSatisfy({
                      "0123456789abcdef".contains($0)
                  }),
                  attempt.startedAtUnixSeconds >= 0,
                  attempt.discoveredWebhookIDs.count
                    <= maximumKnownWebhookCount,
                  Set(attempt.discoveredWebhookIDs).count
                    == attempt.discoveredWebhookIDs.count,
                  attempt.discoveredWebhookIDs.allSatisfy({
                    ManusRemoteContentPolicy.isValidOpaqueIdentifier($0)
                  }),
                  attempts[attempt.token] == nil else {
                return ([:], true)
            }
            attempts[attempt.token] = attempt
        }
        return (attempts, false)
    }

    private static func restoreWebhookRecoveryState(
        from preferences: UserDefaults?
    ) -> (
        knownWebhookIDs: [String],
        unresolvedRegistrationTokens: Set<String>,
        unresolvedRegistrationAttempts:
            [String: UnresolvedWebhookRegistrationAttempt],
        isCorrupt: Bool
    ) {
        guard let preferences else { return ([], [], [:], false) }

        if let envelopeObject = preferences.object(
            forKey: webhookRecoveryStatePreferenceKey
        ) {
            guard let data = envelopeObject as? Data,
                  let state = decodeWebhookRecoveryStateEnvelope(data) else {
                return ([], [], [:], true)
            }
            return (
                state.knownWebhookIDs,
                state.unresolvedRegistrationTokens,
                state.unresolvedRegistrationAttempts,
                false
            )
        }

        var isCorrupt = false
        var knownWebhookIDs: [String] = []
        if let idsObject = preferences.object(forKey: webhookIDsPreferenceKey) {
            guard let ids = idsObject as? [String] else {
                return ([], [], [:], true)
            }
            knownWebhookIDs = ids
        }
        if let legacyIDObject = preferences.object(
            forKey: webhookIDPreferenceKey
        ) {
            guard let legacyID = legacyIDObject as? String else {
                return ([], [], [:], true)
            }
            if knownWebhookIDs.isEmpty {
                knownWebhookIDs = [legacyID]
            } else if knownWebhookIDs.first != legacyID {
                isCorrupt = true
            }
        }

        var unresolvedRegistrationTokens = Set<String>()
        if let tokenObject = preferences.object(
            forKey: unresolvedRegistrationTokensPreferenceKey
        ) {
            guard let tokens = tokenObject as? [String],
                  Set(tokens).count == tokens.count else {
                return ([], [], [:], true)
            }
            unresolvedRegistrationTokens = Set(tokens)
        }

        let attemptState: (
            attempts: [String: UnresolvedWebhookRegistrationAttempt],
            isCorrupt: Bool
        )
        if let attemptObject = preferences.object(
            forKey: unresolvedRegistrationAttemptsPreferenceKey
        ) {
            guard let data = attemptObject as? Data else {
                return ([], [], [:], true)
            }
            attemptState = decodeUnresolvedRegistrationAttempts(data)
        } else {
            attemptState = ([:], false)
        }
        unresolvedRegistrationTokens.formUnion(attemptState.attempts.keys)
        isCorrupt = isCorrupt || attemptState.isCorrupt
        if !validateWebhookRecoveryState(
            knownWebhookIDs: knownWebhookIDs,
            unresolvedRegistrationTokens: unresolvedRegistrationTokens,
            unresolvedRegistrationAttempts: attemptState.attempts
        ) {
            isCorrupt = true
        }
        return (
            knownWebhookIDs,
            unresolvedRegistrationTokens,
            attemptState.attempts,
            isCorrupt
        )
    }

    private static func decodeWebhookRecoveryStateEnvelope(
        _ data: Data
    ) -> (
        knownWebhookIDs: [String],
        unresolvedRegistrationTokens: Set<String>,
        unresolvedRegistrationAttempts:
            [String: UnresolvedWebhookRegistrationAttempt]
    )? {
        guard !data.isEmpty,
              data.count <= maximumRecoveryStateBytes,
              let envelope = try? JSONDecoder().decode(
                WebhookRecoveryStateEnvelope.self,
                from: data
              ),
              envelope.version == WebhookRecoveryStateEnvelope.schemaVersion,
              Set(envelope.unresolvedRegistrationTokens).count
                == envelope.unresolvedRegistrationTokens.count else {
            return nil
        }
        var attempts: [String: UnresolvedWebhookRegistrationAttempt] = [:]
        for attempt in envelope.unresolvedRegistrationAttempts {
            guard attempts[attempt.token] == nil else { return nil }
            attempts[attempt.token] = attempt
        }
        let tokens = Set(envelope.unresolvedRegistrationTokens)
        guard validateWebhookRecoveryState(
            knownWebhookIDs: envelope.knownWebhookIDs,
            unresolvedRegistrationTokens: tokens,
            unresolvedRegistrationAttempts: attempts
        ) else { return nil }
        return (envelope.knownWebhookIDs, tokens, attempts)
    }

    private static func validateWebhookRecoveryState(
        knownWebhookIDs: [String],
        unresolvedRegistrationTokens: Set<String>,
        unresolvedRegistrationAttempts:
            [String: UnresolvedWebhookRegistrationAttempt]
    ) -> Bool {
        guard knownWebhookIDs.count <= maximumKnownWebhookCount,
              Set(knownWebhookIDs).count == knownWebhookIDs.count,
              knownWebhookIDs.allSatisfy({
                ManusRemoteContentPolicy.isValidOpaqueIdentifier($0)
              }),
              unresolvedRegistrationTokens.count
                <= maximumRegistrationAttemptCount,
              unresolvedRegistrationTokens.allSatisfy({
                UUID(uuidString: $0) != nil
              }),
              unresolvedRegistrationAttempts.count
                <= maximumRegistrationAttemptCount else {
            return false
        }

        let knownIDs = Set(knownWebhookIDs)
        var discoveredIDs = Set<String>()
        for (token, attempt) in unresolvedRegistrationAttempts {
            guard token == attempt.token,
                  unresolvedRegistrationTokens.contains(token),
                  attempt.version
                    == UnresolvedWebhookRegistrationAttempt.schemaVersion,
                  UUID(uuidString: token) != nil,
                  attempt.callbackURLSHA256.count == 64,
                  attempt.callbackURLSHA256.allSatisfy({
                    "0123456789abcdef".contains($0)
                  }),
                  attempt.startedAtUnixSeconds >= 0,
                  attempt.discoveredWebhookIDs.count
                    <= maximumKnownWebhookCount,
                  Set(attempt.discoveredWebhookIDs).count
                    == attempt.discoveredWebhookIDs.count,
                  attempt.discoveredWebhookIDs.allSatisfy({ id in
                    ManusRemoteContentPolicy.isValidOpaqueIdentifier(id)
                        && knownIDs.contains(id)
                        && discoveredIDs.insert(id).inserted
                  }) else {
                return false
            }
        }
        return true
    }

    private static func callbackURLSHA256(_ value: String) -> String? {
        guard value.utf8.count <= 2_048,
              let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              !components.path.isEmpty,
              components.url?.absoluteString == value else {
            return nil
        }
        return SHA256.hash(data: Data(value.utf8)).map {
            String(format: "%02x", $0)
        }.joined()
    }

    private func reconcileUnresolvedRegistrationOutcomes() async throws {
        guard !unresolvedRegistrationAttemptStateIsCorrupt else { return }
        // Never infer ownership while a promoted callback is live. Stop first
        // makes that callback unreachable and records/deletes its exact ID;
        // reconciliation is only for process-death orphans.
        guard activeTransport == nil else { return }
        let activeLaunchTokens = Set(
            webhookLaunchOperations.keys.map(\.uuidString)
        )

        // Once IDs have been observed and atomically bound to an attempt, the
        // provider inventory is no longer needed. Retrying those exact IDs is
        // safe across process death; a strict not_found delete response also
        // completes the at-least-once transaction.
        let boundAttempts = unresolvedRegistrationAttempts.values
            .filter {
                unresolvedRegistrationTokens.contains($0.token)
                    && !activeLaunchTokens.contains($0.token)
                    && !$0.discoveredWebhookIDs.isEmpty
            }
            .sorted { $0.token < $1.token }
        var firstDeletionError: (any Error)?
        for attempt in boundAttempts {
            guard unresolvedRegistrationAttempts[attempt.token] == attempt else {
                continue
            }
            for webhookID in attempt.discoveredWebhookIDs {
                do {
                    try await deleteKnownWebhook(webhookID)
                } catch {
                    if firstDeletionError == nil {
                        firstDeletionError = error
                    }
                }
            }
        }
        if let firstDeletionError {
            throw firstDeletionError
        }

        let unboundAttempts = unresolvedRegistrationAttempts.values
            .filter {
                unresolvedRegistrationTokens.contains($0.token)
                    && !activeLaunchTokens.contains($0.token)
                    && $0.discoveredWebhookIDs.isEmpty
            }
            .sorted { $0.token < $1.token }
        guard !unboundAttempts.isEmpty else { return }

        let webhooks: [ManusWebhook]
        do {
            webhooks = try await listWebhooksForReconciliation()
        } catch {
            throw TunnelError.webhookCleanupFailed(underlying: error)
        }

        let attemptsByCallbackDigest = Dictionary(
            grouping: unboundAttempts,
            by: \.callbackURLSHA256
        )
        var deferredDeletionError: (any Error)?
        for attempt in unboundAttempts {
            guard unresolvedRegistrationAttempts[attempt.token] == attempt,
                  unresolvedRegistrationTokens.contains(attempt.token),
                  attempt.discoveredWebhookIDs.isEmpty,
                  !webhookLaunchOperations.keys.contains(where: {
                      $0.uuidString == attempt.token
                  }),
                  attemptsByCallbackDigest[attempt.callbackURLSHA256]?.count
                    == 1 else {
                // Two unknown provider requests with the same callback cannot
                // be attributed uniquely. Keep both markers and delete none.
                continue
            }
            let earliestCreatedAt = max(
                0,
                attempt.startedAtUnixSeconds
                    - Self.registrationTimestampToleranceSeconds
            )
            let upperBound = attempt.startedAtUnixSeconds.addingReportingOverflow(
                Self.registrationTimestampToleranceSeconds
            )
            let latestCreatedAt = upperBound.overflow
                ? Int64.max
                : upperBound.partialValue
            let matches = webhooks.filter { webhook in
                webhook.status == .active
                    && webhook.createdAt >= earliestCreatedAt
                    && webhook.createdAt <= latestCreatedAt
                    && Self.callbackURLSHA256(webhook.url)
                        == attempt.callbackURLSHA256
            }
            // The provider has not documented read-after-create consistency.
            // An empty snapshot therefore cannot prove that no remote callback
            // exists; keep the durable attempt until live acceptance establishes
            // a safe absence rule.
            guard !matches.isEmpty else { continue }

            // The ID ledger and attempt binding are committed in one envelope
            // and read back before the first remote delete. A crash after this
            // point can retry exact IDs without another ambiguous list match.
            try bindDiscoveredWebhookIDs(
                matches.map(\.id),
                toRegistrationToken: attempt.token
            )
            for webhook in matches {
                do {
                    try await deleteKnownWebhook(webhook.id)
                } catch {
                    if deferredDeletionError == nil {
                        deferredDeletionError = error
                    }
                }
            }
        }
        if let deferredDeletionError {
            throw deferredDeletionError
        }
    }

    private func listWebhooksForReconciliation() async throws
        -> [ManusWebhook] {
        let operation: WebhookListingOperation
        let joinedExisting: Bool
        if let existing = webhookListingOperation {
            operation = existing
            joinedExisting = true
        } else {
            let token = UUID()
            let client = self.client
            let task = Task.detached {
                try await client.listWebhooks()
            }
            let created = WebhookListingOperation(token: token, task: task)
            webhookListingOperation = created
            operation = created
            joinedExisting = false
        }
        if let webhookCleanupRaceCheckpointForTesting {
            await webhookCleanupRaceCheckpointForTesting(
                .listingWillAwait(joinedExisting: joinedExisting)
            )
        }

        do {
            let webhooks = try await operation.task.value
            if let webhookCleanupRaceCheckpointForTesting {
                await webhookCleanupRaceCheckpointForTesting(
                    .listingDidReturn(joinedExisting: joinedExisting)
                )
            }
            clearWebhookListingOperation(ifMatching: operation.token)
            return webhooks
        } catch {
            clearWebhookListingOperation(ifMatching: operation.token)
            throw error
        }
    }

    private func clearWebhookListingOperation(ifMatching token: UUID) {
        guard webhookListingOperation?.token == token else { return }
        webhookListingOperation = nil
    }

    private func cleanupActiveTransport() async throws {
        guard let transport = activeTransport else { return }
        activeTransport = nil
        // Make the public callback unreachable before asking Manus to delete
        // it. A failed delete remains persisted for the next explicit retry.
        await transport.process.stop()
        try await deleteKnownWebhook(transport.webhookID)
    }

    private func cleanupStoredWebhook() async throws {
        guard activeTransport == nil else { return }
        try await cleanupKnownWebhooks(excluding: nil)
    }

    private func cleanupKnownWebhooks(excluding retainedID: String?) async throws {
        while let storedID = knownWebhookIDs.first(where: { $0 != retainedID }) {
            try await deleteKnownWebhook(storedID)
        }
    }

    /// Delete one persisted registration exactly once across reentrant
    /// lifecycle callers. The local ID is cleared only after the provider
    /// confirms success; every failure remains a retryable, fail-closed state.
    private func deleteKnownWebhook(_ id: String) async throws {
        try recordKnownWebhookID(id)

        let operation: WebhookDeletionOperation
        if let existing = webhookDeletionOperations[id] {
            operation = existing
        } else {
            let token = UUID()
            let client = self.client
            webhookDeletionAttemptSequence &+= 1
            latestWebhookDeletionAttemptByID[id] = webhookDeletionAttemptSequence
            let task = Task.detached {
                try await client.deleteWebhook(id: id)
            }
            let created = WebhookDeletionOperation(
                token: token,
                webhookID: id,
                task: task
            )
            webhookDeletionOperations[id] = created
            operation = created
        }

        try await awaitWebhookDeletionOperation(operation)
    }

    /// Multiple lifecycle owners may await the same provider operation. The
    /// token check makes completion idempotent while every waiter still sees
    /// the exact success/failure needed for its own transaction boundary.
    private func awaitWebhookDeletionOperation(
        _ operation: WebhookDeletionOperation
    ) async throws {
        if let webhookCleanupRaceCheckpointForTesting {
            await webhookCleanupRaceCheckpointForTesting(
                .deletionWillAwait(operationToken: operation.token)
            )
        }
        do {
            try await operation.task.value
            if webhookDeletionOperations[operation.webhookID]?.token == operation.token {
                webhookDeletionOperations[operation.webhookID] = nil
                try clearKnownWebhookID(operation.webhookID)
                IslandLogger.tunnel.info("Manus webhook deleted")
            }
        } catch {
            if webhookDeletionOperations[operation.webhookID]?.token == operation.token {
                webhookDeletionOperations[operation.webhookID] = nil
                IslandLogger.tunnel.warning("Failed to delete Manus webhook")
            }
            throw TunnelError.webhookCleanupFailed(underlying: error)
        }
    }

    private func recordAcceptedWebhookID(
        _ id: String,
        resolvingRegistrationToken token: String
    ) throws {
        guard ManusRemoteContentPolicy.isValidOpaqueIdentifier(id),
              !knownWebhookIDs.contains(id),
              unresolvedRegistrationTokens.contains(token),
              unresolvedRegistrationAttempts[token] != nil else {
            throw TunnelError.webhookCleanupFailed(
                underlying: WebhookCleanupInvariantError.registrationAttemptPersistenceFailed
            )
        }
        try commitWebhookRecoveryState {
            if !knownWebhookIDs.contains(id) {
                knownWebhookIDs.append(id)
            }
            unresolvedRegistrationAttempts[token] = nil
            unresolvedRegistrationTokens.remove(token)
        }
    }

    private func bindDiscoveredWebhookIDs(
        _ ids: [String],
        toRegistrationToken token: String
    ) throws {
        guard !ids.isEmpty,
              ids.count <= Self.maximumKnownWebhookCount,
              Set(ids).count == ids.count,
              ids.allSatisfy({
                ManusRemoteContentPolicy.isValidOpaqueIdentifier($0)
              }),
              let attempt = unresolvedRegistrationAttempts[token],
              attempt.discoveredWebhookIDs.isEmpty,
              unresolvedRegistrationTokens.contains(token) else {
            throw TunnelError.webhookCleanupFailed(
                underlying: WebhookCleanupInvariantError.registrationAttemptPersistenceFailed
            )
        }
        let alreadyOwnedIDs = Set(
            unresolvedRegistrationAttempts.values
                .filter { $0.token != token }
                .flatMap(\.discoveredWebhookIDs)
        )
        guard alreadyOwnedIDs.isDisjoint(with: ids) else {
            throw TunnelError.webhookCleanupFailed(
                underlying: WebhookCleanupInvariantError.registrationOutcomeUnresolved
            )
        }

        try commitWebhookRecoveryState {
            for id in ids where !knownWebhookIDs.contains(id) {
                knownWebhookIDs.append(id)
            }
            unresolvedRegistrationAttempts[token] =
                UnresolvedWebhookRegistrationAttempt(
                    version: attempt.version,
                    token: attempt.token,
                    callbackURLSHA256: attempt.callbackURLSHA256,
                    startedAtUnixSeconds: attempt.startedAtUnixSeconds,
                    discoveredWebhookIDs: ids
                )
        }
    }

    private func recordKnownWebhookID(_ id: String) throws {
        guard ManusRemoteContentPolicy.isValidOpaqueIdentifier(id) else {
            throw TunnelError.webhookCleanupFailed(
                underlying: WebhookCleanupInvariantError.registrationAttemptPersistenceFailed
            )
        }
        guard !knownWebhookIDs.contains(id) else { return }
        try commitWebhookRecoveryState {
            knownWebhookIDs.append(id)
        }
    }

    private func clearKnownWebhookID(_ id: String) throws {
        guard knownWebhookIDs.contains(id) else { return }
        let owningTokens = unresolvedRegistrationAttempts.values
            .filter { $0.discoveredWebhookIDs.contains(id) }
            .map(\.token)
        try commitWebhookRecoveryState {
            knownWebhookIDs.removeAll { $0 == id }
            for token in owningTokens {
                guard let attempt = unresolvedRegistrationAttempts[token] else {
                    continue
                }
                let remainingIDs = attempt.discoveredWebhookIDs.filter {
                    $0 != id
                }
                if remainingIDs.isEmpty {
                    unresolvedRegistrationAttempts[token] = nil
                    unresolvedRegistrationTokens.remove(token)
                } else {
                    unresolvedRegistrationAttempts[token] =
                        UnresolvedWebhookRegistrationAttempt(
                            version: attempt.version,
                            token: attempt.token,
                            callbackURLSHA256: attempt.callbackURLSHA256,
                            startedAtUnixSeconds: attempt.startedAtUnixSeconds,
                            discoveredWebhookIDs: remainingIDs
                        )
                }
            }
        }
        latestWebhookDeletionAttemptByID[id] = nil
    }

    private func stopServerOnly() async {
        guard isServerStarted else { return }
        await server.stop()
        isServerStarted = false
    }

    private func shouldAllowRestart() -> Bool {
        let windowStart = Date.now.addingTimeInterval(-Self.restartWindowSeconds)
        restartTimestamps = restartTimestamps.filter { $0 > windowStart }
        return restartTimestamps.count < Self.maxRestartsInWindow
    }

    private func requireCurrentLifecycle(_ generation: UInt64) throws {
        guard generation == lifecycleGeneration else {
            throw TunnelError.lifecycleSuperseded
        }
    }

    private func retireCurrentHeartbeat() {
        guard let operation = heartbeatOperation else { return }
        heartbeatOperation = nil
        retiringHeartbeatOperations[operation.token] = operation
        operation.task.cancel()
    }

    private func retireHeartbeat(ifMatching token: UUID) {
        guard let operation = heartbeatOperation,
              operation.token == token else { return }
        heartbeatOperation = nil
        retiringHeartbeatOperations[token] = operation
        operation.task.cancel()
    }

    private func joinRetiringHeartbeats() async {
        let operations = Array(retiringHeartbeatOperations.values)
        for operation in operations {
            await operation.task.value
            if retiringHeartbeatOperations[operation.token]?.token == operation.token {
                retiringHeartbeatOperations[operation.token] = nil
            }
        }
    }

    private func finishHeartbeat(_ token: UUID) {
        if heartbeatOperation?.token == token {
            heartbeatOperation = nil
        }
        retiringHeartbeatOperations[token] = nil
    }

    private func scheduleLifecycleCallback(
        _ callback: @escaping @Sendable () async -> Void
    ) -> LifecycleCallbackOperation {
        let token = UUID()
        let task = Task<Void, Never> { [weak self] in
            guard let self,
                  await self.lifecycleCallbackMayStart(token),
                  !Task.isCancelled else {
                await self?.finishLifecycleCallback(token)
                return
            }
            await Self.$lifecycleCallbackToken.withValue(token) {
                await callback()
            }
            await self.finishLifecycleCallback(token)
        }
        let operation = LifecycleCallbackOperation(token: token, task: task)
        lifecycleCallbackOperations[token] = operation
        return operation
    }

    private func lifecycleCallbackMayStart(_ token: UUID) -> Bool {
        lifecycleCallbackOperations[token]?.token == token
    }

    private func finishLifecycleCallback(_ token: UUID) {
        guard lifecycleCallbackOperations[token]?.token == token else { return }
        lifecycleCallbackOperations[token] = nil
    }

    private func isCurrentHeartbeat(_ token: UUID) -> Bool {
        heartbeatOperation?.token == token
    }

    private func installHeartbeat() {
        guard activeTransport != nil, heartbeatOperation == nil else { return }
        let token = UUID()
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.runHeartbeat(token: token)
        }
        heartbeatOperation = HeartbeatOperation(token: token, task: task)
    }

    private func runHeartbeat(token: UUID) async {
        while !Task.isCancelled, isCurrentHeartbeat(token) {
            do {
                try await Task.sleep(for: heartbeatDelay)
            } catch {
                break
            }
            guard !Task.isCancelled, isCurrentHeartbeat(token) else { break }
            let generation = lifecycleGeneration
            let callback = await performProcessHealthCheck(
                heartbeatToken: token,
                generation: generation
            )
            guard isCurrentHeartbeat(token) else {
                let callbackOperation = callback.map(scheduleLifecycleCallback)
                finishHeartbeat(token)
                // The callback slot is installed before heartbeat ownership is
                // released, closing the stop-vs-delivery observation gap.
                _ = callbackOperation
                return
            }
        }
        finishHeartbeat(token)
    }

    /// Internal for deterministic lifecycle regression tests. Production only
    /// reaches this method through the bounded heartbeat above.
    func checkProcessHealth() async {
        guard stopOperation == nil else { return }
        _ = await cancelLaunchesAndJoinHeartbeat(
            excludingLifecycleCallback: Self.lifecycleCallbackToken
        )
        let callback = await performProcessHealthCheck(
            heartbeatToken: nil,
            generation: lifecycleGeneration
        )
        if let callback {
            let operation = scheduleLifecycleCallback(callback)
            await operation.task.value
        }
    }

    private func performProcessHealthCheck(
        heartbeatToken: UUID?,
        generation: UInt64
    ) async -> (@Sendable () async -> Void)? {
        guard healthCheckOwnerIsCurrent(
            heartbeatToken,
            generation: generation
        ) else { return nil }
        guard let transport = activeTransport else {
            return await transitionToRealtimeUnavailable(
                heartbeatToken: heartbeatToken,
                generation: generation
            )
        }

        let serverReady = await server.isReady()
        guard healthCheckOwnerIsCurrent(
            heartbeatToken,
            generation: generation,
            transportToken: transport.token
        ) else { return nil }
        guard serverReady else {
            IslandLogger.tunnel.warning("WebhookServer readiness lost — switching to polling-only mode")
            return await transitionToRealtimeUnavailable(
                heartbeatToken: heartbeatToken,
                generation: generation
            )
        }

        let isRunning = await transport.process.isRunning
        guard healthCheckOwnerIsCurrent(
            heartbeatToken,
            generation: generation,
            transportToken: transport.token
        ) else { return nil }
        guard !isRunning else { return nil }

        IslandLogger.tunnel.warning("cloudflared process died — attempting restart")
        lifecycleGeneration &+= 1
        let restartGeneration = lifecycleGeneration
        activeTransport = nil
        await transport.process.stop()
        guard healthCheckOwnerIsCurrent(
            heartbeatToken,
            generation: restartGeneration
        ) else { return nil }

        do {
            try await deleteKnownWebhook(transport.webhookID)
        } catch {
            guard healthCheckOwnerIsCurrent(
                heartbeatToken,
                generation: restartGeneration
            ) else { return nil }
            IslandLogger.tunnel.error(
                "Webhook cleanup failed — replacement registration blocked"
            )
            return await transitionToRealtimeUnavailable(
                heartbeatToken: heartbeatToken,
                generation: restartGeneration
            )
        }
        guard healthCheckOwnerIsCurrent(
            heartbeatToken,
            generation: restartGeneration
        ) else { return nil }

        do {
            // WebhookServer is still running; only cloudflared + webhook need restart.
            try await launchAndRegister(generation: restartGeneration)
            if heartbeatToken == nil {
                installHeartbeat()
            }
        } catch TunnelError.tooManyRestarts {
            guard healthCheckOwnerIsCurrent(
                heartbeatToken,
                generation: restartGeneration
            ) else { return nil }
            IslandLogger.tunnel.error("Giving up on tunnel — switching to polling-only mode")
            return await transitionToRealtimeUnavailable(
                heartbeatToken: heartbeatToken,
                generation: restartGeneration
            )
        } catch {
            guard healthCheckOwnerIsCurrent(
                heartbeatToken,
                generation: restartGeneration
            ) else { return nil }
            IslandLogger.tunnel.error("Tunnel restart failed — switching to polling-only mode")
            return await transitionToRealtimeUnavailable(
                heartbeatToken: heartbeatToken,
                generation: restartGeneration
            )
        }
        return nil
    }

    private func healthCheckOwnerIsCurrent(
        _ heartbeatToken: UUID?,
        generation: UInt64,
        transportToken: UUID? = nil
    ) -> Bool {
        guard lifecycleGeneration == generation else { return false }
        if let heartbeatToken,
           heartbeatOperation?.token != heartbeatToken {
            return false
        }
        if let transportToken,
           activeTransport?.token != transportToken {
            return false
        }
        return true
    }

    private func transitionToRealtimeUnavailable(
        heartbeatToken: UUID?,
        generation: UInt64
    ) async -> (@Sendable () async -> Void)? {
        guard healthCheckOwnerIsCurrent(
            heartbeatToken,
            generation: generation
        ) else { return nil }

        lifecycleGeneration &+= 1
        let transitionGeneration = lifecycleGeneration
        if let heartbeatToken {
            retireHeartbeat(ifMatching: heartbeatToken)
        } else {
            retireCurrentHeartbeat()
        }
        _ = await cancelLaunchOperationsAndStopProcesses()
        guard lifecycleGeneration == transitionGeneration else { return nil }

        if activeTransport != nil {
            try? await cleanupActiveTransport()
        } else {
            try? await cleanupStoredWebhook()
        }
        guard lifecycleGeneration == transitionGeneration,
              let callback = onRealtimeUnavailable else { return nil }
        // Deliver once. The heartbeat owner is removed before this callback is
        // scheduled, so TaskStore may safely call `stop()` without self-join.
        onRealtimeUnavailable = nil
        return callback
    }
}

extension TunnelManager: ManusTunnelLifecycleProtocol {}
