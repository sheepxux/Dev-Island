import Foundation

/// Gemini CLI's registry row and payload semantics.
///
/// The connector deliberately subscribes only to low-frequency lifecycle
/// events. Gemini's Notification hook can reveal a ToolPermission prompt,
/// but its public contract does not let this passive hook return the user's
/// authorization decision, so the capability remains observe-only.
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
        settingsSubtitle: "Track lifecycle and permission attention in the island",
        releaseStage: .preview,
        configPath: "~/.gemini/settings.json",
        hookEvents: [
            "SessionStart", "BeforeAgent", "Notification", "AfterAgent", "SessionEnd",
        ],
        hookEntryStyle: .nestedWithEmptyMatcher,
        appCandidates: [],
        usesTerminalFallback: true,
        capabilities: AgentCapabilities(permissionRequests: .observeOnly),
        decodeEvent: { data in
            (Self.decodePayload(data) as GeminiCLIEvent?)?.normalized
        }
    )
}

extension GeminiCLIEvent {
    /// Translate Gemini's hook vocabulary into Dev Island lifecycle state.
    /// Empty or whitespace-only IDs are rejected before they can collapse
    /// unrelated malformed events into one shared task.
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
                message: message ?? "Approval needed in Gemini CLI"
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
