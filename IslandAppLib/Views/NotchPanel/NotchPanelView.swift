import SwiftUI
import IslandCore

/// Intrinsic height of the panel's content, published to `IslandRootView`
/// so the morphing silhouette can size itself to what's actually inside.
/// Before this existed the expanded height was a fixed 360pt guess, and
/// anything past ~5 tasks pushed the "Connect Service" footer outside the
/// silhouette's clip.
struct PanelContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Expanded panel content. A single warm graphite surface with line-based
/// hierarchy; rows only emerge on hover and task state is never used as a
/// decorative panel accent.
struct NotchPanelView: View {
    let tasks: [AgentTask]
    let connectionStatus: ConnectionStatus
    /// Layout snapshot of the host display so the panel knows whether to
    /// reserve space for the hardware notch at the top.
    let layout: NotchMetrics.Layout
    let highlightedTask: TaskIdentity?
    var pendingActionRequests: [AgentActionRequest] = []
    let onTaskTap: (AgentTask) -> Void
    var onActionDecision: (UUID, AgentActionDecision) -> Void = { _, _ in }
    var onQuestionAnswer: (UUID, [AgentQuestionAnswer]) -> Void = { _, _ in }
    var onActionDefer: (UUID) -> Void = { _ in }
    let onSettingsTap: () -> Void
    let onConnectTap: () -> Void
    /// When `false` the view renders content only — the parent
    /// (`IslandRootView`) is drawing a shared backdrop that spans both bar
    /// and panel states for a single SwiftUI morph.
    var drawsBackdrop: Bool = true
    /// The production root has already built one attention-first snapshot.
    /// Reuse its state instead of sorting the same rows again; standalone
    /// previews may omit this and retain the generic derivation path.
    var presentationState: BarState? = nil
    /// The root snapshot has already counted every status in one pass. Reuse
    /// it for the header count and accessibility summary instead of scanning
    /// the same task rows again inside the expanded panel.
    var presentationSummary: TaskStatusSummary? = nil
    /// Deterministic final-state input for DEBUG/QA snapshot hosts, which do
    /// not advance the run loop long enough for the asynchronous renderer.
    /// Production leaves this empty and always uses the off-main path.
    var initialPlanDocuments: [UUID: PlanMarkdownDocument] = [:]
    /// Whether the panel is actually on screen. `false` keeps the layout
    /// (the parent measures it to size the silhouette) but stops the clock
    /// below and every per-card animation.
    var isLive: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.devIslandLanguage) private var language

    var body: some View {
        let requestPresentation = ActionRequestPresentationSnapshot(
            requests: pendingActionRequests,
            tasks: tasks
        )

        ZStack(alignment: .top) {
            if drawsBackdrop {
                NotchPanelShape(
                    notchWidth: layout.hasNotch ? layout.notchWidth : 0,
                    notchHeight: layout.hasNotch ? layout.notchHeight : 0
                )
                .fill(Palette.islandTop)
            }

            VStack(spacing: 0) {
                topRow
                panelBody(requestPresentation: requestPresentation)
                    .padding(.top, layout.hasNotch ? 8 : 0)
            }
            // Measured on the content stack rather than the outer frame:
            // the parent sizes the silhouette FROM this value, so reading
            // it off the parent-imposed frame would be circular.
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: PanelContentHeightKey.self,
                        value: proxy.size.height
                    )
                }
            }
        }
        .frame(width: panelWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Top row (header)

    /// On notched displays, header content is split into the side extensions
    /// flanking the hardware notch so the otherwise-empty space is used.
    /// On synthetic-notch displays, the header sits at the top of the
    /// panel below a small padding.
    @ViewBuilder
    private var topRow: some View {
        if layout.hasNotch {
            HStack(spacing: 0) {
                titleLabel
                    .padding(.leading, 14)
                    .frame(width: sideExtensionWidth, alignment: .leading)

                // Hardware notch corridor — transparent
                Spacer().frame(width: layout.notchWidth)

                trailingCluster
                    .padding(.trailing, 10)
                    .frame(width: sideExtensionWidth, alignment: .trailing)
            }
            .frame(height: layout.notchHeight)
        } else {
            HStack(spacing: 6) {
                titleLabel
                Spacer()
                trailingCluster
            }
            .padding(.horizontal, 16)
            .padding(.top, 11)
            .padding(.bottom, 9)
        }
    }

    @ViewBuilder
    private var titleLabel: some View {
        HStack(spacing: 7) {
            AnimatedDotMatrixMark(
                color: headerState.color,
                size: 8,
                motion: headerState.matrixMotion,
                pattern: headerState.matrixPattern,
                intensity: headerState.matrixIntensity,
                isAnimated: isLive && !reduceMotion
            )

            Text(L10n.string(headerTitle, language: language))
                .font(Typo.sectionHeader)
                .foregroundStyle(Palette.warmWhite.opacity(0.9))

            Text("\(headerCount)")
                .font(Typo.barCount)
                .foregroundStyle(headerState.color.opacity(0.9))
                .monospacedDigit()

            if !layout.hasNotch, headerCount != tasks.count {
                Text("· \(sessionCountLabel)")
                    .font(Typo.barCount)
                    .foregroundStyle(Palette.textTertiary)
                    .monospacedDigit()
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headerAccessibilityLabel)
    }

    private var headerState: BarState {
        presentationState ?? BarState.derive(from: tasks)
    }

    private var headerTitle: String {
        switch headerState {
        case .waiting:   return "Attention"
        case .failed:    return "Review"
        case .completed: return "Results"
        case .running:   return "Working"
        case .idle:      return "Sessions"
        }
    }

    private var headerCount: Int {
        switch headerState {
        case .waiting:   return headerSummary.waiting
        case .failed:    return headerSummary.failed
        case .completed: return headerSummary.completed
        case .running:   return headerSummary.running
        case .idle:      return 0
        }
    }

    private var headerSummary: TaskStatusSummary {
        presentationSummary ?? TaskStatusSummary(tasks: tasks)
    }

    private var sessionCountLabel: String {
        L10n.sessionCount(tasks.count, language: language)
    }

    private var headerAccessibilityLabel: String {
        guard headerSummary.total > 0 else {
            return L10n.string("No sessions", language: language)
        }
        return L10n.format(
            "%@, %lld. %@. %lld sessions total.",
            language: language,
            L10n.string(headerTitle, language: language),
            Int64(headerCount),
            headerSummary.accessibilityLabel(language: language),
            Int64(headerSummary.total)
        )
    }

    @ViewBuilder
    private var trailingCluster: some View {
        HStack(spacing: 7) {
            connectionDot
            Button(action: onConnectTap) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textSecondary.opacity(0.72))
                    .frame(width: 24, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(pressedScale: 0.98))
            .pointingHandCursor()
            .help(L10n.string("Connect an agent", language: language))
            .accessibilityLabel(
                L10n.string("Connect an Agent", language: language)
            )
            .accessibilityHint(
                L10n.string("Opens Agent connection settings", language: language)
            )

            Button(action: onSettingsTap) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textSecondary.opacity(0.72))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(pressedScale: 0.96))
            .pointingHandCursor()
            .help(L10n.string("Open Settings", language: language))
            .accessibilityLabel(
                L10n.string("Open Dev Island Settings", language: language)
            )
            .accessibilityHint(
                L10n.string("Opens settings in a separate window", language: language)
            )
        }
    }

    private var sideExtensionWidth: CGFloat {
        (panelWidth - layout.notchWidth) / 2
    }

    @ViewBuilder
    private var connectionDot: some View {
        // The same point-field signature used by task status keeps connection
        // state from falling back to a generic system dot.
        // — keeps the panel header consistent with the rest of the
        // status palette when reconnecting/degraded states flap.
        HStack(spacing: 0) {
            DotMatrixMark(
                color: connectionColor,
                size: 8,
                pattern: connectionPattern,
                intensity: connectionIntensity
            )
        }
            .animation(Motion.colorTransition, value: connectionStatus)
            .help(L10n.string(connectionTooltip, language: language))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                L10n.string("Agent connections", language: language)
            )
            .accessibilityValue(
                L10n.string(connectionAccessibilityValue, language: language)
            )
    }

    private var connectionColor: Color {
        switch connectionStatus {
        case .connected:                 return Palette.stateCompleted.opacity(0.85)
        case .reconnecting, .degraded:   return Palette.stateWaiting.opacity(0.85)
        case .disconnected:              return Color.white.opacity(0.20)
        }
    }

    private var connectionPattern: DotMatrixMark.Pattern {
        switch connectionStatus {
        case .connected:               return .plus
        case .reconnecting, .degraded: return .ring
        case .disconnected:            return .field
        }
    }

    private var connectionIntensity: Double {
        switch connectionStatus {
        case .connected:               return 0.78
        case .reconnecting, .degraded: return 1.00
        case .disconnected:            return 0.42
        }
    }

    private var connectionTooltip: String {
        switch connectionStatus {
        case .connected:                 return "Connected"
        case .reconnecting:              return "Reconnecting…"
        case .disconnected:              return "Disconnected"
        case .degraded(let reason):      return reason
        }
    }

    private var connectionAccessibilityValue: String {
        switch connectionStatus {
        case .connected:                 return "Connected"
        case .reconnecting:              return "Reconnecting"
        case .disconnected:              return "Disconnected"
        case .degraded:                  return "Needs attention"
        }
    }

    @ViewBuilder
    private func panelBody(
        requestPresentation: ActionRequestPresentationSnapshot
    ) -> some View {
        // The scroll container is deliberately clock-free. Task durations and
        // action countdowns own tiny row/header-local clocks, so a second tick
        // cannot reconstruct ScrollViewReader, LazyVStack, Plan Review, hover
        // state, or the decision buttons around the changing text.
        if tasks.isEmpty && pendingActionRequests.isEmpty {
            emptyState
        } else {
            taskList(requestPresentation: requestPresentation)
        }
    }

    private func taskList(
        requestPresentation: ActionRequestPresentationSnapshot
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 1) {
                    ForEach(tasks, id: \.identity) { task in
                        VStack(spacing: 1) {
                            if let request = requestPresentation.primary(
                                for: task.identity
                            ) {
                                ActionRequestSurface(
                                    request: request,
                                    contextTitle: task.title,
                                    additionalQueuedCount: requestPresentation.additionalCount(
                                        for: task.identity
                                    ),
                                    isLive: isLive,
                                    isKeyboardPrimary: requestPresentation
                                        .isKeyboardPrimary(request),
                                    initialPlanDocument: initialPlanDocuments[request.id],
                                    onDecision: { decision in
                                        onActionDecision(request.id, decision)
                                    },
                                    onAnswer: { answers in
                                        onQuestionAnswer(request.id, answers)
                                    },
                                    onDeferToAgent: {
                                        onActionDefer(request.id)
                                    }
                                )
                            } else {
                                TaskCard(
                                    task: task,
                                    isHighlighted: task.identity == highlightedTask,
                                    isLive: isLive,
                                    onTap: { onTaskTap(task) }
                                )
                            }
                        }
                        .id(task.identity)
                    }

                    ForEach(requestPresentation.orphanedRequests) { request in
                        ActionRequestSurface(
                            request: request,
                            isLive: isLive,
                            isKeyboardPrimary: requestPresentation
                                .isKeyboardPrimary(request),
                            initialPlanDocument: initialPlanDocuments[request.id],
                            onDecision: { decision in
                                onActionDecision(request.id, decision)
                            },
                            onAnswer: { answers in
                                onQuestionAnswer(request.id, answers)
                            },
                            onDeferToAgent: {
                                onActionDefer(request.id)
                            }
                        )
                        .id(request.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .onChange(of: highlightedTask, initial: true) { _, identity in
                guard let identity,
                      tasks.contains(where: { $0.identity == identity }) else { return }
                if isLive && !reduceMotion {
                    withAnimation(Motion.contentReveal) {
                        proxy.scrollTo(identity, anchor: .center)
                    }
                } else {
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        proxy.scrollTo(identity, anchor: .center)
                    }
                }
            }
        }
        .frame(maxHeight: NotchMetrics.panelTaskListMaxHeight)
    }

    @ViewBuilder
    private var emptyState: some View {
        HStack(alignment: .top, spacing: 13) {
            DotMatrixMark(
                color: Palette.stateIdle,
                size: 18,
                pattern: .field,
                intensity: 0.95
            )
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.string("Nothing needs you", language: language))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.warmWhite.opacity(0.90))

                Text(L10n.string(
                    "Agent sessions will appear here automatically.",
                    language: language
                ))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary.opacity(0.88))

                Button(action: onConnectTap) {
                    HStack(spacing: 6) {
                        Text(L10n.string("Connect an agent", language: language))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(IslandQuietActionButtonStyle())
                .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 20)
    }

    // MARK: - Geometry

    private var panelWidth: CGFloat {
        NotchMetrics.panelWidth(for: layout)
    }

}

// PREVIEWS && DEBUG — these previews reference TaskStore.previewTasks
// which lives behind a #if DEBUG extension; release builds (CI / Cask
// release artifact) need the block stripped entirely.
#if PREVIEWS && DEBUG
private let previewLayoutNoNotch = NotchMetrics.Layout(
    hasNotch: false,
    barHeight: 28,
    notchHeight: 0,
    menuBarHeight: 28,
    notchWidth: NotchMetrics.defaultNotchWidth,
    topMargin: 0
)

private let previewLayoutNotched = NotchMetrics.Layout(
    hasNotch: true,
    barHeight: 39,
    notchHeight: 32,
    menuBarHeight: 32,
    notchWidth: 200,
    topMargin: 0
)

#Preview("Panel — no notch, 3 tasks") {
    NotchPanelView(
        tasks: TaskStore.previewTasks,
        connectionStatus: .connected,
        layout: previewLayoutNoNotch,
        highlightedTask: nil,
        onTaskTap: { _ in },
        onSettingsTap: {},
        onConnectTap: {}
    )
    .padding(40)
    .background(Color.gray.opacity(0.25))
}

#Preview("Panel — notched, 3 tasks") {
    NotchPanelView(
        tasks: TaskStore.previewTasks,
        connectionStatus: .connected,
        layout: previewLayoutNotched,
        highlightedTask: TaskStore.previewTasks.first?.identity,
        onTaskTap: { _ in },
        onSettingsTap: {},
        onConnectTap: {}
    )
    .padding(40)
    .background(Color.gray.opacity(0.25))
}

#Preview("Panel — empty") {
    NotchPanelView(
        tasks: [],
        connectionStatus: .reconnecting,
        layout: previewLayoutNoNotch,
        highlightedTask: nil,
        onTaskTap: { _ in },
        onSettingsTap: {},
        onConnectTap: {}
    )
    .padding(40)
    .background(Color.gray.opacity(0.25))
}
#endif
