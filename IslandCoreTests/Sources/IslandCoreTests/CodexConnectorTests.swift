import XCTest
import Foundation
@testable import IslandCore

final class CodexConnectorTests: XCTestCase {

    // MARK: - Event decoding (same decoder config as LocalHookServer)

    private func decode(_ json: String) throws -> CodexEvent {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CodexEvent.self, from: Data(json.utf8))
    }

    func testDecodeSessionStart() throws {
        let event = try decode("""
        {"session_id":"thr_123","transcript_path":"/w/.codex/rollout.jsonl","cwd":"/w/Proj","hook_event_name":"SessionStart","source":"startup","model":"gpt-5.6","permission_mode":"default"}
        """)
        XCTAssertEqual(event.hookEventName, .sessionStart)
        XCTAssertEqual(event.sessionId, "thr_123")
        XCTAssertEqual(event.cwd, "/w/Proj")
    }

    func testDecodePermissionRequestWithToolName() throws {
        let event = try decode("""
        {"session_id":"thr_123","cwd":"/w/Proj","hook_event_name":"PermissionRequest","tool_name":"Bash"}
        """)
        XCTAssertEqual(event.hookEventName, .permissionRequest)
        XCTAssertEqual(event.toolName, "Bash")
    }

    func testDecodeUnsubscribedEventFails() {
        XCTAssertThrowsError(try decode("""
        {"session_id":"thr_123","hook_event_name":"PreToolUse"}
        """))
    }

    // MARK: - Lifecycle mapping

    private func event(
        _ kind: CodexEvent.Kind,
        session: String = "thr_1",
        cwd: String? = "/Users/dev/Proj",
        toolName: String? = nil
    ) -> CodexEvent {
        CodexEvent(hookEventName: kind, sessionId: session, cwd: cwd, toolName: toolName)
    }

    func testSessionLifecycle() async {
        let connector = CodexConnector()

        var tasks = await connector.apply(event(.sessionStart))
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].source, "codex")
        XCTAssertEqual(tasks[0].status, .running)
        XCTAssertEqual(tasks[0].title, "Proj")
        XCTAssertEqual(tasks[0].taskURL, "file:///Users/dev/Proj/")

        tasks = await connector.apply(event(.permissionRequest, toolName: "Bash"))
        XCTAssertEqual(tasks[0].status, .waiting)
        XCTAssertEqual(tasks[0].waitingMessage, "Approval needed: Bash")

        tasks = await connector.apply(event(.userPromptSubmit))
        XCTAssertEqual(tasks[0].status, .running)
        XCTAssertNil(tasks[0].waitingMessage)

        tasks = await connector.apply(event(.stop))
        XCTAssertEqual(tasks[0].status, .completed)

        tasks = await connector.apply(event(.sessionEnd))
        XCTAssertTrue(tasks.isEmpty)
    }

    func testPermissionRequestWithoutToolName() async {
        let connector = CodexConnector()
        let tasks = await connector.apply(event(.permissionRequest))
        XCTAssertEqual(tasks[0].status, .waiting)
        XCTAssertEqual(tasks[0].waitingMessage, "Approval needed")
    }

    func testStopOnUnseenSessionCreatesCompletedTask() async {
        let connector = CodexConnector()
        let tasks = await connector.apply(event(.stop))
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].status, .completed)
    }

    func testClaudeAndCodexSessionsAreIndependent() async {
        // Same session-id string on both connectors must not collide at the
        // TaskStore level: sources differ, snapshots are per-source.
        let claude = ClaudeCodeConnector()
        let codex = CodexConnector()
        let c1 = await claude.apply(ClaudeCodeEvent(
            hookEventName: .sessionStart, sessionId: "s1", cwd: "/a"))
        let x1 = await codex.apply(event(.sessionStart, session: "s1", cwd: "/b"))
        XCTAssertEqual(c1[0].source, "claude-code")
        XCTAssertEqual(x1[0].source, "codex")
    }
}
