import IslandCore
import AppKit
import ServiceManagement
import SwiftUI

/// The Welcome window's fixed geometry. Every step lays out along one central
/// axis under a floating island specimen, so moving through the tour reads as
/// the same object changing modes rather than a new screen loading.
enum OnboardingMetrics {
    static let width: CGFloat = 760
    static let height: CGFloat = 530
    static let windowRadius: CGFloat = 18
    /// Header and footer inset from the window edge.
    static let contentHorizontalPadding: CGFloat = 32
    /// The single column every step's copy, choices and action sit in.
    static let columnWidth: CGFloat = 520
    static let islandCompactWidth: CGFloat = 320
    static let islandRequestWidth: CGFloat = 372
    static let islandCompactHeight: CGFloat = 44
    /// Island radii mirror the real panel: the compact island is a capsule,
    /// the expanded one uses the panel's 22pt corner.
    static let islandRequestRadius: CGFloat = 22
}

enum OnboardingNavigationPolicy {
    static func showsSkipAction(step: Int, stepCount: Int) -> Bool {
        stepCount > 1 && step >= 0 && step < stepCount - 1
    }
}

/// Welcome, built on the 2026-09-20 "float" direction: one cream canvas, the
/// charcoal island floating on the central axis, one title, one sentence, the
/// choices that step needs and one primary action.
///
/// Step 1 is an honest example (labelled as one). Steps 2–4 are live: the
/// connection grid reads and writes real Hook configuration through the
/// shared off-main executor, and the final step reads its answer straight
/// from `TaskStore`, so the first signal a new user sees is never simulated.
struct OnboardingView: View {
    let onFinish: (_ requestsNotificationAuthorization: Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.devIslandLanguage) private var language
    @State private var store: TaskStore
    @State private var step: Int
    @State private var demo = WelcomeDemoPhase.working
    @State private var connectionStates: [String: LocalAgentHookConnectionState]
    @State private var hasLoadedConnectionStates: Bool
    @State private var connectionErrors: [String: String] = [:]
    @State private var connectionOperation = OnboardingConnectionOperationState()
    @State private var liveSignal = OnboardingLiveSignalState.waiting
    @State private var copiedCommandFeedbackID: UUID?
    @State private var showsCodexAuthorization = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

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
        liveSignalStore: TaskStore? = nil,
        initialDemo: WelcomeDemoPhase = .working
    ) {
        self.onFinish = onFinish
        _demo = State(initialValue: initialDemo)
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

            // The stage takes its natural height, so when the example island
            // opens into a request the copy below moves down with it.
            stage

            ZStack {
                stepContent
                    .id(step)
                    .transition(stepTransition)
            }
            .frame(width: OnboardingMetrics.columnWidth)
            .frame(maxHeight: .infinity, alignment: .top)

            footer
        }
        .frame(width: OnboardingMetrics.width, height: OnboardingMetrics.height)
        .background(WindowCanvas())
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
            .strokeBorder(Palette.Window.hairlineStrong, lineWidth: 0.75)
        }
        .foregroundStyle(Palette.Window.ink)
        .tint(Palette.Window.ink)
        .preferredColorScheme(.light)
        .onAppear(perform: loadInstalledSources)
        .onChange(of: observedLiveSignal, initial: true) { _, latched in
            guard latched != liveSignal else { return }
            withAnimation(
                Motion.respectingReducedMotion(reduceMotion, preferred: Motion.contentReveal)
            ) {
                liveSignal = latched
            }
        }
        .sheet(isPresented: $showsCodexAuthorization) {
            CodexHookAuthorizationSheet(onAuthorized: loadInstalledSources)
        }
        .onDisappear {
            // Any managed-config write already in progress is allowed to
            // finish atomically, but this departed view no longer owns its
            // result or a late read-only scan.
            connectionOperation.invalidate()
        }
    }

    // MARK: - Window chrome

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)

            Text("Dev Island")
                .font(Typo.bodyStrong)
                .foregroundStyle(Palette.Window.ink)

            Spacer()

            Button {
                onFinish(false)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.Window.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle(pressedScale: 0.96))
            .pointingHandCursor()
            .keyboardShortcut(.cancelAction)
            .help(L10n.string("Close welcome tour", language: language))
            .accessibilityLabel(L10n.string("Close welcome tour", language: language))
        }
        .padding(.horizontal, OnboardingMetrics.contentHorizontalPadding - 8)
        .padding(.leading, 8)
        .frame(height: 56)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            stepTrack

            Text(L10n.string(stepName, language: language))
                .font(Typo.callout)
                .foregroundStyle(Palette.Window.textSecondary)
                .padding(.leading, 4)

            Spacer()

            if step == 0 {
                Button(L10n.string("Skip to setup", language: language)) {
                    move(to: 1)
                }
                .buttonStyle(.window(.quiet))
            } else {
                Button(L10n.string("Back", language: language)) {
                    move(to: step - 1)
                }
                .buttonStyle(.window(.quiet))
            }
        }
        .padding(.horizontal, OnboardingMetrics.contentHorizontalPadding)
        .frame(height: 56)
    }

    private var stepName: String {
        switch step {
        case 0: return "See it first"
        case 1: return "Connect"
        case 2: return "Reminders"
        default: return "First signal"
        }
    }

    private var stepTrack: some View {
        HStack(spacing: 6) {
            ForEach(0..<stepCount, id: \.self) { index in
                Capsule()
                    .fill(index == step ? Palette.Window.ink : Palette.Window.hairlineStrong)
                    .frame(width: index == step ? 18 : 5, height: 5)
            }
        }
        .animation(reduceMotion ? nil : Motion.tourStep, value: step)
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

    // MARK: - Stage

    /// The island floats on the window's axis above a soft shadow of itself.
    /// The label above it says, in every step, whether what it shows is an
    /// example or live.
    private var stage: some View {
        VStack(spacing: 14) {
            Text(L10n.string(stageLabel, language: language))
                .font(Typo.caption.weight(.medium))
                .foregroundStyle(Palette.Window.textTertiary)
                // Drawn above the island's glow, which reaches up behind it.
                .zIndex(1)

            WelcomeIslandSpecimen(
                content: islandContent,
                isLive: !reduceMotion,
                allowsDefaultAction: step == 0 && demo == .asking,
                onAllow: { resolveDemo() },
                onDeny: { resolveDemo() }
            )
            .background { halo }
            .animation(
                reduceMotion ? nil : Motion.islandMorph,
                value: islandContent.isRequest
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 28)
    }

    /// A soft warm glow centered on the floating island, the one thing
    /// painted on the canvas. It sits only behind the island.
    private var halo: some View {
        Rectangle()
            .fill(
                EllipticalGradient(
                    stops: [
                        .init(color: Sand.s150.opacity(0.85).color, location: 0),
                        .init(color: Sand.s150.opacity(0.35).color, location: 0.55),
                        .init(color: Sand.s150.opacity(0).color, location: 1),
                    ],
                    center: .center,
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.5
                )
            )
            .frame(width: 640, height: 200)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var stageLabel: String {
        switch step {
        case 0: return "A small space at the top of your screen"
        case 1: return "Live connection status"
        case 2: return "Example"
        default: return "Live"
        }
    }

    private var islandContent: WelcomeIslandSpecimen.Content {
        switch step {
        case 0:
            switch demo {
            case .working:
                return .compact(
                    state: .running,
                    title: L10n.string("Prepare release build", language: language),
                    trailing: L10n.sessionCount(3, language: language)
                )
            case .asking:
                return .request(
                    label: L10n.string("Approval", language: language),
                    context: L10n.string("Claude Code · Prepare release build", language: language),
                    title: L10n.string("Allow shell command?", language: language),
                    command: "npm run build"
                )
            case .resumed:
                return .compact(
                    state: .running,
                    title: L10n.string("Back to work", language: language),
                    trailing: L10n.sessionCount(3, language: language)
                )
            }
        case 1:
            return .compact(
                state: connectionIslandState,
                title: connectionSummary,
                trailing: nil
            )
        case 2:
            return completions
                ? .compact(
                    state: .completed,
                    title: L10n.string("Response finished", language: language),
                    trailing: nil
                )
                : .compact(
                    state: .waiting,
                    title: L10n.string("Allow shell command?", language: language),
                    trailing: nil
                )
        default:
            return .compact(
                state: liveSignalBarState,
                title: liveSignalIslandTitle,
                trailing: nil
            )
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: overviewStep
        case 1: connectionsStep
        case 2: remindersStep
        default: firstSignalStep
        }
    }

    private func stepCopy(title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(Typo.display)
                .tracking(-0.8)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(detail)
                .font(Typo.lead)
                .foregroundStyle(Palette.Window.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // Step 1 — an example of the one moment the product exists for.

    private var overviewStep: some View {
        VStack(spacing: 24) {
            stepCopy(title: overviewTitle, detail: overviewDetail)

            // While the example asks, the island's own Allow button is the
            // step's one primary action (and owns Return).
            if demo != .asking {
                Button {
                    advanceDemo()
                } label: {
                    Text(L10n.string(overviewAction, language: language))
                }
                .buttonStyle(.window(.primary, size: .large))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.top, 8)
    }

    private var overviewTitle: String {
        switch demo {
        case .working: return L10n.string("It works. You focus.", language: language)
        case .asking: return L10n.string("When it needs you, it asks.", language: language)
        case .resumed: return L10n.string("One answer, and it keeps going.", language: language)
        }
    }

    private var overviewDetail: String {
        switch demo {
        case .working:
            return L10n.string(
                "Agent progress stays at the top of your screen. When a session needs you, the island says so.",
                language: language
            )
        case .asking:
            return L10n.string(
                "Answer it right on the island. No hunting through terminal windows.",
                language: language
            )
        case .resumed:
            return L10n.string(
                "The island folds back and stays quiet until the next time you are needed.",
                language: language
            )
        }
    }

    private var overviewAction: String {
        demo == .working ? "Show me a request" : "Choose my agents"
    }

    private func advanceDemo() {
        switch demo {
        case .working:
            setDemo(.asking)
        case .asking:
            resolveDemo()
        case .resumed:
            move(to: 1)
        }
    }

    private func resolveDemo() {
        guard demo == .asking else { return }
        setDemo(.resumed)
    }

    private func setDemo(_ phase: WelcomeDemoPhase) {
        withAnimation(
            Motion.respectingReducedMotion(reduceMotion, preferred: Motion.contentReveal)
        ) {
            demo = phase
        }
    }

    // Step 2 — real connections.

    private var connectionsStep: some View {
        VStack(spacing: 22) {
            stepCopy(
                title: L10n.string("Bring your tools onto the island.", language: language),
                detail: L10n.string(
                    "Connect the ones you use. You can add others later in Settings.",
                    language: language
                )
            )

            connectionGrid

            if updateRequiredAgents.count > 1 || connectionOperation.isBulkUpdating {
                Button(action: updateAllRequiredConnections) {
                    HStack(spacing: 6) {
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
                .buttonStyle(.window(.secondary))
                .disabled(connectionOperation.isBusy)
                .accessibilityHint(L10n.string(
                    "Refreshes every shown Dev Island-managed Hook that needs an update.",
                    language: language
                ))
            }

            Button {
                move(to: 2)
            } label: {
                Text(L10n.string("Continue", language: language))
            }
            .buttonStyle(.window(.primary, size: .large))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 8)
    }

    /// Two rows are visible at once; a longer registry scrolls instead of
    /// pushing the primary action out of the window.
    private var connectionGrid: some View {
        // The inset keeps the chips' shadows inside the scroll bounds.
        ScrollView(.vertical) {
            connectionChips
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        }
        .scrollIndicators(.automatic)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 2 * 50 + 8 + 8)
        .padding(.horizontal, -6)
    }

    private var connectionChips: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ],
            spacing: 8
        ) {
            ForEach(onboardingAgents, id: \.source) { descriptor in
                WelcomeAgentChip(
                    descriptor: descriptor,
                    connectionState: hasLoadedConnectionStates
                        ? connectionStates[descriptor.source] ?? .disconnected
                        : nil,
                    isWorking: connectionOperation.workingSources.contains(descriptor.source),
                    isInteractionDisabled: connectionOperation.isBusy,
                    errorMessage: connectionErrors[descriptor.source],
                    onEnable: { enable(descriptor) },
                    onAuthorize: { showsCodexAuthorization = true }
                )
            }

            WelcomeManusChip {
                NotificationCenter.default.post(
                    name: .islandOpenSettingsRequested,
                    object: nil
                )
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

    private var connectedSourceCount: Int {
        onboardingAgents.count { connectionStates[$0.source] == .connected }
    }

    private var needsActionSourceCount: Int {
        onboardingAgents.count {
            connectionStates[$0.source] == .updateRequired
                || connectionStates[$0.source] == .configured
        }
    }

    private var connectionSummary: String {
        guard hasLoadedConnectionStates else {
            return L10n.string("Checking…", language: language)
        }
        return LocalAgentRowPresentation.summary(
            connected: connectedSourceCount,
            needsAttention: needsActionSourceCount,
            notConnected: onboardingAgents.count - connectedSourceCount - needsActionSourceCount,
            language: language
        )
    }

    private var updateRequiredAgents: [LocalAgentDescriptor] {
        OnboardingAgentSelection.descriptorsNeedingUpdate(
            from: onboardingAgents,
            states: connectionStates
        )
    }

    private var connectionIslandState: BarState {
        guard hasLoadedConnectionStates else { return .idle }
        if needsActionSourceCount > 0 { return .waiting }
        return connectedSourceCount > 0 ? .completed : .idle
    }

    // Step 3 — what may interrupt.

    private var remindersStep: some View {
        VStack(spacing: 22) {
            stepCopy(
                title: L10n.string("Interruptions only when they matter.", language: language),
                detail: L10n.string(
                    "Choose when Dev Island may send a notification. The island itself always shows every session.",
                    language: language
                )
            )

            HStack(alignment: .top, spacing: 12) {
                WelcomeChoice(
                    title: L10n.string("When a session needs me", language: language),
                    detail: L10n.string("Waiting for input, or failed", language: language),
                    isSelected: attentionRequired && !completions
                ) {
                    attentionRequired = true
                    completions = false
                }

                WelcomeChoice(
                    title: L10n.string("Also when work finishes", language: language),
                    detail: L10n.string("Needs me, plus finished responses", language: language),
                    isSelected: attentionRequired && completions
                ) {
                    attentionRequired = true
                    completions = true
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Button {
                move(to: 3)
            } label: {
                Text(L10n.string("Continue", language: language))
            }
            .buttonStyle(.window(.primary, size: .large))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 8)
    }

    // Step 4 — the first real signal.

    private var firstSignalStep: some View {
        VStack(spacing: 20) {
            stepCopy(
                title: liveSignal.hasSeenEvent
                    ? L10n.string("Your island is listening.", language: language)
                    : L10n.string("Light up your island.", language: language),
                detail: liveSignal.hasSeenEvent
                    ? L10n.string(
                        "Real task activity has reached your island. Approval delivery needs a separate live request to confirm it.",
                        language: language
                    )
                    : L10n.string(
                        "Run one real command and watch the island answer. Nothing here is staged.",
                        language: language
                    )
            )

            if !liveSignal.hasSeenEvent {
                liveSignalInstructions
            }

            VStack(spacing: 10) {
                Button {
                    finishTour()
                } label: {
                    Text(L10n.string("Start Dev Island", language: language))
                }
                .buttonStyle(.window(.primary, size: .large))
                .keyboardShortcut(.defaultAction)

                launchAtLoginToggle
            }
        }
        .padding(.top, 8)
    }

    /// Resolved from the listener health and the states the Connections step
    /// already read from disk. Welcome never probes an Agent for this page.
    private var liveSignalRecipe: OnboardingLiveSignalRecipe {
        OnboardingLiveSignalRecipe.resolve(
            listener: store.localHookServiceStatus,
            states: hasLoadedConnectionStates ? connectionStates : [:],
            candidateSources: onboardingAgents.map(\.source),
            codexSessionMonitoringEnabled: store.codexSessionMonitoringEnabled
        )
    }

    private var liveSignalSources: Set<String> {
        OnboardingLiveSignalRecipe.signalSources(
            states: connectionStates,
            codexSessionMonitoringEnabled: store.codexSessionMonitoringEnabled
        ).intersection(Set(onboardingAgents.map(\.source)))
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

    private var liveSignalIslandTitle: String {
        switch liveSignal {
        case .waiting:
            return store.localHookServiceStatus == .listening
                ? L10n.string("Waiting for a real task", language: language)
                : L10n.string("The local listener is starting…", language: language)
        case .seen(let source):
            return L10n.format(
                "%@ is running",
                language: language,
                agentDisplayName(for: source)
            )
        case .completed(let source):
            return L10n.format(
                "%@ finished",
                language: language,
                agentDisplayName(for: source)
            )
        }
    }

    @ViewBuilder
    private var liveSignalInstructions: some View {
        VStack(spacing: 10) {
            if !hasLoadedConnectionStates {
                quietLiveSignalLine("Checking…")
            } else {
                switch liveSignalRecipe {
                case .listenerStarting:
                    quietLiveSignalLine("The local listener is starting…")

                case .command(_, let command):
                    quietLiveSignalLine("Run this in a new terminal window.")
                    liveSignalCommandRow(command)

                case .codexSessionMonitoring:
                    quietLiveSignalLine("Send a prompt in Codex. Hook authorization is only needed for approvals.")
                    if connectionStates["codex"] == .configured {
                        codexAuthorizationButton
                    }

                case .codexTrust:
                    quietLiveSignalLine("Review and authorize the Dev Island hooks, then send a prompt in Codex.")
                    codexAuthorizationButton

                case .cursorChat:
                    quietLiveSignalLine("Start an agent chat in Cursor and send any prompt.")

                case .anySession(let source):
                    Text(L10n.format(
                        "Start a session in %@ and send any prompt.",
                        language: language,
                        agentDisplayName(for: source)
                    ))
                    .font(Typo.callout)
                    .foregroundStyle(Palette.Window.textSecondary)
                    .multilineTextAlignment(.center)

                case .connectAgent:
                    quietLiveSignalLine("No agent is connected yet. Go back one step to connect one.")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var codexAuthorizationButton: some View {
        Button {
            showsCodexAuthorization = true
        } label: {
            Text(CodexTrustGuidance.actionTitle(language: language))
        }
        .buttonStyle(.window(.secondary))
        .accessibilityHint(L10n.string(
            "Review the exact commands before authorizing Dev Island hooks",
            language: language
        ))
    }

    private func quietLiveSignalLine(_ key: String) -> some View {
        Text(L10n.string(key, language: language))
            .font(Typo.callout)
            .foregroundStyle(Palette.Window.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Commands are verbatim product strings, never localized, and never
    /// executed by Dev Island: the user runs them in their own terminal.
    /// The well keeps the island's ground, the product's terminal tile.
    private func liveSignalCommandRow(_ command: String) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: command)
                .font(Typo.islandCode)
                .foregroundStyle(Palette.warmWhite)
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
                .accessibilityLabel(L10n.string("Copy command", language: language))
            }
            .buttonStyle(IslandQuietActionButtonStyle())
            .accessibilityHint(L10n.string(
                "Copies the command to the clipboard",
                language: language
            ))
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(width: 340, height: 40)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.islandTop)
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

    /// Keeping the island running is what makes "connect once, stay
    /// connected" true, so the last step offers it. It is off until the
    /// user turns it on; Dev Island never registers a login item by itself.
    private var launchAtLoginToggle: some View {
        VStack(spacing: 4) {
            Toggle(
                L10n.string("Open Dev Island when you log in", language: language),
                isOn: Binding(
                    get: { launchAtLogin },
                    set: { applyLaunchAtLogin($0) }
                )
            )
            .toggleStyle(.checkbox)
            .font(Typo.callout)
            .foregroundStyle(Palette.Window.textSecondary)

            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.Window.destructive)
            }
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = L10n.string(
                "Couldn't update Login Items. Review Login Items in System Settings.",
                language: language
            )
        }
        launchAtLogin = service.status == .enabled
    }

    private func agentDisplayName(for source: String) -> String {
        LocalAgentRegistry.all.first { $0.source == source }?.displayName ?? source
    }

    // MARK: - Navigation

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 6)),
            removal: .opacity
        )
    }

    private func move(to newStep: Int) {
        guard (0..<stepCount).contains(newStep) else { return }
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

/// The first step's example: working, then asking, then back to work.
enum WelcomeDemoPhase: Equatable {
    case working
    case asking
    case resumed
}

// MARK: - Island specimen

/// The island as it looks at the top of the screen, floating on the Welcome
/// canvas: the compact capsule, or the request card it opens into. Built from
/// the island's own palette, type roles and status matrix, not a second style.
private struct WelcomeIslandSpecimen: View {
    enum Content: Equatable {
        case compact(state: BarState, title: String, trailing: String?)
        case request(label: String, context: String, title: String, command: String)

        var isRequest: Bool {
            if case .request = self { return true }
            return false
        }
    }

    let content: Content
    let isLive: Bool
    var allowsDefaultAction = false
    let onAllow: () -> Void
    let onDeny: () -> Void

    @Environment(\.devIslandLanguage) private var language

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            switch content {
            case let .compact(state, title, trailing):
                compact(state: state, title: title, trailing: trailing)
            case let .request(label, context, title, command):
                request(label: label, context: context, title: title, command: command)
            }
        }
        .frame(width: width)
        .background { shape.fill(Palette.islandTop) }
        .overlay { shape.strokeBorder(Palette.islandBorder, lineWidth: 0.75) }
        .compositingGroup()
        .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
        .shadow(color: .black.opacity(0.16), radius: 18, y: 12)
        .accessibilityElement(children: .contain)
    }

    private var width: CGFloat {
        content.isRequest ? OnboardingMetrics.islandRequestWidth : OnboardingMetrics.islandCompactWidth
    }

    private var radius: CGFloat {
        content.isRequest
            ? OnboardingMetrics.islandRequestRadius
            : OnboardingMetrics.islandCompactHeight / 2
    }

    private func compact(state: BarState, title: String, trailing: String?) -> some View {
        HStack(spacing: 10) {
            StatusDot(state: state, size: 16)
                .frame(width: 16, height: 16)

            Text(title)
                .font(Typo.barTitle)
                .foregroundStyle(state == .waiting || state == .failed ? Palette.warmWhite : Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let trailing {
                Text(trailing)
                    .font(Typo.barCount)
                    .foregroundStyle(Palette.textTertiary)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: OnboardingMetrics.islandCompactHeight)
    }

    private func request(label: String, context: String, title: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                DotMatrixMark(color: Palette.stateWaiting, size: 12, pattern: .ring)
                    .padding(.trailing, 3)
                Text(label)
                    .font(Typo.islandLabel)
                    .foregroundStyle(Palette.stateWaiting)
                Text(verbatim: "·")
                    .font(Typo.islandMeta)
                    .foregroundStyle(Palette.textTertiary)
                Text(context)
                    .font(Typo.islandMeta)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }

            Text(title)
                .font(Typo.islandHeadline)
                .foregroundStyle(Palette.warmWhite)

            Text(verbatim: command)
                .font(Typo.islandCode)
                .foregroundStyle(Palette.warmWhite)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.islandWell)
                }

            HStack(spacing: 8) {
                Spacer()
                Button(L10n.string("Deny", language: language), action: onDeny)
                    .buttonStyle(WelcomeIslandButtonStyle(isPrimary: false))
                Button(L10n.string("Allow once", language: language), action: onAllow)
                    .buttonStyle(WelcomeIslandButtonStyle(isPrimary: true))
                    .keyboardShortcut(allowsDefaultAction ? .defaultAction : nil)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }
}

/// The island's decision buttons, at specimen scale.
private struct WelcomeIslandButtonStyle: ButtonStyle {
    let isPrimary: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.islandControl)
            .foregroundStyle(isPrimary ? Palette.islandTop : Palette.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background {
                Capsule().fill(isPrimary ? Palette.warmWhite : Color.clear)
            }
            .contentShape(Capsule())
            .scaleEffect(
                InteractionFeedbackPolicy.pressScale(
                    isPressed: configuration.isPressed,
                    pressedScale: 0.96,
                    reduceMotion: reduceMotion
                )
            )
            .animation(Motion.press, value: configuration.isPressed)
            .pointingHandCursor()
    }
}

// MARK: - Choices

/// One of two mutually exclusive options, shown as a quiet tile whose paper
/// lifts when selected.
private struct WelcomeChoice: View {
    let title: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.devIslandLanguage) private var language
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Palette.Window.ink : Palette.Window.hairlineStrong,
                            lineWidth: isSelected ? 5 : 1
                        )
                        .frame(width: 16, height: 16)
                }
                .padding(.top, 1)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Typo.bodyStrong)
                        .foregroundStyle(Palette.Window.ink)
                    Text(detail)
                        .font(Typo.callout)
                        .foregroundStyle(Palette.Window.textSecondary)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .windowSurface(
            radius: Palette.Window.Radius.group,
            tone: isSelected ? .raised : .sidebar
        )
        .overlay {
            if !isSelected && isHovering {
                RoundedRectangle(cornerRadius: Palette.Window.Radius.group, style: .continuous)
                    .strokeBorder(Palette.Window.hairlineStrong, lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
        }
        .onHover { isHovering = $0 }
        .pointingHandCursor()
        .accessibilityLabel(title)
        .accessibilityValue(L10n.string(isSelected ? "Selected" : "Not selected", language: language))
        .accessibilityHint(detail)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct WelcomeManusChip: View {
    let onOpenSettings: () -> Void
    @Environment(\.devIslandLanguage) private var language

    var body: some View {
        HStack(spacing: 10) {
            AgentStateTile(state: .disconnected, size: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text("Manus")
                    .font(Typo.bodyStrong)
                    .foregroundStyle(Palette.Window.ink)
                Text(L10n.string("Cloud · optional", language: language))
                    .font(Typo.caption)
                    .foregroundStyle(Palette.Window.textTertiary)
            }

            Spacer(minLength: 4)

            Button(L10n.string("Set up", language: language), action: onOpenSettings)
                .buttonStyle(.window(.secondary))
                .accessibilityLabel(L10n.string("Set up Manus in Settings", language: language))
                .accessibilityHint(L10n.string(
                    "Opens the optional Manus cloud connection",
                    language: language
                ))
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .windowSurface(radius: Palette.Window.Radius.group, tone: .raised)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Agent chip

private struct WelcomeAgentChip: View {
    let descriptor: LocalAgentDescriptor
    let connectionState: LocalAgentHookConnectionState?
    let isWorking: Bool
    let isInteractionDisabled: Bool
    let errorMessage: String?
    let onEnable: () -> Void
    let onAuthorize: () -> Void

    @Environment(\.devIslandLanguage) private var language

    var body: some View {
        HStack(spacing: 10) {
            AgentStateTile(state: connectionState, isBusy: isWorking, size: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(compactDisplayName)
                    .font(Typo.bodyStrong)
                    .foregroundStyle(Palette.Window.ink)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.86)
                    .layoutPriority(1)
                if showsStatusLine {
                    Text(L10n.string(statusLabel, language: language))
                        .font(Typo.caption)
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            trailing
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .windowSurface(radius: Palette.Window.Radius.group, tone: .raised)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var trailing: some View {
        if isWorking {
            ProgressView()
                .controlSize(.small)
                .frame(width: 28)
        } else if connectionState == .connected {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.Window.stateCompleted)
                .frame(width: 28, height: 24)
                .accessibilityLabel(L10n.string("Setup complete", language: language))
        } else if connectionState == .configured, descriptor.source == "codex" {
            Button(L10n.string("Authorize", language: language), action: onAuthorize)
                .buttonStyle(.window(.secondary))
                .disabled(isInteractionDisabled)
                .accessibilityLabel(CodexTrustGuidance.actionTitle(language: language))
                .accessibilityHint(L10n.format(
                    "Configured; confirm Hook trust in %@",
                    language: language,
                    descriptor.displayName
                ))
        } else if connectionState == .configured {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.Window.attentionText)
                .frame(width: 28, height: 24)
                .accessibilityLabel(L10n.format(
                    "Configured; confirm Hook trust in %@",
                    language: language,
                    descriptor.displayName
                ))
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
            Button(L10n.string(actionLabel, language: language), action: onEnable)
                .buttonStyle(.window(.secondary))
                .disabled(isInteractionDisabled)
                .accessibilityLabel(actionAccessibilityLabel)
                .accessibilityHint(actionAccessibilityHint)
        }
    }

    private var statusLabel: String {
        OnboardingConnectionStatusPresentation.compactLabel(
            state: connectionState,
            hasError: errorMessage != nil
        )
    }

    /// A chip with an action button lets the button carry the state ("Add",
    /// "Update", "Authorize"); errors always keep their line.
    private var showsStatusLine: Bool {
        if errorMessage != nil { return true }
        switch connectionState {
        case .disconnected?, .updateRequired?: return isWorking
        case .configured?: return descriptor.source != "codex" || isWorking
        case .connected?, nil: return true
        }
    }

    private var compactDisplayName: String {
        descriptor.source == "copilot-cli" ? "Copilot CLI" : descriptor.displayName
    }

    private var statusColor: Color {
        if errorMessage != nil { return Palette.Window.stateFailed }
        switch connectionState {
        case nil: return Palette.Window.textTertiary
        case .connected: return Palette.Window.stateCompleted
        case .configured: return Palette.Window.attentionText
        case .updateRequired: return Palette.Window.attentionText
        case .disconnected: return Palette.Window.textTertiary
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
    /// Welcome is a compact chip, not a diagnostics screen. Keep the visible
    /// state scannable and leave review commands to the existing
    /// accessibility description and full Settings surface.
    static func compactLabel(
        state: LocalAgentHookConnectionState?,
        hasError: Bool
    ) -> String {
        if hasError { return "Try again" }
        switch state {
        case nil: return "Checking…"
        case .connected: return "Setup complete"
        case .configured: return "Needs authorization"
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
        return Array(stable.prefix(maximumLocalAgents))
    }

    static func descriptorsNeedingUpdate(
        from descriptors: [LocalAgentDescriptor],
        states: [String: LocalAgentHookConnectionState]
    ) -> [LocalAgentDescriptor] {
        descriptors.filter { states[$0.source] == .updateRequired }
    }
}

#if PREVIEWS
#Preview("Welcome Tour") {
    OnboardingView(onFinish: { _ in })
}
#endif
