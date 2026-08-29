import Foundation
import XCTest
@testable import IslandCore

final class ClaudePermissionHookTests: XCTestCase {
    func testDecodesOfficialPermissionPayload() throws {
        let request = try XCTUnwrap(ClaudePermissionHook.decodeRequest(Data(#"""
        {
          "session_id": "abc123",
          "transcript_path": "/Users/dev/.claude/project/session.jsonl",
          "cwd": "/Users/dev/Project",
          "permission_mode": "default",
          "hook_event_name": "PermissionRequest",
          "tool_name": "Bash",
          "tool_input": {
            "command": "rm -rf node_modules",
            "description": "Remove node_modules directory"
          },
          "permission_suggestions": []
        }
        """#.utf8)))

        XCTAssertEqual(request.source, "claude-code")
        XCTAssertEqual(request.sessionId, "abc123")
        XCTAssertEqual(request.title, "Approve Bash")
        XCTAssertEqual(request.message, "Remove node_modules directory")
        XCTAssertEqual(request.detail, "rm -rf node_modules")
    }

    func testUsesSharedDocumentedDecisionShape() {
        XCTAssertEqual(
            ClaudePermissionHook.response(for: .allow),
            CodexPermissionHook.response(for: .allow)
        )
        XCTAssertEqual(
            ClaudePermissionHook.response(for: .deny),
            #"{"hookSpecificOutput":{"decision":{"behavior":"deny","message":"Denied in Dev Island."},"hookEventName":"PermissionRequest"}}"#
        )
        XCTAssertEqual(ClaudePermissionHook.response(for: nil), "{}")
    }
}
