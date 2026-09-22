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
    let manusConnectionStatus: ConnectionStatus
    let localAgentStatus: LocalHookServiceStatus
    let apiKeyStatus: APIKeyStatus
    /// Layout snapshot of the host display so the panel knows whether to
    /// reserve space for the hardware notch at the top.
    let layout: NotchMetrics.Layout
    let highlightedTask: TaskIdentity?
    var pendingActionRequests: [AgentActionRequest] = []
    let onTaskTap: (AgentTask) -> Void
    var onActionDecision: (UUID, AgentActionDecision) -> Bool = { _, _ in false }
    var onQuestionAnswer: (UUID, [AgentQuestionAnswer]) -> Bool = { _, _ in false }
    var onActionDefer: (UUID) -> Void = { _ in }
    let onSettingsTap: () -> Void
    let onConnectTap: () -> Void
    var onHistoryTap: () -> Void = {}
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
    /// Pre-rendered "Today: …" line for the idle state; nil hides the row.
    var todaySummary: String? = nil
    /// "X is running but not reporting" notice for the idle state.
    var reportingNotice: LocalAgentReportingNotice? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.devIslandLanguage) private var language
    @State private var responseReceipts: [TaskIdentity: ActionResponseReceipt] = [:]

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
        // A decision made with the system-wide shortcut never passes through
        // the in-panel buttons, so mirror the same short receipt here.
        .onReceive(NotificationCenter.default.publisher(for: .islandGlobalDecisionApplied)) { note in
            guard isLive,
                  let request = note.userInfo?[GlobalDecisionShortcutService.requestUserInfoKey]
                    as? AgentActionRequest,
                  let decision = note.userInfo?[GlobalDecisionShortcutService.decisionUserInfoKey]
                    as? AgentActionDecision else { return }
            let shortcutReceipt = stageResponseReceipt(
                ActionResponseReceiptPresentation.decision(
                    for: request,
                    decision: decision,
                    language: language
                ),
                for: request.taskIdentity
            )
            scheduleResponseReceiptDismissal(shortcutReceipt, for: request.taskIdentity)
        }
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
                // No rows sit beside the notch, so the wing keeps its own
                // tighter inset instead of the row column.
                titleLabel
                    .padding(.leading, 14)
                    .frame(width: sideExtensionWidth, alignment: .leading)

                // Hardware notch corridor — transparent
                Spacer().frame(width: layout.notchWidth)

                trailingCluster
                    .padding(.trailing, 8)
                    .frame(width: sideExtensionWidth, alignment: .trailing)
            }
            .frame(height: layout.notchHeight)
        } else {
            HStack(spacing: 6) {
                titleLabel
                Spacer()
                trailingCluster
            }
            .padding(.leading, NotchMetrics.panelInset + TaskCardMetrics.horizontalPadding)
            .padding(.trailing, 8)
            .padding(.top, 8)
            .padding(.bottom, 6)
        }
    }

    /// Gap between the header's state mark and its title; the empty state
    /// aligns its text to the title with it.
    private static let headerMarkSpacing: CGFloat = 7

    /// The first variant that fits its space, never a truncated one. Beside
    /// a hardware notch the wing can be under 90pt, so the state word gives
    /// way to the mark and its count; VoiceOver always hears the full label.
    private var titleLabel: some View {
        ViewThatFits(in: .horizontal) {
            headerTitle(showsWord: true, showsTotal: !layout.hasNotch)
            headerTitle(showsWord: true, showsTotal: false)
            headerTitle(showsWord: false, showsTotal: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headerAccessibilityLabel)
    }

    private func headerTitle(showsWord: Bool, showsTotal: Bool) -> some View {
        HStack(spacing: Self.headerMarkSpacing) {
            AnimatedDotMatrixMark(
                color: headerState.color,
                size: TaskCardLeadingIdentityMetrics.statusSize,
                motion: headerState.matrixMotion,
                pattern: headerState.matrixPattern,
                intensity: headerState.matrixIntensity,
                isAnimated: isLive && !reduceMotion
            )

            if showsWord {
                Text(L10n.string(headerTitle, language: language))
                    .font(Typo.islandHeadline)
                    .foregroundStyle(Palette.warmWhite)
            }

            if headerCount > 0 {
                Text("\(headerCount)")
                    .font(Typo.islandNumeric)
                    .foregroundStyle(headerState.color)
                    .monospacedDigit()
            }

            if showsTotal, headerSummary.total > 0, headerCount != headerSummary.total {
                Text("· \(sessionCountLabel)")
                    .font(Typo.islandMeta)
                    .foregroundStyle(Palette.textTertiary)
                    .monospacedDigit()
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    private var headerState: BarState {
        presentationState ?? BarState.derive(from: tasks)
    }

    /// Names the state the header count refers to, in the words the rows
    /// already use, so "2" always reads as "2 of this kind".
    private var headerTitle: String {
        switch headerState {
        case .waiting:   return "Needs you"
        case .failed:    return "Failed"
        case .completed: return "Completed"
        case .running:   return "Running"
        case .idle:      return "No sessions"
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
        L10n.sessionCount(headerSummary.total, language: language)
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
        HStack(spacing: 2) {
            connectionDot
            Button(action: onHistoryTap) {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(IslandIconButtonStyle())
            .help(L10n.string("Session History", language: language))
            .accessibilityLabel(
                L10n.string("Session History", language: language)
            )
            .accessibilityHint(
                L10n.string("View recent tasks and results", language: language)
            )

            Button(action: onSettingsTap) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(IslandIconButtonStyle())
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
        let presentation = AgentConnectionIndicatorPresentation.snapshot(
            localAgentStatus: localAgentStatus,
            apiKeyStatus: apiKeyStatus,
            manusStatus: manusConnectionStatus,
            language: language
        )

        // Healthy connections are the expected state and stay silent; the
        // mark shows only while a transport is reconnecting or broken. Its
        // slot is always reserved, so the header never shifts when it
        // appears. The point-field signature keeps connection state from
        // falling back to a generic system dot.
        let isQuiet = presentation.state == .available
        AnimatedDotMatrixMark(
            color: connectionColor(presentation.state),
            size: 9,
            motion: connectionMotion(presentation.state),
            pattern: connectionPattern(presentation.state),
            intensity: connectionIntensity(presentation.state),
            isAnimated: isLive && !reduceMotion && !isQuiet
        )
            .frame(width: 20, height: 28)
            .opacity(isQuiet ? 0 : 1)
            .animation(Motion.colorTransition, value: presentation.state)
            .contentShape(Rectangle())
            .help(isQuiet ? "" : presentation.help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.accessibilityLabel)
            .accessibilityValue(presentation.accessibilityValue)
            .accessibilityHidden(isQuiet)
    }

    private func connectionColor(
        _ state: AgentConnectionIndicatorSnapshot.State
    ) -> Color {
        switch state {
        case .available:       return Palette.stateCompleted
        case .transitioning:   return Palette.stateRunning
        case .needsAttention:  return Palette.stateWaiting
        case .inactive:        return Palette.stateIdle
        }
    }

    private func connectionPattern(
        _ state: AgentConnectionIndicatorSnapshot.State
    ) -> DotMatrixMark.Pattern {
        switch state {
        case .available:       return .plus
        case .transitioning:   return .orbit
        case .needsAttention:  return .ring
        case .inactive:        return .field
        }
    }

    private func connectionMotion(
        _ state: AgentConnectionIndicatorSnapshot.State
    ) -> DotMatrixMark.MotionStyle {
        switch state {
        case .transitioning:   return .orbiting
        case .needsAttention:  return .attention
        case .available, .inactive: return .still
        }
    }

    private func connectionIntensity(
        _ state: AgentConnectionIndicatorSnapshot.State
    ) -> Double {
        switch state {
        case .available:       return 0.92
        case .transitioning:   return 0.98
        case .needsAttention:  return 1.00
        case .inactive:        return 0.42
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
                LazyVStack(spacing: 2) {
                    ForEach(tasks, id: \.identity) { task in
                        VStack(spacing: 2) {
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
                                        resolveDecision(
                                            request,
                                            decision: decision,
                                            for: task.identity
                                        )
                                    },
                                    onAnswer: { answers in
                                        resolveAnswers(
                                            request,
                                            answers: answers,
                                            for: task.identity
                                        )
                                    },
                                    onDeferToAgent: {
                                        onActionDefer(request.id)
                                    }
                                )
                            } else if let receipt = responseReceipts[task.identity] {
                                ActionResponseReceiptRow(
                                    snapshot: receipt.snapshot,
                                    isLive: isLive
                                )
                            } else {
                                TaskCard(
                                    task: task,
                                    isHighlighted: task.identity == highlightedTask,
                                    isLive: isLive,
                                    onTap: { onTaskTap(task) }
                                )
                                .transition(.opacity)
                            }
                        }
                        .id(task.identity)
                        .animation(
                            Motion.respectingReducedMotion(
                                reduceMotion,
                                preferred: Motion.layout
                            ),
                            value: requestPresentation.primary(for: task.identity)?.id
                        )
                    }

                    ForEach(requestPresentation.orphanedRequests) { request in
                        ActionRequestSurface(
                            request: request,
                            isLive: isLive,
                            isKeyboardPrimary: requestPresentation
                                .isKeyboardPrimary(request),
                            initialPlanDocument: initialPlanDocuments[request.id],
                            onDecision: { decision in
                                _ = onActionDecision(request.id, decision)
                            },
                            onAnswer: { answers in
                                _ = onQuestionAnswer(request.id, answers)
                            },
                            onDeferToAgent: {
                                onActionDefer(request.id)
                            }
                        )
                        .id(request.id)
                    }
                }
                .padding(.horizontal, NotchMetrics.panelInset)
                .padding(.bottom, NotchMetrics.panelInset)
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

    private func resolveDecision(
        _ request: AgentActionRequest,
        decision: AgentActionDecision,
        for identity: TaskIdentity
    ) {
        let receipt = stageResponseReceipt(
            ActionResponseReceiptPresentation.decision(
                for: request,
                decision: decision,
                language: language
            ),
            for: identity
        )
        guard onActionDecision(request.id, decision) else {
            discardResponseReceipt(receipt, for: identity)
            return
        }
        scheduleResponseReceiptDismissal(receipt, for: identity)
    }

    private func resolveAnswers(
        _ request: AgentActionRequest,
        answers: [AgentQuestionAnswer],
        for identity: TaskIdentity
    ) {
        let receipt = stageResponseReceipt(
            ActionResponseReceiptPresentation.answersSent(
                for: request,
                language: language
            ),
            for: identity
        )
        guard onQuestionAnswer(request.id, answers) else {
            discardResponseReceipt(receipt, for: identity)
            return
        }
        scheduleResponseReceiptDismissal(receipt, for: identity)
    }

    /// Reserve the post-response row before mutating `TaskStore`. Observation
    /// publishes the request removal synchronously; without this reservation,
    /// SwiftUI briefly constructs the full TaskCard between the form and the
    /// receipt, then throws it away one statement later. Besides being wasted
    /// work, that transient row can lazily decode brand and system glyphs on
    /// the interaction frame. The request branch still wins while it exists,
    /// so staging the receipt is not visible and is safe to roll back when a
    /// stale response loses the store race.
    private func stageResponseReceipt(
        _ snapshot: ActionResponseReceiptSnapshot,
        for identity: TaskIdentity
    ) -> ActionResponseReceipt {
        let receipt = ActionResponseReceipt(snapshot: snapshot)
        let transaction = Transaction(animation: nil)
        withTransaction(transaction) {
            responseReceipts[identity] = receipt
        }
        return receipt
    }

    private func discardResponseReceipt(
        _ receipt: ActionResponseReceipt,
        for identity: TaskIdentity
    ) {
        guard responseReceipts[identity]?.id == receipt.id else { return }
        let transaction = Transaction(animation: nil)
        withTransaction(transaction) {
            _ = responseReceipts.removeValue(forKey: identity)
        }
    }

    private func scheduleResponseReceiptDismissal(
        _ receipt: ActionResponseReceipt,
        for identity: TaskIdentity
    ) {
        let animation = Motion.respectingReducedMotion(
            reduceMotion,
            preferred: Motion.contentReveal
        )

        // The Hook response has already been delivered. This short UI-only
        // receipt bridges the decision surface back into the task row without
        // claiming a resume before the next lifecycle event actually arrives.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            guard responseReceipts[identity]?.id == receipt.id else { return }
            withAnimation(animation) {
                _ = responseReceipts.removeValue(forKey: identity)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        // The header already names the state ("No sessions") with its mark;
        // the body only explains what will appear and offers the next step,
        // aligned under the header's text rather than repeating a mark.
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string(
                    "Agent sessions will appear here automatically.",
                    language: language
                ))
                    .font(Typo.islandBody)
                    .foregroundStyle(Palette.textSecondary)

                if let reportingNotice {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reportingNotice.title)
                            .font(Typo.islandLabel)
                            .foregroundStyle(Palette.stateWaiting)
                        Text(reportingNotice.hint)
                            .font(Typo.islandMeta)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                    .accessibilityElement(children: .combine)
                }

                if let todaySummary {
                    Text(todaySummary)
                        .font(Typo.islandMeta)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }

                Button(action: onConnectTap) {
                    HStack(spacing: 5) {
                        Text(L10n.string("Connect an agent", language: language))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(IslandQuietActionButtonStyle())
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(
            .leading,
            NotchMetrics.panelInset
                + TaskCardMetrics.horizontalPadding
                + TaskCardLeadingIdentityMetrics.statusSize
                + Self.headerMarkSpacing
        )
        .padding(.trailing, 18)
        .padding(.top, 2)
        .padding(.bottom, 16)
    }

    // MARK: - Geometry

    private var panelWidth: CGFloat {
        NotchMetrics.panelWidth(for: layout)
    }

}

private struct ActionResponseReceipt: Identifiable, Equatable {
    let id = UUID()
    let snapshot: ActionResponseReceiptSnapshot
}

/// A calm, non-interactive bridge between the decision form and the ordinary
/// running row. It confirms that the response reached the Agent while the
/// actual Hook continues immediately in the background.
private struct ActionResponseReceiptRow: View {
    let snapshot: ActionResponseReceiptSnapshot
    let isLive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: TaskCardLeadingIdentityMetrics.spacing) {
            AnimatedDotMatrixMark(
                color: Palette.stateRunning,
                size: TaskCardLeadingIdentityMetrics.statusSize,
                motion: .orbiting,
                pattern: .orbit,
                intensity: 0.96,
                isAnimated: isLive && !reduceMotion
            )
            .frame(
                width: TaskCardLeadingIdentityMetrics.statusSize,
                height: TaskCardLeadingIdentityMetrics.statusSize
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.title)
                    .font(Typo.islandTitle)
                    .foregroundStyle(Palette.warmWhite)

                Text(snapshot.detail)
                    .font(Typo.islandMeta)
                    .foregroundStyle(Palette.textSecondary)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, TaskCardMetrics.horizontalPadding)
        .frame(maxWidth: .infinity, minHeight: TaskCardMetrics.minHeight, alignment: .leading)
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.accessibilityLabel)
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
        manusConnectionStatus: .connected,
        localAgentStatus: .listening,
        apiKeyStatus: .valid,
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
        manusConnectionStatus: .connected,
        localAgentStatus: .listening,
        apiKeyStatus: .valid,
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
        manusConnectionStatus: .reconnecting,
        localAgentStatus: .starting,
        apiKeyStatus: .valid,
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
