import Foundation
import XCTest
@testable import IslandCore

final class PollingFallbackTests: XCTestCase {
    func testStopJoinsCancellationUnawareConnectorAndSuppressesLateSnapshot() async throws {
        let cancellationProbe = PollingCancellationProbe()
        let stopProbe = PollingStopProbe()
        let connector = BlockingPollingConnector(onCancellation: {
            Task { await cancellationProbe.record() }
        })
        let probe = PollingCallbackProbe()
        let poller = PollingFallback(connector: connector, interval: 3_600)

        await start(poller, probe: probe)
        try await waitUntil { await connector.fetchCount == 1 }

        let stopTask = Task {
            await poller.stop()
            await stopProbe.recordReturn()
        }
        try await waitUntil { await cancellationProbe.wasObserved }
        let returnedWhileFetchWasSuspended = await stopProbe.didReturn
        XCTAssertFalse(returnedWhileFetchWasSuspended)

        await connector.completeNext(.success([task(id: "late")]))
        await stopTask.value

        let snapshotIDs = await probe.snapshotIDs
        let didReturnAfterFetchExited = await stopProbe.didReturn
        XCTAssertTrue(snapshotIDs.isEmpty)
        XCTAssertTrue(didReturnAfterFetchExited)
    }

    func testRestartInvalidatesOlderInFlightPoll() async throws {
        let connector = BlockingPollingConnector()
        let probe = PollingCallbackProbe()
        let poller = PollingFallback(connector: connector, interval: 3_600)

        await start(poller, probe: probe)
        try await waitUntil { await connector.fetchCount == 1 }

        await start(poller, probe: probe)
        try await waitUntil { await connector.fetchCount == 2 }

        await connector.completeNext(.success([task(id: "obsolete")]))
        await connector.completeNext(.success([task(id: "current")]))
        try await waitUntil { await probe.snapshotIDs.count == 1 }

        let snapshotIDs = await probe.snapshotIDs
        XCTAssertEqual(snapshotIDs, [["current"]])
        await poller.stop()
    }

    func testStopJoinsCurrentAndSupersededCancellationUnawarePolls() async throws {
        let cancellationProbe = PollingCancellationProbe()
        let stopProbe = PollingStopProbe()
        let connector = BlockingPollingConnector(onCancellation: {
            Task { await cancellationProbe.record() }
        })
        let probe = PollingCallbackProbe()
        let poller = PollingFallback(connector: connector, interval: 3_600)

        await start(poller, probe: probe)
        try await waitUntil { await connector.fetchCount == 1 }
        await start(poller, probe: probe)
        try await waitUntil {
            let fetchCount = await connector.fetchCount
            let cancellationCount = await cancellationProbe.cancellationCount
            return fetchCount == 2 && cancellationCount == 1
        }

        let stopTask = Task {
            await poller.stop()
            await stopProbe.recordReturn()
        }
        try await waitUntil { await cancellationProbe.cancellationCount == 2 }
        let returnedBeforeEitherFetchExited = await stopProbe.didReturn
        XCTAssertFalse(returnedBeforeEitherFetchExited)

        await connector.completeNext(.success([task(id: "superseded-late")]))
        try await Task.sleep(for: .milliseconds(20))
        let returnedWithCurrentFetchSuspended = await stopProbe.didReturn
        XCTAssertFalse(returnedWithCurrentFetchSuspended)

        await connector.completeNext(.success([task(id: "current-late")]))
        await stopTask.value

        let didReturn = await stopProbe.didReturn
        let snapshotIDs = await probe.snapshotIDs
        XCTAssertTrue(didReturn)
        XCTAssertTrue(snapshotIDs.isEmpty)
    }

    func testNetworkEdgesAreCoalescedAndUnauthorizedStopsPolling() async throws {
        let connector = ScriptedPollingConnector(steps: [
            .networkUnavailable,
            .networkUnavailable,
            .success([task(id: "restored")]),
            .unauthorized,
        ])
        let probe = PollingCallbackProbe()
        let poller = PollingFallback(connector: connector, interval: 0.005)

        await start(poller, probe: probe)
        try await waitUntil { await probe.unauthorizedCount == 1 }

        let callbackSnapshot = await probe.snapshot()
        let fetchCountAtStop = await connector.fetchCount
        try await Task.sleep(for: .milliseconds(30))
        let finalFetchCount = await connector.fetchCount

        XCTAssertEqual(callbackSnapshot.networkErrorCount, 1)
        XCTAssertEqual(callbackSnapshot.networkRestoredCount, 1)
        XCTAssertEqual(callbackSnapshot.unauthorizedCount, 1)
        XCTAssertEqual(callbackSnapshot.snapshotIDs, [["restored"]])
        XCTAssertEqual(fetchCountAtStop, 4)
        XCTAssertEqual(finalFetchCount, fetchCountAtStop)

        await poller.stop()
    }

    private func start(
        _ poller: PollingFallback,
        probe: PollingCallbackProbe
    ) async {
        await poller.start(
            onSnapshot: { tasks in
                await probe.recordSnapshot(tasks)
            },
            onNetworkError: {
                await probe.recordNetworkError()
            },
            onNetworkRestored: {
                await probe.recordNetworkRestored()
            },
            onUnauthorized: {
                await probe.recordUnauthorized()
            }
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw URLError(.timedOut)
    }

    private func task(id: String) -> AgentTask {
        AgentTask(
            id: id,
            source: "manus",
            title: "Polling fixture",
            status: .running,
            createdAt: .now,
            updatedAt: .now,
            taskURL: "https://manus.im/app/fixture"
        )
    }
}

private actor PollingCallbackProbe {
    struct Snapshot: Sendable {
        let snapshotIDs: [[String]]
        let networkErrorCount: Int
        let networkRestoredCount: Int
        let unauthorizedCount: Int
    }

    private(set) var snapshotIDs: [[String]] = []
    private(set) var networkErrorCount = 0
    private(set) var networkRestoredCount = 0
    private(set) var unauthorizedCount = 0

    func recordSnapshot(_ tasks: [AgentTask]) {
        snapshotIDs.append(tasks.map(\.id))
    }

    func recordNetworkError() {
        networkErrorCount += 1
    }

    func recordNetworkRestored() {
        networkRestoredCount += 1
    }

    func recordUnauthorized() {
        unauthorizedCount += 1
    }

    func snapshot() -> Snapshot {
        Snapshot(
            snapshotIDs: snapshotIDs,
            networkErrorCount: networkErrorCount,
            networkRestoredCount: networkRestoredCount,
            unauthorizedCount: unauthorizedCount
        )
    }
}

private actor PollingCancellationProbe {
    private(set) var cancellationCount = 0

    var wasObserved: Bool { cancellationCount > 0 }

    func record() {
        cancellationCount += 1
    }
}

private actor PollingStopProbe {
    private(set) var didReturn = false

    func recordReturn() {
        didReturn = true
    }
}

private actor BlockingPollingConnector: AgentConnector {
    nonisolated let source = "manus"
    private let onCancellation: (@Sendable () -> Void)?
    private(set) var fetchCount = 0
    private var continuations: [CheckedContinuation<[AgentTask], Error>] = []

    init(onCancellation: (@Sendable () -> Void)? = nil) {
        self.onCancellation = onCancellation
    }

    func fetchTasks() async throws -> [AgentTask] {
        fetchCount += 1
        let onCancellation = self.onCancellation
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuations.append(continuation)
            }
        } onCancel: {
            onCancellation?()
        }
    }

    nonisolated func openInBrowser(taskId: String) {}
    func stop(taskId: String) async throws {}

    func completeNext(_ result: Result<[AgentTask], ManusError>) {
        precondition(!continuations.isEmpty, "No pending fetch to complete")
        let continuation = continuations.removeFirst()
        switch result {
        case .success(let tasks):
            continuation.resume(returning: tasks)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private actor ScriptedPollingConnector: AgentConnector {
    enum Step: Sendable {
        case success([AgentTask])
        case networkUnavailable
        case unauthorized
    }

    nonisolated let source = "manus"
    private var steps: [Step]
    private(set) var fetchCount = 0

    init(steps: [Step]) {
        self.steps = steps
    }

    func fetchTasks() throws -> [AgentTask] {
        fetchCount += 1
        guard !steps.isEmpty else { throw ManusError.unauthorized }
        switch steps.removeFirst() {
        case .success(let tasks):
            return tasks
        case .networkUnavailable:
            throw ManusError.networkUnavailable
        case .unauthorized:
            throw ManusError.unauthorized
        }
    }

    nonisolated func openInBrowser(taskId: String) {}
    func stop(taskId: String) async throws {}
}
