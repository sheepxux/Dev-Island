import Foundation
import IslandCore

/// One privacy-preserving textual snapshot shared by the menu, tooltip and
/// status-button accessibility value. It deliberately contains no task title,
/// session identifier, path, tool input or provider-authored error text.
struct StatusMenuSnapshot: Equatable {
    let overview: String
    let localAgents: String
    let manus: String

    let language: DevIslandLanguage

    var accessibilityValue: String {
        [overview, localAgents, manus].joined(
            separator: L10n.string(", ", language: language)
        )
    }
}

/// Low-noise, low-cardinality copy for the conventional macOS status menu.
///
/// The menu is a health surface, not a second session list. It deliberately
/// avoids task titles, session IDs, paths, raw errors, and a static dump of
/// every supported Agent name.
enum StatusMenuPresentation {
    static func snapshot(
        tasks: [AgentTask],
        localAgentStatus: LocalHookServiceStatus,
        apiKeyStatus: APIKeyStatus,
        connectionStatus: ConnectionStatus,
        now: Date = .now,
        language: DevIslandLanguage = .current
    ) -> StatusMenuSnapshot {
        StatusMenuSnapshot(
            overview: overview(tasks: tasks, now: now, language: language),
            localAgents: localAgents(localAgentStatus, language: language),
            manus: manus(
                apiKeyStatus: apiKeyStatus,
                connectionStatus: connectionStatus,
                language: language
            ),
            language: language
        )
    }

    /// Attention-first headline plus the total session population. The
    /// compact island already follows this model; carrying it into the menu
    /// avoids the ambiguous impression that only the foreground status count
    /// is the complete number of sessions.
    static func overview(
        tasks: [AgentTask],
        now: Date = .now,
        language: DevIslandLanguage = .current
    ) -> String {
        let headline = headline(tasks: tasks, now: now, language: language)
        guard !tasks.isEmpty else { return headline }

        let totalKey = tasks.count == 1
            ? "%lld session total"
            : "%lld sessions total"
        let total = L10n.format(totalKey, language: language, Int64(tasks.count))
        return L10n.format("%@ · %@", language: language, headline, total)
    }

    /// Exact one-shot refresh edge for temporary recent-completion priority.
    /// Returning `nil` lets the controller remain fully event-driven when no
    /// visible state is due to change merely because time passes.
    static func nextRefreshDate(
        tasks: [AgentTask],
        now: Date = .now
    ) -> Date? {
        tasks.compactMap { task -> Date? in
            guard task.status == .completed else { return nil }
            let expiry = task.updatedAt.addingTimeInterval(
                TaskPresentationPolicy.recentResultDuration
            )
            return expiry > now ? expiry : nil
        }.min()
    }

    static func headline(
        tasks: [AgentTask],
        now: Date = .now,
        language: DevIslandLanguage = .current
    ) -> String {
        guard let primary = TaskPresentationPolicy.primaryTask(
            in: tasks,
            now: now
        ) else {
            return L10n.string("Dev Island is running", language: language)
        }

        let count = tasks.count(where: { $0.status == primary.status })
        let key: String
        switch primary.status {
        case .waiting:
            key = count == 1 ? "%lld session needs attention" : "%lld sessions need attention"
        case .failed:
            key = count == 1 ? "%lld session needs review" : "%lld sessions need review"
        case .completed:
            key = count == 1 ? "%lld session completed" : "%lld sessions completed"
        case .running:
            key = count == 1 ? "%lld session running" : "%lld sessions running"
        }
        return L10n.format(key, language: language, Int64(count))
    }

    static func localAgents(
        _ status: LocalHookServiceStatus,
        language: DevIslandLanguage = .current
    ) -> String {
        let key: String
        switch status {
        case .starting:
            key = "Local agents: Starting…"
        case .listening:
            key = "Local agents: Ready"
        case .retrying(let attempt, let limit):
            return L10n.format(
                "Local agents: Reconnecting (%lld/%lld)",
                language: language,
                Int64(attempt),
                Int64(limit)
            )
        case .unavailable:
            key = "Local agents: Offline"
        case .stopped:
            key = "Local agents: Stopped"
        }
        return L10n.string(key, language: language)
    }

    static func manus(
        apiKeyStatus: APIKeyStatus,
        connectionStatus: ConnectionStatus,
        language: DevIslandLanguage = .current
    ) -> String {
        let key: String
        switch apiKeyStatus {
        case .notConfigured:
            return L10n.string("Manus: Not connected", language: language)
        case .invalid:
            return L10n.string("Manus: Reconnect required", language: language)
        case .valid:
            break
        }

        switch connectionStatus {
        case .connected:
            key = "Manus: Connected"
        case .reconnecting:
            key = "Manus: Reconnecting…"
        case .degraded:
            // Raw reasons belong in the dedicated connection surface. The
            // menu stays stable and cannot expose an unexpected provider or
            // transport string.
            key = "Manus: Polling only"
        case .disconnected:
            key = "Manus: Disconnected"
        }
        return L10n.string(key, language: language)
    }

    static func updateHelp(
        status: AppUpdateStatus,
        canCheckForUpdates: Bool,
        language: DevIslandLanguage = .current
    ) -> String? {
        guard !canCheckForUpdates else { return nil }
        let key: String
        switch status {
        case .unavailable:
            key = "Available in signed release builds."
        case .starting:
            key = "Update service is starting."
        case .ready:
            key = "The updater is preparing another check."
        case .checking:
            key = "Checking for updates…"
        case .failed:
            key = "Update service couldn't start. Restart Dev Island to try again."
        }
        return L10n.string(key, language: language)
    }
}
