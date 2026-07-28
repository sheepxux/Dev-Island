import Foundation

/// Shared session bookkeeping for local CLI connectors (Claude Code, Codex).
///
/// Each connector decodes its own hook payloads and translates them into
/// mutations on this table; the table owns the generic concerns — task
/// creation, TTL pruning, and stable snapshot ordering.
struct LocalSessionTable {
    /// Finished sessions linger briefly so the user sees the green state,
    /// then get pruned. Sessions that stop emitting events entirely (e.g.
    /// the CLI crashed before its SessionEnd fired) are dropped after a day.
    static let finishedTTL: TimeInterval = 2 * 60 * 60
    static let staleTTL: TimeInterval = 24 * 60 * 60

    let source: String
    /// Human-readable fallback for the task title when `cwd` is missing.
    let displayName: String
    private var sessions: [String: AgentTask] = [:]

    init(source: String, displayName: String) {
        self.source = source
        self.displayName = displayName
    }

    /// Create-or-update the session task, then apply `mutate`.
    mutating func upsert(id: String, cwd: String?, now: Date, mutate: (inout AgentTask) -> Void) {
        var task = sessions[id] ?? newTask(id: id, cwd: cwd, now: now)
        mutate(&task)
        task.updatedAt = now
        sessions[id] = task
    }

    mutating func remove(id: String) {
        sessions.removeValue(forKey: id)
    }

    mutating func prune(now: Date) {
        sessions = sessions.filter { _, task in
            let age = now.timeIntervalSince(task.updatedAt)
            switch task.status {
            case .completed, .failed: return age < Self.finishedTTL
            case .running, .waiting:  return age < Self.staleTTL
            }
        }
    }

    func snapshot() -> [AgentTask] {
        sessions.values.sorted { $0.createdAt < $1.createdAt }
    }

    func contains(id: String) -> Bool {
        sessions[id] != nil
    }

    private func newTask(id: String, cwd: String?, now: Date) -> AgentTask {
        let projectURL = cwd.map { URL(fileURLWithPath: $0, isDirectory: true) }
        return AgentTask(
            id: id,
            source: source,
            title: projectURL?.lastPathComponent ?? "\(displayName) session",
            status: .running,
            createdAt: now,
            updatedAt: now,
            taskURL: projectURL?.absoluteString ?? ""
        )
    }
}
