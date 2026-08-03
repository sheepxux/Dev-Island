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
/// Generation guard: Cursor dispatches hook processes asynchronously, so
/// events can arrive out of order. Two races are handled:
///
/// 1. A `stop` from an aborted generation arrives *after* the
///    `beforeSubmitPrompt` of the next one and would wrongly paint a
///    running session as "Aborted" → generations explicitly *superseded*
///    by a newer prompt have their late `stop`s dropped.
/// 2. A `stop` outraces its own `beforeSubmitPrompt`; the late prompt
///    would resurrect a finished generation as `.running` → generations
///    that already stopped are remembered and their late prompts ignored.
///
/// Unknown generations always apply — generation IDs aren't ordered, so
/// "not yet superseded" is the only safe staleness signal. Known accepted
/// limitation: two *prompts* delivered in reverse order could mark the
/// newer generation superseded; not guarded because prompt emissions are
/// human-sequenced seconds apart while delivery jitter is milliseconds.
public actor CursorConnector: AgentConnector {
    public let source = "cursor"

    /// Per-session bookkeeping caps so a pathological long-lived session
    /// can't grow memory unboundedly; evicting (unordered) extras only
    /// degrades the guard back to "apply everything", never corrupts state.
    private static let maxTrackedGenerations = 64

    private var table = LocalSessionTable(source: "cursor", displayName: "Cursor")
    /// Latest generation seen per session (from beforeSubmitPrompt).
    private var currentGeneration: [String: String] = [:]
    /// Generations replaced by a newer prompt; their stops are stale.
    private var supersededGenerations: [String: Set<String>] = [:]
    /// Generations that already received a stop; their prompts are stale.
    private var stoppedGenerations: [String: Set<String>] = [:]

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
        pruneBookkeeping()

        guard let id = event.id else { return table.snapshot() }

        switch event.hookEventName {
        case .sessionStart, .beforeSubmitPrompt:
            if event.hookEventName == .beforeSubmitPrompt, let generation = event.generationId {
                // Race 2: this generation already stopped — don't resurrect
                // it as running (its stop outraced this prompt).
                if stoppedGenerations[id]?.contains(generation) == true {
                    IslandLogger.webhook.debug("Cursor: dropping stale prompt (generation already stopped)")
                    break
                }
                if let previous = currentGeneration[id], previous != generation {
                    insertCapped(&supersededGenerations[id, default: []], previous)
                }
                currentGeneration[id] = generation
            }
            table.upsert(id: id, cwd: event.cwd, now: now) { task in
                task.status = .running
                task.currentPhase = nil
                task.waitingMessage = nil
            }

        case .stop:
            if let generation = event.generationId {
                insertCapped(&stoppedGenerations[id, default: []], generation)
                // Race 1: drop stale stops from a superseded generation.
                if supersededGenerations[id]?.contains(generation) == true {
                    IslandLogger.webhook.debug("Cursor: dropping stale stop (superseded generation)")
                    break
                }
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
            stoppedGenerations.removeValue(forKey: id)
        }

        return table.snapshot()
    }

    // MARK: - Bookkeeping hygiene

    /// Drop generation bookkeeping for sessions the table no longer tracks
    /// (TTL-pruned or crashed without a sessionEnd).
    private func pruneBookkeeping() {
        let live = Set(table.snapshot().map(\.id))
        currentGeneration = currentGeneration.filter { live.contains($0.key) }
        supersededGenerations = supersededGenerations.filter { live.contains($0.key) }
        stoppedGenerations = stoppedGenerations.filter { live.contains($0.key) }
    }

    private func insertCapped(_ set: inout Set<String>, _ member: String) {
        set.insert(member)
        while set.count > Self.maxTrackedGenerations {
            set.removeFirst()
        }
    }
}
