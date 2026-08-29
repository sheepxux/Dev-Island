import XCTest
import Foundation
@testable import IslandCore

final class ClaudeCodeConnectorTests: XCTestCase {

    // MARK: - Event decoding (same decoder config as LocalHookServer)

    private func decode(_ json: String) throws -> ClaudeCodeEvent {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ClaudeCodeEvent.self, from: Data(json.utf8))
    }

    func testDecodeSessionStart() throws {
        let event = try decode("""
        {"session_id":"s1","transcript_path":"/tmp/t.jsonl","cwd":"/Users/dev/Proj","hook_event_name":"SessionStart"}
        """)
        XCTAssertEqual(event.hookEventName, .sessionStart)
        XCTAssertEqual(event.sessionId, "s1")
        XCTAssertEqual(event.cwd, "/Users/dev/Proj")
    }

    func testDecodeNotificationWithType() throws {
        let event = try decode("""
        {"session_id":"s1","hook_event_name":"Notification","message":"Claude needs permission to run Bash","notification_type":"permission_prompt"}
        """)
        XCTAssertEqual(event.hookEventName, .notification)
        XCTAssertEqual(event.notificationType, "permission_prompt")
        XCTAssertEqual(event.message, "Claude needs permission to run Bash")
    }

    func testDecodePermissionRequestWithToolName() throws {
        let event = try decode("""
        {"session_id":"s1","cwd":"/Users/dev/Proj","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"pwd"}}
        """)
        XCTAssertEqual(event.hookEventName, .permissionRequest)
        XCTAssertEqual(event.toolName, "Bash")
    }

    func testDecodeUnknownEventFails() {
        XCTAssertThrowsError(try decode("""
        {"session_id":"s1","hook_event_name":"PreToolUse"}
        """))
    }

    // MARK: - Lifecycle mapping

    private func event(
        _ kind: ClaudeCodeEvent.Kind,
        session: String = "s1",
        cwd: String? = "/Users/dev/Proj",
        message: String? = nil,
        type: String? = nil,
        toolName: String? = nil
    ) -> ClaudeCodeEvent {
        ClaudeCodeEvent(
            hookEventName: kind, sessionId: session, cwd: cwd,
            message: message, notificationType: type, toolName: toolName)
    }

    func testSessionLifecycle() async {
        let connector = LocalAgentConnector(descriptor: .claudeCode)

        var tasks = await connector.apply(event(.sessionStart))
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].id, "s1")
        XCTAssertEqual(tasks[0].source, "claude-code")
        XCTAssertEqual(tasks[0].status, .running)
        XCTAssertEqual(tasks[0].title, "Proj")
        XCTAssertEqual(tasks[0].taskURL, "file:///Users/dev/Proj/")

        tasks = await connector.apply(event(.permissionRequest, toolName: "Bash"))
        XCTAssertEqual(tasks[0].status, .waiting)
        XCTAssertEqual(tasks[0].waitingMessage, "Approval needed: Bash")

        tasks = await connector.apply(event(.userPromptSubmit))
        XCTAssertEqual(tasks[0].status, .running)

        tasks = await connector.apply(
            event(.notification, message: "Needs permission", type: "permission_prompt"))
        XCTAssertEqual(tasks[0].status, .waiting)
        XCTAssertEqual(tasks[0].waitingMessage, "Needs permission")

        tasks = await connector.apply(event(.userPromptSubmit))
        XCTAssertEqual(tasks[0].status, .running)
        XCTAssertNil(tasks[0].waitingMessage)

        tasks = await connector.apply(event(.stop))
        XCTAssertEqual(tasks[0].status, .completed)

        tasks = await connector.apply(event(.sessionEnd))
        XCTAssertTrue(tasks.isEmpty)
    }

    func testStopFailureMarksFailed() async {
        let connector = LocalAgentConnector(descriptor: .claudeCode)
        _ = await connector.apply(event(.sessionStart))
        let tasks = await connector.apply(event(.stopFailure))
        XCTAssertEqual(tasks[0].status, .failed)
    }

    func testIgnorableNotificationDoesNotCreateSession() async {
        let connector = LocalAgentConnector(descriptor: .claudeCode)
        let tasks = await connector.apply(event(.notification, type: "auth_success"))
        XCTAssertTrue(tasks.isEmpty)
    }

    func testNotificationWithoutTypeTreatedAsWaiting() async {
        let connector = LocalAgentConnector(descriptor: .claudeCode)
        _ = await connector.apply(event(.sessionStart))
        let tasks = await connector.apply(event(.notification, message: "Attention"))
        XCTAssertEqual(tasks[0].status, .waiting)
    }

    func testStopOnUnseenSessionCreatesCompletedTask() async {
        // Dev Island may launch mid-session — a lone Stop should still
        // surface the session instead of being dropped.
        let connector = LocalAgentConnector(descriptor: .claudeCode)
        let tasks = await connector.apply(event(.stop))
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].status, .completed)
    }

    func testMultipleSessionsSortedByCreation() async {
        let connector = LocalAgentConnector(descriptor: .claudeCode)
        let t0 = Date(timeIntervalSince1970: 1_000)
        _ = await connector.apply(event(.sessionStart, session: "a"), now: t0)
        let tasks = await connector.apply(
            event(.sessionStart, session: "b", cwd: "/Users/dev/Other"),
            now: t0.addingTimeInterval(60))
        XCTAssertEqual(tasks.map(\.id), ["a", "b"])
    }

    func testFinishedSessionsPrunedAfterTTL() async {
        let connector = LocalAgentConnector(descriptor: .claudeCode)
        let t0 = Date(timeIntervalSince1970: 1_000)
        _ = await connector.apply(event(.sessionStart, session: "old"), now: t0)
        _ = await connector.apply(event(.stop, session: "old"), now: t0)

        // Just under the TTL: still visible.
        var tasks = await connector.apply(
            event(.sessionStart, session: "new"),
            now: t0.addingTimeInterval(LocalAgentConnector.finishedTTL - 1))
        XCTAssertEqual(tasks.count, 2)

        // Past the TTL: pruned.
        tasks = await connector.apply(
            event(.userPromptSubmit, session: "new"),
            now: t0.addingTimeInterval(LocalAgentConnector.finishedTTL + 1))
        XCTAssertEqual(tasks.map(\.id), ["new"])
    }
}
