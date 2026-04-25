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
    private var notchBarWindow: NotchBarWindow?
    private var panelWindow: PanelWindow?
    private var screenChangeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bar = NotchBarWindow()
        let panel = PanelWindow()

        bar.makeKeyAndOrderFront(nil)
        // Panel starts hidden — coordinator orderFronts it on expand.
        panel.orderOut(nil)

        self.notchBarWindow = bar
        self.panelWindow = panel

        // §6 task-1 gotcha: setActivationPolicy(.accessory) must come AFTER
        // makeKeyAndOrderFront on the first window, otherwise nothing shows.
        NSApp.setActivationPolicy(.accessory)

        // Bridge coordinator mode → window visibility.
        IslandCoordinator.shared.onModeChange = { [weak self] mode in
            guard
                let bar = self?.notchBarWindow,
                let panel = self?.panelWindow
            else { return }
            switch mode {
            case .collapsed:
                panel.orderOut(nil)
                bar.makeKeyAndOrderFront(nil)
            case .expanded:
                // Re-measure in case the task list changed since last show.
                panel.reposition()
                bar.orderOut(nil)
                panel.makeKeyAndOrderFront(nil)
            }
        }

        // Re-pin both windows when displays change (Task 8 multi-screen).
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.notchBarWindow?.reposition()
            self?.panelWindow?.reposition()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
