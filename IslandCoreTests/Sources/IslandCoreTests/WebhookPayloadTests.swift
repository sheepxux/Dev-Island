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
            "event": "task_created",
            "data": {
                "task_id": "t_abc",
                "task_title": "My New Task",
                "task_url": "https://manus.im/tasks/t_abc"
            }
        }
        """
        let payload = try decoder.decode(WebhookPayload.self, from: Data(json.utf8))
        XCTAssertEqual(payload.event, .taskCreated)
        XCTAssertEqual(payload.taskId, "t_abc")
        guard case .created(let d) = payload.data else {
            XCTFail("Expected .created payload"); return
        }
        XCTAssertEqual(d.taskTitle, "My New Task")
        XCTAssertEqual(d.taskUrl, "https://manus.im/tasks/t_abc")
    }

    func testDecodeTaskProgress() throws {
        let json = """
        {
            "event": "task_progress",
            "data": {
                "task_id": "t_abc",
                "progress_type": "thinking",
                "message": "Analyzing the request..."
            }
        }
        """
        let payload = try decoder.decode(WebhookPayload.self, from: Data(json.utf8))
        XCTAssertEqual(payload.event, .taskProgress)
        guard case .progress(let d) = payload.data else {
            XCTFail("Expected .progress payload"); return
        }
        XCTAssertEqual(d.progressType, "thinking")
        XCTAssertEqual(d.message, "Analyzing the request...")
    }

    func testDecodeTaskStoppedFinish() throws {
        let json = """
        {
            "event": "task_stopped",
            "data": {
                "task_id": "t_abc",
                "stop_reason": "finish",
                "message": "Task completed successfully",
                "attachments": ["file1.pdf", "file2.png"]
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
    }

    func testDecodeTaskStoppedAsk() throws {
        let json = """
        {
            "event": "task_stopped",
            "data": {
                "task_id": "t_xyz",
                "stop_reason": "ask",
                "message": "Please clarify your requirements",
                "attachments": []
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
            "event": "unknown_event_type",
            "data": {}
        }
        """
        XCTAssertThrowsError(try decoder.decode(WebhookPayload.self, from: Data(json.utf8)))
    }
}
