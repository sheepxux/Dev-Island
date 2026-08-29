import Foundation

/// Qwen Code's Preview registry row and normalized event semantics.
///
/// Pinned vendor contract: `@qwen-code/qwen-code@0.22.0`, upstream commit
/// `e38665674e2978f98cd35e7c6f6eac057741647f`.
///
/// Status mapping:
///   SessionStart / UserPromptSubmit       -> .running
///   PermissionRequest                    -> .waiting + Allow/Deny request
///   Notification(permission/idle prompt) -> .waiting
///   Stop                                 -> .completed
///   StopFailure                          -> .failed
///   SessionEnd                           -> session removed
extension LocalAgentDescriptor {
    public static let qwenCode = LocalAgentDescriptor(
        source: "qwen-code",
        displayName: "Qwen Code",
        settingsSubtitle: "Preview lifecycle and handle documented tool approvals",
        releaseStage: .preview,
        configPath: "~/.qwen/settings.json",
        hookEvents: [
            "SessionStart", "UserPromptSubmit", "PermissionRequest", "Notification",
            "Stop", "StopFailure", "SessionEnd",
        ],
        hookEntryStyle: .nestedWithEmptyMatcher,
        appCandidates: [],
        usesTerminalFallback: true,
        capabilities: AgentCapabilities(permissionRequests: .bidirectional),
        actionHookEvents: ["PermissionRequest"],
        actionHookTimeoutUnit: .milliseconds,
        decodeActionRequest: { data in
            QwenPermissionHook.decodeRequest(data)
        },
        encodeActionResponse: { response in
            QwenPermissionHook.response(forActionResponse: response)
        },
        decodeEvent: { data in
            (Self.decodePayload(data) as QwenCodeEvent?)?.normalized
        }
    )
}

extension QwenCodeEvent {
    public var normalized: LocalAgentEvent? {
        guard let id = LocalAgentEvent.validSessionId(sessionId) else { return nil }
        return LocalAgentEvent(sessionId: id, cwd: cwd, action: action)
    }

    private var action: LocalAgentEvent.Action {
        switch hookEventName {
        case .sessionStart, .userPromptSubmit:
            return .running
        case .permissionRequest:
            return .waiting(
                phase: "Needs approval",
                message: toolName.map { "Approval needed: \($0)" } ?? "Approval needed"
            )
        case .notification:
            return notificationAction
        case .stop:
            return .completed(phase: nil)
        case .stopFailure:
            return .failed(phase: failurePhase)
        case .sessionEnd:
            return .sessionEnd
        }
    }

    private var notificationAction: LocalAgentEvent.Action {
        switch notificationType {
        case "permission_prompt":
            return .waiting(phase: "Needs approval", message: message)
        case "idle_prompt":
            return .waiting(phase: "Needs input", message: message)
        default:
            return .ignored
        }
    }

    private var failurePhase: String {
        guard let error else { return "Turn failed" }
        switch error {
        case "rate_limit": return "Rate limit reached"
        case "authentication_failed": return "Authentication failed"
        case "billing_error": return "Billing error"
        case "invalid_request": return "Invalid request"
        case "server_error": return "Server error"
        case "max_output_tokens": return "Output limit reached"
        case "loop_detected": return "Loop detected"
        default: return "Turn failed"
        }
    }
}

extension LocalAgentConnector {
    /// Typed convenience for tests and previews.
    public func apply(_ event: QwenCodeEvent, now: Date = .now) -> [AgentTask] {
        apply(event.normalized, now: now)
    }
}
