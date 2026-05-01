import os

/// Centralized `os.Logger` instances. Subsystem matches the bundle
/// identifier (`app.devisland.Island`) so all our log lines are
/// addressable via `log show --predicate 'subsystem == "app.devisland.Island"'`
/// when diagnosing user-reported issues.
enum IslandLogger {
    private static let subsystem = "app.devisland.Island"

    static let api     = Logger(subsystem: subsystem, category: "api")
    static let webhook = Logger(subsystem: subsystem, category: "webhook")
    static let tunnel  = Logger(subsystem: subsystem, category: "tunnel")
    static let store   = Logger(subsystem: subsystem, category: "store")
    static let sync    = Logger(subsystem: subsystem, category: "sync")
    static let storage = Logger(subsystem: subsystem, category: "storage")
}
