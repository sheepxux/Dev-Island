import Foundation
import IslandCore

/// Privacy-safe, localized copy for the optional Manus connection row.
///
/// `ConnectionStatus.degraded(reason:)` is a Core diagnostic boundary. Keep
/// arbitrary reasons out of the UI and expose only the three product states a
/// user can act on: verified realtime, secure polling-only fallback, or a
/// connection failure that needs an explicit retry.
enum ManusConnectionStatusPresentation {
    static func message(
        apiKeyStatus: APIKeyStatus,
        connectionStatus: ConnectionStatus,
        language: DevIslandLanguage = .current
    ) -> String {
        let key: String
        switch apiKeyStatus {
        case .notConfigured:
            key = "Not connected — paste an API key below"
        case .invalid:
            key = "Stored key is invalid"
        case .valid:
            switch connectionStatus {
            case .connected:
                key = "Verified realtime + polling fallback"
            case .reconnecting:
                key = "Reconnecting…"
            case .disconnected:
                key = "Disconnected"
            case .degraded(let reason):
                if reason == ManusRealtimeTrust.pollingOnlyReason {
                    key = "Polling only — checking every minute"
                } else if reason == ManusCredentialRemovalPolicy.cleanupPendingReason {
                    key = "Remote callback cleanup pending — retry Disconnect"
                } else {
                    key = "Connection unavailable — reconnect to retry"
                }
            }
        }
        return L10n.string(key, language: language)
    }
}
