import Foundation

/// OpenCode Preview registry row and normalized lifecycle semantics.
///
/// Pinned vendor contract: OpenCode / `@opencode-ai/plugin` 1.18.23 at
/// commit 13c27598d35f6f91fa4763a0b61a220ab7fcb263. The plugin API exposes a
/// mutable `permission.ask` hook, but Preview deliberately uses only generic
/// observation events until a real signed-in CLI proves timing and fallback.
extension LocalAgentDescriptor {
    public static let openCode = LocalAgentDescriptor(
        source: "opencode",
        displayName: "OpenCode",
        settingsSubtitle: "Preview lifecycle and permission attention through a local plugin",
        releaseStage: .preview,
        configPath: "~/.config/opencode/plugins/dev-island.js",
        hookEvents: [
            "session.created", "session.status", "session.idle",
            "session.deleted", "session.error", "permission.updated",
            "permission.replied",
        ],
        hookEntryStyle: .standaloneJavaScriptPlugin,
        appCandidates: [],
        usesTerminalFallback: true,
        capabilities: AgentCapabilities(permissionRequests: .observeOnly),
        standalonePluginRenderer: { port in
            OpenCodePlugin.render(port: port)
        },
        decodeEvent: { data in
            (Self.decodePayload(data) as OpenCodeEvent?)?.normalized
        }
    )
}

extension OpenCodeEvent {
    public var normalized: LocalAgentEvent? {
        guard schemaVersion == OpenCodePlugin.schemaVersion,
              let id = LocalAgentEvent.validSessionId(sessionId)
        else { return nil }
        if case .sessionStatus = event,
           status != "busy" && status != "idle" && status != "retry" {
            return nil
        }
        return LocalAgentEvent(sessionId: id, cwd: cwd, action: action)
    }

    private var action: LocalAgentEvent.Action {
        switch event {
        case .sessionCreated:
            return .running
        case .sessionStatus:
            switch status {
            case "busy":
                return .running
            case "idle":
                return .completed(phase: nil)
            case "retry":
                // Retry is vendor activity, not a request for the user. It
                // must never enter the island's human-attention queue.
                return .running
            default:
                // `normalized` rejects unknown/missing status values before
                // this mapping. Keep a non-mutating fallback so future enum
                // evolution cannot turn an unverified status into activity.
                return .ignored
            }
        case .sessionIdle:
            return .completed(phase: nil)
        case .sessionDeleted:
            return .sessionEnd
        case .sessionError:
            return .failed(phase: "Session failed")
        case .permissionUpdated:
            return .waiting(
                phase: "Needs approval",
                message: "Approval needed in OpenCode"
            )
        case .permissionReplied:
            return .running
        }
    }
}

extension LocalAgentConnector {
    public func apply(_ event: OpenCodeEvent, now: Date = .now) -> [AgentTask] {
        apply(event.normalized, now: now)
    }
}
