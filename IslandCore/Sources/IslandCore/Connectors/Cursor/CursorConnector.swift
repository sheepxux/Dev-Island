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
///
/// Generation guard: Cursor dispatches hook processes asynchronously, so a
/// `stop` from an aborted generation can arrive *after* the
/// `beforeSubmitPrompt` of the next one and would wrongly paint a running
/// session as "Aborted". We track generations that were explicitly
/// *superseded* by a newer prompt and drop their late `stop`s. Unknown
/// generations always apply — generation IDs aren't ordered, so "not yet
/// superseded" is the only safe staleness signal (a legit `stop` may even
/// outrace its own `beforeSubmitPrompt`).
public actor CursorConnector: AgentConnector {
    public let source = "cursor"

    private var table = LocalSessionTable(source: "cursor", displayName: "Cursor")
    /// Latest generation seen per session (from beforeSubmitPrompt).
    private var currentGeneration: [String: String] = [:]
    /// Generations replaced by a newer prompt; their stops are stale.
    private var supersededGenerations: [String: Set<String>] = [:]

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
            if event.hookEventName == .beforeSubmitPrompt, let generation = event.generationId {
                if let previous = currentGeneration[id], previous != generation {
                    supersededGenerations[id, default: []].insert(previous)
                }
                currentGeneration[id] = generation
            }
            table.upsert(id: id, cwd: event.cwd, now: now) { task in
                task.status = .running
                task.currentPhase = nil
                task.waitingMessage = nil
            }

        case .stop:
            // Drop stale stops from a superseded generation (see actor doc).
            if let generation = event.generationId,
               supersededGenerations[id]?.contains(generation) == true {
                IslandLogger.webhook.debug("Cursor: dropping stale stop (superseded generation)")
                break
            }
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
            currentGeneration.removeValue(forKey: id)
            supersededGenerations.removeValue(forKey: id)
        }

        return table.snapshot()
    }
}
