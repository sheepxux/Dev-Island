import Foundation

/// Normalized lifecycle event — the lingua franca between per-agent hook
/// payloads and the generic `LocalAgentConnector`.
///
/// Each agent's raw payload (`ClaudeCodeEvent`, `CodexEvent`, `CursorEvent`,
/// …) is translated into this shape by its `normalized` mapping, so the
/// connector machinery (session table, TTL pruning, generation guard) is
/// written exactly once. Adding an agent means writing a payload struct and
/// a mapping — never another connector.
public struct LocalAgentEvent: Sendable, Equatable {

    /// What the event means for the session's task, in task vocabulary.
    public enum Action: Sendable, Equatable {
        /// The agent is working (session started / prompt submitted).
        case running
        /// The agent is blocked on the user (permission, input, …).
        case waiting(phase: String, message: String?)
        /// The turn finished successfully. `phase` annotates non-default
        /// endings (e.g. Cursor's "Aborted").
        case completed(phase: String?)
        /// The turn finished with an error.
        case failed(phase: String)
        /// The session is gone — remove its task.
        case sessionEnd
        /// Decodable but not actionable (e.g. Claude's `auth_success`
        /// notification). Still triggers table pruning, mutates nothing.
        case ignored
    }

    /// Stable per-session identifier (unique within one source).
    public let sessionId: String
    /// Project directory used for the task title / open-in-Finder URL.
    public let cwd: String?
    /// Ordering token for agents that dispatch hook processes
    /// asynchronously (Cursor's `generation_id`). When present, the
    /// connector's generation guard drops stale out-of-order events;
    /// agents with synchronous delivery leave it `nil` and every event
    /// applies directly.
    public let generationId: String?
    public let action: Action

    public init(
        sessionId: String,
        cwd: String? = nil,
        generationId: String? = nil,
        action: Action
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.generationId = generationId
        self.action = action
    }

    /// Session-id hygiene for payload mappings: a malformed local request
    /// with an empty/whitespace id must be dropped, not keyed as one
    /// shared "" task. Returns the trimmed id, or `nil` when unusable.
    public static func validSessionId(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
