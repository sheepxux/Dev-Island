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
    static let maximumSessions = 128
    static let maximumTitleCharacters = 256
    static let maximumTitleBytes = 1_024
    static let maximumTaskURLBytes = 16_384

    let source: String
    /// Human-readable fallback for the task title when `cwd` is missing.
    let displayName: String
    private var sessions: [String: AgentTask] = [:]
    private var arrivalOrder: [String: UInt64] = [:]
    private var nextArrival: UInt64 = 0

    init(source: String, displayName: String) {
        self.source = source
        self.displayName = displayName
    }

    /// Create-or-update the session task, then apply `mutate`.
    mutating func upsert(
        id: String,
        cwd: String?,
        jumpContext: SessionJumpContext?,
        now: Date,
        mutate: (inout AgentTask) -> Void
    ) {
        let isNew = sessions[id] == nil
        var task = sessions[id] ?? newTask(
            id: id,
            cwd: cwd,
            jumpContext: jumpContext,
            now: now
        )
        if let jumpContext {
            task.jumpContext = jumpContext
        }
        mutate(&task)
        task.updatedAt = now
        sessions[id] = task
        if isNew {
            arrivalOrder[id] = nextArrival
            nextArrival &+= 1
        }
        enforceCapacity()
    }

    mutating func remove(id: String) {
        sessions.removeValue(forKey: id)
        arrivalOrder.removeValue(forKey: id)
    }

    mutating func prune(now: Date) {
        sessions = sessions.filter { _, task in
            let age = now.timeIntervalSince(task.updatedAt)
            switch task.status {
            case .completed, .failed: return age < Self.finishedTTL
            case .running, .waiting:  return age < Self.staleTTL
            }
        }
        arrivalOrder = arrivalOrder.filter { sessions[$0.key] != nil }
    }

    func snapshot() -> [AgentTask] {
        sessions.values.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            let lhsArrival = arrivalOrder[lhs.id] ?? 0
            let rhsArrival = arrivalOrder[rhs.id] ?? 0
            if lhsArrival != rhsArrival {
                return lhsArrival < rhsArrival
            }
            return lhs.id < rhs.id
        }
    }

    func contains(id: String) -> Bool {
        sessions[id] != nil
    }

    private func newTask(
        id: String,
        cwd: String?,
        jumpContext: SessionJumpContext?,
        now: Date
    ) -> AgentTask {
        let projectURL = cwd
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            .flatMap { url in
                url.absoluteString.utf8.count <= Self.maximumTaskURLBytes
                    ? url
                    : nil
            }
        let rawTitle = projectURL?.lastPathComponent ?? "\(displayName) session"
        return AgentTask(
            id: id,
            source: source,
            title: AgentActionTextPolicy.bounded(
                rawTitle,
                maximumCharacters: Self.maximumTitleCharacters,
                maximumUTF8Bytes: Self.maximumTitleBytes
            ),
            status: .running,
            createdAt: now,
            updatedAt: now,
            taskURL: projectURL?.absoluteString ?? "",
            jumpContext: jumpContext
        )
    }

    /// Keep the table finite without letting a flood of new sessions evict
    /// earlier user-blocking work. Terminal rows leave first, then the oldest
    /// Running row. If every row is Waiting, the newest arrival loses.
    private mutating func enforceCapacity() {
        while sessions.count > Self.maximumSessions,
              let victim = sessions.values.min(by: isEarlierEvictionCandidate) {
            sessions.removeValue(forKey: victim.id)
            arrivalOrder.removeValue(forKey: victim.id)
        }
    }

    private func isEarlierEvictionCandidate(
        _ lhs: AgentTask,
        _ rhs: AgentTask
    ) -> Bool {
        let lhsRank = evictionRank(lhs.status)
        let rhsRank = evictionRank(rhs.status)
        if lhsRank != rhsRank { return lhsRank < rhsRank }

        let lhsArrival = arrivalOrder[lhs.id] ?? 0
        let rhsArrival = arrivalOrder[rhs.id] ?? 0
        if lhs.status == .waiting {
            if lhsArrival != rhsArrival { return lhsArrival > rhsArrival }
            return lhs.id > rhs.id
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt < rhs.updatedAt
        }
        if lhsArrival != rhsArrival { return lhsArrival < rhsArrival }
        return lhs.id < rhs.id
    }

    private func evictionRank(_ status: TaskStatus) -> Int {
        switch status {
        case .completed, .failed: return 0
        case .running: return 1
        case .waiting: return 2
        }
    }
}
