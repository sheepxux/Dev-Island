import AppKit
import SwiftUI

public extension Notification.Name {
    static let islandOpenOnboardingRequested = Notification.Name("island.openOnboardingRequested")
}

/// The Welcome tour's window: since 2026-09-23 a borderless sheet over the
/// screen the island lives on, stopping at the menu bar's lower edge. It
/// floats above ordinary windows but below the menu bar and the island, so
/// the tutorial can hang its plate under the real island and the real
/// menu-bar item while the desktop ghosts through a light wash. The
/// menu-bar band is left alone: macOS 26 draws the menu bar transparently
/// over whatever sits beneath it, and a light window there washed the
/// menu-bar icons away (2026-09-24).
public final class OnboardingWindow: NSWindow {
    public static let completionKey = "island.didCompleteFirstLaunch"

    /// Live anchors the canvas follows; AppDelegate keeps them current.
    public let anchors: WelcomeTutorialAnchors

    private let finishHandler: (_ requestsNotificationAuthorization: Bool) -> Void
    private var hasRequestedFinish = false

    /// A borderless tour still needs to become key so toggles, Return and
    /// Escape work exactly like native window controls.
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    public init(
        screen: NSScreen,
        anchors: WelcomeTutorialAnchors,
        onFinish: @escaping (_ requestsNotificationAuthorization: Bool) -> Void
    ) {
        self.anchors = anchors
        self.finishHandler = onFinish
        super.init(
            contentRect: anchors.stageFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        title = L10n.string("Welcome to Dev Island")
        appearance = NSAppearance(named: .aqua)
        isMovable = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isReleasedWhenClosed = false
        // Above the user's windows, below the menu bar (`.mainMenu`) and the
        // island (`.statusBar`), which stay visible and clickable.
        level = .floating
        collectionBehavior = [.fullScreenAuxiliary, .stationary]
        contentView = NSHostingView(
            rootView: LocalizedAppRoot {
                WelcomeTutorialCanvas(anchors: anchors) { [weak self] requestsAuthorization in
                    self?.requestFinish(
                        requestsNotificationAuthorization: requestsAuthorization
                    )
                }
            }
        )
        setFrame(anchors.stageFrame, display: false)
    }

    /// Route Command-W through the same semantic close path as the custom X
    /// and Escape shortcut. The tour remains borderless, but still behaves
    /// like a conventional key window once the app is in regular mode.
    public override func performClose(_ sender: Any?) {
        requestFinish(requestsNotificationAuthorization: false)
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
