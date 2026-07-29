import XCTest
import Foundation
@testable import IslandCore

final class CursorConnectorTests: XCTestCase {

    // MARK: - Event decoding (same decoder config as LocalHookServer)

    private func decode(_ json: String) throws -> CursorEvent {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CursorEvent.self, from: Data(json.utf8))
    }

    func testDecodeSessionStart() throws {
        // sessionStart carries session_id; base fields include conversation_id.
        let event = try decode("""
        {"conversation_id":"conv-1","session_id":"conv-1","hook_event_name":"sessionStart","is_background_agent":false,"composer_mode":"agent","cursor_version":"1.7.2","workspace_roots":["/w/Proj"]}
        """)
        XCTAssertEqual(event.hookEventName, .sessionStart)
        XCTAssertEqual(event.id, "conv-1")
        XCTAssertEqual(event.cwd, "/w/Proj")
    }

    func testDecodeStopWithStatus() throws {
        let event = try decode("""
        {"conversation_id":"conv-1","generation_id":"gen-9","hook_event_name":"stop","status":"error","loop_count":0,"workspace_roots":["/w/Proj"]}
        """)
        XCTAssertEqual(event.hookEventName, .stop)
        XCTAssertEqual(event.status, "error")
    }

    func testDecodeSessionEndFallsBackToSessionId() throws {
        // Defensive: key by session_id when conversation_id is absent.
        let event = try decode("""
        {"session_id":"conv-1","hook_event_name":"sessionEnd","reason":"user_close","duration_ms":45000}
        """)
        XCTAssertEqual(event.id, "conv-1")
    }

    func testDecodeUnsubscribedEventFails() {
        XCTAssertThrowsError(try decode("""
        {"conversation_id":"conv-1","hook_event_name":"beforeShellExecution","command":"git status"}
        """))
    }

    // MARK: - Lifecycle mapping

    private func event(
        _ kind: CursorEvent.Kind,
        id: String = "conv-1",
        generation: String? = nil,
        roots: [String]? = ["/Users/dev/Proj"],
        status: String? = nil
    ) -> CursorEvent {
        CursorEvent(
            hookEventName: kind,
            conversationId: id,
            generationId: generation,
            workspaceRoots: roots,
            status: status
        )
    }

    func testSessionLifecycle() async {
        let connector = CursorConnector()

        var tasks = await connector.apply(event(.sessionStart))
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].source, "cursor")
        XCTAssertEqual(tasks[0].status, .running)
        XCTAssertEqual(tasks[0].title, "Proj")
        XCTAssertEqual(tasks[0].taskURL, "file:///Users/dev/Proj/")

        tasks = await connector.apply(event(.beforeSubmitPrompt))
        XCTAssertEqual(tasks[0].status, .running)

        tasks = await connector.apply(event(.stop, status: "completed"))
        XCTAssertEqual(tasks[0].status, .completed)
        XCTAssertNil(tasks[0].currentPhase)

        tasks = await connector.apply(event(.sessionEnd))
        XCTAssertTrue(tasks.isEmpty)
    }

    func testStopErrorMapsToFailed() async {
        let connector = CursorConnector()
        _ = await connector.apply(event(.sessionStart))
        let tasks = await connector.apply(event(.stop, status: "error"))
        XCTAssertEqual(tasks[0].status, .failed)
        XCTAssertEqual(tasks[0].currentPhase, "Error")
    }

    func testStopAbortedMapsToCompletedWithPhase() async {
        let connector = CursorConnector()
        _ = await connector.apply(event(.sessionStart))
        let tasks = await connector.apply(event(.stop, status: "aborted"))
        XCTAssertEqual(tasks[0].status, .completed)
        XCTAssertEqual(tasks[0].currentPhase, "Aborted")
    }

    func testEventWithoutAnyIdIsIgnored() async {
        let connector = CursorConnector()
        let tasks = await connector.apply(
            CursorEvent(hookEventName: .sessionStart)
        )
        XCTAssertTrue(tasks.isEmpty)
    }

    func testMissingWorkspaceRootsFallsBackToDisplayName() async {
        let connector = CursorConnector()
        let tasks = await connector.apply(event(.sessionStart, roots: nil))
        XCTAssertEqual(tasks[0].title, "Cursor session")
    }

    // MARK: - Generation guard (async hook dispatch races)

    func testStaleStopFromSupersededGenerationIsDropped() async {
        // abort g1 → user resubmits (g2) → g1's stop arrives late.
        let connector = CursorConnector()
        _ = await connector.apply(event(.beforeSubmitPrompt, generation: "g1"))
        _ = await connector.apply(event(.beforeSubmitPrompt, generation: "g2"))
        let tasks = await connector.apply(event(.stop, generation: "g1", status: "aborted"))
        XCTAssertEqual(tasks[0].status, .running, "stale aborted stop must not override the new generation")
    }

    func testStopForCurrentGenerationApplies() async {
        let connector = CursorConnector()
        _ = await connector.apply(event(.beforeSubmitPrompt, generation: "g1"))
        let tasks = await connector.apply(event(.stop, generation: "g1", status: "completed"))
        XCTAssertEqual(tasks[0].status, .completed)
    }

    func testStopOutracingItsOwnPromptApplies() async {
        // Generation IDs aren't ordered: a stop we've never seen a prompt
        // for must apply (it may have outraced its own beforeSubmitPrompt).
        let connector = CursorConnector()
        _ = await connector.apply(event(.beforeSubmitPrompt, generation: "g1"))
        let tasks = await connector.apply(event(.stop, generation: "g2", status: "completed"))
        XCTAssertEqual(tasks[0].status, .completed)
    }

    func testStopWithoutGenerationAlwaysApplies() async {
        let connector = CursorConnector()
        _ = await connector.apply(event(.beforeSubmitPrompt, generation: "g1"))
        _ = await connector.apply(event(.beforeSubmitPrompt, generation: "g2"))
        let tasks = await connector.apply(event(.stop, status: "completed"))
        XCTAssertEqual(tasks[0].status, .completed)
    }

    func testSessionEndClearsGenerationBookkeeping() async {
        let connector = CursorConnector()
        _ = await connector.apply(event(.beforeSubmitPrompt, generation: "g1"))
        _ = await connector.apply(event(.beforeSubmitPrompt, generation: "g2"))
        _ = await connector.apply(event(.sessionEnd))
        // Same conversation id reappears: old superseded set must be gone.
        _ = await connector.apply(event(.beforeSubmitPrompt, generation: "g3"))
        let tasks = await connector.apply(event(.stop, generation: "g1", status: "completed"))
        XCTAssertEqual(tasks[0].status, .completed, "pre-sessionEnd bookkeeping must not leak")
    }

    func testLocalSourcesAreIndependent() async {
        // Same session-id string on all three connectors must not collide
        // at the TaskStore level: sources differ, snapshots are per-source.
        let codex = CodexConnector()
        let cursor = CursorConnector()
        let x1 = await codex.apply(CodexEvent(
            hookEventName: .sessionStart, sessionId: "s1", cwd: "/a"))
        let u1 = await cursor.apply(event(.sessionStart, id: "s1", roots: ["/b"]))
        XCTAssertEqual(x1[0].source, "codex")
        XCTAssertEqual(u1[0].source, "cursor")
    }
}
