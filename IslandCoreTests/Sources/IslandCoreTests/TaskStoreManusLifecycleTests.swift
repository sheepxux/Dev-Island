import Foundation
import XCTest
@testable import IslandCore

@MainActor
final class TaskStoreManusLifecycleTests: XCTestCase {
    func testDisconnectSupersedesValidationBeforeItCanPersistOrRestart() async throws {
        let client = LifecycleManusClient(steps: [.blocked])
        let keychain = LifecycleKeychainProbe()
        let store = makeStore(
            clients: ["candidate": client],
            keychain: keychain,
            tasks: [task(id: "cloud", source: "manus"), task(id: "local", source: "codex")]
        )

        let configuration = Task {
            try await store.configureAPIKey("candidate")
        }
        try await waitUntil { await client.fetchCount == 1 }

        try await store.clearAPIKey()
        await client.completeNext(.success([]))

        do {
            try await configuration.value
            XCTFail("Expected obsolete validation to be cancelled")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }

        let keychainSnapshot = keychain.snapshot()
        XCTAssertTrue(keychainSnapshot.savedKeys.isEmpty)
        XCTAssertEqual(keychainSnapshot.deleteCount, 1)
        XCTAssertEqual(store.apiKeyStatus, .notConfigured)
        XCTAssertEqual(store.connectionStatus, .disconnected)
        XCTAssertEqual(store.tasks.map(\.identity), [TaskIdentity(source: "codex", id: "local")])
    }

    func testLatestConcurrentConfigurationIsTheOnlyKeyPersisted() async throws {
        let firstClient = LifecycleManusClient(steps: [.blocked, .immediate(.success([]))])
        let secondClient = LifecycleManusClient(steps: [.blocked, .immediate(.success([]))])
        let keychain = LifecycleKeychainProbe()
        let store = makeStore(
            clients: ["first": firstClient, "second": secondClient],
            keychain: keychain
        )

        let firstConfiguration = Task {
            try await store.configureAPIKey("first")
        }
        try await waitUntil { await firstClient.fetchCount == 1 }

        let secondConfiguration = Task {
            try await store.configureAPIKey("second")
        }
        try await waitUntil { await secondClient.fetchCount == 1 }

        await secondClient.completeNext(.success([]))
        try await secondConfiguration.value

        await firstClient.completeNext(.success([]))
        do {
            try await firstConfiguration.value
            XCTFail("Expected the older configuration to be cancelled")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }

        let keychainSnapshot = keychain.snapshot()
        XCTAssertEqual(keychainSnapshot.savedKeys, ["second"])
        XCTAssertEqual(store.apiKeyStatus, .valid)
        XCTAssertEqual(
            store.connectionStatus,
            .degraded(reason: ManusRealtimeTrust.pollingOnlyReason)
        )

        try await store.clearAPIKey()
    }

    func testPollingOnlyFallbackPreservesLocalSessionsAndNeverClaimsRealtime() async throws {
        let cloudTask = task(id: "cloud", source: "manus")
        let localTask = task(id: "local", source: "codex")
        let client = LifecycleManusClient(steps: [
            .immediate(.success([])),
            .immediate(.success([cloudTask])),
        ])
        let keychain = LifecycleKeychainProbe()
        let store = makeStore(
            clients: ["polling-only": client],
            keychain: keychain,
            tasks: [localTask]
        )

        try await store.configureAPIKey("polling-only")
        try await waitUntil {
            store.tasks.contains(where: { $0.identity == cloudTask.identity })
        }

        XCTAssertEqual(store.apiKeyStatus, .valid)
        XCTAssertEqual(
            store.connectionStatus,
            .degraded(reason: ManusRealtimeTrust.pollingOnlyReason)
        )
        XCTAssertEqual(
            store.tasks.map { "\($0.source):\($0.id)" }.sorted(),
            ["codex:local", "manus:cloud"]
        )

        try await store.clearAPIKey()
    }

    func testReplacingServiceRejectsLateSnapshotFromPreviousKey() async throws {
        let oldClient = LifecycleManusClient(steps: [
            .immediate(.success([])),
            .blocked,
        ])
        let newTask = task(id: "new", source: "manus")
        let newClient = LifecycleManusClient(steps: [
            .immediate(.success([])),
            .immediate(.success([newTask])),
        ])
        let keychain = LifecycleKeychainProbe()
        let store = makeStore(
            clients: ["old": oldClient, "new": newClient],
            keychain: keychain
        )

        try await store.configureAPIKey("old")
        try await waitUntil { await oldClient.fetchCount == 2 }

        let replacement = Task {
            try await store.configureAPIKey("new")
        }
        try await waitUntil { await newClient.fetchCount == 1 }
        // Joinable polling shutdown deliberately waits for an in-flight
        // provider request. Deliver a late old-key result while replacement
        // is stopping that generation; it must never survive into new state.
        await oldClient.completeNext(.success([
            task(id: "obsolete", source: "manus"),
        ]))
        try await replacement.value
        try await waitUntil {
            store.tasks.contains(where: { $0.identity == newTask.identity })
        }

        XCTAssertEqual(store.tasks.map(\.identity), [newTask.identity])
        XCTAssertEqual(keychain.snapshot().savedKeys, ["old", "new"])

        try await store.clearAPIKey()
    }

    func testUnauthorizedCandidateNeverOverwritesKeychain() async {
        let client = LifecycleManusClient(steps: [
            .immediate(.failure(.unauthorized)),
        ])
        let keychain = LifecycleKeychainProbe()
        let store = makeStore(
            clients: ["invalid": client],
            keychain: keychain
        )

        do {
            try await store.configureAPIKey("invalid")
            XCTFail("Expected unauthorized validation")
        } catch ManusError.unauthorized {
            // Expected.
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }

        let keychainSnapshot = keychain.snapshot()
        XCTAssertTrue(keychainSnapshot.savedKeys.isEmpty)
        XCTAssertEqual(keychainSnapshot.deleteCount, 0)
        XCTAssertEqual(store.apiKeyStatus, .invalid)
        XCTAssertEqual(store.connectionStatus, .disconnected)
    }

    func testRuntimeUnauthorizedInvalidatesVisibleAccountState() async throws {
        let client = LifecycleManusClient(steps: [
            .immediate(.success([])),
            .blocked,
        ])
        let keychain = LifecycleKeychainProbe()
        let store = makeStore(
            clients: ["revoked-later": client],
            keychain: keychain
        )

        try await store.configureAPIKey("revoked-later")
        try await waitUntil { await client.fetchCount == 2 }
        await client.completeNext(.failure(.unauthorized))
        try await waitUntil {
            store.apiKeyStatus == .invalid && store.connectionStatus == .disconnected
        }

        XCTAssertEqual(keychain.snapshot().savedKeys, ["revoked-later"])

        try await store.clearAPIKey()
    }

    func testKeychainDeleteFailureNeverPretendsCredentialWasRemoved() async throws {
        let client = LifecycleManusClient(steps: [
            .immediate(.success([])),
            .blocked,
        ])
        let keychain = LifecycleKeychainProbe()
        let store = makeStore(
            clients: ["retained": client],
            keychain: keychain,
            tasks: [task(id: "cloud", source: "manus"), task(id: "local", source: "codex")]
        )

        try await store.configureAPIKey("retained")
        try await waitUntil { await client.fetchCount == 2 }
        keychain.setDeleteFailure(true)
        // Polling stop is a true join. Resolve the deliberately blocked test
        // transport so Disconnect can reach the Keychain failure under test.
        await client.completeNext(.success([]))

        do {
            try await store.clearAPIKey()
            XCTFail("Expected Keychain deletion failure")
        } catch LifecycleKeychainProbe.ProbeError.expected {
            // Expected.
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }

        XCTAssertEqual(store.apiKeyStatus, .valid)
        XCTAssertEqual(store.connectionStatus, .disconnected)
        XCTAssertEqual(store.tasks.map(\.identity), [TaskIdentity(source: "codex", id: "local")])
        XCTAssertEqual(keychain.snapshot().deleteCount, 1)
        keychain.setDeleteFailure(false)
        try await store.clearAPIKey()
        XCTAssertEqual(store.apiKeyStatus, .notConfigured)
    }

    func testCleanupFailureRetainsCredentialAndManagerForDisconnectRetry() async throws {
        let tunnel = SleepWakeTunnelProbe(cleanupFailuresRemaining: 1)
        let keychain = LifecycleKeychainProbe()
        keychain.save("retained-for-cleanup")
        let unusedClient = LifecycleManusClient(steps: [])
        let dependencies = TaskStoreManusDependencies(
            makeClient: { _ in unusedClient },
            saveAPIKey: { keychain.save($0) },
            loadAPIKey: { keychain.load() },
            deleteAPIKey: { try keychain.delete() }
        )
        let store = TaskStore.sleepWakeFixture(
            tunnel: tunnel,
            dependencies: dependencies,
            tasks: [
                task(id: "cloud", source: "manus"),
                task(id: "local", source: "codex"),
            ],
            apiKeyStatus: .valid
        )

        do {
            try await store.clearAPIKey()
            XCTFail("Expected remote cleanup failure")
        } catch SleepWakeTunnelProbe.ProbeError.expectedCleanupFailure {
            // Expected.
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }

        XCTAssertEqual(keychain.load(), "retained-for-cleanup")
        XCTAssertEqual(keychain.snapshot().deleteCount, 0)
        let firstStopCount = await tunnel.stopCount
        XCTAssertEqual(firstStopCount, 1)
        XCTAssertEqual(store.apiKeyStatus, .valid)
        XCTAssertEqual(
            store.tasks.map(\.identity),
            [TaskIdentity(source: "codex", id: "local")]
        )
        XCTAssertEqual(
            store.connectionStatus,
            .degraded(reason: ManusCredentialRemovalPolicy.cleanupPendingReason)
        )

        try await store.clearAPIKey()

        XCTAssertNil(keychain.load())
        XCTAssertEqual(keychain.snapshot().deleteCount, 1)
        let secondStopCount = await tunnel.stopCount
        XCTAssertEqual(secondStopCount, 2)
        XCTAssertEqual(store.apiKeyStatus, .notConfigured)
        XCTAssertEqual(store.connectionStatus, .disconnected)
    }

    func testReplacementKeyCannotOverwriteCredentialBeforeOldWebhookCleanup() async throws {
        let tunnel = SleepWakeTunnelProbe(cleanupFailuresRemaining: 1)
        let keychain = LifecycleKeychainProbe()
        keychain.save("existing-key")
        let candidateClient = LifecycleManusClient(steps: [
            .immediate(.success([])),
        ])
        let dependencies = TaskStoreManusDependencies(
            makeClient: { key in
                precondition(key == "candidate-key")
                return candidateClient
            },
            saveAPIKey: { keychain.save($0) },
            loadAPIKey: { keychain.load() },
            deleteAPIKey: { try keychain.delete() }
        )
        let store = TaskStore.sleepWakeFixture(
            tunnel: tunnel,
            dependencies: dependencies,
            apiKeyStatus: .valid
        )

        do {
            try await store.configureAPIKey("candidate-key")
            XCTFail("Expected old webhook cleanup to block credential replacement")
        } catch SleepWakeTunnelProbe.ProbeError.expectedCleanupFailure {
            // Expected.
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }

        XCTAssertEqual(keychain.load(), "existing-key")
        XCTAssertEqual(keychain.snapshot().savedKeys, ["existing-key"])
        XCTAssertEqual(store.apiKeyStatus, .valid)
        XCTAssertEqual(
            store.connectionStatus,
            .degraded(reason: ManusCredentialRemovalPolicy.cleanupPendingReason)
        )

        try await store.configureAPIKey("candidate-key")

        XCTAssertEqual(keychain.load(), "candidate-key")
        XCTAssertEqual(
            keychain.snapshot().savedKeys,
            ["existing-key", "candidate-key"]
        )
        let stopCount = await tunnel.stopCount
        XCTAssertGreaterThanOrEqual(stopCount, 2)

        try await store.clearAPIKey()
    }

    func testReplacementSaveFailureRetiresOldServicesAndRetryCanConfigure() async throws {
        let tunnel = SleepWakeTunnelProbe()
        let keychain = LifecycleKeychainProbe()
        keychain.save("existing-key")
        keychain.setSaveFailure(true)
        let candidateClient = LifecycleManusClient(steps: [
            .immediate(.success([])),
            .immediate(.success([])),
        ])
        let dependencies = TaskStoreManusDependencies(
            makeClient: { _ in candidateClient },
            saveAPIKey: { try keychain.saveThrowing($0) },
            loadAPIKey: { keychain.load() },
            deleteAPIKey: { try keychain.delete() }
        )
        let store = TaskStore.sleepWakeFixture(
            tunnel: tunnel,
            dependencies: dependencies,
            tasks: [
                task(id: "cloud", source: "manus"),
                task(id: "local", source: "codex"),
            ],
            apiKeyStatus: .valid
        )

        do {
            try await store.configureAPIKey("candidate-key")
            XCTFail("Expected Keychain save failure")
        } catch LifecycleKeychainProbe.ProbeError.expected {
            // Expected.
        }

        XCTAssertEqual(keychain.load(), "existing-key")
        XCTAssertEqual(store.apiKeyStatus, .valid)
        XCTAssertEqual(store.connectionStatus, .disconnected)
        XCTAssertEqual(
            store.tasks.map(\.identity),
            [TaskIdentity(source: "codex", id: "local")]
        )
        let firstStopCount = await tunnel.stopCount
        let firstFetchCount = await candidateClient.fetchCount
        XCTAssertEqual(firstStopCount, 1)
        XCTAssertEqual(firstFetchCount, 1)

        keychain.setSaveFailure(false)
        try await store.configureAPIKey("candidate-key")

        XCTAssertEqual(keychain.load(), "candidate-key")
        XCTAssertEqual(store.apiKeyStatus, .valid)
        let stopCountAfterRetry = await tunnel.stopCount
        XCTAssertEqual(stopCountAfterRetry, 1)
        try await store.clearAPIKey()
    }

    func testReplacementSaveFailureWithoutPersistedCredentialAllowsDisconnect() async throws {
        let tunnel = SleepWakeTunnelProbe()
        let keychain = LifecycleKeychainProbe()
        keychain.save("existing-key")
        keychain.setSaveFailure(true, clearingStoredValue: true)
        let candidateClient = LifecycleManusClient(steps: [
            .immediate(.success([])),
        ])
        let dependencies = TaskStoreManusDependencies(
            makeClient: { _ in candidateClient },
            saveAPIKey: { try keychain.saveThrowing($0) },
            loadAPIKey: { keychain.load() },
            deleteAPIKey: { try keychain.delete() }
        )
        let store = TaskStore.sleepWakeFixture(
            tunnel: tunnel,
            dependencies: dependencies,
            apiKeyStatus: .valid
        )

        do {
            try await store.configureAPIKey("candidate-key")
            XCTFail("Expected Keychain save failure")
        } catch LifecycleKeychainProbe.ProbeError.expected {
            // Expected.
        }

        XCTAssertNil(keychain.load())
        XCTAssertEqual(store.apiKeyStatus, .notConfigured)
        XCTAssertEqual(store.connectionStatus, .disconnected)
        let fetchCount = await candidateClient.fetchCount
        let stopCountAfterFailure = await tunnel.stopCount
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(stopCountAfterFailure, 1)

        try await store.clearAPIKey()

        XCTAssertEqual(store.apiKeyStatus, .notConfigured)
        XCTAssertEqual(store.connectionStatus, .disconnected)
        let stopCountAfterDisconnect = await tunnel.stopCount
        XCTAssertEqual(stopCountAfterDisconnect, 1)
        XCTAssertEqual(keychain.snapshot().deleteCount, 1)
    }

    func testWakeWaitsForBlockedSuspendBeforeRestartingRealtime() async throws {
        let tunnel = SleepWakeTunnelProbe(blockSuspend: true)
        let store = TaskStore.sleepWakeFixture(tunnel: tunnel)

        store.handleSystemWillSleep()
        try await waitUntil { await tunnel.suspendStartCount == 1 }

        let wake = Task { await store.handleSystemDidWake() }
        try await Task.sleep(for: .milliseconds(40))
        let wakeStartsBeforeSuspendCompletes = await tunnel.wakeStartCount
        XCTAssertEqual(wakeStartsBeforeSuspendCompletes, 0)

        await tunnel.releaseSuspend()
        await wake.value

        let events = await tunnel.events
        XCTAssertEqual(
            events,
            ["suspend-start", "suspend-end", "wake-start", "wake-end"]
        )
    }

    func testDuplicateWakeDoesNotRestartRealtimeTwice() async throws {
        let tunnel = SleepWakeTunnelProbe()
        let store = TaskStore.sleepWakeFixture(tunnel: tunnel)

        store.handleSystemWillSleep()
        try await waitUntil { await tunnel.suspendEndCount == 1 }
        await store.handleSystemDidWake()
        await store.handleSystemDidWake()

        let wakeStartCount = await tunnel.wakeStartCount
        XCTAssertEqual(wakeStartCount, 1)
    }

    func testDisconnectDuringBlockedSuspendPreventsObsoleteWakeRecovery() async throws {
        let tunnel = SleepWakeTunnelProbe(blockSuspend: true)
        let keychain = LifecycleKeychainProbe()
        let unusedClient = LifecycleManusClient(steps: [])
        let dependencies = TaskStoreManusDependencies(
            makeClient: { _ in unusedClient },
            saveAPIKey: { keychain.save($0) },
            loadAPIKey: { keychain.load() },
            deleteAPIKey: { try keychain.delete() }
        )
        let store = TaskStore.sleepWakeFixture(
            tunnel: tunnel,
            dependencies: dependencies
        )

        store.handleSystemWillSleep()
        try await waitUntil { await tunnel.suspendStartCount == 1 }
        let obsoleteWake = Task { await store.handleSystemDidWake() }

        try await store.clearAPIKey()
        await tunnel.releaseSuspend()
        await obsoleteWake.value

        let wakeStartCount = await tunnel.wakeStartCount
        let stopCount = await tunnel.stopCount
        XCTAssertEqual(wakeStartCount, 0)
        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(store.connectionStatus, .disconnected)
        XCTAssertEqual(store.apiKeyStatus, .notConfigured)
    }

    func testNewSleepSupersedesInFlightWakeFailureWithoutFalseDegradation() async throws {
        let tunnel = SleepWakeTunnelProbe(blockWake: true, failWake: true)
        let store = TaskStore.sleepWakeFixture(tunnel: tunnel)

        store.handleSystemWillSleep()
        try await waitUntil { await tunnel.suspendEndCount == 1 }

        let obsoleteWake = Task { await store.handleSystemDidWake() }
        try await waitUntil { await tunnel.wakeStartCount == 1 }

        store.handleSystemWillSleep()
        try await waitUntil { await tunnel.suspendEndCount == 2 }
        await tunnel.releaseWake()
        await obsoleteWake.value

        XCTAssertEqual(store.connectionStatus, .disconnected)
        let stopCount = await tunnel.stopCount
        XCTAssertEqual(stopCount, 0)

        await tunnel.setWakeBehavior(block: false, fail: false)
        await store.handleSystemDidWake()
        let wakeStartCount = await tunnel.wakeStartCount
        XCTAssertEqual(wakeStartCount, 2)
    }

    func testShutdownWaitsForBlockedTunnelAndConcurrentCallersShareStop() async throws {
        let tunnel = SleepWakeTunnelProbe(blockStop: true)
        let keychain = LifecycleKeychainProbe()
        let unusedClient = LifecycleManusClient(steps: [])
        let dependencies = TaskStoreManusDependencies(
            makeClient: { _ in unusedClient },
            saveAPIKey: { keychain.save($0) },
            loadAPIKey: { keychain.load() },
            deleteAPIKey: { try keychain.delete() }
        )
        let store = TaskStore.sleepWakeFixture(
            tunnel: tunnel,
            dependencies: dependencies
        )
        let completions = ShutdownCompletionProbe()

        let first = Task {
            let result = await store.shutdown()
            await completions.record(result)
            return result
        }
        try await waitUntil { await tunnel.stopCount == 1 }
        let completionsWhileBlocked = await completions.results
        XCTAssertTrue(completionsWhileBlocked.isEmpty)

        let second = Task {
            let result = await store.shutdown()
            await completions.record(result)
            return result
        }
        await Task.yield()
        let concurrentStopCount = await tunnel.stopCount
        XCTAssertEqual(concurrentStopCount, 1)

        await tunnel.releaseStop()
        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertEqual(firstResult, .completed)
        XCTAssertEqual(secondResult, .completed)
        let repeatedResult = await store.shutdown()
        XCTAssertEqual(repeatedResult, .completed)

        let finalStopCount = await tunnel.stopCount
        let finalStopEndCount = await tunnel.stopEndCount
        let finalCompletions = await completions.results
        XCTAssertEqual(finalStopCount, 1)
        XCTAssertEqual(finalStopEndCount, 1)
        XCTAssertEqual(finalCompletions, [.completed, .completed])
        XCTAssertEqual(keychain.snapshot().deleteCount, 0)
    }

    func testCancellingShutdownCallerDoesNotCancelSharedOperation() async throws {
        let tunnel = SleepWakeTunnelProbe(blockStop: true)
        let store = TaskStore.sleepWakeFixture(tunnel: tunnel)
        let completions = ShutdownCompletionProbe()

        let cancelledCaller = Task {
            let result = await store.shutdown()
            await completions.record(result)
            return result
        }
        try await waitUntil { await tunnel.stopCount == 1 }

        cancelledCaller.cancel()
        await Task.yield()
        let completionsAfterCancellation = await completions.results
        let stopEndCountAfterCancellation = await tunnel.stopEndCount
        XCTAssertTrue(cancelledCaller.isCancelled)
        XCTAssertTrue(completionsAfterCancellation.isEmpty)
        XCTAssertEqual(stopEndCountAfterCancellation, 0)

        let joiningCaller = Task { await store.shutdown() }
        await tunnel.releaseStop()

        let cancelledCallerResult = await cancelledCaller.value
        let joiningCallerResult = await joiningCaller.value
        let stopCount = await tunnel.stopCount
        XCTAssertEqual(cancelledCallerResult, .completed)
        XCTAssertEqual(joiningCallerResult, .completed)
        XCTAssertEqual(stopCount, 1)
    }

    func testShutdownJoinsBlockedBootstrapWithoutResurrectingServices() async throws {
        let gate = BootstrapGate()
        let keychain = LifecycleKeychainProbe()
        let client = LifecycleManusClient(steps: [])
        let dependencies = TaskStoreManusDependencies(
            makeClient: { _ in client },
            saveAPIKey: { keychain.save($0) },
            loadAPIKey: { keychain.load() },
            deleteAPIKey: { try keychain.delete() },
            awaitBootstrapPermission: { await gate.wait() }
        )
        let store = TaskStore.bootstrapLifecycleFixture(dependencies: dependencies)
        let completions = ShutdownCompletionProbe()
        try await waitUntil { await gate.waiterCount == 1 }

        let shutdown = Task {
            let result = await store.shutdown()
            await completions.record(result)
            return result
        }
        try await waitUntil { store.shutdownStartedForTesting }

        let completionsWhileBlocked = await completions.results
        XCTAssertTrue(completionsWhileBlocked.isEmpty)
        XCTAssertFalse(store.ownsRuntimeResourcesForTesting)
        XCTAssertEqual(store.localHookServiceStatus, .stopped)

        await gate.releaseAll()
        let result = await shutdown.value
        XCTAssertEqual(result, .completed)
        XCTAssertFalse(store.ownsRuntimeResourcesForTesting)
        XCTAssertEqual(store.localHookServiceStatus, .stopped)

        do {
            try await store.configureAPIKey("must-not-restart")
            XCTFail("Expected Configure after shutdown to be cancelled")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }
        do {
            try await store.clearAPIKey()
            XCTFail("Expected Disconnect after shutdown to be cancelled")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }

        let keychainSnapshot = keychain.snapshot()
        let fetchCount = await client.fetchCount
        XCTAssertEqual(keychainSnapshot.loadCount, 0)
        XCTAssertEqual(keychainSnapshot.deleteCount, 0)
        XCTAssertEqual(fetchCount, 0)
        XCTAssertFalse(store.ownsRuntimeResourcesForTesting)
    }

    func testShutdownSupersedesRegisteredDisconnectBeforeCleanupBodyStarts() async throws {
        let removalGate = BootstrapGate()
        let tunnel = SleepWakeTunnelProbe(blockStop: true)
        let keychain = LifecycleKeychainProbe()
        keychain.save("registered-before-quit")
        let unusedClient = LifecycleManusClient(steps: [])
        let dependencies = TaskStoreManusDependencies(
            makeClient: { _ in unusedClient },
            saveAPIKey: { keychain.save($0) },
            loadAPIKey: { keychain.load() },
            deleteAPIKey: { try keychain.delete() },
            awaitCredentialRemovalPermission: { await removalGate.wait() }
        )
        let store = TaskStore.sleepWakeFixture(
            tunnel: tunnel,
            dependencies: dependencies,
            apiKeyStatus: .valid
        )
        let completions = ShutdownCompletionProbe()

        let disconnect = Task { try await store.clearAPIKey() }
        try await waitUntil { await removalGate.waiterCount == 1 }

        let shutdown = Task {
            let result = await store.shutdown()
            await completions.record(result)
            return result
        }
        try await waitUntil { store.shutdownStartedForTesting }
        let stopCountBeforeRemovalRelease = await tunnel.stopCount
        XCTAssertEqual(stopCountBeforeRemovalRelease, 0)

        await removalGate.releaseAll()
        try await waitUntil { await tunnel.stopCount == 1 }
        let completionsWhileTunnelBlocked = await completions.results
        XCTAssertTrue(completionsWhileTunnelBlocked.isEmpty)

        await tunnel.releaseStop()
        let shutdownResult = await shutdown.value
        XCTAssertEqual(shutdownResult, .completed)
        do {
            try await disconnect.value
            XCTFail("Expected registered Disconnect to be superseded by Quit")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }

        let stopCount = await tunnel.stopCount
        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(keychain.load(), "registered-before-quit")
        XCTAssertEqual(keychain.snapshot().deleteCount, 0)
    }

    func testShutdownJoinsQueuedLocalRetryAndPreventsRestartAfterStop() async throws {
        let precedingGate = BootstrapGate()
        let restartProbe = InvocationProbe()
        let precedingLifecycle = Task {
            await precedingGate.wait()
        }
        try await waitUntil { await precedingGate.waiterCount == 1 }
        let store = TaskStore.localHookLifecycleFixture(
            precedingLifecycle: precedingLifecycle,
            restart: { _ in await restartProbe.record() }
        )
        let completions = ShutdownCompletionProbe()

        store.retryLocalHookService()
        let shutdown = Task {
            let result = await store.shutdown()
            await completions.record(result)
            return result
        }
        try await waitUntil { store.shutdownStartedForTesting }

        let completionsWhileQueued = await completions.results
        XCTAssertTrue(completionsWhileQueued.isEmpty)
        XCTAssertFalse(store.ownsRuntimeResourcesForTesting)

        await precedingGate.releaseAll()
        let result = await shutdown.value
        let restartCount = await restartProbe.count
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(restartCount, 0)
        XCTAssertEqual(store.localHookServiceStatus, .stopped)
        XCTAssertFalse(store.ownsRuntimeResourcesForTesting)

        store.retryLocalHookService()
        await Task.yield()
        let countAfterTerminalRetry = await restartProbe.count
        XCTAssertEqual(countAfterTerminalRetry, 0)
    }

    func testShutdownCleanupFailureRetainsCredentialAndMemoizesPendingResult() async {
        let tunnel = SleepWakeTunnelProbe(cleanupFailuresRemaining: 1)
        let keychain = LifecycleKeychainProbe()
        keychain.save("retained-on-quit")
        let unusedClient = LifecycleManusClient(steps: [])
        let dependencies = TaskStoreManusDependencies(
            makeClient: { _ in unusedClient },
            saveAPIKey: { keychain.save($0) },
            loadAPIKey: { keychain.load() },
            deleteAPIKey: { try keychain.delete() }
        )
        let store = TaskStore.sleepWakeFixture(
            tunnel: tunnel,
            dependencies: dependencies,
            apiKeyStatus: .valid
        )

        let firstResult = await store.shutdown()
        let repeatedResult = await store.shutdown()

        XCTAssertEqual(firstResult, .cleanupPending)
        XCTAssertEqual(repeatedResult, .cleanupPending)
        XCTAssertEqual(keychain.load(), "retained-on-quit")
        XCTAssertEqual(keychain.snapshot().deleteCount, 0)
        let stopCount = await tunnel.stopCount
        XCTAssertEqual(stopCount, 1)
    }

    func testShutdownJoinsInFlightDisconnectWithoutDeletingCredential() async throws {
        let tunnel = SleepWakeTunnelProbe(blockStop: true)
        let keychain = LifecycleKeychainProbe()
        keychain.save("disconnecting-on-quit")
        let unusedClient = LifecycleManusClient(steps: [])
        let dependencies = TaskStoreManusDependencies(
            makeClient: { _ in unusedClient },
            saveAPIKey: { keychain.save($0) },
            loadAPIKey: { keychain.load() },
            deleteAPIKey: { try keychain.delete() }
        )
        let store = TaskStore.sleepWakeFixture(
            tunnel: tunnel,
            dependencies: dependencies,
            apiKeyStatus: .valid
        )

        let disconnect = Task {
            try await store.clearAPIKey()
        }
        try await waitUntil { await tunnel.stopCount == 1 }

        let shutdown = Task { await store.shutdown() }
        try await waitUntil { store.shutdownStartedForTesting }
        await tunnel.releaseStop()

        let shutdownResult = await shutdown.value
        XCTAssertEqual(shutdownResult, .completed)
        do {
            try await disconnect.value
            XCTFail("Expected shutdown to supersede credential deletion")
        } catch is CancellationError {
            // Expected: tunnel cleanup finished, but Quit owns the generation.
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }

        XCTAssertEqual(keychain.load(), "disconnecting-on-quit")
        XCTAssertEqual(keychain.snapshot().deleteCount, 0)
        let stopCount = await tunnel.stopCount
        let stopEndCount = await tunnel.stopEndCount
        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(stopEndCount, 1)
    }

    func testShutdownMapsInFlightDisconnectCleanupFailureToPending() async throws {
        let tunnel = SleepWakeTunnelProbe(
            blockStop: true,
            cleanupFailuresRemaining: 1
        )
        let keychain = LifecycleKeychainProbe()
        keychain.save("cleanup-pending-on-quit")
        let unusedClient = LifecycleManusClient(steps: [])
        let dependencies = TaskStoreManusDependencies(
            makeClient: { _ in unusedClient },
            saveAPIKey: { keychain.save($0) },
            loadAPIKey: { keychain.load() },
            deleteAPIKey: { try keychain.delete() }
        )
        let store = TaskStore.sleepWakeFixture(
            tunnel: tunnel,
            dependencies: dependencies,
            apiKeyStatus: .valid
        )

        let disconnect = Task {
            try await store.clearAPIKey()
        }
        try await waitUntil { await tunnel.stopCount == 1 }

        let shutdown = Task { await store.shutdown() }
        try await waitUntil { store.shutdownStartedForTesting }
        await tunnel.releaseStop()

        let shutdownResult = await shutdown.value
        XCTAssertEqual(shutdownResult, .cleanupPending)
        do {
            try await disconnect.value
            XCTFail("Expected the in-flight cleanup failure")
        } catch SleepWakeTunnelProbe.ProbeError.expectedCleanupFailure {
            // Expected.
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }

        XCTAssertEqual(keychain.load(), "cleanup-pending-on-quit")
        XCTAssertEqual(keychain.snapshot().deleteCount, 0)
        let stopCount = await tunnel.stopCount
        XCTAssertEqual(stopCount, 1)
    }

    func testShutdownJoinsSleepSuspensionBeforeStoppingTunnel() async throws {
        let tunnel = SleepWakeTunnelProbe(blockSuspend: true)
        let store = TaskStore.sleepWakeFixture(tunnel: tunnel)
        let completions = ShutdownCompletionProbe()

        store.handleSystemWillSleep()
        try await waitUntil { await tunnel.suspendStartCount == 1 }

        let shutdown = Task {
            let result = await store.shutdown()
            await completions.record(result)
            return result
        }
        try await waitUntil { store.shutdownStartedForTesting }

        let stopCountWhileSuspended = await tunnel.stopCount
        let completionsWhileSuspended = await completions.results
        XCTAssertEqual(stopCountWhileSuspended, 0)
        XCTAssertTrue(completionsWhileSuspended.isEmpty)

        await tunnel.releaseSuspend()
        let result = await shutdown.value
        let finalStopCount = await tunnel.stopCount
        let events = await tunnel.events
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(finalStopCount, 1)
        XCTAssertEqual(events, ["suspend-start", "suspend-end", "stop"])
    }

    private func makeStore(
        clients: [String: LifecycleManusClient],
        keychain: LifecycleKeychainProbe,
        tasks: [AgentTask] = []
    ) -> TaskStore {
        let dependencies = TaskStoreManusDependencies(
            makeClient: { key in
                guard let client = clients[key] else {
                    preconditionFailure("Missing lifecycle client fixture")
                }
                return client
            },
            saveAPIKey: { key in keychain.save(key) },
            loadAPIKey: { keychain.load() },
            deleteAPIKey: { try keychain.delete() }
        )
        return TaskStore.manusLifecycleFixture(
            dependencies: dependencies,
            tasks: tasks
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor @Sendable () async -> Bool
    ) async throws {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw URLError(.timedOut)
    }

    private func task(id: String, source: String) -> AgentTask {
        AgentTask(
            id: id,
            source: source,
            title: "Lifecycle fixture",
            status: .running,
            createdAt: .now,
            updatedAt: .now,
            taskURL: source == "manus" ? "https://manus.im/app/fixture" : ""
        )
    }
}

private actor SleepWakeTunnelProbe: ManusTunnelLifecycleProtocol {
    enum ProbeError: Error {
        case expectedWakeFailure
        case expectedCleanupFailure
    }

    private(set) var events: [String] = []
    private(set) var suspendStartCount = 0
    private(set) var suspendEndCount = 0
    private(set) var wakeStartCount = 0
    private(set) var stopCount = 0
    private(set) var stopEndCount = 0
    private var blockStop: Bool
    private var blockSuspend: Bool
    private var blockWake: Bool
    private var failWake: Bool
    private var cleanupFailuresRemaining: Int
    private var stopContinuation: CheckedContinuation<Void, Never>?
    private var suspendContinuation: CheckedContinuation<Void, Never>?
    private var wakeContinuation: CheckedContinuation<Void, Never>?

    init(
        blockStop: Bool = false,
        blockSuspend: Bool = false,
        blockWake: Bool = false,
        failWake: Bool = false,
        cleanupFailuresRemaining: Int = 0
    ) {
        self.blockStop = blockStop
        self.blockSuspend = blockSuspend
        self.blockWake = blockWake
        self.failWake = failWake
        self.cleanupFailuresRemaining = cleanupFailuresRemaining
    }

    func start(
        onEvent: @escaping @Sendable (WebhookPayload) -> Void,
        onRealtimeUnavailable: @escaping @Sendable () async -> Void
    ) async throws {}

    func stop() async throws {
        stopCount += 1
        events.append("stop")
        if blockStop {
            await withCheckedContinuation { continuation in
                stopContinuation = continuation
            }
        }
        if cleanupFailuresRemaining > 0 {
            cleanupFailuresRemaining -= 1
            throw ProbeError.expectedCleanupFailure
        }
        stopEndCount += 1
    }

    func suspend() async {
        suspendStartCount += 1
        events.append("suspend-start")
        if blockSuspend {
            await withCheckedContinuation { continuation in
                suspendContinuation = continuation
            }
        }
        suspendEndCount += 1
        events.append("suspend-end")
    }

    func handleSleepWake() async throws {
        wakeStartCount += 1
        events.append("wake-start")
        if blockWake {
            await withCheckedContinuation { continuation in
                wakeContinuation = continuation
            }
        }
        if failWake {
            events.append("wake-failed")
            throw ProbeError.expectedWakeFailure
        }
        events.append("wake-end")
    }

    func releaseSuspend() {
        blockSuspend = false
        let continuation = suspendContinuation
        suspendContinuation = nil
        continuation?.resume()
    }

    func releaseStop() {
        blockStop = false
        let continuation = stopContinuation
        stopContinuation = nil
        continuation?.resume()
    }

    func releaseWake() {
        blockWake = false
        let continuation = wakeContinuation
        wakeContinuation = nil
        continuation?.resume()
    }

    func setWakeBehavior(block: Bool, fail: Bool) {
        blockWake = block
        failWake = fail
    }
}

private actor ShutdownCompletionProbe {
    private(set) var results: [TaskStoreShutdownResult] = []

    func record(_ result: TaskStoreShutdownResult) {
        results.append(result)
    }
}

private actor BootstrapGate {
    private(set) var waiterCount = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        waiterCount += 1
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func releaseAll() {
        let pending = continuations
        continuations = []
        for continuation in pending {
            continuation.resume()
        }
    }
}

private actor InvocationProbe {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

private actor LifecycleManusClient: ManusServiceClientProtocol {
    enum Step: Sendable {
        case immediate(Result<[AgentTask], ManusError>)
        case blocked
    }

    private var steps: [Step]
    private var continuations: [CheckedContinuation<[AgentTask], Error>] = []
    private(set) var fetchCount = 0

    init(steps: [Step]) {
        self.steps = steps
    }

    func listTasks() async throws -> [AgentTask] {
        fetchCount += 1
        guard !steps.isEmpty else { return [] }
        switch steps.removeFirst() {
        case .immediate(let result):
            return try result.get()
        case .blocked:
            return try await withCheckedThrowingContinuation { continuation in
                continuations.append(continuation)
            }
        }
    }

    func registerWebhook(publicURL: String) async throws -> String {
        "unused-webhook"
    }

    func webhookPublicKey() -> String { "unused-public-key" }
    func deleteWebhook(id: String) async throws {}
    func stopTask(id: String) async throws {}

    func completeNext(_ result: Result<[AgentTask], ManusError>) {
        precondition(!continuations.isEmpty, "No blocked list request")
        let continuation = continuations.removeFirst()
        switch result {
        case .success(let tasks):
            continuation.resume(returning: tasks)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private final class LifecycleKeychainProbe: @unchecked Sendable {
    enum ProbeError: Error {
        case expected
    }

    struct Snapshot: Sendable {
        let savedKeys: [String]
        let loadCount: Int
        let deleteCount: Int
    }

    private let lock = NSLock()
    private var savedKeys: [String] = []
    private var currentKey: String?
    private var loadCount = 0
    private var deleteCount = 0
    private var failsDelete = false
    private var failsSave = false
    private var clearsStoredValueOnSaveFailure = false

    func save(_ key: String) {
        lock.lock()
        savedKeys.append(key)
        currentKey = key
        lock.unlock()
    }

    func saveThrowing(_ key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if failsSave {
            if clearsStoredValueOnSaveFailure {
                currentKey = nil
            }
            throw ProbeError.expected
        }
        savedKeys.append(key)
        currentKey = key
    }

    func load() -> String? {
        lock.lock()
        defer { lock.unlock() }
        loadCount += 1
        return currentKey
    }

    func delete() throws {
        lock.lock()
        defer { lock.unlock() }
        deleteCount += 1
        if failsDelete { throw ProbeError.expected }
        currentKey = nil
    }

    func setDeleteFailure(_ value: Bool) {
        lock.lock()
        failsDelete = value
        lock.unlock()
    }

    func setSaveFailure(_ value: Bool, clearingStoredValue: Bool = false) {
        lock.lock()
        failsSave = value
        clearsStoredValueOnSaveFailure = clearingStoredValue
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            savedKeys: savedKeys,
            loadCount: loadCount,
            deleteCount: deleteCount
        )
    }
}
