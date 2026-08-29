import Foundation

/// Low-frequency Qwen Code hook payload used for lifecycle and attention.
///
/// Qwen sends a forward-extensible JSON object. This deliberately decodes
/// only the fields needed to render task state; prompts, assistant output,
/// transcript paths, permission suggestions and error details are ignored.
public struct QwenCodeEvent: Decodable, Sendable {

    public enum Kind: String, Decodable, Sendable {
        case sessionStart = "SessionStart"
        case userPromptSubmit = "UserPromptSubmit"
        case permissionRequest = "PermissionRequest"
        case notification = "Notification"
        case stop = "Stop"
        case stopFailure = "StopFailure"
        case sessionEnd = "SessionEnd"
    }

    public let hookEventName: Kind
    public let sessionId: String
    public let cwd: String?
    public let toolName: String?
    public let message: String?
    public let notificationType: String?
    public let error: String?

    public init(
        hookEventName: Kind,
        sessionId: String,
        cwd: String? = nil,
        toolName: String? = nil,
        message: String? = nil,
        notificationType: String? = nil,
        error: String? = nil
    ) {
        self.hookEventName = hookEventName
        self.sessionId = sessionId
        self.cwd = cwd
        self.toolName = toolName
        self.message = message
        self.notificationType = notificationType
        self.error = error
    }
}
