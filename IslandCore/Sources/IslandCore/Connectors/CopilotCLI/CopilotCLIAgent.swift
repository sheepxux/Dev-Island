import Foundation

/// GitHub Copilot CLI's Preview registry row and normalized event semantics.
///
/// Pinned vendor contract: `@github/copilot@1.0.80` plus the GitHub Docs
/// Hook reference at commit `be8d08aa6e3a95d7f531c6a00cbeff883e4e9814`.
///
/// Dev Island deliberately uses PascalCase event names so Copilot emits the
/// documented VS Code-compatible payload with `hook_event_name`. Native
/// camelCase payloads do not carry an event discriminator, while every event
/// shares one loopback route in the declarative connector framework.
///
/// Status mapping:
///   SessionStart / UserPromptSubmit -> .running
///   Notification(permission_prompt) -> .waiting
///   Notification(elicitation_dialog)-> .waiting
///   Stop                             -> .completed
///   ErrorOccurred(non-recoverable)   -> .failed
///   SessionEnd                       -> session removed
extension LocalAgentDescriptor {
    public static let copilotCLI = LocalAgentDescriptor(
        source: "copilot-cli",
        displayName: "GitHub Copilot CLI",
        settingsSubtitle: "Preview lifecycle, approval and input attention",
        releaseStage: .preview,
        configPath: "~/.copilot/hooks/dev-island.json",
        hookEvents: [
            "SessionStart", "UserPromptSubmit", "Notification",
            "Stop", "ErrorOccurred", "SessionEnd",
        ],
        hookEntryStyle: .flatVersioned,
        appCandidates: [],
        usesTerminalFallback: true,
        capabilities: AgentCapabilities(
            permissionRequests: .observeOnly,
            questionRequests: .observeOnly
        ),
        decodeEvent: { data in
            (Self.decodePayload(data) as CopilotCLIEvent?)?.normalized
        }
    )
}

extension CopilotCLIEvent {
    public var normalized: LocalAgentEvent? {
        guard let id = LocalAgentEvent.validSessionId(sessionId) else { return nil }
        return LocalAgentEvent(sessionId: id, cwd: cwd, action: action)
    }

    private var action: LocalAgentEvent.Action {
        switch hookEventName {
        case .sessionStart, .userPromptSubmit:
            return .running
        case .notification:
            return notificationAction
        case .stop:
            return .completed(phase: nil)
        case .errorOccurred:
            guard recoverable == false else { return .ignored }
            return .failed(phase: failurePhase)
        case .sessionEnd:
            return .sessionEnd
        }
    }

    /// Notification text can contain vendor- or tool-authored content. The
    /// Preview connector therefore stores only a fixed category label; the
    /// complete raw payload transits loopback but is never logged or retained.
    private var notificationAction: LocalAgentEvent.Action {
        switch notificationType {
        case "permission_prompt":
            return .waiting(
                phase: "Needs approval",
                message: "Approval needed in Copilot CLI"
            )
        case "elicitation_dialog":
            return .waiting(
                phase: "Needs input",
                message: "Input needed in Copilot CLI"
            )
        default:
            return .ignored
        }
    }

    private var failurePhase: String {
        switch errorContext {
        case "model_call": return "Model call failed"
        case "tool_execution": return "Tool execution failed"
        case "user_input": return "Input failed"
        default: return "Session failed"
        }
    }
}

extension LocalAgentConnector {
    /// Typed convenience for tests and previews.
    public func apply(_ event: CopilotCLIEvent, now: Date = .now) -> [AgentTask] {
        apply(event.normalized, now: now)
    }
}
