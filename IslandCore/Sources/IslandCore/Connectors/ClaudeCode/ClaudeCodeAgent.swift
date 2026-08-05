import Foundation

/// Claude Code's registry row + payload semantics.
///
/// Status mapping:
///   SessionStart / UserPromptSubmit        → .running
///   Notification (permission/idle/input/…) → .waiting
///   Notification (agent_completed)         → .completed
///   Stop                                   → .completed
///   StopFailure                            → .failed
///   SessionEnd                             → session removed
extension LocalAgentDescriptor {
    public static let claudeCode = LocalAgentDescriptor(
        source: "claude-code",
        displayName: "Claude Code",
        settingsSubtitle: "Track local Claude Code sessions in the island",
        configPath: "~/.claude/settings.json",
        hookEvents: [
            "SessionStart", "UserPromptSubmit", "Notification",
            "Stop", "StopFailure", "SessionEnd",
        ],
        hookEntryStyle: .nestedWithEmptyMatcher,
        appCandidates: [],
        usesTerminalFallback: true,
        decodeEvent: { data in
            (Self.decodePayload(data) as ClaudeCodeEvent?)?.normalized
        }
    )
}

extension ClaudeCodeEvent {

    /// Notification subtypes that mean "the agent is blocked on the user".
    static let waitingNotificationTypes: Set<String> = [
        "permission_prompt", "idle_prompt", "agent_needs_input", "elicitation_dialog",
    ]
    /// Notification subtypes that carry no actionable state change.
    static let ignoredNotificationTypes: Set<String> = [
        "auth_success", "elicitation_complete", "elicitation_response",
    ]

    /// Translate to the connector's normalized vocabulary. `nil` when the
    /// payload carries no usable session identifier.
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
        case .stopFailure:
            return .failed(phase: "Turn ended with an API error")
        case .sessionEnd:
            return .sessionEnd
        }
    }

    private var notificationAction: LocalAgentEvent.Action {
        if let type = notificationType, Self.ignoredNotificationTypes.contains(type) {
            return .ignored
        }
        if notificationType == "agent_completed" {
            return .completed(phase: nil)
        }
        // Known waiting subtypes — and, defensively, any unknown/missing
        // subtype: a notification generally means Claude wants attention.
        return .waiting(phase: "Needs input", message: message)
    }
}

extension LocalAgentConnector {
    /// Typed convenience for tests and previews.
    public func apply(_ event: ClaudeCodeEvent, now: Date = .now) -> [AgentTask] {
        apply(event.normalized, now: now)
    }
}
