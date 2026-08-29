import Foundation
import XCTest
@testable import IslandCore

final class OpenCodeConnectorTests: XCTestCase {
    private func decode(_ json: String) throws -> OpenCodeEvent {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OpenCodeEvent.self, from: Data(json.utf8))
    }

    private func event(
        _ kind: OpenCodeEvent.Kind,
        session: String = "open-1",
        cwd: String? = "/Users/dev/Project",
        status: String? = nil,
        schema: Int = OpenCodeEvent.currentSchemaVersion
    ) -> OpenCodeEvent {
        OpenCodeEvent(
            schemaVersion: schema,
            event: kind,
            sessionId: session,
            cwd: cwd,
            status: status
        )
    }

    func testPinnedPrivacyEnvelopeIgnoresVendorContentAndMetadata() async throws {
        let decoded = try decode(#"""
        {
          "schema_version": 1,
          "event": "permission.updated",
          "session_id": "open-privacy",
          "cwd": "/Users/dev/PrivateProject",
          "title": "Secret customer title",
          "prompt": "Never retain this prompt",
          "tool": {"args": {"token": "sk-private"}},
          "permission": {"metadata": {"command": "rm private-file"}},
          "error": {"message": "Private provider output"},
          "future": {"assistant_output": "Private model content"}
        }
        """#)

        XCTAssertEqual(decoded.event, .permissionUpdated)
        XCTAssertEqual(decoded.sessionId, "open-privacy")
        XCTAssertEqual(
            decoded.normalized?.action,
            .waiting(
                phase: "Needs approval",
                message: "Approval needed in OpenCode"
            )
        )

        let connector = LocalAgentConnector(descriptor: .openCode)
        let tasks = await connector.apply(decoded)
        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.title, "PrivateProject")
        XCTAssertFalse(task.currentPhase?.contains("Secret") == true)
        XCTAssertFalse(task.waitingMessage?.contains("private") == true)
    }

    func testLifecycleStatusRetryErrorPermissionAndDeleteMapping() async throws {
        let connector = LocalAgentConnector(descriptor: .openCode)

        var tasks = await connector.apply(event(.sessionCreated))
        XCTAssertEqual(tasks.single?.source, "opencode")
        XCTAssertEqual(tasks.single?.status, .running)

        tasks = await connector.apply(event(.sessionStatus, status: "busy"))
        XCTAssertEqual(tasks.single?.status, .running)

        tasks = await connector.apply(event(.sessionStatus, status: "retry"))
        XCTAssertEqual(tasks.single?.status, .running)
        XCTAssertNil(tasks.single?.currentPhase)
        XCTAssertNil(tasks.single?.waitingMessage)

        tasks = await connector.apply(event(.sessionStatus, status: "idle"))
        XCTAssertEqual(tasks.single?.status, .completed)

        tasks = await connector.apply(event(.sessionStatus, status: "busy"))
        XCTAssertEqual(tasks.single?.status, .running)

        tasks = await connector.apply(event(.permissionUpdated))
        XCTAssertEqual(tasks.single?.status, .waiting)
        XCTAssertEqual(tasks.single?.currentPhase, "Needs approval")

        tasks = await connector.apply(event(.permissionReplied))
        XCTAssertEqual(tasks.single?.status, .running)

        tasks = await connector.apply(event(.sessionError))
        XCTAssertEqual(tasks.single?.status, .failed)
        XCTAssertEqual(tasks.single?.currentPhase, "Session failed")

        tasks = await connector.apply(event(.sessionIdle))
        XCTAssertEqual(tasks.single?.status, .completed)

        tasks = await connector.apply(event(.sessionDeleted))
        XCTAssertTrue(tasks.isEmpty)
    }

    func testSchemaSessionEventAndStatusAllowlistRejectsUnsupportedPayloads() {
        XCTAssertNil(event(.sessionCreated, schema: 2).normalized)
        XCTAssertNil(event(.sessionCreated, session: " \n").normalized)
        XCTAssertNil(event(.sessionStatus).normalized)
        XCTAssertNil(event(.sessionStatus, status: "paused").normalized)
        XCTAssertNil(event(.sessionStatus, status: "private error text").normalized)

        XCTAssertNil(LocalAgentDescriptor.openCode.decodeEvent(Data("not-json".utf8)))
        XCTAssertNil(LocalAgentDescriptor.openCode.decodeEvent(Data(#"""
        {"schema_version":1,"event":"message.updated","session_id":"open-1"}
        """#.utf8)))
        XCTAssertNil(LocalAgentDescriptor.openCode.decodeEvent(Data(#"""
        {"schema_version":1,"event":"session.status","session_id":"open-1","status":"future"}
        """#.utf8)))
    }

    func testMultipleSessionsRemainIndependent() async {
        let connector = LocalAgentConnector(descriptor: .openCode)
        _ = await connector.apply(event(.sessionCreated, session: "one", cwd: "/w/One"))
        var tasks = await connector.apply(event(.sessionCreated, session: "two", cwd: "/w/Two"))
        XCTAssertEqual(Set(tasks.map(\.id)), ["one", "two"])

        tasks = await connector.apply(event(.permissionUpdated, session: "one", cwd: nil))
        XCTAssertEqual(tasks.first { $0.id == "one" }?.status, .waiting)
        XCTAssertEqual(tasks.first { $0.id == "two" }?.status, .running)

        tasks = await connector.apply(event(.sessionDeleted, session: "one", cwd: nil))
        XCTAssertEqual(tasks.map(\.id), ["two"])
        XCTAssertEqual(tasks.single?.title, "Two")
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
