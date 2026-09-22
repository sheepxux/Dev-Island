import Foundation
import IslandCore

/// Pure formatting and scheduling policy for the expanded panel's one-second
/// labels. Keeping this outside SwiftUI lets row-local clocks stay tiny and
/// gives duration/countdown semantics deterministic regression coverage.
enum PanelClockPresentation {
    static func taskTimingLabel(
        for task: AgentTask,
        at now: Date,
        language: DevIslandLanguage
    ) -> String {
        guard task.source == "codex" else {
            return taskDuration(for: task, at: now)
        }
        // Codex task identity spans turns. Its creation date is the session's
        // origin, so this must never look like the current turn's stopwatch.
        let elapsed = max(0, Int(now.timeIntervalSince(task.createdAt)))
        if elapsed >= 86_400 {
            return L10n.format("Session · %lldd", language: language, Int64(elapsed / 86_400))
        }
        if elapsed >= 3_600 {
            return L10n.format("Session · %lldh", language: language, Int64(elapsed / 3_600))
        }
        return L10n.format("Session · %lldm", language: language, Int64(elapsed / 60))
    }

    static func taskNeedsLiveTick(_ status: TaskStatus) -> Bool {
        switch status {
        case .running, .waiting:
            return true
        case .completed, .failed:
            return false
        }
    }

    static func taskDuration(
        for task: AgentTask,
        at now: Date
    ) -> String {
        let referenceDate = taskNeedsLiveTick(task.status) ? now : task.updatedAt
        let elapsed = max(0, Int(referenceDate.timeIntervalSince(task.createdAt)))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        if minutes >= 60 {
            return String(
                format: "%d:%02d:%02d",
                minutes / 60,
                minutes % 60,
                seconds
            )
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func requestCountdown(
        expiresAt: Date,
        at now: Date
    ) -> String {
        let remaining = max(0, Int(ceil(expiresAt.timeIntervalSince(now))))
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }
}
