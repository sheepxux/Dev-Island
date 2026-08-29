import Foundation

/// Globally unique identity for one task inside Dev Island.
///
/// Agent session IDs are only guaranteed to be unique within their source,
/// so every UI lookup, notification payload, and jump-back action must carry
/// both values. Keeping this as a typed value prevents a future caller from
/// accidentally falling back to an ambiguous bare session ID.
public struct TaskIdentity: Hashable, Codable, Sendable {
    public let source: String
    public let id: String

    public init(source: String, id: String) {
        self.source = source
        self.id = id
    }
}

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
    /// In-memory terminal/tmux return target captured by managed local Hooks.
    /// The SQLite layer deliberately omits it, so it disappears with the live
    /// session and never becomes historical terminal metadata.
    public var jumpContext: SessionJumpContext?

    public init(
        id: String,
        source: String,
        title: String,
        status: TaskStatus,
        currentPhase: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        taskURL: String,
        waitingMessage: String? = nil,
        jumpContext: SessionJumpContext? = nil
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
        self.jumpContext = jumpContext
    }

    /// Stable cross-agent identity used by lists, notification routing, and
    /// jump-back. `id` remains available for connector-facing APIs.
    public var identity: TaskIdentity {
        TaskIdentity(source: source, id: id)
    }
}

// TaskStatus, ConnectionStatus, APIKeyStatus 定义在各自的独立文件中：
// Models/TaskStatus.swift、Models/ConnectionStatus.swift、Models/APIKeyStatus.swift
// （与前端 C 的文件结构保持一致）
