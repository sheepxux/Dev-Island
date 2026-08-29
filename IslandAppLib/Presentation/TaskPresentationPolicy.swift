import Foundation
import IslandCore

/// One attention-first policy shared by the compact island and expanded
/// session list. A task that needs the user must never be displaced by
/// background work, and a fresh result should surface before ongoing work.
///
/// Priority: needs attention > failed > completed > running.
enum TaskPresentationPolicy {
    /// A completion may briefly lead concurrent work so the result is seen,
    /// then yields back to live sessions. The completed row itself remains
    /// available until connector TTL pruning and in Session History.
    static let recentResultDuration: TimeInterval = 15

    static func rank(for status: TaskStatus) -> Int {
        switch status {
        case .waiting:   return 0
        case .failed:    return 1
        case .completed: return 2
        case .running:   return 3
        }
    }

    static func primaryTask(
        in tasks: [AgentTask],
        pendingActionRequests: [AgentActionRequest] = [],
        now: Date = .now
    ) -> AgentTask? {
        ordered(
            tasks,
            pendingActionRequests: pendingActionRequests,
            now: now
        ).first
    }

    /// Status groups are attention ordered. Waiting sessions that own an
    /// interactive request follow the request queue's arrival order; the
    /// remaining Waiting and Running sessions retain creation order so routine
    /// progress updates do not make the panel reshuffle. Terminal results use
    /// their transition timestamp because they no longer emit live progress.
    static func ordered(
        _ tasks: [AgentTask],
        pendingActionRequests: [AgentActionRequest] = [],
        now: Date = .now
    ) -> [AgentTask] {
        let queuedAttentionOrder = attentionOrder(
            from: pendingActionRequests
        )

        return tasks.sorted { lhs, rhs in
            let lhsRank = presentationRank(for: lhs, now: now)
            let rhsRank = presentationRank(for: rhs, now: now)
            if lhsRank != rhsRank { return lhsRank < rhsRank }

            if lhs.status == .waiting {
                let lhsQueueIndex = queuedAttentionOrder[lhs.identity]
                let rhsQueueIndex = queuedAttentionOrder[rhs.identity]
                switch (lhsQueueIndex, rhsQueueIndex) {
                case let (.some(lhsIndex), .some(rhsIndex)) where lhsIndex != rhsIndex:
                    return lhsIndex < rhsIndex
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                default:
                    break
                }
            }

            if lhs.status != .running,
               lhs.status != .waiting,
               lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            if lhs.source != rhs.source { return lhs.source < rhs.source }
            return lhs.id < rhs.id
        }
    }

    /// `TaskStore.pendingActionRequests` is append-only until a request is
    /// resolved. Preserve the first position for each session so a second
    /// queued question cannot move that session or displace an older request.
    private static func attentionOrder(
        from requests: [AgentActionRequest]
    ) -> [TaskIdentity: Int] {
        var result: [TaskIdentity: Int] = [:]
        for (index, request) in requests.enumerated()
            where result[request.taskIdentity] == nil {
            result[request.taskIdentity] = index
        }
        return result
    }

    private static func presentationRank(
        for task: AgentTask,
        now: Date
    ) -> Int {
        guard task.status == .completed else { return rank(for: task.status) }
        let age = now.timeIntervalSince(task.updatedAt)
        return age <= recentResultDuration ? 2 : 4
    }
}
