import AppKit
import SwiftUI
import IslandCore

/// Borderless NSWindow that hosts the collapsed bar.
///
/// Placed at `.statusBar` level so it sits above the menu bar layer, with
/// `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]` so it persists
/// across Spaces and stays visible in full-screen apps.
///
/// Reads its dimensions from `NotchMetrics.current()` on every reposition,
/// so a screen-parameter change (notch detected/removed, menu bar height
/// change, display swap) is fully self-correcting.
public final class NotchBarWindow: NSWindow {
    private var hostingView: NSHostingView<NotchBarRootView>!
    private(set) var layout: NotchMetrics.Layout = NotchMetrics.current()

    public init() {
        let initialLayout = NotchMetrics.current()
        let size = NSSize(width: initialLayout.totalWidth, height: initialLayout.barHeight)

        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        isMovable = false
        isReleasedWhenClosed = false

        let host = NSHostingView(rootView: NotchBarRootView(layout: initialLayout))
        self.hostingView = host
        contentView = host

        self.layout = initialLayout
        reposition()
    }

    /// Re-measure the active screen and pin the window to the top, centered.
    /// Call from `didChangeScreenParametersNotification` and on launch.
    public func reposition() {
        guard let screen = NSScreen.main else { return }
        let newLayout = NotchMetrics.layout(for: screen)
        layout = newLayout

        // Push the new layout into the SwiftUI tree so the shape switches
        // (notched ⇄ capsule) and dimensions update without a relaunch.
        hostingView.rootView = NotchBarRootView(layout: newLayout)

        let size = NSSize(width: newLayout.totalWidth, height: newLayout.barHeight)
        let frame = screen.frame
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height - newLayout.topMargin
        )
        setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

/// Root SwiftUI view for the bar window. Subscribes to the shared store and
/// derives state + count.
struct NotchBarRootView: View {
    let layout: NotchMetrics.Layout
    @State private var store = TaskStore.shared

    var body: some View {
        NotchBarView(
            state: BarState.derive(from: store.tasks),
            taskCount: store.tasks.filter {
                $0.status == .running || $0.status == .waiting
            }.count,
            layout: layout
        )
    }
}
