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

    public static let maximumSessionIDBytes = 256
    public static let maximumGenerationIDBytes = 256
    public static let maximumCWDBytes = 4_096
    public static let maximumPhaseCharacters = 256
    public static let maximumPhaseBytes = 1_024
    public static let maximumMessageCharacters = 1_024
    public static let maximumMessageBytes = 4_096

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
    /// Validated terminal host / tmux metadata attached by LocalHookServer.
    /// Vendor payload decoders never read the process environment directly.
    public let jumpContext: SessionJumpContext?
    public let action: Action

    public init(
        sessionId: String,
        cwd: String? = nil,
        generationId: String? = nil,
        jumpContext: SessionJumpContext? = nil,
        action: Action
    ) {
        self.sessionId = sessionId
        self.cwd = Self.validCWD(cwd)
        self.generationId = Self.validGenerationID(generationId)
        self.jumpContext = jumpContext
        self.action = Self.bounded(action)
    }

    func withJumpContext(_ jumpContext: SessionJumpContext?) -> Self {
        Self(
            sessionId: sessionId,
            cwd: cwd,
            generationId: generationId,
            jumpContext: jumpContext,
            action: action
        )
    }

    /// Session-id hygiene for payload mappings: a malformed local request
    /// with an empty/whitespace id must be dropped, not keyed as one
    /// shared "" task. Returns the trimmed id, or `nil` when unusable.
    public static func validSessionId(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isBoundedNoncontrolText(
            trimmed,
            maximumUTF8Bytes: maximumSessionIDBytes
        ) else { return nil }
        return trimmed
    }

    private static func validGenerationID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isBoundedNoncontrolText(
            trimmed,
            maximumUTF8Bytes: maximumGenerationIDBytes
        ) else { return nil }
        return trimmed
    }

    private static func validCWD(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"),
              isBoundedNoncontrolText(
                trimmed,
                maximumUTF8Bytes: maximumCWDBytes
              ) else { return nil }
        return trimmed
    }

    private static func isBoundedNoncontrolText(
        _ value: String,
        maximumUTF8Bytes: Int
    ) -> Bool {
        guard !value.isEmpty, value.utf8.count <= maximumUTF8Bytes else {
            return false
        }
        return value.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0)
        }
    }

    private static func bounded(_ action: Action) -> Action {
        switch action {
        case .running, .sessionEnd, .ignored:
            return action
        case .waiting(let phase, let message):
            return .waiting(
                phase: boundedPhase(phase),
                message: message.map(boundedMessage)
            )
        case .completed(let phase):
            return .completed(phase: phase.map(boundedPhase))
        case .failed(let phase):
            return .failed(phase: boundedPhase(phase))
        }
    }

    private static func boundedPhase(_ value: String) -> String {
        AgentActionTextPolicy.bounded(
            value,
            maximumCharacters: maximumPhaseCharacters,
            maximumUTF8Bytes: maximumPhaseBytes
        )
    }

    private static func boundedMessage(_ value: String) -> String {
        AgentActionTextPolicy.bounded(
            value,
            maximumCharacters: maximumMessageCharacters,
            maximumUTF8Bytes: maximumMessageBytes
        )
    }
}
