import Foundation
import IslandCore

/// A deliberately low-cardinality support report.
///
/// It contains enough environment and aggregate state to diagnose common
/// launch/connection problems, but never accepts or emits task titles, task
/// IDs, prompts, URLs, project paths, hook payloads, or API-key material.
enum SupportDiagnostics {
    static func report(
        appVersion: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "unknown",
        appBuild: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "unknown",
        operatingSystem: String = ProcessInfo.processInfo.operatingSystemVersionString,
        architecture: String = currentArchitecture,
        generatedAt: Date = .now,
        connectionStatus: ConnectionStatus,
        apiKeyStatus: APIKeyStatus,
        tasks: [AgentTask],
        localHookServiceStatus: LocalHookServiceStatus = .listening,
        localAgentHooks: LocalAgentHookHealthSnapshot = .init(agents: []),
        previousLaunchState: PreviousLaunchState = .firstLaunch,
        consecutiveStartupInterruptions: Int = 0
    ) -> String {
        let statusCounts = Dictionary(grouping: tasks, by: \AgentTask.status)
            .mapValues(\.count)
        let sourceCounts = safeSourceCounts(tasks)
        let previousLaunch = previousLaunchLabel(
            previousLaunchState,
            consecutiveStartupInterruptions: consecutiveStartupInterruptions
        )

        var lines = [
            "Dev Island Diagnostics",
            "Generated: \(ISO8601DateFormatter().string(from: generatedAt))",
            "Version: \(appVersion) (\(appBuild))",
            "macOS: \(operatingSystem)",
            "Architecture: \(architecture)",
            "Manus API: \(apiKeyLabel(apiKeyStatus))",
            "Connection: \(connectionLabel(connectionStatus))",
            "Local Agent Listener: \(localHookServiceLabel(localHookServiceStatus))",
            "Local Agent Hooks: \(localAgentHooks.connectedCount) connected, \(localAgentHooks.configuredCount) configured, \(localAgentHooks.updateRequiredCount) update required, \(localAgentHooks.disconnectedCount) disconnected",
            "Previous Launch: \(previousLaunch)",
            "Sessions: \(tasks.count)",
            "- waiting: \(statusCounts[.waiting, default: 0])",
            "- failed: \(statusCounts[.failed, default: 0])",
            "- completed: \(statusCounts[.completed, default: 0])",
            "- running: \(statusCounts[.running, default: 0])",
        ]

        if !sourceCounts.isEmpty {
            lines.append("Agents:")
            for item in sourceCounts {
                lines.append("- \(item.name): \(item.count)")
            }
        }

        if !localAgentHooks.agents.isEmpty {
            lines.append("Hook Connections:")
            for agent in localAgentHooks.agents {
                lines.append("- \(agent.displayName): \(hookConnectionLabel(agent.state))")
            }
        }

        lines.append("Privacy: aggregate state only; no keys, paths, prompts, titles, URLs, or session IDs.")
        return lines.joined(separator: "\n")
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private static func apiKeyLabel(_ status: APIKeyStatus) -> String {
        switch status {
        case .notConfigured: return "not configured"
        case .valid: return "configured"
        case .invalid: return "invalid"
        }
    }

    private static func connectionLabel(_ status: ConnectionStatus) -> String {
        switch status {
        case .connected: return "connected"
        case .disconnected: return "disconnected"
        case .reconnecting: return "reconnecting"
        case .degraded: return "degraded"
        }
    }

    private static func localHookServiceLabel(_ status: LocalHookServiceStatus) -> String {
        switch status {
        case .starting:
            return "starting"
        case .listening:
            return "ready"
        case .retrying(let attempt, let limit):
            return "retrying (\(attempt)/\(limit))"
        case .unavailable:
            return "unavailable"
        case .stopped:
            return "stopped"
        }
    }

    private static func previousLaunchLabel(
        _ state: PreviousLaunchState,
        consecutiveStartupInterruptions: Int
    ) -> String {
        switch state {
        case .firstLaunch:
            return "first launch or no prior record"
        case .ready:
            return "startup ready recorded"
        case .startupInterrupted:
            let boundedCount = min(
                max(consecutiveStartupInterruptions, 1),
                LaunchHealthTracker.maximumConsecutiveStartupInterruptions
            )
            return "startup readiness not reached (\(boundedCount) consecutive; capped at 3)"
        case .legacyUnknown:
            return "legacy shutdown record was ambiguous"
        }
    }

    private static func hookConnectionLabel(_ state: LocalAgentHookConnectionState) -> String {
        switch state {
        case .connected: return "connected"
        case .configured: return "configured; confirm in agent"
        case .updateRequired: return "update required"
        case .disconnected: return "not connected"
        }
    }

    private static func safeSourceCounts(_ tasks: [AgentTask]) -> [(name: String, count: Int)] {
        var knownNames = ["manus": "Manus"]
        for descriptor in LocalAgentRegistry.all {
            knownNames[descriptor.source] = descriptor.displayName
        }
        let grouped = Dictionary(grouping: tasks) { task in
            knownNames[task.source] ?? "Other"
        }
        return grouped
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
    }
}
