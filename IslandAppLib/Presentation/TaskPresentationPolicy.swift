import Foundation
import IslandCore

/// One attention-first policy shared by the compact island and expanded
/// session list. A task that needs the user must never be displaced by
/// background work, and a fresh result should surface before ongoing work.
///
/// Priority: needs attention > failed > completed > running.
enum TaskPresentationPolicy {
    static func rank(for status: TaskStatus) -> Int {
        switch status {
        case .waiting:   return 0
        case .failed:    return 1
        case .completed: return 2
        case .running:   return 3
        }
    }

    static func primaryTask(in tasks: [AgentTask]) -> AgentTask? {
        ordered(tasks).first
    }

    /// Status groups are attention ordered. Within an attention/result group,
    /// the newest event leads its queue. Running sessions retain creation
    /// order so routine progress updates do not make the panel reshuffle.
    static func ordered(_ tasks: [AgentTask]) -> [AgentTask] {
        tasks.sorted { lhs, rhs in
            let lhsRank = rank(for: lhs.status)
            let rhsRank = rank(for: rhs.status)
            if lhsRank != rhsRank { return lhsRank < rhsRank }

            if lhs.status != .running, lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            if lhs.source != rhs.source { return lhs.source < rhs.source }
            return lhs.id < rhs.id
        }
    }
}
