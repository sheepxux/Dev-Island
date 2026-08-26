import SwiftUI
import IslandCore

/// Unified root view for the bar ⇄ panel morph. Always rendered inside a
/// single `IslandWindow` whose frame is sized to the largest possible
/// state (panel + shadow padding); the visible silhouette is a SINGLE
/// `NotchPanelShape` whose width / height / corner radius are bound to
/// `IslandCoordinator.shared.mode` (and a local `isHovering` state). When
/// the coordinator flips mode it does so inside `withAnimation(.spring)`,
/// so SwiftUI interpolates every dependent value — the same mechanism
/// that makes the bar's hover-widen feel buttery.
///
/// One shape morphing == no cross-fade between two windows. Bar content
/// (status dot + count) and panel content (header / list / footer) are
/// stacked on top of the same shape, with their opacity tied to the
/// active mode so they cross-fade in place during the morph.
struct IslandRootView: View {
    private enum VisualPhase: Equatable {
        case collapsed
        case expanding
        case expanded
        case collapsing
    }

    let baseLayout: NotchMetrics.Layout
    /// Width of the host NSWindow's content view. The silhouette is
    /// centered horizontally inside this width, so we need it to compute
    /// the silhouette's rect for click-through hit-testing.
    let containerWidth: CGFloat
    /// Notifies the host NSWindow when the desired system-shadow state
    /// changes. The compact island stays optically embedded in the menu bar;
    /// the system shadow belongs only to the panel and remains present until
    /// its collapse animation has fully finished.
    var onShouldShowShadowChanged: ((Bool) -> Void)? = nil
    /// Notifies the host NSWindow when the silhouette's bounding rect
    /// changes (mode flip, hover widen). The window's
    /// `ClickThroughHostingView` uses the rect to pass clicks through
    /// any transparent area outside the silhouette — without this the
    /// 408pt-tall window swallows clicks across the upper-middle of
    /// the screen.
    var onSilhouetteRectChanged: ((CGRect) -> Void)? = nil

    private let coordinator = IslandCoordinator.shared
    @State private var isHovering = false
    @State private var store = TaskStore.shared
    /// Intrinsic height the panel content reports through
    /// `PanelContentHeightKey`. Drives `expandedHeight` so the silhouette
    /// morphs to the task list instead of a fixed guess.
    @State private var panelContentHeight: CGFloat = 0
    /// The silhouette moves first; its contents follow a fraction later.
    /// Keeping this separate from `mode` prevents the full task layout from
    /// being visibly squeezed through the 28pt bar during the first frames
    /// of the expand animation.
    @State private var panelContentVisible = false
    @State private var panelRevealID = UUID()
    /// AppKit hit-testing and system shadow cannot read SwiftUI's in-flight
    /// presentation frame. This explicit phase keeps them conservative:
    /// expanding accepts input only on the compact island; collapsing makes
    /// the disappearing body click-through while retaining its panel shadow
    /// until the silhouette has fully returned to rest.
    @State private var visualPhase: VisualPhase = .collapsed
    @State private var visualPhaseID = UUID()
    @State private var reportedPanelHeight = NotchMetrics.panelMinHeight
    @State private var panelHitRegionID = UUID()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var mode: IslandCoordinator.Mode { coordinator.mode }

    /// True when the system shadow should be on. See
    /// `onShouldShowShadowChanged` for why we gate it.
    private var shouldShowShadow: Bool {
        switch visualPhase {
        case .collapsed:
            return false
        case .expanding, .expanded, .collapsing:
            return true
        }
    }

    // MARK: - Body

    var body: some View {
        // VStack + trailing Spacer rather than a ZStack(.top) wrapper so the
        // shape is glued to the window's top edge by stack semantics, not by
        // an alignment hint. The hint version had a brief frame during the
        // spring expand where the morphing shape would sit a few pt below
        // the menu bar before snapping up — looked like a "gap" above the
        // panel as it popped out.
        VStack(spacing: 0) {
            shapeWithContent
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: shouldShowShadow, initial: true) { _, new in
            onShouldShowShadowChanged?(new)
        }
        .onChange(of: reportedSilhouetteRect, initial: true) { _, new in
            onSilhouetteRectChanged?(new)
        }
        // When the panel collapses back, force the bar to idle. Without
        // this `isHovering` would stay `true` from the click-to-expand
        // moment (because handleHover doesn't update it during expanded
        // mode), and the bar would land in the hover-widened state. The
        // contract the user wants: hover affordance only fires for an
        // actual mouse-over after collapse, not as a leftover from before.
        .onChange(of: mode, initial: true) { _, newMode in
            synchronizeVisualPhase(with: newMode)
            synchronizePanelContent(with: newMode)

            if newMode == .collapsed, isHovering {
                withAnimation(IslandCoordinator.modeAnimation) {
                    isHovering = false
                }
            }

        }
    }

    /// Bounding rect of the visible silhouette in the host's contentView
    /// coordinate space (top-left origin, matching SwiftUI). The
    /// silhouette is centered horizontally inside `containerWidth` and
    /// glued to the top of the VStack, so x = (container - shape) / 2,
    /// y = 0. Used by `ClickThroughHostingView.visibleRegion` to make
    /// clicks outside this rect pass through to the window below.
    private var silhouetteRect: CGRect {
        let w = shapeWidth
        let h = shapeHeight
        let x = (containerWidth - w) / 2
        return CGRect(x: x, y: 0, width: w, height: h)
    }

    /// Conservative hit region reported to AppKit while geometry animates.
    /// We cannot observe every interpolated SwiftUI frame, so the region
    /// changes only after the corresponding visual edge has arrived.
    private var reportedSilhouetteRect: CGRect {
        switch visualPhase {
        case .collapsed:
            return silhouetteRect
        case .expanding:
            return rect(width: baseLayout.totalWidth, height: baseLayout.barHeight)
        case .expanded:
            return rect(width: panelWidth, height: reportedPanelHeight)
        case .collapsing:
            // The click that initiated collapse already reached its target.
            // Let subsequent clicks pass through the disappearing panel
            // instead of swallowing them in a now non-interactive region.
            return rect(width: baseLayout.totalWidth, height: baseLayout.barHeight)
        }
    }

    private func rect(width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: (containerWidth - width) / 2, y: 0, width: width, height: height)
    }

    /// The single morphing shape with all overlaid content. Sized to the
    /// current mode dimensions; SwiftUI interpolates `width`, `height`,
    /// `cornerRadius` between renders that happen inside `withAnimation`.
    private var shapeWithContent: some View {
        ZStack(alignment: .top) {
            // Backdrop — one shape for both modes.
            backdrop

            // Panel content — visible while expanded.
            NotchPanelView(
                tasks: presentedTasks,
                connectionStatus: store.connectionStatus,
                layout: baseLayout,
                highlightedTask: coordinator.highlightedTask,
                onTaskTap: handleTaskTap,
                onSettingsTap: handleSettingsTap,
                onConnectTap: handleConnectTap,
                drawsBackdrop: false,
                // The panel stays in the tree while collapsed so it can keep
                // reporting the height the silhouette morphs to. `isLive`
                // tells it to stop everything that only matters on screen —
                // the per-second duration clock — so a hidden panel costs
                // nothing but layout.
                isLive: panelContentVisible
            )
            .opacity(panelContentVisible ? 1 : 0)
            .offset(y: panelContentVisible ? 0 : -2)
            .frame(maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(panelContentVisible && visualPhase == .expanded)
        }
        .frame(width: shapeWidth, height: shapeHeight)
        .clipShape(silhouette)
        .overlay(alignment: .top) {
            if mode == .collapsed {
                collapsedBarContent
                    .frame(width: shapeWidth, height: shapeHeight, alignment: .top)
                    .clipShape(silhouette)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(silhouette)
        .onHover(perform: handleHover)
        .onTapGesture(perform: handleTap)
        .onPreferenceChange(PanelContentHeightKey.self) { height in
            // Sub-point deltas are layout noise; reacting to them would
            // feed the measurement back into the frame it measures.
            guard abs(height - panelContentHeight) > 0.5 else { return }
            // Animate only while the panel is on screen — a task arriving
            // while collapsed should just resize the hidden layout so the
            // next expand lands at the right height in one spring.
            if mode == .expanded {
                synchronizePanelHitRegion(toContentHeight: height)
                withAnimation(Motion.respectingReducedMotion(reduceMotion, preferred: Motion.layout)) {
                    panelContentHeight = height
                }
            } else {
                panelContentHeight = height
                reportedPanelHeight = NotchMetrics.panelHeight(forContentHeight: height)
            }
        }
    }

    // MARK: - Backdrop

    /// The expanded surface stays visually quiet and static. State motion
    /// belongs to the compact status dot; animating a blurred shadow around
    /// the full panel forced a 60fps off-screen redraw of a ~420pt surface.
    private var backdrop: some View {
        ZStack(alignment: .top) {
            silhouette
                .fill(Palette.notchBlack)

            // A graphite surface appears only after the black capsule begins
            // to expand. Collapsed remains absolute black so it blends into
            // the physical notch.
            silhouette
                .fill(Palette.islandTop)
                .opacity(mode == .expanded ? 1 : 0)

            silhouette
                .stroke(Color.white.opacity(mode == .expanded ? 0.06 : 0), lineWidth: 0.5)
        }
    }

    /// Connection health is shown separately in the panel header. It must not
    /// erase a real task state: local agents continue to be authoritative even
    /// when an unrelated cloud connector is disconnected.
    private var effectiveBarState: BarState {
        BarState.derive(from: presentedTasks)
    }

    /// The shape used for backdrop, clipping, and hit-testing — built once
    /// per render so all three stay in lockstep as the dimensions morph.
    private var silhouette: NotchPanelShape {
        NotchPanelShape(
            notchWidth: baseLayout.hasNotch ? baseLayout.notchWidth : 0,
            notchHeight: baseLayout.hasNotch ? baseLayout.notchHeight : 0,
            cornerRadius: cornerRadius
        )
    }

    // MARK: - Geometry (mode + hover dependent — animated by withAnimation)

    private var shapeWidth: CGFloat {
        switch mode {
        case .collapsed:
            return isHovering
                ? baseLayout.hovered().totalWidth
                : baseLayout.totalWidth
        case .expanded:
            return panelWidth
        }
    }

    private var shapeHeight: CGFloat {
        switch mode {
        case .collapsed:
            return isHovering
                ? baseLayout.hovered().barHeight
                : baseLayout.barHeight
        case .expanded:
            return expandedHeight
        }
    }

    private var cornerRadius: CGFloat {
        // Smoothly interpolate corner radius between bar (~11) and panel
        // (14) as the morph progresses — `withAnimation` handles the lerp.
        if mode == .expanded {
            return NotchMetrics.panelCornerRadius
        }
        return baseLayout.hasNotch
            ? NotchMetrics.cornerRadius
            : NotchMetrics.syntheticCornerRadius
    }

    private var panelWidth: CGFloat {
        NotchMetrics.panelWidth(for: baseLayout)
    }

    /// Height of the expanded panel, driven by what the content actually
    /// measures. Clamped on both ends: the floor keeps a transient zero
    /// measurement from collapsing the silhouette mid-morph, the ceiling
    /// keeps the panel inside the host window's container.
    private var expandedHeight: CGFloat {
        NotchMetrics.panelHeight(forContentHeight: panelContentHeight)
    }

    // MARK: - Sub-layouts

    private var barLayoutForContent: NotchMetrics.Layout {
        isHovering ? baseLayout.hovered() : baseLayout
    }

    @ViewBuilder
    private var collapsedBarContent: some View {
        if baseLayout.hasNotch {
            NotchBarView(
                state: effectiveBarState,
                summary: taskStatusSummary,
                title: barTitle,
                layout: barLayoutForContent,
                showsContent: true,
                drawsBackdrop: false
            )
        } else {
            syntheticBarContent
        }
    }

    private var syntheticBarContent: some View {
        HStack(spacing: 10) {
            StatusDot(state: effectiveBarState, size: 12)
                .frame(width: 16, height: 16)

            Text(barTitle)
                .font(Typo.barTitle)
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            CompactTaskStatusSummary(summary: taskStatusSummary)
                .padding(.horizontal, 2)
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(
            width: barLayoutForContent.totalWidth,
            height: barLayoutForContent.barHeight,
            alignment: .center
        )
    }

    private var taskStatusSummary: TaskStatusSummary {
        TaskStatusSummary(tasks: presentedTasks)
    }

    private var presentedTasks: [AgentTask] {
        TaskPresentationPolicy.ordered(store.tasks)
    }

    private var barTitle: String {
        guard let task = priorityTask else { return "No tasks" }
        return task.currentPhase ?? task.title
    }

    private var priorityTask: AgentTask? {
        TaskPresentationPolicy.primaryTask(in: presentedTasks)
    }

    /// Stage panel content behind the shape morph. Collapse is immediate
    /// and quick; expand waits 70ms so the surface has enough room before
    /// the task hierarchy begins to appear. The reveal token makes rapid
    /// collapse/re-expand sequences interruptible instead of letting an old
    /// delayed callback flash content into the wrong state.
    private func synchronizePanelContent(with newMode: IslandCoordinator.Mode) {
        let revealID = UUID()
        panelRevealID = revealID

        switch newMode {
        case .collapsed:
            withAnimation(.easeOut(duration: reduceMotion ? 0.07 : 0.09)) {
                panelContentVisible = false
            }

        case .expanded:
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.12)) {
                    panelContentVisible = true
                }
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                guard panelRevealID == revealID, mode == .expanded else { return }
                withAnimation(Motion.contentReveal) {
                    panelContentVisible = true
                }
            }
        }
    }

    /// Keep AppKit-only effects aligned with the end of the SwiftUI morph.
    /// The UUID makes rapid open/close/open sequences interruptible so an
    /// earlier delayed completion can never publish the wrong hit region.
    private func synchronizeVisualPhase(with newMode: IslandCoordinator.Mode) {
        if newMode == .collapsed, visualPhase == .collapsed { return }
        if newMode == .expanded, visualPhase == .expanded { return }

        let phaseID = UUID()
        visualPhaseID = phaseID

        switch newMode {
        case .collapsed:
            visualPhase = .collapsing
        case .expanded:
            visualPhase = .expanding
        }

        let duration = reduceMotion ? 0.14 : Motion.islandMorphDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard visualPhaseID == phaseID, mode == newMode else { return }
            visualPhase = newMode == .expanded ? .expanded : .collapsed
        }
    }

    /// Preserve the union of old/new panel heights until a dynamic layout
    /// animation settles. This prevents the visible tail of a shrinking list
    /// from becoming click-through before the silhouette reaches its target.
    private func synchronizePanelHitRegion(toContentHeight height: CGFloat) {
        let target = NotchMetrics.panelHeight(forContentHeight: height)
        let regionID = UUID()
        panelHitRegionID = regionID
        reportedPanelHeight = max(reportedPanelHeight, target)

        let duration = reduceMotion ? 0.14 : Motion.layoutDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard panelHitRegionID == regionID else { return }
            reportedPanelHeight = target
        }
    }

    // MARK: - Event handlers

    private func handleHover(_ hovering: Bool) {
        switch mode {
        case .collapsed:
            guard visualPhase == .collapsed else { return }
            // Hover only widens the bar (clickable affordance). The panel
            // opens on click, not hover-dwell. The pointing-hand cursor is
            // owned by IslandWindow's mouse poll — NSCursor push/pop from
            // here never worked (AppKit cursorUpdate resets non-key
            // borderless windows to arrow) and leaked stack pushes when a
            // click expanded the panel before the un-hover pop could fire.
            withAnimation(Motion.respectingReducedMotion(reduceMotion, preferred: Motion.hover)) {
                isHovering = hovering
            }

        case .expanded:
            guard visualPhase == .expanded else { return }
            // Mouse re-entered → cancel pending collapse; mouse left →
            // schedule the forgiving grace-period collapse.
            if hovering {
                coordinator.armAutomaticCollapse()
                coordinator.cancelCollapse()
            } else {
                coordinator.scheduleCollapse()
            }
        }
    }

    private func handleTap() {
        guard mode == .collapsed,
              visualPhase == .collapsed || visualPhase == .collapsing else {
            // Inner Buttons (TaskCard, gear, connect) consume their own
            // taps; this gesture only fires for the compact bar shell. Keep
            // that shell reversible while the panel is collapsing: AppKit
            // already reports the compact hit region (and its hand cursor),
            // so swallowing this click would make the visible affordance lie.
            return
        }
        // Hand `isHovering` over to the same spring that drives the mode
        // morph. Without this, the hover spring (response 0.3) might still
        // be settling when the click fires the mode spring (response 0.42)
        // — two springs fight over shapeWidth/Height, and the bar content's
        // layout reflow briefly desyncs from the morphing silhouette,
        // showing as a thin seam at the start of the expand.
        withAnimation(IslandCoordinator.modeAnimation) {
            isHovering = false
        }
        coordinator.expandFromPointer()
    }

    private func handleTaskTap(_ task: AgentTask) {
        coordinator.clearHighlight()
        store.jumpToTask(task)
        coordinator.collapse()
    }

    private func handleSettingsTap() {
        // Collapse first so the panel doesn't visually compete with the
        // Settings window that's about to open.
        coordinator.collapse()
        // AppDelegate listens for this notification and lazily creates /
        // brings the SettingsWindow to front. Decoupled via Notification
        // so the SwiftUI view doesn't need to know about NSWindow plumbing.
        NotificationCenter.default.post(name: .islandOpenSettingsRequested, object: nil)
    }

    private func handleConnectTap() {
        coordinator.collapse()
        NotificationCenter.default.post(name: .islandOpenSettingsRequested, object: nil)
    }
}
