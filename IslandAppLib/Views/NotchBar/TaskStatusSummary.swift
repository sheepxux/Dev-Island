import IslandCore
import SwiftUI

/// Multi-session snapshot for the collapsed island. The point matrix and
/// title communicate the highest-attention state; the trailing label reports
/// the total number of sessions instead of repeating that state.
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
        var running = 0
        var waiting = 0
        var failed = 0
        var completed = 0
        for task in tasks {
            switch task.status {
            case .running:   running += 1
            case .waiting:   waiting += 1
            case .failed:    failed += 1
            case .completed: completed += 1
            }
        }
        self.running = running
        self.waiting = waiting
        self.failed = failed
        self.completed = completed
    }

    init(running: Int = 0, waiting: Int = 0, failed: Int = 0, completed: Int = 0) {
        self.running = running
        self.waiting = waiting
        self.failed = failed
        self.completed = completed
    }

    var total: Int { running + waiting + failed + completed }
    func compactLabel(language: DevIslandLanguage = .current) -> String {
        L10n.sessionCount(total, language: language)
    }

    var foregroundSegment: Segment? {
        if waiting > 0 { return .init(status: .waiting, count: waiting) }
        if failed > 0 { return .init(status: .failed, count: failed) }
        if completed > 0 { return .init(status: .completed, count: completed) }
        if running > 0 { return .init(status: .running, count: running) }
        return nil
    }

    var segments: [Segment] { foregroundSegment.map { [$0] } ?? [] }

    func accessibilityLabel(language: DevIslandLanguage = .current) -> String {
        guard total > 0 else {
            return L10n.string("No sessions", language: language)
        }
        var parts: [String] = []
        if waiting > 0 {
            parts.append(L10n.format("%lld waiting", language: language, Int64(waiting)))
        }
        if failed > 0 {
            parts.append(L10n.format("%lld failed", language: language, Int64(failed)))
        }
        if running > 0 {
            parts.append(L10n.format("%lld running", language: language, Int64(running)))
        }
        if completed > 0 {
            parts.append(L10n.format("%lld completed", language: language, Int64(completed)))
        }
        return parts.joined(separator: L10n.string(", ", language: language))
    }
}

struct CompactTaskStatusSummary: View {
    let summary: TaskStatusSummary
    @Environment(\.devIslandLanguage) private var language

    @ViewBuilder
    var body: some View {
        if summary.total > 0 {
            Text(summary.compactLabel(language: language))
                .foregroundStyle(.white.opacity(0.82))
                .font(Typo.barBadge)
                .monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(summary.accessibilityLabel(language: language))
        }
    }
}
