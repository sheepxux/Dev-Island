import Foundation

/// One task status transition, delivered through `TaskStore.onTaskTransition`
/// (contract v1.4.0, J1). B side maps these to user notifications.
public struct TaskTransition: Sendable {
    /// The task *after* the transition.
    public let task: AgentTask
    /// Status before the transition; `nil` means the task appeared for the
    /// first time (B should usually not notify on these — startup snapshots
    /// would spam).
    public let oldStatus: TaskStatus?
    /// Same as `task.status`, duplicated for ergonomic `switch`ing.
    public let newStatus: TaskStatus

    public init(task: AgentTask, oldStatus: TaskStatus?, newStatus: TaskStatus) {
        self.task = task
        self.oldStatus = oldStatus
        self.newStatus = newStatus
    }
}

extension TaskTransition {
    /// Diff two task lists into the transitions the contract promises:
    /// one per task whose status changed, `oldStatus == nil` for newly
    /// appeared tasks, nothing for removals. Order follows `new`.
    ///
    /// Tasks are keyed by (source, id) — session ids are only unique per
    /// source (the same CLI session-id string can legally exist on two
    /// different connectors).
    static func diff(old: [AgentTask], new: [AgentTask]) -> [TaskTransition] {
        var oldStatuses: [String: TaskStatus] = [:]
        for task in old {
            oldStatuses["\(task.source)#\(task.id)"] = task.status
        }
        return new.compactMap { task in
            let oldStatus = oldStatuses["\(task.source)#\(task.id)"]
            guard oldStatus != task.status else { return nil }
            return TaskTransition(task: task, oldStatus: oldStatus, newStatus: task.status)
        }
    }
}
