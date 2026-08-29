import Foundation
import XCTest
@testable import IslandCore

final class CopilotCLIConnectorTests: XCTestCase {
    private func decode(_ json: String) throws -> CopilotCLIEvent {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CopilotCLIEvent.self, from: Data(json.utf8))
    }

    private func event(
        _ kind: CopilotCLIEvent.Kind,
        session: String = "copilot-1",
        cwd: String? = "/Users/dev/Proj",
        notificationType: String? = nil,
        recoverable: Bool? = nil,
        errorContext: String? = nil
    ) -> CopilotCLIEvent {
        CopilotCLIEvent(
            hookEventName: kind,
            sessionId: session,
            cwd: cwd,
            notificationType: notificationType,
            recoverable: recoverable,
            errorContext: errorContext
        )
    }

    func testDecodesPinnedCompatiblePayloadWithoutModelingSensitiveContent() throws {
        let decoded = try decode(#"""
        {
          "hook_event_name":"Notification",
          "session_id":"copilot-123",
          "timestamp":"2026-08-26T06:00:00.000Z",
          "cwd":"/Users/dev/Proj",
          "title":"Permission needed",
          "message":"Run a command containing a secret",
          "notification_type":"permission_prompt",
          "future":{"prompt":"must not be retained"}
        }
        """#)

        XCTAssertEqual(decoded.hookEventName, .notification)
        XCTAssertEqual(decoded.sessionId, "copilot-123")
        XCTAssertEqual(decoded.cwd, "/Users/dev/Proj")
        XCTAssertEqual(decoded.notificationType, "permission_prompt")
    }

    func testLifecycleAndAttentionMapping() async {
        let connector = LocalAgentConnector(descriptor: .copilotCLI)

        var tasks = await connector.apply(event(.sessionStart))
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].source, "copilot-cli")
        XCTAssertEqual(tasks[0].status, .running)
        XCTAssertEqual(tasks[0].title, "Proj")

        tasks = await connector.apply(event(
            .notification,
            notificationType: "permission_prompt"
        ))
        XCTAssertEqual(tasks[0].status, .waiting)
        XCTAssertEqual(tasks[0].currentPhase, "Needs approval")
        XCTAssertEqual(tasks[0].waitingMessage, "Approval needed in Copilot CLI")

        tasks = await connector.apply(event(.userPromptSubmit))
        XCTAssertEqual(tasks[0].status, .running)
        XCTAssertNil(tasks[0].waitingMessage)

        tasks = await connector.apply(event(
            .notification,
            notificationType: "elicitation_dialog"
        ))
        XCTAssertEqual(tasks[0].status, .waiting)
        XCTAssertEqual(tasks[0].currentPhase, "Needs input")
        XCTAssertEqual(tasks[0].waitingMessage, "Input needed in Copilot CLI")

        tasks = await connector.apply(event(.stop))
        XCTAssertEqual(tasks[0].status, .completed)

        tasks = await connector.apply(event(.sessionEnd))
        XCTAssertTrue(tasks.isEmpty)
    }

    func testOnlyNonRecoverableErrorsFailTheSession() async {
        let connector = LocalAgentConnector(descriptor: .copilotCLI)
        _ = await connector.apply(event(.sessionStart))

        var tasks = await connector.apply(event(
            .errorOccurred,
            recoverable: true,
            errorContext: "tool_execution"
        ))
        XCTAssertEqual(tasks[0].status, .running)

        tasks = await connector.apply(event(
            .errorOccurred,
            recoverable: false,
            errorContext: "tool_execution"
        ))
        XCTAssertEqual(tasks[0].status, .failed)
        XCTAssertEqual(tasks[0].currentPhase, "Tool execution failed")
    }

    func testInformationalNotificationsDoNotInventAttention() async {
        let connector = LocalAgentConnector(descriptor: .copilotCLI)

        var tasks = await connector.apply(event(
            .notification,
            notificationType: "shell_completed"
        ))
        XCTAssertTrue(tasks.isEmpty)

        _ = await connector.apply(event(.sessionStart))
        tasks = await connector.apply(event(
            .notification,
            notificationType: "agent_completed"
        ))
        XCTAssertEqual(tasks[0].status, .running)
        XCTAssertNil(tasks[0].waitingMessage)
    }

    func testUnsupportedAndUnusablePayloadsDrop() {
        XCTAssertNil(event(.sessionStart, session: " \n").normalized)
        XCTAssertNil(LocalAgentDescriptor.copilotCLI.decodeEvent(Data("not-json".utf8)))
        XCTAssertNil(LocalAgentDescriptor.copilotCLI.decodeEvent(Data(#"""
        {"hook_event_name":"PreToolUse","session_id":"c1","tool_name":"Bash"}
        """#.utf8)))
    }
}
