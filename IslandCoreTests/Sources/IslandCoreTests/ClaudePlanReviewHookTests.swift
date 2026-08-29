import Foundation
import XCTest
@testable import IslandCore

final class ClaudePlanReviewHookTests: XCTestCase {
    func testDecodesDocumentedExitPlanModePayload() throws {
        let request = try XCTUnwrap(ClaudePlanReviewHook.decodeRequest(samplePayload()))

        XCTAssertEqual(request.source, "claude-code")
        XCTAssertEqual(request.sessionId, "session-plan")
        XCTAssertEqual(request.kind, .planReview)
        XCTAssertEqual(request.title, "Review Claude Code plan")
        XCTAssertEqual(request.planReview?.markdown, "## Refactor auth\n\n1. Extract token validation.\n2. Add tests.")
    }

    func testApprovalEchoesCompleteOriginalInput() throws {
        let request = try XCTUnwrap(ClaudePlanReviewHook.decodeRequest(samplePayload()))
        let review = try XCTUnwrap(request.planReview)
        let encoded = ClaudePlanReviewHook.response(for: .planReview(.allow, review))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: Data(encoded.utf8)
        ) as? [String: Any])
        let output = try XCTUnwrap(root["hookSpecificOutput"] as? [String: Any])

        XCTAssertEqual(output["hookEventName"] as? String, "PreToolUse")
        XCTAssertEqual(output["permissionDecision"] as? String, "allow")
        let input = try XCTUnwrap(output["updatedInput"] as? [String: Any])
        XCTAssertEqual(input["plan"] as? String, review.markdown)
        XCTAssertEqual(input["planFilePath"] as? String, "/Users/dev/.claude/plans/auth.md")
        XCTAssertEqual(input["futureField"] as? String, "preserved")
    }

    func testRejectionUsesDocumentedPreToolUseDecisionShape() throws {
        let review = try XCTUnwrap(
            ClaudePlanReviewHook.decodeRequest(samplePayload())?.planReview
        )
        let encoded = ClaudePlanReviewHook.response(for: .planReview(.deny, review))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: Data(encoded.utf8)
        ) as? [String: Any])
        let output = try XCTUnwrap(root["hookSpecificOutput"] as? [String: Any])

        XCTAssertEqual(output["permissionDecision"] as? String, "deny")
        XCTAssertEqual(
            output["permissionDecisionReason"] as? String,
            "Plan rejected in Dev Island."
        )
        XCTAssertNil(output["updatedInput"])
    }

    func testInvalidOversizedAndMismatchedValuesFailNeutral() throws {
        let oversized = String(
            repeating: "x",
            count: AgentPlanReview.maximumMarkdownCharacters + 1
        )
        let invalidPayloads = [
            ##"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"ExitPlanMode","tool_input":{"plan":"# P"}}"##,
            ##"{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"plan":"# P"}}"##,
            ##"{"session_id":"","hook_event_name":"PreToolUse","tool_name":"ExitPlanMode","tool_input":{"plan":"# P"}}"##,
            #"{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"ExitPlanMode","tool_input":{"plan":""}}"#,
            ##"{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"ExitPlanMode","tool_input":{"plan":"# P","planFilePath":42}}"##,
        ]
        for json in invalidPayloads {
            XCTAssertNil(ClaudePlanReviewHook.decodeRequest(Data(json.utf8)), json)
        }
        let oversizedPayload = try JSONSerialization.data(withJSONObject: [
            "session_id": "s",
            "hook_event_name": "PreToolUse",
            "tool_name": "ExitPlanMode",
            "tool_input": ["plan": oversized],
        ])
        XCTAssertNil(ClaudePlanReviewHook.decodeRequest(oversizedPayload))

        XCTAssertEqual(ClaudePlanReviewHook.response(for: nil), "{}")
        XCTAssertEqual(ClaudePlanReviewHook.response(for: .permission(.allow)), "{}")
    }

    func testPlanReviewEnforcesUTF8BytesEvenForOneCombiningGrapheme() {
        let exactByteLimit = String(
            repeating: "😀",
            count: AgentPlanReview.maximumMarkdownCharacters
        )
        XCTAssertEqual(
            exactByteLimit.utf8.count,
            AgentPlanReview.maximumMarkdownBytes
        )
        XCTAssertNotNil(AgentPlanReview(
            markdown: exactByteLimit,
            originalInputJSON: Data("{}".utf8)
        ))

        let oversizedSingleGrapheme = "a" + String(
            repeating: "\u{0301}",
            count: AgentPlanReview.maximumMarkdownBytes / 2 + 1
        )
        XCTAssertEqual(oversizedSingleGrapheme.count, 1)
        XCTAssertGreaterThan(
            oversizedSingleGrapheme.utf8.count,
            AgentPlanReview.maximumMarkdownBytes
        )
        XCTAssertNil(AgentPlanReview(
            markdown: oversizedSingleGrapheme,
            originalInputJSON: Data("{}".utf8)
        ))
    }

    private func samplePayload() -> Data {
        Data(#"""
        {
          "session_id": "session-plan",
          "cwd": "/Users/dev/Project",
          "hook_event_name": "PreToolUse",
          "tool_name": "ExitPlanMode",
          "tool_input": {
            "plan": "## Refactor auth\n\n1. Extract token validation.\n2. Add tests.",
            "planFilePath": "/Users/dev/.claude/plans/auth.md",
            "allowedPrompts": [{"tool": "Bash", "prompt": "run tests"}],
            "futureField": "preserved"
          },
          "tool_use_id": "toolu_plan"
        }
        """#.utf8)
    }
}
