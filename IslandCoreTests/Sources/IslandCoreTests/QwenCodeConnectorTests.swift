import Foundation
import XCTest
@testable import IslandCore

final class QwenCodeConnectorTests: XCTestCase {

    private func decode(_ json: String) throws -> QwenCodeEvent {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(QwenCodeEvent.self, from: Data(json.utf8))
    }

    private func event(
        _ kind: QwenCodeEvent.Kind,
        session: String = "qwen-1",
        cwd: String? = "/Users/dev/Proj",
        toolName: String? = nil,
        message: String? = nil,
        notificationType: String? = nil,
        error: String? = nil
    ) -> QwenCodeEvent {
        QwenCodeEvent(
            hookEventName: kind,
            sessionId: session,
            cwd: cwd,
            toolName: toolName,
            message: message,
            notificationType: notificationType,
            error: error
        )
    }

    func testDecodesPinnedForwardExtensiblePayloadWithoutRetainingContentFields() throws {
        let decoded = try decode(#"""
        {
          "session_id":"qwen-123",
          "transcript_path":"/tmp/qwen.jsonl",
          "cwd":"/Users/dev/Proj",
          "hook_event_name":"PermissionRequest",
          "timestamp":"2026-08-26T05:00:00.000Z",
          "permission_mode":"default",
          "tool_name":"run_shell_command",
          "tool_input":{"command":"git status --short"},
          "permission_suggestions":[{"type":"tool","tool":"run_shell_command"}],
          "future_field":{"prompt":"must not be retained"}
        }
        """#)

        XCTAssertEqual(decoded.hookEventName, .permissionRequest)
        XCTAssertEqual(decoded.sessionId, "qwen-123")
        XCTAssertEqual(decoded.cwd, "/Users/dev/Proj")
        XCTAssertEqual(decoded.toolName, "run_shell_command")
    }

    func testLifecycleAndAttentionMapping() async {
        let connector = LocalAgentConnector(descriptor: .qwenCode)

        var tasks = await connector.apply(event(.sessionStart))
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].source, "qwen-code")
        XCTAssertEqual(tasks[0].status, .running)
        XCTAssertEqual(tasks[0].title, "Proj")

        tasks = await connector.apply(event(
            .permissionRequest,
            toolName: "run_shell_command"
        ))
        XCTAssertEqual(tasks[0].status, .waiting)
        XCTAssertEqual(tasks[0].currentPhase, "Needs approval")
        XCTAssertEqual(tasks[0].waitingMessage, "Approval needed: run_shell_command")

        tasks = await connector.apply(event(.userPromptSubmit))
        XCTAssertEqual(tasks[0].status, .running)
        XCTAssertNil(tasks[0].waitingMessage)

        tasks = await connector.apply(event(.stop))
        XCTAssertEqual(tasks[0].status, .completed)

        tasks = await connector.apply(event(.sessionEnd))
        XCTAssertTrue(tasks.isEmpty)
    }

    func testOnlyAttentionNotificationsMutateState() async {
        let connector = LocalAgentConnector(descriptor: .qwenCode)

        var tasks = await connector.apply(event(
            .notification,
            message: "Allow this command?",
            notificationType: "permission_prompt"
        ))
        XCTAssertEqual(tasks[0].status, .waiting)
        XCTAssertEqual(tasks[0].currentPhase, "Needs approval")

        tasks = await connector.apply(event(.userPromptSubmit))
        tasks = await connector.apply(event(
            .notification,
            message: "Signed in",
            notificationType: "auth_success"
        ))
        XCTAssertEqual(tasks[0].status, .running)
        XCTAssertNil(tasks[0].waitingMessage)

        tasks = await connector.apply(event(
            .notification,
            message: "Ready for the next prompt",
            notificationType: "idle_prompt"
        ))
        XCTAssertEqual(tasks[0].status, .waiting)
        XCTAssertEqual(tasks[0].currentPhase, "Needs input")
    }

    func testStopFailureUsesBoundedCategoryInsteadOfErrorDetails() async {
        let connector = LocalAgentConnector(descriptor: .qwenCode)
        let tasks = await connector.apply(event(.stopFailure, error: "rate_limit"))

        XCTAssertEqual(tasks[0].status, .failed)
        XCTAssertEqual(tasks[0].currentPhase, "Rate limit reached")
    }

    func testUnknownFailureCategoryDoesNotSurfaceVendorText() async {
        let connector = LocalAgentConnector(descriptor: .qwenCode)
        let tasks = await connector.apply(event(.stopFailure, error: "future_secret_error"))

        XCTAssertEqual(tasks[0].currentPhase, "Turn failed")
    }

    func testMalformedEventAndSessionIdsDrop() {
        XCTAssertNil(LocalAgentDescriptor.qwenCode.decodeEvent(Data("not-json".utf8)))
        XCTAssertNil(event(.sessionStart, session: "  \n").normalized)
        XCTAssertNil(LocalAgentDescriptor.qwenCode.decodeEvent(Data(#"""
        {"session_id":"q1","hook_event_name":"MessageDisplay","displayed_text":"secret"}
        """#.utf8)))
    }
}
