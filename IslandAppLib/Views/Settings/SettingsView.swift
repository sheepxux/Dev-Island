import AppKit
import SwiftUI
import IslandCore
import ServiceManagement
import UniformTypeIdentifiers

/// Top-level Settings UI (CLAUDE_CLIENT.md §6 task 6). Three sections:
///
/// - **Connected Services** — Manus row with API key entry + connect/
///   disconnect controls; Claude Code, Codex and Cursor rows toggle local
///   hook installation (no API key needed).
/// - **General** — Launch at Login toggle wired through `SMAppService`.
/// - **Support** — copies or saves an aggregate-only diagnostic summary.
/// - **Footer** — Quit button (NSApp.terminate). Closing the window
///   alone won't quit, since we're an `.accessory` activation app.
///
/// Bound directly to `TaskStore.shared` so the Manus row's status dot
/// reflects live `apiKeyStatus` / `connectionStatus` without manual
/// notification plumbing.
public struct SettingsView: View {
    @State private var store = TaskStore.shared
    @State private var selectedPane: SettingsPane = .agents
    @State private var presentation = SettingsPresentation()
    @State private var diagnosticsRevealID = UUID()
    @State private var localAgentConnectionsOperation =
        LocalAgentConnectionsOperationState()
    private let initialLiveReadinessSnapshot: LocalLiveReadinessSnapshot?
    private let initialConnectionStates: [String: LocalAgentHookConnectionState]
    private let previewAppVersion: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.devIslandLanguage) private var language

    public init() {
        initialLiveReadinessSnapshot = nil
        initialConnectionStates = [:]
        previewAppVersion = nil
    }

    init(presentation: SettingsPresentation) {
        self.init()
        _presentation = State(initialValue: presentation)
    }

    #if DEBUG
    init(
        previewStore: TaskStore,
        initialPane: SettingsPane = .agents,
        initialLiveReadinessSnapshot: LocalLiveReadinessSnapshot? = nil,
        previewConnectionStates: [String: LocalAgentHookConnectionState] = [:],
        previewAppVersion: String = "0.3.0"
    ) {
        _store = State(initialValue: previewStore)
        _selectedPane = State(initialValue: initialPane)
        self.initialLiveReadinessSnapshot = initialLiveReadinessSnapshot
        self.initialConnectionStates = previewConnectionStates
        self.previewAppVersion = previewAppVersion
    }
    #endif

    public var body: some View {
        HStack(spacing: 10) {
            sidebar

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Color.clear
                            .frame(height: 0)
                            .id("settings-pane-top")

                        paneHeader
                        paneContent
                            .id(selectedPane)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .opacity.combined(with: .offset(y: 4))
                            )
                    }
                    .padding(.leading, 26)
                    .padding(.trailing, 32)
                    .padding(.top, 44)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: diagnosticsRevealID) { _, _ in
                    withAnimation(reduceMotion ? nil : Motion.contentReveal) {
                        proxy.scrollTo("settings-pane-top", anchor: .top)
                    }
                }
                .onChange(of: selectedPane) { _, _ in
                    if reduceMotion {
                        var transaction = Transaction()
                        transaction.animation = nil
                        withTransaction(transaction) {
                            proxy.scrollTo("settings-pane-top", anchor: .top)
                        }
                    } else {
                        withAnimation(Motion.contentReveal) {
                            proxy.scrollTo("settings-pane-top", anchor: .top)
                        }
                    }
                }
            }
        }
        .padding(.leading, 10)
        .padding(.vertical, 10)
        .frame(minWidth: 740, idealWidth: 800, minHeight: 540, idealHeight: 560)
        .background(WindowCanvas())
        .foregroundStyle(Palette.Window.ink)
        .tint(Palette.Window.ink)
        .preferredColorScheme(.light)
        .sheet(isPresented: $presentation.showsHistory) {
            TaskHistoryView(store: store)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)

                Text("Dev Island")
                    .font(Typo.bodyStrong)
                    .foregroundStyle(Palette.Window.ink)
            }
            .padding(.horizontal, 14)
            // The pane runs under the transparent title bar; leave the
            // traffic lights their row.
            .padding(.top, 46)
            .padding(.bottom, 16)

            VStack(spacing: 2) {
                Button {
                    presentation.showsHistory = true
                } label: {
                    Label(L10n.string("Session History", language: language), systemImage: "clock.arrow.circlepath")
                        .font(Typo.control)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                }
                .buttonStyle(SettingsSidebarButtonStyle(isSelected: false))
                .keyboardShortcut("h", modifiers: [.command, .shift])

                settingsDivider.padding(.vertical, 8)

                ForEach(SettingsPane.allCases) { pane in
                    Button {
                        withAnimation(reduceMotion ? nil : Motion.contentReveal) {
                            selectedPane = pane
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: pane.symbolName)
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 24, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                        .fill(
                                            pane == selectedPane
                                                ? Palette.Window.onInk.opacity(0.16)
                                                : Palette.Window.ink.opacity(0.06)
                                        )
                                )
                                .foregroundStyle(
                                    pane == selectedPane ? Palette.Window.onInk : Palette.Window.inkSoft
                                )
                                .accessibilityHidden(true)

                            Text(pane.title(language: language))
                                .font(Typo.control)
                                .foregroundStyle(
                                    pane == selectedPane ? Palette.Window.onInk : Palette.Window.inkSoft
                                )

                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(SettingsSidebarButtonStyle(
                        isSelected: pane == selectedPane
                    ))
                    .accessibilityValue(
                        pane == selectedPane
                            ? L10n.string("Selected", language: language)
                            : ""
                    )
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 18)

            VStack(alignment: .leading, spacing: 1) {
                Button {
                    NotificationCenter.default.post(
                        name: .islandOpenOnboardingRequested,
                        object: nil
                    )
                } label: {
                    Text(L10n.string("Welcome Tour", language: language))
                }
                .buttonStyle(SettingsSidebarUtilityButtonStyle())

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text(L10n.string("Quit Dev Island", language: language))
                }
                // Quitting preserves settings and history, so it is a neutral
                // application command rather than a destructive red action.
                .buttonStyle(SettingsSidebarUtilityButtonStyle())
                .keyboardShortcut("q", modifiers: [.command])
            }
            .padding(10)
        }
        .frame(width: 214)
        .windowSurface(radius: Palette.Window.Radius.pane, tone: .sidebar)
    }

    private var paneHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(selectedPane.title(language: language))
                .font(Typo.title)
                .tracking(Typo.titleTracking)
                .foregroundStyle(Palette.Window.ink)

            Text(selectedPane.detail(language: language))
                .font(Typo.body)
                .foregroundStyle(Palette.Window.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .id(selectedPane)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var paneContent: some View {
        switch selectedPane {
        case .agents:
            ConnectedServicesSection(
                store: store,
                showsTitle: false,
                initialLiveReadinessSnapshot: initialLiveReadinessSnapshot,
                initialConnectionStates: initialConnectionStates,
                connectionsOperation: $localAgentConnectionsOperation,
                onRevealDiagnostics: { diagnosticsRevealID = UUID() }
            )
        case .general:
            GeneralSection(showsTitle: false)
        case .notifications:
            NotificationsSection(showsTitle: false)
        case .usage:
            UsageInsightsSection(showsTitle: false)
        case .updates:
            UpdatesSection(
                showsTitle: false,
                previewAppVersion: previewAppVersion
            )
        case .support:
            SupportSection(store: store, showsTitle: false)
        }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case agents
    case general
    case notifications
    case usage
    case updates
    case support

    var id: String { rawValue }

    var indexLabel: String {
        String(format: "%02d", Self.allCases.firstIndex(of: self)! + 1)
    }

    var symbolName: String {
        switch self {
        case .agents:        return "cpu"
        case .general:       return "gearshape"
        case .notifications: return "bell"
        case .usage:         return "gauge.with.dots.needle.33percent"
        case .updates:       return "arrow.down.circle"
        case .support:       return "hand.raised"
        }
    }

    func title(language: DevIslandLanguage) -> String {
        switch self {
        case .agents:        return L10n.string("Agents", language: language)
        case .general:       return L10n.string("General", language: language)
        case .notifications: return L10n.string("Notifications", language: language)
        case .usage:         return L10n.string("Usage & Limits", language: language)
        case .updates:       return L10n.string("Updates", language: language)
        case .support:       return L10n.string("Privacy & Support", language: language)
        }
    }

    func detail(language: DevIslandLanguage) -> String {
        switch self {
        case .agents:
            return L10n.string(
                "Connect the tools you use. Task activity and approvals are checked separately.",
                language: language
            )
        case .general:
            return L10n.string(
                "What Dev Island does when you sign in to this Mac.",
                language: language
            )
        case .notifications:
            return L10n.string(
                "Interrupt only when a session needs you.",
                language: language
            )
        case .usage:
            return L10n.string(
                "Codex rate limits, read on this Mac. Prompts are never stored.",
                language: language
            )
        case .updates:
            return L10n.string(
                "Signed updates for Dev Island, verified before they install.",
                language: language
            )
        case .support:
            return L10n.string(
                "Local history, legal documents and a redacted diagnostic summary.",
                language: language
            )
        }
    }
}

private struct SettingsSidebarButtonStyle: ButtonStyle {
    let isSelected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        SettingsSidebarButtonBody(
            configuration: configuration,
            isSelected: isSelected,
            reduceMotion: reduceMotion
        )
    }
}

private struct SettingsSidebarButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let isSelected: Bool
    let reduceMotion: Bool

    @State private var isHovering = false

    var body: some View {
        configuration.label
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(background)
            )
            .animation(Motion.hoverHighlight, value: isSelected)
            .animation(Motion.press, value: configuration.isPressed)
            .animation(
                Motion.respectingReducedMotion(
                    reduceMotion,
                    preferred: Motion.hoverHighlight
                ),
                value: isHovering
            )
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .pointingHandCursor()
    }

    private var background: Color {
        if isSelected { return configuration.isPressed ? Palette.Window.inkSoft : Palette.Window.ink }
        if configuration.isPressed { return Palette.Window.pressed }
        return isHovering ? Palette.Window.hover : .clear
    }
}

private struct SettingsSidebarUtilityButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        SettingsSidebarUtilityButtonBody(
            configuration: configuration,
            reduceMotion: reduceMotion
        )
    }
}

private struct SettingsSidebarUtilityButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let reduceMotion: Bool

    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(Typo.calloutStrong)
            .foregroundStyle(isHovering ? Palette.Window.ink : Palette.Window.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                Rectangle()
                    .fill(configuration.isPressed ? Palette.Window.pressed : (isHovering ? Palette.Window.hover : .clear))
            )
            .animation(Motion.press, value: configuration.isPressed)
            .animation(
                Motion.respectingReducedMotion(
                    reduceMotion,
                    preferred: Motion.hoverHighlight
                ),
                value: isHovering
            )
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .pointingHandCursor()
    }
}

/// Keeps every Settings switch on the same two-column rhythm regardless of
/// localization or subtitle length. Native `Toggle` labels size to their
/// content on macOS; using them directly made short rows drift toward the
/// center while longer rows reached the trailing edge.
private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    @Environment(\.devIslandLanguage) private var language

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string(title, language: language))
                    .font(Typo.bodyStrong)
                Text(L10n.string(subtitle, language: language))
                    .font(Typo.caption)
                    .foregroundStyle(Palette.Window.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityHidden(true)

            Spacer(minLength: 20)

            Toggle(
                L10n.string(title, language: language),
                isOn: $isOn
            )
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Palette.Window.ink)
                .accessibilityHint(
                    L10n.string(subtitle, language: language)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
}

// MARK: - Usage insights

private struct UsageInsightsSection: View {
    var showsTitle = true
    @AppStorage("devIsland.usage.localInsightsEnabled")
    private var isEnabled = false

    @State private var usage = AgentUsageController()
    @Environment(\.devIslandLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsTitle { sectionTitle("Usage & Limits") }

            VStack(spacing: 0) {
                SettingsToggleRow(
                    title: "Local Usage Insights",
                    subtitle: "Read provider-authored rate-limit events from recent Codex activity. Off by default and never uploaded.",
                    isOn: $isEnabled
                )

                if isEnabled {
                    settingsDivider.padding(.leading, 16)
                    usageContent
                        .padding(16)
                }
            }
            .windowSurface(radius: Palette.Window.Radius.group, tone: .raised)
        }
        .onAppear {
            if isEnabled, usage.status == .idle { usage.refresh() }
        }
        .onChange(of: isEnabled) { _, enabled in
            if enabled {
                usage.refresh()
            } else {
                usage.disable()
            }
        }
    }

    @ViewBuilder
    private var usageContent: some View {
        switch usage.status {
        case .idle, .loading:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.string(
                    "Reading the latest local Codex usage snapshot…",
                    language: language
                ))
                    .font(Typo.caption)
                    .foregroundStyle(Palette.Window.textSecondary)
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                L10n.string("Reading local Codex usage", language: language)
            )

        case .available:
            if let snapshot = usage.snapshot {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        // Freshness and locality are stated once, in the
                        // footer under the limits.
                        Text("Codex")
                            .font(Typo.bodyStrong)
                        Spacer()
                        Button(L10n.string("Refresh", language: language)) {
                            usage.refresh()
                        }
                            .buttonStyle(.window(.secondary))
                    }

                    ForEach(snapshot.windows) { window in
                        usageWindow(window)
                    }

                    Text(snapshotFooter(snapshot))
                        .font(Typo.caption)
                        .foregroundStyle(Palette.Window.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        case .unavailable:
            emptyState(
                title: "No recent Codex limit snapshot",
                detail: "Run Codex once, then refresh. Dev Island does not estimate missing limits."
            )

        case .failed:
            emptyState(
                title: "Usage data unavailable",
                detail: "The local activity file could not be read. Agent monitoring is unaffected."
            )
        }
    }

    private func usageWindow(_ window: AgentUsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(windowLabel(window))
                    .font(Typo.caption.weight(.medium))
                Spacer()
                Text(L10n.format(
                    "%lld%% used",
                    language: language,
                    Int64(window.usedPercent.rounded())
                ))
                    .font(Typo.numeric)
                    .foregroundStyle(Palette.Window.ink.opacity(0.86))
            }

            ProgressView(value: window.usedPercent, total: 100)
                .progressViewStyle(.linear)
                .tint(usageTint(window.usedPercent))

            Text(resetLabel(window.resetsAt))
                .font(Typo.caption)
                .foregroundStyle(Palette.Window.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            L10n.format(
                "%@, %lld percent used, %@",
                language: language,
                windowLabel(window),
                Int64(window.usedPercent.rounded()),
                resetLabel(window.resetsAt)
            )
        )
    }

    private func emptyState(title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string(title, language: language))
                    .font(Typo.bodyStrong)
                Text(L10n.string(detail, language: language))
                    .font(Typo.caption)
                    .foregroundStyle(Palette.Window.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(L10n.string("Refresh", language: language)) { usage.refresh() }
                .buttonStyle(.window(.secondary))
        }
    }

    private func windowLabel(_ window: AgentUsageWindow) -> String {
        switch window.durationMinutes {
        case 300: return L10n.string("5-hour window", language: language)
        case 10_080: return L10n.string("Weekly window", language: language)
        default:
            if window.durationMinutes.isMultiple(of: 1_440) {
                return L10n.format(
                    "%lld-day window",
                    language: language,
                    Int64(window.durationMinutes / 1_440)
                )
            }
            if window.durationMinutes.isMultiple(of: 60) {
                return L10n.format(
                    "%lld-hour window",
                    language: language,
                    Int64(window.durationMinutes / 60)
                )
            }
            return L10n.format(
                "%lld-minute window",
                language: language,
                Int64(window.durationMinutes)
            )
        }
    }

    private func resetLabel(_ date: Date?) -> String {
        guard let date else {
            return L10n.string("Reset time not provided", language: language)
        }
        if date <= .now {
            return L10n.string("Awaiting a fresh provider snapshot", language: language)
        }
        return L10n.format(
            "Resets %@",
            language: language,
            date.formatted(.relative(presentation: .numeric).locale(language.locale))
        )
    }

    private func snapshotFooter(_ snapshot: AgentUsageSnapshot) -> String {
        let age = snapshot.observedAt.formatted(
            .relative(presentation: .numeric).locale(language.locale)
        )
        if snapshot.isStale() {
            return L10n.format(
                "Provider snapshot from %@. Values may be stale; prompts, responses and credentials are never retained.",
                language: language,
                age
            )
        }
        return L10n.format(
            "Provider snapshot from %@. Numeric limits stay on this Mac; prompts, responses and credentials are never retained.",
            language: language,
            age
        )
    }

    private func usageTint(_ usedPercent: Double) -> Color {
        if usedPercent >= 90 { return Palette.Window.stateFailed }
        if usedPercent >= 75 { return Palette.Window.stateWaiting }
        return Palette.Window.ink.opacity(0.82)
    }
}

// MARK: - Updates

private struct UpdatesSection: View {
    var showsTitle = true
    var previewAppVersion: String?
    @State private var updates = AppUpdateController.shared
    @Environment(\.devIslandLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsTitle { sectionTitle("Updates") }

            VStack(spacing: 0) {
                SettingsToggleRow(
                    title: "Check Automatically",
                    subtitle: updateStatusDescription,
                    isOn: Binding(
                        get: { updates.automaticallyChecksForUpdates },
                        set: { updates.setAutomaticallyChecksForUpdates($0) }
                    )
                )
                .disabled(!updates.canChangeAutomaticChecks)

                settingsDivider.padding(.leading, 16)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dev Island \(previewAppVersion ?? updates.currentVersion)")
                            .font(Typo.bodyStrong)
                        Text(L10n.string(
                            "Updates are verified before extraction and installation.",
                            language: language
                        ))
                            .font(Typo.caption)
                            .foregroundStyle(Palette.Window.textSecondary)
                    }

                    Spacer(minLength: 8)

                    Button(L10n.string("Check Now", language: language)) {
                        updates.checkForUpdates()
                    }
                    .buttonStyle(.window(.secondary))
                    .disabled(!updates.canCheckForUpdates)
                    .accessibilityHint(
                        L10n.string(
                            "Checks the authenticated Dev Island update feed",
                            language: language
                        )
                    )
                }
                .padding(16)
            }
            .windowSurface(radius: Palette.Window.Radius.group, tone: .raised)
        }
    }

    private var updateStatusDescription: String {
        switch updates.status {
        case .unavailable:
            return "Available in signed release builds."
        case .starting:
            return "Update service is starting."
        case .ready:
            return "Check the signed Dev Island feed once a day. No system profile is sent."
        case .checking:
            return "Checking for updates…"
        case .failed:
            return "Update service couldn't start. Restart Dev Island to try again."
        }
    }
}

// MARK: - Support

private struct SupportSection: View {
    let store: TaskStore
    var showsTitle = true
    @State private var diagnosticsOperation = SupportDiagnosticsOperationState()
    @State private var diagnosticsFeedback = SupportDiagnosticsFeedbackState()
    @State private var showHistory = false
    @State private var showClearHistoryConfirmation = false
    @State private var isClearingHistory = false
    @State private var historyMessage: String?
    @State private var selectedLegalDocument: LegalDocumentKind?
    @Environment(\.devIslandLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsTitle { sectionTitle("Support") }

            if LaunchHealthTracker.shared.previousLaunchState == .startupInterrupted {
                LaunchHealthNotice(
                    consecutiveStartupInterruptions:
                        LaunchHealthTracker.shared.consecutiveStartupInterruptions
                )
            }

            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.string("Legal Documents", language: language))
                            .font(Typo.bodyStrong)
                        Text(L10n.string(
                            "Offline review copies bundled with this build. No browser or network is required.",
                            language: language
                        ))
                            .font(Typo.caption)
                            .foregroundStyle(Palette.Window.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 8) {
                        ForEach(LegalDocumentKind.allCases) { kind in
                            Button(kind.buttonTitle(language: language)) {
                                selectedLegalDocument = kind
                            }
                            .buttonStyle(.window(.secondary))
                            .accessibilityHint(
                                L10n.string(
                                    kind == .privacy
                                        ? "Opens the exact privacy notice bundled with this app"
                                        : "Opens the exact terms bundled with this app",
                                    language: language
                                )
                            )
                        }
                    }
                }
                .padding(16)

                settingsDivider.padding(.leading, 16)

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.string("Diagnostic Summary", language: language))
                            .font(Typo.bodyStrong)
                        Text(diagnosticsFeedback.message
                             ?? L10n.string(
                                diagnosticsFeedback.copied
                                    ? "Copied — ready to paste into a support message."
                                    : "Aggregate app and session state only. No keys, prompts, paths, titles, URLs, or session IDs.",
                                language: language
                             ))
                            .font(Typo.caption)
                            .foregroundStyle(Palette.Window.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 8) {
                        Button {
                            copyDiagnostics()
                        } label: {
                            Text(L10n.string(
                                diagnosticsFeedback.copied ? "Copied" : "Copy",
                                language: language
                            ))
                        }
                        .buttonStyle(.window(.secondary))
                        .disabled(diagnosticsOperation.isBusy)
                        .accessibilityHint(
                            L10n.string(
                                "Copies a privacy-safe diagnostic summary to the clipboard",
                                language: language
                            )
                        )

                        Button(L10n.string("Save…", language: language)) {
                            saveDiagnostics()
                        }
                        .buttonStyle(.window(.secondary))
                        .disabled(diagnosticsOperation.isBusy)
                        .accessibilityHint(
                            L10n.string(
                                "Saves a privacy-safe diagnostic text file without uploading it",
                                language: language
                            )
                        )
                    }
                }
                .padding(16)

                settingsDivider.padding(.leading, 16)

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.string("Stored Task History", language: language))
                            .font(Typo.bodyStrong)
                        Text(historyMessage
                             ?? L10n.string(
                                "Remove persisted task and progress records from this Mac. Active sessions stay visible.",
                                language: language
                             ))
                            .font(Typo.caption)
                            .foregroundStyle(historyMessage == nil
                                             ? Palette.Window.textSecondary
                                             : Palette.Window.ink.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 8) {
                        Button(L10n.string("View History", language: language)) {
                            showHistory = true
                        }
                        .buttonStyle(.window(.secondary))
                        .accessibilityHint(
                            L10n.string(
                                "Opens private session history stored on this Mac",
                                language: language
                            )
                        )

                        if isClearingHistory {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 28)
                                .accessibilityLabel(
                                    L10n.string(
                                        "Clearing stored task history",
                                        language: language
                                    )
                                )
                        } else {
                            Button(
                                L10n.string("Clear", language: language),
                                role: .destructive
                            ) {
                                showClearHistoryConfirmation = true
                            }
                            .buttonStyle(.window(.secondary))
                            .accessibilityHint(
                                L10n.string(
                                    "Asks before deleting persisted task and progress records",
                                    language: language
                                )
                            )
                        }
                    }
                }
                .padding(16)
            }
            .windowSurface(radius: Palette.Window.Radius.group, tone: .raised)
        }
        .alert(
            L10n.string("Clear stored history?", language: language),
            isPresented: $showClearHistoryConfirmation
        ) {
            Button(L10n.string("Cancel", language: language), role: .cancel) {}
            Button(
                L10n.string("Clear History", language: language),
                role: .destructive
            ) {
                clearHistory()
            }
        } message: {
            Text(L10n.string(
                "This permanently removes persisted task and progress records from this Mac. Running and waiting sessions remain visible in the island.",
                language: language
            ))
        }
        .sheet(isPresented: $showHistory) {
            TaskHistoryView(store: store)
        }
        .sheet(item: $selectedLegalDocument) { kind in
            LegalDocumentSheet(kind: kind)
        }
        .onDisappear {
            // Descriptor writes already in progress finish atomically, but a
            // departed Support surface no longer owns any delayed result.
            diagnosticsOperation.invalidate()
            diagnosticsFeedback.invalidate()
        }
    }

    private func copyDiagnostics() {
        guard let operationID = diagnosticsOperation.begin(.copy) else { return }
        diagnosticsFeedback.invalidate()

        Task { @MainActor in
            let report = await diagnosticsReport()
            guard diagnosticsOperation.complete(operationID) else { return }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(report, forType: .string)
            let feedbackID = diagnosticsFeedback.showCopied()

            try? await Task.sleep(for: .seconds(2))
            diagnosticsFeedback.clear(feedbackID)
        }
    }

    private func saveDiagnostics() {
        guard let operationID = diagnosticsOperation.begin(.save) else { return }
        diagnosticsFeedback.invalidate()

        Task { @MainActor in
            let report = await diagnosticsReport()
            guard diagnosticsOperation.owns(operationID) else { return }

            let panel = NSSavePanel()
            panel.title = L10n.string(
                "Save Dev Island Diagnostics",
                language: language
            )
            panel.message = L10n.string(
                "Saves aggregate state only. Nothing is uploaded.",
                language: language
            )
            panel.prompt = L10n.string("Save", language: language)
            panel.nameFieldStringValue = SupportDiagnosticsExporter.suggestedFilename()
            panel.allowedContentTypes = [.plainText]
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.showsTagField = false

            let completion: @MainActor (NSApplication.ModalResponse) -> Void = { response in
                guard response == .OK, let destination = panel.url else {
                    diagnosticsOperation.complete(operationID)
                    return
                }

                Task { @MainActor in
                    guard diagnosticsOperation.owns(operationID) else { return }
                    let outcome = await SupportDiagnosticsIOExecutor.run(
                        priority: .userInitiated
                    ) {
                        SupportDiagnosticsExportWorker.write(report, to: destination)
                    }
                    guard diagnosticsOperation.complete(operationID) else { return }

                    switch outcome {
                    case .saved:
                        publishDiagnosticMessage(L10n.string(
                            "Saved privately to your chosen folder.",
                            language: language
                        ))
                    case let .failed(error):
                        publishDiagnosticMessage(L10n.string(
                            error.errorDescription
                                ?? "The diagnostic file couldn’t be saved.",
                            language: language
                        ))
                    }
                }
            }

            if let settingsWindow = NSApp.keyWindow {
                panel.beginSheetModal(for: settingsWindow, completionHandler: completion)
            } else {
                panel.begin(completionHandler: completion)
            }
        }
    }

    private func diagnosticsReport() async -> String {
        let connectionStatus = store.connectionStatus
        let apiKeyStatus = store.apiKeyStatus
        let tasks = store.tasks
        let listenerStatus = store.localHookServiceStatus
        let previousLaunchState = LaunchHealthTracker.shared.previousLaunchState
        let consecutiveStartupInterruptions =
            LaunchHealthTracker.shared.consecutiveStartupInterruptions
        let localAgentHooks = await SupportDiagnosticsIOExecutor.run(
            priority: .userInitiated
        ) {
            LocalAgentHookDiagnostics.snapshotResolvingVendorActivation()
        }
        return SupportDiagnostics.report(
            connectionStatus: connectionStatus,
            apiKeyStatus: apiKeyStatus,
            tasks: tasks,
            localHookServiceStatus: listenerStatus,
            localAgentHooks: localAgentHooks,
            previousLaunchState: previousLaunchState,
            consecutiveStartupInterruptions: consecutiveStartupInterruptions
        )
    }

    private func publishDiagnosticMessage(_ message: String) {
        let feedbackID = diagnosticsFeedback.showMessage(message)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            diagnosticsFeedback.clear(feedbackID)
        }
    }

    private func clearHistory() {
        guard !isClearingHistory else { return }
        isClearingHistory = true
        historyMessage = nil

        Task { @MainActor in
            let cleared = await store.clearStoredTaskHistory()
            isClearingHistory = false
            let result = L10n.string(
                cleared
                    ? "Stored history cleared. Active sessions were not interrupted."
                    : "Couldn't clear stored history. Try again after relaunching Dev Island.",
                language: language
            )
            historyMessage = result
            try? await Task.sleep(for: .seconds(4))
            if historyMessage == result {
                historyMessage = nil
            }
        }
    }
}

/// Quiet Support-only notice for a prior process that did not survive the
/// short startup-health window. It stays out of the island's attention queue
/// because the evidence cannot distinguish a quick Force Quit, power loss, an
/// OS restart, and a crash. No automatic safe mode can disrupt Agent listening.
struct LaunchHealthNotice: View {
    var consecutiveStartupInterruptions = 1
    @Environment(\.devIslandLanguage) private var language

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            DotMatrixMark(
                color: Palette.Window.stateWaiting,
                size: 11,
                pattern: .ring,
                intensity: 0.92
            )
            .padding(.top, 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string(
                    "Previous launch did not reach ready state",
                    language: language
                ))
                    .font(Typo.bodyStrong)
                Text(L10n.string(
                    "Dev Island ended before its brief startup health check completed. This can follow a quick Force Quit, restart, power loss, or a crash. No crash report was read or sent.",
                    language: language
                ))
                    .font(Typo.caption)
                    .foregroundStyle(Palette.Window.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if consecutiveStartupInterruptions >= 2 {
                    Text(L10n.string(
                        "This happened repeatedly. Keep this launch open briefly, then relaunch. If it repeats, copy the private diagnostic summary below.",
                        language: language
                    ))
                        .font(Typo.caption.weight(.medium))
                        .foregroundStyle(Palette.Window.stateWaiting.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.Window.stateWaiting.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Palette.Window.stateWaiting.opacity(0.20), lineWidth: 0.75)
                }
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Notifications

private struct NotificationsSection: View {
    var showsTitle = true
    @AppStorage(TaskNotificationPreferences.attentionRequiredKey)
    private var attentionRequired = true

    @AppStorage(TaskNotificationPreferences.completionsKey)
    private var completions = false

    @AppStorage(TaskNotificationPreferences.signalSoundsKey)
    private var signalSounds = true

    @State private var authorizationIssue: String?
    @Environment(\.devIslandLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsTitle { sectionTitle("Notifications") }

            if notificationsEnabled, let authorizationIssue {
                VStack(alignment: .leading, spacing: 10) {
                    Label(L10n.string(authorizationIssue, language: language), systemImage: "bell.slash")
                        .font(Typo.bodyStrong)
                    Text(L10n.string("Your notification preferences are saved. System banners and sounds need macOS permission; task activity remains visible in the island.", language: language))
                        .font(Typo.callout)
                        .foregroundStyle(Palette.Window.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L10n.string("Open System Settings", language: language)) {
                        openNotificationSettings()
                    }
                    .buttonStyle(.window(.secondary))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .windowSurface(radius: Palette.Window.Radius.group, tone: .attention)
            }

            VStack(spacing: 0) {
                SettingsToggleRow(
                    title: "Attention Required",
                    subtitle: "Bring the island forward when a task needs input or fails.",
                    isOn: $attentionRequired
                )

                settingsDivider.padding(.leading, 16)

                SettingsToggleRow(
                    title: "Task Completed",
                    subtitle: "Optionally notify when a task finishes.",
                    isOn: $completions
                )

                settingsDivider.padding(.leading, 16)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.string("Signal Sounds", language: language))
                            .font(Typo.bodyStrong)
                        Text(L10n.string(
                            "Brief, distinct cues for input, failure, and completion.",
                            language: language
                        ))
                            .font(Typo.caption)
                            .foregroundStyle(Palette.Window.textSecondary)
                    }

                    Spacer(minLength: 12)

                    Button(L10n.string("Preview", language: language)) {
                        TaskNotifier.shared.previewSignalSound()
                    }
                    .buttonStyle(.window(.secondary))
                    .disabled(!signalSounds)

                    Toggle(
                        L10n.string("Signal Sounds", language: language),
                        isOn: $signalSounds
                    )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(Palette.Window.ink)
                        .accessibilityHint(
                            L10n.string(
                                "Plays short cues through macOS notifications.",
                                language: language
                            )
                        )
                }
                .padding(16)


            }
            .windowSurface(radius: Palette.Window.Radius.group, tone: .raised)
        }
        .onChange(of: attentionRequired) { _, enabled in
            if enabled { TaskNotifier.shared.refreshAuthorizationIfNeeded() }
        }
        .onChange(of: completions) { _, enabled in
            if enabled { TaskNotifier.shared.refreshAuthorizationIfNeeded() }
        }
        .onAppear {
            authorizationIssue = TaskNotifier.shared.authorizationIssue
            TaskNotifier.shared.refreshAuthorizationState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .islandNotificationAuthorizationChanged)) { _ in
            authorizationIssue = TaskNotifier.shared.authorizationIssue
        }
    }

    private var notificationsEnabled: Bool {
        attentionRequired || completions
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

}

// MARK: - Connected Services

enum SettingsAgentGroup: Hashable {
    case local
    case cloud

    /// Local integrations are the primary setup path; optional Manus cloud
    /// configuration follows them when both groups are visible.
    static func ordered(hasLocalAgents: Bool, showsManus: Bool) -> [Self] {
        var groups: [Self] = []
        if hasLocalAgents { groups.append(.local) }
        if showsManus { groups.append(.cloud) }
        return groups
    }
}

/// Stable connections are grouped by required action; preview capabilities
/// stay separate. A requested diagnostics result appears above the list.
private struct ConnectedServicesSection: View {
    let store: TaskStore
    let showsTitle: Bool
    let onRevealDiagnostics: () -> Void
    @Binding private var connectionsOperation: LocalAgentConnectionsOperationState
    @State private var installationRefreshToken = UUID()
    @State private var hasManagedLocalHooks = false
    @State private var isRefreshingManagedHookState = true
    @State private var managedHookRefreshID = UUID()
    @State private var showDisconnectAllConfirmation = false
    @State private var liveReadinessCheckState: LocalLiveReadinessCheckState
    @State private var connectionStates: [String: LocalAgentHookConnectionState]
    @State private var connectionSnapshotToken = UUID()
    @State private var expandedSource: String?
    @State private var showsPreviewConnectors = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.devIslandLanguage) private var language

    init(
        store: TaskStore,
        showsTitle: Bool = true,
        initialLiveReadinessSnapshot: LocalLiveReadinessSnapshot? = nil,
        initialConnectionStates: [String: LocalAgentHookConnectionState] = [:],
        connectionsOperation: Binding<LocalAgentConnectionsOperationState>,
        onRevealDiagnostics: @escaping () -> Void = {}
    ) {
        self.store = store
        self.showsTitle = showsTitle
        self.onRevealDiagnostics = onRevealDiagnostics
        _connectionsOperation = connectionsOperation
        _connectionStates = State(initialValue: initialConnectionStates)
        _liveReadinessCheckState = State(
            initialValue: LocalLiveReadinessCheckState(
                snapshot: initialLiveReadinessSnapshot
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showsTitle { sectionTitle("Agent Connections") }

            summaryLine

            switch store.localHookServiceStatus {
            case .retrying, .unavailable, .stopped:
                LocalHookServiceNotice(store: store)
            case .starting, .listening:
                EmptyView()
            }

            if let notice = LocalAgentReportingPresentation.notice(
                store.reportingHealth,
                visibleTaskSources: Set(store.tasks.filter { $0.status == .running || $0.status == .waiting }.map(\.source)),
                language: language
            ) {
                LocalAgentReportingNoticeView(notice: notice, isChecking: liveReadinessCheckState.isChecking) {
                    expandedSource = notice.source
                    checkLiveReadiness(for: notice.source)
                }
                    .task { await store.refreshReportingHealth() }
            } else {
                Color.clear
                    .frame(height: 0)
                    .task { await store.refreshReportingHealth() }
            }

            if liveReadinessCheckState.isChecking || liveReadinessCheckState.snapshot != nil {
                readinessCard
            }

            ForEach(Array(groupedLocalAgents.enumerated()), id: \.offset) { _, entry in
                if entry.group == .preview {
                    DisclosureGroup(isExpanded: $showsPreviewConnectors) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.string("These connectors handle simulated requests only. They are not included in your setup count.", language: language))
                                .font(Typo.callout)
                                .foregroundStyle(Palette.Window.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            agentRows(entry.descriptors)
                        }
                        .padding(.top, 10)
                    } label: {
                        HStack {
                            Text(L10n.string("Preview connectors", language: language))
                            Spacer()
                            Text("\(entry.descriptors.count)")
                                .monospacedDigit()
                        }
                        .font(Typo.calloutStrong)
                        .foregroundStyle(Palette.Window.textSecondary)
                    }
                    .padding(14)
                    .windowSurface(radius: Palette.Window.Radius.group, tone: .raised)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        groupLabel(
                            entry.group?.title(language: language) ?? L10n.string("Local Agents", language: language),
                            tone: entry.group == .needsAttention ? .attention : .raised
                        )
                        agentRows(entry.descriptors)
                            .windowSurface(
                                radius: Palette.Window.Radius.group,
                                tone: entry.group == .needsAttention ? .attention : .raised
                            )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                groupLabel(L10n.string("Cloud", language: language), tone: .raised)
                ManusServiceRow(store: store)
                    .windowSurface(radius: Palette.Window.Radius.group, tone: .raised)
            }

            footer
        }
        .onAppear {
            refreshManagedHookState()
            refreshConnectionStates()
        }
        .onDisappear {
            managedHookRefreshID = UUID()
            connectionSnapshotToken = UUID()
            liveReadinessCheckState.invalidate()
        }
        // Manual CLI authorization can happen outside this window.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshConnectionStates()
        }
        .onChange(of: store.localHookServiceStatus) { _, _ in
            liveReadinessCheckState.invalidate()
        }
        .onChange(of: connectionsOperation.activeOperationID) { _, operationID in
            if operationID != nil {
                liveReadinessCheckState.invalidate()
            }
        }
        .onChange(of: connectionsOperation.completionGeneration) { _, _ in
            installationRefreshToken = UUID()
            refreshManagedHookState()
            refreshConnectionStates()
            liveReadinessCheckState.invalidate()
        }
        .alert(
            L10n.string("Disconnect all local agents?", language: language),
            isPresented: $showDisconnectAllConfirmation
        ) {
            Button(L10n.string("Cancel", language: language), role: .cancel) {}
            Button(
                L10n.string("Disconnect All", language: language),
                role: .destructive
            ) {
                disconnectAllLocalAgents()
            }
        } message: {
            Text(L10n.string(
                "This removes only Dev Island's managed Hook commands from every local Agent configuration. Your other settings and Hooks stay in place. Manus is not affected.",
                language: language
            ))
        }
    }

    // MARK: Grouping

    private var groupedLocalAgents: [(group: LocalAgentConnectionGroup?, descriptors: [LocalAgentDescriptor])] {
        LocalAgentRowPresentation.grouped(LocalAgentRegistry.all, states: connectionStates)
    }

    private func agentRows(_ descriptors: [LocalAgentDescriptor]) -> some View {
        VStack(spacing: 0) {
            ForEach(descriptors, id: \.source) { descriptor in
                if descriptor.source != descriptors.first?.source { rowDivider }
                AgentConnectionRow(
                    descriptor: descriptor,
                    store: store,
                    refreshToken: installationRefreshToken,
                    connectionState: connectionStates[descriptor.source],
                    isExpanded: expandedSource == descriptor.source,
                    onToggleExpanded: { toggleExpanded(descriptor.source) },
                    onConnectionChanged: refreshConnectionStates,
                    connectionsOperation: $connectionsOperation
                )
            }
        }
    }

    private var summaryLine: some View {
        Text(LocalAgentRowPresentation.summary(
            descriptors: LocalAgentRegistry.all,
            states: connectionStates,
            language: language
        ))
        .font(Typo.calloutStrong)
        .foregroundStyle(Palette.Window.textSecondary)
        .monospacedDigit()
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func groupLabel(_ text: String, tone: WindowSurfaceTone) -> some View {
        Text(text)
            .font(Typo.calloutStrong)
            .foregroundStyle(
                tone == .attention ? Palette.Window.attentionText : Palette.Window.textSecondary
            )
            .padding(.leading, 14)
    }

    private var rowDivider: some View {
        settingsDivider.padding(.leading, 54)
    }

    private func toggleExpanded(_ source: String) {
        withAnimation(reduceMotion ? nil : Motion.layout) {
            expandedSource = expandedSource == source ? nil : source
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !liveReadinessCheckState.isChecking && liveReadinessCheckState.snapshot == nil {
                readinessCard
            }
            localAgentMaintenanceRow
        }
        .padding(.top, 6)
    }

    private var readinessCard: some View {
        LocalLiveReadinessCard(
            snapshot: liveReadinessCheckState.snapshot,
            isChecking: liveReadinessCheckState.isChecking,
            isMutationInProgress: connectionsOperation.isMutating,
            onCheck: checkLiveReadiness
        )
    }

    private var localAgentMaintenanceRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(maintenanceMessage ?? maintenanceStatusMessage)
                .font(Typo.caption)
                .foregroundStyle(maintenanceFailed
                                 ? Palette.Window.destructive
                                 : Palette.Window.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if connectionsOperation.isMutating || isRefreshingManagedHookState {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(
                        maintenanceProgressAccessibilityLabel
                    )
            } else {
                Button(role: .destructive) {
                    showDisconnectAllConfirmation = true
                } label: {
                    Text(L10n.string(
                        hasManagedLocalHooks ? "Disconnect all local Agents…" : "All Disconnected",
                        language: language
                    ))
                }
                .buttonStyle(.window(.quiet))
                .disabled(!hasManagedLocalHooks || isRefreshingManagedHookState)
                .accessibilityHint(
                    L10n.string(
                        "Removes only Dev Island's managed Hooks from every local Agent",
                        language: language
                    )
                )
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: Data

    /// One read-only diagnostics pass classifies every row and resolves the
    /// Codex authorization gate through the signed CLI. It never writes.
    private func refreshConnectionStates() {
        let token = UUID()
        connectionSnapshotToken = token

        Task { @MainActor in
            let snapshot = await Task.detached(priority: .utility) {
                LocalAgentHookDiagnostics.snapshotResolvingVendorActivation()
            }.value
            guard connectionSnapshotToken == token else { return }
            let states = Dictionary(
                snapshot.agents.map { ($0.source, $0.state) },
                uniquingKeysWith: { first, _ in first }
            )
            guard states != connectionStates else { return }
            withAnimation(reduceMotion ? nil : Motion.layout) {
                connectionStates = states
            }
        }
    }

    private func refreshManagedHookState() {
        let refreshID = UUID()
        managedHookRefreshID = refreshID
        isRefreshingManagedHookState = true

        Task { @MainActor in
            let hasManagedHooks = await LocalAgentConfigurationExecutor.run(
                priority: .utility
            ) {
                LocalAgentHookMaintenance.hasManagedHooks()
            }
            guard managedHookRefreshID == refreshID else { return }
            hasManagedLocalHooks = hasManagedHooks
            isRefreshingManagedHookState = false
        }
    }

    private func checkLiveReadiness() {
        checkLiveReadiness(for: liveReadinessCheckState.source)
    }

    private func checkLiveReadiness(for source: String?) {
        guard let checkID = liveReadinessCheckState.begin(source: source) else { return }
        onRevealDiagnostics()

        Task { @MainActor in
            let snapshot = await Task.detached(priority: .userInitiated) {
                await LocalLiveReadinessProbe().snapshot()
            }.value
            liveReadinessCheckState.accept(snapshot, for: checkID)
        }
    }

    private func disconnectAllLocalAgents() {
        guard let operationID = connectionsOperation.beginDisconnectAll() else { return }
        managedHookRefreshID = UUID()
        isRefreshingManagedHookState = false
        liveReadinessCheckState.invalidate()

        Task { @MainActor in
            let outcome = await LocalAgentConfigurationExecutor.run(
                priority: .userInitiated
            ) {
                LocalAgentMaintenanceWorker.disconnectAll()
            }
            connectionsOperation.completeDisconnectAll(outcome, for: operationID)
        }
    }

    private var maintenanceFailed: Bool {
        connectionsOperation.maintenanceOutcome == .failed
    }

    private var maintenanceStatusMessage: String {
        let key: String
        if connectionsOperation.isDisconnectingAll {
            key = "Disconnecting local Agents…"
        } else if connectionsOperation.isMutating {
            key = "Finishing the current Agent change…"
        } else if isRefreshingManagedHookState {
            key = "Checking managed Hooks…"
        } else if hasManagedLocalHooks {
            key = "Remove every Dev Island Hook while preserving user-owned configuration."
        } else {
            key = "No Dev Island Hooks are installed."
        }
        return L10n.string(key, language: language)
    }

    private var maintenanceProgressAccessibilityLabel: String {
        let key: String
        if connectionsOperation.isDisconnectingAll {
            key = "Disconnecting all local agents"
        } else if connectionsOperation.isMutating {
            key = "Updating local Agent Hooks"
        } else {
            key = "Checking managed Hooks"
        }
        return L10n.string(key, language: language)
    }

    private var maintenanceMessage: String? {
        switch connectionsOperation.maintenanceOutcome {
        case nil:
            return nil
        case .noChanges?:
            return L10n.string(
                "No Dev Island Hooks were installed.",
                language: language
            )
        case let .disconnected(count)?:
            return L10n.format(
                count == 1
                    ? "Disconnected %lld local Agent. User settings were preserved."
                    : "Disconnected %lld local Agents. User settings were preserved.",
                language: language,
                Int64(count)
            )
        case .failed?:
            return L10n.string(
                "Couldn't disconnect local Agents. User settings were preserved.",
                language: language
            )
        }
    }
}

/// One calm preflight surface for the two shipping bidirectional Agents. It
/// deliberately shows only the next useful action; individual rows remain the
/// place where the user chooses to modify managed Hook configuration.
private struct LocalLiveReadinessCard: View {
    let snapshot: LocalLiveReadinessSnapshot?
    let isChecking: Bool
    let isMutationInProgress: Bool
    let onCheck: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.devIslandLanguage) private var language

    private var content: LocalLiveReadinessPresentation.Content {
        LocalLiveReadinessPresentation.content(
            snapshot: snapshot,
            isChecking: isChecking,
            language: language
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            AnimatedDotMatrixMark(
                color: tint,
                size: 18,
                motion: content.tone == .checking ? .orbiting : .still,
                pattern: pattern,
                intensity: intensity,
                isAnimated: content.tone == .checking && !reduceMotion
            )
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot == nil && !isChecking
                     ? L10n.string("Island not reacting?", language: language)
                     : content.title)
                    .font(Typo.bodyStrong)
                    .foregroundStyle(Palette.Window.ink)
                Text(content.detail)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.Window.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(action: onCheck) {
                HStack(spacing: 6) {
                    if isChecking {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityHidden(true)
                    }
                    Text(L10n.string(buttonTitle, language: language))
                }
            }
            .buttonStyle(.window(.secondary))
            .disabled(isChecking || isMutationInProgress)
            .accessibilityHint(
                L10n.string(
                    "Checks local CLI versions, managed Hooks, Codex trust, and the private listener without changing configuration.",
                    language: language
                )
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .windowSurface(radius: Palette.Window.Radius.group, tone: surfaceTone)
        .accessibilityElement(children: .contain)
    }

    private var buttonTitle: String {
        if isChecking { return "Checking…" }
        return snapshot == nil ? "Check this Mac" : "Check again"
    }

    private var tint: Color {
        switch content.tone {
        case .neutral:   return Palette.Window.textSecondary
        case .checking:  return Palette.Window.stateRunning
        case .retry:     return Palette.Window.stateRunning
        case .ready:     return Palette.Window.stateCompleted
        case .attention: return Palette.Window.stateWaiting
        }
    }

    private var pattern: DotMatrixMark.Pattern {
        switch content.tone {
        case .neutral:   return .field
        case .checking:  return .orbit
        case .retry:     return .ring
        case .ready:     return .plus
        case .attention: return .ring
        }
    }

    private var intensity: Double {
        switch content.tone {
        case .neutral: return 0.78
        case .retry: return 0.90
        case .checking, .ready, .attention: return 0.96
        }
    }

    private var surfaceTone: WindowSurfaceTone {
        switch content.tone {
        case .attention: return .attention
        case .neutral, .checking, .retry, .ready: return .raised
        }
    }
}

/// Quiet Agents-page notice for a vendor that is working while its Hooks
/// deliver nothing: the one situation where a blank island is a bug, not a
/// quiet day.
private struct LocalAgentReportingNoticeView: View {
    let notice: LocalAgentReportingNotice
    let isChecking: Bool
    let onCheck: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.devIslandLanguage) private var language

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AnimatedDotMatrixMark(
                color: Palette.Window.attention,
                size: 16,
                motion: .attention,
                pattern: .ring,
                intensity: 0.96,
                isAnimated: !reduceMotion
            )
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(Typo.bodyStrong)
                    .foregroundStyle(Palette.Window.ink)
                Text(notice.hint)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.Window.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(L10n.string(isChecking ? "Checking…" : "Check connection", language: language), action: onCheck)
                .buttonStyle(.window(.secondary))
                .disabled(isChecking)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .windowSurface(radius: Palette.Window.Radius.group, tone: .attention)
        .accessibilityElement(children: .contain)
    }
}

/// Appears only when the shared loopback listener needs attention. Healthy
/// operation stays quiet; failed delivery must not masquerade as a connected
/// integration whose events are silently disappearing.
private struct LocalHookServiceNotice: View {
    let store: TaskStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.devIslandLanguage) private var language

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AnimatedDotMatrixMark(
                color: tint,
                size: 16,
                motion: isRecovering ? .orbiting : .attention,
                pattern: isRecovering ? .orbit : .ring,
                intensity: 0.96,
                isAnimated: !reduceMotion
            )
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string(title, language: language))
                    .font(Typo.bodyStrong)
                    .foregroundStyle(Palette.Window.ink)
                Text(L10n.string(detail, language: language))
                    .font(Typo.caption)
                    .foregroundStyle(Palette.Window.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(L10n.string("Retry Now", language: language)) {
                store.retryLocalHookService()
            }
            .buttonStyle(.window(.secondary))
            .accessibilityHint(
                L10n.string("Restarts the local Agent listener", language: language)
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .windowSurface(radius: Palette.Window.Radius.group, tone: .attention)
        .accessibilityElement(children: .contain)
    }

    private var isRecovering: Bool {
        switch store.localHookServiceStatus {
        case .retrying, .starting: return true
        case .unavailable, .stopped, .listening: return false
        }
    }

    private var title: String {
        switch store.localHookServiceStatus {
        case .retrying:
            return "Agent listener is reconnecting"
        case .unavailable:
            return "Agent listener is offline"
        case .stopped:
            return "Agent listener is stopped"
        case .starting:
            return "Agent listener is starting"
        case .listening:
            return "Agent listener is ready"
        }
    }

    private var detail: String {
        switch store.localHookServiceStatus {
        case .retrying(let attempt, let limit):
            return L10n.format(
                "Couldn't open the local port. Retrying automatically (%lld of %lld).",
                language: language,
                Int64(attempt),
                Int64(limit)
            )
        case .unavailable:
            return "Local Agent sessions cannot update until Dev Island can use port 7824."
        case .stopped:
            return "Restart the local listener to resume Agent session updates."
        case .starting:
            return "Preparing the private loopback connection."
        case .listening:
            return "Local Agent events are arriving through this Mac only."
        }
    }

    private var tint: Color {
        switch store.localHookServiceStatus {
        case .retrying:
            return Palette.Window.attention
        case .unavailable, .stopped:
            return Palette.Window.stateFailed
        case .starting, .listening:
            return Palette.Window.stateRunning
        }
    }
}

// MARK: - Manus row

private struct ManusServiceRow: View {
    let store: TaskStore

    @State private var apiKeyDraft: String = ""
    @State private var isSubmitting = false
    @State private var lastError: String?
    @Environment(\.devIslandLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AgentStateTile(
                    state: store.apiKeyStatus == .valid ? .connected : .disconnected,
                    isBusy: isSubmitting,
                    source: "manus"
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Manus").font(Typo.bodyStrong)
                    Text(L10n.string(statusLine, language: language))
                        .font(Typo.callout)
                        .foregroundStyle(Palette.Window.textSecondary)
                }
                Spacer()
                trailingControl
            }

            // Show key entry when not configured / invalid. When valid,
            // show a "Disconnect" button only — no need to expose the key.
            if store.apiKeyStatus != .valid {
                keyField
                    .padding(.leading, 40)
            }

            if let lastError {
                Text(lastError)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.Window.destructive)
                    .padding(.leading, 40)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var statusLine: String {
        ManusConnectionStatusPresentation.message(
            apiKeyStatus: store.apiKeyStatus,
            connectionStatus: store.connectionStatus,
            language: language
        )
    }

    @ViewBuilder
    private var trailingControl: some View {
        if isSubmitting {
            ProgressView().controlSize(.small)
        } else if store.apiKeyStatus == .valid {
            Button(role: .destructive) {
                Task { await disconnect() }
            } label: {
                Text(L10n.string("Disconnect", language: language))
            }
            .buttonStyle(.window(.quiet))
        } else {
            Button {
                Task { await connect() }
            } label: {
                Text(L10n.string("Connect", language: language))
            }
            .buttonStyle(.window(.secondary))
            .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            .keyboardShortcut(.defaultAction)
        }
    }

    /// A persistent label above the field: the `sk-…` format hint is a
    /// placeholder and disappears the moment typing starts.
    private var keyField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.string("Manus API key", language: language))
                .font(Typo.caption.weight(.medium))
                .foregroundStyle(Palette.Window.textSecondary)
                .accessibilityHidden(true)

            // Per S's docs/manus-api-field-notes.md, the real API key
            // format is `sk-…` (not the `mk_live_…` from the public docs
            // example). Placeholder updated to match what users actually
            // get from manus.im.
            SecureField(
                L10n.string("Manus API key", language: language),
                text: $apiKeyDraft,
                prompt: Text(verbatim: "sk-…")
            )
                .textFieldStyle(.plain)
                .font(Typo.mono)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(
                    Capsule()
                        .fill(Palette.Window.field)
                        .overlay {
                            Capsule()
                                .strokeBorder(Palette.Window.hairlineStrong, lineWidth: 0.75)
                        }
                )
                .onSubmit {
                    guard !apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    Task { await connect() }
                }
        }
    }

    @MainActor
    private func connect() async {
        let key = apiKeyDraft.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        isSubmitting = true
        lastError = nil
        defer { isSubmitting = false }
        do {
            try await store.configureAPIKey(key)
            apiKeyDraft = ""
        } catch {
            lastError = ManusConnectionErrorPresentation.message(
                for: error,
                language: language
            )
        }
    }

    @MainActor
    private func disconnect() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await store.clearAPIKey()
            apiKeyDraft = ""
            lastError = nil
        } catch {
            lastError = L10n.string(
                "Disconnected, but the saved key couldn’t be removed. Retry Disconnect before uninstalling.",
                language: language
            )
        }
    }

}

// MARK: - Local agent row (registry-driven)

/// One Agent, one sentence, one control. Connected rows expand into an inset
/// panel that explains what arrives and lets the user disconnect; the Codex
/// authorization sheet and the monitoring toggle live there too. Row
/// identity (name, subtitle, config path) comes entirely from the Agent's
/// `LocalAgentDescriptor`; enabling installs Hook entries through the
/// generic `LocalHooksInstaller` and sessions report to `LocalHookServer`.
private struct AgentConnectionRow: View {
    let descriptor: LocalAgentDescriptor
    let store: TaskStore
    let refreshToken: UUID
    let connectionState: LocalAgentHookConnectionState?
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onConnectionChanged: () -> Void
    @Binding var connectionsOperation: LocalAgentConnectionsOperationState

    @State private var configurationState = LocalAgentInstallationOperationState()
    @State private var lastError: String?
    @State private var showsAuthorization = false
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.devIslandLanguage) private var language

    private var installer: LocalHooksInstaller { .init(descriptor) }
    private var action: LocalAgentRowAction { LocalAgentRowPresentation.action(for: connectionState) }
    /// Only a user-initiated change replaces the row's control with progress;
    /// the quiet background re-inspection keeps the section's known state.
    private var isBusy: Bool { configurationState.activeMutation != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            connectionHeader
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .background(rowHighlight)
                .onHover { isHovering = $0 }
                .accessibilityElement(children: .contain)
                .accessibilityHint(
                    action == .expand
                        ? L10n.string(isExpanded ? "Hide details" : "Show details", language: language)
                        : ""
                )

            if let lastError {
                Text(lastError)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.Window.destructive)
                    .padding(.horizontal, 14)
                    .padding(.leading, 40)
                    .padding(.bottom, 10)
            }

            if isExpanded, action == .expand {
                details
                    .padding(.horizontal, 14)
                    .padding(.leading, 40)
                    .padding(.bottom, 12)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear { refreshInstallationState() }
        .onChange(of: refreshToken) { _, _ in refreshInstallationState() }
        .onDisappear {
            configurationState.invalidate()
        }
        .sheet(isPresented: $showsAuthorization) {
            CodexHookAuthorizationSheet(onAuthorized: onConnectionChanged)
        }
    }

    @ViewBuilder
    private var connectionHeader: some View {
        if action == .expand {
            Button(action: onToggleExpanded) { headline.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .disabled(isBusy)
        } else {
            headline
        }
    }

    private var rowHighlight: some View {
        Rectangle()
            .fill(
                isExpanded
                    ? Palette.Window.ink.opacity(0.035)
                    : (isHovering && action == .expand ? Palette.Window.hover : .clear)
            )
    }

    private var headline: some View {
        HStack(spacing: 12) {
            AgentStateTile(state: connectionState, isBusy: isBusy, source: descriptor.source)

            VStack(alignment: .leading, spacing: 2) {
                // Preview connectors live in their own "Preview connectors"
                // group, which already says what a tag here would.
                Text(descriptor.displayName)
                    .font(Typo.bodyStrong)
                    .foregroundStyle(Palette.Window.ink)
                Text(statusLine)
                    .font(Typo.callout)
                    .foregroundStyle(
                        action == .authorize || action == .update
                            ? Palette.Window.attentionText
                            : Palette.Window.textSecondary
                    )
                    .fixedSize(horizontal: false, vertical: true)
                if descriptor.releaseStage == .stable, connectionState == .connected {
                    Text(L10n.string(
                        store.tasks.contains { $0.source == descriptor.source && ($0.status == .running || $0.status == .waiting) }
                            ? "Task activity visible" : "Waiting for task activity",
                        language: language
                    ))
                    .font(Typo.callout)
                    .foregroundStyle(Palette.Window.textSecondary)
                }
            }

            Spacer(minLength: 8)

            trailingControl
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        if isBusy {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityHidden(true)
                Text(L10n.string(
                    configurationState.activeMutation?.progressLocalizationKey
                        ?? "Checking…",
                    language: language
                ))
            }
            .font(Typo.caption.weight(.medium))
            .foregroundStyle(Palette.Window.textSecondary)
            .accessibilityElement(children: .combine)
        } else {
            switch action {
            case .expand:
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.Window.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(reduceMotion ? nil : Motion.layout, value: isExpanded)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)

            case .authorize:
                Button {
                    showsAuthorization = true
                } label: {
                    Text(CodexTrustGuidance.actionTitle(language: language))
                }
                .buttonStyle(.window(.primary))
                .disabled(connectionsOperation.isMutating)
                .accessibilityHint(L10n.string(
                    "Review the exact commands before authorizing Dev Island hooks",
                    language: language
                ))

            case .update:
                Button {
                    apply(.update)
                } label: {
                    Text(L10n.string("Update connection", language: language))
                }
                .buttonStyle(.window(.primary))
                .disabled(connectionsOperation.isMutating)

            case .connect:
                Button {
                    apply(.enable)
                } label: {
                    Text(L10n.string("Connect", language: language))
                }
                .buttonStyle(.window(.secondary))
                .disabled(connectionsOperation.isMutating || connectionState == nil)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 0) {
                if descriptor.source == "codex" {
                    detailLine(
                        title: L10n.string("Task activity", language: language),
                        subtitle: L10n.string(
                            "Reads local session logs. Data stays on this Mac.",
                            language: language
                        )
                    ) {
                        Toggle(
                            L10n.string("Task activity", language: language),
                            isOn: Binding(
                                get: { store.codexSessionMonitoringEnabled },
                                set: { store.setCodexSessionMonitoringEnabled($0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(Palette.Window.ink)
                    }
                    Text(CodexSessionMonitoringPresentation.status(
                        store.codexSessionMonitorStatus, language: language
                    ))
                    .font(Typo.callout)
                    .foregroundStyle(Palette.Window.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 9)
                    settingsDivider
                }

                detailLine(
                    title: L10n.string("Approvals", language: language),
                    subtitle: approvalsSubtitle
                ) {
                    if descriptor.source == "codex" {
                        Button {
                            showsAuthorization = true
                        } label: {
                            Text(L10n.string("View commands", language: language))
                        }
                        .buttonStyle(.window(.quiet))
                        .accessibilityHint(L10n.string(
                            "Review the exact commands before authorizing Dev Island hooks",
                            language: language
                        ))
                    }
                }
                if descriptor.source == "codex" {
                    Text(L10n.string("Hooks installed · verify delivery with a real request", language: language))
                        .font(Typo.callout)
                        .foregroundStyle(Palette.Window.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            }
            .windowSurface(radius: Palette.Window.Radius.inset, tone: .inset)

            Button(role: .destructive) {
                apply(.disable)
            } label: {
                Text(L10n.string("Disconnect", language: language))
            }
            .buttonStyle(.window(.quiet))
            .disabled(connectionsOperation.isMutating)
            .padding(.leading, 2)
        }
    }

    private func detailLine<Control: View>(
        title: String,
        subtitle: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Typo.bodyStrong)
                    .foregroundStyle(Palette.Window.ink)
                Text(subtitle)
                    .font(Typo.callout)
                    .foregroundStyle(Palette.Window.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var approvalsSubtitle: String {
        if descriptor.releaseStage == .preview {
            return L10n.string("Simulated requests only", language: language)
        }
        if descriptor.source == "codex" {
            return L10n.format(
                "Authorized · %lld commands",
                language: language,
                Int64(descriptor.hookEvents.count)
            )
        }
        let capabilities = descriptor.capabilities
        if capabilities.permissionRequests == .bidirectional
            || capabilities.questionRequests == .bidirectional
            || capabilities.planReviews == .bidirectional {
            return L10n.string("Hooks installed · verify delivery with a real request", language: language)
        }
        if capabilities.permissionRequests == .observeOnly
            || capabilities.questionRequests == .observeOnly
            || capabilities.planReviews == .observeOnly {
            return L10n.string("Attention monitoring only · respond in the Agent", language: language)
        }
        return L10n.string("Task activity only · approvals stay in the Agent", language: language)
    }

    private var statusLine: String {
        if let operation = configurationState.activeMutation {
            return L10n.string(operation.progressLocalizationKey, language: language)
        }
        return LocalAgentRowPresentation.statusLine(
            state: connectionState,
            descriptor: descriptor,
            language: language
        )
    }

    private func apply(_ operation: LocalAgentConfigurationOperation) {
        guard !configurationState.isBusy,
              let surfaceOperationID = connectionsOperation.beginAgentMutation(
                source: descriptor.source,
                operation: operation
              ) else {
            return
        }
        guard let operationID = configurationState.beginMutation(operation) else {
            connectionsOperation.cancel(surfaceOperationID)
            return
        }
        lastError = nil
        let installer = installer

        Task { @MainActor in
            let outcome = await LocalAgentConfigurationExecutor.run(
                priority: .userInitiated
            ) {
                LocalAgentConfigurationWorker.perform(
                    operation,
                    installer: installer
                )
            }
            let surfaceAccepted = connectionsOperation.completeAgentMutation(
                surfaceOperationID
            )
            let rowAccepted = configurationState.accept(
                outcome.installationState,
                for: operationID
            )
            guard surfaceAccepted, rowAccepted else { return }

            lastError = outcome.succeeded
                ? nil
                : L10n.string(
                    "Could not update this agent’s configuration.",
                    language: language
                )
        }
    }

    private func refreshInstallationState() {
        guard let refreshID = configurationState.beginRefresh() else { return }
        let installer = installer

        Task { @MainActor in
            let state = await LocalAgentConfigurationExecutor.run(
                priority: .utility
            ) {
                LocalAgentConfigurationWorker.inspect(installer: installer)
            }
            _ = configurationState.accept(state, for: refreshID)
        }
    }
}

// MARK: - General section (Launch at Login)

private struct GeneralSection: View {
    var showsTitle = true
    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)
    @State private var lastError: String?
    @State private var canObserveGlobalKeys = InputPermissions.canObserveGlobalKeys
    @AppStorage(DevIslandLanguage.preferenceKey)
    private var storedLanguage = DevIslandLanguage.system.rawValue
    @AppStorage(GlobalDecisionShortcutPreferences.enabledKey)
    private var globalDecisionShortcutsEnabled = true
    @Environment(\.devIslandLanguage) private var language

    private var selectedLanguage: DevIslandLanguage {
        DevIslandLanguage(rawValue: storedLanguage) ?? .system
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsTitle { sectionTitle("General") }

            VStack(alignment: .leading, spacing: 0) {
                SettingsToggleRow(
                    title: "Launch at Login",
                    subtitle: "Open Island automatically when you log in.",
                    isOn: $launchAtLogin
                )
                .onChange(of: launchAtLogin) { _, new in
                    apply(launchAtLogin: new)
                }

                settingsDivider.padding(.leading, 16)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.string("Language", language: language))
                            .font(Typo.bodyStrong)
                        Text(L10n.string(
                            "Change Dev Island without changing your Mac language.",
                            language: language
                        ))
                            .font(Typo.caption)
                            .foregroundStyle(Palette.Window.textSecondary)
                    }

                    Spacer(minLength: 12)

                    Menu {
                        ForEach(DevIslandLanguage.allCases) { option in
                            Button {
                                storedLanguage = option.rawValue
                            } label: {
                                if option == selectedLanguage {
                                    Label(
                                        L10n.string(option.displayKey, language: language),
                                        systemImage: "checkmark"
                                    )
                                } else {
                                    Text(L10n.string(
                                        option.displayKey,
                                        language: language
                                    ))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(L10n.string(
                                selectedLanguage.displayKey,
                                language: language
                            ))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Palette.Window.textTertiary)
                        }
                        .font(Typo.caption.weight(.medium))
                        .foregroundStyle(Palette.Window.ink.opacity(0.82))
                        .padding(.horizontal, 10)
                        .frame(width: 150, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Palette.Window.ink.opacity(0.025))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(Palette.Window.hairline, lineWidth: 0.75)
                                }
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel(L10n.string(
                        "Interface Language",
                        language: language
                    ))
                    .accessibilityValue(L10n.string(
                        selectedLanguage.displayKey,
                        language: language
                    ))
                }
                .padding(16)

                settingsDivider.padding(.leading, 16)

                SettingsToggleRow(
                    title: "Decide from Anywhere",
                    subtitle: "Press ⌃⌥⌘Y to allow or ⌃⌥⌘N to deny the request at the front of the island while any app is active. Questions and plan reviews open the island instead.",
                    isOn: $globalDecisionShortcutsEnabled
                )

                if let lastError {
                    Text(lastError)
                        .font(Typo.caption)
                        .foregroundStyle(Palette.Window.stateFailed)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

                if !canObserveGlobalKeys {
                    settingsDivider.padding(.leading, 16)
                    escShortcutRow
                }
            }
            .windowSurface(radius: Palette.Window.Radius.group, tone: .raised)
        }
        // The user grants the permission in System Settings, so re-read it
        // whenever they come back to us rather than caching it for the
        // lifetime of the window.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            canObserveGlobalKeys = InputPermissions.canObserveGlobalKeys
        }
    }

    private var escShortcutRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .foregroundStyle(Palette.Window.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string("Close the Panel with Esc", language: language))
                    .font(Typo.bodyStrong)
                Text(L10n.string(
                    "Needs Accessibility access — Esc is pressed while your editor still has focus. Clicking away always closes the panel.",
                    language: language
                ))
                    .font(Typo.caption)
                    .foregroundStyle(Palette.Window.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                InputPermissions.openAccessibilitySettings()
            } label: {
                Text(L10n.string("Open System Settings", language: language))
            }
            .buttonStyle(.window(.secondary))
        }
        .padding(16)
    }

    private func apply(launchAtLogin: Bool) {
        let service = SMAppService.mainApp
        do {
            if launchAtLogin {
                try service.register()
            } else {
                try service.unregister()
            }
            lastError = nil
        } catch {
            // SMAppService.register() can throw `notAuthorized` if the
            // user disabled the helper in System Settings. Surface the
            // message and revert the toggle to actual state.
            lastError = L10n.string(
                "Couldn't update Login Items. Review Login Items in System Settings.",
                language: language
            )
            self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }
}

// MARK: - Helpers

@ViewBuilder
private func sectionTitle(_ text: LocalizedStringKey) -> some View {
    Text(text)
        .font(Typo.calloutStrong)
        .foregroundStyle(Palette.Window.ink.opacity(0.72))
}

private var settingsDivider: some View {
    WindowDivider()
}

#if PREVIEWS && DEBUG
#Preview("Settings — not configured") {
    SettingsView(previewStore: .presentationFixture())
        .frame(width: 720, height: 520)
}
#endif
