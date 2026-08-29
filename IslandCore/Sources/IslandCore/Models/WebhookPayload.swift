import Foundation

/// Exact Manus v2 webhook envelope documented at
/// https://open.manus.im/docs/v2/webhooks-overview.
public struct WebhookPayload: Sendable {
    public let eventID: String
    public let event: EventType
    public let taskId: String
    public let data: EventData

    public init(eventID: String, event: EventType, taskId: String, data: EventData) {
        self.eventID = eventID
        self.event = event
        self.taskId = taskId
        self.data = data
    }

    public enum EventType: String, Decodable, Sendable {
        case taskCreated = "task_created"
        case taskStopped = "task_stopped"
    }

    public enum EventData: Sendable {
        case created(TaskCreatedData)
        case stopped(TaskStoppedData)
    }
}

public struct TaskCreatedData: Decodable, Sendable {
    public let taskId: String
    public let taskTitle: String
    public let taskUrl: String

    private enum CodingKeys: String, CodingKey {
        case taskId, taskTitle, taskUrl
    }

    public init(taskId: String, taskTitle: String, taskUrl: String) {
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.taskUrl = taskUrl
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        taskId = try container.decode(String.self, forKey: .taskId)
        taskTitle = try container.decode(String.self, forKey: .taskTitle)
        taskUrl = try container.decode(String.self, forKey: .taskUrl)
        guard ManusRemoteContentPolicy.isValidOpaqueIdentifier(taskId),
              ManusRemoteContentPolicy.isValidTitle(taskTitle),
              TaskDestinationPolicy.manusDestination(
                  rawValue: taskUrl,
                  taskID: taskId
              ) != nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .taskUrl,
                in: container,
                debugDescription: "Manus task event contains an unsafe or unbounded field"
            )
        }
    }
}

public struct TaskStoppedData: Decodable, Sendable {
    public let taskId: String
    public let taskTitle: String
    public let taskUrl: String
    public let message: String
    public let attachments: [WebhookAttachment]
    public let stopReason: StopReason

    public enum StopReason: String, Decodable, Sendable {
        case finish, ask
    }

    private enum CodingKeys: String, CodingKey {
        case taskId, taskTitle, taskUrl
        case message
        case attachments
        case stopReason
    }

    public init(
        taskId: String,
        taskTitle: String,
        taskUrl: String,
        message: String,
        attachments: [WebhookAttachment],
        stopReason: StopReason
    ) {
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.taskUrl = taskUrl
        self.message = message
        self.attachments = attachments
        self.stopReason = stopReason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        taskId = try container.decode(String.self, forKey: .taskId)
        taskTitle = try container.decode(String.self, forKey: .taskTitle)
        taskUrl = try container.decode(String.self, forKey: .taskUrl)
        message = try container.decode(String.self, forKey: .message)
        attachments = try container.decodeIfPresent(
            [WebhookAttachment].self,
            forKey: .attachments
        ) ?? []
        stopReason = try container.decode(StopReason.self, forKey: .stopReason)
        guard ManusRemoteContentPolicy.isValidOpaqueIdentifier(taskId),
              ManusRemoteContentPolicy.isValidTitle(taskTitle),
              ManusRemoteContentPolicy.isValidMessage(message),
              attachments.count <= ManusRemoteContentPolicy.maximumAttachmentCount,
              TaskDestinationPolicy.manusDestination(
                  rawValue: taskUrl,
                  taskID: taskId
              ) != nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .taskUrl,
                in: container,
                debugDescription: "Manus task event contains an unsafe or unbounded field"
            )
        }
    }
}

public struct WebhookAttachment: Decodable, Sendable {
    public let fileName: String
    public let url: String
    public let sizeBytes: Int64

    private enum CodingKeys: String, CodingKey {
        case fileName, url, sizeBytes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileName = try container.decode(String.self, forKey: .fileName)
        url = try container.decode(String.self, forKey: .url)
        sizeBytes = try container.decode(Int64.self, forKey: .sizeBytes)
        guard ManusRemoteContentPolicy.isValidAttachmentName(fileName),
              ManusRemoteContentPolicy.isValidAttachmentURL(url),
              sizeBytes >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .url,
                in: container,
                debugDescription: "Manus attachment metadata is unsafe or unbounded"
            )
        }
    }
}

extension WebhookPayload: Decodable {
    private enum CodingKeys: String, CodingKey {
        // JSONDecoder.convertFromSnakeCase transforms `event_id` to
        // `eventId`; spell the acronym accordingly at the coding boundary.
        case eventID = "eventId"
        case eventType, taskDetail
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let eventID = try container.decode(String.self, forKey: .eventID)
        guard ManusRemoteContentPolicy.isValidEventIdentifier(eventID) else {
            throw DecodingError.dataCorruptedError(
                forKey: .eventID,
                in: container,
                debugDescription: "event_id must not be empty"
            )
        }
        let eventType = try container.decode(EventType.self, forKey: .eventType)

        self.eventID = eventID
        self.event = eventType
        switch eventType {
        case .taskCreated:
            let payload = try container.decode(TaskCreatedData.self, forKey: .taskDetail)
            taskId = payload.taskId
            data = .created(payload)
        case .taskStopped:
            let payload = try container.decode(TaskStoppedData.self, forKey: .taskDetail)
            taskId = payload.taskId
            data = .stopped(payload)
        }
    }
}
