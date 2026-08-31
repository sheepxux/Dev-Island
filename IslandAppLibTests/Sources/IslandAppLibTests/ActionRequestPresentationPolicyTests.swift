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

    func testResponseReceiptUsesDecisionSpecificCopyWithoutLeakingSessionID() {
        let permission = request(session: "private-session-id")
        let allowed = ActionResponseReceiptPresentation.decision(
            for: permission,
            decision: .allow,
            language: .english
        )
        let denied = ActionResponseReceiptPresentation.decision(
            for: permission,
            decision: .deny,
            language: .simplifiedChinese
        )

        XCTAssertEqual(allowed.title, "Allowed once")
        XCTAssertEqual(allowed.detail, "Response sent to Codex")
        XCTAssertEqual(denied.title, "已拒绝请求")
        XCTAssertEqual(denied.detail, "响应已发送给 Codex")
        XCTAssertFalse(allowed.accessibilityLabel.contains("private-session-id"))
        XCTAssertFalse(denied.accessibilityLabel.contains("private-session-id"))
    }

    func testResponseReceiptDistinguishesPlanAndQuestionOutcomes() throws {
        let planReview = try XCTUnwrap(AgentPlanReview(
            markdown: "# Plan",
            originalInputJSON: Data(#"{"plan":"x"}"#.utf8)
        ))
        let plan = AgentActionRequest(
            source: "claude-code",
            sessionId: "plan",
            kind: .planReview,
            title: "Review plan",
            message: "Ready",
            planReview: planReview
        )
        let question = AgentActionRequest(
            source: "claude-code",
            sessionId: "question",
            kind: .question,
            title: "Choose",
            message: "Pick one",
            questions: [
                AgentQuestion(
                    question: "Tone?",
                    header: "Tone",
                    options: [AgentQuestionOption(label: "Quiet")]
                ),
            ]
        )

        XCTAssertEqual(
            ActionResponseReceiptPresentation.decision(
                for: plan,
                decision: .allow,
                language: .english
            ).title,
            "Plan approved"
        )
        XCTAssertEqual(
            ActionResponseReceiptPresentation.decision(
                for: plan,
                decision: .deny,
                language: .english
            ).title,
            "Plan rejected"
        )
        XCTAssertEqual(
            ActionResponseReceiptPresentation.answersSent(
                for: question,
                language: .english
            ).title,
            "Answers sent"
        )
    }

    func testQuestionSelectionUsesDistinctStableNinePointStates() {
        let unselectedSingle = QuestionSelectionPresentation.style(
            selected: false,
            allowsMultipleSelection: false
        )
        let unselectedMultiple = QuestionSelectionPresentation.style(
            selected: false,
            allowsMultipleSelection: true
        )
        let selectedSingle = QuestionSelectionPresentation.style(
            selected: true,
            allowsMultipleSelection: false
        )
        let selectedMultiple = QuestionSelectionPresentation.style(
            selected: true,
            allowsMultipleSelection: true
        )

        XCTAssertEqual(unselectedSingle.pattern, .field)
        XCTAssertEqual(unselectedMultiple.pattern, .field)
        XCTAssertEqual(unselectedSingle.tone, .quiet)
        XCTAssertEqual(unselectedMultiple.tone, .quiet)
        XCTAssertEqual(selectedSingle.pattern, .ring)
        XCTAssertEqual(selectedMultiple.pattern, .plus)
        XCTAssertEqual(selectedSingle.tone, .attention)
        XCTAssertEqual(selectedMultiple.tone, .attention)
        XCTAssertEqual(selectedSingle.intensity, 1)
        XCTAssertEqual(selectedMultiple.intensity, 1)
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
