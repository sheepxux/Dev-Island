import IslandCore
import AppKit
import ServiceManagement
import SwiftUI

/// The Welcome coaching card's fixed geometry (`WelcomeTutorialCanvas`): one
/// central column for copy, choices and the primary action. `height` and the
/// island specimen widths stay for the layout tests and offscreen captures
/// that pin them; the specimen itself retired on 2026-09-23 when the tour
/// began showing its example on the real island.
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

/// The setup half of the Welcome tutorial. `WelcomeTutorialCanvas` owns the
/// full-screen stage, the card chrome and the step track; this view carries
/// one setup step's content in the card's 520pt column and keeps its live
/// state across the three steps: the connection grid reads and writes real
/// Hook configuration through the shared off-main executor, and the final
/// step reads its answer straight from `TaskStore`, so the first signal a
/// new user sees is never simulated.
struct OnboardingView: View {
    enum Step: Int, CaseIterable, Equatable {
        case connect
        case reminders
        case firstSignal
    }

    let step: Step
    let onContinue: () -> Void
    let onFinish: (_ requestsNotificationAuthorization: Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.devIslandLanguage) private var language
    @State private var store: TaskStore
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

    /// `liveSignalStore` exists so previews and offscreen snapshots can bind
    /// the final step to an inert fixture instead of the bootstrapping
    /// shared store. The App always passes nothing and observes the live one.
    init(
        step: Step = .connect,
        onContinue: @escaping () -> Void = {},
        onFinish: @escaping (_ requestsNotificationAuthorization: Bool) -> Void,
        initialHookSnapshot: LocalAgentHookHealthSnapshot? = nil,
        liveSignalStore: TaskStore? = nil
    ) {
        self.step = step
        self.onContinue = onContinue
        self.onFinish = onFinish
        _store = State(initialValue: liveSignalStore ?? TaskStore.shared)
        _connectionStates = State(initialValue: Dictionary(
            uniqueKeysWithValues: initialHookSnapshot?.agents.map {
                ($0.source, $0.state)
            } ?? []
        ))
        _hasLoadedConnectionStates = State(initialValue: initialHookSnapshot != nil)
    }

    var body: some View {
        // The host keeps this view's identity across steps so connection
        // state survives; only the content swaps.
        ZStack {
            stepContent
                .id(step)
                .transition(stepTransition)
        }
        .frame(width: OnboardingMetrics.columnWidth)
        // The column keeps the card's header/footer insets on both sides so
        // the card reads as one composition (see `WelcomeTutorialCanvas`).
        .padding(.horizontal, OnboardingMetrics.contentHorizontalPadding)
        .foregroundStyle(Palette.Window.ink)
        .tint(Palette.Window.ink)
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

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .connect: connectionsStep
        case .reminders: remindersStep
        case .firstSignal: firstSignalStep
        }
    }

    private func stepCopy(title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(Typo.display)
                .tracking(Typo.displayTracking)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(detail)
                .font(Typo.lead)
                .foregroundStyle(Palette.Window.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                // About 60 characters a line at 14pt.
                .frame(maxWidth: 430)
        }
        .frame(maxWidth: .infinity)
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

            Button(action: onContinue) {
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

    private var updateRequiredAgents: [LocalAgentDescriptor] {
        OnboardingAgentSelection.descriptorsNeedingUpdate(
            from: onboardingAgents,
            states: connectionStates
        )
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

            // Island only sends nothing, so finishing the tour does not ask
            // macOS for notification permission.
            HStack(alignment: .top, spacing: 10) {
                WelcomeChoice(
                    title: L10n.string("When I'm needed", language: language),
                    detail: L10n.string("Waiting for input, or failed", language: language),
                    isSelected: attentionRequired && !completions
                ) {
                    attentionRequired = true
                    completions = false
                }

                WelcomeChoice(
                    title: L10n.string("Also when it finishes", language: language),
                    detail: L10n.string("Plus finished responses", language: language),
                    isSelected: attentionRequired && completions
                ) {
                    attentionRequired = true
                    completions = true
                }

                WelcomeChoice(
                    title: L10n.string("Island only", language: language),
                    detail: L10n.string("No system notifications", language: language),
                    isSelected: !attentionRequired && !completions
                ) {
                    attentionRequired = false
                    completions = false
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Button(action: onContinue) {
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
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(width: 340, height: 40)
        .background(Capsule().fill(Palette.islandTop))
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
                            isSelected ? Palette.Window.ink : Palette.Window.textTertiary,
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
        .buttonStyle(PressableButtonStyle(pressedScale: 0.98))
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
            AgentStateTile(state: .disconnected, size: 24, source: "manus")

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
            AgentStateTile(state: connectionState, isBusy: isWorking, size: 24, source: descriptor.source)

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
