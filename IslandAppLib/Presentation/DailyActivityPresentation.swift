import Foundation
import IslandCore

/// One calm line about today: "Today: 14 sessions · 3 approvals · 2h 10m of
/// agent time". Numbers only — no project, session, or agent names — so the
/// same string is safe in the status menu and the idle panel.
enum DailyActivityPresentation {
    /// `nil` when nothing happened yet, so surfaces can simply omit the row.
    static func summaryLine(
        _ summary: DailyActivitySummary?,
        language: DevIslandLanguage = .current
    ) -> String? {
        guard let summary, !summary.isEmpty else { return nil }

        var parts = [L10n.sessionCount(summary.sessionCount, language: language)]
        if summary.approvalCount > 0 {
            parts.append(L10n.format(
                summary.approvalCount == 1 ? "%lld approval" : "%lld approvals",
                language: language,
                Int64(summary.approvalCount)
            ))
        }
        parts.append(agentTime(summary.activeSeconds, language: language))

        let joined = parts.dropFirst().reduce(parts[0]) { partial, next in
            L10n.format("%@ · %@", language: language, partial, next)
        }
        return L10n.format("Today: %@", language: language, joined)
    }

    static func agentTime(
        _ seconds: TimeInterval,
        language: DevIslandLanguage = .current
    ) -> String {
        let totalMinutes = Int(max(0, seconds) / 60)
        guard totalMinutes >= 1 else {
            return L10n.string("under a minute of agent time", language: language)
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 {
            return L10n.format("%lldm of agent time", language: language, Int64(minutes))
        }
        return L10n.format(
            "%lldh %lldm of agent time",
            language: language,
            Int64(hours),
            Int64(minutes)
        )
    }
}
