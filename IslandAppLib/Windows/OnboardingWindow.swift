import AppKit
import SwiftUI

public extension Notification.Name {
    static let islandOpenOnboardingRequested = Notification.Name("island.openOnboardingRequested")
}

public final class OnboardingWindow: NSWindow {
    public static let completionKey = "island.didCompleteFirstLaunch"

    public init(onFinish: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        title = "Welcome to Dev Island"
        isReleasedWhenClosed = false
        level = .normal
        collectionBehavior = [.fullScreenAuxiliary]
        contentView = NSHostingView(rootView: OnboardingView(onFinish: onFinish))
        center()
    }

    public func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}
