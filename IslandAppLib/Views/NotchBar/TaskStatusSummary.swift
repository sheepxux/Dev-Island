import IslandCore
import SwiftUI

/// Compact multi-session snapshot for the collapsed island. Active states are
/// shown together (waiting, failed, running); completed is shown only when no
/// task is active, keeping the capsule useful without turning it into a row of
/// counters.
struct TaskStatusSummary: Equatable {
    struct Segment: Equatable, Identifiable {
        let status: TaskStatus
        let count: Int

        var id: String { status.rawValue }
    }

    let running: Int
    let waiting: Int
    let failed: Int
    let completed: Int

    init(tasks: [AgentTask]) {
        running = tasks.count(where: { $0.status == .running })
        waiting = tasks.count(where: { $0.status == .waiting })
        failed = tasks.count(where: { $0.status == .failed })
        completed = tasks.count(where: { $0.status == .completed })
    }

    init(running: Int = 0, waiting: Int = 0, failed: Int = 0, completed: Int = 0) {
        self.running = running
        self.waiting = waiting
        self.failed = failed
        self.completed = completed
    }

    var total: Int { running + waiting + failed + completed }

    var segments: [Segment] {
        var active: [Segment] = []
        if waiting > 0 { active.append(.init(status: .waiting, count: waiting)) }
        if failed > 0 { active.append(.init(status: .failed, count: failed)) }
        if running > 0 { active.append(.init(status: .running, count: running)) }
        if !active.isEmpty { return active }
        if completed > 0 { return [.init(status: .completed, count: completed)] }
        return []
    }

    var accessibilityLabel: String {
        guard total > 0 else { return "No tasks" }
        var parts: [String] = []
        if waiting > 0 { parts.append("\(waiting) waiting") }
        if failed > 0 { parts.append("\(failed) failed") }
        if running > 0 { parts.append("\(running) running") }
        if completed > 0 { parts.append("\(completed) completed") }
        return parts.joined(separator: ", ")
    }
}

struct CompactTaskStatusSummary: View {
    let summary: TaskStatusSummary

    var body: some View {
        HStack(spacing: 7) {
            if summary.segments.isEmpty {
                Text("0")
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                ForEach(summary.segments) { segment in
                    HStack(spacing: 3) {
                        Text("\(segment.count)")
                            .foregroundStyle(.white.opacity(0.9))
                        Image(systemName: symbol(for: segment.status))
                            .foregroundStyle(segment.status.color)
                    }
                }
            }
        }
        .font(Typo.barBadge)
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityLabel)
    }

    private func symbol(for status: TaskStatus) -> String {
        switch status {
        case .running:   return "play.fill"
        case .waiting:   return "pause.fill"
        case .failed:    return "exclamationmark"
        case .completed: return "checkmark"
        }
    }
}
