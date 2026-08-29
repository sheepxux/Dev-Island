import Logging
import os

/// Centralized `os.Logger` instances. Subsystem matches the bundle
/// identifier (`app.devisland.Island`) so all our log lines are
/// addressable via `log show --predicate 'subsystem == "app.devisland.Island"'`
/// when diagnosing user-reported issues.
enum IslandLogger {
    private static let subsystem = "app.devisland.Island"

    static let api     = os.Logger(subsystem: subsystem, category: "api")
    static let webhook = os.Logger(subsystem: subsystem, category: "webhook")
    static let tunnel  = os.Logger(subsystem: subsystem, category: "tunnel")
    static let store   = os.Logger(subsystem: subsystem, category: "store")
    static let sync    = os.Logger(subsystem: subsystem, category: "sync")
    static let storage = os.Logger(subsystem: subsystem, category: "storage")

    /// The hermetic transport fixture has a closed five-line CLI contract;
    /// Hummingbird startup/cancellation details must not escape on stderr.
    static let silentFramework = Logging.Logger(
        label: "app.devisland.hermetic-listener"
    ) { _ in
        SwiftLogNoOpLogHandler()
    }
}
