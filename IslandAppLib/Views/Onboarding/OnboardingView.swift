import IslandCore
import AppKit
import SwiftUI

enum OnboardingMetrics {
    static let width: CGFloat = 760
    static let height: CGFloat = 500
    static let windowRadius: CGFloat = 18
    static let contentHorizontalPadding: CGFloat = 32
    static let editorialWidth: CGFloat = 264
    static let editorialSpacing: CGFloat = 28
    static let stageWidth: CGFloat = 404
    static let stageHeight: CGFloat = 253
    static let stageRadius: CGFloat = 14
}

enum OnboardingNavigationPolicy {
    static func showsSkipAction(step: Int, stepCount: Int) -> Bool {
        stepCount > 1 && step >= 0 && step < stepCount - 1
    }
}

/// A four-step introduction built like a compact macOS instrument: one clear
/// promise, one functional specimen, and no decorative feature-card grid.
/// Every page shares the same stable geometry so moving through the tour feels
/// like changing modes on one object rather than loading a new screen. The
/// final page asks for one real command and reads the answer straight from
/// `TaskStore`, so the first signal a new user sees is never simulated.
struct OnboardingView: View {
    let onFinish: (_ requestsNotificationAuthorization: Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.devIslandLanguage) private var language
    @State private var store: TaskStore
    @State private var step: Int
    @State private var direction = 1
    @State private var connectionStates: [String: LocalAgentHookConnectionState]
    @State private var hasLoadedConnectionStates: Bool
    @State private var connectionErrors: [String: String] = [:]
    @State private var connectionOperation = OnboardingConnectionOperationState()
    @State private var liveSignal = OnboardingLiveSignalState.waiting
    @State private var copiedCommandFeedbackID: UUID?

    @AppStorage(TaskNotificationPreferences.attentionRequiredKey)
    private var attentionRequired = true
    @AppStorage(TaskNotificationPreferences.completionsKey)
    private var completions = false

    private let stepCount = 4

    /// `liveSignalStore` exists so previews and offscreen snapshots can bind
    /// the final step to an inert fixture instead of the bootstrapping
    /// shared store. The App always passes nothing and observes the live one.
    init(
        onFinish: @escaping (_ requestsNotificationAuthorization: Bool) -> Void,
        initialStep: Int = 0,
        initialHookSnapshot: LocalAgentHookHealthSnapshot? = nil,
        liveSignalStore: TaskStore? = nil
    ) {
        self.onFinish = onFinish
        _store = State(initialValue: liveSignalStore ?? TaskStore.shared)
        _step = State(initialValue: min(max(initialStep, 0), stepCount - 1))
        _connectionStates = State(initialValue: Dictionary(
            uniqueKeysWithValues: initialHookSnapshot?.agents.map {
                ($0.source, $0.state)
            } ?? []
        ))
        _hasLoadedConnectionStates = State(initialValue: initialHookSnapshot != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                stepContent
                    .id(step)
                    .transition(stepTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            footer
        }
        .frame(width: OnboardingMetrics.width, height: OnboardingMetrics.height)
        .background(tourCanvas)
        .clipShape(
            RoundedRectangle(
                cornerRadius: OnboardingMetrics.windowRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: OnboardingMetrics.windowRadius,
                style: .continuous
            )
            .stroke(
                LinearGradient(
                    colors: [
                        Palette.warmWhite.opacity(0.15),
                        Palette.warmWhite.opacity(0.055),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.75
            )
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: loadInstalledSources)
        .onDisappear {
            // Any managed-config write already in progress is allowed to
            // finish atomically, but this departed view no longer owns its
            // result or a late read-only scan.
            connectionOperation.invalidate()
        }
    }

    /// A near-achromatic studio canvas. The value shift is deliberately
    /// quieter than the state colors and exists only to separate the fixed
    /// chrome, editorial copy and live specimen without adding decoration.
    private var tourCanvas: some View {
        LinearGradient(
            stops: [
                .init(color: Palette.tourCanvasRaised, location: 0),
                .init(color: Palette.tourCanvas, location: 0.42),
                .init(color: Palette.notchBlack.opacity(0.96), location: 1),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Window chrome

    private var header: some View {
        HStack(spacing: 11) {
            brandMark

            Text("Dev Island")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.warmWhite.opacity(0.88))

            Spacer()

            stepTrack
                .padding(.trailing, 5)

            Button {
                onFinish(false)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(pressedScale: 0.98))
            .keyboardShortcut(.cancelAction)
            .help(L10n.string("Close welcome tour", language: language))
            .accessibilityLabel(L10n.string("Close welcome tour", language: language))
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
        }
    }

    private var stepTrack: some View {
        HStack(spacing: 5) {
            ForEach(0..<stepCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(
                        index == step
                            ? Palette.warmWhite.opacity(0.76)
                            : Palette.warmWhite.opacity(index < step ? 0.24 : 0.10)
                    )
                    .frame(width: index == step ? 20 : 10, height: 2)
            }
        }
        .animation(
            reduceMotion ? nil : Motion.tourStep,
            value: step
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.format(
                "Step %lld of %lld",
                language: language,
                Int64(step + 1),
                Int64(stepCount)
            )
        )
    }

    private var brandMark: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
    }

    // MARK: - Pages

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: overviewPage
        case 1: connectionsPage
        case 2: notificationsPage
        default: liveSignalPage
        }
    }

    private var overviewPage: some View {
        editorialPage(
            number: "01 / 04",
            label: "Overview",
            title: "Know when\nyou’re needed.",
            detail: "Dev Island keeps agent work in sight, then gets out of the way until a session needs you.",
            note: "One quiet signal in the menu bar."
        ) {
            overviewStage
        }
    }

    private var connectionsPage: some View {
        editorialPage(
            number: "02 / 04",
            label: "Connections",
            title: "Bring your\nagents together.",
            detail: "Connect your local tools—and keep Manus cloud work in the same quiet surface. Dev Island changes only the hooks it owns.",
            note: "Local hooks remain inspectable and reversible."
        ) {
            connectionsStage
        }
    }

    private var notificationsPage: some View {
        editorialPage(
            number: "03 / 04",
            label: "Attention",
            title: "Protect your\nfocus.",
            detail: "Choose what deserves an interruption. Dev Island stays quiet while work is moving and uses one restrained signal when you are needed.",
            note: "Signal sounds follow macOS Focus and can be muted in Settings."
        ) {
            notificationsStage
        }
    }

    private var liveSignalPage: some View {
        editorialPage(
            number: "04 / 04",
            label: "First signal",
            title: "Light up\nyour island.",
            detail: "Run one real command and watch the island answer. Nothing is staged—this is the signal you will see every day.",
            note: "Dev Island only listens. Your agent keeps running in your own terminal."
        ) {
            liveSignalStage
        }
    }

    private func editorialPage<Stage: View>(
        number: String,
        label: String,
        title: String,
        detail: String,
        note: String,
        @ViewBuilder stage: () -> Stage
    ) -> some View {
        HStack(alignment: .top, spacing: OnboardingMetrics.editorialSpacing) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Text(number)
                        .foregroundStyle(Palette.tourAccent)

                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(width: 22, height: 1)

                    Text(L10n.string(label, language: language))
                        .foregroundStyle(Palette.textSecondary)
                }
                .font(Typo.tourLabel)
                .padding(.bottom, 22)

                Text(L10n.string(title, language: language))
                    .font(Typo.tourDisplay)
                    .tracking(-1.05)
                    .foregroundStyle(Palette.warmWhite)
                    .lineSpacing(-1)
                    .accessibilityAddTraits(.isHeader)

                Text(L10n.string(detail, language: language))
                    .font(Typo.tourBody)
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)

                Spacer(minLength: 18)

                HStack(alignment: .top, spacing: 9) {
                    Rectangle()
                        .fill(Palette.tourAccent)
                        .frame(width: 18, height: 1)
                        .padding(.top, 6)

                    Text(L10n.string(note, language: language))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.textTertiary)
                        .lineSpacing(2)
                }
            }
            .frame(width: OnboardingMetrics.editorialWidth)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            stage()
                .frame(
                    width: OnboardingMetrics.stageWidth,
                    height: OnboardingMetrics.stageHeight
                )
                .background(stageSurface)
                .clipShape(stageShape)
                .overlay { stageRim }
                .shadow(color: .black.opacity(0.34), radius: 18, y: 10)
                .frame(maxHeight: .infinity, alignment: .center)
        }
        .padding(.horizontal, OnboardingMetrics.contentHorizontalPadding)
        .padding(.vertical, 28)
    }

    // MARK: Overview specimen

    private var overviewStage: some View {
        VStack(spacing: 0) {
            stageHeader(title: "Current signal", trailing: "Live")

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)

            compactIslandPreview
                .padding(.horizontal, 18)
                .padding(.vertical, 17)

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)

            signalRow(title: "Running", detail: "3 sessions", state: .running)
            rowDivider
            signalRow(title: "Needs attention", detail: "None", state: .waiting)
            rowDivider
            signalRow(title: "Completed", detail: "2 today", state: .completed)
        }
        .accessibilityElement(children: .contain)
    }

    private var compactIslandPreview: some View {
        HStack(spacing: 11) {
            stageSignal(.running, size: 10, animated: true)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("Prepare release build", language: language))
                    .font(Typo.tourStageTitle)
                    .foregroundStyle(Palette.warmWhite.opacity(0.9))
                Text(L10n.string("Codex · Running tests", language: language))
                    .font(Typo.tourLabel)
                    .foregroundStyle(Palette.textTertiary)
            }

            Spacer()

            Text("04:12")
                .font(Typo.tourLabel)
                .foregroundStyle(Palette.textSecondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 17)
        .frame(height: 58)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 3,
                bottomLeadingRadius: 14,
                bottomTrailingRadius: 14,
                topTrailingRadius: 3,
                style: .continuous
            )
                .fill(Palette.notchBlack)
                .overlay {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 3,
                        bottomLeadingRadius: 14,
                        bottomTrailingRadius: 14,
                        topTrailingRadius: 3,
                        style: .continuous
                    )
                        .stroke(Palette.warmWhite.opacity(0.10), lineWidth: 0.75)
                }
        )
    }

    private func signalRow(title: String, detail: String, state: BarState) -> some View {
        HStack(spacing: 10) {
            stageSignal(state, size: 8)

            Text(L10n.string(title, language: language))
                .font(Typo.tourStageBody.weight(.medium))
                .foregroundStyle(Palette.warmWhite.opacity(0.78))

            Spacer()

            Text(L10n.string(detail, language: language))
                .font(Typo.tourLabel)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, 18)
        .frame(height: 37)
    }

    // MARK: Connection specimen

    private var connectionsStage: some View {
        VStack(spacing: 0) {
            connectionStageHeader

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 0),
                    GridItem(.flexible(), spacing: 0),
                ],
                spacing: 0
            ) {
                ForEach(Array(onboardingAgents.enumerated()), id: \.element.source) { item in
                    OnboardingAgentCell(
                        descriptor: item.element,
                        connectionState: hasLoadedConnectionStates
                            ? connectionStates[item.element.source] ?? .disconnected
                            : nil,
                        isWorking: connectionOperation.workingSources.contains(
                            item.element.source
                        ),
                        isInteractionDisabled: connectionOperation.isBusy,
                        errorMessage: connectionErrors[item.element.source],
                        onEnable: { enable(item.element) }
                    )
                    .frame(height: connectionCellHeight)
                    .overlay(alignment: .trailing) {
                        if item.offset.isMultiple(of: 2) {
                            Rectangle()
                                .fill(Palette.hairline)
                                .frame(width: 1)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if item.offset / 2 < connectionRowCount - 1 {
                            Rectangle()
                                .fill(Palette.hairline)
                                .frame(height: 1)
                        }
                    }
                }

                OnboardingManusCell {
                    NotificationCenter.default.post(
                        name: .islandOpenSettingsRequested,
                        object: nil
                    )
                }
                .frame(height: connectionCellHeight)
                .overlay(alignment: .bottom) {
                    if onboardingAgents.count / 2 < connectionRowCount - 1 {
                        Rectangle()
                            .fill(Palette.hairline)
                            .frame(height: 1)
                    }
                }
            }
        }
    }

    /// The Welcome flow stays intentionally bounded even as the connector
    /// registry grows; Settings remains the complete management surface.
    /// Stable connectors must never disappear merely because a new Preview
    /// row was inserted earlier in the registry.
    private var onboardingAgents: [LocalAgentDescriptor] {
        OnboardingAgentSelection.descriptors(from: LocalAgentRegistry.all)
    }

    private var connectionRowCount: Int {
        max(1, Int(ceil(Double(onboardingAgents.count + 1) / 2)))
    }

    private var connectionCellHeight: CGFloat {
        (OnboardingMetrics.stageHeight - 47) / CGFloat(connectionRowCount)
    }

    private var connectedSourceCount: Int {
        onboardingAgents.count { connectionStates[$0.source] == .connected }
    }

    private var updateRequiredSourceCount: Int {
        onboardingAgents.count { connectionStates[$0.source] == .updateRequired }
    }

    private var updateRequiredAgents: [LocalAgentDescriptor] {
        OnboardingAgentSelection.descriptorsNeedingUpdate(
            from: onboardingAgents,
            states: connectionStates
        )
    }

    private var configuredSourceCount: Int {
        onboardingAgents.count { connectionStates[$0.source] == .configured }
    }

    private var connectionSummary: String {
        guard hasLoadedConnectionStates else {
            return L10n.string("Checking…", language: language)
        }
        return L10n.agentConnectionSummary(
            connected: connectedSourceCount,
            updateRequired: updateRequiredSourceCount,
            configured: configuredSourceCount,
            language: language
        )
    }

    private var connectionStageHeader: some View {
        HStack(spacing: 10) {
            Text(L10n.string("Agent sources", language: language))
                .font(Typo.tourStageTitle)
                .foregroundStyle(Palette.warmWhite.opacity(0.84))

            Spacer()

            Text(connectionSummary)
                .font(Typo.tourLabel)
                .foregroundStyle(Palette.textTertiary)

            if updateRequiredSourceCount > 1 || connectionOperation.isBulkUpdating {
                Button(action: updateAllRequiredConnections) {
                    HStack(spacing: 5) {
                        if connectionOperation.isBulkUpdating {
                            ProgressView()
                                .controlSize(.mini)
                                .accessibilityHidden(true)
                        }
                        Text(L10n.string(
                            connectionOperation.isBulkUpdating ? "Updating…" : "Update all",
                            language: language
                        ))
                    }
                }
                .buttonStyle(AgentConnectButtonStyle())
                .disabled(connectionOperation.isBusy)
                .accessibilityHint(L10n.string(
                    "Refreshes every shown Dev Island-managed Hook that needs an update.",
                    language: language
                ))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
    }

    // MARK: Notification specimen

    private var notificationsStage: some View {
        VStack(spacing: 0) {
            stageHeader(title: "Notifications", trailing: "Your choice")

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)

            notificationRow(
                title: "Needs input or failed",
                detail: "Recommended",
                state: .waiting,
                isOn: $attentionRequired
            )

            rowDivider
                .padding(.leading, 45)

            notificationRow(
                title: "Task completed",
                detail: "Off by default",
                state: .completed,
                isOn: $completions
            )

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)

            HStack(spacing: 9) {
                stageSignal(.waiting, size: 8, animated: true)
                Text(L10n.string(
                    "Codex · Waiting for approval",
                    language: language
                ))
                    .font(Typo.tourStageBody)

                Spacer()

                Text(L10n.string("Needs input", language: language))
                    .font(Typo.tourLabel)
                    .foregroundStyle(Palette.stateWaiting)
            }
            .foregroundStyle(Palette.textTertiary)
            .padding(.horizontal, 16)
            .frame(height: 52, alignment: .leading)
        }
    }

    private func notificationRow(
        title: String,
        detail: String,
        state: BarState,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                stageSignal(state, size: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string(title, language: language))
                        .font(Typo.tourStageTitle)
                        .foregroundStyle(Palette.warmWhite.opacity(0.82))
                    Text(L10n.string(detail, language: language))
                        .font(Typo.tourStageBody)
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            Spacer(minLength: 16)

            Toggle(L10n.string(title, language: language), isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Palette.tourAccent)
                .accessibilityLabel(L10n.string(title, language: language))
                .accessibilityHint(L10n.string(detail, language: language))
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76)
    }

    // MARK: Live signal specimen

    /// Resolved from the listener health and the states the Connections step
    /// already read from disk. Welcome never probes an Agent for this page.
    private var liveSignalRecipe: OnboardingLiveSignalRecipe {
        OnboardingLiveSignalRecipe.resolve(
            listener: store.localHookServiceStatus,
            states: hasLoadedConnectionStates ? connectionStates : [:],
            candidateSources: onboardingAgents.map(\.source)
        )
    }

    private var liveSignalSources: Set<String> {
        OnboardingLiveSignalRecipe.signalSources(states: connectionStates)
    }

    /// Derived from the live store on every change; `onChange` fires only
    /// when the latch actually moves, so unrelated task churn never
    /// re-animates the stage and a removed session never resets it.
    private var observedLiveSignal: OnboardingLiveSignalState {
        liveSignal.advanced(with: store.tasks, sources: liveSignalSources)
    }

    private var liveSignalBarState: BarState {
        switch liveSignal {
        case .waiting: return .idle
        case .seen: return .running
        case .completed: return .completed
        }
    }

    private var liveSignalStage: some View {
        VStack(spacing: 0) {
            stageHeader(title: "Your first signal", trailing: liveSignalTrailingLabel)

            rowDivider

            liveSignalStatusRow

            rowDivider

            liveSignalInstructions
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onChange(of: observedLiveSignal, initial: true) { _, latched in
            guard latched != liveSignal else { return }
            withAnimation(
                Motion.respectingReducedMotion(reduceMotion, preferred: Motion.contentReveal)
            ) {
                liveSignal = latched
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var liveSignalTrailingLabel: String {
        switch liveSignal {
        case .waiting:
            return store.localHookServiceStatus == .listening ? "Listening" : "Starting…"
        case .seen:
            return "Running"
        case .completed:
            return "Completed"
        }
    }

    private var liveSignalStatusRow: some View {
        HStack(spacing: 12) {
            ZStack {
                stageSignal(liveSignalBarState, size: 12, animated: true)
                    .id(liveSignal)
                    .transition(.opacity)
            }
            .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(liveSignalTitle)
                    .font(Typo.tourStageTitle)
                    .foregroundStyle(Palette.warmWhite.opacity(0.9))
                Text(liveSignalDetail)
                    .font(Typo.tourLabel)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
    }

    private var liveSignalTitle: String {
        liveSignal.hasSeenEvent
            ? L10n.string("Your island is live.", language: language)
            : L10n.string("Nothing yet.", language: language)
    }

    private var liveSignalDetail: String {
        switch liveSignal {
        case .waiting:
            return L10n.string(
                "The island stays idle until a real event lands.",
                language: language
            )
        case .seen(let source):
            return L10n.format(
                "%@ is running. Look at the menu bar.",
                language: language,
                agentDisplayName(for: source)
            )
        case .completed(let source):
            return L10n.format(
                "%@ finished. That is the whole loop.",
                language: language,
                agentDisplayName(for: source)
            )
        }
    }

    @ViewBuilder
    private var liveSignalInstructions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !hasLoadedConnectionStates {
                quietLiveSignalLine("Checking…")
            } else {
                switch liveSignalRecipe {
                case .listenerStarting:
                    quietLiveSignalLine("The local listener is starting…")

                case .command(_, let command):
                    liveSignalInstruction(
                        "Run this in a new terminal window. The island turns Running, then Completed."
                    )
                    liveSignalCommandRow(command)

                case .codexTrust(let command):
                    liveSignalInstruction("Run this in a new terminal window.")
                    liveSignalCommandRow(command)
                    liveSignalInstruction(
                        L10n.format(
                            "Then type %@, trust only the Dev Island entries, and send any prompt.",
                            language: language,
                            "/hooks"
                        ),
                        isLocalized: true
                    )

                case .cursorChat:
                    liveSignalInstruction(
                        "Start an agent chat in Cursor and send any prompt. The island lights up as soon as the agent begins."
                    )

                case .anySession(let source):
                    liveSignalInstruction(
                        L10n.format(
                            "Start a session in %@ and send any prompt. The island lights up as soon as the agent begins.",
                            language: language,
                            agentDisplayName(for: source)
                        ),
                        isLocalized: true
                    )

                case .connectAgent:
                    liveSignalInstruction(
                        "No agent is connected yet. Go back one step to connect one, then return here."
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func quietLiveSignalLine(_ key: String) -> some View {
        Text(L10n.string(key, language: language))
            .font(Typo.tourStageBody)
            .foregroundStyle(Palette.textTertiary)
    }

    private func liveSignalInstruction(
        _ copy: String,
        isLocalized: Bool = false
    ) -> some View {
        Text(isLocalized ? copy : L10n.string(copy, language: language))
            .font(Typo.tourStageBody)
            .foregroundStyle(Palette.textSecondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Commands are verbatim product strings, never localized, and never
    /// executed by Dev Island: the user runs them in their own terminal.
    private func liveSignalCommandRow(_ command: String) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: command)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.warmWhite.opacity(0.9))
                .lineLimit(1)
                .textSelection(.enabled)

            Spacer(minLength: 8)

            Button {
                copyLiveSignalCommand(command)
            } label: {
                Text(L10n.string(
                    copiedCommandFeedbackID == nil ? "Copy" : "Copied",
                    language: language
                ))
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityLabel(L10n.string("Copy command", language: language))
            }
            .buttonStyle(AgentConnectButtonStyle())
            .accessibilityHint(L10n.string(
                "Copies the command to the clipboard",
                language: language
            ))
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.notchBlack)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Palette.warmWhite.opacity(0.10), lineWidth: 0.75)
                }
        )
    }

    private func copyLiveSignalCommand(_ command: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)

        let feedbackID = UUID()
        copiedCommandFeedbackID = feedbackID
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            // Only the timer that created this feedback may clear it.
            if copiedCommandFeedbackID == feedbackID {
                copiedCommandFeedbackID = nil
            }
        }
    }

    private func agentDisplayName(for source: String) -> String {
        LocalAgentRegistry.all.first { $0.source == source }?.displayName ?? source
    }

    private func stageSignal(
        _ state: BarState,
        size: CGFloat,
        animated: Bool = false
    ) -> some View {
        AnimatedDotMatrixMark(
            color: state.color,
            size: size,
            motion: state.matrixMotion,
            pattern: state.matrixPattern,
            intensity: state.matrixIntensity,
            isAnimated: animated && !reduceMotion
        )
    }

    private func stageHeader(title: String, trailing: String) -> some View {
        HStack(spacing: 10) {
            Text(L10n.string(title, language: language))
                .font(Typo.tourStageTitle)
                .foregroundStyle(Palette.warmWhite.opacity(0.84))

            Spacer()

            Text(L10n.string(trailing, language: language))
                .font(Typo.tourLabel)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
    }

    private var stageShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: OnboardingMetrics.stageRadius,
            style: .continuous
        )
    }

    private var stageSurface: some View {
        stageShape.fill(
            LinearGradient(
                colors: [Palette.tourPanelRaised, Palette.tourPanel],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var stageRim: some View {
        stageShape.stroke(
            LinearGradient(
                colors: [
                    Palette.warmWhite.opacity(0.12),
                    Palette.warmWhite.opacity(0.045),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: 0.75
        )
    }

    // MARK: - Navigation

    private var footer: some View {
        HStack(spacing: 10) {
            if OnboardingNavigationPolicy.showsSkipAction(
                step: step,
                stepCount: stepCount
            ) {
                Button {
                    onFinish(false)
                } label: {
                    Text(L10n.string("Skip tour", language: language))
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.textTertiary)
            }

            Spacer()

            Button {
                move(to: step - 1)
            } label: {
                Text(L10n.string("Back", language: language))
            }
                .buttonStyle(TourSecondaryButtonStyle())
                .opacity(step > 0 ? 1 : 0)
                .allowsHitTesting(step > 0)
                .accessibilityHidden(step == 0)

            Button {
                if step == stepCount - 1 {
                    finishTour()
                } else {
                    move(to: step + 1)
                }
            } label: {
                Text(L10n.string(actionTitle, language: language))
            }
            .buttonStyle(TourPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
        }
    }

    private var actionTitle: String {
        step == stepCount - 1 ? "Start Dev Island" : "Continue"
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: CGFloat(direction * 6))),
            removal: .opacity.combined(with: .offset(x: CGFloat(direction * -3)))
        )
    }

    private func move(to newStep: Int) {
        guard (0..<stepCount).contains(newStep) else { return }
        direction = newStep > step ? 1 : -1
        withAnimation(
            Motion.respectingReducedMotion(reduceMotion, preferred: Motion.tourStep)
        ) {
            step = newStep
        }
    }

    private func finishTour() {
        // Authorization is requested by the window owner only after its exit
        // animation completes, so the system sheet never overlaps the tour.
        onFinish(true)
    }

    // MARK: - Local connections

    private func loadInstalledSources() {
        guard let refreshID = connectionOperation.beginRefresh() else { return }

        Task { @MainActor in
            let snapshot = await LocalAgentConfigurationExecutor.run(
                priority: .userInitiated
            ) {
                OnboardingConnectionWorker.inspect()
            }
            guard connectionOperation.completeRefresh(id: refreshID) else {
                return
            }
            connectionStates = Dictionary(uniqueKeysWithValues: snapshot.agents.map {
                ($0.source, $0.state)
            })
            hasLoadedConnectionStates = true
        }
    }

    private func enable(_ descriptor: LocalAgentDescriptor) {
        install([descriptor])
    }

    private func updateAllRequiredConnections() {
        guard !connectionOperation.isBusy,
              updateRequiredAgents.count > 1 else { return }
        install(updateRequiredAgents, isBulkOperation: true)
    }

    private func install(
        _ descriptors: [LocalAgentDescriptor],
        isBulkOperation: Bool = false
    ) {
        let candidates = descriptors
        let sources = Set(candidates.map(\.source))
        guard let mutationID = connectionOperation.beginMutation(
            sources: sources,
            isBulk: isBulkOperation
        ) else { return }

        for source in sources {
            connectionErrors[source] = nil
        }

        Task { @MainActor in
            let outcome = await LocalAgentConfigurationExecutor.run(
                priority: .userInitiated
            ) {
                OnboardingConnectionWorker.install(candidates)
            }
            guard connectionOperation.completeMutation(id: mutationID) else {
                return
            }
            applyMutationOutcome(outcome, targetSources: sources)
        }
    }

    private func applyMutationOutcome(
        _ outcome: OnboardingConnectionMutationOutcome,
        targetSources: Set<String>
    ) {
        if reduceMotion {
            applyMutationOutcomeState(outcome, targetSources: targetSources)
        } else {
            withAnimation(Motion.contentReveal) {
                applyMutationOutcomeState(outcome, targetSources: targetSources)
            }
        }
    }

    private func applyMutationOutcomeState(
        _ outcome: OnboardingConnectionMutationOutcome,
        targetSources: Set<String>
    ) {
        connectionStates = Dictionary(uniqueKeysWithValues: outcome.snapshot.agents.map {
            ($0.source, $0.state)
        })
        hasLoadedConnectionStates = true

        for source in targetSources {
            connectionErrors[source] = outcome.failedSources.contains(source)
                ? L10n.string(
                    "Could not update this agent’s configuration.",
                    language: language
                )
                : nil
        }
    }
}

private struct OnboardingManusCell: View {
    let onOpenSettings: () -> Void
    @Environment(\.devIslandLanguage) private var language

    var body: some View {
        HStack(spacing: 9) {
            AgentLogoBadge(source: "manus", size: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text("Manus")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.warmWhite.opacity(0.86))
                Text(L10n.string("Cloud · optional", language: language))
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(Palette.textTertiary)
            }

            Spacer(minLength: 4)

            Button(action: onOpenSettings) {
                Text(L10n.string("Set up", language: language))
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityLabel(L10n.string(
                        "Set up Manus in Settings",
                        language: language
                    ))
            }
            .buttonStyle(AgentConnectButtonStyle())
            .accessibilityHint(L10n.string(
                "Opens the optional Manus cloud connection",
                language: language
            ))
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Agent connection row

private struct OnboardingAgentCell: View {
    let descriptor: LocalAgentDescriptor
    let connectionState: LocalAgentHookConnectionState?
    let isWorking: Bool
    let isInteractionDisabled: Bool
    let errorMessage: String?
    let onEnable: () -> Void

    @Environment(\.devIslandLanguage) private var language

    var body: some View {
        HStack(spacing: 9) {
            AgentLogoBadge(source: descriptor.source, size: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(compactDisplayName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.warmWhite.opacity(0.86))
                    .lineLimit(1)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.86)
                    .layoutPriority(1)
                Text(L10n.string(statusLabel, language: language))
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if isWorking {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28)
            } else if connectionState == .connected || connectionState == .configured {
                Image(systemName: connectionState == .connected ? "checkmark" : "ellipsis")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(
                        connectionState == .connected
                            ? Palette.stateCompleted
                            : Palette.stateWaiting
                    )
                    .frame(width: 28, height: 24)
                    .accessibilityLabel(
                        connectionState == .connected
                            ? L10n.string("Connected", language: language)
                            : L10n.format(
                                "Configured; confirm Hook trust in %@",
                                language: language,
                                descriptor.displayName
                            )
                    )
            } else if connectionState == nil {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 28)
                    .accessibilityLabel(
                        L10n.format(
                            "Checking %@ connection",
                            language: language,
                            descriptor.displayName
                        )
                    )
            } else {
                Button(action: onEnable) {
                    Text(L10n.string(actionLabel, language: language))
                        .font(.system(size: 9, weight: .semibold))
                        .accessibilityLabel(actionAccessibilityLabel)
                }
                    .buttonStyle(AgentConnectButtonStyle())
                    .disabled(isInteractionDisabled)
                    .accessibilityHint(actionAccessibilityHint)
            }
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var statusLabel: String {
        OnboardingConnectionStatusPresentation.compactLabel(
            state: connectionState,
            hasError: errorMessage != nil
        )
    }

    private var compactDisplayName: String {
        descriptor.source == "copilot-cli" ? "Copilot CLI" : descriptor.displayName
    }

    private var statusColor: Color {
        if errorMessage != nil { return Palette.stateFailed }
        switch connectionState {
        case nil: return Palette.textTertiary
        case .connected: return Palette.stateCompleted
        case .configured: return Palette.stateWaiting
        case .updateRequired: return Palette.stateWaiting
        case .disconnected: return Palette.textTertiary
        }
    }

    private var actionAccessibilityLabel: String {
        L10n.format(
            connectionState == .updateRequired
                ? "Update %@ connection"
                : "Connect %@",
            language: language,
            descriptor.displayName
        )
    }

    private var actionLabel: String {
        if errorMessage != nil { return "Retry" }
        return connectionState == .updateRequired ? "Update" : "Add"
    }

    private var actionAccessibilityHint: String {
        L10n.format(
            connectionState == .updateRequired
                ? "Refreshes Dev Island's managed hooks without changing other %@ settings"
                : "Adds Dev Island's managed hooks for %@",
            language: language,
            descriptor.displayName
        )
    }
}

enum OnboardingConnectionStatusPresentation {
    /// Welcome is a 202-point-wide specimen cell, not a diagnostics screen.
    /// Keep the visible state scannable and leave review commands to the
    /// existing accessibility description and full Settings surface.
    static func compactLabel(
        state: LocalAgentHookConnectionState?,
        hasError: Bool
    ) -> String {
        if hasError { return "Try again" }
        switch state {
        case nil: return "Checking…"
        case .connected: return "Connected"
        case .configured: return "Configured"
        case .updateRequired: return "Needs update"
        case .disconnected: return "Not connected"
        }
    }
}

enum OnboardingAgentSelection {
    static let maximumLocalAgents = 7

    static func descriptors(
        from all: [LocalAgentDescriptor]
    ) -> [LocalAgentDescriptor] {
        let stable = all.filter { $0.releaseStage == .stable }
        let preview = all.filter { $0.releaseStage == .preview }
        return Array((stable + preview).prefix(maximumLocalAgents))
    }

    static func descriptorsNeedingUpdate(
        from descriptors: [LocalAgentDescriptor],
        states: [String: LocalAgentHookConnectionState]
    ) -> [LocalAgentDescriptor] {
        descriptors.filter { states[$0.source] == .updateRequired }
    }
}

private struct AgentConnectButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Palette.warmWhite.opacity(configuration.isPressed ? 0.5 : 0.72))
            .padding(.horizontal, 7)
            .frame(minWidth: 42, minHeight: 26, maxHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Palette.warmWhite.opacity(configuration.isPressed ? 0.035 : 0.02))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 0.75)
                    }
            )
            .scaleEffect(
                InteractionFeedbackPolicy.pressScale(
                    isPressed: configuration.isPressed,
                    pressedScale: 0.99,
                    reduceMotion: reduceMotion
                )
            )
            .animation(
                Motion.respectingReducedMotion(
                    reduceMotion,
                    preferred: Motion.press
                ),
                value: configuration.isPressed
            )
    }
}

#if PREVIEWS
#Preview("Welcome Tour") {
    OnboardingView(onFinish: { _ in })
}
#endif
