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
/// visible silhouette (the bar's ~28pt vs. the window's allowance for a
/// full-height expanded panel). The empty area is fully transparent, but
/// a transparent NSWindow still intercepts every mouse event in its frame
/// — that means clicks across the upper-middle of the screen get
/// silently swallowed unless we opt out. We do that by tracking the
/// cursor position and toggling `ignoresMouseEvents` based on whether it
/// is inside the silhouette's screen-coords rect. Cursor inside
/// silhouette: window receives events normally (bar is clickable, panel
/// buttons work). Cursor anywhere else (including the transparent area of
/// our own window): events fall through to the app below.
///
/// Tracking is driven by mouse-move monitors, so a boundary crossing takes
/// effect on the very event that caused it, with a low-frequency timer
/// behind them as a safety net.
public final class IslandWindow: NSWindow {
    private var hostingView: NSHostingView<IslandRootView>!
    public private(set) var layout: NotchMetrics.Layout = NotchMetrics.current()

    /// Outer container size: panel max width + shadow padding on each side,
    /// panel max height + shadow padding at bottom. Constants chosen so the
    /// inside SwiftUI shape never touches the window's edges.
    private static let containerWidth: CGFloat  = NotchMetrics.panelMaxWidth + 2 * NotchMetrics.shadowPadding
    private static let containerHeight: CGFloat = NotchMetrics.panelMaxHeight + NotchMetrics.shadowPadding

    /// Poll interval while the cursor is over the silhouette. Fast, because
    /// this is the tick that keeps re-asserting the pointing-hand cursor
    /// against a system that clears it behind our back (see below).
    private static let activeTrackingInterval: TimeInterval = 0.04
    /// Poll interval while the cursor is elsewhere — the overwhelming
    /// majority of the app's lifetime. Boundary crossings are picked up by
    /// the mouse-move monitors, so this is only a safety net for state
    /// changes that arrive without a mouse event (window repositioned under
    /// a stationary cursor, monitor starved during a modal loop).
    private static let idleTrackingInterval: TimeInterval = 0.25

    /// Cached silhouette rect in absolute screen coordinates. Updated
    /// whenever the SwiftUI side reports a new silhouette (mode flip /
    /// hover widen) or whenever the window is repositioned. The
    /// mouse-tracking timer reads this every tick.
    private var silhouetteScreenRect: CGRect = .zero

    private var mouseTrackingTimer: Timer?
    private var mouseMoveMonitors: [Any] = []
    private var mouseTrackingStarted = false
    private var pointerWasInsideSilhouette: Bool?
    /// Interval the live timer was scheduled with, so a tick only pays for
    /// rescheduling when the cursor actually crosses the boundary.
    private var mouseTrackingInterval: TimeInterval = IslandWindow.idleTrackingInterval

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
        // Start with no shadow — the compact island stays flat and embedded.
        // The SwiftUI root enables it only for the expanded panel lifecycle.
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

        // Must precede any cursor writes from the poll below — without it
        // macOS discards NSCursor.set() from non-active apps entirely
        // (the hand only flashed during clicks, never on hover).
        BackgroundCursor.enable()
        startMouseTracking()
    }

    deinit {
        mouseTrackingTimer?.invalidate()
        for monitor in mouseMoveMonitors {
            NSEvent.removeMonitor(monitor)
        }
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

        // A phase completion can grow the accepted region under a stationary
        // pointer. Reconcile immediately so the first click never waits for
        // the 250ms idle safety timer and falls through to the app below.
        if mouseTrackingStarted {
            tickMouseTracking(forceCollapseReconciliation: true)
        }
    }

    private func startMouseTracking() {
        installMouseMoveMonitors()
        scheduleMouseTrackingTimer(interval: Self.idleTrackingInterval)
        mouseTrackingStarted = true
        tickMouseTracking(forceCollapseReconciliation: true)
    }

    /// Mouse-move monitors make boundary crossings synchronous with the
    /// event that caused them. On a timer alone, `ignoresMouseEvents`
    /// lagged the cursor by up to one interval, so a fast move-then-click
    /// landed while the window was still click-through and the first click
    /// on the bar went silently to the app underneath.
    ///
    /// Mouse events need no accessibility authorization (unlike keyDown),
    /// so this works without prompting. The global monitor covers the
    /// normal case where another app is active; the local one covers our
    /// own (Settings open, notification click).
    private func installMouseMoveMonitors() {
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
        ]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            self?.tickMouseTracking()
        }) {
            mouseMoveMonitors.append(global)
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.tickMouseTracking()
            return event
        }) {
            mouseMoveMonitors.append(local)
        }
    }

    private func scheduleMouseTrackingTimer(interval: TimeInterval) {
        mouseTrackingTimer?.invalidate()
        mouseTrackingInterval = interval
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tickMouseTracking()
        }
        // Run during scrolling / dragging too — without .common mode the
        // timer pauses while the user is actively moving the cursor in
        // certain UI contexts.
        RunLoop.main.add(timer, forMode: .common)
        mouseTrackingTimer = timer
    }

    private func tickMouseTracking(forceCollapseReconciliation: Bool = false) {
        // Skip work until we have a real silhouette to compare against.
        guard silhouetteScreenRect.width > 0, silhouetteScreenRect.height > 0 else { return }
        let cursor = NSEvent.mouseLocation  // already screen coords (bottom-left)
        let inside = silhouetteScreenRect.contains(cursor)
        let crossedBoundary = pointerWasInsideSilhouette != inside
        pointerWasInsideSilhouette = inside
        let shouldIgnore = !inside
        if ignoresMouseEvents != shouldIgnore {
            ignoresMouseEvents = shouldIgnore
        }

        // Spin fast only while the cursor is on the silhouette — that's the
        // only time the cursor re-assert below has anything to do. Away
        // from the island (nearly always) a quarter-second safety net is
        // enough, because the move monitors own the transitions.
        let wantedInterval = inside ? Self.activeTrackingInterval : Self.idleTrackingInterval
        if wantedInterval != mouseTrackingInterval {
            scheduleMouseTrackingTimer(interval: wantedInterval)
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

        // Direct-click opens are already armed. Reconcile on real boundary
        // crossings and whenever a newly published phase rect changes under
        // a stationary pointer; repeated outside mouse moves do not reset the
        // grace-period timer.
        if crossedBoundary || forceCollapseReconciliation {
            reconcileAutomaticCollapse(pointerInside: inside)
        }
    }

    private func reconcileAutomaticCollapse(pointerInside: Bool) {
        let coordinator = IslandCoordinator.shared
        guard coordinator.mode == .expanded,
              coordinator.automaticCollapseArmed else { return }
        if pointerInside {
            coordinator.cancelCollapse()
        } else {
            coordinator.scheduleCollapse()
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
