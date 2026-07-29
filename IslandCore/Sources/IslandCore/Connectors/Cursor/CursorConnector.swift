import Foundation

/// Tracks Cursor agent conversations as `AgentTask`s.
///
/// Event-sourced from hook callbacks delivered by `LocalHookServer`, same
/// as the Claude Code and Codex connectors. Session bookkeeping lives in
/// `LocalSessionTable`; this type only supplies the Cursor event vocabulary.
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
public actor CursorConnector: AgentConnector {
    public let source = "cursor"

    private var table = LocalSessionTable(source: "cursor", displayName: "Cursor")

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
    public func apply(_ event: CursorEvent, now: Date = .now) -> [AgentTask] {
        table.prune(now: now)

        guard let id = event.id else { return table.snapshot() }

        switch event.hookEventName {
        case .sessionStart, .beforeSubmitPrompt:
            table.upsert(id: id, cwd: event.cwd, now: now) { task in
                task.status = .running
                task.currentPhase = nil
                task.waitingMessage = nil
            }

        case .stop:
            table.upsert(id: id, cwd: event.cwd, now: now) { task in
                switch event.status {
                case "error":
                    task.status = .failed
                    task.currentPhase = "Error"
                case "aborted":
                    task.status = .completed
                    task.currentPhase = "Aborted"
                default:
                    task.status = .completed
                    task.currentPhase = nil
                }
                task.waitingMessage = nil
            }

        case .sessionEnd:
            table.remove(id: id)
        }

        return table.snapshot()
    }
}
