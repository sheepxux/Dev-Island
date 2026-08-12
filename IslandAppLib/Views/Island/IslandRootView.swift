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
    let baseLayout: NotchMetrics.Layout
    /// Width of the host NSWindow's content view. The silhouette is
    /// centered horizontally inside this width, so we need it to compute
    /// the silhouette's rect for click-through hit-testing.
    let containerWidth: CGFloat
    /// Notifies the host NSWindow when the desired system-shadow state
    /// changes. The window toggles `hasShadow` so the silhouette only
    /// drops a shadow when (a) hovered in collapsed mode — clickable
    /// affordance — or (b) expanded as a panel. Idle bar has no shadow.
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

    private var mode: IslandCoordinator.Mode { coordinator.mode }

    /// True when the system shadow should be on. See
    /// `onShouldShowShadowChanged` for why we gate it.
    private var shouldShowShadow: Bool {
        mode == .expanded || isHovering
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
        .onChange(of: silhouetteRect, initial: true) { _, new in
            onSilhouetteRectChanged?(new)
        }
        // When the panel collapses back, force the bar to idle. Without
        // this `isHovering` would stay `true` from the click-to-expand
        // moment (because handleHover doesn't update it during expanded
        // mode), and the bar would land in the hover-widened state. The
        // contract the user wants: hover affordance only fires for an
        // actual mouse-over after collapse, not as a leftover from before.
        .onChange(of: mode) { _, newMode in
            guard newMode == .collapsed, isHovering else { return }
            withAnimation(IslandCoordinator.modeAnimation) {
                isHovering = false
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

    /// The single morphing shape with all overlaid content. Sized to the
    /// current mode dimensions; SwiftUI interpolates `width`, `height`,
    /// `cornerRadius` between renders that happen inside `withAnimation`.
    private var shapeWithContent: some View {
        ZStack(alignment: .top) {
            // Backdrop — one shape for both modes.
            backdrop

            // Panel content — visible while expanded.
            NotchPanelView(
                tasks: store.tasks,
                connectionStatus: store.connectionStatus,
                layout: baseLayout,
                highlightedTask: coordinator.highlightedTask,
                onTaskTap: handleTaskTap,
                onSettingsTap: handleSettingsTap,
                onConnectTap: handleConnectTap,
                drawsBackdrop: false
            )
            .opacity(mode == .expanded ? 1 : 0)
            .frame(maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(mode == .expanded)
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
        .allowsHitTesting(mode == .collapsed || mode == .expanded)
    }

    // MARK: - Backdrop with synced glow

    /// Backdrop shape with a `StatusPhase`-driven outer glow. Pause the
    /// timeline for static states so we don't burn frames at idle.
    /// `.animation(Motion.colorTransition, value: state)` keeps the
    /// glow's color in lockstep with the StatusDot's fill — both
    /// cross-fade over 250ms on state change, per CLAUDE_CLIENT.md §6
    /// task 3 ("和圆点同相位"). Without it, the glow would jump-cut
    /// while the dot smoothly faded.
    private var backdrop: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !needsTimelineGlow)) { context in
            let state = effectiveBarState
            let phase = StatusPhase.compute(state: state, at: context.date)
            ZStack(alignment: .top) {
                silhouette
                    .fill(Palette.notchBlack)
                    .shadow(
                        color: state.color.opacity(phase.glowOpacity * 0.55),
                        radius: phase.glowRadius * 1.3
                    )
                    .animation(Motion.colorTransition, value: state)
            }
        }
    }

    private var needsTimelineGlow: Bool {
        let s = effectiveBarState
        return s == .running || s == .waiting
    }

    /// `BarState` adjusted for the current `ConnectionStatus`. Per
    /// CLAUDE_CLIENT.md §6 task 8, the bar should "show gray" when
    /// `connectionStatus` is disconnected or reconnecting — the data
    /// the user is looking at may be stale, so we don't want to keep
    /// the dot/glow loudly running/waiting/etc. We collapse to `.idle`
    /// (gray, no glow, no animation). The 250ms color crossfade in
    /// StatusDot + backdrop handles the transition smoothly.
    ///
    /// `.degraded` is intentionally NOT dimmed — it just means the
    /// webhook tunnel is down and we're polling, so data is still
    /// being refreshed every 60s. Status colors stay live.
    private var effectiveBarState: BarState {
        let raw = BarState.derive(from: store.tasks)
        switch store.connectionStatus {
        case .disconnected, .reconnecting:
            return .idle
        case .connected, .degraded:
            return raw
        }
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
        // (~22) as the morph progresses — `withAnimation` handles the lerp.
        if mode == .expanded {
            return NotchMetrics.panelCornerRadius
        }
        return baseLayout.hasNotch
            ? NotchMetrics.cornerRadius
            : NotchMetrics.syntheticCornerRadius
    }

    private var panelWidth: CGFloat {
        baseLayout.hasNotch
            ? min(NotchMetrics.panelMaxWidth, baseLayout.notchWidth + 240)
            : NotchMetrics.panelWidth
    }

    /// Conservative fixed height for the expanded panel. The inner task
    /// list caps itself at `maxHeight: 320` (NotchPanelView), so 360 is a
    /// comfortable upper bound for header + list + footer. Refinement:
    /// drive this off intrinsic content height via a PreferenceKey.
    private var expandedHeight: CGFloat { 360 }

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
            StatusDot(state: effectiveBarState, size: 10)
                .frame(width: 14, height: 14)

            Text(barTitle)
                .font(Typo.barTitle)
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            CompactTaskStatusSummary(summary: taskStatusSummary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                )
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
        TaskStatusSummary(tasks: store.tasks)
    }

    private var barTitle: String {
        guard let task = priorityTask else { return "No tasks" }
        return task.currentPhase ?? task.title
    }

    private var priorityTask: AgentTask? {
        let statuses: [TaskStatus] = [.waiting, .failed, .running, .completed]
        for status in statuses {
            if let task = store.tasks.first(where: { $0.status == status }) {
                return task
            }
        }
        return nil
    }

    // MARK: - Event handlers

    private func handleHover(_ hovering: Bool) {
        switch mode {
        case .collapsed:
            // Hover only widens the bar (clickable affordance). The panel
            // opens on click, not hover-dwell. The pointing-hand cursor is
            // owned by IslandWindow's mouse poll — NSCursor push/pop from
            // here never worked (AppKit cursorUpdate resets non-key
            // borderless windows to arrow) and leaked stack pushes when a
            // click expanded the panel before the un-hover pop could fire.
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                isHovering = hovering
            }

        case .expanded:
            // Mouse re-entered → cancel pending collapse; mouse left →
            // schedule the 300ms grace-period collapse.
            if hovering {
                coordinator.cancelCollapse()
            } else {
                coordinator.scheduleCollapse()
            }
        }
    }

    private func handleTap() {
        guard mode == .collapsed else {
            // Inner Buttons (TaskCard, gear, connect) consume their own
            // taps; this gesture only fires for the bar shell.
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
        coordinator.expand()
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
