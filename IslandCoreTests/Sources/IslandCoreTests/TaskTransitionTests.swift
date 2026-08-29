import XCTest
import Foundation
@testable import IslandCore

final class TaskTransitionTests: XCTestCase {

    private func task(
        _ id: String,
        source: String = "cursor",
        status: TaskStatus,
        updatedAt: Date = .now
    ) -> AgentTask {
        AgentTask(
            id: id, source: source, title: id, status: status,
            createdAt: .now, updatedAt: updatedAt, taskURL: ""
        )
    }

    // MARK: - Pure diff

    func testStatusChangeFires() {
        let transitions = TaskTransition.diff(
            old: [task("a", status: .running)],
            new: [task("a", status: .completed)]
        )
        XCTAssertEqual(transitions.count, 1)
        XCTAssertEqual(transitions[0].oldStatus, .running)
        XCTAssertEqual(transitions[0].newStatus, .completed)
    }

    func testNewTaskFiresWithNilOldStatus() {
        let transitions = TaskTransition.diff(old: [], new: [task("a", status: .running)])
        XCTAssertEqual(transitions.count, 1)
        XCTAssertNil(transitions[0].oldStatus)
    }

    func testRemovalDoesNotFire() {
        let transitions = TaskTransition.diff(old: [task("a", status: .running)], new: [])
        XCTAssertTrue(transitions.isEmpty)
    }

    func testUnchangedDoesNotFire() {
        let transitions = TaskTransition.diff(
            old: [task("a", status: .waiting)],
            new: [task("a", status: .waiting)]
        )
        XCTAssertTrue(transitions.isEmpty)
    }

    func testSameIdDifferentSourcesAreDistinct() {
        // "s1" on codex completing must not mask "s1" on cursor appearing.
        let transitions = TaskTransition.diff(
            old: [task("s1", source: "codex", status: .running)],
            new: [
                task("s1", source: "codex", status: .completed),
                task("s1", source: "cursor", status: .running),
            ]
        )
        XCTAssertEqual(transitions.count, 2)
        let bySource = Dictionary(grouping: transitions, by: { $0.task.source })
        XCTAssertEqual(bySource["codex"]?[0].oldStatus, .running)
        XCTAssertNil(bySource["cursor"]?[0].oldStatus)
    }

    func testKeyingIsNotFooledByDelimiterCharacters() {
        // (source "a", id "b#c") must not collide with (source "a#b", id "c").
        let transitions = TaskTransition.diff(
            old: [task("b#c", source: "a", status: .running)],
            new: [task("c", source: "a#b", status: .running)]
        )
        // The new task is genuinely new (oldStatus nil), not "unchanged".
        XCTAssertEqual(transitions.count, 1)
        XCTAssertNil(transitions[0].oldStatus)
    }

    func testBatchWithMultipleChanges() {
        let transitions = TaskTransition.diff(
            old: [task("a", status: .running), task("b", status: .running)],
            new: [task("a", status: .failed), task("b", status: .waiting)]
        )
        XCTAssertEqual(transitions.count, 2)
    }

    // MARK: - TaskStore integration (contract v1.4.0 semantics)

    @MainActor
    func testStoreFiresAfterTasksUpdated() {
        let store = TaskStore.mock(tasks: [])
        var seen: [TaskTransition] = []
        var tasksAtCallback: [AgentTask] = []
        store.onTaskTransition = { transition in
            seen.append(transition)
            tasksAtCallback = store.tasks
        }

        store.debugSetTasks([task("a", status: .waiting)])

        XCTAssertEqual(seen.count, 1)
        XCTAssertNil(seen[0].oldStatus)
        XCTAssertEqual(seen[0].newStatus, .waiting)
        // Contract: callback fires after `tasks` is already updated.
        XCTAssertEqual(tasksAtCallback.count, 1)
    }

    @MainActor
    func testDebugMutatorsFire() {
        let store = TaskStore.mock(tasks: [])
        var count = 0
        store.onTaskTransition = { _ in count += 1 }

        store.debugAppend(task("a", status: .running))          // +1 (new)
        store.debugSetTasks([task("a", status: .completed)])    // +1 (running→completed)
        store.debugClearTasks()                                 // +0 (removals don't fire)
        XCTAssertEqual(count, 2)
    }

    @MainActor
    func testLocalSnapshotFiresScopedTransitions() async {
        let store = TaskStore.mock(tasks: [
            task("m", source: "manus", status: .running),
            task("c", source: "cursor", status: .running),
        ])
        var seen: [TaskTransition] = []
        store.onTaskTransition = { seen.append($0) }

        // Cursor snapshot replaces only cursor tasks; manus untouched.
        await store.applyLocalSnapshot(
            source: "cursor",
            [task("c", source: "cursor", status: .completed)]
        )

        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen[0].task.source, "cursor")
        XCTAssertEqual(seen[0].oldStatus, .running)
        XCTAssertEqual(seen[0].newStatus, .completed)
    }

    @MainActor
    func testLocalSnapshotCannotInjectAnotherSourceOrDuplicateAnIdentity() async {
        let store = TaskStore.mock(tasks: [
            task("shared", source: "manus", status: .running),
            task("shared", source: "cursor", status: .running),
        ])
        let older = Date(timeIntervalSinceReferenceDate: 100)
        let newer = Date(timeIntervalSinceReferenceDate: 200)

        await store.applyLocalSnapshot(source: "cursor", [
            task("shared", source: "cursor", status: .waiting, updatedAt: older),
            task("shared", source: "codex", status: .failed, updatedAt: newer),
            task("shared", source: "cursor", status: .completed, updatedAt: newer),
        ])

        XCTAssertEqual(store.tasks.count, 2)
        XCTAssertEqual(store.tasks.first { $0.source == "manus" }?.status, .running)
        XCTAssertEqual(store.tasks.first { $0.source == "cursor" }?.status, .completed)
        XCTAssertFalse(store.tasks.contains { $0.source == "codex" })
    }
}
