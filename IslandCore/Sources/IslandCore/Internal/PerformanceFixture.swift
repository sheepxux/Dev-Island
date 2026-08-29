#if DEV_ISLAND_PERFORMANCE_QA
import Foundation

/// Hermetic task fixtures compiled only into dedicated performance-QA builds.
/// They keep measurements away from the user's SQLite database, Keychain,
/// local Hook port, Manus account, and notification preferences.
public enum PerformanceFixture {
    public enum Scenario: String, Sendable {
        case idle
        case compactRunning20 = "compact-running-20"
        case expandedRunning20 = "expanded-running-20"
        case expandedMixed20 = "expanded-mixed-20"
        case transitionRunning20 = "transition-running-20"
    }

    public static let scenario: Scenario = {
        let raw = ProcessInfo.processInfo.environment["DEV_ISLAND_PERFORMANCE_SCENARIO"]
        return raw.flatMap(Scenario.init(rawValue:)) ?? .idle
    }()

    public static var shouldExpand: Bool {
        switch scenario {
        case .idle, .compactRunning20, .transitionRunning20:
            return false
        case .expandedRunning20, .expandedMixed20:
            return true
        }
    }

    /// Repeated bar-to-panel morphs are isolated to the dedicated QA binary.
    /// The interval leaves each 300 ms silhouette transition fully settled
    /// before the next edge begins, while still producing enough samples for
    /// a one-minute Animation Hitches recording.
    public static var transitionInterval: TimeInterval? {
        scenario == .transitionRunning20 ? 0.8 : nil
    }

    public static let transitionInitialDelay: TimeInterval = 1.0

    public static func makeTasks(now: Date = .now) -> [AgentTask] {
        switch scenario {
        case .idle:
            return []
        case .compactRunning20, .expandedRunning20, .transitionRunning20:
            return (0..<20).map { makeTask(index: $0, status: .running, now: now) }
        case .expandedMixed20:
            return (0..<20).map { index in
                let status: TaskStatus
                switch index {
                case 0..<3: status = .waiting
                case 3..<5: status = .failed
                case 5..<8: status = .completed
                default: status = .running
                }
                return makeTask(index: index, status: status, now: now)
            }
        }
    }

    private static func makeTask(index: Int, status: TaskStatus, now: Date) -> AgentTask {
        let sources = ["claude-code", "codex", "cursor", "manus"]
        let phase: String?
        switch status {
        case .running: phase = "Running deterministic QA workload"
        case .waiting: phase = "Needs input"
        case .completed: phase = nil
        case .failed: phase = "Fixture failure"
        }

        return AgentTask(
            id: String(format: "perf-%02d", index + 1),
            source: sources[index % sources.count],
            title: "Performance session \(index + 1)",
            status: status,
            currentPhase: phase,
            createdAt: now.addingTimeInterval(TimeInterval(-900 - index * 11)),
            updatedAt: now.addingTimeInterval(TimeInterval(-index)),
            taskURL: "https://example.invalid/dev-island-performance/\(index + 1)",
            waitingMessage: status == .waiting ? "Fixture needs a deterministic answer" : nil
        )
    }
}
#endif
