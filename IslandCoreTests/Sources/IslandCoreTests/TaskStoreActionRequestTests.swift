import Foundation
import XCTest
@testable import IslandCore

final class TaskStoreActionRequestTests: XCTestCase {
    func testActionRequestBoundsVisibleTextAndLifetime() {
        let createdAt = Date(timeIntervalSinceReferenceDate: 100)
        let request = AgentActionRequest(
            source: "codex",
            sessionId: "bounded",
            kind: .permission,
            title: String(repeating: "t", count: AgentActionRequest.maximumTitleCharacters + 1),
            message: String(repeating: "m", count: AgentActionRequest.maximumMessageCharacters + 1),
            createdAt: createdAt,
            timeout: .infinity
        )
        let longLived = AgentActionRequest(
            source: "codex",
            sessionId: "long-lived",
            kind: .permission,
            title: "Title",
            message: "Message",
            createdAt: createdAt,
            timeout: AgentActionRequest.maximumTimeout + 10_000
        )
        let pathologicalCluster = "a" + String(repeating: "\u{0301}", count: 8_192)
        let unicodeRequest = AgentActionRequest(
            source: "codex",
            sessionId: "unicode",
            kind: .permission,
            title: pathologicalCluster,
            message: pathologicalCluster,
            detail: pathologicalCluster
        )

        XCTAssertEqual(request.title.count, AgentActionRequest.maximumTitleCharacters)
        XCTAssertEqual(request.message.count, AgentActionRequest.maximumMessageCharacters)
        XCTAssertEqual(
            request.expiresAt.timeIntervalSince(request.createdAt),
            AgentActionRequest.defaultTimeout,
            accuracy: 0.001
        )
        XCTAssertEqual(
            longLived.expiresAt.timeIntervalSince(longLived.createdAt),
            AgentActionRequest.maximumTimeout,
            accuracy: 0.001
        )
        XCTAssertLessThanOrEqual(unicodeRequest.title.utf8.count, AgentActionRequest.maximumTitleBytes)
        XCTAssertLessThanOrEqual(unicodeRequest.message.utf8.count, AgentActionRequest.maximumMessageBytes)
        XCTAssertLessThanOrEqual(
            unicodeRequest.detail?.utf8.count ?? .max,
            AgentActionRequest.maximumDetailBytes
        )
    }

    @MainActor
    func testStructuredQuestionAnswerIsValidatedCanonicalizedAndResumes() async throws {
        let store = TaskStore.mock(tasks: [questionTask()])
        let request = questionRequest(timeout: 2)
        let result = Task { @MainActor in
            await store.awaitActionResponse(for: request)
        }

        try await waitUntil { store.pendingActionRequests.count == 1 }
        XCTAssertEqual(store.tasks.first?.status, .waiting)
        XCTAssertEqual(store.tasks.first?.currentPhase, "Needs input")

        XCTAssertFalse(store.respond(
            to: request.id,
            answers: [AgentQuestionAnswer(
                question: request.questions[0].question,
                selectedLabels: ["SwiftUI"]
            )]
        ))
        XCTAssertFalse(store.respond(
            to: request.id,
            answers: [
                AgentQuestionAnswer(
                    question: request.questions[0].question,
                    selectedLabels: ["Unknown"]
                ),
                AgentQuestionAnswer(
                    question: request.questions[1].question,
                    selectedLabels: ["Unit tests"]
                ),
            ]
        ))

        XCTAssertTrue(store.respond(
            to: request.id,
            answers: [
                AgentQuestionAnswer(
                    question: request.questions[1].question,
                    selectedLabels: ["Launch smoke", "Unit tests"]
                ),
                AgentQuestionAnswer(
                    question: request.questions[0].question,
                    selectedLabels: ["SwiftUI"]
                ),
            ]
        ))

        guard case .question(let submission) = await result.value else {
            return XCTFail("Expected a structured question response")
        }
        XCTAssertEqual(submission.answers.map(\.question), request.questions.map(\.question))
        XCTAssertEqual(submission.answers[1].selectedLabels, ["Unit tests", "Launch smoke"])
        XCTAssertTrue(store.pendingActionRequests.isEmpty)
        XCTAssertEqual(store.tasks.first?.status, .running)
    }

    @MainActor
    func testQuestionCanReturnImmediatelyToNativeClaudePrompt() async throws {
        let store = TaskStore.mock(tasks: [questionTask()])
        let request = questionRequest(timeout: 2)
        let result = Task { @MainActor in
            await store.awaitActionResponse(for: request)
        }

        try await waitUntil { store.pendingActionRequests.count == 1 }
        XCTAssertTrue(store.deferActionRequestToAgent(request.id))
        XCTAssertFalse(store.deferActionRequestToAgent(request.id))
        let response = await result.value
        XCTAssertNil(response)
        XCTAssertEqual(store.tasks.first?.status, .waiting)
    }

    @MainActor
    func testAllowResumesHookAndRestoresSession() async throws {
        let store = TaskStore.mock(tasks: [waitingTask()])
        let request = actionRequest(timeout: 2)
        let result = Task { @MainActor in
            await store.awaitActionDecision(for: request)
        }

        try await waitUntil { store.pendingActionRequests.count == 1 }
        XCTAssertTrue(store.respond(to: request.id, decision: .allow))
        XCTAssertFalse(store.respond(to: request.id, decision: .deny))
        let decision = await result.value
        XCTAssertEqual(decision, .allow)
        XCTAssertTrue(store.pendingActionRequests.isEmpty)
        XCTAssertEqual(store.tasks.first?.status, .running)
        XCTAssertNil(store.tasks.first?.waitingMessage)
    }

    @MainActor
    func testPlanDecisionReturnsOriginalReviewAndRestoresSession() async throws {
        let store = TaskStore.mock(tasks: [waitingTask()])
        let input = Data("{\"plan\":\"# Ship it\",\"future\":true}".utf8)
        let review = try XCTUnwrap(AgentPlanReview(
            markdown: "# Ship it",
            originalInputJSON: input
        ))
        let request = AgentActionRequest(
            source: "codex",
            sessionId: "session-1",
            kind: .planReview,
            title: "Review plan",
            message: "Ready to implement",
            planReview: review,
            timeout: 2
        )
        let result = Task { @MainActor in
            await store.awaitActionResponse(for: request)
        }

        try await waitUntil { store.pendingActionRequests.count == 1 }
        XCTAssertEqual(store.tasks.first?.currentPhase, "Review plan")
        XCTAssertTrue(store.respond(to: request.id, decision: .allow))
        guard case .planReview(let decision, let returnedReview) = await result.value else {
            return XCTFail("Expected a plan-review response")
        }
        XCTAssertEqual(decision, .allow)
        XCTAssertEqual(returnedReview, review)
        XCTAssertEqual(store.tasks.first?.status, .running)
    }

    @MainActor
    func testTimeoutReturnsNoDecisionAndLeavesNativeWaitingState() async throws {
        let store = TaskStore.mock(tasks: [waitingTask()])
        let request = actionRequest(timeout: 0.05)
        let result = Task { @MainActor in
            await store.awaitActionDecision(for: request)
        }

        try await waitUntil { store.pendingActionRequests.count == 1 }
        let decision = await result.value
        XCTAssertNil(decision)
        XCTAssertTrue(store.pendingActionRequests.isEmpty)
        XCTAssertFalse(store.respond(to: request.id, decision: .allow))
        XCTAssertEqual(store.tasks.first?.status, .waiting)
    }

    @MainActor
    func testSessionCleanupResumesEveryMatchingRequestOnly() async throws {
        let store = TaskStore.mock(tasks: [waitingTask()])
        let first = actionRequest(timeout: 2)
        let second = AgentActionRequest(
            source: "codex",
            sessionId: "other-session",
            kind: .permission,
            title: "Approve Write",
            message: "Write a file",
            timeout: 2
        )
        let firstResult = Task { @MainActor in
            await store.awaitActionDecision(for: first)
        }
        let secondResult = Task { @MainActor in
            await store.awaitActionDecision(for: second)
        }

        try await waitUntil { store.pendingActionRequests.count == 2 }
        store.cancelActionRequests(for: first.taskIdentity)
        let firstDecision = await firstResult.value
        XCTAssertNil(firstDecision)
        XCTAssertEqual(store.pendingActionRequests.map(\.id), [second.id])

        XCTAssertTrue(store.respond(to: second.id, decision: .deny))
        let secondDecision = await secondResult.value
        XCTAssertEqual(secondDecision, .deny)
    }

    @MainActor
    func testSessionStaysWaitingUntilItsLastQueuedRequestIsResolved() async throws {
        let store = TaskStore.mock(tasks: [waitingTask()])
        let first = actionRequest(timeout: 2)
        let second = actionRequest(timeout: 2)
        let firstResult = Task { @MainActor in
            await store.awaitActionDecision(for: first)
        }
        let secondResult = Task { @MainActor in
            await store.awaitActionDecision(for: second)
        }

        try await waitUntil { store.pendingActionRequests.count == 2 }
        XCTAssertTrue(store.respond(to: first.id, decision: .allow))
        let firstDecision = await firstResult.value
        XCTAssertEqual(firstDecision, .allow)
        XCTAssertEqual(store.tasks.first?.status, .waiting)

        XCTAssertTrue(store.respond(to: second.id, decision: .deny))
        let secondDecision = await secondResult.value
        XCTAssertEqual(secondDecision, .deny)
        XCTAssertEqual(store.tasks.first?.status, .running)
    }

    @MainActor
    func testCancelledHookCannotLeakAContinuation() async throws {
        let store = TaskStore.mock(tasks: [waitingTask()])
        let request = actionRequest(timeout: 2)
        let result = Task { @MainActor in
            await store.awaitActionDecision(for: request)
        }

        try await waitUntil { store.pendingActionRequests.count == 1 }
        result.cancel()
        let decision = await result.value
        XCTAssertNil(decision)
        XCTAssertTrue(store.pendingActionRequests.isEmpty)
    }

    @MainActor
    func testGlobalQueueOverflowFailsNeutralWithoutRetainingContinuation() async throws {
        let store = TaskStore.mock(tasks: [])
        var results: [Task<AgentActionResponse?, Never>] = []
        for index in 0..<TaskStore.maximumPendingActionRequests {
            let request = actionRequest(sessionID: "session-\(index)", timeout: 10)
            results.append(Task { @MainActor in
                await store.awaitActionResponse(for: request)
            })
        }
        try await waitUntil {
            store.pendingActionRequests.count == TaskStore.maximumPendingActionRequests
        }

        let overflow = await store.awaitActionResponse(
            for: actionRequest(sessionID: "overflow", timeout: 10)
        )

        XCTAssertNil(overflow)
        XCTAssertEqual(
            store.pendingActionRequests.count,
            TaskStore.maximumPendingActionRequests
        )

        store.shutdown()
        for result in results {
            let value = await result.value
            XCTAssertNil(value)
        }
        XCTAssertTrue(store.pendingActionRequests.isEmpty)
    }

    @MainActor
    func testPerSessionQueueOverflowRecoversCapacityAfterResolution() async throws {
        let store = TaskStore.mock(tasks: [waitingTask()])
        var requests: [AgentActionRequest] = []
        var results: [Task<AgentActionResponse?, Never>] = []
        for _ in 0..<TaskStore.maximumPendingActionRequestsPerSession {
            let request = actionRequest(sessionID: "session-1", timeout: 10)
            requests.append(request)
            results.append(Task { @MainActor in
                await store.awaitActionResponse(for: request)
            })
        }
        try await waitUntil {
            store.pendingActionRequests.count == TaskStore.maximumPendingActionRequestsPerSession
        }

        let overflow = await store.awaitActionResponse(
            for: actionRequest(sessionID: "session-1", timeout: 10)
        )
        XCTAssertNil(overflow)

        XCTAssertTrue(store.respond(to: requests[0].id, decision: .deny))
        guard case .permission(.deny) = await results[0].value else {
            return XCTFail("Expected the resolved request to return deny")
        }

        let replacement = actionRequest(sessionID: "session-1", timeout: 10)
        let replacementResult = Task { @MainActor in
            await store.awaitActionResponse(for: replacement)
        }
        try await waitUntil {
            store.pendingActionRequests.contains { $0.id == replacement.id }
        }
        XCTAssertEqual(
            store.pendingActionRequests.count,
            TaskStore.maximumPendingActionRequestsPerSession
        )

        store.shutdown()
        for result in results.dropFirst() {
            let value = await result.value
            XCTAssertNil(value)
        }
        let replacementValue = await replacementResult.value
        XCTAssertNil(replacementValue)
        XCTAssertTrue(store.pendingActionRequests.isEmpty)
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 1,
        _ predicate: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for TaskStore state")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func actionRequest(timeout: TimeInterval) -> AgentActionRequest {
        actionRequest(sessionID: "session-1", timeout: timeout)
    }

    private func actionRequest(
        sessionID: String,
        timeout: TimeInterval
    ) -> AgentActionRequest {
        AgentActionRequest(
            source: "codex",
            sessionId: sessionID,
            kind: .permission,
            title: "Approve Bash",
            message: "Run a command",
            timeout: timeout
        )
    }

    private func questionRequest(timeout: TimeInterval) -> AgentActionRequest {
        AgentActionRequest(
            source: "claude-code",
            sessionId: "question-session",
            kind: .question,
            title: "Claude Code needs input",
            message: "Answer two questions",
            questions: [
                AgentQuestion(
                    question: "Which framework?",
                    header: "Framework",
                    options: [
                        AgentQuestionOption(label: "SwiftUI"),
                        AgentQuestionOption(label: "AppKit"),
                    ]
                ),
                AgentQuestion(
                    question: "Which checks?",
                    header: "Checks",
                    options: [
                        AgentQuestionOption(label: "Unit tests"),
                        AgentQuestionOption(label: "Launch smoke"),
                    ],
                    allowsMultipleSelection: true
                ),
            ],
            timeout: timeout
        )
    }

    private func questionTask() -> AgentTask {
        AgentTask(
            id: "question-session",
            source: "claude-code",
            title: "DevLand",
            status: .running,
            currentPhase: "Thinking",
            createdAt: .now,
            updatedAt: .now,
            taskURL: "file:///tmp/DevLand"
        )
    }

    private func waitingTask() -> AgentTask {
        AgentTask(
            id: "session-1",
            source: "codex",
            title: "DevLand",
            status: .waiting,
            currentPhase: "Needs approval",
            createdAt: .now,
            updatedAt: .now,
            taskURL: "file:///tmp/DevLand",
            waitingMessage: "Approval needed: Bash"
        )
    }
}
