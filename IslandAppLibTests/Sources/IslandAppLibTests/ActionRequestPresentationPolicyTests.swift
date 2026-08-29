import XCTest
@testable import IslandAppLib
import IslandCore

final class ActionRequestPresentationPolicyTests: XCTestCase {
    func testAttentionTargetUsesOldestQueuedRequest() {
        let requests = [request(session: "a"), request(session: "b")]
        XCTAssertEqual(
            ActionRequestPresentationPolicy.attentionTarget(in: requests),
            TaskIdentity(source: "codex", id: "a")
        )
    }

    func testOneRequestPerSessionIsVisibleAndRemainderIsCounted() throws {
        let first = request(session: "a")
        let second = request(session: "a")
        let requests = [first, request(session: "b"), second]
        let identity = TaskIdentity(source: "codex", id: "a")

        XCTAssertEqual(
            try XCTUnwrap(ActionRequestPresentationPolicy.primary(for: identity, in: requests)).id,
            first.id
        )
        XCTAssertEqual(
            ActionRequestPresentationPolicy.additionalCount(for: identity, in: requests),
            1
        )
    }

    func testOnlyOldestQueuedRequestOwnsKeyboardShortcuts() {
        let first = request(session: "a")
        let second = request(session: "b")
        let third = request(session: "a")
        let requests = [first, second, third]

        XCTAssertTrue(
            ActionRequestPresentationPolicy.isKeyboardPrimary(first, in: requests)
        )
        XCTAssertFalse(
            ActionRequestPresentationPolicy.isKeyboardPrimary(second, in: requests)
        )
        XCTAssertFalse(
            ActionRequestPresentationPolicy.isKeyboardPrimary(third, in: requests)
        )
        XCTAssertFalse(
            ActionRequestPresentationPolicy.isKeyboardPrimary(first, in: [])
        )
    }

    func testOnlyRequestsWithoutASessionRowAreOrphaned() {
        let requests = [request(session: "a"), request(session: "b")]
        let tasks = [task(session: "a")]

        XCTAssertEqual(
            ActionRequestPresentationPolicy.orphaned(requests: requests, tasks: tasks).map(\.sessionId),
            ["b"]
        )
    }

    func testSnapshotIndexesVisibleQueuesAndOrphansWithoutChangingArrivalOrder() throws {
        let firstA = request(session: "a")
        let orphan = request(session: "orphan")
        let firstC = request(session: "c")
        let secondA = request(session: "a")
        let snapshot = ActionRequestPresentationSnapshot(
            requests: [firstA, orphan, firstC, secondA],
            tasks: [task(session: "a"), task(session: "c")]
        )

        XCTAssertEqual(
            try XCTUnwrap(
                snapshot.primary(for: TaskIdentity(source: "codex", id: "a"))
            ).id,
            firstA.id
        )
        XCTAssertEqual(
            snapshot.additionalCount(
                for: TaskIdentity(source: "codex", id: "a")
            ),
            1
        )
        XCTAssertEqual(
            try XCTUnwrap(
                snapshot.primary(for: TaskIdentity(source: "codex", id: "c"))
            ).id,
            firstC.id
        )
        XCTAssertEqual(snapshot.orphanedRequests.map(\.id), [orphan.id])
        XCTAssertTrue(snapshot.isKeyboardPrimary(firstA))
        XCTAssertFalse(snapshot.isKeyboardPrimary(orphan))
    }

    func testSnapshotKeepsOldestOrphanAsTheOnlyKeyboardPrimaryRequest() {
        let orphan = request(session: "orphan")
        let visible = request(session: "visible")
        let snapshot = ActionRequestPresentationSnapshot(
            requests: [orphan, visible],
            tasks: [task(session: "visible")]
        )

        XCTAssertTrue(snapshot.isKeyboardPrimary(orphan))
        XCTAssertFalse(snapshot.isKeyboardPrimary(visible))
        XCTAssertEqual(snapshot.orphanedRequests.map(\.id), [orphan.id])
    }

    func testSessionReferenceIsStableCompactAndDoesNotExposeRawIdentifier() {
        let identifier = "permission-session-4f553cf7-bab2-45b3"
        let reference = ActionRequestPresentationPolicy.sessionReference(
            for: identifier,
            language: .english
        )

        XCTAssertEqual(
            reference,
            ActionRequestPresentationPolicy.sessionReference(for: identifier, language: .english)
        )
        XCTAssertTrue(reference.range(of: #"^Session [0-9A-F]{4}$"#, options: .regularExpression) != nil)
        XCTAssertFalse(reference.contains("permission"))
        XCTAssertNotEqual(
            reference,
            ActionRequestPresentationPolicy.sessionReference(
                for: identifier + "-other",
                language: .english
            )
        )

        let chineseReference = ActionRequestPresentationPolicy.sessionReference(
            for: identifier,
            language: .simplifiedChinese
        )
        XCTAssertTrue(
            chineseReference.range(
                of: #"^会话 [0-9A-F]{4}$"#,
                options: .regularExpression
            ) != nil
        )
        XCTAssertEqual(
            chineseReference.replacingOccurrences(of: "会话 ", with: ""),
            reference.replacingOccurrences(of: "Session ", with: "")
        )
    }

    private func request(session: String) -> AgentActionRequest {
        AgentActionRequest(
            source: "codex",
            sessionId: session,
            kind: .permission,
            title: "Approve Bash",
            message: "Run a command"
        )
    }

    private func task(session: String) -> AgentTask {
        AgentTask(
            id: session,
            source: "codex",
            title: "Project",
            status: .waiting,
            createdAt: .now,
            updatedAt: .now,
            taskURL: ""
        )
    }
}
