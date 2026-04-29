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
    /// Custom NSHostingView subclass that filters hit-tests to the
    /// silhouette area so clicks on the otherwise-transparent ~408pt
    /// window don't get swallowed across the upper-middle of the screen.
    private var hostingView: ClickThroughHostingView<IslandRootView>!
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
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none

        let host = ClickThroughHostingView(
            rootView: IslandRootView(
                baseLayout: initialLayout,
                containerWidth: Self.containerWidth,
                onShouldShowShadowChanged: { [weak self] enabled in
                    self?.setShadow(enabled)
                },
                onSilhouetteRectChanged: { [weak self] rect in
                    self?.hostingView.visibleRegion = rect
                }
            )
        )
        // Seed `visibleRegion` BEFORE setting contentView so the very
        // first hitTest after the window appears already filters
        // correctly. The SwiftUI .onChange(initial: true) callback can
        // race with `self.hostingView` not being set yet, and after
        // that `.onChange` only fires on actual silhouette changes —
        // so without this seed line, visibleRegion stays nil forever
        // and the whole 408pt window keeps swallowing clicks.
        host.visibleRegion = Self.idleSilhouetteRect(for: initialLayout)
        self.hostingView = host
        contentView = host

        layout = initialLayout
        reposition()
    }

    /// Silhouette bounding rect for the COLLAPSED, NOT-HOVERED state —
    /// used as the seed value for `visibleRegion` until SwiftUI's
    /// `onSilhouetteRectChanged` callback takes over for hover/mode
    /// transitions. Mirrors the same math `IslandRootView.silhouetteRect`
    /// uses (container-centered, glued to top).
    private static func idleSilhouetteRect(for layout: NotchMetrics.Layout) -> CGRect {
        let w = layout.totalWidth
        let h = layout.barHeight
        return CGRect(
            x: (containerWidth - w) / 2,
            y: 0,
            width: w,
            height: h
        )
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
            containerWidth: Self.containerWidth,
            onShouldShowShadowChanged: { [weak self] enabled in
                self?.setShadow(enabled)
            },
            onSilhouetteRectChanged: { [weak self] rect in
                self?.hostingView.visibleRegion = rect
            }
        )
        // Same seeding rationale as in init — re-assigning rootView on
        // an already-mounted NSHostingView does NOT re-trigger
        // .onChange(initial: true), so if `silhouetteRect` happens to
        // be the same as before (typical when the user moves windows
        // around without changing screens), the callback never fires
        // and visibleRegion drifts. Seed it explicitly here too.
        hostingView.visibleRegion = Self.idleSilhouetteRect(for: newLayout)

        let frame = screen.frame
        let origin = NSPoint(
            x: frame.midX - Self.containerWidth / 2,
            // Window's TOP edge sits `topMargin` below the screen's top.
            // Notched: 0 → bar wraps the hardware notch at screen top.
            // Synthetic: menu-bar-height → bar floats just below the
            //   menu bar, in normal drawable area (macOS 26's menu bar
            //   refuses to host arbitrary windows on top of itself).
            y: frame.maxY - Self.containerHeight - newLayout.topMargin
        )
        setFrame(NSRect(origin: origin, size: NSSize(width: Self.containerWidth, height: Self.containerHeight)),
                 display: true)
    }
}
