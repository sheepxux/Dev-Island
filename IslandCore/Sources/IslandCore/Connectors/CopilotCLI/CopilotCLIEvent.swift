import Foundation

/// Low-frequency GitHub Copilot CLI Hook payload used for lifecycle and
/// attention. The PascalCase event configuration selects Copilot's documented
/// snake_case, VS Code-compatible wire format.
///
/// Only bounded categorical fields are modeled. Prompts, transcripts, error
/// messages/stacks, tool arguments, notification text, and future fields are
/// intentionally ignored so they cannot enter task state accidentally.
public struct CopilotCLIEvent: Decodable, Sendable {
    public enum Kind: String, Decodable, Sendable {
        case sessionStart = "SessionStart"
        case userPromptSubmit = "UserPromptSubmit"
        case notification = "Notification"
        case stop = "Stop"
        case errorOccurred = "ErrorOccurred"
        case sessionEnd = "SessionEnd"
    }

    public let hookEventName: Kind
    public let sessionId: String
    public let cwd: String?
    public let notificationType: String?
    public let recoverable: Bool?
    public let errorContext: String?

    public init(
        hookEventName: Kind,
        sessionId: String,
        cwd: String? = nil,
        notificationType: String? = nil,
        recoverable: Bool? = nil,
        errorContext: String? = nil
    ) {
        self.hookEventName = hookEventName
        self.sessionId = sessionId
        self.cwd = cwd
        self.notificationType = notificationType
        self.recoverable = recoverable
        self.errorContext = errorContext
    }
}
