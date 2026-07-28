import Foundation

/// One lifecycle event emitted by a Codex CLI hook.
///
/// Codex's hooks engine pipes a JSON object on stdin to command hooks —
/// the same transport as Claude Code, with the same core fields
/// (`session_id`, `cwd`, `hook_event_name`). Our installed `curl` hook
/// forwards it verbatim to `LocalHookServer` on `/hooks/codex`.
///
/// Only the events we install hooks for are modeled. Anything else fails to
/// decode and is dropped by the server without disturbing Codex.
public struct CodexEvent: Decodable, Sendable {

    public enum Kind: String, Decodable, Sendable {
        case sessionStart      = "SessionStart"
        case userPromptSubmit  = "UserPromptSubmit"
        case permissionRequest = "PermissionRequest"
        case stop              = "Stop"
        case sessionEnd        = "SessionEnd"
    }

    public let hookEventName: Kind
    public let sessionId: String
    /// Working directory of the session. Used for the task title and the
    /// open-in-Finder URL.
    public let cwd: String?
    /// Tool awaiting approval — set on `PermissionRequest` events.
    public let toolName: String?

    public init(
        hookEventName: Kind,
        sessionId: String,
        cwd: String? = nil,
        toolName: String? = nil
    ) {
        self.hookEventName = hookEventName
        self.sessionId = sessionId
        self.cwd = cwd
        self.toolName = toolName
    }
}
