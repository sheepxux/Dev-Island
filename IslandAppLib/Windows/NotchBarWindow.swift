import AppKit
import SwiftUI
import IslandCore

/// Borderless NSWindow that hosts the collapsed bar.
///
/// The window's frame is sized for the **hover-expanded** dimensions so the
/// bar can animate fluidly without any NSWindow frame changes (which are
/// not as smooth as SwiftUI layout animations). The bar itself snaps
/// between idle and hover sizes inside the window via `withAnimation`.
public final class NotchBarWindow: NSWindow {
    private var hostingView: NSHostingView<NotchBarRootView>!
    private(set) var layout: NotchMetrics.Layout = NotchMetrics.current()

    public init() {
        let initialLayout = NotchMetrics.current()
        let containerSize = NotchBarWindow.containerSize(for: initialLayout)

        super.init(
            contentRect: NSRect(origin: .zero, size: containerSize),
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

        let host = NSHostingView(rootView: NotchBarRootView(baseLayout: initialLayout))
        self.hostingView = host
        contentView = host

        self.layout = initialLayout
        reposition()
    }

    /// Re-measure the active screen and pin the window. Window size always
    /// equals the hover-expanded size so the bar can grow/shrink internally.
    public func reposition() {
        guard let screen = NSScreen.main else { return }
        let newLayout = NotchMetrics.layout(for: screen)
        layout = newLayout

        hostingView.rootView = NotchBarRootView(baseLayout: newLayout)

        let containerSize = NotchBarWindow.containerSize(for: newLayout)
        let frame = screen.frame
        let origin = NSPoint(
            x: frame.midX - containerSize.width / 2,
            // Window TOP stays at `screen.maxY - topMargin`; extra hover
            // height extends downward.
            y: frame.maxY - containerSize.height - newLayout.topMargin
        )
        setFrame(NSRect(origin: origin, size: containerSize), display: true)
    }

    private static func containerSize(for layout: NotchMetrics.Layout) -> NSSize {
        let hover = layout.hovered()
        return NSSize(width: hover.totalWidth, height: hover.barHeight)
    }
}

/// Root SwiftUI view for the bar window. Holds hover state and animates
/// between idle ↔ hover layout.
struct NotchBarRootView: View {
    let baseLayout: NotchMetrics.Layout
    @State private var isHovering = false
    @State private var store = TaskStore.shared

    private var displayLayout: NotchMetrics.Layout {
        isHovering ? baseLayout.hovered() : baseLayout
    }

    var body: some View {
        // Outer container = hover-sized window. The bar lives at the top,
        // centered horizontally. Empty space below the idle bar is where
        // the bar grows into on hover.
        VStack(spacing: 0) {
            NotchBarView(
                state: BarState.derive(from: store.tasks),
                taskCount: activeCount,
                layout: displayLayout
            )
            .contentShape(barHitShape)
            .onHover(perform: handleHover)
            Spacer(minLength: 0)
        }
        .frame(
            width: baseLayout.hovered().totalWidth,
            height: baseLayout.hovered().barHeight,
            alignment: .top
        )
    }

    // MARK: - Hover handling

    private func handleHover(_ hovering: Bool) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            isHovering = hovering
        }
        if hovering {
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
        }
    }

    /// Restrict hover detection to the actual bar shape (so the cursor
    /// doesn't change while crossing transparent corners).
    private var barHitShape: AnyShape {
        if displayLayout.hasNotch {
            return AnyShape(NotchBarShape(
                notchWidth: displayLayout.notchWidth,
                notchHeight: displayLayout.notchHeight
            ))
        } else {
            return AnyShape(Capsule())
        }
    }

    private var activeCount: Int {
        store.tasks.filter { $0.status == .running || $0.status == .waiting }.count
    }
}
