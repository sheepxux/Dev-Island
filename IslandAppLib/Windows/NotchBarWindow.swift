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
        // Window is sized to hover-expanded dimensions PLUS shadow padding
        // around so the SwiftUI .shadow on hover renders without clipping.
        // Idle bar anchors to top of the inner area; the empty space is
        // where the bar expands and where the shadow falls.
        let hover = layout.hovered()
        let pad = NotchMetrics.shadowPadding
        return NSSize(
            width: hover.totalWidth + 2 * pad,
            height: hover.barHeight + pad      // pad only at bottom
        )
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
        // Both modes anchor to TOP so the bar hangs flush with the screen
        // edge — matching the real MacBook hardware notch on notched
        // displays and giving the no-notch fake notch the same flush-top
        // silhouette. Hover grows the bar downward (and wider).
        NotchBarView(
            state: BarState.derive(from: store.tasks),
            taskCount: activeCount,
            layout: displayLayout,
            // Notched bar always shows status. Synthetic notch shows it
            // only on hover for a cleaner idle silhouette.
            showsContent: baseLayout.hasNotch || isHovering
        )
        .contentShape(barHitShape)
        .onHover(perform: handleHover)
        // Subtle ambient shadow on hover — soft, diffuse, no directional
        // offset so there's no visible edge between the bar bottom and the
        // shadow. Two stacked layers: a tight close shadow + a wide ambient
        // glow, mimicking real-world soft lighting.
        .shadow(
            color: .black.opacity(isHovering ? 0.18 : 0),
            radius: isHovering ? 6 : 0,
            x: 0,
            y: isHovering ? 2 : 0
        )
        .shadow(
            color: .black.opacity(isHovering ? 0.12 : 0),
            radius: isHovering ? 22 : 0,
            x: 0,
            y: isHovering ? 4 : 0
        )
        .frame(
            width: baseLayout.hovered().totalWidth + 2 * NotchMetrics.shadowPadding,
            height: baseLayout.hovered().barHeight + NotchMetrics.shadowPadding,
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
            return AnyShape(UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: 0,
                    bottomLeading: NotchMetrics.cornerRadius,
                    bottomTrailing: NotchMetrics.cornerRadius,
                    topTrailing: 0
                ),
                style: .continuous
            ))
        }
    }

    private var activeCount: Int {
        store.tasks.filter { $0.status == .running || $0.status == .waiting }.count
    }
}
