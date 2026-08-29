import XCTest
@testable import IslandAppLib
import IslandCore

final class IslandPresentationSnapshotTests: XCTestCase {
    func testSnapshotOrdersOnceAndSharesPrimaryStateAndCounts() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = IslandPresentationSnapshot(
            tasks: [
                task("running", status: .running, now: now),
                task("failed", status: .failed, now: now),
                task("waiting", status: .waiting, now: now),
                task("completed", status: .completed, now: now),
            ],
            pendingActionRequests: [],
            now: now
        )

        XCTAssertEqual(snapshot.tasks.map(\.id), [
            "waiting", "failed", "completed", "running",
        ])
        XCTAssertEqual(snapshot.primaryTask?.id, "waiting")
        XCTAssertEqual(snapshot.state, .waiting)
        XCTAssertEqual(
            snapshot.summary,
            TaskStatusSummary(running: 1, waiting: 1, failed: 1, completed: 1)
        )
    }

    func testSnapshotLetsExpiredCompletionYieldToRunning() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = IslandPresentationSnapshot(
            tasks: [
                task(
                    "completed",
                    status: .completed,
                    now: now.addingTimeInterval(
                        -TaskPresentationPolicy.recentResultDuration - 1
                    )
                ),
                task("running", status: .running, now: now),
            ],
            pendingActionRequests: [],
            now: now
        )

        XCTAssertEqual(snapshot.primaryTask?.id, "running")
        XCTAssertEqual(snapshot.state, .running)
    }

    func testEmptySnapshotIsIdle() {
        let snapshot = IslandPresentationSnapshot(
            tasks: [],
            pendingActionRequests: [],
            now: .now
        )

        XCTAssertTrue(snapshot.tasks.isEmpty)
        XCTAssertNil(snapshot.primaryTask)
        XCTAssertEqual(snapshot.state, .idle)
        XCTAssertEqual(snapshot.summary, TaskStatusSummary())
    }

    private func task(
        _ id: String,
        status: TaskStatus,
        now: Date
    ) -> AgentTask {
        AgentTask(
            id: id,
            source: "snapshot-test",
            title: id,
            status: status,
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now,
            taskURL: "https://example.invalid/\(id)"
        )
    }
}
