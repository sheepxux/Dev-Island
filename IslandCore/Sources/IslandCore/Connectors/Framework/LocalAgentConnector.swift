import Foundation

/// The one connector for all local, event-sourced agents.
///
/// State machine over normalized `LocalAgentEvent`s: session bookkeeping
/// lives in `LocalSessionTable`, out-of-order delivery is handled by the
/// generation guard. Per-agent behavior lives entirely in the descriptor's
/// payload mapping — this actor has no agent-specific branches.
///
/// ## Generation guard
///
/// Agents that dispatch hook processes asynchronously (Cursor) can deliver
/// events out of order. Events carrying a `generationId` get two guards:
///
/// 1. A late stop from a generation explicitly *superseded* by a newer
///    prompt is dropped (an aborted turn must not repaint the session that
///    already moved on).
/// 2. A late prompt for a generation that already *stopped* is dropped
///    (a finished generation must not resurrect as running).
///
/// Unknown generations always apply — generation IDs aren't ordered, so
/// "not yet superseded" is the only safe staleness signal. Events without
/// a `generationId` bypass the guard entirely, so agents with synchronous
/// delivery (Claude Code, Codex) get plain apply-everything semantics.
public actor LocalAgentConnector: AgentConnector {

    public static let finishedTTL = LocalSessionTable.finishedTTL
    public static let staleTTL = LocalSessionTable.staleTTL

    /// Per-session bookkeeping caps so a pathological long-lived session
    /// can't grow memory unboundedly; evicting (unordered) extras only
    /// degrades the guard back to "apply everything", never corrupts state.
    private static let maxTrackedGenerations = 64

    public let source: String
    private let displayName: String

    private var table: LocalSessionTable
    /// Latest generation seen per session (from its prompt event).
    private var currentGeneration: [String: String] = [:]
    /// Generations replaced by a newer prompt; their stops are stale.
    private var supersededGenerations: [String: Set<String>] = [:]
    /// Generations that already received a stop; their prompts are stale.
    private var stoppedGenerations: [String: Set<String>] = [:]

    public init(descriptor: LocalAgentDescriptor) {
        self.source = descriptor.source
        self.displayName = descriptor.displayName
        self.table = LocalSessionTable(
            source: descriptor.source,
            displayName: descriptor.displayName
        )
    }

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

    /// Apply one normalized hook event and return the updated snapshot.
    /// `nil` events (undecodable / no session id) still prune the table so
    /// TTL expiry doesn't depend on decodable traffic.
    public func apply(_ event: LocalAgentEvent?, now: Date = .now) -> [AgentTask] {
        table.prune(now: now)
        pruneBookkeeping()

        guard let event else { return table.snapshot() }
        let id = event.sessionId

        switch event.action {
        case .ignored:
            break

        case .running:
            if let generation = event.generationId {
                // Guard 2: this generation already stopped — don't
                // resurrect it (its stop outraced this prompt).
                if stoppedGenerations[id]?.contains(generation) == true {
                    IslandLogger.webhook.debug("\(self.displayName): dropping stale prompt (generation already stopped)")
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

        case .waiting(let phase, let message):
            // No shipped agent emits versioned waiting events today
            // (Claude/Codex carry no generationId, Cursor has no waiting),
            // but the generic guarantee must hold for future descriptors:
            // a waiting event from a known-stale generation is dropped.
            if let generation = event.generationId,
               supersededGenerations[id]?.contains(generation) == true
                || stoppedGenerations[id]?.contains(generation) == true {
                IslandLogger.webhook.debug("\(self.displayName): dropping stale waiting event (finished generation)")
                break
            }
            table.upsert(id: id, cwd: event.cwd, now: now) { task in
                task.status = .waiting
                task.currentPhase = phase
                task.waitingMessage = message
            }

        case .completed(let phase):
            guard stopApplies(id: id, generation: event.generationId) else { break }
            table.upsert(id: id, cwd: event.cwd, now: now) { task in
                task.status = .completed
                task.currentPhase = phase
                task.waitingMessage = nil
            }

        case .failed(let phase):
            guard stopApplies(id: id, generation: event.generationId) else { break }
            table.upsert(id: id, cwd: event.cwd, now: now) { task in
                task.status = .failed
                task.currentPhase = phase
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

    // MARK: - Generation guard

    /// Record the stop and decide whether it may repaint the session.
    /// Guard 1: stops from explicitly superseded generations are stale.
    private func stopApplies(id: String, generation: String?) -> Bool {
        guard let generation else { return true }
        insertCapped(&stoppedGenerations[id, default: []], generation)
        if supersededGenerations[id]?.contains(generation) == true {
            IslandLogger.webhook.debug("\(self.displayName): dropping stale stop (superseded generation)")
            return false
        }
        return true
    }

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
