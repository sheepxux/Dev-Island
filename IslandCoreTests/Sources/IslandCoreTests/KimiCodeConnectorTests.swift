import Foundation
import XCTest
@testable import IslandCore

final class KimiCodeConnectorTests: XCTestCase {
    private func decode(_ json: String) throws -> KimiCodeEvent {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(KimiCodeEvent.self, from: Data(json.utf8))
    }

    private func event(
        _ kind: KimiCodeEvent.Kind,
        session: String = "kimi-1",
        cwd: String? = "/Users/dev/Project",
        errorType: String? = nil
    ) -> KimiCodeEvent {
        KimiCodeEvent(
            hookEventName: kind,
            sessionId: session,
            cwd: cwd,
            errorType: errorType
        )
    }

    func testDecodesPinnedPayloadWithoutModelingSensitiveContent() throws {
        let decoded = try decode(#"""
        {
          "hook_event_name": "PermissionRequest",
          "session_id": "kimi-privacy",
          "cwd": "/Users/dev/Project",
          "tool_name": "Shell",
          "tool_input": {"command": "echo a-secret"},
          "display": "Approve a sensitive command?",
          "prompt": "private user prompt",
          "future": {"assistant_output": "private model content"}
        }
        """#)

        XCTAssertEqual(decoded.hookEventName, .permissionRequest)
        XCTAssertEqual(decoded.sessionId, "kimi-privacy")
        XCTAssertEqual(decoded.cwd, "/Users/dev/Project")
        XCTAssertNil(decoded.errorType)
        XCTAssertEqual(
            decoded.normalized?.action,
            .waiting(
                phase: "Needs approval",
                message: "Approval needed in Kimi Code CLI"
            )
        )
    }

    func testLifecycleAndObserveOnlyPermissionMapping() async {
        let connector = LocalAgentConnector(descriptor: .kimiCode)

        var tasks = await connector.apply(event(.sessionStart))
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].source, "kimi-code")
        XCTAssertEqual(tasks[0].status, .running)
        XCTAssertEqual(tasks[0].title, "Project")

        tasks = await connector.apply(event(.permissionRequest))
        XCTAssertEqual(tasks[0].status, .waiting)
        XCTAssertEqual(tasks[0].currentPhase, "Needs approval")
        XCTAssertEqual(tasks[0].waitingMessage, "Approval needed in Kimi Code CLI")

        tasks = await connector.apply(event(.permissionResult))
        XCTAssertEqual(tasks[0].status, .running)
        XCTAssertNil(tasks[0].currentPhase)
        XCTAssertNil(tasks[0].waitingMessage)

        tasks = await connector.apply(event(.turnStarted))
        XCTAssertEqual(tasks[0].status, .running)

        tasks = await connector.apply(event(.stop))
        XCTAssertEqual(tasks[0].status, .completed)
        XCTAssertNil(tasks[0].currentPhase)

        tasks = await connector.apply(event(.interrupt))
        XCTAssertEqual(tasks[0].status, .completed)
        XCTAssertEqual(tasks[0].currentPhase, "Interrupted")

        tasks = await connector.apply(event(.sessionEnd))
        XCTAssertTrue(tasks.isEmpty)
    }

    func testFailureUsesOnlyAllowlistedCategoryNotVendorText() async {
        let connector = LocalAgentConnector(descriptor: .kimiCode)

        var tasks = await connector.apply(event(
            .stopFailure,
            errorType: "AuthenticationError"
        ))
        XCTAssertEqual(tasks[0].status, .failed)
        XCTAssertEqual(tasks[0].currentPhase, "Authentication failed")

        let decoded = try? decode(#"""
        {
          "hook_event_name": "StopFailure",
          "session_id": "kimi-unknown-error",
          "cwd": "/tmp/private-project",
          "error_type": "PrivateVendorError: token sk-secret",
          "error_message": "Prompt and provider response must never persist",
          "traceback": "private stack"
        }
        """#)
        tasks = await connector.apply(decoded ?? event(.stopFailure))
        XCTAssertEqual(tasks.first { $0.id == "kimi-unknown-error" }?.status, .failed)
        XCTAssertEqual(tasks.first { $0.id == "kimi-unknown-error" }?.currentPhase, "Turn failed")
        XCTAssertFalse(tasks.contains { $0.currentPhase?.contains("secret") == true })
    }

    func testUnsupportedPayloadsAndUnusableSessionIDsDrop() {
        XCTAssertNil(event(.sessionStart, session: " \n").normalized)
        XCTAssertNil(LocalAgentDescriptor.kimiCode.decodeEvent(Data("not-json".utf8)))
        XCTAssertNil(LocalAgentDescriptor.kimiCode.decodeEvent(Data(#"""
        {"hook_event_name":"PreToolUse","session_id":"kimi-1","tool_input":{"secret":true}}
        """#.utf8)))
        XCTAssertNil(LocalAgentDescriptor.kimiCode.decodeEvent(Data(#"""
        {"hook_event_name":"UserPromptSubmit","session_id":"kimi-1"}
        """#.utf8)))
    }

    func testSameVendorSessionIDRemainsIsolatedAcrossSources() async {
        let kimi = LocalAgentConnector(descriptor: .kimiCode)
        let codex = LocalAgentConnector(descriptor: .codex)

        let kimiTasks = await kimi.apply(event(.sessionStart, session: "shared-id"))
        let codexTasks = await codex.apply(LocalAgentEvent(
            sessionId: "shared-id",
            action: .waiting(phase: "Needs approval", message: nil)
        ))

        XCTAssertEqual(kimiTasks.single?.source, "kimi-code")
        XCTAssertEqual(kimiTasks.single?.status, .running)
        XCTAssertEqual(codexTasks.single?.source, "codex")
        XCTAssertEqual(codexTasks.single?.status, .waiting)
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
