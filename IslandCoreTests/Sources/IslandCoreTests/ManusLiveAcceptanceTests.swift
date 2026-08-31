import Darwin
import Foundation
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
        XCTAssertFalse(checklist.snapshot.fullyAccepted)

        checklist.markRecoveryJournalCleared()
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
            journal: makeRecoveryJournal(),
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

    func testRunnerAcceptsOnlyFullLifecycleThenDeletesAndStops() async throws {
        let relay = AcceptanceEventRelay()
        let fixture = makeRecoveryFixture()
        let client = AcceptanceFakeClient(
            relay: relay,
            observedJournal: fixture.journal
        )
        let server = AcceptanceFakeServer(relay: relay)
        let tunnel = AcceptanceFakeTunnel()
        let checkpoints = AcceptanceCheckpointRecorder()
        let runner = ManusLiveAcceptanceRunner(
            client: client,
            journal: fixture.journal,
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
        let journalPresentAtRegistration = await client
            .journalPresentWhenRegisterCalled
        let webhookBoundAtDeletion = await client.webhookBoundWhenDeleteCalled
        let serverStopCount = await server.stopCount
        let tunnelStopCount = await tunnel.stopCount
        XCTAssertTrue(report.accepted)
        XCTAssertFalse(report.manualWebhookReviewRequired)
        XCTAssertEqual(deleteCount, 1)
        XCTAssertEqual(journalPresentAtRegistration, true)
        XCTAssertEqual(webhookBoundAtDeletion, true)
        XCTAssertEqual(serverStopCount, 1)
        XCTAssertEqual(tunnelStopCount, 1)
        XCTAssertTrue(checkpoints.contains(.webhookDeleted))
        XCTAssertTrue(checkpoints.contains(.recoveryJournalCleared))
        XCTAssertTrue(checkpoints.contains(.transportsStopped))
        XCTAssertNil(try fixture.journal.snapshot())

        let ordered = checkpoints.values
        XCTAssertLessThan(
            try XCTUnwrap(ordered.firstIndex(of: .tunnelStarted)),
            try XCTUnwrap(ordered.firstIndex(of: .recoveryJournalPersisted))
        )
        XCTAssertLessThan(
            try XCTUnwrap(ordered.firstIndex(of: .recoveryJournalPersisted)),
            try XCTUnwrap(ordered.firstIndex(of: .registrationStarted))
        )
        XCTAssertLessThan(
            try XCTUnwrap(ordered.firstIndex(of: .webhookDeleted)),
            try XCTUnwrap(ordered.firstIndex(of: .recoveryJournalCleared))
        )
        XCTAssertLessThan(
            try XCTUnwrap(ordered.firstIndex(of: .recoveryJournalCleared)),
            try XCTUnwrap(ordered.firstIndex(of: .transportsStopped))
        )
    }

    func testCancelledRunnerUsesCleanupPathAndDeletesKnownWebhook() async {
        let relay = AcceptanceEventRelay()
        let client = AcceptanceFakeClient(relay: relay)
        let server = AcceptanceFakeServer(relay: relay)
        let tunnel = AcceptanceFakeTunnel()
        let checkpoints = AcceptanceCheckpointRecorder()
        let runner = ManusLiveAcceptanceRunner(
            client: client,
            journal: makeRecoveryJournal(),
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
            journal: makeRecoveryJournal(),
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
        let fixture = makeRecoveryFixture()
        let client = AcceptanceFakeClient(
            relay: relay,
            deletionFails: true,
            observedJournal: fixture.journal
        )
        let server = AcceptanceFakeServer(relay: relay)
        let tunnel = AcceptanceFakeTunnel()
        let checkpoints = AcceptanceCheckpointRecorder()
        let runner = ManusLiveAcceptanceRunner(
            client: client,
            journal: fixture.journal,
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
        XCTAssertEqual(
            try? fixture.journal.snapshot()?.webhookIDs,
            ["fixture-webhook"]
        )
        let webhookBoundAtDeletion = await client.webhookBoundWhenDeleteCalled
        XCTAssertEqual(webhookBoundAtDeletion, true)
    }

    func testUnboundRecoveryDeletesOnlyOneExactActiveWebhook() async throws {
        let fixture = makeRecoveryFixture()
        let startedAt: Int64 = 10_000
        try fixture.journal.beginRegistration(
            callbackURL: "https://fixture.trycloudflare.com/webhook",
            startedAtUnixSeconds: startedAt
        )
        let client = AcceptanceFakeClient(
            relay: AcceptanceEventRelay(),
            webhooks: [
                recoveryWebhook(
                    id: "unrelated-webhook",
                    url: "https://other.trycloudflare.com/webhook",
                    createdAt: startedAt
                ),
                recoveryWebhook(
                    id: "matching-webhook",
                    createdAt: startedAt + 300
                ),
            ],
            observedJournal: fixture.journal
        )
        let checkpoints = AcceptanceCheckpointRecorder()
        let runner = ManusLiveAcceptanceRecoveryRunner(
            client: client,
            journal: fixture.journal,
            checkpointHandler: { checkpoints.append($0) }
        )

        let result = await runner.recover()
        let listCount = await client.listCount
        let deletedIDs = await client.deletedIDs
        let webhookBoundAtDeletion = await client.webhookBoundWhenDeleteCalled
        XCTAssertEqual(result, .recovered)
        XCTAssertEqual(listCount, 1)
        XCTAssertEqual(deletedIDs, ["matching-webhook"])
        XCTAssertEqual(webhookBoundAtDeletion, true)
        XCTAssertNil(try fixture.journal.snapshot())
        XCTAssertEqual(checkpoints.values, [
            .recoveryJournalValidated,
            .recoveryInventoryChecked,
            .recoveryWebhookBound,
            .webhookDeleted,
            .recoveryJournalCleared,
        ])
    }

    func testUnboundRecoveryWithEmptyInventoryRequiresManualReview() async throws {
        try await assertUnboundRecoveryRequiresManualReview(webhooks: [])
    }

    func testUnboundRecoveryWithMultipleExactMatchesRequiresManualReview() async throws {
        let startedAt: Int64 = 10_000
        try await assertUnboundRecoveryRequiresManualReview(
            startedAt: startedAt,
            webhooks: [
                recoveryWebhook(id: "match-one", createdAt: startedAt),
                recoveryWebhook(id: "match-two", createdAt: startedAt + 1),
            ]
        )
    }

    func testUnboundRecoveryRejectsInactiveMatch() async throws {
        let startedAt: Int64 = 10_000
        try await assertUnboundRecoveryRequiresManualReview(
            startedAt: startedAt,
            webhooks: [
                recoveryWebhook(
                    id: "inactive-match",
                    status: .inactive,
                    createdAt: startedAt
                ),
            ]
        )
    }

    func testUnboundRecoveryRejectsWebhookOlderThanWindow() async throws {
        let startedAt: Int64 = 10_000
        try await assertUnboundRecoveryRequiresManualReview(
            startedAt: startedAt,
            webhooks: [
                recoveryWebhook(
                    id: "old-match",
                    createdAt: startedAt - 301
                ),
            ]
        )
    }

    func testUnboundRecoveryRejectsWebhookNewerThanWindow() async throws {
        let startedAt: Int64 = 10_000
        try await assertUnboundRecoveryRequiresManualReview(
            startedAt: startedAt,
            webhooks: [
                recoveryWebhook(
                    id: "future-match",
                    createdAt: startedAt + 301
                ),
            ]
        )
    }

    func testUnboundRecoveryNeverDeletesUnrelatedWebhook() async throws {
        let startedAt: Int64 = 10_000
        try await assertUnboundRecoveryRequiresManualReview(
            startedAt: startedAt,
            webhooks: [
                recoveryWebhook(
                    id: "unrelated-webhook",
                    url: "https://unrelated.trycloudflare.com/webhook",
                    createdAt: startedAt
                ),
            ]
        )
    }

    func testRecoveryListFailurePreservesUnboundJournal() async throws {
        let fixture = makeRecoveryFixture()
        try fixture.journal.beginRegistration(
            callbackURL: "https://fixture.trycloudflare.com/webhook",
            startedAtUnixSeconds: 10_000
        )
        let client = AcceptanceFakeClient(
            relay: AcceptanceEventRelay(),
            listingFails: true
        )
        let checkpoints = AcceptanceCheckpointRecorder()
        let runner = ManusLiveAcceptanceRecoveryRunner(
            client: client,
            journal: fixture.journal,
            checkpointHandler: { checkpoints.append($0) }
        )

        let result = await runner.recover()
        let listCount = await client.listCount
        let deleteCount = await client.deleteCount
        XCTAssertEqual(result, .manualReviewRequired)
        XCTAssertEqual(listCount, 1)
        XCTAssertEqual(deleteCount, 0)
        XCTAssertNotNil(try fixture.journal.snapshot())
        XCTAssertEqual(checkpoints.values, [
            .recoveryJournalValidated,
            .manualWebhookReviewRequired,
        ])
    }

    func testBoundRecoverySkipsInventoryList() async throws {
        let fixture = makeRecoveryFixture()
        try fixture.journal.beginRegistration(
            callbackURL: "https://fixture.trycloudflare.com/webhook",
            startedAtUnixSeconds: 10_000
        )
        try fixture.journal.bindWebhookIDs(["bound-webhook"])
        let client = AcceptanceFakeClient(
            relay: AcceptanceEventRelay(),
            listingFails: true,
            observedJournal: fixture.journal
        )
        let checkpoints = AcceptanceCheckpointRecorder()
        let runner = ManusLiveAcceptanceRecoveryRunner(
            client: client,
            journal: fixture.journal,
            checkpointHandler: { checkpoints.append($0) }
        )

        let result = await runner.recover()
        let listCount = await client.listCount
        let deletedIDs = await client.deletedIDs
        let webhookBoundAtDeletion = await client.webhookBoundWhenDeleteCalled
        XCTAssertEqual(result, .recovered)
        XCTAssertEqual(listCount, 0)
        XCTAssertEqual(deletedIDs, ["bound-webhook"])
        XCTAssertEqual(webhookBoundAtDeletion, true)
        XCTAssertNil(try fixture.journal.snapshot())
        XCTAssertEqual(checkpoints.values, [
            .recoveryJournalValidated,
            .webhookDeleted,
            .recoveryJournalCleared,
        ])
    }

    func testRecoveryWithoutJournalDoesNotCallProvider() async {
        let fixture = makeRecoveryFixture()
        let client = AcceptanceFakeClient(
            relay: AcceptanceEventRelay(),
            listingFails: true,
            deletionFails: true
        )
        let checkpoints = AcceptanceCheckpointRecorder()
        let runner = ManusLiveAcceptanceRecoveryRunner(
            client: client,
            journal: fixture.journal,
            checkpointHandler: { checkpoints.append($0) }
        )

        let result = await runner.recover()
        let listCount = await client.listCount
        let deleteCount = await client.deleteCount
        XCTAssertEqual(result, .noJournal)
        XCTAssertEqual(listCount, 0)
        XCTAssertEqual(deleteCount, 0)
        XCTAssertTrue(checkpoints.values.isEmpty)
    }

    func testDeleteFailureKeepsBoundJournalAndRetryDoesNotList() async throws {
        let fixture = makeRecoveryFixture()
        let startedAt: Int64 = 10_000
        try fixture.journal.beginRegistration(
            callbackURL: "https://fixture.trycloudflare.com/webhook",
            startedAtUnixSeconds: startedAt
        )
        let firstClient = AcceptanceFakeClient(
            relay: AcceptanceEventRelay(),
            deletionFails: true,
            webhooks: [
                recoveryWebhook(id: "discovered-webhook", createdAt: startedAt),
            ],
            observedJournal: fixture.journal
        )
        let firstRunner = ManusLiveAcceptanceRecoveryRunner(
            client: firstClient,
            journal: fixture.journal
        )

        let firstResult = await firstRunner.recover()
        let firstListCount = await firstClient.listCount
        XCTAssertEqual(firstResult, .manualReviewRequired)
        XCTAssertEqual(firstListCount, 1)
        XCTAssertEqual(
            try fixture.journal.snapshot()?.webhookIDs,
            ["discovered-webhook"]
        )

        let retryClient = AcceptanceFakeClient(
            relay: AcceptanceEventRelay(),
            listingFails: true,
            observedJournal: fixture.journal
        )
        let retryRunner = ManusLiveAcceptanceRecoveryRunner(
            client: retryClient,
            journal: fixture.journal
        )
        let retryResult = await retryRunner.recover()
        let retryListCount = await retryClient.listCount
        let retryDeletedIDs = await retryClient.deletedIDs
        XCTAssertEqual(retryResult, .recovered)
        XCTAssertEqual(retryListCount, 0)
        XCTAssertEqual(retryDeletedIDs, ["discovered-webhook"])
        XCTAssertNil(try fixture.journal.snapshot())
    }

    func testCorruptJournalFailsClosedBeforeProviderInventory() async throws {
        let fixture = makeRecoveryFixture()
        try fixture.journal.beginRegistration(
            callbackURL: "https://fixture.trycloudflare.com/webhook",
            startedAtUnixSeconds: 10_000
        )
        let handle = try FileHandle(
            forWritingTo: URL(fileURLWithPath: fixture.path)
        )
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("not-json".utf8))
        try handle.synchronize()
        try handle.close()

        let client = AcceptanceFakeClient(relay: AcceptanceEventRelay())
        let runner = ManusLiveAcceptanceRecoveryRunner(
            client: client,
            journal: fixture.journal
        )
        let result = await runner.recover()
        let listCount = await client.listCount
        let deleteCount = await client.deleteCount
        XCTAssertEqual(result, .manualReviewRequired)
        XCTAssertEqual(listCount, 0)
        XCTAssertEqual(deleteCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path))
    }

    func testJournalSymlinkIsRejectedBeforeProviderInventory() async throws {
        let fixture = makeRecoveryFixture()
        let target = fixture.directory.appendingPathComponent("target.json")
        try Data("{}".utf8).write(to: target)
        XCTAssertEqual(chmod(target.path, S_IRUSR | S_IWUSR), 0)
        let result = target.path.withCString { source in
            fixture.path.withCString { destination in
                Darwin.symlink(source, destination)
            }
        }
        XCTAssertEqual(result, 0)
        XCTAssertThrowsError(try fixture.journal.snapshot())

        let client = AcceptanceFakeClient(relay: AcceptanceEventRelay())
        let runner = ManusLiveAcceptanceRecoveryRunner(
            client: client,
            journal: fixture.journal
        )
        let recoveryResult = await runner.recover()
        let listCount = await client.listCount
        XCTAssertEqual(recoveryResult, .manualReviewRequired)
        XCTAssertEqual(listCount, 0)
    }

    func testHardLinkedJournalIsRejectedBeforeProviderInventory() async throws {
        let fixture = makeRecoveryFixture()
        try fixture.journal.beginRegistration(
            callbackURL: "https://fixture.trycloudflare.com/webhook",
            startedAtUnixSeconds: 10_000
        )
        let secondPath = fixture.directory
            .appendingPathComponent("second-link.json").path
        let result = fixture.path.withCString { source in
            secondPath.withCString { destination in
                Darwin.link(source, destination)
            }
        }
        XCTAssertEqual(result, 0)
        XCTAssertThrowsError(try fixture.journal.snapshot())

        let client = AcceptanceFakeClient(relay: AcceptanceEventRelay())
        let runner = ManusLiveAcceptanceRecoveryRunner(
            client: client,
            journal: fixture.journal
        )
        let recoveryResult = await runner.recover()
        let listCount = await client.listCount
        XCTAssertEqual(recoveryResult, .manualReviewRequired)
        XCTAssertEqual(listCount, 0)
    }

    func testWrongModeJournalIsRejectedBeforeProviderInventory() async throws {
        let fixture = makeRecoveryFixture()
        try fixture.journal.beginRegistration(
            callbackURL: "https://fixture.trycloudflare.com/webhook",
            startedAtUnixSeconds: 10_000
        )
        XCTAssertEqual(chmod(fixture.path, 0o644), 0)
        XCTAssertThrowsError(try fixture.journal.snapshot())

        let client = AcceptanceFakeClient(relay: AcceptanceEventRelay())
        let runner = ManusLiveAcceptanceRecoveryRunner(
            client: client,
            journal: fixture.journal
        )
        let recoveryResult = await runner.recover()
        let listCount = await client.listCount
        XCTAssertEqual(recoveryResult, .manualReviewRequired)
        XCTAssertEqual(listCount, 0)
    }

    func testParentSymlinkComponentIsRejected() throws {
        let fixture = makeRecoveryFixture()
        let realParent = fixture.directory.appendingPathComponent(
            "real-parent",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: realParent,
            withIntermediateDirectories: false
        )
        XCTAssertEqual(chmod(realParent.path, S_IRWXU), 0)
        let linkedParent = fixture.directory.appendingPathComponent(
            "linked-parent",
            isDirectory: true
        )
        try FileManager.default.createSymbolicLink(
            at: linkedParent,
            withDestinationURL: realParent
        )

        XCTAssertThrowsError(try ManusLiveAcceptanceRecoveryJournal(
            path: linkedParent.appendingPathComponent("recovery.json").path
        ))
    }

    func testNonPrivateParentDirectoryIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .appendingPathComponent(
                "dev-island-manus-public-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        XCTAssertEqual(chmod(directory.path, 0o755), 0)
        XCTAssertThrowsError(try ManusLiveAcceptanceRecoveryJournal(
            path: directory.appendingPathComponent("recovery.json").path
        ))
    }

    func testExistingJournalBlocksNewLiveRunBeforeAnyProviderCall() async throws {
        let fixture = makeRecoveryFixture()
        try fixture.journal.beginRegistration(
            callbackURL: "https://fixture.trycloudflare.com/webhook",
            startedAtUnixSeconds: 10_000
        )
        let relay = AcceptanceEventRelay()
        let client = AcceptanceFakeClient(relay: relay)
        let server = AcceptanceFakeServer(relay: relay)
        let tunnel = AcceptanceFakeTunnel()
        let runner = ManusLiveAcceptanceRunner(
            client: client,
            journal: fixture.journal,
            serverFactory: { _ in server },
            tunnelFactory: { tunnel }
        )

        let report = await runner.run(timeout: .milliseconds(1))
        let trustAnchorCount = await client.trustAnchorCount
        let registerCount = await client.registerCount
        let tunnelStartCount = await tunnel.startCount
        XCTAssertEqual(report.termination, .failed(.lifecycle))
        XCTAssertTrue(report.manualWebhookReviewRequired)
        XCTAssertEqual(trustAnchorCount, 0)
        XCTAssertEqual(registerCount, 0)
        XCTAssertEqual(tunnelStartCount, 0)
        XCTAssertNotNil(try fixture.journal.snapshot())
    }

    func testRegistrationAttemptIsJournaledBeforeClientCall() async throws {
        let fixture = makeRecoveryFixture()
        let relay = AcceptanceEventRelay()
        let client = AcceptanceFakeClient(
            relay: relay,
            registrationFails: true,
            observedJournal: fixture.journal
        )
        let runner = ManusLiveAcceptanceRunner(
            client: client,
            journal: fixture.journal,
            serverFactory: { _ in AcceptanceFakeServer(relay: relay) },
            tunnelFactory: { AcceptanceFakeTunnel() }
        )

        let report = await runner.run(timeout: .seconds(1))
        let registerCount = await client.registerCount
        let journalPresentAtRegistration = await client
            .journalPresentWhenRegisterCalled
        XCTAssertEqual(report.termination, .failed(.registration))
        XCTAssertEqual(registerCount, 1)
        XCTAssertEqual(journalPresentAtRegistration, true)
        XCTAssertNotNil(try fixture.journal.snapshot())
    }

    private func assertUnboundRecoveryRequiresManualReview(
        startedAt: Int64 = 10_000,
        webhooks: [ManusWebhook],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let fixture = makeRecoveryFixture()
        try fixture.journal.beginRegistration(
            callbackURL: "https://fixture.trycloudflare.com/webhook",
            startedAtUnixSeconds: startedAt
        )
        let client = AcceptanceFakeClient(
            relay: AcceptanceEventRelay(),
            webhooks: webhooks
        )
        let checkpoints = AcceptanceCheckpointRecorder()
        let runner = ManusLiveAcceptanceRecoveryRunner(
            client: client,
            journal: fixture.journal,
            checkpointHandler: { checkpoints.append($0) }
        )

        let result = await runner.recover()
        let listCount = await client.listCount
        let deleteCount = await client.deleteCount
        XCTAssertEqual(
            result,
            .manualReviewRequired,
            file: file,
            line: line
        )
        XCTAssertEqual(listCount, 1, file: file, line: line)
        XCTAssertEqual(deleteCount, 0, file: file, line: line)
        XCTAssertNotNil(
            try fixture.journal.snapshot(),
            file: file,
            line: line
        )
        XCTAssertEqual(
            checkpoints.values,
            [
                .recoveryJournalValidated,
                .recoveryInventoryChecked,
                .manualWebhookReviewRequired,
            ],
            file: file,
            line: line
        )
    }

    private func makeRecoveryFixture() -> AcceptanceRecoveryJournalFixture {
        let base = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .appendingPathComponent(
                "dev-island-manus-live-\(UUID().uuidString)",
                isDirectory: true
            )
        do {
            try FileManager.default.createDirectory(
                at: base,
                withIntermediateDirectories: false
            )
            guard chmod(base.path, S_IRWXU) == 0 else {
                throw AcceptanceFakeError.expected
            }
            addTeardownBlock {
                try? FileManager.default.removeItem(at: base)
            }
            let path = base.appendingPathComponent("recovery.json").path
            return AcceptanceRecoveryJournalFixture(
                journal: try ManusLiveAcceptanceRecoveryJournal(path: path),
                path: path,
                directory: base
            )
        } catch {
            preconditionFailure("Could not create private journal fixture")
        }
    }

    private func makeRecoveryJournal() -> ManusLiveAcceptanceRecoveryJournal {
        makeRecoveryFixture().journal
    }

    private func recoveryWebhook(
        id: String,
        url: String = "https://fixture.trycloudflare.com/webhook",
        status: ManusWebhook.Status = .active,
        createdAt: Int64
    ) -> ManusWebhook {
        ManusWebhook(
            id: id,
            url: url,
            status: status,
            createdAt: createdAt
        )
    }

    private func acceptedRegistrationChecklist() -> ManusLiveAcceptanceChecklist {
        let checklist = ManusLiveAcceptanceChecklist()
        checklist.markTrustAnchorValidated()
        checklist.markRecoveryJournalPersisted()
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

private struct AcceptanceRecoveryJournalFixture {
    let journal: ManusLiveAcceptanceRecoveryJournal
    let path: String
    let directory: URL
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
    private var storage = [ManusLiveAcceptanceCheckpoint]()

    func append(_ checkpoint: ManusLiveAcceptanceCheckpoint) {
        lock.lock()
        storage.append(checkpoint)
        lock.unlock()
    }

    func contains(_ checkpoint: ManusLiveAcceptanceCheckpoint) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage.contains(checkpoint)
    }

    var values: [ManusLiveAcceptanceCheckpoint] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private actor AcceptanceFakeClient: ManusLiveAcceptanceClientProtocol {
    private let relay: AcceptanceEventRelay
    private let registrationFails: Bool
    private let listingFails: Bool
    private let deletionFails: Bool
    private let webhooks: [ManusWebhook]
    private let observedJournal: ManusLiveAcceptanceRecoveryJournal?
    private(set) var trustAnchorCount = 0
    private(set) var registerCount = 0
    private(set) var listCount = 0
    private(set) var deleteCount = 0
    private(set) var deletedIDs = [String]()
    private(set) var journalPresentWhenRegisterCalled: Bool?
    private(set) var webhookBoundWhenDeleteCalled: Bool?

    init(
        relay: AcceptanceEventRelay,
        registrationFails: Bool = false,
        listingFails: Bool = false,
        deletionFails: Bool = false,
        webhooks: [ManusWebhook] = [],
        observedJournal: ManusLiveAcceptanceRecoveryJournal? = nil
    ) {
        self.relay = relay
        self.registrationFails = registrationFails
        self.listingFails = listingFails
        self.deletionFails = deletionFails
        self.webhooks = webhooks
        self.observedJournal = observedJournal
    }

    func webhookPublicKey() async throws -> String {
        trustAnchorCount += 1
        return "fixture-trust-anchor"
    }

    func registerWebhook(publicURL: String) async throws -> String {
        registerCount += 1
        if let observedJournal {
            journalPresentWhenRegisterCalled = try? observedJournal
                .snapshot()?.webhookIDs.isEmpty == true
        }
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

    func listWebhooks() async throws -> [ManusWebhook] {
        listCount += 1
        if listingFails { throw AcceptanceFakeError.expected }
        return webhooks
    }

    func deleteWebhook(id: String) async throws {
        deleteCount += 1
        deletedIDs.append(id)
        if let observedJournal {
            webhookBoundWhenDeleteCalled = try? observedJournal
                .snapshot()?.webhookIDs.contains(id) == true
        }
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
