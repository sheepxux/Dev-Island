import AppKit
import SwiftUI
import IslandCore

/// Single borderless NSWindow that hosts both bar and panel modes via
/// `IslandRootView`. Sized to the LARGEST possible visible state (panel
/// width + shadow padding × panel height) so the SwiftUI shape inside can
/// freely morph without triggering an NSWindow frame animation (which is
/// jankier than SwiftUI's own spring).
///
/// **Click-through model.** This window is much taller than the actual
/// visible silhouette (the bar's ~28pt vs. the window's 408pt allowance
/// for the expanded panel). The empty area is fully transparent, but a
/// transparent NSWindow still intercepts every mouse event in its frame
/// — that means clicks across the upper-middle of the screen get
/// silently swallowed unless we opt out. We do that by polling the
/// cursor position via a low-frequency timer and toggling
/// `ignoresMouseEvents` based on whether the cursor is inside the
/// silhouette's screen-coords rect. Cursor inside silhouette: window
/// receives events normally (bar is clickable, panel buttons work).
/// Cursor anywhere else (including the transparent area of our own
/// window): events fall through to the app below.
public final class IslandWindow: NSWindow {
    private var hostingView: NSHostingView<IslandRootView>!
    public private(set) var layout: NotchMetrics.Layout = NotchMetrics.current()

    /// Outer container size: panel max width + shadow padding on each side,
    /// panel max height + shadow padding at bottom. Constants chosen so the
    /// inside SwiftUI shape never touches the window's edges.
    private static let containerWidth: CGFloat  = NotchMetrics.panelMaxWidth + 2 * NotchMetrics.shadowPadding
    private static let containerHeight: CGFloat = 380 + NotchMetrics.shadowPadding

    /// Cursor-tracking poll interval. 40ms ≈ 25 Hz — enough that the bar
    /// "feels" instantly clickable on hover without any visible latency,
    /// cheap enough that the CPU cost is invisible at idle.
    private static let mouseTrackingInterval: TimeInterval = 0.04

    /// Cached silhouette rect in absolute screen coordinates. Updated
    /// whenever the SwiftUI side reports a new silhouette (mode flip /
    /// hover widen) or whenever the window is repositioned. The
    /// mouse-tracking timer reads this every tick.
    private var silhouetteScreenRect: CGRect = .zero

    private var mouseTrackingTimer: Timer?

    /// Whether the poll below last set the pointing-hand cursor. Cursor
    /// writes happen only on transitions, so panel sub-elements (task
    /// cards, buttons) remain free to set their own cursor while expanded.
    private var cursorShowsPointingHand = false

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
        // Default to click-through. The mouse-tracking timer below
        // toggles this back to `false` when the cursor is over the
        // silhouette so the bar / panel respond to clicks normally.
        ignoresMouseEvents = true
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none

        let host = NSHostingView(
            rootView: IslandRootView(
                baseLayout: initialLayout,
                containerWidth: Self.containerWidth,
                onShouldShowShadowChanged: { [weak self] enabled in
                    self?.setShadow(enabled)
                },
                onSilhouetteRectChanged: { [weak self] rect in
                    self?.cacheSilhouetteScreenRect(localRect: rect)
                }
            )
        )
        self.hostingView = host
        contentView = host

        layout = initialLayout
        reposition()

        startMouseTracking()
    }

    deinit {
        mouseTrackingTimer?.invalidate()
    }

    // MARK: - Click-through tracking

    /// Convert a SwiftUI-local silhouette rect (top-left origin, in
    /// content-view coords) to absolute screen coordinates (bottom-left
    /// origin) and cache it for the mouse tracker.
    private func cacheSilhouetteScreenRect(localRect: CGRect) {
        // Top-left → window-local (bottom-left) Y flip.
        let contentH = Self.containerHeight
        let windowLocalY = contentH - localRect.origin.y - localRect.height

        // Window-local → screen by adding the window's frame origin
        // (which is itself in screen coords, bottom-left).
        let origin = self.frame.origin
        silhouetteScreenRect = CGRect(
            x: origin.x + localRect.origin.x,
            y: origin.y + windowLocalY,
            width: localRect.width,
            height: localRect.height
        )
    }

    private func startMouseTracking() {
        mouseTrackingTimer?.invalidate()
        mouseTrackingTimer = Timer.scheduledTimer(
            withTimeInterval: Self.mouseTrackingInterval,
            repeats: true
        ) { [weak self] _ in
            self?.tickMouseTracking()
        }
        // Run during scrolling / dragging too — without .common mode the
        // timer pauses while the user is actively moving the cursor in
        // certain UI contexts.
        if let t = mouseTrackingTimer {
            RunLoop.main.add(t, forMode: .common)
        }
    }

    private func tickMouseTracking() {
        // Skip work until we have a real silhouette to compare against.
        guard silhouetteScreenRect.width > 0, silhouetteScreenRect.height > 0 else { return }
        let cursor = NSEvent.mouseLocation  // already screen coords (bottom-left)
        let inside = silhouetteScreenRect.contains(cursor)
        let shouldIgnore = !inside
        if ignoresMouseEvents != shouldIgnore {
            ignoresMouseEvents = shouldIgnore
        }

        // Pointing-hand affordance for the collapsed bar (the whole bar is
        // one big "open the panel" button). Driven from this poll — the
        // SwiftUI-side NSCursor push/pop was unreliable in this borderless,
        // non-key window (AppKit cursorUpdate kept resetting to arrow, and
        // the pop leg never ran after click-to-expand). Writes fire on
        // transitions only: while expanded, panel sub-elements own the
        // cursor via `.pointingHandCursor()`.
        let wantsHand = inside && IslandCoordinator.shared.mode == .collapsed
        if wantsHand {
            // Re-assert EVERY tick, not just on the transition: as a
            // non-active app our set() can be clobbered whenever the
            // system or the active app touches the cursor, and there's no
            // notification for that. set() is idempotent and cheap at
            // 25Hz, so continuous re-assert is the reliable option.
            NSCursor.pointingHand.set()
            cursorShowsPointingHand = true
        } else if cursorShowsPointingHand {
            cursorShowsPointingHand = false
            NSCursor.arrow.set()
        }
    }

    // MARK: - Window plumbing

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
                self?.cacheSilhouetteScreenRect(localRect: rect)
            }
        )

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

        // Re-compute the cached silhouette in screen coords now that the
        // window has a new origin. Use the idle layout as the seed —
        // SwiftUI's onSilhouetteRectChanged will overwrite it on the next
        // hover / mode change, but the seed makes click-through work
        // immediately at idle without waiting for any animation.
        cacheSilhouetteScreenRect(localRect: idleLocalRect(for: newLayout))
    }

    /// Silhouette rect in CONTENT VIEW local coords (top-left origin) for
    /// the COLLAPSED, NOT-HOVERED state. Mirrors
    /// `IslandRootView.silhouetteRect`'s math.
    private func idleLocalRect(for layout: NotchMetrics.Layout) -> CGRect {
        let w = layout.totalWidth
        let h = layout.barHeight
        return CGRect(
            x: (Self.containerWidth - w) / 2,
            y: 0,
            width: w,
            height: h
        )
    }
}
