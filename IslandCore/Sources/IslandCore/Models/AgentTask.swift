import Foundation

public struct AgentTask: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let source: String          // "manus" (future: "claude-code", "cursor")
    public var title: String
    public var status: TaskStatus
    public var currentPhase: String?
    public let createdAt: Date
    public var updatedAt: Date
    public let taskURL: String
    public var waitingMessage: String?

    public init(
        id: String,
        source: String,
        title: String,
        status: TaskStatus,
        currentPhase: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        taskURL: String,
        waitingMessage: String? = nil
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.status = status
        self.currentPhase = currentPhase
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.taskURL = taskURL
        self.waitingMessage = waitingMessage
    }
}
