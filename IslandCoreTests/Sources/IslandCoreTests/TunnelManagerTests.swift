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

        await manager.stop()
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

        await manager.stop()
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

        await manager.stop()
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

        await manager.stop()
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

        await manager.stop()
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

        await manager.stop()
        await client.completeRegistration(id: "late-webhook")

        do {
            try await startTask.value
            XCTFail("Expected the obsolete start to be superseded")
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
        processes: [MockTunnelProcess]
    ) -> TunnelManager {
        let sequence = TunnelProcessSequence(processes)
        return TunnelManager(
            client: client,
            server: server,
            processFactory: { sequence.next() },
            preferences: nil,
            wakeDelay: .zero,
            // Tests invoke health checks directly; keep the automatic loop inert.
            heartbeatDelay: .seconds(3_600)
        )
    }
}

private enum MockFailure: Error {
    case expected
}

private actor MockWebhookClient: ManusWebhookClientProtocol {
    struct Snapshot: Sendable {
        let registerCount: Int
        let deletedWebhookIDs: [String]
    }

    private var registrations: [Result<String, MockFailure>]
    private let publicKey: Result<String, MockFailure>
    private var registerCount = 0
    private var deletedWebhookIDs: [String] = []

    init(
        registrations: [Result<String, MockFailure>],
        publicKey: Result<String, MockFailure> = .success("test-public-key")
    ) {
        self.registrations = registrations
        self.publicKey = publicKey
    }

    func registerWebhook(publicURL: String) throws -> String {
        registerCount += 1
        guard !registrations.isEmpty else { throw MockFailure.expected }
        return try registrations.removeFirst().get()
    }

    func webhookPublicKey() throws -> String {
        try publicKey.get()
    }

    func deleteWebhook(id: String) {
        deletedWebhookIDs.append(id)
    }

    func snapshot() -> Snapshot {
        Snapshot(
            registerCount: registerCount,
            deletedWebhookIDs: deletedWebhookIDs
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
        let deletedWebhookIDs: [String]
    }

    private var registrationStarted = false
    private var registrationContinuation: CheckedContinuation<String, Error>?
    private var deletedWebhookIDs: [String] = []

    func webhookPublicKey() -> String {
        "test-public-key"
    }

    func registerWebhook(publicURL: String) async throws -> String {
        registrationStarted = true
        return try await withCheckedThrowingContinuation { continuation in
            registrationContinuation = continuation
        }
    }

    func deleteWebhook(id: String) {
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
        Snapshot(deletedWebhookIDs: deletedWebhookIDs)
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
