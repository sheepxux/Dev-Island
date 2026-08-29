import Foundation

/// Release gate for Manus' current v2 webhook protocol.
///
/// The official protocol is now documented and implemented, including the
/// authenticated public-key endpoint and timestamp-bound signature format.
/// Keep the gate disabled until registration, the signed test delivery,
/// event delivery, and deletion have all passed against a real account. The
/// gate is code-reviewed only: it must never be sourced from UserDefaults or
/// the environment.
public enum ManusRealtimeTrust {
    public static let liveV2AcceptanceComplete = false

    public static let pollingOnlyReason =
        "Secure realtime unavailable; checking every minute"
}
