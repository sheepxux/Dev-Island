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

        XCTAssertEqual(
            summary.accessibilityLabel(language: .english),
            "1 waiting, 1 failed, 2 running, 4 completed"
        )
    }

    func testCompactLabelReportsAllSessions() {
        XCTAssertEqual(
            TaskStatusSummary(running: 2, waiting: 1, failed: 1, completed: 4)
                .compactLabel(language: .english),
            "8 sessions"
        )
        XCTAssertEqual(
            TaskStatusSummary(running: 1).compactLabel(language: .english),
            "1 session"
        )
        XCTAssertEqual(
            TaskStatusSummary().compactLabel(language: .english),
            "0 sessions"
        )
        XCTAssertEqual(
            TaskStatusSummary().accessibilityLabel(language: .english),
            "No sessions"
        )
    }

    func testBarStateUsesAttentionFirstPriority() {
        XCTAssertEqual(BarState.derive(from: [task("run", .running), task("done", .completed)]), .completed)
        XCTAssertEqual(BarState.derive(from: [task("done", .completed), task("fail", .failed)]), .failed)
        XCTAssertEqual(BarState.derive(from: [task("fail", .failed), task("wait", .waiting)]), .waiting)
    }

    func testOldCompletionYieldsBackToConcurrentRunningWork() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let oldCompletion = task(
            "done",
            .completed,
            updatedAt: now.addingTimeInterval(
                -TaskPresentationPolicy.recentResultDuration - 1
            )
        )
        let running = task(
            "run",
            .running,
            updatedAt: now.addingTimeInterval(-120)
        )

        XCTAssertEqual(
            BarState.derive(from: [oldCompletion, running], now: now),
            .running
        )
        XCTAssertEqual(
            TaskPresentationPolicy.ordered(
                [oldCompletion, running],
                now: now
            ).map(\.id),
            ["run", "done"]
        )
        XCTAssertEqual(
            BarState.derive(from: [oldCompletion], now: now),
            .completed
        )
    }

    func testPanelOrderingIsPriorityFirstAndLiveRowsAreStable() {
        let now = Date()
        let runningOld = task("run-old", .running, createdAt: now.addingTimeInterval(-100), updatedAt: now)
        let runningNew = task("run-new", .running, createdAt: now.addingTimeInterval(-10), updatedAt: now.addingTimeInterval(10))
        let completed = task("done", .completed, createdAt: now.addingTimeInterval(-200), updatedAt: now.addingTimeInterval(-5))
        let waitingOld = task("wait-old", .waiting, createdAt: now.addingTimeInterval(-50), updatedAt: now.addingTimeInterval(-20))
        let waitingNew = task("wait-new", .waiting, createdAt: now.addingTimeInterval(-40), updatedAt: now)

        XCTAssertEqual(
            TaskPresentationPolicy.ordered([runningNew, waitingOld, completed, runningOld, waitingNew]).map(\.id),
            ["wait-old", "wait-new", "done", "run-old", "run-new"]
        )
    }

    func testQueuedRequestArrivalOrdersWaitingSessionsWithoutTimestampReshuffle() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let waitingA = task(
            "waiting-a",
            .waiting,
            createdAt: now.addingTimeInterval(-120),
            updatedAt: now.addingTimeInterval(-3)
        )
        let waitingB = task(
            "waiting-b",
            .waiting,
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now.addingTimeInterval(-30)
        )
        let requests = [
            actionRequest(session: "waiting-b"),
            actionRequest(session: "waiting-a"),
        ]

        XCTAssertEqual(
            TaskPresentationPolicy.ordered(
                [waitingA, waitingB],
                pendingActionRequests: requests,
                now: now
            ).map(\.id),
            ["waiting-b", "waiting-a"]
        )

        let churnedA = task(
            "waiting-a",
            .waiting,
            createdAt: waitingA.createdAt,
            updatedAt: now.addingTimeInterval(40)
        )
        let churnedB = task(
            "waiting-b",
            .waiting,
            createdAt: waitingB.createdAt,
            updatedAt: now.addingTimeInterval(5)
        )
        XCTAssertEqual(
            TaskPresentationPolicy.ordered(
                [churnedB, churnedA],
                pendingActionRequests: requests,
                now: now.addingTimeInterval(40)
            ).map(\.id),
            ["waiting-b", "waiting-a"]
        )
    }

    func testTwentySessionOrderIsDeterministicAcrossPermutationAndLiveTimestampChurn() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let statuses: [TaskStatus] =
            Array(repeating: .waiting, count: 5)
            + Array(repeating: .failed, count: 3)
            + Array(repeating: .completed, count: 4)
            + Array(repeating: .running, count: 8)
        let baseline = statuses.enumerated().map { index, status in
            task(
                "session-\(index)",
                status,
                createdAt: now.addingTimeInterval(TimeInterval(index - 100)),
                updatedAt: now.addingTimeInterval(TimeInterval(-index))
            )
        }
        let requests = [
            actionRequest(session: "session-4"),
            actionRequest(session: "session-2"),
        ]
        let baselineOrder = TaskPresentationPolicy.ordered(
            baseline,
            pendingActionRequests: requests,
            now: now
        ).map(\.id)

        let churnedAndReversed = baseline.reversed().map { item in
            guard item.status == .waiting || item.status == .running else {
                return item
            }
            let itemIndex = Int(item.id.split(separator: "-").last ?? "") ?? 0
            return task(
                item.id,
                item.status,
                createdAt: item.createdAt,
                updatedAt: now.addingTimeInterval(
                    TimeInterval(1_000 - itemIndex)
                )
            )
        }
        let churnedOrder = TaskPresentationPolicy.ordered(
            churnedAndReversed,
            pendingActionRequests: requests,
            now: now
        ).map(\.id)

        XCTAssertEqual(baseline.count, 20)
        XCTAssertEqual(Array(baselineOrder.prefix(5)), [
            "session-4", "session-2", "session-0", "session-1", "session-3",
        ])
        XCTAssertEqual(churnedOrder, baselineOrder)
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

    private func actionRequest(session: String) -> AgentActionRequest {
        AgentActionRequest(
            source: "codex",
            sessionId: session,
            kind: .permission,
            title: "Allow command?",
            message: "A command is waiting for approval."
        )
    }
}
