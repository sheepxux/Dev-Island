import AppKit
import SwiftUI

public extension Notification.Name {
    static let islandOpenOnboardingRequested = Notification.Name("island.openOnboardingRequested")
}

public final class OnboardingWindow: NSWindow {
    public static let completionKey = "island.didCompleteFirstLaunch"

    private let finishHandler: (_ requestsNotificationAuthorization: Bool) -> Void
    private var hasRequestedFinish = false

    /// A borderless tour still needs to become key so toggles, Return and
    /// Escape work exactly like native window controls.
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    public init(
        screen: NSScreen? = nil,
        onFinish: @escaping (_ requestsNotificationAuthorization: Bool) -> Void
    ) {
        self.finishHandler = onFinish
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: OnboardingMetrics.width,
                height: OnboardingMetrics.height
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        title = L10n.string("Welcome to Dev Island")
        appearance = NSAppearance(named: .darkAqua)
        isMovable = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false
        level = .normal
        collectionBehavior = [.fullScreenAuxiliary]
        contentView = NSHostingView(
            rootView: LocalizedAppRoot {
                OnboardingView { [weak self] requestsAuthorization in
                    self?.requestFinish(
                        requestsNotificationAuthorization: requestsAuthorization
                    )
                }
            }
        )
        minSize = NSSize(width: OnboardingMetrics.width, height: OnboardingMetrics.height)
        maxSize = NSSize(width: OnboardingMetrics.width, height: OnboardingMetrics.height)
        center(on: screen)
    }

    /// Route Command-W through the same semantic close path as the custom X
    /// and Escape shortcut. The tour remains borderless, but still behaves
    /// like a conventional key window once the app is in regular mode.
    public override func performClose(_ sender: Any?) {
        requestFinish(requestsNotificationAuthorization: false)
    }

    /// Keep the tour on the same display as the island. `NSWindow.center()`
    /// always favors the main display, which feels like a focus jump when the
    /// menu-bar utility is being used on a secondary screen.
    private func center(on preferredScreen: NSScreen?) {
        guard let targetScreen = preferredScreen ?? NSScreen.main else {
            center()
            return
        }
        let visibleFrame = targetScreen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.midY - frame.height / 2
        )
        setFrameOrigin(origin)
    }

    public func bringToFront() {
        let shouldAnimate = !isVisible
        if shouldAnimate { alphaValue = 0 }
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        guard shouldAnimate else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.allowsImplicitAnimation = true
            animator().alphaValue = 1
        }
    }

    public func dismiss(completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.allowsImplicitAnimation = true
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.close()
            self?.alphaValue = 1
            completion()
        }
    }

    private func requestFinish(requestsNotificationAuthorization: Bool) {
        guard !hasRequestedFinish else { return }
        hasRequestedFinish = true
        finishHandler(requestsNotificationAuthorization)
    }
}
