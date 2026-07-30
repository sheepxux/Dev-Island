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
    private var openSettingsObserver: NSObjectProtocol?

    /// Lazily-created so we don't pay the SwiftUI view-construction cost
    /// until the user actually opens settings. Re-used across opens —
    /// the second gear tap brings the same window forward instead of
    /// stacking a new one.
    private var settingsWindow: SettingsWindow?

    /// Conventional menu-bar icon (`NSStatusItem`): visible whenever the
    /// app — and therefore the local hook backend — is running. Menu
    /// carries live status lines plus panel/settings/quit shortcuts.
    private var statusItemController: StatusItemController?

    /// NSEvent monitors that are alive only while the panel is expanded.
    /// Global monitors fire for events going to OTHER apps (so clicks on
    /// the desktop / Finder / another app trigger collapse), and the
    /// keyDown global monitor catches Esc regardless of which app is key.
    /// Cleared on every collapse so we don't leak handlers.
    private var panelEventMonitors: [Any] = []

    #if DEBUG
    /// In-app sandbox for driving the island without Manus (CLAUDE_CLIENT.md
    /// §6 task 10). Only ever instantiated in DEBUG builds.
    private var debugSandboxWindow: DebugSandboxWindow?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = IslandWindow()
        window.makeKeyAndOrderFront(nil)
        self.islandWindow = window

        // §6 task-1 gotcha: setActivationPolicy(.accessory) must come AFTER
        // makeKeyAndOrderFront on the first window, otherwise nothing shows.
        NSApp.setActivationPolicy(.accessory)

        #if DEBUG
        // Open the Debug Sandbox alongside the island so every dev launch
        // has live controls without any extra step. Release builds skip
        // this entire block (and don't link the sandbox types at all).
        let sandbox = DebugSandboxWindow(onReposition: { [weak self] in
            self?.islandWindow?.reposition()
        })
        sandbox.orderFront(nil)
        self.debugSandboxWindow = sandbox
        #endif

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

        // Settings window plumbing. Panel's gear button posts this
        // notification (defined in IslandAppLib's SettingsWindow.swift);
        // we lazily create / focus the window here so the SwiftUI side
        // stays free of AppKit window references.
        openSettingsObserver = NotificationCenter.default.addObserver(
            forName: .islandOpenSettingsRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.openSettings()
        }

        // Banner notifications for task state transitions
        // (running → completed, * → waiting). Owns its own
        // UNUserNotificationCenter delegate + observation re-arming
        // loop; we just kick it off once.
        TaskNotifier.shared.start()

        // Conventional status-bar presence: icon visible = backend running.
        statusItemController = StatusItemController()

        // Open with the panel expanded so a fresh launch lands the user
        // somewhere actionable (see the task list, reach the gear) instead
        // of a bare capsule they may not notice. Delayed one runloop-ish
        // beat so IslandWindow has finished pinning to the notch before
        // the morph animation runs.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            IslandCoordinator.shared.expand()
        }

        // True first launch (no settings ever saved): also open Settings —
        // the panel is empty until at least one agent is connected, and
        // Settings is where connectors get set up.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "island.didCompleteFirstLaunch") {
            defaults.set(true, forKey: "island.didCompleteFirstLaunch")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.openSettings()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = openSettingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        removePanelEventMonitors()
    }

    // MARK: - Settings

    private func openSettings() {
        if let existing = settingsWindow {
            existing.bringToFront()
            return
        }
        let window = SettingsWindow()
        settingsWindow = window
        window.bringToFront()
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
