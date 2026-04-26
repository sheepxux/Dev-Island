import Foundation

public struct WebhookPayload: Sendable {
    public let event: EventType
    public let taskId: String
    public let data: EventData

    public init(event: EventType, taskId: String, data: EventData) {
        self.event = event
        self.taskId = taskId
        self.data = data
    }

    public enum EventType: String, Decodable, Sendable {
        case taskCreated   = "task_created"
        case taskProgress  = "task_progress"
        case taskStopped   = "task_stopped"
    }

    public enum EventData: Sendable {
        case created(TaskCreatedData)
        case progress(TaskProgressData)
        case stopped(TaskStoppedData)
    }
}

public struct TaskCreatedData: Decodable, Sendable {
    public let taskId: String
    public let taskTitle: String
    public let taskUrl: String
}

public struct TaskProgressData: Decodable, Sendable {
    public let taskId: String
    public let progressType: String
    public let message: String
}

public struct TaskStoppedData: Decodable, Sendable {
    public let taskId: String
    public let stopReason: StopReason
    public let message: String
    public let attachments: [String]

    public enum StopReason: String, Decodable, Sendable {
        case finish, ask
    }
}

extension WebhookPayload: Decodable {
    private enum CodingKeys: String, CodingKey {
        case event, taskId, data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let eventType = try container.decode(EventType.self, forKey: .event)
        self.event = eventType
        // taskId may be top-level or inside data — we decode from data structs
        switch eventType {
        case .taskCreated:
            let payload = try container.decode(TaskCreatedData.self, forKey: .data)
            self.taskId = payload.taskId
            self.data = .created(payload)
        case .taskProgress:
            let payload = try container.decode(TaskProgressData.self, forKey: .data)
            self.taskId = payload.taskId
            self.data = .progress(payload)
        case .taskStopped:
            let payload = try container.decode(TaskStoppedData.self, forKey: .data)
            self.taskId = payload.taskId
            self.data = .stopped(payload)
        }
    }
}
