import OSLog

/// App-layer unified-log categories.
///
/// Keeping Logger construction in one reviewed file lets CI reject ad-hoc log
/// channels that could bypass the runtime privacy policy.
enum AppLogger {
    private static let subsystem = "app.devisland.Island"

    static let notifier = Logger(subsystem: subsystem, category: "notifier")
    static let window = Logger(subsystem: subsystem, category: "window")
    static let dock = Logger(subsystem: subsystem, category: "dock-visibility")
}
