import Foundation

/// One lifecycle event emitted by a Gemini CLI command hook.
///
/// Gemini CLI invokes hooks from `~/.gemini/settings.json` and writes a JSON
/// payload to the command's stdin. Every event shares `session_id`, `cwd`, and
/// `hook_event_name`; event-specific fields are optional here so the same
/// compact payload type can cover the lifecycle events Dev Island subscribes
/// to. Unknown JSON fields (prompt text, transcript path, details, etc.) are
/// intentionally ignored by `JSONDecoder`.
public struct GeminiCLIEvent: Decodable, Sendable {

    public enum Kind: String, Decodable, Sendable {
        case sessionStart = "SessionStart"
        case beforeAgent  = "BeforeAgent"
        case notification = "Notification"
        case afterAgent   = "AfterAgent"
        case sessionEnd   = "SessionEnd"
    }

    public let hookEventName: Kind
    public let sessionId: String
    /// Project directory the CLI session runs in.
    public let cwd: String?
    /// Human-readable summary carried by `Notification` events.
    public let message: String?
    /// Gemini's notification category. As of the hooks reference, the only
    /// public value is `ToolPermission`.
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
