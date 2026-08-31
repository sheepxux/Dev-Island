import Foundation
import IslandCore

/// One privacy-safe summary for the tiny connection mark in the island
/// header. Manus and the local Hook listener are independent transports, so
/// neither one may be presented as the health of every Agent connection.
struct AgentConnectionIndicatorSnapshot: Equatable {
    enum State: Equatable {
        case available
        case transitioning
        case needsAttention
        case inactive
    }

    let state: State
    let help: String
    let accessibilityLabel: String
    let accessibilityValue: String
}

enum AgentConnectionIndicatorPresentation {
    static func snapshot(
        localAgentStatus: LocalHookServiceStatus,
        apiKeyStatus: APIKeyStatus,
        manusStatus: ConnectionStatus,
        language: DevIslandLanguage = .current
    ) -> AgentConnectionIndicatorSnapshot {
        let localAgents = StatusMenuPresentation.localAgents(
            localAgentStatus,
            language: language
        )
        let manus = StatusMenuPresentation.manus(
            apiKeyStatus: apiKeyStatus,
            connectionStatus: manusStatus,
            language: language
        )
        let value = [localAgents, manus].joined(
            separator: L10n.string(", ", language: language)
        )

        return AgentConnectionIndicatorSnapshot(
            state: state(
                localAgentStatus: localAgentStatus,
                apiKeyStatus: apiKeyStatus,
                manusStatus: manusStatus
            ),
            help: value,
            accessibilityLabel: L10n.string(
                "Agent connections",
                language: language
            ),
            accessibilityValue: value
        )
    }

    private enum ChannelState {
        case available
        case transitioning
        case needsAttention
        case inactive
    }

    private static func state(
        localAgentStatus: LocalHookServiceStatus,
        apiKeyStatus: APIKeyStatus,
        manusStatus: ConnectionStatus
    ) -> AgentConnectionIndicatorSnapshot.State {
        let channels = [
            localState(localAgentStatus),
            manusState(apiKeyStatus: apiKeyStatus, status: manusStatus),
        ]

        if channels.contains(where: { $0 == .needsAttention }) {
            return .needsAttention
        }
        if channels.contains(where: { $0 == .transitioning }) {
            return .transitioning
        }
        if channels.contains(where: { $0 == .available }) {
            return .available
        }
        return .inactive
    }

    private static func localState(
        _ status: LocalHookServiceStatus
    ) -> ChannelState {
        switch status {
        case .listening:
            return .available
        case .starting, .retrying:
            return .transitioning
        case .unavailable:
            return .needsAttention
        case .stopped:
            return .inactive
        }
    }

    private static func manusState(
        apiKeyStatus: APIKeyStatus,
        status: ConnectionStatus
    ) -> ChannelState {
        switch apiKeyStatus {
        case .notConfigured:
            return .inactive
        case .invalid:
            return .needsAttention
        case .valid:
            break
        }

        switch status {
        case .connected:
            return .available
        case .reconnecting:
            return .transitioning
        case .degraded, .disconnected:
            return .needsAttention
        }
    }
}
