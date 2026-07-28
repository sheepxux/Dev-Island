import Foundation

enum StateReconciler {

    /// Merge a remote polling snapshot into local state, touching only tasks
    /// of the given source. Tasks from other sources (e.g. local "claude-code"
    /// sessions during a Manus poll) pass through untouched — a remote
    /// snapshot is only authoritative for its own source.
    static func reconcile(local: [AgentTask], incoming: [AgentTask], source: String) -> [AgentTask] {
        let scoped = local.filter { $0.source == source }
        let others = local.filter { $0.source != source }
        return reconcile(local: scoped, incoming: incoming) + others
    }

    /// Merge a remote polling snapshot into local state.
    /// Remote is authoritative: tasks present only locally are dropped.
    /// For tasks present in both, take the version with the later updatedAt.
    static func reconcile(local: [AgentTask], incoming: [AgentTask]) -> [AgentTask] {
        var localById = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        var result: [AgentTask] = []

        for remote in incoming {
            if let localTask = localById[remote.id] {
                result.append(localTask.updatedAt >= remote.updatedAt ? localTask : remote)
            } else {
                result.append(remote)
            }
            localById.removeValue(forKey: remote.id)
        }
        // Tasks remaining in localById are not in the remote snapshot — drop them.
        return result
    }

    /// Apply a single webhook event to the current task list.
    static func apply(event: WebhookPayload, to tasks: [AgentTask]) -> [AgentTask] {
        switch event.data {
        case .created(let d):
            // Avoid duplicates
            guard !tasks.contains(where: { $0.id == d.taskId }) else { return tasks }
            let task = AgentTask(
                id: d.taskId,
                source: "manus",
                title: d.taskTitle,
                status: .running,
                createdAt: Date.now,
                updatedAt: Date.now,
                taskURL: d.taskUrl
            )
            return tasks + [task]

        case .progress(let d):
            return tasks.map { task in
                guard task.id == d.taskId else { return task }
                var updated = task
                updated.currentPhase   = d.progressType
                updated.waitingMessage = d.progressType.lowercased() == "waiting" ? d.message : nil
                updated.status         = d.progressType.lowercased() == "waiting" ? .waiting : .running
                updated.updatedAt      = Date.now
                return updated
            }

        case .stopped(let d):
            return tasks.map { task in
                guard task.id == d.taskId else { return task }
                var updated = task
                updated.status    = d.stopReason == .finish ? .completed : .waiting
                updated.updatedAt = Date.now
                return updated
            }
        }
    }
}
