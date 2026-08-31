import Foundation
import XCTest
@testable import IslandCore

final class TunnelManagerTests: XCTestCase {
    func testServerStartFailurePreventsTunnelAndRemoteRegistration() async {
        let client = MockWebhookClient(registrations: [.success("must-not-register")])
        let server = FakeTunnelServer(startFailure: .expected)
        let process = MockTunnelProcess()
        let manager = makeManager(
            client: client,
            server: server,
            processes: [process]
        )

        do {
            try await manager.start(onEvent: { _ in })
            XCTFail("Expected local WebhookServer startup to fail")
        } catch MockFailure.expected {
            // Expected.
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }

        let clientSnapshot = await client.snapshot()
        let processSnapshot = await process.snapshot()
        let serverSnapshot = await server.snapshot()
        let managerStatus = await manager.statusSnapshot()
        XCTAssertEqual(clientSnapshot.registerCount, 0)
        XCTAssertEqual(processSnapshot.startCount, 0)
        XCTAssertEqual(processSnapshot.stopCount, 0)
        XCTAssertEqual(serverSnapshot.startCount, 1)
        XCTAssertEqual(serverSnapshot.stopCount, 1)
        XCTAssertEqual(managerStatus, .stopped)
    }

    func testTrustRefreshFailureStopsProcessBeforeRegistration() async {
        let client = MockWebhookClient(
            registrations: [],
            publicKey: .failure(.expected)
        )
        let server = FakeTunnelServer()
        let process = MockTunnelProcess()
        let manager = makeManager(
            client: client,
            server: server,
            processes: [process]
        )

        do {
            try await manager.start(onEvent: { _ in })
            XCTFail("Expected trust refresh to fail")
        } catch TunnelError.trustConfigurationFailed {
            // Expected.
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }

        let processSnapshot = await process.snapshot()
        let clientSnapshot = await client.snapshot()
        let serverSnapshot = await server.snapshot()
        let managerStatus = await manager.statusSnapshot()
        XCTAssertFalse(processSnapshot.isRunning)
        XCTAssertEqual(processSnapshot.stopCount, 1)
        XCTAssertEqual(clientSnapshot.registerCount, 0)
        XCTAssertEqual(serverSnapshot.configureCount, 0)
        XCTAssertEqual(serverSnapshot.stopCount, 1)
        XCTAssertEqual(managerStatus, .stopped)
    }

    func testRegistrationFailureStopsUnregisteredProcessAndRollsBackServer() async {
        let client = MockWebhookClient(registrations: [.failure(.expected)])
        let server = FakeTunnelServer()
        let process = MockTunnelProcess()
        let manager = makeManager(
            client: client,
            server: server,
            processes: [process]
        )

        do {
            try await manager.start(onEvent: { _ in })
            XCTFail("Expected webhook registration to fail")
        } catch TunnelError.registrationFailed {
            // Expected.
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }

        let processSnapshot = await process.snapshot()
        let serverSnapshot = await server.snapshot()
        let managerStatus = await manager.statusSnapshot()
        XCTAssertFalse(processSnapshot.isRunning)
        XCTAssertEqual(processSnapshot.stopCount, 1)
        XCTAssertEqual(serverSnapshot.startCount, 1)
        XCTAssertEqual(serverSnapshot.configureCount, 1)
        XCTAssertEqual(serverSnapshot.stopCount, 1)
        XCTAssertEqual(managerStatus, .stopped)
    }

    func testProcessStartFailureAfterLaunchIsStoppedTransactionally() async {
        let client = MockWebhookClient(registrations: [])
        let server = FakeTunnelServer()
        let process = MockTunnelProcess(startFailure: .expected)
        let manager = makeManager(
            client: client,
            server: server,
            processes: [process]
        )

        do {
            try await manager.start(onEvent: { _ in })
            XCTFail("Expected process startup to fail")
        } catch MockFailure.expected {
            // Expected.
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }

        let snapshot = await process.snapshot()
        let managerStatus = await manager.statusSnapshot()
        XCTAssertFalse(snapshot.isRunning)
        XCTAssertEqual(snapshot.stopCount, 1)
        XCTAssertEqual(managerStatus, .stopped)
    }

    func testDirectSuccessorStartRetiresRegisteredTransportBeforeReplacement() async throws {
        let client = MockWebhookClient(registrations: [
            .success("webhook-initial"),
            .success("webhook-replacement"),
        ])
        let server = FakeTunnelServer()
        let initialProcess = MockTunnelProcess()
        let replacementProcess = MockTunnelProcess()
        let manager = makeManager(
            client: client,
            server: server,
            processes: [initialProcess, replacementProcess]
        )

        try await manager.start(onEvent: { _ in })
        try await manager.start(onEvent: { _ in })

        let clientSnapshot = await client.snapshot()
        let initialSnapshot = await initialProcess.snapshot()
        let replacementSnapshot = await replacementProcess.snapshot()
        let managerStatus = await manager.statusSnapshot()
        XCTAssertEqual(clientSnapshot.registerCount, 2)
        XCTAssertEqual(clientSnapshot.deletedWebhookIDs, ["webhook-initial"])
        XCTAssertFalse(initialSnapshot.isRunning)
        XCTAssertEqual(initialSnapshot.stopCount, 1)
        XCTAssertTrue(replacementSnapshot.isRunning)
        XCTAssertEqual(managerStatus, .registered)

        try await manager.stop()
        let finalClientSnapshot = await client.snapshot()
        XCTAssertEqual(
            finalClientSnapshot.deletedWebhookIDs,
            ["webhook-initial", "webhook-replacement"]
        )
    }

    func testWakeFailureIsReturnedAndCannotLeaveProcessOnlyRealtime() async throws {
        let client = MockWebhookClient(registrations: [
            .success("webhook-initial"),
            .failure(.expected),
        ])
        let server = FakeTunnelServer()
        let initialProcess = MockTunnelProcess()
        let wakeProcess = MockTunnelProcess()
        let manager = makeManager(
            client: client,
            server: server,
            processes: [initialProcess, wakeProcess]
        )

        try await manager.start(onEvent: { _ in })
        await manager.suspend()

        do {
            try await manager.handleSleepWake()
            XCTFail("Expected wake registration to fail")
        } catch TunnelError.registrationFailed {
            // Expected: TaskStore must explicitly downgrade to polling-only.
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }

        let wakeSnapshot = await wakeProcess.snapshot()
        let managerStatus = await manager.statusSnapshot()
        XCTAssertFalse(wakeSnapshot.isRunning)
        XCTAssertEqual(wakeSnapshot.stopCount, 1)
        XCTAssertEqual(managerStatus, .serverOnly)

        try await manager.stop()
    }

    func testSuccessfulWakeRestoresOnlyAfterWebhookRegistration() async throws {
        let client = MockWebhookClient(registrations: [
            .success("webhook-initial"),
            .success("webhook-wake"),
        ])
        let server = FakeTunnelServer()
        let initialProcess = MockTunnelProcess()
        let wakeProcess = MockTunnelProcess()
        let manager = makeManager(
            client: client,
            server: server,
            processes: [initialProcess, wakeProcess]
        )

        try await manager.start(onEvent: { _ in })
        let startedStatus = await manager.statusSnapshot()
        XCTAssertEqual(startedStatus, .registered)

        await manager.suspend()
        let suspendedStatus = await manager.statusSnapshot()
        XCTAssertEqual(suspendedStatus, .serverOnly)

        try await manager.handleSleepWake()

        let wakeSnapshot = await wakeProcess.snapshot()
        let clientSnapshot = await client.snapshot()
        let serverSnapshot = await server.snapshot()
        let restoredStatus = await manager.statusSnapshot()
        XCTAssertTrue(wakeSnapshot.isRunning)
        XCTAssertEqual(clientSnapshot.registerCount, 2)
        XCTAssertEqual(clientSnapshot.deletedWebhookIDs, ["webhook-initial"])
        XCTAssertEqual(serverSnapshot.configureCount, 2)
        XCTAssertEqual(restoredStatus, .registered)

        try await manager.stop()
    }

    func testHeartbeatRegistrationFailureSignalsPollingOnlyAndStopsReplacement() async throws {
        let client = MockWebhookClient(registrations: [
            .success("webhook-initial"),
            .failure(.expected),
        ])
        let server = FakeTunnelServer()
        let initialProcess = MockTunnelProcess()
        let replacementProcess = MockTunnelProcess()
        let unavailableProbe = RealtimeUnavailableProbe()
        let manager = makeManager(
            client: client,
            server: server,
            processes: [initialProcess, replacementProcess]
        )

        try await manager.start(
            onEvent: { _ in },
            onRealtimeUnavailable: {
                await unavailableProbe.record()
            }
        )
        await initialProcess.simulateExit()

        await manager.checkProcessHealth()

        let replacementSnapshot = await replacementProcess.snapshot()
        let clientSnapshot = await client.snapshot()
        let unavailableCount = await unavailableProbe.count
        let managerStatus = await manager.statusSnapshot()
        XCTAssertFalse(replacementSnapshot.isRunning)
        XCTAssertEqual(replacementSnapshot.stopCount, 1)
        XCTAssertEqual(clientSnapshot.registerCount, 2)
        XCTAssertEqual(clientSnapshot.deletedWebhookIDs, ["webhook-initial"])
        XCTAssertEqual(unavailableCount, 1)
        XCTAssertEqual(managerStatus, .serverOnly)

        try await manager.stop()
    }

    func testHealthyHeartbeatDoesNotReregisterWebhook() async throws {
        let client = MockWebhookClient(registrations: [.success("webhook-live")])
        let server = FakeTunnelServer()
        let process = MockTunnelProcess()
        let manager = makeManager(
            client: client,
            server: server,
            processes: [process]
        )

        try await manager.start(onEvent: { _ in })
        await manager.checkProcessHealth()

        let clientSnapshot = await client.snapshot()
        let managerStatus = await manager.statusSnapshot()
        XCTAssertEqual(clientSnapshot.registerCount, 1)
        XCTAssertTrue(clientSnapshot.deletedWebhookIDs.isEmpty)
        XCTAssertEqual(managerStatus, .registered)

        try await manager.stop()
    }

    func testHeartbeatServerFailureDeletesWebhookStopsProcessAndSignalsPollingOnly() async throws {
        let client = MockWebhookClient(registrations: [.success("webhook-live")])
        let server = FakeTunnelServer()
        let process = MockTunnelProcess()
        let unavailableProbe = RealtimeUnavailableProbe()
        let manager = makeManager(
            client: client,
            server: server,
            processes: [process]
        )

        try await manager.start(
            onEvent: { _ in },
            onRealtimeUnavailable: {
                await unavailableProbe.record()
            }
        )
        await server.setReady(false)

        await manager.checkProcessHealth()

        let clientSnapshot = await client.snapshot()
        let processSnapshot = await process.snapshot()
        let unavailableCount = await unavailableProbe.count
        let managerStatus = await manager.statusSnapshot()
        XCTAssertEqual(clientSnapshot.deletedWebhookIDs, ["webhook-live"])
        XCTAssertFalse(processSnapshot.isRunning)
        XCTAssertEqual(processSnapshot.stopCount, 1)
        XCTAssertEqual(unavailableCount, 1)
        XCTAssertEqual(managerStatus, .serverOnly)

        try await manager.stop()
    }

    func testStoredWebhookCleanupFailureBlocksReplacementAndRetainsID() async throws {
        let preferences = isolatedPreferences()
        preferences.set(
            "orphan-webhook",
            forKey: TunnelManager.webhookIDPreferenceKey
        )
        let client = MockWebhookClient(
            registrations: [.success("must-not-register")],
            deletions: [.failure(.expected)]
        )
        let server = FakeTunnelServer()
        let process = MockTunnelProcess()
        let manager = makeManager(
            client: client,
            server: server,
            processes: [process],
            preferences: preferences
        )

        do {
            try await manager.start(onEvent: { _ in })
            XCTFail("Expected unresolved webhook cleanup to block registration")
        } catch TunnelError.webhookCleanupFailed {
            // Expected: no new public callback may be registered yet.
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }

        let clientSnapshot = await client.snapshot()
        let processSnapshot = await process.snapshot()
        let serverSnapshot = await server.snapshot()
        let managerStatus = await manager.statusSnapshot()
        XCTAssertEqual(clientSnapshot.registerCount, 0)
        XCTAssertEqual(clientSnapshot.deleteAttempts, ["orphan-webhook"])
        XCTAssertTrue(clientSnapshot.deletedWebhookIDs.isEmpty)
        XCTAssertEqual(processSnapshot.startCount, 0)
        XCTAssertEqual(serverSnapshot.startCount, 1)
        XCTAssertEqual(serverSnapshot.stopCount, 1)
        XCTAssertEqual(managerStatus, .stopped)
        XCTAssertEqual(
            preferences.string(forKey: TunnelManager.webhookIDPreferenceKey),
            "orphan-webhook"
        )
    }

    func testCleanupOnlyManagerDeletesPersistedIDsWithoutOpeningRealtime() async throws {
        let preferences = isolatedPreferences()
        preferences.set(
            ["orphan-one", "orphan-two"],
            forKey: TunnelManager.webhookIDsPreferenceKey
        )
        preferences.set(
            "orphan-one",
            forKey: TunnelManager.webhookIDPreferenceKey
        )
        let client = MockWebhookClient(registrations: [])
        let manager = TunnelManager(
            client: client,
            server: CleanupOnlyWebhookServer(),
            preferences: TunnelPreferencesHandle(preferences)
        )

        try await manager.stop()

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.registerCount, 0)
        XCTAssertEqual(snapshot.deleteAttempts, ["orphan-one", "orphan-two"])
        XCTAssertEqual(snapshot.deletedWebhookIDs, ["orphan-one", "orphan-two"])
        XCTAssertNil(
            preferences.stringArray(forKey: TunnelManager.webhookIDsPreferenceKey)
        )
        XCTAssertNil(
            preferences.string(forKey: TunnelManager.webhookIDPreferenceKey)
        )
        let managerStatus = await manager.statusSnapshot()
        XCTAssertEqual(managerStatus, .stopped)
    }

    func testJoinedCleanupFailureDoesNotSuppressOtherPersistedIDs() async {
        let preferences = isolatedPreferences()
        preferences.set(
            ["orphan-one", "orphan-two"],
            forKey: TunnelManager.webhookIDsPreferenceKey
        )
        preferences.set(
            "orphan-one",
            forKey: TunnelManager.webhookIDPreferenceKey
        )
        let client = OverlappingWebhookClient(
            blockFirstDeletionOf: "orphan-one"
        )
        let manager = TunnelManager(
            client: client,
            server: FakeTunnelServer(),
            processFactory: {
                preconditionFailure("Persisted cleanup must precede process creation")
            },
            preferences: TunnelPreferencesHandle(preferences),
            wakeDelay: .zero,
            heartbeatDelay: .seconds(3_600)
        )

        let startTask = Task {
            try await manager.start(onEvent: { _ in })
        }
        await client.waitUntilDeletionStarted(id: "orphan-one")

        let generationBeforeStop = await manager.lifecycleGenerationSnapshot()
        let stopTask = Task {
            try await manager.stop()
        }
        while await manager.lifecycleGenerationSnapshot() == generationBeforeStop {
            await Task.yield()
        }
        await client.completeBlockedDeletion(.failure(.expected))

        do {
            try await startTask.value
            XCTFail("Expected the joined launch cleanup to fail")
        } catch TunnelError.webhookCleanupFailed {
            // Expected.
        } catch {
            XCTFail("Unexpected start error: \(error)")
        }
        do {
            try await stopTask.value
            XCTFail("Expected stop to report the first cleanup failure")
        } catch TunnelError.webhookCleanupFailed {
            // Expected, after independently cleaning every other stored ID.
        } catch {
            XCTFail("Unexpected stop error: \(error)")
        }

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.deleteAttempts, ["orphan-one", "orphan-two"])
        XCTAssertEqual(snapshot.deletedWebhookIDs, ["orphan-two"])
        XCTAssertEqual(
            preferences.stringArray(forKey: TunnelManager.webhookIDsPreferenceKey),
            ["orphan-one"]
        )
        XCTAssertEqual(
            preferences.string(forKey: TunnelManager.webhookIDPreferenceKey),
            "orphan-one"
        )
    }

    func testStopJoinsInFlightStoredDeletionBeforeCredentialRelease() async {
        let preferences = isolatedPreferences()
        preferences.set(
            ["orphan-webhook"],
            forKey: TunnelManager.webhookIDsPreferenceKey
        )
        preferences.set(
            "orphan-webhook",
            forKey: TunnelManager.webhookIDPreferenceKey
        )
        let client = OverlappingWebhookClient(
            blockFirstDeletionOf: "orphan-webhook"
        )
        let manager = TunnelManager(
            client: client,
            server: CleanupOnlyWebhookServer(),
            preferences: TunnelPreferencesHandle(preferences)
        )

        let suspendTask = Task {
            await manager.suspend()
        }
        await client.waitUntilDeletionStarted(id: "orphan-webhook")

        let generationBeforeStop = await manager.lifecycleGenerationSnapshot()
        let stopTask = Task {
            try await manager.stop()
        }
        while await manager.lifecycleGenerationSnapshot() == generationBeforeStop {
            await Task.yield()
        }
        await client.completeBlockedDeletion(.failure(.expected))
        await suspendTask.value

        do {
            try await stopTask.value
            XCTFail("Credential-releasing stop must observe the joined failure")
        } catch TunnelError.webhookCleanupFailed {
            // Expected: the credential cannot be released after a hidden failure.
        } catch {
            XCTFail("Unexpected stop error: \(error)")
        }

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.deleteAttempts, ["orphan-webhook"])
        XCTAssertTrue(snapshot.deletedWebhookIDs.isEmpty)
        XCTAssertEqual(
            preferences.stringArray(forKey: TunnelManager.webhookIDsPreferenceKey),
            ["orphan-webhook"]
        )
        XCTAssertEqual(
            preferences.string(forKey: TunnelManager.webhookIDPreferenceKey),
            "orphan-webhook"
        )
    }

    func testStopFailsClosedWhenConcurrentCleanupFailureLeavesLedgerID() async throws {
        let preferences = isolatedPreferences()
        preferences.set(
            ["orphan-a", "orphan-b"],
            forKey: TunnelManager.webhookIDsPreferenceKey
        )
        preferences.set(
            "orphan-a",
            forKey: TunnelManager.webhookIDPreferenceKey
        )
        let client = MockWebhookClient(
            registrations: [],
            deletions: [
                .success(()),
                .failure(.expected),
                .success(()),
            ]
        )
        let manager = TunnelManager(
            client: client,
            server: CleanupOnlyWebhookServer(),
            preferences: TunnelPreferencesHandle(preferences)
        )
        let interlock = StopCleanupCheckpointInterlock(blockingID: "orphan-a")
        await manager.setStopCleanupCheckpointForTesting { webhookID in
            await interlock.checkpoint(afterDeleting: webhookID)
        }

        let stopTask = Task {
            try await manager.stop()
        }
        await interlock.waitUntilBlocked()

        // While stop is paused after A succeeds, another lifecycle owns a
        // fast B attempt. Its failure leaves B durable but disappears from the
        // in-flight operation table before stop resumes.
        await manager.suspend()
        await interlock.release()

        do {
            try await stopTask.value
            XCTFail("Stop must fail while any credential-backed cleanup ID remains")
        } catch TunnelError.webhookCleanupFailed {
            // Expected: a non-empty ledger is itself a fail-closed result.
        } catch {
            XCTFail("Unexpected stop error: \(error)")
        }

        let failedSnapshot = await client.snapshot()
        XCTAssertEqual(failedSnapshot.deleteAttempts, ["orphan-a", "orphan-b"])
        XCTAssertEqual(failedSnapshot.deletedWebhookIDs, ["orphan-a"])
        XCTAssertEqual(
            preferences.stringArray(forKey: TunnelManager.webhookIDsPreferenceKey),
            ["orphan-b"]
        )
        XCTAssertEqual(
            preferences.string(forKey: TunnelManager.webhookIDPreferenceKey),
            "orphan-b"
        )

        await manager.setStopCleanupCheckpointForTesting(nil)
        try await manager.stop()

        let recoveredSnapshot = await client.snapshot()
        XCTAssertEqual(
            recoveredSnapshot.deleteAttempts,
            ["orphan-a", "orphan-b", "orphan-b"]
        )
        XCTAssertEqual(
            recoveredSnapshot.deletedWebhookIDs,
            ["orphan-a", "orphan-b"]
        )
        XCTAssertNil(
            preferences.stringArray(forKey: TunnelManager.webhookIDsPreferenceKey)
        )
        XCTAssertNil(
            preferences.string(forKey: TunnelManager.webhookIDPreferenceKey)
        )
    }

    func testConcurrentStopsShareSuccessfulCredentialReleaseOperation() async throws {
        let preferences = isolatedPreferences()
        let client = BlockingStopWebhookClient(
            deletions: [.success(())]
        )
        let server = FakeTunnelServer()
        let process = MockTunnelProcess()
        let sequence = TunnelProcessSequence([process])
        let manager = TunnelManager(
            client: client,
            server: server,
            processFactory: { sequence.next() },
            preferences: TunnelPreferencesHandle(preferences),
            wakeDelay: .zero,
            heartbeatDelay: .seconds(3_600)
        )
        let joinProbe = StopJoinProbe()
        await manager.setStopJoinCheckpointForTesting { joinedExisting in
            await joinProbe.record(joinedExisting: joinedExisting)
        }

        try await manager.start(onEvent: { _ in })
        let generationBeforeStop = await manager.lifecycleGenerationSnapshot()
        let firstStop = Task {
            try await manager.stop()
        }
        await client.waitUntilDeletionIsBlocked()
        let secondStop = Task {
            try await manager.stop()
        }
        await joinProbe.waitUntilExistingOperationJoined()

        // One cancelled waiter must not cancel the retained teardown task or
        // change the result observed by the other concurrent caller.
        firstStop.cancel()
        await client.releaseBlockedDeletion()
        try await firstStop.value
        try await secondStop.value

        let clientSnapshot = await client.snapshot()
        let serverSnapshot = await server.snapshot()
        let processSnapshot = await process.snapshot()
        let generationAfterStop = await manager.lifecycleGenerationSnapshot()
        XCTAssertEqual(clientSnapshot.deleteAttempts, ["webhook-live"])
        XCTAssertEqual(clientSnapshot.deletedWebhookIDs, ["webhook-live"])
        XCTAssertEqual(serverSnapshot.stopCount, 1)
        XCTAssertEqual(processSnapshot.stopCount, 1)
        XCTAssertEqual(generationAfterStop, generationBeforeStop + 1)
        XCTAssertNil(
            preferences.stringArray(forKey: TunnelManager.webhookIDsPreferenceKey)
        )
        XCTAssertNil(
            preferences.string(forKey: TunnelManager.webhookIDPreferenceKey)
        )
    }

    func testConcurrentStopsShareFailureAndLaterStopRetriesLedger() async throws {
        let preferences = isolatedPreferences()
        let client = BlockingStopWebhookClient(
            deletions: [
                .failure(.expected),
                .success(()),
            ]
        )
        let server = FakeTunnelServer()
        let process = MockTunnelProcess()
        let sequence = TunnelProcessSequence([process])
        let manager = TunnelManager(
            client: client,
            server: server,
            processFactory: { sequence.next() },
            preferences: TunnelPreferencesHandle(preferences),
            wakeDelay: .zero,
            heartbeatDelay: .seconds(3_600)
        )
        let joinProbe = StopJoinProbe()
        await manager.setStopJoinCheckpointForTesting { joinedExisting in
            await joinProbe.record(joinedExisting: joinedExisting)
        }

        try await manager.start(onEvent: { _ in })
        let generationBeforeStop = await manager.lifecycleGenerationSnapshot()
        let firstStop = Task {
            try await manager.stop()
        }
        await client.waitUntilDeletionIsBlocked()
        let secondStop = Task {
            try await manager.stop()
        }
        await joinProbe.waitUntilExistingOperationJoined()
        await client.releaseBlockedDeletion()

        do {
            try await firstStop.value
            XCTFail("The first stop waiter must observe provider cleanup failure")
        } catch TunnelError.webhookCleanupFailed {
            // Expected.
        } catch {
            XCTFail("Unexpected first stop error: \(error)")
        }
        do {
            try await secondStop.value
            XCTFail("Every joined stop waiter must observe the same failure")
        } catch TunnelError.webhookCleanupFailed {
            // Expected.
        } catch {
            XCTFail("Unexpected joined stop error: \(error)")
        }

        let failedClientSnapshot = await client.snapshot()
        let failedServerSnapshot = await server.snapshot()
        let failedProcessSnapshot = await process.snapshot()
        let generationAfterFailure = await manager.lifecycleGenerationSnapshot()
        XCTAssertEqual(failedClientSnapshot.deleteAttempts, ["webhook-live"])
        XCTAssertTrue(failedClientSnapshot.deletedWebhookIDs.isEmpty)
        XCTAssertEqual(failedServerSnapshot.stopCount, 1)
        XCTAssertEqual(failedProcessSnapshot.stopCount, 1)
        XCTAssertEqual(generationAfterFailure, generationBeforeStop + 1)
        XCTAssertEqual(
            preferences.stringArray(forKey: TunnelManager.webhookIDsPreferenceKey),
            ["webhook-live"]
        )
        XCTAssertEqual(
            preferences.string(forKey: TunnelManager.webhookIDPreferenceKey),
            "webhook-live"
        )

        await manager.setStopJoinCheckpointForTesting(nil)
        try await manager.stop()

        let recoveredClientSnapshot = await client.snapshot()
        let recoveredServerSnapshot = await server.snapshot()
        let recoveredProcessSnapshot = await process.snapshot()
        XCTAssertEqual(
            recoveredClientSnapshot.deleteAttempts,
            ["webhook-live", "webhook-live"]
        )
        XCTAssertEqual(
            recoveredClientSnapshot.deletedWebhookIDs,
            ["webhook-live"]
        )
        XCTAssertEqual(recoveredServerSnapshot.stopCount, 1)
        XCTAssertEqual(recoveredProcessSnapshot.stopCount, 1)
        XCTAssertNil(
            preferences.stringArray(forKey: TunnelManager.webhookIDsPreferenceKey)
        )
        XCTAssertNil(
            preferences.string(forKey: TunnelManager.webhookIDPreferenceKey)
        )
    }

    func testStopRetainsFailedDeletionAndNextStartCleansBeforeRegistering() async throws {
        let preferences = isolatedPreferences()
        let client = MockWebhookClient(
            registrations: [
                .success("webhook-initial"),
                .success("webhook-reconnected"),
            ],
            deletions: [
                .failure(.expected),
                .success(()),
                .success(()),
            ]
        )
        let server = FakeTunnelServer()
        let initialProcess = MockTunnelProcess()
        let reconnectedProcess = MockTunnelProcess()
        let manager = makeManager(
            client: client,
            server: server,
            processes: [initialProcess, reconnectedProcess],
            preferences: preferences
        )

        try await manager.start(onEvent: { _ in })
        XCTAssertEqual(
            preferences.string(forKey: TunnelManager.webhookIDPreferenceKey),
            "webhook-initial"
        )

        do {
            try await manager.stop()
            XCTFail("Expected provider cleanup failure to be returned")
        } catch TunnelError.webhookCleanupFailed {
            // Expected: local resources are stopped while the ID stays retryable.
        }
        XCTAssertEqual(
            preferences.string(forKey: TunnelManager.webhookIDPreferenceKey),
            "webhook-initial",
            "A failed provider delete must retain the only cleanup capability"
        )

        try await manager.start(onEvent: { _ in })

        let clientBeforeFinalStop = await client.snapshot()
        XCTAssertEqual(
            clientBeforeFinalStop.operations,
            [
                .register,
                .deleteAttempt("webhook-initial"),
                .deleteAttempt("webhook-initial"),
                .deleteSuccess("webhook-initial"),
                .register,
            ]
        )
        XCTAssertEqual(
            preferences.string(forKey: TunnelManager.webhookIDPreferenceKey),
            "webhook-reconnected"
        )
        let initialSnapshot = await initialProcess.snapshot()
        let reconnectedSnapshot = await reconnectedProcess.snapshot()
        XCTAssertEqual(initialSnapshot.stopCount, 1)
        XCTAssertTrue(reconnectedSnapshot.isRunning)

        try await manager.stop()
        let clientAfterFinalStop = await client.snapshot()
        XCTAssertEqual(
            clientAfterFinalStop.deletedWebhookIDs,
            ["webhook-initial", "webhook-reconnected"]
        )
        XCTAssertNil(
            preferences.string(forKey: TunnelManager.webhookIDPreferenceKey)
        )
    }

    func testHeartbeatDeleteFailureBlocksReplacementAndRetainsID() async throws {
        let preferences = isolatedPreferences()
        let client = MockWebhookClient(
            registrations: [.success("webhook-live")],
            deletions: [
                .failure(.expected),
                .failure(.expected),
                .failure(.expected),
            ]
        )
        let server = FakeTunnelServer()
        let process = MockTunnelProcess()
        let unavailableProbe = RealtimeUnavailableProbe()
        let manager = makeManager(
            client: client,
            server: server,
            processes: [process],
            preferences: preferences
        )

        try await manager.start(
            onEvent: { _ in },
            onRealtimeUnavailable: {
                await unavailableProbe.record()
            }
        )
        await process.simulateExit()

        await manager.checkProcessHealth()

        let clientSnapshot = await client.snapshot()
        let unavailableCount = await unavailableProbe.count
        let managerStatus = await manager.statusSnapshot()
        XCTAssertEqual(clientSnapshot.registerCount, 1)
        XCTAssertEqual(
            clientSnapshot.deleteAttempts,
            ["webhook-live", "webhook-live"]
        )
        XCTAssertTrue(clientSnapshot.deletedWebhookIDs.isEmpty)
        XCTAssertEqual(unavailableCount, 1)
        XCTAssertEqual(managerStatus, .serverOnly)
        XCTAssertEqual(
            preferences.string(forKey: TunnelManager.webhookIDPreferenceKey),
            "webhook-live"
        )

        try? await manager.stop()
    }

    func testStopDuringRegistrationDeletesLateWebhookAndLeavesNoTransport() async {
        let client = BlockingWebhookClient()
        let server = FakeTunnelServer()
        let process = MockTunnelProcess()
        let sequence = TunnelProcessSequence([process])
        let manager = TunnelManager(
            client: client,
            server: server,
            processFactory: { sequence.next() },
            preferences: nil,
            wakeDelay: .zero,
            heartbeatDelay: .seconds(3_600)
        )

        let startTask = Task {
            try await manager.start(onEvent: { _ in })
        }
        await client.waitUntilRegistrationStarted()

        let generationBeforeStop = await manager.lifecycleGenerationSnapshot()
        let stopTask = Task {
            try await manager.stop()
        }
        while await manager.lifecycleGenerationSnapshot() == generationBeforeStop {
            await Task.yield()
        }
        await client.completeRegistration(id: "late-webhook")
        do {
            try await stopTask.value
        } catch {
            XCTFail("Late registration cleanup should let stop succeed: \(error)")
        }

        do {
            try await startTask.value
            XCTFail("Expected the obsolete start to be superseded")
        } catch is CancellationError {
            // The retained launch owner is canceled before its late ID is
            // persisted and compensated; cancellation is the supersession.
        } catch TunnelError.lifecycleSuperseded {
            // Expected.
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }

        let processSnapshot = await process.snapshot()
        let clientSnapshot = await client.snapshot()
        let serverSnapshot = await server.snapshot()
        let managerStatus = await manager.statusSnapshot()
        XCTAssertFalse(processSnapshot.isRunning)
        XCTAssertEqual(processSnapshot.stopCount, 1)
        XCTAssertEqual(clientSnapshot.deletedWebhookIDs, ["late-webhook"])
        XCTAssertEqual(serverSnapshot.stopCount, 1)
        XCTAssertEqual(managerStatus, .stopped)
    }

    func testLateRegistrationFailedDeletionRemainsRetryableAfterSupersession() async {
        let preferences = isolatedPreferences()
        let client = BlockingWebhookClient(deletions: [
            .failure(.expected),
            .success(()),
        ])
        let server = FakeTunnelServer()
        let process = MockTunnelProcess()
        let sequence = TunnelProcessSequence([process])
        let manager = TunnelManager(
            client: client,
            server: server,
            processFactory: { sequence.next() },
            preferences: TunnelPreferencesHandle(preferences),
            wakeDelay: .zero,
            heartbeatDelay: .seconds(3_600)
        )

        let startTask = Task {
            try await manager.start(onEvent: { _ in })
        }
        await client.waitUntilRegistrationStarted()

        let generationBeforeStop = await manager.lifecycleGenerationSnapshot()
        let stopTask = Task {
            try await manager.stop()
        }
        while await manager.lifecycleGenerationSnapshot() == generationBeforeStop {
            await Task.yield()
        }
        await client.completeRegistration(id: "late-webhook")

        do {
            try await startTask.value
            XCTFail("Expected failed late cleanup to surface")
        } catch TunnelError.webhookCleanupFailed {
            // Expected: cleanup failure takes precedence over supersession.
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }
        do {
            try await stopTask.value
            XCTFail("Credential-releasing stop must observe late cleanup failure")
        } catch TunnelError.webhookCleanupFailed {
            // Expected.
        } catch {
            XCTFail("Unexpected stop error type: \(type(of: error))")
        }

        let failedCleanup = await client.snapshot()
        XCTAssertEqual(failedCleanup.deleteAttempts, ["late-webhook"])
        XCTAssertTrue(failedCleanup.deletedWebhookIDs.isEmpty)
        XCTAssertEqual(
            preferences.string(forKey: TunnelManager.webhookIDPreferenceKey),
            "late-webhook"
        )

        try? await manager.stop()

        let retriedCleanup = await client.snapshot()
        XCTAssertEqual(
            retriedCleanup.deleteAttempts,
            ["late-webhook", "late-webhook"]
        )
        XCTAssertEqual(retriedCleanup.deletedWebhookIDs, ["late-webhook"])
        XCTAssertNil(
            preferences.string(forKey: TunnelManager.webhookIDPreferenceKey)
        )
    }

    func testServerLossDuringRegistrationDeletesAcceptedWebhookAndRollsBack() async {
        let client = BlockingWebhookClient()
        let server = FakeTunnelServer()
        let process = MockTunnelProcess()
        let sequence = TunnelProcessSequence([process])
        let manager = TunnelManager(
            client: client,
            server: server,
            processFactory: { sequence.next() },
            preferences: nil,
            wakeDelay: .zero,
            heartbeatDelay: .seconds(3_600)
        )

        let startTask = Task {
            try await manager.start(onEvent: { _ in })
        }
        await client.waitUntilRegistrationStarted()
        await server.setReady(false)
        await client.completeRegistration(id: "unreachable-webhook")

        do {
            try await startTask.value
            XCTFail("Expected local server readiness loss to roll back registration")
        } catch TunnelError.serverUnavailable {
            // Expected.
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }

        let processSnapshot = await process.snapshot()
        let clientSnapshot = await client.snapshot()
        let serverSnapshot = await server.snapshot()
        let managerStatus = await manager.statusSnapshot()
        XCTAssertEqual(clientSnapshot.deletedWebhookIDs, ["unreachable-webhook"])
        XCTAssertFalse(processSnapshot.isRunning)
        XCTAssertEqual(processSnapshot.stopCount, 1)
        XCTAssertEqual(serverSnapshot.stopCount, 1)
        XCTAssertEqual(managerStatus, .stopped)
    }

    func testStopStrictlyJoinsHeartbeatBlockedInServerReadiness() async throws {
        let client = MockWebhookClient(registrations: [.success("webhook-a")])
        let server = BlockingHeartbeatServer(blockedReadinessCall: 4)
        let process = MockTunnelProcess()
        let sequence = AnyTunnelProcessSequence([process])
        let unavailable = RealtimeUnavailableProbe()
        let manager = TunnelManager(
            client: client,
            server: server,
            processFactory: { sequence.next() },
            preferences: nil,
            wakeDelay: .zero,
            heartbeatDelay: .milliseconds(1)
        )

        try await manager.start(
            onEvent: { _ in },
            onRealtimeUnavailable: { await unavailable.record() }
        )
        await server.waitUntilReadinessBlocked()
        let generation = await manager.lifecycleGenerationSnapshot()
        let stop = Task { try await manager.stop() }
        while await manager.lifecycleGenerationSnapshot() == generation {
            await Task.yield()
        }
        for _ in 0..<20 { await Task.yield() }

        let pendingClient = await client.snapshot()
        let pendingProcess = await process.snapshot()
        XCTAssertTrue(pendingClient.deleteAttempts.isEmpty)
        XCTAssertEqual(pendingProcess.stopCount, 0)

        await server.releaseReadiness()
        try await stop.value

        let finalClient = await client.snapshot()
        let finalProcess = await process.snapshot()
        let unavailableCount = await unavailable.count
        XCTAssertEqual(finalClient.deletedWebhookIDs, ["webhook-a"])
        XCTAssertEqual(finalProcess.stopCount, 1)
        XCTAssertEqual(unavailableCount, 0)
    }

    func testSuspendJoinsHeartbeatBlockedInProcessCheckBeforeWakePromotesReplacement() async throws {
        let client = MockWebhookClient(registrations: [
            .success("webhook-a"),
            .success("webhook-b"),
        ])
        let server = FakeTunnelServer()
        let firstProcess = BlockingIsRunningProcess()
        let replacementProcess = MockTunnelProcess()
        let sequence = AnyTunnelProcessSequence([firstProcess, replacementProcess])
        let unavailable = RealtimeUnavailableProbe()
        let manager = TunnelManager(
            client: client,
            server: server,
            processFactory: { sequence.next() },
            preferences: nil,
            wakeDelay: .zero,
            heartbeatDelay: .milliseconds(1)
        )

        try await manager.start(
            onEvent: { _ in },
            onRealtimeUnavailable: { await unavailable.record() }
        )
        await firstProcess.waitUntilCheckBlocked()
        await firstProcess.simulateExit()
        let generation = await manager.lifecycleGenerationSnapshot()
        let suspension = Task { await manager.suspend() }
        while await manager.lifecycleGenerationSnapshot() == generation {
            await Task.yield()
        }
        for _ in 0..<20 { await Task.yield() }

        let pendingStopCount = await firstProcess.stopCountSnapshot()
        let pendingClient = await client.snapshot()
        XCTAssertEqual(pendingStopCount, 0)
        XCTAssertTrue(pendingClient.deleteAttempts.isEmpty)

        await firstProcess.releaseCheck()
        await suspension.value
        try await manager.handleSleepWake()

        let beforeFinalStop = await client.snapshot()
        let replacementBeforeFinalStop = await replacementProcess.snapshot()
        let unavailableCount = await unavailable.count
        XCTAssertEqual(beforeFinalStop.deletedWebhookIDs, ["webhook-a"])
        XCTAssertTrue(replacementBeforeFinalStop.isRunning)
        XCTAssertEqual(unavailableCount, 0)

        try await manager.stop()
        let finalClient = await client.snapshot()
        XCTAssertEqual(
            finalClient.deletedWebhookIDs,
            ["webhook-a", "webhook-b"]
        )
    }

    func testStopJoinsHeartbeatBlockedAfterClearingActiveBeforeLedgerCleanup() async throws {
        let preferences = isolatedPreferences()
        let client = MockWebhookClient(registrations: [.success("webhook-a")])
        let process = BlockingFirstStopProcess()
        let sequence = AnyTunnelProcessSequence([process])
        let unavailable = RealtimeUnavailableProbe()
        let manager = TunnelManager(
            client: client,
            server: FakeTunnelServer(),
            processFactory: { sequence.next() },
            preferences: TunnelPreferencesHandle(preferences),
            wakeDelay: .zero,
            heartbeatDelay: .milliseconds(1)
        )

        try await manager.start(
            onEvent: { _ in },
            onRealtimeUnavailable: { await unavailable.record() }
        )
        await process.simulateExit()
        await process.waitUntilFirstStopBlocked()
        let generation = await manager.lifecycleGenerationSnapshot()
        let stop = Task { try await manager.stop() }
        while await manager.lifecycleGenerationSnapshot() == generation {
            await Task.yield()
        }
        for _ in 0..<20 { await Task.yield() }
        let pendingClient = await client.snapshot()
        XCTAssertTrue(pendingClient.deleteAttempts.isEmpty)

        await process.releaseFirstStop()
        try await stop.value

        let snapshot = await client.snapshot()
        let stopCount = await process.stopCountSnapshot()
        let unavailableCount = await unavailable.count
        XCTAssertEqual(snapshot.deleteAttempts, ["webhook-a"])
        XCTAssertEqual(snapshot.deletedWebhookIDs, ["webhook-a"])
        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(unavailableCount, 0)
        XCTAssertNil(
            preferences.stringArray(forKey: TunnelManager.webhookIDsPreferenceKey)
        )
    }

    func testBlockedRegistrationStopIsImmediateFailClosedAndLateIDIsCompensated() async {
        let preferences = isolatedPreferences()
        let client = BlockingWebhookClient()
        let process = MockTunnelProcess()
        let sequence = AnyTunnelProcessSequence([process])
        let manager = TunnelManager(
            client: client,
            server: FakeTunnelServer(),
            processFactory: { sequence.next() },
            preferences: TunnelPreferencesHandle(preferences),
            wakeDelay: .zero,
            heartbeatDelay: .seconds(3_600),
            launchCancellationGrace: .zero
        )

        let start = Task { try await manager.start(onEvent: { _ in }) }
        await client.waitUntilRegistrationStarted()

        do {
            try await manager.stop()
            XCTFail("Unknown registration outcome must fail credential release")
        } catch TunnelError.webhookCleanupFailed {
            // Expected: process is stopped, but remote commit is still unknown.
        } catch {
            XCTFail("Unexpected stop error: \(error)")
        }

        let stoppedProcess = await process.snapshot()
        XCTAssertFalse(stoppedProcess.isRunning)
        XCTAssertEqual(stoppedProcess.stopCount, 1)
        XCTAssertFalse(
            preferences.stringArray(
                forKey: TunnelManager.unresolvedRegistrationTokensPreferenceKey
            )?.isEmpty ?? true
        )

        await client.completeRegistration(id: "late-webhook")
        do {
            try await start.value
            XCTFail("Superseded registration must not promote a transport")
        } catch is CancellationError {
            // Expected from the canceled retained launch owner.
        } catch TunnelError.lifecycleSuperseded {
            // Also valid if generation supersession wins the check.
        } catch {
            XCTFail("Unexpected start error: \(error)")
        }

        let clientSnapshot = await client.snapshot()
        XCTAssertEqual(clientSnapshot.deletedWebhookIDs, ["late-webhook"])
        XCTAssertNil(
            preferences.stringArray(
                forKey: TunnelManager.unresolvedRegistrationTokensPreferenceKey
            )
        )
        XCTAssertNil(
            preferences.stringArray(forKey: TunnelManager.webhookIDsPreferenceKey)
        )
        try? await manager.stop()
    }

    func testConflictAndRateLimitRegistrationFailuresRemainPersistedUnknown() async {
        let errors: [ManusError] = [
            .httpError(statusCode: 409, responseBytes: 0),
            .rateLimited(retryAfter: 30),
        ]

        for error in errors {
            let preferences = isolatedPreferences()
            let client = ManusFailureWebhookClient(registrationError: error)
            let process = MockTunnelProcess()
            let sequence = AnyTunnelProcessSequence([process])
            let manager = TunnelManager(
                client: client,
                server: FakeTunnelServer(),
                processFactory: { sequence.next() },
                preferences: TunnelPreferencesHandle(preferences),
                wakeDelay: .zero,
                heartbeatDelay: .seconds(3_600)
            )

            do {
                try await manager.start(onEvent: { _ in })
                XCTFail("Expected registration failure")
            } catch TunnelError.registrationFailed {
                // Expected.
            } catch {
                XCTFail("Unexpected start error: \(error)")
            }

            XCTAssertFalse(
                preferences.stringArray(
                    forKey: TunnelManager.unresolvedRegistrationTokensPreferenceKey
                )?.isEmpty ?? true
            )
            do {
                try await manager.stop()
                XCTFail("Ambiguous registration must keep credential cleanup pending")
            } catch TunnelError.webhookCleanupFailed {
                // Expected.
            } catch {
                XCTFail("Unexpected stop error: \(error)")
            }
        }
    }

    func testExternalStopJoinsBlockedCallbackWhoseRecursiveStopSeesSingleFlight() async throws {
        let client = MockWebhookClient(registrations: [.success("webhook-a")])
        let server = FakeTunnelServer()
        let process = MockTunnelProcess()
        let sequence = AnyTunnelProcessSequence([process])
        let interlock = AsyncInterlock()
        let manager = TunnelManager(
            client: client,
            server: server,
            processFactory: { sequence.next() },
            preferences: nil,
            wakeDelay: .zero,
            heartbeatDelay: .milliseconds(1)
        )

        try await manager.start(
            onEvent: { _ in },
            onRealtimeUnavailable: {
                await interlock.arriveAndWait()
                try? await manager.stop()
                await interlock.recordCallbackFinished()
            }
        )
        await server.setReady(false)
        await interlock.waitUntilArrived()
        let generation = await manager.lifecycleGenerationSnapshot()
        let externalStop = Task {
            try await manager.stop()
            await interlock.recordExternalStopFinished()
        }
        while await manager.lifecycleGenerationSnapshot() == generation {
            await Task.yield()
        }
        let pending = await interlock.snapshot()
        XCTAssertFalse(pending.callbackFinished)
        XCTAssertFalse(pending.externalStopFinished)

        await interlock.release()
        try await externalStop.value
        let finished = await interlock.snapshot()
        XCTAssertTrue(finished.callbackFinished)
        XCTAssertTrue(finished.externalStopFinished)
    }

    func testCallbackOwnedStopLetsExternalWaiterJoinCallbackWithoutCycle() async throws {
        let client = MockWebhookClient(registrations: [.success("webhook-a")])
        let server = BlockingStopTunnelServer()
        let process = MockTunnelProcess()
        let sequence = AnyTunnelProcessSequence([process])
        let interlock = AsyncInterlock()
        let manager = TunnelManager(
            client: client,
            server: server,
            processFactory: { sequence.next() },
            preferences: nil,
            wakeDelay: .zero,
            heartbeatDelay: .milliseconds(1)
        )

        try await manager.start(
            onEvent: { _ in },
            onRealtimeUnavailable: {
                await interlock.recordArrival()
                try? await manager.stop()
                await interlock.recordCallbackFinished()
            }
        )
        await server.setReady(false)
        await interlock.waitUntilArrived()
        await server.waitUntilStopBlocked()

        let externalStop = Task {
            try await manager.stop()
            await interlock.recordExternalStopFinished()
        }
        for _ in 0..<20 { await Task.yield() }
        let pending = await interlock.snapshot()
        XCTAssertFalse(pending.externalStopFinished)

        await server.releaseStop()
        try await externalStop.value
        let finished = await interlock.snapshot()
        XCTAssertTrue(finished.callbackFinished)
        XCTAssertTrue(finished.externalStopFinished)
    }

    func testSuccessorStartWaitsForRetiringCallbackBeforePromotingNewTransport() async throws {
        let client = MockWebhookClient(registrations: [
            .success("webhook-a"),
            .success("webhook-b"),
        ])
        let server = FakeTunnelServer()
        let firstProcess = MockTunnelProcess()
        let replacementProcess = MockTunnelProcess()
        let sequence = AnyTunnelProcessSequence([firstProcess, replacementProcess])
        let interlock = AsyncInterlock()
        let manager = TunnelManager(
            client: client,
            server: server,
            processFactory: { sequence.next() },
            preferences: nil,
            wakeDelay: .zero,
            heartbeatDelay: .milliseconds(1)
        )

        try await manager.start(
            onEvent: { _ in },
            onRealtimeUnavailable: {
                await interlock.arriveAndWait()
                await interlock.recordCallbackFinished()
            }
        )
        await server.setReady(false)
        await interlock.waitUntilArrived()
        await server.setReady(true)

        let successor = Task { try await manager.start(onEvent: { _ in }) }
        for _ in 0..<20 { await Task.yield() }
        let whileBlocked = await client.snapshot()
        let processWhileBlocked = await replacementProcess.snapshot()
        XCTAssertEqual(whileBlocked.registerCount, 1)
        XCTAssertFalse(processWhileBlocked.isRunning)

        await interlock.release()
        try await successor.value

        let finished = await interlock.snapshot()
        let promotedProcess = await replacementProcess.snapshot()
        let promotedClient = await client.snapshot()
        XCTAssertTrue(finished.callbackFinished)
        XCTAssertTrue(promotedProcess.isRunning)
        XCTAssertEqual(promotedClient.deletedWebhookIDs, ["webhook-a"])

        try await manager.stop()
    }

    func testCallbackOwnedFailedStopStillJoinsCallbackBeforeExternalErrorReturns() async throws {
        let client = CallbackFailureWebhookClient()
        let server = FakeTunnelServer()
        let process = MockTunnelProcess()
        let sequence = AnyTunnelProcessSequence([process])
        let interlock = AsyncInterlock()
        let manager = TunnelManager(
            client: client,
            server: server,
            processFactory: { sequence.next() },
            preferences: nil,
            wakeDelay: .zero,
            heartbeatDelay: .milliseconds(1)
        )

        try await manager.start(
            onEvent: { _ in },
            onRealtimeUnavailable: {
                await interlock.recordArrival()
                do {
                    try await manager.stop()
                } catch {
                    // Expected: both provider delete attempts fail.
                }
                await interlock.recordCallbackFinished()
            }
        )
        await server.setReady(false)
        await interlock.waitUntilArrived()
        await client.waitUntilSecondDeletionBlocked()

        let externalStop = Task { () -> Bool in
            do {
                try await manager.stop()
                return false
            } catch TunnelError.webhookCleanupFailed {
                await interlock.recordExternalStopFinished()
                return true
            } catch {
                return false
            }
        }
        for _ in 0..<20 { await Task.yield() }
        let pending = await interlock.snapshot()
        XCTAssertFalse(pending.externalStopFinished)

        await client.releaseSecondDeletion()
        let externalObservedFailure = await externalStop.value
        XCTAssertTrue(externalObservedFailure)
        let finished = await interlock.snapshot()
        XCTAssertTrue(finished.callbackFinished)
        XCTAssertTrue(finished.externalStopFinished)
    }

    func testUnknownRegistrationBlocksOverlapUntilLateIDIsCompensated() async throws {
        let preferences = isolatedPreferences()
        let client = OverlappingWebhookClient(blockFirstDeletionOf: "webhook-stale")
        let firstProcess = MockTunnelProcess()
        let recoveryProcess = MockTunnelProcess()
        let sequence = TunnelProcessSequence([
            firstProcess,
            recoveryProcess,
        ])
        let manager = TunnelManager(
            client: client,
            server: FakeTunnelServer(),
            processFactory: { sequence.next() },
            preferences: TunnelPreferencesHandle(preferences),
            wakeDelay: .zero,
            heartbeatDelay: .seconds(3_600),
            launchCancellationGrace: .seconds(5)
        )

        let obsoleteStart = Task {
            try await manager.start(onEvent: { _ in })
        }
        await client.waitUntilRegistrationCount(1)
        let generationBeforeStop = await manager.lifecycleGenerationSnapshot()
        let firstStop = Task {
            try await manager.stop()
        }
        while await manager.lifecycleGenerationSnapshot() == generationBeforeStop {
            await Task.yield()
        }

        let currentStart = Task {
            try await manager.start(onEvent: { _ in })
        }
        do {
            try await currentStart.value
            XCTFail("Unknown first registration must block replacement")
        } catch TunnelError.lifecycleSuperseded {
            // Expected: a credential-releasing stop owns the lifecycle epoch.
        } catch {
            XCTFail("Unexpected replacement error: \(error)")
        }

        await client.completeRegistration(at: 0, id: "webhook-stale")
        await client.waitUntilDeletionStarted(id: "webhook-stale")
        await client.completeBlockedDeletion(.success(()))

        do {
            try await obsoleteStart.value
            XCTFail("Expected the obsolete launch owner to be cancelled")
        } catch is CancellationError {
            // Expected after compensating the late accepted ID.
        } catch TunnelError.lifecycleSuperseded {
            // Also valid if generation supersession wins the check.
        } catch TunnelError.webhookCleanupFailed {
            XCTFail("Late accepted ID cleanup unexpectedly failed")
        } catch {
            XCTFail("Unexpected obsolete lifecycle error: \(error)")
        }
        try await firstStop.value

        XCTAssertNil(
            preferences.stringArray(
                forKey: TunnelManager.unresolvedRegistrationTokensPreferenceKey
            )
        )
        XCTAssertNil(
            preferences.stringArray(forKey: TunnelManager.webhookIDsPreferenceKey)
        )

        let recoveryStart = Task {
            try await manager.start(onEvent: { _ in })
        }
        await client.waitUntilRegistrationCount(2)
        let preRecoverySnapshot = await client.snapshot()
        XCTAssertEqual(
            preRecoverySnapshot.deleteAttempts,
            ["webhook-stale"]
        )
        XCTAssertEqual(
            preRecoverySnapshot.deletedWebhookIDs,
            ["webhook-stale"]
        )

        await client.completeRegistration(at: 1, id: "webhook-recovered")
        try await recoveryStart.value
        XCTAssertEqual(
            preferences.stringArray(forKey: TunnelManager.webhookIDsPreferenceKey),
            ["webhook-recovered"]
        )

        try await manager.stop()
        XCTAssertNil(
            preferences.stringArray(forKey: TunnelManager.webhookIDsPreferenceKey)
        )
        XCTAssertNil(
            preferences.string(forKey: TunnelManager.webhookIDPreferenceKey)
        )
    }

    func testRestartReconcilesOnlyExactCallbackAndClearsDurableAttempt() async throws {
        let preferences = isolatedPreferences()
        await seedUnresolvedRegistrationAttempt(in: preferences)

        let client = ReconciliationWebhookClient(webhooks: [
            recoveryWebhook(id: "recovered-exact"),
            recoveryWebhook(
                id: "unrelated-account-webhook",
                url: "https://someone-else.trycloudflare.com/webhook"
            ),
        ])
        let manager = TunnelManager(
            client: client,
            server: CleanupOnlyWebhookServer(),
            preferences: TunnelPreferencesHandle(preferences)
        )

        try await manager.stop()

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.listCount, 1)
        XCTAssertEqual(snapshot.registerCount, 0)
        XCTAssertEqual(snapshot.deleteAttempts, ["recovered-exact"])
        XCTAssertEqual(snapshot.deletedWebhookIDs, ["recovered-exact"])
        XCTAssertNil(
            preferences.stringArray(
                forKey: TunnelManager.unresolvedRegistrationTokensPreferenceKey
            )
        )
        XCTAssertNil(
            preferences.data(
                forKey: TunnelManager.unresolvedRegistrationAttemptsPreferenceKey
            )
        )
        XCTAssertNil(
            preferences.stringArray(forKey: TunnelManager.webhookIDsPreferenceKey)
        )
    }

    func testRestartPersistsEveryExactMatchBeforeDeletingAnyOfThem() async throws {
        let preferences = isolatedPreferences()
        await seedUnresolvedRegistrationAttempt(in: preferences)

        let client = ReconciliationWebhookClient(
            webhooks: [
                recoveryWebhook(id: "recovered-one"),
                recoveryWebhook(id: "recovered-two"),
                recoveryWebhook(
                    id: "unrelated-account-webhook",
                    url: "https://different.trycloudflare.com/webhook"
                ),
            ],
            ledgerPreferences: TunnelPreferencesHandle(preferences)
        )
        let manager = TunnelManager(
            client: client,
            server: CleanupOnlyWebhookServer(),
            preferences: TunnelPreferencesHandle(preferences)
        )

        try await manager.stop()

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.listCount, 1)
        XCTAssertEqual(
            Set(snapshot.deleteAttempts),
            Set(["recovered-one", "recovered-two"])
        )
        XCTAssertEqual(snapshot.deleteAttempts.count, 2)
        XCTAssertEqual(
            Set(snapshot.firstDeletionLedger),
            Set(["recovered-one", "recovered-two"]),
            "Every discovered ID must be durable before the first provider delete"
        )
        XCTAssertFalse(snapshot.deleteAttempts.contains("unrelated-account-webhook"))
        XCTAssertNil(
            preferences.stringArray(
                forKey: TunnelManager.unresolvedRegistrationTokensPreferenceKey
            )
        )
        XCTAssertNil(
            preferences.stringArray(forKey: TunnelManager.webhookIDsPreferenceKey)
        )
    }

    func testRestartDoesNotAttributeInactiveExactCallback() async {
        let preferences = isolatedPreferences()
        await seedUnresolvedRegistrationAttempt(in: preferences)
        let client = ReconciliationWebhookClient(webhooks: [
            recoveryWebhook(id: "inactive-exact", status: .inactive),
        ])
        let manager = TunnelManager(
            client: client,
            server: CleanupOnlyWebhookServer(),
            preferences: TunnelPreferencesHandle(preferences)
        )

        do {
            try await manager.stop()
            XCTFail("An inactive row cannot prove this request created a live callback")
        } catch TunnelError.webhookCleanupFailed {
            // Expected: retain the attempt without deleting provider state.
        } catch {
            XCTFail("Unexpected stop error: \(error)")
        }

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.listCount, 1)
        XCTAssertTrue(snapshot.deleteAttempts.isEmpty)
        XCTAssertFalse(
            preferences.stringArray(
                forKey: TunnelManager.unresolvedRegistrationTokensPreferenceKey
            )?.isEmpty ?? true
        )
        XCTAssertNotNil(
            preferences.data(forKey: TunnelManager.webhookRecoveryStatePreferenceKey)
        )
    }

    func testRestartKeepsAttemptWhenAuthoritativeListIsEmpty() async {
        let preferences = isolatedPreferences()
        await seedUnresolvedRegistrationAttempt(in: preferences)
        let originalTokens = preferences.stringArray(
            forKey: TunnelManager.unresolvedRegistrationTokensPreferenceKey
        )
        let originalAttempts = preferences.data(
            forKey: TunnelManager.unresolvedRegistrationAttemptsPreferenceKey
        )
        let client = ReconciliationWebhookClient(webhooks: [])
        let manager = TunnelManager(
            client: client,
            server: CleanupOnlyWebhookServer(),
            preferences: TunnelPreferencesHandle(preferences)
        )

        do {
            try await manager.stop()
            XCTFail("An empty provider snapshot cannot prove the request was rejected")
        } catch TunnelError.webhookCleanupFailed {
            // Expected until live read-after-create consistency is accepted.
        } catch {
            XCTFail("Unexpected stop error: \(error)")
        }

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.listCount, 1)
        XCTAssertTrue(snapshot.deleteAttempts.isEmpty)
        XCTAssertEqual(
            preferences.stringArray(
                forKey: TunnelManager.unresolvedRegistrationTokensPreferenceKey
            ),
            originalTokens
        )
        XCTAssertEqual(
            preferences.data(
                forKey: TunnelManager.unresolvedRegistrationAttemptsPreferenceKey
            ),
            originalAttempts
        )
    }

    func testRestartKeepsAttemptWhenWebhookListFails() async {
        let preferences = isolatedPreferences()
        await seedUnresolvedRegistrationAttempt(in: preferences)
        let originalTokens = preferences.stringArray(
            forKey: TunnelManager.unresolvedRegistrationTokensPreferenceKey
        )
        let originalAttempts = preferences.data(
            forKey: TunnelManager.unresolvedRegistrationAttemptsPreferenceKey
        )
        let client = ReconciliationWebhookClient(
            webhooks: [],
            listFailure: .expected
        )
        let manager = TunnelManager(
            client: client,
            server: CleanupOnlyWebhookServer(),
            preferences: TunnelPreferencesHandle(preferences)
        )

        do {
            try await manager.stop()
            XCTFail("A failed account inventory cannot resolve an unknown commit")
        } catch TunnelError.webhookCleanupFailed {
            // Expected; the durable attempt remains retryable.
        } catch {
            XCTFail("Unexpected stop error: \(error)")
        }

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.listCount, 1)
        XCTAssertTrue(snapshot.deleteAttempts.isEmpty)
        XCTAssertEqual(
            preferences.stringArray(
                forKey: TunnelManager.unresolvedRegistrationTokensPreferenceKey
            ),
            originalTokens
        )
        XCTAssertEqual(
            preferences.data(
                forKey: TunnelManager.unresolvedRegistrationAttemptsPreferenceKey
            ),
            originalAttempts
        )
    }

    func testRestartRejectsExactCallbackCreatedBeforeAttemptWindow() async {
        let preferences = isolatedPreferences()
        await seedUnresolvedRegistrationAttempt(in: preferences)
        let client = ReconciliationWebhookClient(webhooks: [
            recoveryWebhook(id: "stale-exact", createdAt: 0),
        ])
        let manager = TunnelManager(
            client: client,
            server: CleanupOnlyWebhookServer(),
            preferences: TunnelPreferencesHandle(preferences)
        )

        do {
            try await manager.stop()
            XCTFail("A pre-existing callback must not be attributed to this request")
        } catch TunnelError.webhookCleanupFailed {
            // Expected: exact URL alone is insufficient across the time boundary.
        } catch {
            XCTFail("Unexpected stop error: \(error)")
        }

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.listCount, 1)
        XCTAssertTrue(snapshot.deleteAttempts.isEmpty)
        XCTAssertFalse(
            preferences.stringArray(
                forKey: TunnelManager.unresolvedRegistrationTokensPreferenceKey
            )?.isEmpty ?? true
        )
    }

    func testRestartRejectsExactCallbackCreatedAfterAttemptWindow() async {
        let preferences = isolatedPreferences()
        await seedUnresolvedRegistrationAttempt(in: preferences)
        let farFuture = Int64(Date.now.timeIntervalSince1970) + 1_000
        let client = ReconciliationWebhookClient(webhooks: [
            recoveryWebhook(id: "future-exact", createdAt: farFuture),
        ])
        let manager = TunnelManager(
            client: client,
            server: CleanupOnlyWebhookServer(),
            preferences: TunnelPreferencesHandle(preferences)
        )

        do {
            try await manager.stop()
            XCTFail("A callback outside the upper time bound must not be attributed")
        } catch TunnelError.webhookCleanupFailed {
            // Expected: exact URL and active status still need temporal ownership.
        } catch {
            XCTFail("Unexpected stop error: \(error)")
        }

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.listCount, 1)
        XCTAssertTrue(snapshot.deleteAttempts.isEmpty)
        XCTAssertFalse(
            preferences.stringArray(
                forKey: TunnelManager.unresolvedRegistrationTokensPreferenceKey
            )?.isEmpty ?? true
        )
    }

    func testRestartCleansKnownIDThenReconcilesUnknownRegistration() async throws {
        let preferences = isolatedPreferences()
        preferences.set(
            ["known-before-restart"],
            forKey: TunnelManager.webhookIDsPreferenceKey
        )
        preferences.set(
            "known-before-restart",
            forKey: TunnelManager.webhookIDPreferenceKey
        )
        try seedRecoveryEnvelope(
            in: preferences,
            attempts: [recoveryAttemptRecord()]
        )
        let client = ReconciliationWebhookClient(webhooks: [
            recoveryWebhook(id: "recovered-after-known"),
        ])
        let manager = TunnelManager(
            client: client,
            server: CleanupOnlyWebhookServer(),
            preferences: TunnelPreferencesHandle(preferences)
        )

        try await manager.stop()

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.listCount, 1)
        XCTAssertEqual(
            snapshot.deleteAttempts,
            ["known-before-restart", "recovered-after-known"]
        )
        XCTAssertNil(
            preferences.stringArray(forKey: TunnelManager.webhookIDsPreferenceKey)
        )
        XCTAssertNil(
            preferences.stringArray(
                forKey: TunnelManager.unresolvedRegistrationTokensPreferenceKey
            )
        )
    }

    func testTwoUnknownAttemptsWithSameCallbackDigestDeleteNothing() async throws {
        let preferences = isolatedPreferences()
        try seedRecoveryEnvelope(
            in: preferences,
            attempts: [
                recoveryAttemptRecord(token: UUID().uuidString),
                recoveryAttemptRecord(token: UUID().uuidString),
            ]
        )
        let originalEnvelope = preferences.data(
            forKey: TunnelManager.webhookRecoveryStatePreferenceKey
        )
        let client = ReconciliationWebhookClient(webhooks: [
            recoveryWebhook(id: "ambiguous-exact"),
        ])
        let manager = TunnelManager(
            client: client,
            server: CleanupOnlyWebhookServer(),
            preferences: TunnelPreferencesHandle(preferences)
        )

        do {
            try await manager.stop()
            XCTFail("One provider row cannot be attributed to two unknown requests")
        } catch TunnelError.webhookCleanupFailed {
            // Expected: preserve both attempts and delete no account object.
        } catch {
            XCTFail("Unexpected stop error: \(error)")
        }

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.listCount, 1)
        XCTAssertTrue(snapshot.deleteAttempts.isEmpty)
        XCTAssertEqual(
            preferences.data(forKey: TunnelManager.webhookRecoveryStatePreferenceKey),
            originalEnvelope
        )
    }

    func testWrongTypeLegacyRecoveryStateFailsClosed() async {
        let preferences = isolatedPreferences()
        preferences.set(
            42,
            forKey: TunnelManager.unresolvedRegistrationTokensPreferenceKey
        )
        let client = ReconciliationWebhookClient(webhooks: [
            recoveryWebhook(id: "must-not-delete"),
        ])
        let manager = TunnelManager(
            client: client,
            server: CleanupOnlyWebhookServer(),
            preferences: TunnelPreferencesHandle(preferences)
        )

        do {
            try await manager.stop()
            XCTFail("A wrong-type legacy marker must block credential release")
        } catch TunnelError.webhookCleanupFailed {
            // Expected: malformed legacy data cannot be interpreted or migrated.
        } catch {
            XCTFail("Unexpected stop error: \(error)")
        }

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.listCount, 0)
        XCTAssertTrue(snapshot.deleteAttempts.isEmpty)
        XCTAssertEqual(
            preferences.object(
                forKey: TunnelManager.unresolvedRegistrationTokensPreferenceKey
            ) as? Int,
            42
        )
    }

    func testWrongTypeRecoveryEnvelopeFailsClosedAndIgnoresLegacyMirrors() async {
        let preferences = isolatedPreferences()
        preferences.set(
            "not-data",
            forKey: TunnelManager.webhookRecoveryStatePreferenceKey
        )
        preferences.set(
            ["legacy-must-not-delete"],
            forKey: TunnelManager.webhookIDsPreferenceKey
        )
        preferences.set(
            "legacy-must-not-delete",
            forKey: TunnelManager.webhookIDPreferenceKey
        )
        let client = ReconciliationWebhookClient(webhooks: [])
        let manager = TunnelManager(
            client: client,
            server: CleanupOnlyWebhookServer(),
            preferences: TunnelPreferencesHandle(preferences)
        )

        do {
            try await manager.stop()
            XCTFail("A present but malformed authoritative envelope must fail closed")
        } catch TunnelError.webhookCleanupFailed {
            // Expected: never fall back to non-authoritative legacy mirrors.
        } catch {
            XCTFail("Unexpected stop error: \(error)")
        }

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.listCount, 0)
        XCTAssertTrue(snapshot.deleteAttempts.isEmpty)
        XCTAssertEqual(
            preferences.object(
                forKey: TunnelManager.webhookRecoveryStatePreferenceKey
            ) as? String,
            "not-data"
        )
        XCTAssertEqual(
            preferences.stringArray(forKey: TunnelManager.webhookIDsPreferenceKey),
            ["legacy-must-not-delete"]
        )
    }

    func testRestartRetriesBoundDiscoveredIDWithoutListingAgain() async throws {
        let preferences = isolatedPreferences()
        await seedUnresolvedRegistrationAttempt(in: preferences)
        let firstClient = ReconciliationWebhookClient(
            webhooks: [recoveryWebhook(id: "bound-after-failed-delete")],
            deletions: [.failure(.expected)]
        )
        let firstManager = TunnelManager(
            client: firstClient,
            server: CleanupOnlyWebhookServer(),
            preferences: TunnelPreferencesHandle(preferences)
        )

        do {
            try await firstManager.stop()
            XCTFail("The first provider delete is expected to fail")
        } catch TunnelError.webhookCleanupFailed {
            // Expected after the exact ID has already been atomically bound.
        } catch {
            XCTFail("Unexpected first stop error: \(error)")
        }

        let failedSnapshot = await firstClient.snapshot()
        XCTAssertEqual(failedSnapshot.listCount, 1)
        XCTAssertEqual(failedSnapshot.deleteAttempts, ["bound-after-failed-delete"])
        XCTAssertTrue(failedSnapshot.deletedWebhookIDs.isEmpty)
        XCTAssertEqual(
            preferences.stringArray(forKey: TunnelManager.webhookIDsPreferenceKey),
            ["bound-after-failed-delete"]
        )
        XCTAssertFalse(
            preferences.stringArray(
                forKey: TunnelManager.unresolvedRegistrationTokensPreferenceKey
            )?.isEmpty ?? true
        )

        let retryClient = ReconciliationWebhookClient(
            webhooks: [],
            listFailure: .expected
        )
        let retryManager = TunnelManager(
            client: retryClient,
            server: CleanupOnlyWebhookServer(),
            preferences: TunnelPreferencesHandle(preferences)
        )

        try await retryManager.stop()

        let retrySnapshot = await retryClient.snapshot()
        XCTAssertEqual(retrySnapshot.listCount, 0)
        XCTAssertEqual(retrySnapshot.deleteAttempts, ["bound-after-failed-delete"])
        XCTAssertEqual(retrySnapshot.deletedWebhookIDs, ["bound-after-failed-delete"])
        XCTAssertNil(
            preferences.stringArray(forKey: TunnelManager.webhookIDsPreferenceKey)
        )
        XCTAssertNil(
            preferences.stringArray(
                forKey: TunnelManager.unresolvedRegistrationTokensPreferenceKey
            )
        )
        try assertRecoveryEnvelopeIsEmpty(in: preferences)
    }

    func testLegacyTokenOnlyMarkerStaysFailClosedWithoutAccountDeletion() async {
        let preferences = isolatedPreferences()
        let legacyToken = UUID().uuidString
        preferences.set(
            [legacyToken],
            forKey: TunnelManager.unresolvedRegistrationTokensPreferenceKey
        )
        let client = ReconciliationWebhookClient(webhooks: [
            recoveryWebhook(id: "must-not-delete"),
        ])
        let manager = TunnelManager(
            client: client,
            server: CleanupOnlyWebhookServer(),
            preferences: TunnelPreferencesHandle(preferences)
        )

        do {
            try await manager.stop()
            XCTFail("A legacy marker has no callback identity and needs manual review")
        } catch TunnelError.webhookCleanupFailed {
            // Expected: never guess from an account-wide trycloudflare inventory.
        } catch {
            XCTFail("Unexpected stop error: \(error)")
        }

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.listCount, 0)
        XCTAssertTrue(snapshot.deleteAttempts.isEmpty)
        XCTAssertEqual(
            preferences.stringArray(
                forKey: TunnelManager.unresolvedRegistrationTokensPreferenceKey
            ),
            [legacyToken]
        )
    }

    func testStopBlockedInListRejectsSuccessorStartAndWake() async throws {
        let preferences = isolatedPreferences()
        await seedUnresolvedRegistrationAttempt(in: preferences)
        let client = ReconciliationWebhookClient(
            webhooks: [recoveryWebhook(id: "stop-owned-recovery")],
            blocksFirstList: true
        )
        let server = FakeTunnelServer()
        let manager = TunnelManager(
            client: client,
            server: server,
            processFactory: {
                preconditionFailure("A successor must not create a process during stop")
            },
            preferences: TunnelPreferencesHandle(preferences),
            wakeDelay: .zero,
            heartbeatDelay: .seconds(3_600)
        )

        let stop = Task {
            try await manager.stop()
        }
        await client.waitUntilListIsBlocked()

        do {
            try await manager.start(onEvent: { _ in })
            XCTFail("Successor start must not enter a stop-owned terminal epoch")
        } catch TunnelError.lifecycleSuperseded {
            // Expected before local server or provider work begins.
        } catch {
            XCTFail("Unexpected successor start error: \(error)")
        }
        do {
            try await manager.handleSleepWake()
            XCTFail("Wake must not reopen realtime while stop owns cleanup")
        } catch TunnelError.lifecycleSuperseded {
            // Expected before wake delay or provider work begins.
        } catch {
            XCTFail("Unexpected successor wake error: \(error)")
        }

        let blockedClient = await client.snapshot()
        let blockedServer = await server.snapshot()
        XCTAssertEqual(blockedClient.listCount, 1)
        XCTAssertEqual(blockedClient.registerCount, 0)
        XCTAssertTrue(blockedClient.deleteAttempts.isEmpty)
        XCTAssertEqual(blockedServer.startCount, 0)

        await client.releaseBlockedList()
        try await stop.value

        let finished = await client.snapshot()
        XCTAssertEqual(finished.listCount, 1)
        XCTAssertEqual(finished.deleteAttempts, ["stop-owned-recovery"])
        try assertRecoveryEnvelopeIsEmpty(in: preferences)
    }

    func testOverlappingRestartReconciliationSharesListAndDeleteOperations() async throws {
        let preferences = isolatedPreferences()
        await seedUnresolvedRegistrationAttempt(in: preferences)
        let client = ReconciliationWebhookClient(
            webhooks: [recoveryWebhook(id: "single-flight-recovered")],
            blocksFirstList: true,
            blockedDeletionAttempt: 1
        )
        let server = FakeTunnelServer()
        let manager = TunnelManager(
            client: client,
            server: server,
            processFactory: {
                preconditionFailure("Reconciliation must finish before tunnel creation")
            },
            preferences: TunnelPreferencesHandle(preferences),
            wakeDelay: .zero,
            heartbeatDelay: .seconds(3_600)
        )
        let race = WebhookCleanupRaceInterlock()
        await manager.setWebhookCleanupRaceCheckpointForTesting { checkpoint in
            await race.checkpoint(checkpoint)
        }

        let start = Task {
            try await manager.start(onEvent: { _ in })
        }
        await client.waitUntilListIsBlocked()

        let stop = Task {
            try await manager.stop()
        }
        try await race.waitUntilStopJoinedListing()
        let blockedSnapshot = await client.snapshot()
        XCTAssertEqual(blockedSnapshot.listCount, 1)

        await client.releaseBlockedList()
        try await race.waitUntilStopReturnedListingAndBlocked()
        await client.waitUntilDeletionIsBlocked()
        try await race.waitUntilDeletionWaiterCount(1)
        await race.releaseStopAfterListing()
        try await race.waitUntilDeletionWaiterCount(2)
        await client.releaseBlockedDeletion()

        do {
            try await start.value
            XCTFail("The stop must supersede the in-flight start")
        } catch TunnelError.lifecycleSuperseded {
            // Expected after both callers share reconciliation.
        } catch is CancellationError {
            // Also valid if cancellation wins the lifecycle check.
        } catch {
            XCTFail("Unexpected start error: \(error)")
        }
        try await stop.value

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.listCount, 1)
        XCTAssertEqual(snapshot.deleteAttempts, ["single-flight-recovered"])
        XCTAssertEqual(snapshot.deletedWebhookIDs, ["single-flight-recovered"])
        XCTAssertNil(
            preferences.stringArray(
                forKey: TunnelManager.unresolvedRegistrationTokensPreferenceKey
            )
        )
        try assertRecoveryEnvelopeIsEmpty(in: preferences)
        await manager.setWebhookCleanupRaceCheckpointForTesting(nil)
    }

    func testPostReconciliationDrainJoinsReplacementDeletionTokenForPreviouslyAttemptedID() async throws {
        let preferences = isolatedPreferences()
        let webhookID = "replacement-token-recovered"
        preferences.set(
            [webhookID],
            forKey: TunnelManager.webhookIDsPreferenceKey
        )
        preferences.set(
            webhookID,
            forKey: TunnelManager.webhookIDPreferenceKey
        )
        try seedRecoveryEnvelope(
            in: preferences,
            attempts: [recoveryAttemptRecord()]
        )
        let client = ReconciliationWebhookClient(
            webhooks: [recoveryWebhook(id: webhookID)],
            blocksFirstList: true,
            blockedDeletionAttempt: 2
        )
        let server = FakeTunnelServer()
        let manager = TunnelManager(
            client: client,
            server: server,
            processFactory: {
                preconditionFailure("Reconciliation must finish before tunnel creation")
            },
            preferences: TunnelPreferencesHandle(preferences),
            wakeDelay: .zero,
            heartbeatDelay: .seconds(3_600)
        )
        let race = WebhookCleanupRaceInterlock()
        await manager.setWebhookCleanupRaceCheckpointForTesting { checkpoint in
            await race.checkpoint(checkpoint)
        }

        let start = Task {
            try await manager.start(onEvent: { _ in })
        }
        await client.waitUntilListIsBlocked()

        let stop = Task {
            try await manager.stop()
        }
        try await race.waitUntilStopJoinedListing()
        let afterFirstDeletion = await client.snapshot()
        XCTAssertEqual(afterFirstDeletion.deleteAttempts, [webhookID])
        XCTAssertEqual(afterFirstDeletion.deletedWebhookIDs, [webhookID])

        await client.releaseBlockedList()
        try await race.waitUntilStopReturnedListingAndBlocked()
        await client.waitUntilDeletionIsBlocked()
        try await race.waitUntilDeletionWaiterCount(2)
        await race.releaseStopAfterListing()
        try await race.waitUntilDeletionWaiterCount(3)

        let waiterTokens = await race.deletionWaiterTokensSnapshot()
        XCTAssertEqual(waiterTokens.count, 3)
        XCTAssertNotEqual(waiterTokens[0], waiterTokens[1])
        XCTAssertEqual(waiterTokens[1], waiterTokens[2])
        let whileBlocked = await client.snapshot()
        XCTAssertEqual(whileBlocked.deleteAttempts, [webhookID, webhookID])
        XCTAssertEqual(whileBlocked.deletedWebhookIDs, [webhookID])

        await client.releaseBlockedDeletion()
        do {
            try await start.value
            XCTFail("The stop must supersede the stale reconciliation owner")
        } catch TunnelError.lifecycleSuperseded {
            // Expected after the replacement deletion is joined.
        } catch is CancellationError {
            // Also valid if cancellation wins the lifecycle check.
        } catch {
            XCTFail("Unexpected start error: \(error)")
        }
        try await stop.value

        let finished = await client.snapshot()
        XCTAssertEqual(finished.listCount, 1)
        XCTAssertEqual(finished.registerCount, 0)
        XCTAssertEqual(finished.deleteAttempts, [webhookID, webhookID])
        XCTAssertEqual(finished.deletedWebhookIDs, [webhookID, webhookID])
        let managerStatus = await manager.statusSnapshot()
        XCTAssertEqual(managerStatus, .stopped)
        try assertRecoveryEnvelopeIsEmpty(in: preferences)
        await manager.setWebhookCleanupRaceCheckpointForTesting(nil)
    }

    func testSuccessfulPollCannotPromotePollingOnlyModeToConnected() {
        let reason = "realtime registration unavailable"

        XCTAssertEqual(
            ManusConnectionStatusPolicy.restoredStatus(pollingOnlyReason: reason),
            .degraded(reason: reason)
        )
        XCTAssertEqual(
            ManusConnectionStatusPolicy.restoredStatus(pollingOnlyReason: nil),
            .connected
        )
    }

    private func makeManager(
        client: MockWebhookClient,
        server: FakeTunnelServer,
        processes: [MockTunnelProcess],
        preferences: UserDefaults? = nil
    ) -> TunnelManager {
        let sequence = TunnelProcessSequence(processes)
        return TunnelManager(
            client: client,
            server: server,
            processFactory: { sequence.next() },
            preferences: preferences.map(TunnelPreferencesHandle.init),
            wakeDelay: .zero,
            // Tests invoke health checks directly; keep the automatic loop inert.
            heartbeatDelay: .seconds(3_600)
        )
    }

    private func seedUnresolvedRegistrationAttempt(
        in preferences: UserDefaults
    ) async {
        let client = ManusFailureWebhookClient(
            registrationError: .rateLimited(retryAfter: 30)
        )
        let process = MockTunnelProcess()
        let sequence = AnyTunnelProcessSequence([process])
        let manager = TunnelManager(
            client: client,
            server: FakeTunnelServer(),
            processFactory: { sequence.next() },
            preferences: TunnelPreferencesHandle(preferences),
            wakeDelay: .zero,
            heartbeatDelay: .seconds(3_600)
        )

        do {
            try await manager.start(onEvent: { _ in })
            XCTFail("Expected an unknown registration outcome")
        } catch TunnelError.registrationFailed {
            // Expected; both durable recovery records must survive this owner.
        } catch {
            XCTFail("Unexpected seed error: \(error)")
        }
        XCTAssertFalse(
            preferences.stringArray(
                forKey: TunnelManager.unresolvedRegistrationTokensPreferenceKey
            )?.isEmpty ?? true
        )
        XCTAssertNotNil(
            preferences.data(
                forKey: TunnelManager.unresolvedRegistrationAttemptsPreferenceKey
            )
        )
    }

    private func seedRecoveryEnvelope(
        in preferences: UserDefaults,
        attempts: [[String: Any]]
    ) throws {
        let knownWebhookIDs: [String]
        if let ids = preferences.stringArray(
            forKey: TunnelManager.webhookIDsPreferenceKey
        ) {
            knownWebhookIDs = ids
        } else if let id = preferences.string(
            forKey: TunnelManager.webhookIDPreferenceKey
        ) {
            knownWebhookIDs = [id]
        } else {
            knownWebhookIDs = []
        }
        let tokens = attempts.compactMap { $0["token"] as? String }
        XCTAssertEqual(tokens.count, attempts.count)
        let envelope: [String: Any] = [
            "version": 1,
            "knownWebhookIDs": knownWebhookIDs,
            "unresolvedRegistrationTokens": tokens,
            "unresolvedRegistrationAttempts": attempts,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: envelope,
            options: [.sortedKeys]
        )
        preferences.set(data, forKey: TunnelManager.webhookRecoveryStatePreferenceKey)
    }

    private func assertRecoveryEnvelopeIsEmpty(
        in preferences: UserDefaults
    ) throws {
        let data = try XCTUnwrap(
            preferences.data(forKey: TunnelManager.webhookRecoveryStatePreferenceKey)
        )
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(object["knownWebhookIDs"] as? [String], [])
        XCTAssertEqual(object["unresolvedRegistrationTokens"] as? [String], [])
        XCTAssertEqual(
            (object["unresolvedRegistrationAttempts"] as? [Any])?.count,
            0
        )
    }

    private func recoveryAttemptRecord(
        token: String = UUID().uuidString,
        startedAt: Int64 = Int64(Date.now.timeIntervalSince1970),
        discoveredWebhookIDs: [String] = []
    ) -> [String: Any] {
        [
            "version": 1,
            "token": token,
            "callbackURLSHA256":
                "f053b6ff32bde57dc74f3bcefa649fe7384dac2919ac013c8e8eab2b0155c070",
            "startedAtUnixSeconds": startedAt,
            "discoveredWebhookIDs": discoveredWebhookIDs,
        ]
    }

    private func recoveryWebhook(
        id: String,
        url: String = "https://unit-test.trycloudflare.com/webhook",
        status: ManusWebhook.Status = .active,
        createdAt: Int64 = Int64(Date.now.timeIntervalSince1970)
    ) -> ManusWebhook {
        ManusWebhook(
            id: id,
            url: url,
            status: status,
            createdAt: createdAt
        )
    }

    private func isolatedPreferences() -> UserDefaults {
        let suiteName = "app.devisland.TunnelManagerTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        preferences.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?
                .removePersistentDomain(forName: suiteName)
        }
        return preferences
    }
}

private enum MockFailure: Error {
    case expected
}

private enum WebhookClientOperation: Equatable, Sendable {
    case register
    case deleteAttempt(String)
    case deleteSuccess(String)
}

private actor MockWebhookClient: ManusWebhookClientProtocol {
    struct Snapshot: Sendable {
        let registerCount: Int
        let deleteAttempts: [String]
        let deletedWebhookIDs: [String]
        let operations: [WebhookClientOperation]
    }

    private var registrations: [Result<String, MockFailure>]
    private var deletions: [Result<Void, MockFailure>]
    private let publicKey: Result<String, MockFailure>
    private var registerCount = 0
    private var deleteAttempts: [String] = []
    private var deletedWebhookIDs: [String] = []
    private var operations: [WebhookClientOperation] = []

    init(
        registrations: [Result<String, MockFailure>],
        deletions: [Result<Void, MockFailure>] = [],
        publicKey: Result<String, MockFailure> = .success("test-public-key")
    ) {
        self.registrations = registrations
        self.deletions = deletions
        self.publicKey = publicKey
    }

    func registerWebhook(publicURL: String) throws -> String {
        registerCount += 1
        operations.append(.register)
        guard !registrations.isEmpty else { throw MockFailure.expected }
        return try registrations.removeFirst().get()
    }

    func webhookPublicKey() throws -> String {
        try publicKey.get()
    }

    func deleteWebhook(id: String) throws {
        deleteAttempts.append(id)
        operations.append(.deleteAttempt(id))
        if !deletions.isEmpty {
            try deletions.removeFirst().get()
        }
        deletedWebhookIDs.append(id)
        operations.append(.deleteSuccess(id))
    }

    func registrationFailureDisposition(
        for error: any Error
    ) -> WebhookRegistrationFailureDisposition {
        .definitivelyRejected
    }

    func snapshot() -> Snapshot {
        Snapshot(
            registerCount: registerCount,
            deleteAttempts: deleteAttempts,
            deletedWebhookIDs: deletedWebhookIDs,
            operations: operations
        )
    }
}

private actor ReconciliationWebhookClient: ManusWebhookClientProtocol {
    struct Snapshot: Sendable {
        let listCount: Int
        let registerCount: Int
        let deleteAttempts: [String]
        let deletedWebhookIDs: [String]
        let firstDeletionLedger: [String]
    }

    private let webhooks: [ManusWebhook]
    private let listFailure: MockFailure?
    private let ledgerPreferences: TunnelPreferencesHandle?
    private var deletions: [Result<Void, MockFailure>]
    private var shouldBlockList: Bool
    private var listIsBlocked = false
    private var listContinuation: CheckedContinuation<Void, Never>?
    private let blockedDeletionAttempt: Int?
    private var deletionIsBlocked = false
    private var deletionContinuation: CheckedContinuation<Void, Never>?
    private var listCount = 0
    private var registerCount = 0
    private var deleteAttempts: [String] = []
    private var deletedWebhookIDs: [String] = []
    private var firstDeletionLedger: [String] = []

    init(
        webhooks: [ManusWebhook],
        listFailure: MockFailure? = nil,
        ledgerPreferences: TunnelPreferencesHandle? = nil,
        deletions: [Result<Void, MockFailure>] = [],
        blocksFirstList: Bool = false,
        blockedDeletionAttempt: Int? = nil
    ) {
        self.webhooks = webhooks
        self.listFailure = listFailure
        self.ledgerPreferences = ledgerPreferences
        self.deletions = deletions
        self.shouldBlockList = blocksFirstList
        self.blockedDeletionAttempt = blockedDeletionAttempt
    }

    func webhookPublicKey() -> String {
        "test-public-key"
    }

    func registerWebhook(publicURL: String) throws -> String {
        registerCount += 1
        throw MockFailure.expected
    }

    func listWebhooks() async throws -> [ManusWebhook] {
        listCount += 1
        if shouldBlockList {
            shouldBlockList = false
            listIsBlocked = true
            await withCheckedContinuation { continuation in
                listContinuation = continuation
            }
        }
        if let listFailure { throw listFailure }
        return webhooks
    }

    func deleteWebhook(id: String) async throws {
        deleteAttempts.append(id)
        if deleteAttempts.count == 1 {
            firstDeletionLedger = ledgerPreferences?.defaults?.stringArray(
                forKey: TunnelManager.webhookIDsPreferenceKey
            ) ?? []
        }
        if let blockedDeletionAttempt,
           deleteAttempts.count == blockedDeletionAttempt {
            deletionIsBlocked = true
            await withCheckedContinuation { continuation in
                deletionContinuation = continuation
            }
        }
        if !deletions.isEmpty {
            try deletions.removeFirst().get()
        }
        deletedWebhookIDs.append(id)
    }

    func registrationFailureDisposition(
        for error: any Error
    ) -> WebhookRegistrationFailureDisposition {
        .definitivelyRejected
    }

    func waitUntilListIsBlocked() async {
        while !listIsBlocked || listContinuation == nil {
            await Task.yield()
        }
    }

    func releaseBlockedList() {
        listContinuation?.resume()
        listContinuation = nil
    }

    func waitUntilDeletionIsBlocked() async {
        while !deletionIsBlocked || deletionContinuation == nil {
            await Task.yield()
        }
    }

    func releaseBlockedDeletion() {
        deletionContinuation?.resume()
        deletionContinuation = nil
        deletionIsBlocked = false
    }

    func snapshot() -> Snapshot {
        Snapshot(
            listCount: listCount,
            registerCount: registerCount,
            deleteAttempts: deleteAttempts,
            deletedWebhookIDs: deletedWebhookIDs,
            firstDeletionLedger: firstDeletionLedger
        )
    }
}

private actor FakeTunnelServer: WebhookServerProtocol {
    struct Snapshot: Sendable {
        let configureCount: Int
        let startCount: Int
        let stopCount: Int
    }

    private var configureCount = 0
    private var startCount = 0
    private var stopCount = 0
    private var ready: Bool
    private let startFailure: MockFailure?

    init(ready: Bool = true, startFailure: MockFailure? = nil) {
        self.ready = ready
        self.startFailure = startFailure
    }

    func configure(externalURL: String, signaturePublicKeyPEM: String) {
        configureCount += 1
    }

    func start(onEvent: @escaping @Sendable (WebhookPayload) -> Void) throws {
        startCount += 1
        if let startFailure { throw startFailure }
    }

    func isReady() -> Bool {
        ready
    }

    func setReady(_ ready: Bool) {
        self.ready = ready
    }

    func stop() {
        stopCount += 1
    }

    func snapshot() -> Snapshot {
        Snapshot(
            configureCount: configureCount,
            startCount: startCount,
            stopCount: stopCount
        )
    }
}

private actor BlockingWebhookClient: ManusWebhookClientProtocol {
    struct Snapshot: Sendable {
        let deleteAttempts: [String]
        let deletedWebhookIDs: [String]
    }

    private var registrationStarted = false
    private var registrationContinuation: CheckedContinuation<String, Error>?
    private var deletions: [Result<Void, MockFailure>]
    private var deleteAttempts: [String] = []
    private var deletedWebhookIDs: [String] = []

    init(deletions: [Result<Void, MockFailure>] = []) {
        self.deletions = deletions
    }

    func webhookPublicKey() -> String {
        "test-public-key"
    }

    func registerWebhook(publicURL: String) async throws -> String {
        registrationStarted = true
        return try await withCheckedThrowingContinuation { continuation in
            registrationContinuation = continuation
        }
    }

    func deleteWebhook(id: String) throws {
        deleteAttempts.append(id)
        if !deletions.isEmpty {
            try deletions.removeFirst().get()
        }
        deletedWebhookIDs.append(id)
    }

    func waitUntilRegistrationStarted() async {
        while !registrationStarted {
            await Task.yield()
        }
    }

    func completeRegistration(id: String) {
        registrationContinuation?.resume(returning: id)
        registrationContinuation = nil
    }

    func snapshot() -> Snapshot {
        Snapshot(
            deleteAttempts: deleteAttempts,
            deletedWebhookIDs: deletedWebhookIDs
        )
    }
}

private actor OverlappingWebhookClient: ManusWebhookClientProtocol {
    struct Snapshot: Sendable {
        let deleteAttempts: [String]
        let deletedWebhookIDs: [String]
    }

    private var registrationCount = 0
    private var registrationContinuations: [Int: CheckedContinuation<String, Error>] = [:]
    private var blockedDeletionID: String?
    private var deletionContinuation: CheckedContinuation<Void, Error>?
    private var deleteAttempts: [String] = []
    private var deletedWebhookIDs: [String] = []

    init(blockFirstDeletionOf id: String) {
        blockedDeletionID = id
    }

    func webhookPublicKey() -> String {
        "test-public-key"
    }

    func registerWebhook(publicURL: String) async throws -> String {
        let index = registrationCount
        registrationCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            registrationContinuations[index] = continuation
        }
    }

    func deleteWebhook(id: String) async throws {
        deleteAttempts.append(id)
        if blockedDeletionID == id {
            blockedDeletionID = nil
            try await withCheckedThrowingContinuation { continuation in
                deletionContinuation = continuation
            }
        }
        deletedWebhookIDs.append(id)
    }

    func waitUntilRegistrationCount(_ expected: Int) async {
        while registrationCount < expected {
            await Task.yield()
        }
    }

    func completeRegistration(at index: Int, id: String) {
        let continuation = registrationContinuations.removeValue(forKey: index)
        precondition(continuation != nil, "No registration continuation at index \(index)")
        continuation?.resume(returning: id)
    }

    func waitUntilDeletionStarted(id: String) async {
        while !deleteAttempts.contains(id) || deletionContinuation == nil {
            await Task.yield()
        }
    }

    func completeBlockedDeletion(_ result: Result<Void, MockFailure>) {
        let continuation = deletionContinuation
        deletionContinuation = nil
        precondition(continuation != nil, "No blocked deletion")
        switch result {
        case .success:
            continuation?.resume()
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    func snapshot() -> Snapshot {
        Snapshot(
            deleteAttempts: deleteAttempts,
            deletedWebhookIDs: deletedWebhookIDs
        )
    }
}

private actor BlockingStopWebhookClient: ManusWebhookClientProtocol {
    struct Snapshot: Sendable {
        let deleteAttempts: [String]
        let deletedWebhookIDs: [String]
    }

    private var deletions: [Result<Void, MockFailure>]
    private var shouldBlockDeletion = true
    private var deletionIsBlocked = false
    private var deletionContinuation: CheckedContinuation<Void, Never>?
    private var deleteAttempts: [String] = []
    private var deletedWebhookIDs: [String] = []

    init(deletions: [Result<Void, MockFailure>]) {
        self.deletions = deletions
    }

    func webhookPublicKey() -> String {
        "test-public-key"
    }

    func registerWebhook(publicURL: String) -> String {
        "webhook-live"
    }

    func deleteWebhook(id: String) async throws {
        deleteAttempts.append(id)
        if shouldBlockDeletion {
            shouldBlockDeletion = false
            deletionIsBlocked = true
            await withCheckedContinuation { continuation in
                deletionContinuation = continuation
            }
        }
        guard !deletions.isEmpty else { throw MockFailure.expected }
        try deletions.removeFirst().get()
        deletedWebhookIDs.append(id)
    }

    func waitUntilDeletionIsBlocked() async {
        while !deletionIsBlocked || deletionContinuation == nil {
            await Task.yield()
        }
    }

    func releaseBlockedDeletion() {
        deletionContinuation?.resume()
        deletionContinuation = nil
        deletionIsBlocked = false
    }

    func snapshot() -> Snapshot {
        Snapshot(
            deleteAttempts: deleteAttempts,
            deletedWebhookIDs: deletedWebhookIDs
        )
    }
}

private actor MockTunnelProcess: TunnelProcessProtocol {
    struct Snapshot: Sendable {
        let isRunning: Bool
        let startCount: Int
        let stopCount: Int
    }

    private var running = false
    private var startCount = 0
    private var stopCount = 0
    private let startFailure: MockFailure?

    init(startFailure: MockFailure? = nil) {
        self.startFailure = startFailure
    }

    var isRunning: Bool { running }

    func start() throws -> URL {
        startCount += 1
        // Model the important partial-failure boundary: the child exists
        // before URL acquisition can fail.
        running = true
        if let startFailure { throw startFailure }
        return URL(string: "https://unit-test.trycloudflare.com")!
    }

    func stop() {
        stopCount += 1
        running = false
    }

    func simulateExit() {
        running = false
    }

    func snapshot() -> Snapshot {
        Snapshot(
            isRunning: running,
            startCount: startCount,
            stopCount: stopCount
        )
    }
}

private actor RealtimeUnavailableProbe {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

private actor AsyncInterlock {
    struct Snapshot: Sendable {
        let callbackFinished: Bool
        let externalStopFinished: Bool
    }

    private var arrived = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var callbackFinished = false
    private(set) var externalStopFinished = false

    func arriveAndWait() async {
        arrived = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func recordArrival() {
        arrived = true
    }

    func waitUntilArrived() async {
        while !arrived {
            await Task.yield()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }

    func recordCallbackFinished() {
        callbackFinished = true
    }

    func recordExternalStopFinished() {
        precondition(callbackFinished, "External stop returned before callback retired")
        externalStopFinished = true
    }

    func snapshot() -> Snapshot {
        Snapshot(
            callbackFinished: callbackFinished,
            externalStopFinished: externalStopFinished
        )
    }
}

private actor BlockingHeartbeatServer: WebhookServerProtocol {
    private let blockedReadinessCall: Int
    private var readinessCallCount = 0
    private var readinessContinuation: CheckedContinuation<Void, Never>?
    private var readinessBlocked = false
    private var ready = true

    init(blockedReadinessCall: Int) {
        self.blockedReadinessCall = blockedReadinessCall
    }

    func configure(externalURL: String, signaturePublicKeyPEM: String) {}
    func start(onEvent: @escaping @Sendable (WebhookPayload) -> Void) {}

    func isReady() async -> Bool {
        readinessCallCount += 1
        if readinessCallCount == blockedReadinessCall {
            readinessBlocked = true
            await withCheckedContinuation { continuation in
                readinessContinuation = continuation
            }
        }
        return ready
    }

    func waitUntilReadinessBlocked() async {
        while !readinessBlocked || readinessContinuation == nil {
            await Task.yield()
        }
    }

    func releaseReadiness() {
        readinessContinuation?.resume()
        readinessContinuation = nil
    }

    func stop() {}
}

private actor BlockingStopTunnelServer: WebhookServerProtocol {
    private var ready = true
    private var stopBlocked = false
    private var stopContinuation: CheckedContinuation<Void, Never>?

    func configure(externalURL: String, signaturePublicKeyPEM: String) {}
    func start(onEvent: @escaping @Sendable (WebhookPayload) -> Void) {}
    func isReady() -> Bool { ready }
    func setReady(_ ready: Bool) { self.ready = ready }

    func stop() async {
        stopBlocked = true
        await withCheckedContinuation { continuation in
            stopContinuation = continuation
        }
    }

    func waitUntilStopBlocked() async {
        while !stopBlocked || stopContinuation == nil {
            await Task.yield()
        }
    }

    func releaseStop() {
        stopContinuation?.resume()
        stopContinuation = nil
    }
}

private actor BlockingIsRunningProcess: TunnelProcessProtocol {
    private var running = false
    private var checkBlocked = false
    private var checkContinuation: CheckedContinuation<Void, Never>?
    private var stopCount = 0

    var isRunning: Bool {
        get async {
            checkBlocked = true
            await withCheckedContinuation { continuation in
                checkContinuation = continuation
            }
            return running
        }
    }

    func start() -> URL {
        running = true
        return URL(string: "https://blocked-health.trycloudflare.com")!
    }

    func stop() {
        stopCount += 1
        running = false
    }

    func simulateExit() { running = false }

    func waitUntilCheckBlocked() async {
        while !checkBlocked || checkContinuation == nil {
            await Task.yield()
        }
    }

    func releaseCheck() {
        checkContinuation?.resume()
        checkContinuation = nil
    }

    func stopCountSnapshot() -> Int { stopCount }
}

private actor BlockingFirstStopProcess: TunnelProcessProtocol {
    private var running = false
    private var stopCount = 0
    private var firstStopBlocked = false
    private var stopContinuation: CheckedContinuation<Void, Never>?

    var isRunning: Bool { running }

    func start() -> URL {
        running = true
        return URL(string: "https://blocked-stop.trycloudflare.com")!
    }

    func stop() async {
        stopCount += 1
        running = false
        if stopCount == 1 {
            firstStopBlocked = true
            await withCheckedContinuation { continuation in
                stopContinuation = continuation
            }
        }
    }

    func simulateExit() { running = false }

    func waitUntilFirstStopBlocked() async {
        while !firstStopBlocked || stopContinuation == nil {
            await Task.yield()
        }
    }

    func releaseFirstStop() {
        stopContinuation?.resume()
        stopContinuation = nil
    }

    func stopCountSnapshot() -> Int { stopCount }
}

private actor ManusFailureWebhookClient: ManusWebhookClientProtocol {
    private let registrationError: ManusError
    private let classifier = ManusAPIClient(apiKey: "classification-only")

    init(registrationError: ManusError) {
        self.registrationError = registrationError
    }

    func webhookPublicKey() -> String { "test-public-key" }
    func registerWebhook(publicURL: String) throws -> String {
        throw registrationError
    }
    func deleteWebhook(id: String) {}
    func registrationFailureDisposition(
        for error: any Error
    ) async -> WebhookRegistrationFailureDisposition {
        await classifier.registrationFailureDisposition(for: error)
    }
}

private actor CallbackFailureWebhookClient: ManusWebhookClientProtocol {
    private var deletionAttemptCount = 0
    private var secondDeletionBlocked = false
    private var secondDeletionContinuation: CheckedContinuation<Void, Never>?

    func webhookPublicKey() -> String { "test-public-key" }
    func registerWebhook(publicURL: String) -> String { "webhook-a" }

    func deleteWebhook(id: String) async throws {
        deletionAttemptCount += 1
        if deletionAttemptCount == 2 {
            secondDeletionBlocked = true
            await withCheckedContinuation { continuation in
                secondDeletionContinuation = continuation
            }
        }
        throw MockFailure.expected
    }

    func waitUntilSecondDeletionBlocked() async {
        while !secondDeletionBlocked || secondDeletionContinuation == nil {
            await Task.yield()
        }
    }

    func releaseSecondDeletion() {
        secondDeletionContinuation?.resume()
        secondDeletionContinuation = nil
    }
}

private final class AnyTunnelProcessSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [any TunnelProcessProtocol]

    init(_ processes: [any TunnelProcessProtocol]) {
        self.processes = processes
    }

    func next() -> any TunnelProcessProtocol {
        lock.lock()
        defer { lock.unlock() }
        precondition(!processes.isEmpty, "Unexpected extra process launch")
        return processes.removeFirst()
    }
}

private actor StopCleanupCheckpointInterlock {
    private let blockingID: String
    private var isBlocked = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(blockingID: String) {
        self.blockingID = blockingID
    }

    func checkpoint(afterDeleting webhookID: String) async {
        guard webhookID == blockingID else { return }
        isBlocked = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilBlocked() async {
        while !isBlocked {
            await Task.yield()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor WebhookCleanupRaceInterlock {
    private static let waitTimeout = Duration.seconds(2)
    private static let pollInterval = Duration.milliseconds(1)

    private var stopJoinedListing = false
    private var stopReturnedListing = false
    private var stopListingContinuation: CheckedContinuation<Void, Never>?
    private var deletionWaiterTokens: [UUID] = []
    private var lastCheckpoint = "none"

    func checkpoint(_ checkpoint: WebhookCleanupRaceCheckpoint) async {
        switch checkpoint {
        case .listingWillAwait(let joinedExisting):
            lastCheckpoint = "listingWillAwait(joinedExisting: \(joinedExisting))"
            if joinedExisting {
                stopJoinedListing = true
            }
        case .listingDidReturn(let joinedExisting):
            lastCheckpoint = "listingDidReturn(joinedExisting: \(joinedExisting))"
            guard joinedExisting else { return }
            stopReturnedListing = true
            await withCheckedContinuation { continuation in
                stopListingContinuation = continuation
            }
        case .deletionWillAwait(let operationToken):
            lastCheckpoint = "deletionWillAwait(operationToken: \(operationToken.uuidString))"
            deletionWaiterTokens.append(operationToken)
        }
    }

    func waitUntilStopJoinedListing() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.waitTimeout)
        try Task.checkCancellation()
        while !stopJoinedListing {
            guard clock.now < deadline else {
                throw timeoutError(waitingFor: "stop to join the in-flight webhook listing")
            }
            try await clock.sleep(for: Self.pollInterval)
        }
    }

    func waitUntilStopReturnedListingAndBlocked() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.waitTimeout)
        try Task.checkCancellation()
        while !stopReturnedListing || stopListingContinuation == nil {
            guard clock.now < deadline else {
                throw timeoutError(
                    waitingFor: "stop to return from listing and block at its checkpoint"
                )
            }
            try await clock.sleep(for: Self.pollInterval)
        }
    }

    func waitUntilDeletionWaiterCount(_ expected: Int) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.waitTimeout)
        try Task.checkCancellation()
        while deletionWaiterTokens.count < expected {
            guard clock.now < deadline else {
                throw timeoutError(
                    waitingFor: "at least \(expected) deletion waiter token(s)"
                )
            }
            try await clock.sleep(for: Self.pollInterval)
        }
    }

    func deletionWaiterTokensSnapshot() -> [UUID] {
        deletionWaiterTokens
    }

    func releaseStopAfterListing() {
        stopListingContinuation?.resume()
        stopListingContinuation = nil
    }

    private func timeoutError(waitingFor expectation: String) -> WebhookCleanupRaceWaitTimeout {
        WebhookCleanupRaceWaitTimeout(
            expectation: expectation,
            lastCheckpoint: lastCheckpoint,
            stopJoinedListing: stopJoinedListing,
            stopReturnedListing: stopReturnedListing,
            stopListingIsBlocked: stopListingContinuation != nil,
            deletionWaiterTokens: deletionWaiterTokens
        )
    }
}

private struct WebhookCleanupRaceWaitTimeout: LocalizedError {
    let expectation: String
    let lastCheckpoint: String
    let stopJoinedListing: Bool
    let stopReturnedListing: Bool
    let stopListingIsBlocked: Bool
    let deletionWaiterTokens: [UUID]

    var errorDescription: String? {
        let tokens = deletionWaiterTokens.map { $0.uuidString }.joined(separator: ", ")
        return """
        Timed out after 2 seconds waiting for \(expectation); \
        lastCheckpoint=\(lastCheckpoint), \
        stopJoinedListing=\(stopJoinedListing), \
        stopReturnedListing=\(stopReturnedListing), \
        stopListingIsBlocked=\(stopListingIsBlocked), \
        deletionWaiterTokens=[\(tokens)]
        """
    }
}

private actor StopJoinProbe {
    private var didJoinExistingOperation = false

    func record(joinedExisting: Bool) {
        didJoinExistingOperation = didJoinExistingOperation || joinedExisting
    }

    func waitUntilExistingOperationJoined() async {
        while !didJoinExistingOperation {
            await Task.yield()
        }
    }
}

private final class TunnelProcessSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [MockTunnelProcess]

    init(_ processes: [MockTunnelProcess]) {
        self.processes = processes
    }

    func next() -> any TunnelProcessProtocol {
        lock.lock()
        defer { lock.unlock() }
        precondition(!processes.isEmpty, "Unexpected extra process launch")
        return processes.removeFirst()
    }
}
