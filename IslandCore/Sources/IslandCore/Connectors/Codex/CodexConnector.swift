import Foundation

/// Tracks local Codex CLI sessions as `AgentTask`s.
///
/// Event-sourced from hook callbacks delivered by `LocalHookServer`, same
/// as `ClaudeCodeConnector`. Session bookkeeping lives in
/// `LocalSessionTable`; this type only supplies the Codex event vocabulary.
///
/// Status mapping:
///   SessionStart / UserPromptSubmit → .running
///   PermissionRequest               → .waiting (Codex is about to ask)
///   Stop                            → .completed
///   SessionEnd                      → session removed
public actor CodexConnector: AgentConnector {
    public let source = "codex"

    private var table = LocalSessionTable(source: "codex", displayName: "Codex")

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
    public func apply(_ event: CodexEvent, now: Date = .now) -> [AgentTask] {
        table.prune(now: now)

        switch event.hookEventName {
        case .sessionStart, .userPromptSubmit:
            table.upsert(id: event.sessionId, cwd: event.cwd, now: now) { task in
                task.status = .running
                task.currentPhase = nil
                task.waitingMessage = nil
            }

        case .permissionRequest:
            table.upsert(id: event.sessionId, cwd: event.cwd, now: now) { task in
                task.status = .waiting
                task.currentPhase = "Needs approval"
                task.waitingMessage = event.toolName.map { "Approval needed: \($0)" }
                    ?? "Approval needed"
            }

        case .stop:
            table.upsert(id: event.sessionId, cwd: event.cwd, now: now) { task in
                task.status = .completed
                task.currentPhase = nil
                task.waitingMessage = nil
            }

        case .sessionEnd:
            table.remove(id: event.sessionId)
        }

        return table.snapshot()
    }
}
