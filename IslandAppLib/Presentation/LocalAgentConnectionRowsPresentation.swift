import Foundation
import IslandCore

/// Settings › Agent groups every local Agent by what the user has to do about
/// it, not by vendor: connected rows need nothing, rows that need attention
/// carry the page's one primary action, everything else offers "Connect".
enum LocalAgentConnectionGroup: Hashable, CaseIterable {
    case needsAttention
    case connected
    case notConnected
    case preview

    func title(language: DevIslandLanguage) -> String {
        switch self {
        case .connected:      return L10n.string("Setup complete", language: language)
        case .needsAttention: return L10n.string("Needs action", language: language)
        case .notConnected:   return L10n.string("Not connected", language: language)
        case .preview:        return L10n.string("Preview connectors", language: language)
        }
    }
}

/// The trailing control a row shows. Exactly one per row; connected rows
/// expand instead of exposing a destructive button.
enum LocalAgentRowAction: Equatable {
    case expand
    case authorize
    case update
    case connect
}

enum LocalAgentRowPresentation {
    /// `nil` while the first diagnostics pass is still running, so rows can
    /// stay in registry order instead of jumping between groups.
    static func group(for state: LocalAgentHookConnectionState?) -> LocalAgentConnectionGroup? {
        switch state {
        case .connected?:      return .connected
        case .configured?:     return .needsAttention
        case .updateRequired?: return .needsAttention
        case .disconnected?:   return .notConnected
        case nil:              return nil
        }
    }

    static func action(for state: LocalAgentHookConnectionState?) -> LocalAgentRowAction {
        switch state {
        case .connected?:      return .expand
        case .configured?:     return .authorize
        case .updateRequired?: return .update
        case .disconnected?, nil: return .connect
        }
    }

    /// Rows inside one group keep the registry order; groups keep the order
    /// the user should read them in.
    static func grouped(
        _ descriptors: [LocalAgentDescriptor],
        states: [String: LocalAgentHookConnectionState]
    ) -> [(group: LocalAgentConnectionGroup?, descriptors: [LocalAgentDescriptor])] {
        let stable = descriptors.filter { $0.releaseStage == .stable }
        let preview = descriptors.filter { $0.releaseStage == .preview }
        var groups: [(group: LocalAgentConnectionGroup?, descriptors: [LocalAgentDescriptor])] = []
        if stable.allSatisfy({ states[$0.source] != nil }) {
            groups = LocalAgentConnectionGroup.allCases.filter { $0 != .preview }.compactMap { group in
                let members = stable.filter { self.group(for: states[$0.source]) == group }
                return members.isEmpty ? nil : (group, members)
            }
        } else if !stable.isEmpty {
            groups.append((nil, stable))
        }
        if !preview.isEmpty {
            groups.append((.preview, preview))
        }
        return groups
    }

    /// One human sentence per state. Vendor mechanics (Hooks, trust hashes)
    /// stay out of the sentence; the expanded row explains them on request.
    static func statusLine(
        state: LocalAgentHookConnectionState?,
        descriptor: LocalAgentDescriptor,
        language: DevIslandLanguage
    ) -> String {
        if descriptor.releaseStage == .preview, state != nil {
            return L10n.string(
                state == .updateRequired
                    ? "Preview setup needs an update · simulation only"
                    : "Preview connector · simulated requests only",
                language: language
            )
        }
        switch state {
        case nil:
            return L10n.string("Checking…", language: language)
        case .disconnected?:
            return L10n.string(
                "Connect to receive task activity",
                language: language
            )
        case .updateRequired?:
            return L10n.string(
                "Update this connection to keep receiving activity.",
                language: language
            )
        case .configured?:
            return L10n.string(
                "Approval access needs authorization",
                language: language
            )
        case .connected?:
            let capabilities = descriptor.capabilities
            if descriptor.source == "codex" {
                return L10n.string("Approval access authorized", language: language)
            }
            if capabilities.permissionRequests == .bidirectional
                || capabilities.questionRequests == .bidirectional
                || capabilities.planReviews == .bidirectional {
                return L10n.string(
                    "Task and approval access configured",
                    language: language
                )
            }
            if capabilities.permissionRequests == .observeOnly
                || capabilities.questionRequests == .observeOnly
                || capabilities.planReviews == .observeOnly {
                return L10n.string(
                    "Attention monitoring configured · respond in the Agent",
                    language: language
                )
            }
            return L10n.string(
                "Task monitoring configured",
                language: language
            )
        }
    }

    /// Header line: only the counts that are non-zero, in reading order.
    static func summary(
        connected: Int,
        needsAttention: Int,
        notConnected: Int,
        language: DevIslandLanguage
    ) -> String {
        var parts: [String] = []
        if connected > 0 {
            parts.append(L10n.format("%lld set up", language: language, Int64(connected)))
        }
        if needsAttention > 0 {
            parts.append(L10n.format("%lld need action", language: language, Int64(needsAttention)))
        }
        if notConnected > 0 {
            parts.append(L10n.format("%lld not connected", language: language, Int64(notConnected)))
        }
        if parts.isEmpty {
            return L10n.string("Checking local Agents…", language: language)
        }
        return parts.joined(separator: " · ")
    }

    static func summary(
        descriptors: [LocalAgentDescriptor],
        states: [String: LocalAgentHookConnectionState],
        language: DevIslandLanguage
    ) -> String {
        let stable = descriptors.filter { $0.releaseStage == .stable }
        guard stable.allSatisfy({ states[$0.source] != nil }) else {
            return L10n.string("Checking local Agents…", language: language)
        }
        let stableStates = stable.compactMap { states[$0.source] }
        return summary(
            connected: stableStates.filter { $0 == .connected }.count,
            needsAttention: stableStates.filter { $0 == .configured || $0 == .updateRequired }.count,
            notConnected: stableStates.filter { $0 == .disconnected }.count,
            language: language
        )
    }

    static func summary(
        _ snapshot: LocalAgentHookHealthSnapshot,
        language: DevIslandLanguage
    ) -> String {
        summary(
            connected: snapshot.connectedCount,
            needsAttention: snapshot.configuredCount + snapshot.updateRequiredCount,
            notConnected: snapshot.disconnectedCount,
            language: language
        )
    }
}
