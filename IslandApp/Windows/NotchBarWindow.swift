import AppKit
import SwiftUI
import IslandCore

/// Borderless NSWindow that hugs the notch.
///
/// Placed at `.statusBar` level so it sits above the menu bar layer, with
/// `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]` so it persists
/// across Spaces and stays visible in full-screen apps.
final class NotchBarWindow: NSWindow {
    init() {
        let size = NSSize(width: NotchMetrics.totalWidth, height: NotchMetrics.barHeight)
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

        contentView = NSHostingView(rootView: NotchBarRootView())

        reposition()
    }

    /// Pin the window to the top-center of the main display.
    func reposition() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let size = NSSize(width: NotchMetrics.totalWidth, height: NotchMetrics.barHeight)
        // Top of the screen — y origin from bottom-left coordinate space.
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height
        )
        setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

/// Root SwiftUI view for the bar window. Subscribes to the shared store and
/// derives state + count.
private struct NotchBarRootView: View {
    @State private var store = TaskStore.shared

    var body: some View {
        NotchBarView(
            state: BarState.derive(from: store.tasks),
            taskCount: store.tasks.filter {
                $0.status == .running || $0.status == .waiting
            }.count
        )
    }
}
