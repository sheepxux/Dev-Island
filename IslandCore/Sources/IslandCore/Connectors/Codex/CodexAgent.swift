import Foundation

/// Codex's registry row + payload semantics.
///
/// Status mapping:
///   SessionStart / UserPromptSubmit → .running
///   PermissionRequest               → .waiting (Codex is about to ask)
///   Stop                            → .completed
///   SessionEnd                      → session removed
extension LocalAgentDescriptor {
    public static let codex = LocalAgentDescriptor(
        source: "codex",
        displayName: "Codex",
        settingsSubtitle: "Track local Codex CLI sessions in the island",
        configPath: "~/.codex/hooks.json",
        hookEvents: [
            "SessionStart", "UserPromptSubmit", "PermissionRequest",
            "Stop", "SessionEnd",
        ],
        hookEntryStyle: .nested,
        appCandidates: ["com.openai.codex"],  // Codex Desktop first
        usesTerminalFallback: true,           // CLI sessions live in a terminal
        decodeEvent: { data in
            (Self.decodePayload(data) as CodexEvent?)?.normalized
        }
    )
}

extension CodexEvent {

    /// Translate to the connector's normalized vocabulary.
    public var normalized: LocalAgentEvent? {
        LocalAgentEvent(sessionId: sessionId, cwd: cwd, action: action)
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
        case .stop:
            return .completed(phase: nil)
        case .sessionEnd:
            return .sessionEnd
        }
    }
}

extension LocalAgentConnector {
    /// Typed convenience for tests and previews.
    public func apply(_ event: CodexEvent, now: Date = .now) -> [AgentTask] {
        apply(event.normalized, now: now)
    }
}
