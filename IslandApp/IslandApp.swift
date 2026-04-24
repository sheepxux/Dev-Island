import SwiftUI
import AppKit
import IslandCore

@main
struct IslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // NotchBarWindow / PanelWindow come in Task 1–2.
        // .accessory must be set AFTER makeKeyAndOrderFront on the first window.
        NSApp.setActivationPolicy(.accessory)
    }
}
