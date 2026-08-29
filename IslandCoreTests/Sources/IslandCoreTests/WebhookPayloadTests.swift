import XCTest
@testable import IslandCore

final class WebhookPayloadTests: XCTestCase {

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func testDecodeTaskCreated() throws {
        let json = """
        {
            "event_id": "task_created_t_abc",
            "event_type": "task_created",
            "task_detail": {
                "task_id": "t_abc",
                "task_title": "My New Task",
                "task_url": "https://manus.im/app/t_abc"
            }
        }
        """
        let payload = try decoder.decode(WebhookPayload.self, from: Data(json.utf8))
        XCTAssertEqual(payload.eventID, "task_created_t_abc")
        XCTAssertEqual(payload.event, .taskCreated)
        XCTAssertEqual(payload.taskId, "t_abc")
        guard case .created(let d) = payload.data else {
            XCTFail("Expected .created payload"); return
        }
        XCTAssertEqual(d.taskTitle, "My New Task")
        XCTAssertEqual(d.taskUrl, "https://manus.im/app/t_abc")
    }

    func testDecodeTaskStoppedFinish() throws {
        let json = """
        {
            "event_id": "task_stopped_t_abc",
            "event_type": "task_stopped",
            "task_detail": {
                "task_id": "t_abc",
                "task_title": "Completed task",
                "task_url": "https://manus.im/app/t_abc",
                "message": "Task completed successfully",
                "attachments": [
                    {
                        "file_name": "file1.pdf",
                        "url": "https://files.example/file1.pdf",
                        "size_bytes": 1024
                    },
                    {
                        "file_name": "file2.png",
                        "url": "https://files.example/file2.png",
                        "size_bytes": 2048
                    }
                ],
                "stop_reason": "finish"
            }
        }
        """
        let payload = try decoder.decode(WebhookPayload.self, from: Data(json.utf8))
        XCTAssertEqual(payload.event, .taskStopped)
        guard case .stopped(let d) = payload.data else {
            XCTFail("Expected .stopped payload"); return
        }
        XCTAssertEqual(d.stopReason, .finish)
        XCTAssertEqual(d.attachments.count, 2)
        XCTAssertEqual(d.attachments.first?.fileName, "file1.pdf")
    }

    func testDecodeTaskStoppedAsk() throws {
        let json = """
        {
            "event_id": "task_stopped_t_xyz",
            "event_type": "task_stopped",
            "task_detail": {
                "task_id": "t_xyz",
                "task_title": "Needs a choice",
                "task_url": "https://manus.im/app/t_xyz",
                "message": "Please clarify your requirements",
                "attachments": [],
                "stop_reason": "ask"
            }
        }
        """
        let payload = try decoder.decode(WebhookPayload.self, from: Data(json.utf8))
        guard case .stopped(let d) = payload.data else {
            XCTFail("Expected .stopped payload"); return
        }
        XCTAssertEqual(d.stopReason, .ask)
        XCTAssertEqual(d.message, "Please clarify your requirements")
    }

    func testDecodeUnknownEventFails() {
        let json = """
        {
            "event_id": "unknown_t_abc",
            "event_type": "unknown_event_type",
            "task_detail": {}
        }
        """
        XCTAssertThrowsError(try decoder.decode(WebhookPayload.self, from: Data(json.utf8)))
    }

    func testEmptyEventIDFailsClosed() {
        let json = """
        {
            "event_id": "",
            "event_type": "task_created",
            "task_detail": {
                "task_id": "t_abc",
                "task_title": "Task",
                "task_url": "https://manus.im/app/t_abc"
            }
        }
        """
        XCTAssertThrowsError(try decoder.decode(WebhookPayload.self, from: Data(json.utf8)))
    }

    func testUnsafeTaskDestinationFailsClosedDuringWebhookDecode() {
        for taskURL in [
            "file:///tmp/project",
            "javascript:alert(1)",
            "https://evil.example/app/t_abc",
            "https://manus.im/app/another_task",
            "https://user@manus.im/app/t_abc",
        ] {
            let json = """
            {
                "event_id": "task_created_t_abc",
                "event_type": "task_created",
                "task_detail": {
                    "task_id": "t_abc",
                    "task_title": "Task",
                    "task_url": "\(taskURL)"
                }
            }
            """
            XCTAssertThrowsError(
                try decoder.decode(WebhookPayload.self, from: Data(json.utf8)),
                taskURL
            )
        }
    }

    func testUnboundedRemoteDisplayFieldsFailClosedDuringWebhookDecode() {
        let oversizedTitle = String(repeating: "t", count: 1_025)
        let oversizedMessage = String(repeating: "m", count: 16_385)
        let oversizedEventID = String(repeating: "e", count: 513)

        let created = """
        {"event_id":"task_created_t_abc","event_type":"task_created","task_detail":{"task_id":"t_abc","task_title":"\(oversizedTitle)","task_url":"https://manus.im/app/t_abc"}}
        """
        let stopped = """
        {"event_id":"task_stopped_t_abc","event_type":"task_stopped","task_detail":{"task_id":"t_abc","task_title":"Task","task_url":"https://manus.im/app/t_abc","message":"\(oversizedMessage)","attachments":[],"stop_reason":"ask"}}
        """
        let event = """
        {"event_id":"\(oversizedEventID)","event_type":"task_created","task_detail":{"task_id":"t_abc","task_title":"Task","task_url":"https://manus.im/app/t_abc"}}
        """

        for json in [created, stopped, event] {
            XCTAssertThrowsError(
                try decoder.decode(WebhookPayload.self, from: Data(json.utf8))
            )
        }
    }

    func testLegacyGuessedEnvelopeIsRejected() {
        let json = """
        {
            "event": "task_created",
            "data": {
                "task_id": "t_abc",
                "task_title": "Task",
                "task_url": "https://manus.im/app/t_abc"
            }
        }
        """
        XCTAssertThrowsError(try decoder.decode(WebhookPayload.self, from: Data(json.utf8)))
    }
}
