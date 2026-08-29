import Foundation
import XCTest
@testable import IslandCore

final class CodexPermissionHookTests: XCTestCase {
    func testDecodesDocumentedPermissionPayload() throws {
        let request = try XCTUnwrap(CodexPermissionHook.decodeRequest(Data(#"""
        {
          "hook_event_name": "PermissionRequest",
          "session_id": "thr_123",
          "turn_id": "turn_456",
          "cwd": "/Users/dev/Project",
          "tool_name": "Bash",
          "tool_input": {
            "command": "git status --short",
            "description": "Inspect the working tree"
          }
        }
        """#.utf8)))

        XCTAssertEqual(request.source, "codex")
        XCTAssertEqual(request.sessionId, "thr_123")
        XCTAssertEqual(request.kind, .permission)
        XCTAssertEqual(request.title, "Approve Bash")
        XCTAssertEqual(request.message, "Inspect the working tree")
        XCTAssertEqual(request.detail, "git status --short")
    }

    func testRejectsWrongEventAndEmptySession() {
        XCTAssertNil(CodexPermissionHook.decodeRequest(Data(#"""
        {"hook_event_name":"Stop","session_id":"s","tool_name":"Bash","tool_input":{}}
        """#.utf8)))
        XCTAssertNil(CodexPermissionHook.decodeRequest(Data(#"""
        {"hook_event_name":"PermissionRequest","session_id":" ","tool_name":"Bash","tool_input":{}}
        """#.utf8)))
    }

    func testDetailIsBounded() throws {
        let longCommand = String(repeating: "x", count: AgentActionRequest.maximumDetailCharacters + 200)
        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "PermissionRequest",
            "session_id": "s",
            "tool_name": "Bash",
            "tool_input": ["command": longCommand],
        ])
        let request = try XCTUnwrap(CodexPermissionHook.decodeRequest(data))
        XCTAssertEqual(request.detail?.count, AgentActionRequest.maximumDetailCharacters)
    }

    func testExactAllowResponse() {
        XCTAssertEqual(
            CodexPermissionHook.response(for: .allow),
            #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"#
        )
    }

    func testExactDenyResponse() {
        XCTAssertEqual(
            CodexPermissionHook.response(for: .deny),
            #"{"hookSpecificOutput":{"decision":{"behavior":"deny","message":"Denied in Dev Island."},"hookEventName":"PermissionRequest"}}"#
        )
    }

    func testNilDecisionPreservesNativeCodexPrompt() {
        XCTAssertEqual(CodexPermissionHook.response(for: nil), "{}")
    }
}
