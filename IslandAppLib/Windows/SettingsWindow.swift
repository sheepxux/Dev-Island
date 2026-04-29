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
/// any normal app window — draggable, closeable, in the App Switcher
/// while open. Closing the window doesn't quit the app (we're a
/// `.accessory` activation policy).
public final class SettingsWindow: NSWindow {

    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        title = "Island — Settings"
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
        // Switch the app to a regular activation policy briefly so the
        // window can become key with full focus. `.accessory` apps
        // can show key windows but the focus story is finicky;
        // activating ignoringOtherApps is the established pattern.
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}
