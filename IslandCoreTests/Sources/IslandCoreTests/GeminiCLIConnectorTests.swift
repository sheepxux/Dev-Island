import XCTest
import Foundation
@testable import IslandCore

final class GeminiCLIConnectorTests: XCTestCase {

    // MARK: - Payload decoding

    private func decode(_ json: String) throws -> GeminiCLIEvent {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GeminiCLIEvent.self, from: Data(json.utf8))
    }

    func testDecodeSessionStart() throws {
        let event = try decode("""
        {"session_id":"gem-123","transcript_path":"/tmp/gemini.jsonl","cwd":"/Users/dev/Proj","hook_event_name":"SessionStart"}
        """)

        XCTAssertEqual(event.hookEventName, .sessionStart)
        XCTAssertEqual(event.sessionId, "gem-123")
        XCTAssertEqual(event.cwd, "/Users/dev/Proj")
    }

    func testDecodeToolPermissionNotification() throws {
        let event = try decode("""
        {"session_id":"gem-123","cwd":"/Users/dev/Proj","hook_event_name":"Notification","notification_type":"ToolPermission","message":"Allow shell command?","details":{"tool_name":"run_shell_command"}}
        """)

        XCTAssertEqual(event.hookEventName, .notification)
        XCTAssertEqual(event.notificationType, "ToolPermission")
        XCTAssertEqual(event.message, "Allow shell command?")
    }

    func testDecodeUnsubscribedEventFails() {
        XCTAssertThrowsError(try decode("""
        {"session_id":"gem-123","hook_event_name":"BeforeTool","tool_name":"run_shell_command"}
        """))
    }

    // MARK: - Lifecycle mapping

    private func event(
        _ kind: GeminiCLIEvent.Kind,
        session: String = "gem-1",
        cwd: String? = "/Users/dev/Proj",
        message: String? = nil,
        notificationType: String? = nil
    ) -> GeminiCLIEvent {
        GeminiCLIEvent(
            hookEventName: kind,
            sessionId: session,
            cwd: cwd,
            message: message,
            notificationType: notificationType
        )
    }

    func testSessionLifecycle() async {
        let connector = LocalAgentConnector(descriptor: .geminiCLI)

        var tasks = await connector.apply(event(.sessionStart))
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].id, "gem-1")
        XCTAssertEqual(tasks[0].source, "gemini-cli")
        XCTAssertEqual(tasks[0].status, .running)
        XCTAssertEqual(tasks[0].title, "Proj")
        XCTAssertEqual(tasks[0].taskURL, "file:///Users/dev/Proj/")

        tasks = await connector.apply(event(
            .notification,
            message: "Allow shell command?",
            notificationType: "ToolPermission"
        ))
        XCTAssertEqual(tasks[0].status, .waiting)
        XCTAssertEqual(tasks[0].currentPhase, "Needs approval")
        XCTAssertEqual(tasks[0].waitingMessage, "Allow shell command?")

        tasks = await connector.apply(event(.beforeAgent))
        XCTAssertEqual(tasks[0].status, .running)
        XCTAssertNil(tasks[0].waitingMessage)

        tasks = await connector.apply(event(.afterAgent))
        XCTAssertEqual(tasks[0].status, .completed)

        tasks = await connector.apply(event(.sessionEnd))
        XCTAssertTrue(tasks.isEmpty)
    }

    func testToolPermissionWithoutMessageUsesFallback() async {
        let connector = LocalAgentConnector(descriptor: .geminiCLI)
        let tasks = await connector.apply(event(
            .notification,
            message: nil,
            notificationType: "ToolPermission"
        ))

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].status, .waiting)
        XCTAssertEqual(tasks[0].waitingMessage, "Approval needed")
    }

    func testNonPermissionNotificationsAreIgnored() async {
        let connector = LocalAgentConnector(descriptor: .geminiCLI)

        var tasks = await connector.apply(event(.notification, notificationType: nil))
        XCTAssertTrue(tasks.isEmpty, "a subtype-free notification must not invent a session")

        _ = await connector.apply(event(.sessionStart))
        tasks = await connector.apply(event(
            .notification,
            message: "Informational",
            notificationType: "Unknown"
        ))
        XCTAssertEqual(tasks[0].status, .running, "informational notifications must not block the task")
        XCTAssertNil(tasks[0].waitingMessage)
    }
}
