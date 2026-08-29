import XCTest
@testable import IslandCore

final class ManusLiveAcceptanceTests: XCTestCase {
    func testCredentialIsBoundedPrintableASCIIWithoutPinningProviderPrefix() {
        XCTAssertNotNil(ManusLiveAcceptanceCredential.validated(
            "sk-0123456789abcdef"
        ))
        XCTAssertNotNil(ManusLiveAcceptanceCredential.validated(
            "mk_live_0123456789abcdef"
        ))
        XCTAssertNil(ManusLiveAcceptanceCredential.validated("short"))
        XCTAssertNil(ManusLiveAcceptanceCredential.validated(
            "sk-0123456789abc\ndef"
        ))
        XCTAssertNil(ManusLiveAcceptanceCredential.validated(
            String(repeating: "a", count: ManusLiveAcceptanceCredential.maximumLength + 1)
        ))
    }

    func testSignedRegistrationProbeCannotSatisfyTaskLifecycle() {
        let checklist = ManusLiveAcceptanceChecklist()
        checklist.markTrustAnchorValidated()
        checklist.beginRegistration()

        XCTAssertEqual(
            checklist.record(createdPayload(id: "registration-probe")),
            .signedRegistrationProbe
        )
        checklist.markRegistrationAccepted()

        let snapshot = checklist.snapshot
        XCTAssertTrue(snapshot.signedRegistrationProbeObserved)
        XCTAssertFalse(snapshot.taskCreatedObserved)
        XCTAssertFalse(snapshot.lifecycleComplete)
    }

    func testStoppedEventCountsOnlyAfterMatchingTaskWasCreatedInThisRun() {
        let checklist = acceptedRegistrationChecklist()

        XCTAssertNil(checklist.record(stoppedPayload(
            id: "older-task",
            reason: .finish
        )))
        XCTAssertEqual(
            checklist.record(createdPayload(id: "finish-task")),
            .taskCreated
        )
        XCTAssertEqual(
            checklist.record(stoppedPayload(id: "finish-task", reason: .finish)),
            .taskStoppedFinish
        )
        XCTAssertNil(checklist.record(stoppedPayload(
            id: "unseen-ask-task",
            reason: .ask
        )))
        XCTAssertFalse(checklist.snapshot.lifecycleComplete)

        XCTAssertNil(checklist.record(createdPayload(id: "ask-task")))
        XCTAssertEqual(
            checklist.record(stoppedPayload(id: "ask-task", reason: .ask)),
            .taskStoppedAsk
        )
        XCTAssertTrue(checklist.snapshot.lifecycleComplete)
    }

    func testFullAcceptanceRequiresRemoteDeletionAndLocalTransportStop() {
        let checklist = acceptedRegistrationChecklist()
        _ = checklist.record(createdPayload(id: "finish-task"))
        _ = checklist.record(stoppedPayload(id: "finish-task", reason: .finish))
        _ = checklist.record(createdPayload(id: "ask-task"))
        _ = checklist.record(stoppedPayload(id: "ask-task", reason: .ask))

        XCTAssertTrue(checklist.snapshot.lifecycleComplete)
        XCTAssertFalse(checklist.snapshot.fullyAccepted)

        checklist.markWebhookDeleted()
        XCTAssertFalse(checklist.snapshot.fullyAccepted)

        checklist.markTransportsStopped()
        XCTAssertTrue(checklist.snapshot.fullyAccepted)
    }

    func testCloudflaredChildEnvironmentExcludesParentCredentialsAndConfig() {
        let environment = CloudflaredProcess.childEnvironment(from: [
            "PATH": "/custom/bin:/usr/bin",
            "TMPDIR": "/private/tmp/example",
            "LANG": "en_US.UTF-8",
            "LC_ALL": "C",
            "HOME": "/Users/example",
            "MANUS_API_KEY_DEV": "secret",
            "OPENAI_API_KEY": "secret",
            "DYLD_INSERT_LIBRARIES": "/tmp/untrusted.dylib",
        ])

        XCTAssertEqual(environment, [
            "PATH": "/custom/bin:/usr/bin",
            "TMPDIR": "/private/tmp/example",
            "LANG": "en_US.UTF-8",
            "LC_ALL": "C",
        ])
    }

    func testServerStartupFailureCannotStartTunnelOrAttemptRegistration() async {
        let relay = AcceptanceEventRelay()
        let client = AcceptanceFakeClient(relay: relay)
        let server = AcceptanceFakeServer(relay: relay, startFails: true)
        let tunnel = AcceptanceFakeTunnel()
        let checkpoints = AcceptanceCheckpointRecorder()
        let runner = ManusLiveAcceptanceRunner(
            client: client,
            serverFactory: { _ in server },
            tunnelFactory: { tunnel },
            checkpointHandler: { checkpoints.append($0) }
        )

        let report = await runner.run(timeout: .seconds(2))
        let registerCount = await client.registerCount
        let serverStopCount = await server.stopCount
        let tunnelStartCount = await tunnel.startCount
        let tunnelStopCount = await tunnel.stopCount
        XCTAssertEqual(report.termination, .failed(.serverStartup))
        XCTAssertEqual(registerCount, 0)
        XCTAssertEqual(serverStopCount, 1)
        XCTAssertEqual(tunnelStartCount, 0)
        XCTAssertEqual(tunnelStopCount, 0)
        XCTAssertFalse(checkpoints.contains(.serverStarted))
        XCTAssertFalse(checkpoints.contains(.tunnelStarted))
        XCTAssertTrue(report.snapshot.transportsStopped)
    }

    func testRunnerAcceptsOnlyFullLifecycleThenDeletesAndStops() async {
        let relay = AcceptanceEventRelay()
        let client = AcceptanceFakeClient(relay: relay)
        let server = AcceptanceFakeServer(relay: relay)
        let tunnel = AcceptanceFakeTunnel()
        let checkpoints = AcceptanceCheckpointRecorder()
        let runner = ManusLiveAcceptanceRunner(
            client: client,
            serverFactory: { _ in server },
            tunnelFactory: { tunnel },
            checkpointHandler: { checkpoints.append($0) }
        )

        let run = Task { await runner.run(timeout: .seconds(2)) }
        await waitUntil { checkpoints.contains(.registrationAccepted) }

        relay.deliver(createdPayload(id: "finish-task"))
        relay.deliver(stoppedPayload(id: "finish-task", reason: .finish))
        relay.deliver(createdPayload(id: "ask-task"))
        relay.deliver(stoppedPayload(id: "ask-task", reason: .ask))

        let report = await run.value
        let deleteCount = await client.deleteCount
        let serverStopCount = await server.stopCount
        let tunnelStopCount = await tunnel.stopCount
        XCTAssertTrue(report.accepted)
        XCTAssertFalse(report.manualWebhookReviewRequired)
        XCTAssertEqual(deleteCount, 1)
        XCTAssertEqual(serverStopCount, 1)
        XCTAssertEqual(tunnelStopCount, 1)
        XCTAssertTrue(checkpoints.contains(.webhookDeleted))
        XCTAssertTrue(checkpoints.contains(.transportsStopped))
    }

    func testCancelledRunnerUsesCleanupPathAndDeletesKnownWebhook() async {
        let relay = AcceptanceEventRelay()
        let client = AcceptanceFakeClient(relay: relay)
        let server = AcceptanceFakeServer(relay: relay)
        let tunnel = AcceptanceFakeTunnel()
        let checkpoints = AcceptanceCheckpointRecorder()
        let runner = ManusLiveAcceptanceRunner(
            client: client,
            serverFactory: { _ in server },
            tunnelFactory: { tunnel },
            checkpointHandler: { checkpoints.append($0) }
        )

        let run = Task { await runner.run(timeout: .seconds(2)) }
        await waitUntil { checkpoints.contains(.registrationAccepted) }
        run.cancel()

        let report = await run.value
        let deleteCount = await client.deleteCount
        let serverStopCount = await server.stopCount
        let tunnelStopCount = await tunnel.stopCount
        XCTAssertEqual(report.termination, .cancelled)
        XCTAssertFalse(report.manualWebhookReviewRequired)
        XCTAssertEqual(deleteCount, 1)
        XCTAssertEqual(serverStopCount, 1)
        XCTAssertEqual(tunnelStopCount, 1)
        XCTAssertTrue(report.snapshot.webhookDeleted)
        XCTAssertTrue(report.snapshot.transportsStopped)
    }

    func testUncertainRegistrationRequiresManualReviewButStillStopsTransports() async {
        let relay = AcceptanceEventRelay()
        let client = AcceptanceFakeClient(relay: relay, registrationFails: true)
        let server = AcceptanceFakeServer(relay: relay)
        let tunnel = AcceptanceFakeTunnel()
        let checkpoints = AcceptanceCheckpointRecorder()
        let runner = ManusLiveAcceptanceRunner(
            client: client,
            serverFactory: { _ in server },
            tunnelFactory: { tunnel },
            checkpointHandler: { checkpoints.append($0) }
        )

        let report = await runner.run(timeout: .seconds(2))
        let deleteCount = await client.deleteCount
        let serverStopCount = await server.stopCount
        let tunnelStopCount = await tunnel.stopCount

        XCTAssertEqual(report.termination, .failed(.registration))
        XCTAssertTrue(report.manualWebhookReviewRequired)
        XCTAssertEqual(deleteCount, 0)
        XCTAssertEqual(serverStopCount, 1)
        XCTAssertEqual(tunnelStopCount, 1)
        XCTAssertTrue(checkpoints.contains(.manualWebhookReviewRequired))
        XCTAssertTrue(report.snapshot.transportsStopped)
    }

    func testDeletionFailureNeverReportsAcceptanceAndRequiresManualReview() async {
        let relay = AcceptanceEventRelay()
        let client = AcceptanceFakeClient(relay: relay, deletionFails: true)
        let server = AcceptanceFakeServer(relay: relay)
        let tunnel = AcceptanceFakeTunnel()
        let checkpoints = AcceptanceCheckpointRecorder()
        let runner = ManusLiveAcceptanceRunner(
            client: client,
            serverFactory: { _ in server },
            tunnelFactory: { tunnel },
            checkpointHandler: { checkpoints.append($0) }
        )

        let run = Task { await runner.run(timeout: .seconds(2)) }
        await waitUntil { checkpoints.contains(.registrationAccepted) }
        relay.deliver(createdPayload(id: "finish-task"))
        relay.deliver(stoppedPayload(id: "finish-task", reason: .finish))
        relay.deliver(createdPayload(id: "ask-task"))
        relay.deliver(stoppedPayload(id: "ask-task", reason: .ask))

        let report = await run.value
        let serverStopCount = await server.stopCount
        let tunnelStopCount = await tunnel.stopCount
        XCTAssertFalse(report.accepted)
        XCTAssertEqual(report.termination, .failed(.lifecycle))
        XCTAssertTrue(report.manualWebhookReviewRequired)
        XCTAssertFalse(report.snapshot.webhookDeleted)
        XCTAssertTrue(report.snapshot.transportsStopped)
        XCTAssertEqual(serverStopCount, 1)
        XCTAssertEqual(tunnelStopCount, 1)
        XCTAssertTrue(checkpoints.contains(.manualWebhookReviewRequired))
    }

    private func acceptedRegistrationChecklist() -> ManusLiveAcceptanceChecklist {
        let checklist = ManusLiveAcceptanceChecklist()
        checklist.markTrustAnchorValidated()
        checklist.beginRegistration()
        _ = checklist.record(createdPayload(id: "registration-probe"))
        checklist.markRegistrationAccepted()
        return checklist
    }

    private func createdPayload(id: String) -> WebhookPayload {
        WebhookPayload(
            eventID: "event-\(id)",
            event: .taskCreated,
            taskId: id,
            data: .created(.init(
                taskId: id,
                taskTitle: "Fixture",
                taskUrl: "https://manus.im/app/fixture"
            ))
        )
    }

    private func stoppedPayload(
        id: String,
        reason: TaskStoppedData.StopReason
    ) -> WebhookPayload {
        WebhookPayload(
            eventID: "event-\(id)-\(reason.rawValue)",
            event: .taskStopped,
            taskId: id,
            data: .stopped(.init(
                taskId: id,
                taskTitle: "Fixture",
                taskUrl: "https://manus.im/app/fixture",
                message: "Fixture",
                attachments: [],
                stopReason: reason
            ))
        )
    }

    private func waitUntil(
        _ predicate: @escaping @Sendable () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for acceptance checkpoint", file: file, line: line)
    }
}

private enum AcceptanceFakeError: Error {
    case expected
}

private final class AcceptanceEventRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable (WebhookPayload) -> Void)?

    func install(_ callback: @escaping @Sendable (WebhookPayload) -> Void) {
        lock.lock()
        self.callback = callback
        lock.unlock()
    }

    func deliver(_ payload: WebhookPayload) {
        lock.lock()
        let callback = callback
        lock.unlock()
        callback?(payload)
    }
}

private final class AcceptanceCheckpointRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Set<ManusLiveAcceptanceCheckpoint>()

    func append(_ checkpoint: ManusLiveAcceptanceCheckpoint) {
        lock.lock()
        storage.insert(checkpoint)
        lock.unlock()
    }

    func contains(_ checkpoint: ManusLiveAcceptanceCheckpoint) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage.contains(checkpoint)
    }
}

private actor AcceptanceFakeClient: ManusLiveAcceptanceClientProtocol {
    private let relay: AcceptanceEventRelay
    private let registrationFails: Bool
    private let deletionFails: Bool
    private(set) var registerCount = 0
    private(set) var deleteCount = 0

    init(
        relay: AcceptanceEventRelay,
        registrationFails: Bool = false,
        deletionFails: Bool = false
    ) {
        self.relay = relay
        self.registrationFails = registrationFails
        self.deletionFails = deletionFails
    }

    func webhookPublicKey() async throws -> String {
        "fixture-trust-anchor"
    }

    func registerWebhook(publicURL: String) async throws -> String {
        registerCount += 1
        relay.deliver(WebhookPayload(
            eventID: "registration-event",
            event: .taskCreated,
            taskId: "registration-probe",
            data: .created(.init(
                taskId: "registration-probe",
                taskTitle: "Fixture",
                taskUrl: "https://manus.im/app/fixture"
            ))
        ))
        if registrationFails { throw AcceptanceFakeError.expected }
        return "fixture-webhook"
    }

    func deleteWebhook(id: String) async throws {
        deleteCount += 1
        if deletionFails { throw AcceptanceFakeError.expected }
    }
}

private actor AcceptanceFakeServer: ManusLiveAcceptanceServerProtocol {
    private let relay: AcceptanceEventRelay
    private let startFails: Bool
    private(set) var stopCount = 0

    init(relay: AcceptanceEventRelay, startFails: Bool = false) {
        self.relay = relay
        self.startFails = startFails
    }

    func configure(externalURL: String, signaturePublicKeyPEM: String) async throws {}

    func start(onEvent: @escaping @Sendable (WebhookPayload) -> Void) async throws {
        if startFails { throw AcceptanceFakeError.expected }
        relay.install(onEvent)
    }

    func stop() async {
        stopCount += 1
    }
}

private actor AcceptanceFakeTunnel: ManusLiveAcceptanceTunnelProtocol {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() async throws -> URL {
        startCount += 1
        return URL(string: "https://fixture.trycloudflare.com")!
    }

    func stop() async {
        stopCount += 1
    }
}
