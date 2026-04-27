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
    /// Notifies the host NSWindow when the desired system-shadow state
    /// changes. The window toggles `hasShadow` so the silhouette only
    /// drops a shadow when (a) hovered in collapsed mode — clickable
    /// affordance — or (b) expanded as a panel. Idle bar has no shadow.
    var onShouldShowShadowChanged: ((Bool) -> Void)? = nil

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

    /// The single morphing shape with all overlaid content. Sized to the
    /// current mode dimensions; SwiftUI interpolates `width`, `height`,
    /// `cornerRadius` between renders that happen inside `withAnimation`.
    private var shapeWithContent: some View {
        ZStack(alignment: .top) {
            // Backdrop — one shape for both modes.
            backdrop

            // Bar content — visible while collapsed, faded out while expanded.
            NotchBarView(
                state: BarState.derive(from: store.tasks),
                taskCount: activeCount,
                layout: barLayoutForContent,
                showsContent: baseLayout.hasNotch || isHovering,
                drawsBackdrop: false
            )
            .opacity(mode == .collapsed ? 1 : 0)
            // Anchor to the very top so the bar content stays where it
            // belongs as the parent grows downward.
            .frame(maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(mode == .collapsed)

            // Panel content — visible while expanded.
            NotchPanelView(
                tasks: store.tasks,
                connectionStatus: store.connectionStatus,
                layout: baseLayout,
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
        .contentShape(silhouette)
        .onHover(perform: handleHover)
        .onTapGesture(perform: handleTap)
    }

    // MARK: - Backdrop with synced glow

    /// Backdrop shape with a `StatusPhase`-driven outer glow. Pause the
    /// timeline for static states so we don't burn frames at idle.
    private var backdrop: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !needsTimelineGlow)) { context in
            let phase = StatusPhase.compute(state: BarState.derive(from: store.tasks), at: context.date)
            silhouette
                .fill(Palette.notchBlack)
                .shadow(
                    color: BarState.derive(from: store.tasks).color.opacity(phase.glowOpacity * 0.55),
                    radius: phase.glowRadius * 1.3
                )
        }
    }

    private var needsTimelineGlow: Bool {
        let s = BarState.derive(from: store.tasks)
        return s == .running || s == .waiting
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
        mode == .expanded
            ? NotchMetrics.panelCornerRadius
            : NotchMetrics.cornerRadius
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

    private var activeCount: Int {
        store.tasks.filter { $0.status == .running || $0.status == .waiting }.count
    }

    // MARK: - Event handlers

    private func handleHover(_ hovering: Bool) {
        switch mode {
        case .collapsed:
            // Hover only widens the bar (clickable affordance). The panel
            // opens on click, not hover-dwell.
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                isHovering = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
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
        store.openTaskInBrowser(id: task.id)
        coordinator.collapse()
    }

    private func handleSettingsTap() {
        // Task 6 will route to SettingsWindow.
        coordinator.collapse()
    }

    private func handleConnectTap() {
        coordinator.collapse()
    }
}
