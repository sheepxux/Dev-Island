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

        try await store.configureAPIKey("new")
        try await waitUntil {
            store.tasks.contains(where: { $0.identity == newTask.identity })
        }

        await oldClient.completeNext(.success([task(id: "obsolete", source: "manus")]))
        try await Task.sleep(for: .milliseconds(40))

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

        await client.completeNext(.success([]))
        keychain.setDeleteFailure(false)
        try await store.clearAPIKey()
        XCTAssertEqual(store.apiKeyStatus, .notConfigured)
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
    }

    private(set) var events: [String] = []
    private(set) var suspendStartCount = 0
    private(set) var suspendEndCount = 0
    private(set) var wakeStartCount = 0
    private(set) var stopCount = 0
    private var blockSuspend: Bool
    private var blockWake: Bool
    private var failWake: Bool
    private var suspendContinuation: CheckedContinuation<Void, Never>?
    private var wakeContinuation: CheckedContinuation<Void, Never>?

    init(
        blockSuspend: Bool = false,
        blockWake: Bool = false,
        failWake: Bool = false
    ) {
        self.blockSuspend = blockSuspend
        self.blockWake = blockWake
        self.failWake = failWake
    }

    func start(
        onEvent: @escaping @Sendable (WebhookPayload) -> Void,
        onRealtimeUnavailable: @escaping @Sendable () async -> Void
    ) async throws {}

    func stop() async {
        stopCount += 1
        events.append("stop")
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
        let deleteCount: Int
    }

    private let lock = NSLock()
    private var savedKeys: [String] = []
    private var deleteCount = 0
    private var failsDelete = false

    func save(_ key: String) {
        lock.lock()
        savedKeys.append(key)
        lock.unlock()
    }

    func load() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return savedKeys.last
    }

    func delete() throws {
        lock.lock()
        defer { lock.unlock() }
        deleteCount += 1
        if failsDelete { throw ProbeError.expected }
    }

    func setDeleteFailure(_ value: Bool) {
        lock.lock()
        failsDelete = value
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(savedKeys: savedKeys, deleteCount: deleteCount)
    }
}
