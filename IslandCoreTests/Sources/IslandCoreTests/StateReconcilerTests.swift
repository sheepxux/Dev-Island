import XCTest
@testable import IslandCore

final class StateReconcilerTests: XCTestCase {

    // MARK: - Helpers

    private func makeTask(id: String, title: String = "Task", status: TaskStatus = .running, updatedAt: Date = .now) -> AgentTask {
        AgentTask(
            id: id,
            source: "manus",
            title: title,
            status: status,
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            updatedAt: updatedAt,
            taskURL: "https://manus.im/tasks/\(id)"
        )
    }

    // MARK: - reconcile tests

    func testReconcileRemoteWinsOnConflict() {
        let old = Date(timeIntervalSinceReferenceDate: 100)
        let new = Date(timeIntervalSinceReferenceDate: 200)
        let local    = [makeTask(id: "t1", title: "Old Title", updatedAt: old)]
        let incoming = [makeTask(id: "t1", title: "New Title", updatedAt: new)]

        let result = StateReconciler.reconcile(local: local, incoming: incoming)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "New Title")
    }

    func testReconcileLocalWinsWhenNewer() {
        let old = Date(timeIntervalSinceReferenceDate: 100)
        let new = Date(timeIntervalSinceReferenceDate: 200)
        let local    = [makeTask(id: "t1", title: "Local Title", updatedAt: new)]
        let incoming = [makeTask(id: "t1", title: "Remote Title", updatedAt: old)]

        let result = StateReconciler.reconcile(local: local, incoming: incoming)
        XCTAssertEqual(result[0].title, "Local Title")
    }

    func testReconcileDropsLocalOnlyTasks() {
        let local    = [makeTask(id: "t1"), makeTask(id: "t2")]
        let incoming = [makeTask(id: "t1")]

        let result = StateReconciler.reconcile(local: local, incoming: incoming)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, "t1")
    }

    func testReconcileAddsNewRemoteTasks() {
        let local    = [makeTask(id: "t1")]
        let incoming = [makeTask(id: "t1"), makeTask(id: "t2")]

        let result = StateReconciler.reconcile(local: local, incoming: incoming)
        XCTAssertEqual(result.count, 2)
    }

    func testReconcileEmptyRemoteClearsAll() {
        let local = [makeTask(id: "t1"), makeTask(id: "t2")]
        let result = StateReconciler.reconcile(local: local, incoming: [])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - apply event tests

    func testApplyCreatedAddsTask() {
        let event = makeCreatedEvent(taskId: "t_new", title: "Brand New")
        let result = StateReconciler.apply(event: event, to: [])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, "t_new")
        XCTAssertEqual(result[0].title, "Brand New")
        XCTAssertEqual(result[0].status, .running)
    }

    func testApplyCreatedIgnoresDuplicate() {
        let existing = makeTask(id: "t1")
        let event = makeCreatedEvent(taskId: "t1", title: "Duplicate")
        let result = StateReconciler.apply(event: event, to: [existing])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, existing.title)
    }

    func testApplyProgressUpdatesPhase() {
        let task = makeTask(id: "t1")
        let event = makeProgressEvent(taskId: "t1", progressType: "thinking", message: "Processing...")
        let result = StateReconciler.apply(event: event, to: [task])
        XCTAssertEqual(result[0].currentPhase, "thinking")
        XCTAssertEqual(result[0].status, .running)
    }

    func testApplyProgressWaitingUpdatesStatus() {
        let task = makeTask(id: "t1")
        let event = makeProgressEvent(taskId: "t1", progressType: "waiting", message: "Need your input")
        let result = StateReconciler.apply(event: event, to: [task])
        XCTAssertEqual(result[0].status, .waiting)
        XCTAssertEqual(result[0].waitingMessage, "Need your input")
    }

    func testApplyStoppedFinishSetsCompleted() {
        let task = makeTask(id: "t1", status: .running)
        let event = makeStoppedEvent(taskId: "t1", reason: "finish")
        let result = StateReconciler.apply(event: event, to: [task])
        XCTAssertEqual(result[0].status, .completed)
    }

    func testApplyStoppedAskSetsWaiting() {
        let task = makeTask(id: "t1", status: .running)
        let event = makeStoppedEvent(taskId: "t1", reason: "ask")
        let result = StateReconciler.apply(event: event, to: [task])
        XCTAssertEqual(result[0].status, .waiting)
    }

    func testApplyEventPreservesOtherTasks() {
        let t1 = makeTask(id: "t1")
        let t2 = makeTask(id: "t2")
        let event = makeProgressEvent(taskId: "t1", progressType: "thinking", message: "")
        let result = StateReconciler.apply(event: event, to: [t1, t2])
        XCTAssertEqual(result.count, 2)
        let t2Result = result.first { $0.id == "t2" }
        XCTAssertEqual(t2Result?.currentPhase, t2.currentPhase)
    }

    // MARK: - Event builders

    private func makeCreatedEvent(taskId: String, title: String) -> WebhookPayload {
        let data = TaskCreatedData(taskId: taskId, taskTitle: title, taskUrl: "https://manus.im/tasks/\(taskId)")
        return WebhookPayload(event: .taskCreated, taskId: taskId, data: .created(data))
    }

    private func makeProgressEvent(taskId: String, progressType: String, message: String) -> WebhookPayload {
        let data = TaskProgressData(taskId: taskId, progressType: progressType, message: message)
        return WebhookPayload(event: .taskProgress, taskId: taskId, data: .progress(data))
    }

    private func makeStoppedEvent(taskId: String, reason: String) -> WebhookPayload {
        let stopReason = TaskStoppedData.StopReason(rawValue: reason) ?? .finish
        let data = TaskStoppedData(taskId: taskId, stopReason: stopReason, message: "", attachments: [])
        return WebhookPayload(event: .taskStopped, taskId: taskId, data: .stopped(data))
    }
}
