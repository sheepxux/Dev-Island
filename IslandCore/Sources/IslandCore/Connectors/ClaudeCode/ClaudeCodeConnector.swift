import Foundation

/// Tracks local Claude Code sessions as `AgentTask`s.
///
/// Unlike `ManusConnector` there is no remote API: state is event-sourced
/// from hook callbacks delivered by `LocalHookServer`. Each session becomes
/// one task; the task's `taskURL` is a `file://` URL of the project
/// directory so "open" lands in Finder.
///
/// Status mapping:
///   SessionStart / UserPromptSubmit          → .running
///   Notification (permission/idle/input/…)   → .waiting
///   Notification (agent_completed)           → .completed
///   Stop                                      → .completed
///   StopFailure                               → .failed
///   SessionEnd                                → session removed
public actor ClaudeCodeConnector: AgentConnector {
    public let source = "claude-code"

    /// Notification subtypes that mean "the agent is blocked on the user".
    static let waitingNotificationTypes: Set<String> = [
        "permission_prompt", "idle_prompt", "agent_needs_input", "elicitation_dialog",
    ]
    /// Notification subtypes that carry no actionable state change.
    static let ignoredNotificationTypes: Set<String> = [
        "auth_success", "elicitation_complete", "elicitation_response",
    ]

    public static let finishedTTL = LocalSessionTable.finishedTTL
    public static let staleTTL = LocalSessionTable.staleTTL

    private var table = LocalSessionTable(source: "claude-code", displayName: "Claude Code")

    public init() {}

    // MARK: - AgentConnector

    public func fetchTasks() async throws -> [AgentTask] {
        table.snapshot()
    }

    nonisolated public func openInBrowser(taskId: String) {
        // URL opening is handled by TaskStore.openTaskInBrowser(id:).
    }

    public func stop(taskId: String) async throws {
        // Local sessions can't be stopped remotely — no-op by design.
    }

    // MARK: - Event ingestion

    /// Apply one hook event and return the updated task snapshot.
    public func apply(_ event: ClaudeCodeEvent, now: Date = .now) -> [AgentTask] {
        table.prune(now: now)

        switch event.hookEventName {
        case .sessionStart, .userPromptSubmit:
            table.upsert(id: event.sessionId, cwd: event.cwd, now: now) { task in
                task.status = .running
                task.currentPhase = nil
                task.waitingMessage = nil
            }

        case .notification:
            applyNotification(event, now: now)

        case .stop:
            table.upsert(id: event.sessionId, cwd: event.cwd, now: now) { task in
                task.status = .completed
                task.currentPhase = nil
                task.waitingMessage = nil
            }

        case .stopFailure:
            table.upsert(id: event.sessionId, cwd: event.cwd, now: now) { task in
                task.status = .failed
                task.currentPhase = "Turn ended with an API error"
                task.waitingMessage = nil
            }

        case .sessionEnd:
            table.remove(id: event.sessionId)
        }

        return table.snapshot()
    }

    // MARK: - Private

    private func applyNotification(_ event: ClaudeCodeEvent, now: Date) {
        let type = event.notificationType

        if let type, Self.ignoredNotificationTypes.contains(type) {
            return
        }
        if type == "agent_completed" {
            table.upsert(id: event.sessionId, cwd: event.cwd, now: now) { task in
                task.status = .completed
                task.currentPhase = nil
                task.waitingMessage = nil
            }
            return
        }
        // Known waiting subtypes — and, defensively, any unknown/missing
        // subtype: a notification generally means Claude wants attention.
        table.upsert(id: event.sessionId, cwd: event.cwd, now: now) { task in
            task.status = .waiting
            task.currentPhase = "Needs input"
            task.waitingMessage = event.message
        }
    }
}
