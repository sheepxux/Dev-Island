import Foundation

/// One lifecycle event emitted by a Claude Code hook.
///
/// Claude Code invokes our hook command (a `curl` one-liner installed into
/// `~/.claude/settings.json`) and pipes a JSON payload on stdin, which the
/// hook forwards verbatim to `LocalHookServer`. Field names are snake_case
/// (`session_id`, `hook_event_name`, …) — decode with `.convertFromSnakeCase`.
///
/// Only the events we install hooks for are modeled. Anything else fails to
/// decode and is dropped by the server without disturbing Claude Code.
public struct ClaudeCodeEvent: Decodable, Sendable {

    public enum Kind: String, Decodable, Sendable {
        case sessionStart     = "SessionStart"
        case userPromptSubmit = "UserPromptSubmit"
        case notification     = "Notification"
        case stop             = "Stop"
        case stopFailure      = "StopFailure"
        case sessionEnd       = "SessionEnd"
    }

    public let hookEventName: Kind
    public let sessionId: String
    /// Project directory the session runs in. Used for the task title and
    /// the open-in-Finder URL.
    public let cwd: String?
    /// Human-readable text carried by `Notification` events.
    public let message: String?
    /// Notification subtype (`permission_prompt`, `idle_prompt`,
    /// `agent_needs_input`, `auth_success`, …). Missing on older Claude Code
    /// versions — treat absence as "needs attention".
    public let notificationType: String?

    public init(
        hookEventName: Kind,
        sessionId: String,
        cwd: String? = nil,
        message: String? = nil,
        notificationType: String? = nil
    ) {
        self.hookEventName = hookEventName
        self.sessionId = sessionId
        self.cwd = cwd
        self.message = message
        self.notificationType = notificationType
    }
}
