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
    private var screenChangeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bar = NotchBarWindow()
        bar.makeKeyAndOrderFront(nil)
        self.notchBarWindow = bar

        // §6 task-1 gotcha: setActivationPolicy(.accessory) must come AFTER
        // makeKeyAndOrderFront, otherwise the window won't display.
        NSApp.setActivationPolicy(.accessory)

        // Re-pin the bar when displays change (Task 8 covers multi-screen).
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.notchBarWindow?.reposition()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
