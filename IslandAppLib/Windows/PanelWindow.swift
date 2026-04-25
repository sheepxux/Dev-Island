import AppKit
import SwiftUI
import IslandCore

/// Borderless NSWindow that hosts the expanded panel.
///
/// Like `NotchBarWindow`: borderless, statusBar level, present across all
/// Spaces and full-screen apps. Sized to its SwiftUI content's intrinsic
/// dimensions so the panel grows and shrinks with the task list.
public final class PanelWindow: NSWindow {
    private var hostingView: NSHostingView<NotchPanelRootView>!
    public private(set) var layout: NotchMetrics.Layout = NotchMetrics.current()

    public init() {
        let initialLayout = NotchMetrics.current()

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 480),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        // System shadow follows the panel's alpha silhouette automatically.
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        isMovable = false
        isReleasedWhenClosed = false

        let host = NSHostingView(rootView: NotchPanelRootView(layout: initialLayout))
        self.hostingView = host
        contentView = host

        layout = initialLayout
        reposition()
    }

    /// Re-measure the active screen and resize/reposition the window so its
    /// top is flush with the screen edge and the panel is centered
    /// horizontally. Call when screen parameters change AND just before
    /// orderFront so the panel always shows at the right intrinsic size
    /// (task count may have changed since last show).
    public func reposition() {
        guard let screen = NSScreen.main else { return }
        let newLayout = NotchMetrics.layout(for: screen)
        layout = newLayout

        hostingView.rootView = NotchPanelRootView(layout: newLayout)
        hostingView.layoutSubtreeIfNeeded()

        let intrinsic = hostingView.fittingSize
        let frame = screen.frame
        let origin = NSPoint(
            x: frame.midX - intrinsic.width / 2,
            // Window TOP flush with screen TOP.
            y: frame.maxY - intrinsic.height
        )
        setFrame(NSRect(origin: origin, size: intrinsic), display: true)
    }
}

/// Root SwiftUI view for the panel window. Subscribes to TaskStore and
/// drives collapse via hover-out.
struct NotchPanelRootView: View {
    let layout: NotchMetrics.Layout
    @State private var store = TaskStore.shared

    var body: some View {
        NotchPanelView(
            tasks: store.tasks,
            connectionStatus: store.connectionStatus,
            layout: layout,
            onTaskTap: { task in
                store.openTaskInBrowser(id: task.id)
                IslandCoordinator.shared.collapse()
            },
            onSettingsTap: {
                // Task 6 wires the Settings window. For now just collapse.
                IslandCoordinator.shared.collapse()
            },
            onConnectTap: {
                // Routes to Settings → Connected Services in Task 6.
                IslandCoordinator.shared.collapse()
            }
        )
        .onHover { hovering in
            if hovering {
                IslandCoordinator.shared.cancelCollapse()
            } else {
                IslandCoordinator.shared.scheduleCollapse()
            }
        }
    }
}
