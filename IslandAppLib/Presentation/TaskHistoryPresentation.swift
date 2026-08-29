import Foundation
import IslandCore

enum TaskHistoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case inProgress = "In Progress"
    case completed = "Completed"
    case failed = "Failed"

    var id: Self { self }

    func label(language: DevIslandLanguage = .current) -> String {
        L10n.string(rawValue, language: language)
    }
}

enum TaskHistoryPresentation {
    static func filtered(
        _ tasks: [AgentTask],
        query: String,
        filter: TaskHistoryFilter
    ) -> [AgentTask] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return tasks.filter { task in
            let matchesFilter: Bool = switch filter {
            case .all:
                true
            case .inProgress:
                task.status == .running || task.status == .waiting
            case .completed:
                task.status == .completed
            case .failed:
                task.status == .failed
            }
            guard matchesFilter else { return false }
            guard !needle.isEmpty else { return true }
            return task.title.lowercased().contains(needle)
                || sourceName(task.source).lowercased().contains(needle)
        }
    }

    static func sourceName(_ source: String) -> String {
        if source == "manus" { return "Manus" }
        if let descriptor = LocalAgentRegistry.descriptor(for: source) {
            return descriptor.displayName
        }
        return source
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    static func statusLabel(
        for task: AgentTask,
        isLive: Bool,
        language: DevIslandLanguage = .current
    ) -> String {
        let key: String
        switch task.status {
        case .running:
            key = isLive ? "Running now" : "Last seen running"
        case .waiting:
            key = isLive ? "Waiting now" : "Last seen waiting"
        case .completed:
            key = "Completed"
        case .failed:
            key = "Failed"
        }
        return L10n.string(key, language: language)
    }

    /// Compact, deterministic relative time that follows Dev Island's own
    /// language setting instead of macOS's global locale.
    static func relativeAgeLabel(
        for date: Date,
        relativeTo now: Date,
        language: DevIslandLanguage = .current
    ) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case 0..<10:
            return L10n.string("just now", language: language)
        case 10..<60:
            return L10n.format("%llds ago", language: language, Int64(seconds))
        case 60..<3_600:
            return L10n.format("%lldm ago", language: language, Int64(seconds / 60))
        case 3_600..<86_400:
            return L10n.format("%lldh ago", language: language, Int64(seconds / 3_600))
        default:
            return L10n.format("%lldd ago", language: language, Int64(seconds / 86_400))
        }
    }
}
