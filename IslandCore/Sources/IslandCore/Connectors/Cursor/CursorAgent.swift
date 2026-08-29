import Foundation

/// Cursor's registry row + payload semantics.
///
/// Status mapping:
///   sessionStart / beforeSubmitPrompt → .running
///   stop(completed)                   → .completed
///   stop(aborted)                     → .completed ("Aborted" phase)
///   stop(error)                       → .failed
///   sessionEnd                        → session removed
///
/// Cursor has no permission-request hook (its gating hooks answer inline),
/// so unlike Claude/Codex there is no `.waiting` mapping.
///
/// Cursor dispatches hook processes asynchronously, so events can arrive
/// out of order — `generation_id` is forwarded on prompts and stops, which
/// arms `LocalAgentConnector`'s generation guard. Known accepted
/// limitation: two *prompts* delivered in reverse order could mark the
/// newer generation superseded; not guarded because prompt emissions are
/// human-sequenced seconds apart while delivery jitter is milliseconds.
extension LocalAgentDescriptor {
    public static let cursor = LocalAgentDescriptor(
        source: "cursor",
        displayName: "Cursor",
        settingsSubtitle: "Track Cursor agent lifecycle and results in the island",
        configPath: "~/.cursor/hooks.json",
        hookEvents: [
            "sessionStart", "beforeSubmitPrompt", "stop", "sessionEnd",
        ],
        hookEntryStyle: .flatVersioned,
        appCandidates: ["com.todesktop.230313mzl4w4u92"],  // Cursor.app
        usesTerminalFallback: false,
        capabilities: .lifecycleOnly,
        decodeEvent: { data in
            (Self.decodePayload(data) as CursorEvent?)?.normalized
        }
    )
}

extension CursorEvent {

    /// Translate to the connector's normalized vocabulary. `nil` when the
    /// payload carries no usable session identifier.
    public var normalized: LocalAgentEvent? {
        guard let id = LocalAgentEvent.validSessionId(id) else { return nil }
        return LocalAgentEvent(
            sessionId: id,
            cwd: cwd,
            // sessionStart carries no generation; prompts/stops do. The
            // guard only needs the token on prompt/stop pairs.
            generationId: generationId,
            action: action
        )
    }

    private var action: LocalAgentEvent.Action {
        switch hookEventName {
        case .sessionStart, .beforeSubmitPrompt:
            return .running
        case .stop:
            switch status {
            case "error":   return .failed(phase: "Error")
            case "aborted": return .completed(phase: "Aborted")
            default:        return .completed(phase: nil)
            }
        case .sessionEnd:
            return .sessionEnd
        }
    }
}

extension LocalAgentConnector {
    /// Typed convenience for tests and previews.
    public func apply(_ event: CursorEvent, now: Date = .now) -> [AgentTask] {
        apply(event.normalized, now: now)
    }
}
