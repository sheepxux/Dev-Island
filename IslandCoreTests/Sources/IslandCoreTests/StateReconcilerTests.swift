import XCTest
@testable import IslandCore

final class StateReconcilerTests: XCTestCase {

    // MARK: - Helpers

    private func makeTask(id: String, source: String = "manus", title: String = "Task", status: TaskStatus = .running, updatedAt: Date = .now) -> AgentTask {
        AgentTask(
            id: id,
            source: source,
            title: title,
            status: status,
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            updatedAt: updatedAt,
            taskURL: source == "manus"
                ? "https://manus.im/app/\(id)"
                : "file:///tmp/\(source)"
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

    // MARK: - Source-scoped reconcile (Manus poll must not touch local sessions)

    func testScopedReconcilePreservesOtherSources() {
        let local = [
            makeTask(id: "m1"),
            makeTask(id: "c1", source: "claude-code"),
        ]
        // Manus snapshot no longer contains m1 — but c1 must survive.
        let result = StateReconciler.reconcile(local: local, incoming: [], source: "manus")
        XCTAssertEqual(result.map(\.id), ["c1"])
    }

    func testScopedReconcileMergesOwnSourceNormally() {
        let old = Date(timeIntervalSinceReferenceDate: 100)
        let new = Date(timeIntervalSinceReferenceDate: 200)
        let local = [
            makeTask(id: "m1", title: "Old", updatedAt: old),
            makeTask(id: "c1", source: "claude-code"),
        ]
        let incoming = [makeTask(id: "m1", title: "New", updatedAt: new)]

        let result = StateReconciler.reconcile(local: local, incoming: incoming, source: "manus")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first { $0.id == "m1" }?.title, "New")
        XCTAssertNotNil(result.first { $0.id == "c1" })
    }

    func testScopedReconcileIgnoresMalformedCrossSourceIncomingRows() {
        let localCodex = makeTask(id: "shared", source: "codex", title: "Local Codex")
        let injectedCodex = makeTask(id: "shared", source: "codex", title: "Injected")

        let result = StateReconciler.reconcile(
            local: [localCodex],
            incoming: [injectedCodex],
            source: "manus"
        )

        XCTAssertEqual(result, [localCodex])
    }

    func testReconcileUsesCompositeIdentityForSameIDAcrossAgents() {
        let old = Date(timeIntervalSinceReferenceDate: 100)
        let new = Date(timeIntervalSinceReferenceDate: 200)
        let local = [
            makeTask(id: "shared", source: "manus", title: "Old Manus", updatedAt: old),
            makeTask(id: "shared", source: "codex", title: "Old Codex", updatedAt: old),
        ]
        let incoming = [
            makeTask(id: "shared", source: "manus", title: "New Manus", updatedAt: new),
            makeTask(id: "shared", source: "codex", title: "New Codex", updatedAt: new),
        ]

        let result = StateReconciler.reconcile(local: local, incoming: incoming)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first { $0.source == "manus" }?.title, "New Manus")
        XCTAssertEqual(result.first { $0.source == "codex" }?.title, "New Codex")
    }

    func testDuplicateSnapshotRowsCoalesceWithoutCrashing() {
        let local = [
            makeTask(
                id: "duplicate",
                title: "Old local",
                updatedAt: Date(timeIntervalSinceReferenceDate: 100)
            ),
            makeTask(
                id: "duplicate",
                title: "New local",
                updatedAt: Date(timeIntervalSinceReferenceDate: 200)
            ),
        ]
        let incoming = [
            makeTask(
                id: "duplicate",
                title: "Old remote",
                updatedAt: Date(timeIntervalSinceReferenceDate: 150)
            ),
            makeTask(
                id: "duplicate",
                title: "Newest remote",
                updatedAt: Date(timeIntervalSinceReferenceDate: 300)
            ),
        ]

        let result = StateReconciler.reconcile(local: local, incoming: incoming)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Newest remote")
    }

    func testNormalizedSnapshotDropsWrongSourceAndCoalescesDuplicates() {
        let old = makeTask(
            id: "same",
            source: "codex",
            title: "Old Codex",
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        let newest = makeTask(
            id: "same",
            source: "codex",
            title: "New Codex",
            updatedAt: Date(timeIntervalSinceReferenceDate: 200)
        )
        let wrongSource = makeTask(
            id: "same",
            source: "claude-code",
            title: "Injected Claude",
            updatedAt: Date(timeIntervalSinceReferenceDate: 300)
        )

        let result = StateReconciler.normalizedSnapshot(
            [old, wrongSource, newest],
            source: "codex"
        )

        XCTAssertEqual(result, [newest])
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

    func testCreatedEventDoesNotTreatAnotherAgentSameIDAsDuplicate() {
        let local = makeTask(id: "shared", source: "codex", title: "Codex Session")
        let event = makeCreatedEvent(taskId: "shared", title: "Manus Session")

        let result = StateReconciler.apply(event: event, to: [local])

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first { $0.source == "codex" }?.title, "Codex Session")
        XCTAssertEqual(result.first { $0.source == "manus" }?.title, "Manus Session")
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
        XCTAssertEqual(result[0].waitingMessage, "Need your input")
    }

    func testStoppedReplayCannotRegressTerminalManusTask() {
        let replayedAsk = makeStoppedEvent(taskId: "t1", reason: "ask")

        for terminalStatus in [TaskStatus.completed, .failed] {
            let terminal = makeTask(id: "t1", status: terminalStatus)
            let result = StateReconciler.apply(event: replayedAsk, to: [terminal])

            XCTAssertEqual(result, [terminal])
        }
    }

    func testWaitingTaskCanStillAdvanceToCompleted() {
        let waiting = makeTask(id: "t1", status: .waiting)
        let finished = makeStoppedEvent(taskId: "t1", reason: "finish")

        let result = StateReconciler.apply(event: finished, to: [waiting])

        XCTAssertEqual(result[0].status, .completed)
        XCTAssertNil(result[0].waitingMessage)
    }

    func testStoppedEventUpdatesOnlyMatchingManusIdentity() {
        let local = makeTask(
            id: "shared",
            source: "codex",
            title: "Codex Session",
            status: .running
        )
        let manus = makeTask(
            id: "shared",
            source: "manus",
            title: "Manus Session",
            status: .running
        )
        let event = makeStoppedEvent(taskId: "shared", reason: "ask")

        let result = StateReconciler.apply(event: event, to: [local, manus])

        let unchangedLocal = result.first { $0.source == "codex" }
        let updatedManus = result.first { $0.source == "manus" }
        XCTAssertEqual(unchangedLocal?.title, "Codex Session")
        XCTAssertEqual(unchangedLocal?.status, .running)
        XCTAssertNil(unchangedLocal?.waitingMessage)
        XCTAssertEqual(updatedManus?.title, "Stopped Task")
        XCTAssertEqual(updatedManus?.status, .waiting)
        XCTAssertEqual(updatedManus?.waitingMessage, "Need your input")
    }

    func testStoppedEventRecoversManusTaskWithoutMutatingSameIDLocalTask() {
        let local = makeTask(
            id: "shared",
            source: "claude-code",
            title: "Claude Session",
            status: .running
        )
        let event = makeStoppedEvent(taskId: "shared", reason: "finish")

        let result = StateReconciler.apply(event: event, to: [local])

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first { $0.source == "claude-code" }, local)
        XCTAssertEqual(result.first { $0.source == "manus" }?.status, .completed)
    }

    func testApplyStoppedPreservesOtherTasks() {
        let t1 = makeTask(id: "t1")
        let t2 = makeTask(id: "t2")
        let event = makeStoppedEvent(taskId: "t1", reason: "finish")
        let result = StateReconciler.apply(event: event, to: [t1, t2])
        XCTAssertEqual(result.count, 2)
        let t2Result = result.first { $0.id == "t2" }
        XCTAssertEqual(t2Result?.currentPhase, t2.currentPhase)
    }

    func testStoppedEventCanRecoverTaskWhenCreatedEventWasMissed() {
        let event = makeStoppedEvent(taskId: "t_missing", reason: "finish")
        let result = StateReconciler.apply(event: event, to: [])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, "t_missing")
        XCTAssertEqual(result[0].title, "Stopped Task")
        XCTAssertEqual(result[0].status, .completed)
    }

    // MARK: - Event builders

    private func makeCreatedEvent(taskId: String, title: String) -> WebhookPayload {
        let data = TaskCreatedData(
            taskId: taskId,
            taskTitle: title,
            taskUrl: "https://manus.im/app/\(taskId)"
        )
        return WebhookPayload(
            eventID: "task_created_\(taskId)",
            event: .taskCreated,
            taskId: taskId,
            data: .created(data)
        )
    }

    private func makeStoppedEvent(taskId: String, reason: String) -> WebhookPayload {
        let stopReason = TaskStoppedData.StopReason(rawValue: reason) ?? .finish
        let data = TaskStoppedData(
            taskId: taskId,
            taskTitle: "Stopped Task",
            taskUrl: "https://manus.im/app/\(taskId)",
            message: stopReason == .ask ? "Need your input" : "Finished",
            attachments: [],
            stopReason: stopReason
        )
        return WebhookPayload(
            eventID: "task_stopped_\(taskId)",
            event: .taskStopped,
            taskId: taskId,
            data: .stopped(data)
        )
    }
}
