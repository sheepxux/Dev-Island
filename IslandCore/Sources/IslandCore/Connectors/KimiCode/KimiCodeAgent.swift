import Foundation

/// Kimi Code CLI's Preview registry row and normalized event semantics.
///
/// Pinned vendor contract: `@moonshot-ai/kimi-code@0.38.0`, release commit
/// `0999454bdcb5ddd98f39bffee434dcf0a810f394`.
///
/// Kimi Code exposes explicit observation-only `PermissionRequest` and
/// `PermissionResult` Hooks. They let Dev Island surface attention promptly,
/// but their stdout cannot answer approval, so the native Kimi UI remains the
/// only decision surface.
///
/// Status mapping:
///   SessionStart / TurnStarted / PermissionResult -> .running
///   PermissionRequest                                -> .waiting
///   Stop                                             -> .completed
///   StopFailure                                      -> .failed
///   Interrupt                                        -> .completed(interrupted)
///   SessionEnd                                       -> session removed
extension LocalAgentDescriptor {
    public static let kimiCode = LocalAgentDescriptor(
        source: "kimi-code",
        displayName: "Kimi Code CLI",
        settingsSubtitle: "Preview lifecycle and approval attention",
        releaseStage: .preview,
        configPath: "~/.kimi-code/config.toml",
        hookEvents: [
            "SessionStart", "TurnStarted",
            "PermissionRequest", "PermissionResult",
            "Stop", "StopFailure", "Interrupt", "SessionEnd",
        ],
        hookEntryStyle: .tomlArrayOfTables,
        appCandidates: [],
        usesTerminalFallback: true,
        capabilities: AgentCapabilities(permissionRequests: .observeOnly),
        decodeEvent: { data in
            (Self.decodePayload(data) as KimiCodeEvent?)?.normalized
        }
    )
}

extension KimiCodeEvent {
    public var normalized: LocalAgentEvent? {
        guard let id = LocalAgentEvent.validSessionId(sessionId) else { return nil }
        return LocalAgentEvent(sessionId: id, cwd: cwd, action: action)
    }

    private var action: LocalAgentEvent.Action {
        switch hookEventName {
        case .sessionStart, .turnStarted, .permissionResult:
            return .running
        case .permissionRequest:
            return .waiting(
                phase: "Needs approval",
                message: "Approval needed in Kimi Code CLI"
            )
        case .stop:
            return .completed(phase: nil)
        case .stopFailure:
            return .failed(phase: failurePhase)
        case .interrupt:
            return .completed(phase: "Interrupted")
        case .sessionEnd:
            return .sessionEnd
        }
    }

    /// Error messages can contain prompt/provider content. Only a small
    /// allowlist of vendor error classes changes the persisted phase label.
    private var failurePhase: String {
        switch errorType {
        case "APIError", "APIConnectionError", "APITimeoutError":
            return "Connection failed"
        case "AuthenticationError":
            return "Authentication failed"
        case "RateLimitError":
            return "Rate limit reached"
        default:
            return "Turn failed"
        }
    }
}

extension LocalAgentConnector {
    /// Typed convenience for tests and previews.
    public func apply(_ event: KimiCodeEvent, now: Date = .now) -> [AgentTask] {
        apply(event.normalized, now: now)
    }
}
