import XCTest
import Foundation
@testable import IslandCore

final class GeminiCLIConnectorTests: XCTestCase {

    private func decode(_ json: String) throws -> GeminiCLIEvent {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GeminiCLIEvent.self, from: Data(json.utf8))
    }

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

    func testDecodesVerifiedPayloadAndIgnoresSensitiveUnknownFields() throws {
        let event = try decode("""
        {
          "session_id":"gem-123",
          "transcript_path":"/tmp/gemini.jsonl",
          "cwd":"/Users/dev/Proj",
          "hook_event_name":"Notification",
          "notification_type":"ToolPermission",
          "message":"Allow shell command?",
          "prompt":"must not be retained",
          "details":{"tool_name":"run_shell_command"}
        }
        """)

        XCTAssertEqual(event.hookEventName, .notification)
        XCTAssertEqual(event.sessionId, "gem-123")
        XCTAssertEqual(event.cwd, "/Users/dev/Proj")
        XCTAssertEqual(event.notificationType, "ToolPermission")
        XCTAssertEqual(event.message, "Allow shell command?")
    }

    func testUnsubscribedHighFrequencyEventDoesNotDecode() {
        XCTAssertThrowsError(try decode("""
        {"session_id":"gem-123","hook_event_name":"AfterModel","llm_response":{}}
        """))
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

    func testToolPermissionWithoutMessageUsesNativeFallbackCopy() async {
        let connector = LocalAgentConnector(descriptor: .geminiCLI)
        let tasks = await connector.apply(event(
            .notification,
            notificationType: "ToolPermission"
        ))

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].status, .waiting)
        XCTAssertEqual(tasks[0].waitingMessage, "Approval needed in Gemini CLI")
    }

    func testNonPermissionNotificationsAreIgnored() async {
        let connector = LocalAgentConnector(descriptor: .geminiCLI)

        var tasks = await connector.apply(event(.notification, notificationType: nil))
        XCTAssertTrue(tasks.isEmpty, "an informational notification must not invent a task")

        _ = await connector.apply(event(.sessionStart))
        tasks = await connector.apply(event(
            .notification,
            message: "Informational",
            notificationType: "UnknownFutureType"
        ))
        XCTAssertEqual(tasks[0].status, .running)
        XCTAssertNil(tasks[0].waitingMessage)
    }

    func testEmptyAndWhitespaceSessionIdsDrop() {
        XCTAssertNil(event(.sessionStart, session: "").normalized)
        XCTAssertNil(event(.notification, session: "  \n").normalized)
    }

    func testDescriptorDecodesLifecycleAndDropsMalformedPayloads() throws {
        let descriptor = LocalAgentDescriptor.geminiCLI
        let decoded = try XCTUnwrap(descriptor.decodeEvent(Data("""
        {"session_id":"g1","cwd":"/tmp/P","hook_event_name":"BeforeAgent"}
        """.utf8)))

        XCTAssertEqual(decoded.sessionId, "g1")
        XCTAssertEqual(decoded.action, .running)
        XCTAssertNil(descriptor.decodeEvent(Data("not-json".utf8)))
        XCTAssertNil(descriptor.decodeEvent(Data("""
        {"session_id":"g1","hook_event_name":"BeforeTool"}
        """.utf8)))
    }
}
