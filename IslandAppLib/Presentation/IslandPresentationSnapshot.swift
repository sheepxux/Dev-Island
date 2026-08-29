import Foundation
import IslandCore

/// One immutable render input for the root island.
///
/// A SwiftUI body can ask for panel rows, compact state, count and title in
/// the same pass. Keeping those values together prevents each consumer from
/// independently sorting the same session array during a hover, mode or Agent
/// status update.
struct IslandPresentationSnapshot {
    let tasks: [AgentTask]
    let summary: TaskStatusSummary
    let state: BarState
    let primaryTask: AgentTask?

    init(
        tasks: [AgentTask],
        pendingActionRequests: [AgentActionRequest],
        now: Date
    ) {
        let orderedTasks = TaskPresentationPolicy.ordered(
            tasks,
            pendingActionRequests: pendingActionRequests,
            now: now
        )
        self.tasks = orderedTasks
        summary = TaskStatusSummary(tasks: orderedTasks)
        primaryTask = orderedTasks.first
        state = BarState.derive(
            fromPrimaryStatus: orderedTasks.first?.status
        )
    }
}
