import AppKit
import SwiftUI
import IslandCore
import Observation

/// Cross-module signal that the Settings window should open. The panel's
/// gear button posts this, AppDelegate observes it. NotificationCenter
/// is the lightest-weight way to bridge a SwiftUI view → NSApplication-
/// owned window without threading a coordinator reference through the
/// view tree.
public extension Notification.Name {
    static let islandOpenSettingsRequested = Notification.Name("island.openSettingsRequested")
}

@Observable
final class SettingsPresentation {
    var showsHistory = false
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
    private let presentation = SettingsPresentation()

    public init(onDidClose: @escaping @MainActor () -> Void = {}) {
        self.onDidClose = onDidClose
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        title = "Dev Island"
        // Windows are the icon's beige outer tile; the island keeps the black
        // inner tile. The sidebar pane runs under the transparent title bar,
        // so the content view reserves room for the traffic lights itself.
        appearance = NSAppearance(named: .aqua)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        backgroundColor = NSColor(
            srgbRed: 0xEF / 255,
            green: 0xEB / 255,
            blue: 0xE2 / 255,
            alpha: 1
        )
        isReleasedWhenClosed = false
        // .normal level so the user can put other windows on top while
        // they're working — settings is configuration, not a HUD.
        level = .normal
        // Settings is not a Dynamic-Island-class window; it doesn't
        // need to follow the user across Spaces. Default behaviors.
        collectionBehavior = [.fullScreenAuxiliary]

        let host = NSHostingView(
            rootView: LocalizedAppRoot {
                SettingsView(presentation: presentation)
            }
        )
        host.translatesAutoresizingMaskIntoConstraints = true
        contentView = host

        // Center on the active screen the first time it's shown.
        center()
    }

    /// Bring the window forward and make it the key window. Use this
    /// from gear-tap so a second tap on an already-open settings window
    /// just refocuses it instead of stacking.
    public func bringToFront(showHistory: Bool = false) {
        if showHistory { presentation.showsHistory = true }
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
