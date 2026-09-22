import Foundation
import IslandCore

/// Copy for the "connected but not reporting" state: the vendor is working,
/// the island is blank, and the user needs one concrete next step.
struct LocalAgentReportingNotice: Equatable {
    let source: String
    let title: String
    let hint: String

    var accessibilityLabel: String { "\(title) \(hint)" }
}

enum LocalAgentReportingPresentation {
    /// The first Agent that is not reporting, Codex first because its trust
    /// gate is the common cause. `nil` when every connected Agent is fine.
    static func notice(
        _ snapshot: LocalAgentReportingSnapshot?,
        visibleTaskSources: Set<String> = [],
        language: DevIslandLanguage = .current
    ) -> LocalAgentReportingNotice? {
        guard let snapshot else { return nil }
        let candidates = snapshot.notReporting.filter {
            !visibleTaskSources.contains($0.source)
        }.sorted { lhs, rhs in
            if lhs.source == "codex" { return true }
            if rhs.source == "codex" { return false }
            return lhs.displayName < rhs.displayName
        }
        guard let agent = candidates.first else { return nil }
        return LocalAgentReportingNotice(
            source: agent.source,
            title: L10n.format(
                "No recent hook events from %@",
                language: language,
                agent.displayName
            ),
            hint: hint(for: agent, language: language)
        )
    }

    static func hint(
        for agent: LocalAgentReportingHealth,
        language: DevIslandLanguage
    ) -> String {
        if agent.source == "codex" {
            return L10n.string(
                "Local activity was detected. Check task monitoring and approval authorization separately.",
                language: language
            )
        }
        return L10n.string("Local activity was detected. Check whether this connection can send events.", language: language)
    }
}
