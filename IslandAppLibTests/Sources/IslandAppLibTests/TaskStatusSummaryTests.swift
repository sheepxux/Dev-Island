import XCTest
@testable import IslandAppLib
import IslandCore

final class TaskStatusSummaryTests: XCTestCase {
    func testOnlyHighestAttentionTierIsPresented() {
        let summary = TaskStatusSummary(running: 2, waiting: 1, failed: 1, completed: 4)

        XCTAssertEqual(summary.segments, [.init(status: .waiting, count: 1)])
    }

    func testCompletedLeadsRunningButNotAttentionStates() {
        XCTAssertEqual(
            TaskStatusSummary(running: 2, completed: 3).foregroundSegment,
            .init(status: .completed, count: 3)
        )
        XCTAssertEqual(
            TaskStatusSummary(running: 2, failed: 1, completed: 3).foregroundSegment,
            .init(status: .failed, count: 1)
        )
        XCTAssertEqual(
            TaskStatusSummary(completed: 3).segments,
            [.init(status: .completed, count: 3)]
        )
        XCTAssertTrue(TaskStatusSummary().segments.isEmpty)
    }

    func testAccessibilityLabelIncludesEveryState() {
        let summary = TaskStatusSummary(running: 2, waiting: 1, failed: 1, completed: 4)

        XCTAssertEqual(summary.accessibilityLabel, "1 waiting, 1 failed, 2 running, 4 completed")
    }

    func testBarStateUsesAttentionFirstPriority() {
        XCTAssertEqual(BarState.derive(from: [task("run", .running), task("done", .completed)]), .completed)
        XCTAssertEqual(BarState.derive(from: [task("done", .completed), task("fail", .failed)]), .failed)
        XCTAssertEqual(BarState.derive(from: [task("fail", .failed), task("wait", .waiting)]), .waiting)
    }

    func testPanelOrderingIsPriorityFirstAndRunningIsStable() {
        let now = Date()
        let runningOld = task("run-old", .running, createdAt: now.addingTimeInterval(-100), updatedAt: now)
        let runningNew = task("run-new", .running, createdAt: now.addingTimeInterval(-10), updatedAt: now.addingTimeInterval(10))
        let completed = task("done", .completed, createdAt: now.addingTimeInterval(-200), updatedAt: now.addingTimeInterval(-5))
        let waitingOld = task("wait-old", .waiting, createdAt: now.addingTimeInterval(-50), updatedAt: now.addingTimeInterval(-20))
        let waitingNew = task("wait-new", .waiting, createdAt: now.addingTimeInterval(-40), updatedAt: now)

        XCTAssertEqual(
            TaskPresentationPolicy.ordered([runningNew, waitingOld, completed, runningOld, waitingNew]).map(\.id),
            ["wait-new", "wait-old", "done", "run-old", "run-new"]
        )
    }

    private func task(
        _ id: String,
        _ status: TaskStatus,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) -> AgentTask {
        AgentTask(
            id: id,
            source: "codex",
            title: id,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            taskURL: "file:///tmp/\(id)"
        )
    }
}
