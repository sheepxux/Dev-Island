import XCTest
@testable import IslandAppLib
import IslandCore

final class TaskNotificationPolicyTests: XCTestCase {
    func testNewlyDiscoveredWaitingTaskDoesNotNotify() {
        let transition = TaskTransition(task: task(.waiting), oldStatus: nil)

        XCTAssertNil(TaskNotificationKind.decide(
            for: transition,
            attentionRequired: true,
            completions: true
        ))
    }

    func testWaitingAndFailureAreAttentionNotifications() {
        let waiting = TaskTransition(task: task(.waiting), oldStatus: .running)
        let failed = TaskTransition(task: task(.failed), oldStatus: .running)

        XCTAssertEqual(TaskNotificationKind.decide(
            for: waiting,
            attentionRequired: true,
            completions: false
        ), .waiting)
        XCTAssertEqual(TaskNotificationKind.decide(
            for: failed,
            attentionRequired: true,
            completions: false
        ), .failed)
    }

    func testAttentionToggleSuppressesWaitingAndFailure() {
        for status: TaskStatus in [.waiting, .failed] {
            let transition = TaskTransition(task: task(status), oldStatus: .running)
            XCTAssertNil(TaskNotificationKind.decide(
                for: transition,
                attentionRequired: false,
                completions: true
            ))
        }
    }

    func testCompletionIsOptIn() {
        let transition = TaskTransition(task: task(.completed), oldStatus: .running)

        XCTAssertNil(TaskNotificationKind.decide(
            for: transition,
            attentionRequired: true,
            completions: false
        ))
        XCTAssertEqual(TaskNotificationKind.decide(
            for: transition,
            attentionRequired: true,
            completions: true
        ), .completed)
    }

    func testOnlyAttentionNotificationsInterruptTheIsland() {
        XCTAssertTrue(TaskNotificationKind.waiting.shouldExpandIsland)
        XCTAssertTrue(TaskNotificationKind.failed.shouldExpandIsland)
        XCTAssertFalse(TaskNotificationKind.completed.shouldExpandIsland)
    }

    @MainActor
    func testNotificationSelectionHighlightsTaskAndExpandsPanel() {
        let identity = TaskIdentity(source: "codex", id: "session-1")
        let coordinator = IslandCoordinator.shared
        coordinator.collapse()

        coordinator.expand(highlighting: identity)

        XCTAssertEqual(coordinator.mode, .expanded)
        XCTAssertEqual(coordinator.highlightedTask, identity)

        coordinator.collapse()
        XCTAssertNil(coordinator.highlightedTask)
    }

    @MainActor
    func testProgrammaticOpenStaysUnarmedUntilPointerEngages() {
        let coordinator = IslandCoordinator.shared
        coordinator.collapse()

        coordinator.expand()
        XCTAssertFalse(coordinator.automaticCollapseArmed)

        coordinator.armAutomaticCollapse()
        XCTAssertTrue(coordinator.automaticCollapseArmed)

        coordinator.collapse()
        XCTAssertFalse(coordinator.automaticCollapseArmed)
    }

    @MainActor
    func testDirectIslandClickArmsAutomaticCollapse() {
        let coordinator = IslandCoordinator.shared
        coordinator.collapse()

        coordinator.expandFromPointer()

        XCTAssertEqual(coordinator.mode, .expanded)
        XCTAssertTrue(coordinator.automaticCollapseArmed)

        coordinator.collapse()
    }

    private func task(_ status: TaskStatus) -> AgentTask {
        AgentTask(
            id: "session-1",
            source: "codex",
            title: "DevLand",
            status: status,
            createdAt: .now,
            updatedAt: .now,
            taskURL: "file:///tmp/DevLand"
        )
    }
}
