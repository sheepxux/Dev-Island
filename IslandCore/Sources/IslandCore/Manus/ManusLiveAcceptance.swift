import Foundation

/// A low-cardinality, in-memory checklist for the one-time Manus v2 live
/// acceptance run. The CLI feeds this type only after `WebhookServer` has
/// authenticated and decoded a delivery.
///
/// Task and event identifiers are retained only long enough to correlate a
/// stopped event with a task created during the same run. They are never
/// exposed by `Snapshot` and are cleared when local transports stop.
public final class ManusLiveAcceptanceChecklist: @unchecked Sendable {
    public enum Observation: String, Sendable {
        case signedRegistrationProbe = "signed_registration_probe"
        case taskCreated = "task_created"
        case taskStoppedFinish = "task_stopped_finish"
        case taskStoppedAsk = "task_stopped_ask"
    }

    public struct Snapshot: Equatable, Sendable {
        public let trustAnchorValidated: Bool
        public let registrationStarted: Bool
        public let signedRegistrationProbeObserved: Bool
        public let registrationAccepted: Bool
        public let taskCreatedObserved: Bool
        public let taskStoppedFinishObserved: Bool
        public let taskStoppedAskObserved: Bool
        public let webhookDeleted: Bool
        public let transportsStopped: Bool

        public var lifecycleComplete: Bool {
            trustAnchorValidated
                && signedRegistrationProbeObserved
                && registrationAccepted
                && taskCreatedObserved
                && taskStoppedFinishObserved
                && taskStoppedAskObserved
        }

        public var fullyAccepted: Bool {
            lifecycleComplete && webhookDeleted && transportsStopped
        }
    }

    private let lock = NSLock()
    private var trustAnchorValidated = false
    private var registrationStarted = false
    private var registrationInFlight = false
    private var signedRegistrationProbeObserved = false
    private var registrationAccepted = false
    private var taskCreatedObserved = false
    private var taskStoppedFinishObserved = false
    private var taskStoppedAskObserved = false
    private var webhookDeleted = false
    private var transportsStopped = false
    private var createdTaskIDs = Set<String>()

    public init() {}

    public func markTrustAnchorValidated() {
        lock.withLock {
            trustAnchorValidated = true
        }
    }

    public func beginRegistration() {
        lock.withLock {
            registrationStarted = true
            registrationInFlight = true
        }
    }

    public func markRegistrationAccepted() {
        lock.withLock {
            registrationInFlight = false
            registrationAccepted = true
        }
    }

    public func markRegistrationFailed() {
        lock.withLock {
            registrationInFlight = false
        }
    }

    /// Records one already-authenticated delivery and returns only a safe
    /// category when it advances the checklist. No provider identifier or
    /// vendor-authored content crosses this boundary.
    @discardableResult
    public func record(_ payload: WebhookPayload) -> Observation? {
        lock.withLock {
            if registrationInFlight {
                guard !signedRegistrationProbeObserved else { return nil }
                signedRegistrationProbeObserved = true
                return .signedRegistrationProbe
            }

            guard registrationAccepted, !payload.taskId.isEmpty else {
                return nil
            }

            switch payload.data {
            case .created:
                createdTaskIDs.insert(payload.taskId)
                guard !taskCreatedObserved else { return nil }
                taskCreatedObserved = true
                return .taskCreated

            case .stopped(let stopped):
                // A late event from a task that predates this acceptance run
                // must not make the new integration appear complete.
                guard createdTaskIDs.contains(payload.taskId) else { return nil }
                switch stopped.stopReason {
                case .finish:
                    guard !taskStoppedFinishObserved else { return nil }
                    taskStoppedFinishObserved = true
                    return .taskStoppedFinish
                case .ask:
                    guard !taskStoppedAskObserved else { return nil }
                    taskStoppedAskObserved = true
                    return .taskStoppedAsk
                }
            }
        }
    }

    public func markWebhookDeleted() {
        lock.withLock {
            webhookDeleted = true
        }
    }

    public func markTransportsStopped() {
        lock.withLock {
            transportsStopped = true
            createdTaskIDs.removeAll(keepingCapacity: false)
        }
    }

    public var snapshot: Snapshot {
        lock.withLock {
            Snapshot(
                trustAnchorValidated: trustAnchorValidated,
                registrationStarted: registrationStarted,
                signedRegistrationProbeObserved: signedRegistrationProbeObserved,
                registrationAccepted: registrationAccepted,
                taskCreatedObserved: taskCreatedObserved,
                taskStoppedFinishObserved: taskStoppedFinishObserved,
                taskStoppedAskObserved: taskStoppedAskObserved,
                webhookDeleted: webhookDeleted,
                transportsStopped: transportsStopped
            )
        }
    }
}

/// Keeps malformed or terminal-control-bearing values out of the HTTP header
/// before a live acceptance request is attempted. Prefixes are deliberately
/// not pinned: the already-verified v1 account and current v2 documentation
/// use different example formats.
public enum ManusLiveAcceptanceCredential {
    public static let minimumLength = ManusCredentialPolicy.minimumLength
    public static let maximumLength = ManusCredentialPolicy.maximumLength

    public static func validated(_ candidate: String) -> String? {
        ManusCredentialPolicy.validated(candidate)
    }
}

/// Narrow, public seams for the one-time live acceptance harness. They are
/// intentionally separate from the shipping `TunnelManager` protocols: the
/// harness has stricter evidence and cleanup requirements and must remain
/// deterministic under cancellation tests.
public protocol ManusLiveAcceptanceClientProtocol: Sendable {
    func webhookPublicKey() async throws -> String
    func registerWebhook(publicURL: String) async throws -> String
    func deleteWebhook(id: String) async throws
}

public protocol ManusLiveAcceptanceServerProtocol: Sendable {
    func configure(externalURL: String, signaturePublicKeyPEM: String) async throws
    func start(onEvent: @escaping @Sendable (WebhookPayload) -> Void) async throws
    func stop() async
}

public protocol ManusLiveAcceptanceTunnelProtocol: Sendable {
    func start() async throws -> URL
    func stop() async
}

extension ManusAPIClient: ManusLiveAcceptanceClientProtocol {}
extension WebhookServer: ManusLiveAcceptanceServerProtocol {}
extension CloudflaredProcess: ManusLiveAcceptanceTunnelProtocol {}

public enum ManusLiveAcceptanceCheckpoint: String, Sendable {
    case trustAnchorValidated = "trust_anchor_validated"
    case serverStarted = "server_started"
    case tunnelStarted = "tunnel_started"
    case registrationStarted = "registration_started"
    case signedRegistrationProbe = "signed_registration_probe"
    case registrationAccepted = "registration_accepted"
    case taskCreated = "task_created"
    case taskStoppedFinish = "task_stopped_finish"
    case taskStoppedAsk = "task_stopped_ask"
    case webhookDeleted = "webhook_deleted"
    case transportsStopped = "transports_stopped"
    case manualWebhookReviewRequired = "manual_webhook_review_required"
}

public enum ManusLiveAcceptanceFailureStage: String, Sendable {
    case trustAnchor = "trust_anchor"
    case serverStartup = "server_startup"
    case serverConfiguration = "server_configuration"
    case tunnelStartup = "tunnel_startup"
    case registration = "registration"
    case lifecycle = "lifecycle"
}

public enum ManusLiveAcceptanceTermination: Equatable, Sendable {
    case accepted
    case timedOut
    case cancelled
    case failed(ManusLiveAcceptanceFailureStage)
}

public struct ManusLiveAcceptanceReport: Equatable, Sendable {
    public let termination: ManusLiveAcceptanceTermination
    public let snapshot: ManusLiveAcceptanceChecklist.Snapshot
    public let manualWebhookReviewRequired: Bool

    public var accepted: Bool {
        termination == .accepted
            && snapshot.fullyAccepted
            && !manualWebhookReviewRequired
    }
}

/// Transactional runner for the explicit Manus live-account acceptance tool.
///
/// The runner never exposes provider identifiers, URLs, payload content or
/// vendor-authored errors. Any code path that may have created a remote
/// webhook enters a non-cancelled cleanup task before returning. A run that
/// cannot prove remote deletion is reported for manual account review.
public actor ManusLiveAcceptanceRunner {
    public typealias ServerFactory = @Sendable (
        _ trustAnchor: String
    ) -> (any ManusLiveAcceptanceServerProtocol)?
    public typealias TunnelFactory = @Sendable () -> any ManusLiveAcceptanceTunnelProtocol
    public typealias CheckpointHandler = @Sendable (ManusLiveAcceptanceCheckpoint) -> Void

    private enum RuntimeFailure: Error {
        case stage(ManusLiveAcceptanceFailureStage)
    }

    private let client: any ManusLiveAcceptanceClientProtocol
    private let serverFactory: ServerFactory
    private let tunnelFactory: TunnelFactory
    private let checkpointHandler: CheckpointHandler
    private let checklist = ManusLiveAcceptanceChecklist()

    private var server: (any ManusLiveAcceptanceServerProtocol)?
    private var tunnel: (any ManusLiveAcceptanceTunnelProtocol)?
    private var webhookID: String?
    private var registrationAttempted = false
    private var registrationResultUncertain = false
    private var hasRun = false

    public init(
        client: any ManusLiveAcceptanceClientProtocol,
        serverFactory: @escaping ServerFactory = { trustAnchor in
            WebhookServer(port: 7823, signaturePublicKeyPEM: trustAnchor)
        },
        tunnelFactory: @escaping TunnelFactory = {
            CloudflaredProcess()
        },
        checkpointHandler: @escaping CheckpointHandler = { _ in }
    ) {
        self.client = client
        self.serverFactory = serverFactory
        self.tunnelFactory = tunnelFactory
        self.checkpointHandler = checkpointHandler
    }

    public func run(timeout: Duration = .seconds(600)) async -> ManusLiveAcceptanceReport {
        guard !hasRun else {
            return ManusLiveAcceptanceReport(
                termination: .failed(.lifecycle),
                snapshot: checklist.snapshot,
                manualWebhookReviewRequired: registrationResultUncertain
            )
        }
        hasRun = true

        let termination: ManusLiveAcceptanceTermination
        do {
            try await prepareAndRegister()
            termination = try await waitForLifecycle(timeout: timeout)
        } catch is CancellationError {
            termination = .cancelled
        } catch let RuntimeFailure.stage(stage) {
            termination = .failed(stage)
        } catch {
            // No dynamic error description crosses the acceptance boundary.
            termination = .failed(.lifecycle)
        }

        // `Task.detached` is deliberate: SIGINT/SIGTERM cancels the run task,
        // but cancellation must never prevent deletion and transport stop.
        let cleanup = await Task.detached(priority: .userInitiated) {
            await self.cleanup()
        }.value

        let finalTermination: ManusLiveAcceptanceTermination
        if termination == .accepted, !cleanup.snapshot.fullyAccepted {
            finalTermination = .failed(.lifecycle)
        } else {
            finalTermination = termination
        }
        return ManusLiveAcceptanceReport(
            termination: finalTermination,
            snapshot: cleanup.snapshot,
            manualWebhookReviewRequired: cleanup.manualWebhookReviewRequired
        )
    }

    private func prepareAndRegister() async throws {
        let trustAnchor: String
        do {
            trustAnchor = try await client.webhookPublicKey()
        } catch {
            throw RuntimeFailure.stage(.trustAnchor)
        }
        try Task.checkCancellation()

        guard let server = serverFactory(trustAnchor) else {
            throw RuntimeFailure.stage(.trustAnchor)
        }
        self.server = server
        checklist.markTrustAnchorValidated()
        checkpointHandler(.trustAnchorValidated)

        let checklist = self.checklist
        let checkpointHandler = self.checkpointHandler
        do {
            try await server.start { payload in
                guard let observation = checklist.record(payload) else { return }
                switch observation {
                case .signedRegistrationProbe:
                    checkpointHandler(.signedRegistrationProbe)
                case .taskCreated:
                    checkpointHandler(.taskCreated)
                case .taskStoppedFinish:
                    checkpointHandler(.taskStoppedFinish)
                case .taskStoppedAsk:
                    checkpointHandler(.taskStoppedAsk)
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RuntimeFailure.stage(.serverStartup)
        }
        checkpointHandler(.serverStarted)
        try Task.checkCancellation()

        let tunnel = tunnelFactory()
        self.tunnel = tunnel
        let publicURL: URL
        do {
            publicURL = try await tunnel.start()
        } catch {
            throw RuntimeFailure.stage(.tunnelStartup)
        }
        checkpointHandler(.tunnelStarted)
        try Task.checkCancellation()

        let webhookURL = publicURL.appendingPathComponent("/webhook").absoluteString
        do {
            try await server.configure(
                externalURL: webhookURL,
                signaturePublicKeyPEM: trustAnchor
            )
        } catch {
            throw RuntimeFailure.stage(.serverConfiguration)
        }
        try Task.checkCancellation()

        registrationAttempted = true
        checklist.beginRegistration()
        checkpointHandler(.registrationStarted)
        do {
            let identifier = try await client.registerWebhook(publicURL: webhookURL)
            webhookID = identifier
            checklist.markRegistrationAccepted()
            checkpointHandler(.registrationAccepted)
        } catch {
            checklist.markRegistrationFailed()
            registrationResultUncertain = true
            throw RuntimeFailure.stage(.registration)
        }
        try Task.checkCancellation()
    }

    private func waitForLifecycle(timeout: Duration) async throws -> ManusLiveAcceptanceTermination {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !checklist.snapshot.lifecycleComplete {
            try Task.checkCancellation()
            guard clock.now < deadline else { return .timedOut }
            try await Task.sleep(for: .milliseconds(100))
        }
        return .accepted
    }

    private func cleanup() async -> (
        snapshot: ManusLiveAcceptanceChecklist.Snapshot,
        manualWebhookReviewRequired: Bool
    ) {
        var requiresManualReview = registrationResultUncertain

        if let webhookID {
            do {
                try await client.deleteWebhook(id: webhookID)
                checklist.markWebhookDeleted()
                checkpointHandler(.webhookDeleted)
            } catch {
                requiresManualReview = true
            }
        } else if registrationAttempted {
            // Registration may have reached Manus even when the response was
            // lost. Without an identifier, automated deletion is impossible.
            requiresManualReview = true
        }

        if let tunnel { await tunnel.stop() }
        if let server { await server.stop() }
        checklist.markTransportsStopped()
        checkpointHandler(.transportsStopped)

        if requiresManualReview {
            checkpointHandler(.manualWebhookReviewRequired)
        }
        return (checklist.snapshot, requiresManualReview)
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}
