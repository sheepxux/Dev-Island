import Foundation

enum StateReconciler {

    /// Merge a remote polling snapshot into local state, touching only tasks
    /// of the given source. Tasks from other sources (e.g. local "claude-code"
    /// sessions during a Manus poll) pass through untouched — a remote
    /// snapshot is only authoritative for its own source.
    static func reconcile(local: [AgentTask], incoming: [AgentTask], source: String) -> [AgentTask] {
        let scoped = local.filter { $0.source == source }
        let others = local.filter { $0.source != source }
        // A connector snapshot is authoritative only for its declared source.
        // Drop a malformed cross-source row instead of letting it inject or
        // evict another Agent's session through this merge boundary.
        let scopedIncoming = normalizedSnapshot(incoming, source: source)
        return reconcile(local: scoped, incoming: scopedIncoming) + others
    }

    /// Keep only rows owned by the connector that produced the snapshot and
    /// coalesce duplicate composite identities before they can reach TaskStore.
    static func normalizedSnapshot(_ incoming: [AgentTask], source: String) -> [AgentTask] {
        coalesced(incoming.filter { $0.source == source })
    }

    /// Merge a remote polling snapshot into local state.
    /// Remote is authoritative: tasks present only locally are dropped.
    /// For tasks present in both, take the version with the later updatedAt.
    static func reconcile(local: [AgentTask], incoming: [AgentTask]) -> [AgentTask] {
        var localByIdentity = Dictionary(
            uniqueKeysWithValues: coalesced(local).map { ($0.identity, $0) }
        )
        var result: [AgentTask] = []

        for remote in coalesced(incoming) {
            if let localTask = localByIdentity[remote.identity] {
                result.append(localTask.updatedAt >= remote.updatedAt ? localTask : remote)
            } else {
                result.append(remote)
            }
            localByIdentity.removeValue(forKey: remote.identity)
        }
        // Tasks remaining in localByIdentity are not in the authoritative
        // snapshot — drop them.
        return result
    }

    /// Apply a single webhook event to the current task list.
    static func apply(event: WebhookPayload, to tasks: [AgentTask]) -> [AgentTask] {
        switch event.data {
        case .created(let d):
            let identity = TaskIdentity(source: "manus", id: d.taskId)
            // Avoid duplicates
            guard !tasks.contains(where: { $0.identity == identity }) else { return tasks }
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

        case .stopped(let d):
            let identity = TaskIdentity(source: "manus", id: d.taskId)
            if let current = tasks.first(where: { $0.identity == identity }) {
                switch current.status {
                case .completed, .failed:
                    // A captured older `ask` event must never pull a terminal
                    // task back into the attention queue. Task IDs are opaque
                    // provider identities and are not reused as new sessions.
                    return tasks
                case .running, .waiting:
                    break
                }
            }
            let status: TaskStatus = d.stopReason == .finish ? .completed : .waiting
            let updatedTasks = tasks.map { task in
                guard task.identity == identity else { return task }
                var updated = task
                updated.title = d.taskTitle
                updated.status = status
                updated.waitingMessage = d.stopReason == .ask ? d.message : nil
                updated.updatedAt = Date.now
                return updated
            }
            guard !tasks.contains(where: { $0.identity == identity }) else {
                return updatedTasks
            }
            return updatedTasks + [AgentTask(
                id: d.taskId,
                source: "manus",
                title: d.taskTitle,
                status: status,
                createdAt: .now,
                updatedAt: .now,
                taskURL: d.taskUrl,
                waitingMessage: d.stopReason == .ask ? d.message : nil
            )]
        }
    }

    /// Provider snapshots should contain one row per composite task identity,
    /// but a malformed or replayed response must not crash
    /// `Dictionary(uniqueKeysWithValues:)` or duplicate UI rows. Preserve the
    /// first-seen order and keep the newest value for each identity.
    private static func coalesced(_ tasks: [AgentTask]) -> [AgentTask] {
        var order: [TaskIdentity] = []
        var newestByIdentity: [TaskIdentity: AgentTask] = [:]

        for task in tasks {
            let identity = task.identity
            if let existing = newestByIdentity[identity] {
                if task.updatedAt > existing.updatedAt {
                    newestByIdentity[identity] = task
                }
            } else {
                order.append(identity)
                newestByIdentity[identity] = task
            }
        }
        return order.compactMap { newestByIdentity[$0] }
    }
}
