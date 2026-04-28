import AppKit
import SwiftUI
import IslandCore

/// Single borderless NSWindow that hosts both bar and panel modes via
/// `IslandRootView`. Sized to the LARGEST possible visible state (panel
/// width + shadow padding × panel height) so the SwiftUI shape inside can
/// freely morph without triggering an NSWindow frame animation (which is
/// jankier than SwiftUI's own spring).
///
/// Replaces the prior `NotchBarWindow` + `PanelWindow` pair so the
/// transition between collapsed and expanded is a single shape morph
/// instead of a two-window cross-fade.
public final class IslandWindow: NSWindow {
    private var hostingView: NSHostingView<IslandRootView>!
    public private(set) var layout: NotchMetrics.Layout = NotchMetrics.current()

    /// Outer container size: panel max width + shadow padding on each side,
    /// panel max height + shadow padding at bottom. Constants chosen so the
    /// inside SwiftUI shape never touches the window's edges.
    private static let containerWidth: CGFloat  = NotchMetrics.panelMaxWidth + 2 * NotchMetrics.shadowPadding
    private static let containerHeight: CGFloat = 380 + NotchMetrics.shadowPadding

    public init() {
        let initialLayout = NotchMetrics.current()

        super.init(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(width: Self.containerWidth, height: Self.containerHeight)
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        // Start with no shadow — idle bar matches the original Apple notch
        // (flat, embedded). The SwiftUI root view toggles `hasShadow` on
        // hover or expand for the affordance-shadow effect.
        hasShadow = false
        // `.screenSaver` (1000), not `.statusBar` (25). On macOS 26 the
        // system menu bar's own translucent overlay sits above .statusBar
        // and ends up covering the bar's content frame at idle (it only
        // peeks through during a SwiftUI redraw, which is why content
        // briefly flashes during animations). .screenSaver is far above
        // any normal system overlay, guaranteeing the island always
        // renders on top.
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none

        let host = NSHostingView(
            rootView: IslandRootView(
                baseLayout: initialLayout,
                onShouldShowShadowChanged: { [weak self] enabled in
                    self?.setShadow(enabled)
                }
            )
        )
        self.hostingView = host
        contentView = host

        layout = initialLayout
        reposition()
    }

    /// Toggle the system-rendered window shadow. Forced recompute via
    /// `invalidateShadow()` so the shadow follows the morphing alpha
    /// silhouette without a stale cached version showing through.
    fileprivate func setShadow(_ enabled: Bool) {
        guard hasShadow != enabled else { return }
        hasShadow = enabled
        invalidateShadow()
    }

    /// Re-measure the active screen and pin the window. The window itself
    /// stays at `containerWidth × containerHeight`; only its position
    /// changes here. The morph happens inside SwiftUI.
    public func reposition() {
        guard let screen = NSScreen.main else { return }
        let newLayout = NotchMetrics.layout(for: screen)
        layout = newLayout
        hostingView.rootView = IslandRootView(
            baseLayout: newLayout,
            onShouldShowShadowChanged: { [weak self] enabled in
                self?.setShadow(enabled)
            }
        )

        let frame = screen.frame
        let origin = NSPoint(
            x: frame.midX - Self.containerWidth / 2,
            // Anchor TOP edge of window at the screen's top edge so the
            // shape inside (which top-anchors itself) hugs the menu bar.
            y: frame.maxY - Self.containerHeight
        )
        setFrame(NSRect(origin: origin, size: NSSize(width: Self.containerWidth, height: Self.containerHeight)),
                 display: true)
    }
}
