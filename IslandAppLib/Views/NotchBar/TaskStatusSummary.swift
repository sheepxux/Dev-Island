import IslandCore
import SwiftUI

/// Compact multi-session snapshot for the collapsed island. Only the highest
/// attention tier is presented, keeping the capsule focused on the one thing
/// the user should understand next instead of becoming a row of counters.
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

    var foregroundSegment: Segment? {
        if waiting > 0 { return .init(status: .waiting, count: waiting) }
        if failed > 0 { return .init(status: .failed, count: failed) }
        if completed > 0 { return .init(status: .completed, count: completed) }
        if running > 0 { return .init(status: .running, count: running) }
        return nil
    }

    var segments: [Segment] { foregroundSegment.map { [$0] } ?? [] }

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
        Group {
            if let segment = summary.foregroundSegment {
                HStack(spacing: 4) {
                    Text("\(segment.count)")
                        .foregroundStyle(.white.opacity(0.94))
                    Text(label(for: segment.status))
                        .foregroundStyle(segment.status.color)
                }
            } else {
                Text("0")
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .font(Typo.barBadge)
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityLabel)
    }

    private func label(for status: TaskStatus) -> String {
        switch status {
        case .running:   return "running"
        case .waiting:   return "waiting"
        case .failed:    return "failed"
        case .completed: return "done"
        }
    }
}
