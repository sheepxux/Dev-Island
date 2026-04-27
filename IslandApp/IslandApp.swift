import SwiftUI
import AppKit
import IslandAppLib
import IslandCore

@main
struct IslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings scene is intentionally empty for v1's PoC — the real UI
        // lives in custom NSWindows owned by AppDelegate. Task 6 builds out
        // the SettingsWindow.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var islandWindow: IslandWindow?
    private var screenChangeObserver: NSObjectProtocol?

    /// NSEvent monitors that are alive only while the panel is expanded.
    /// Global monitors fire for events going to OTHER apps (so clicks on
    /// the desktop / Finder / another app trigger collapse), and the
    /// keyDown global monitor catches Esc regardless of which app is key.
    /// Cleared on every collapse so we don't leak handlers.
    private var panelEventMonitors: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = IslandWindow()
        window.makeKeyAndOrderFront(nil)
        self.islandWindow = window

        // §6 task-1 gotcha: setActivationPolicy(.accessory) must come AFTER
        // makeKeyAndOrderFront on the first window, otherwise nothing shows.
        NSApp.setActivationPolicy(.accessory)

        // Bridge coordinator mode → AppKit-side concerns (event monitors).
        // The visual morph is driven entirely inside `IslandRootView` via
        // SwiftUI's withAnimation; AppDelegate no longer touches alpha.
        IslandCoordinator.shared.onModeChange = { [weak self] mode in
            guard let self else { return }
            switch mode {
            case .collapsed:
                self.removePanelEventMonitors()
            case .expanded:
                self.installPanelEventMonitors()
            }
        }

        // Re-pin the window when displays change (Task 8 multi-screen).
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.islandWindow?.reposition()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        removePanelEventMonitors()
    }

    // MARK: - Panel-only event monitors

    /// Install Esc + click-outside monitors. CLAUDE_CLIENT.md §2 trigger
    /// spec: "点外部 / Esc 收起". Both are global because:
    ///
    /// - IslandWindow doesn't override `canBecomeKey` for keyDown, so
    ///   keyboard events flow to whatever app IS key, and only a global
    ///   monitor sees them there.
    /// - Global monitors only fire for events targeted at OTHER apps —
    ///   clicks on the visible shape itself don't trigger collapse, which
    ///   is the behavior we want.
    private func installPanelEventMonitors() {
        guard panelEventMonitors.isEmpty else { return }

        if let escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
            // 53 = Escape (kVK_Escape).
            if event.keyCode == 53 {
                Task { @MainActor in IslandCoordinator.shared.collapse() }
            }
        }) {
            panelEventMonitors.append(escMonitor)
        }

        if let clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { _ in
                Task { @MainActor in IslandCoordinator.shared.collapse() }
            }
        ) {
            panelEventMonitors.append(clickMonitor)
        }
    }

    private func removePanelEventMonitors() {
        for monitor in panelEventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        panelEventMonitors.removeAll()
    }
}
