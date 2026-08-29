import Foundation

/// Privacy-minimal subset of Kimi Code's Hook payload.
///
/// The complete body can contain prompts, tool arguments, permission display
/// details, failure messages and future vendor fields. Dev Island decodes only
/// categorical state needed by the island; vendor-authored text is ignored so
/// it cannot enter task persistence accidentally.
public struct KimiCodeEvent: Decodable, Sendable {
    public enum Kind: String, Decodable, Sendable {
        case sessionStart = "SessionStart"
        case turnStarted = "TurnStarted"
        case permissionRequest = "PermissionRequest"
        case permissionResult = "PermissionResult"
        case stop = "Stop"
        case stopFailure = "StopFailure"
        case interrupt = "Interrupt"
        case sessionEnd = "SessionEnd"
    }

    public let hookEventName: Kind
    public let sessionId: String
    public let cwd: String?
    public let errorType: String?

    public init(
        hookEventName: Kind,
        sessionId: String,
        cwd: String? = nil,
        errorType: String? = nil
    ) {
        self.hookEventName = hookEventName
        self.sessionId = sessionId
        self.cwd = cwd
        self.errorType = errorType
    }
}
