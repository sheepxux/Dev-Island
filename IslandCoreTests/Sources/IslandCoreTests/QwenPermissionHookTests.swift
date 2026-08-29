import Foundation
import XCTest
@testable import IslandCore

final class QwenPermissionHookTests: XCTestCase {
    func testDecodesPinnedQwenPermissionRequest() throws {
        let request = try XCTUnwrap(QwenPermissionHook.decodeRequest(Data(#"""
        {
          "session_id":"qwen-session",
          "transcript_path":"/Users/dev/.qwen/session.jsonl",
          "cwd":"/Users/dev/Project",
          "hook_event_name":"PermissionRequest",
          "timestamp":"2026-08-26T05:00:00.000Z",
          "permission_mode":"default",
          "tool_name":"run_shell_command",
          "tool_input":{
            "command":"npm test",
            "description":"Run the project tests"
          },
          "permission_suggestions":[]
        }
        """#.utf8)))

        XCTAssertEqual(request.source, "qwen-code")
        XCTAssertEqual(request.sessionId, "qwen-session")
        XCTAssertEqual(request.kind, .permission)
        XCTAssertEqual(request.title, "Approve run_shell_command")
        XCTAssertEqual(request.message, "Run the project tests")
        XCTAssertEqual(request.detail, "npm test")
    }

    func testResponseMatchesPinnedStructuredDecisionContract() {
        XCTAssertEqual(
            QwenPermissionHook.response(for: .allow),
            #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"#
        )
        XCTAssertEqual(
            QwenPermissionHook.response(for: .deny),
            #"{"hookSpecificOutput":{"decision":{"behavior":"deny","message":"Denied in Dev Island."},"hookEventName":"PermissionRequest"}}"#
        )
        XCTAssertEqual(QwenPermissionHook.response(for: nil), "{}")
    }

    func testWrongEventAndInvalidShapeFailNeutral() {
        XCTAssertNil(QwenPermissionHook.decodeRequest(Data(#"""
        {"hook_event_name":"PreToolUse","session_id":"q","tool_name":"read_file","tool_input":{}}
        """#.utf8)))
        XCTAssertNil(QwenPermissionHook.decodeRequest(Data(#"""
        {"hook_event_name":"PermissionRequest","session_id":" ","tool_name":"read_file","tool_input":{}}
        """#.utf8)))
        XCTAssertNil(QwenPermissionHook.decodeRequest(Data(#"""
        {"hook_event_name":"PermissionRequest","session_id":"q","tool_name":"read_file","tool_input":"bad"}
        """#.utf8)))
    }
}
