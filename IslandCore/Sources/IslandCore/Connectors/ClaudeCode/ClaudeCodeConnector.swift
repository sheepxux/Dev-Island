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

    /// Finished sessions linger briefly so the user sees the green state,
    /// then get pruned. Sessions that stop emitting events entirely (e.g.
    /// Claude Code crashed before SessionEnd) are dropped after a day.
    static let finishedTTL: TimeInterval = 2 * 60 * 60
    static let staleTTL: TimeInterval = 24 * 60 * 60

    private var sessions: [String: AgentTask] = [:]

    public init() {}

    // MARK: - AgentConnector

    public func fetchTasks() async throws -> [AgentTask] {
        snapshot()
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
        prune(now: now)

        switch event.hookEventName {
        case .sessionStart, .userPromptSubmit:
            upsert(event, now: now) { task in
                task.status = .running
                task.currentPhase = nil
                task.waitingMessage = nil
            }

        case .notification:
            applyNotification(event, now: now)

        case .stop:
            upsert(event, now: now) { task in
                task.status = .completed
                task.currentPhase = nil
                task.waitingMessage = nil
            }

        case .stopFailure:
            upsert(event, now: now) { task in
                task.status = .failed
                task.currentPhase = "Turn ended with an API error"
                task.waitingMessage = nil
            }

        case .sessionEnd:
            sessions.removeValue(forKey: event.sessionId)
        }

        return snapshot()
    }

    // MARK: - Private

    private func applyNotification(_ event: ClaudeCodeEvent, now: Date) {
        let type = event.notificationType

        if let type, Self.ignoredNotificationTypes.contains(type) {
            return
        }
        if type == "agent_completed" {
            upsert(event, now: now) { task in
                task.status = .completed
                task.currentPhase = nil
                task.waitingMessage = nil
            }
            return
        }
        // Known waiting subtypes — and, defensively, any unknown/missing
        // subtype: a notification generally means Claude wants attention.
        upsert(event, now: now) { task in
            task.status = .waiting
            task.currentPhase = "Needs input"
            task.waitingMessage = event.message
        }
    }

    private func upsert(_ event: ClaudeCodeEvent, now: Date, mutate: (inout AgentTask) -> Void) {
        var task = sessions[event.sessionId] ?? Self.newTask(for: event, now: now)
        mutate(&task)
        task.updatedAt = now
        sessions[event.sessionId] = task
    }

    private static func newTask(for event: ClaudeCodeEvent, now: Date) -> AgentTask {
        let projectURL = event.cwd.map { URL(fileURLWithPath: $0, isDirectory: true) }
        return AgentTask(
            id: event.sessionId,
            source: "claude-code",
            title: projectURL?.lastPathComponent ?? "Claude Code session",
            status: .running,
            createdAt: now,
            updatedAt: now,
            taskURL: projectURL?.absoluteString ?? ""
        )
    }

    private func prune(now: Date) {
        sessions = sessions.filter { _, task in
            let age = now.timeIntervalSince(task.updatedAt)
            switch task.status {
            case .completed, .failed: return age < Self.finishedTTL
            case .running, .waiting:  return age < Self.staleTTL
            }
        }
    }

    private func snapshot() -> [AgentTask] {
        sessions.values.sorted { $0.createdAt < $1.createdAt }
    }
}
