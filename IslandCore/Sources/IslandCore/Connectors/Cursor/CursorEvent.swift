import Foundation

/// One lifecycle event emitted by a Cursor hook.
///
/// Cursor invokes our hook command (a `curl` one-liner installed into
/// `~/.cursor/hooks.json`) and pipes a JSON payload on stdin, which the hook
/// forwards verbatim to `LocalHookServer`. Field names are snake_case —
/// decode with `.convertFromSnakeCase`.
///
/// Unlike Claude Code / Codex, Cursor's event names are camelCase and the
/// stable session identifier is `conversation_id` (present on every agent
/// hook); `session_id` appears only on sessionStart / sessionEnd and holds
/// the same value. The project directory arrives as `workspace_roots`.
///
/// Only fire-and-forget events are modeled — we never subscribe to gating
/// hooks (`beforeShellExecution` etc.), so an empty response from our curl
/// command can never block a Cursor action. Anything else fails to decode
/// and is dropped by the server.
public struct CursorEvent: Decodable, Sendable {

    public enum Kind: String, Decodable, Sendable {
        case sessionStart
        case beforeSubmitPrompt
        case stop
        case sessionEnd
    }

    public let hookEventName: Kind
    /// Stable conversation ID; present on all agent hooks.
    public let conversationId: String?
    /// Only on sessionStart / sessionEnd — same value as `conversationId`.
    public let sessionId: String?
    /// Workspace root folders (normally exactly one).
    public let workspaceRoots: [String]?
    /// `stop` only: "completed" | "aborted" | "error".
    public let status: String?

    /// The identifier we key sessions by, whichever field carried it.
    public var id: String? { conversationId ?? sessionId }
    /// Project directory for the task title / open-in-Finder URL.
    public var cwd: String? { workspaceRoots?.first }

    public init(
        hookEventName: Kind,
        conversationId: String? = nil,
        sessionId: String? = nil,
        workspaceRoots: [String]? = nil,
        status: String? = nil
    ) {
        self.hookEventName = hookEventName
        self.conversationId = conversationId
        self.sessionId = sessionId
        self.workspaceRoots = workspaceRoots
        self.status = status
    }
}
