import AppKit
import SwiftUI
import IslandCore

/// Cross-module signal that the Settings window should open. The panel's
/// gear button posts this, AppDelegate observes it. NotificationCenter
/// is the lightest-weight way to bridge a SwiftUI view → NSApplication-
/// owned window without threading a coordinator reference through the
/// view tree.
public extension Notification.Name {
    static let islandOpenSettingsRequested = Notification.Name("island.openSettingsRequested")
}

/// Standalone titled window hosting `SettingsView` (CLAUDE_CLIENT.md §6
/// task 6). Opened on demand from the panel's gear button. Behaves like
/// any normal app window — draggable, closeable, and represented in the
/// Dock while open. Its owner returns the app to accessory mode after the
/// final conventional window closes; closing Settings never quits the
/// background agent monitor.
public final class SettingsWindow: NSWindow {
    private let onDidClose: @MainActor () -> Void
    private var hasReportedClose = false

    public init(onDidClose: @escaping @MainActor () -> Void = {}) {
        self.onDidClose = onDidClose
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        title = "Dev Island"
        appearance = NSAppearance(named: .darkAqua)
        titlebarAppearsTransparent = true
        backgroundColor = NSColor(
            calibratedRed: 10 / 255,
            green: 10 / 255,
            blue: 9 / 255,
            alpha: 1
        )
        isReleasedWhenClosed = false
        // .normal level so the user can put other windows on top while
        // they're working — settings is configuration, not a HUD.
        level = .normal
        // Settings is not a Dynamic-Island-class window; it doesn't
        // need to follow the user across Spaces. Default behaviors.
        collectionBehavior = [.fullScreenAuxiliary]

        let host = NSHostingView(rootView: SettingsView())
        host.translatesAutoresizingMaskIntoConstraints = true
        contentView = host

        // Center on the active screen the first time it's shown.
        center()
    }

    /// Bring the window forward and make it the key window. Use this
    /// from gear-tap so a second tap on an already-open settings window
    /// just refocuses it instead of stacking.
    public func bringToFront() {
        // AppDelegate acquires the window's Dock lease before this method,
        // so activation always happens after the app becomes `.regular`.
        hasReportedClose = false
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    public override func close() {
        let shouldReport = !hasReportedClose
        super.close()
        guard shouldReport else { return }
        hasReportedClose = true
        onDidClose()
    }
}
