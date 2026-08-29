import Foundation

/// One low-frequency lifecycle event emitted by a Gemini CLI command hook.
///
/// Gemini CLI writes JSON to the hook command's stdin. Every subscribed
/// event shares `session_id`, `cwd`, and `hook_event_name`; event-specific
/// fields are optional so this compact type can cover the lifecycle contract
/// without retaining prompts, model responses, transcript paths, or tool
/// details. Unknown JSON fields are intentionally ignored by `JSONDecoder`.
public struct GeminiCLIEvent: Decodable, Sendable {

    public enum Kind: String, Decodable, Sendable {
        case sessionStart = "SessionStart"
        case beforeAgent = "BeforeAgent"
        case notification = "Notification"
        case afterAgent = "AfterAgent"
        case sessionEnd = "SessionEnd"
    }

    public let hookEventName: Kind
    public let sessionId: String
    /// Project directory used only to derive the local task title and URL.
    public let cwd: String?
    /// Human-readable summary carried by Notification events.
    public let message: String?
    /// Gemini's notification category. Only ToolPermission is actionable in
    /// the verified hook contract; unknown categories must remain quiet.
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
