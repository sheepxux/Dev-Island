import Foundation

/// Gemini CLI's registry row + payload semantics.
///
/// Gemini CLI's user hook configuration uses the same nested group shape as
/// Claude Code (`matcher` + inner `hooks` array), so the existing
/// `.nestedWithEmptyMatcher` installer style is sufficient.
///
/// Status mapping:
///   SessionStart / BeforeAgent       -> .running
///   Notification(ToolPermission)     -> .waiting
///   AfterAgent                       -> .completed
///   SessionEnd                       -> session removed
extension LocalAgentDescriptor {
    public static let geminiCLI = LocalAgentDescriptor(
        source: "gemini-cli",
        displayName: "Gemini CLI",
        settingsSubtitle: "Track local Gemini CLI sessions in the island",
        configPath: "~/.gemini/settings.json",
        hookEvents: [
            "SessionStart", "BeforeAgent", "Notification", "AfterAgent", "SessionEnd",
        ],
        hookEntryStyle: .nestedWithEmptyMatcher,
        appCandidates: [],
        usesTerminalFallback: true,
        decodeEvent: { data in
            (Self.decodePayload(data) as GeminiCLIEvent?)?.normalized
        }
    )
}

extension GeminiCLIEvent {

    /// Translate Gemini's hook vocabulary into the connector framework's
    /// normalized lifecycle. A malformed session id is dropped before it can
    /// become a shared empty-key task.
    public var normalized: LocalAgentEvent? {
        guard let id = LocalAgentEvent.validSessionId(sessionId) else { return nil }
        return LocalAgentEvent(sessionId: id, cwd: cwd, action: action)
    }

    private var action: LocalAgentEvent.Action {
        switch hookEventName {
        case .sessionStart, .beforeAgent:
            return .running
        case .notification:
            guard notificationType == "ToolPermission" else { return .ignored }
            return .waiting(
                phase: "Needs approval",
                message: message ?? "Approval needed"
            )
        case .afterAgent:
            return .completed(phase: nil)
        case .sessionEnd:
            return .sessionEnd
        }
    }
}

extension LocalAgentConnector {
    /// Typed convenience for tests and previews.
    public func apply(_ event: GeminiCLIEvent, now: Date = .now) -> [AgentTask] {
        apply(event.normalized, now: now)
    }
}
