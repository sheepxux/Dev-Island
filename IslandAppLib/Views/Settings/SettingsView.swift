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
    @State private var localAgentConnectionsOperation =
        LocalAgentConnectionsOperationState()
    private let initialLiveReadinessSnapshot: LocalLiveReadinessSnapshot?
    private let previewAppVersion: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.devIslandLanguage) private var language

    public init() {
        initialLiveReadinessSnapshot = nil
        previewAppVersion = nil
    }

    #if DEBUG
    init(
        previewStore: TaskStore,
        initialPane: SettingsPane = .agents,
        initialLiveReadinessSnapshot: LocalLiveReadinessSnapshot? = nil,
        previewAppVersion: String = "0.3.0"
    ) {
        _store = State(initialValue: previewStore)
        _selectedPane = State(initialValue: initialPane)
        self.initialLiveReadinessSnapshot = initialLiveReadinessSnapshot
        self.previewAppVersion = previewAppVersion
    }
    #endif

    public var body: some View {
        HStack(spacing: 0) {
            sidebar

            Rectangle()
                .fill(Palette.hairline)
                .frame(width: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
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
                    .padding(.horizontal, 30)
                    .padding(.vertical, 26)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(minWidth: 700, idealWidth: 720, minHeight: 500, idealHeight: 520)
        .background(Palette.tourCanvas)
        .foregroundStyle(Palette.warmWhite)
        .tint(Palette.warmWhite)
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 25, height: 25)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Dev Island")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.warmWhite.opacity(0.9))
                    Text(L10n.string("SETTINGS", language: language))
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 62)

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)

            VStack(spacing: 1) {
                ForEach(SettingsPane.allCases) { pane in
                    Button {
                        withAnimation(Motion.contentReveal) {
                            selectedPane = pane
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Text(pane.indexLabel)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(
                                    pane == selectedPane
                                        ? Palette.warmWhite.opacity(0.72)
                                        : Palette.textTertiary
                                )
                                .frame(width: 18, alignment: .leading)

                            Text(pane.title(language: language))
                                .font(.system(size: 11.5, weight: pane == selectedPane ? .semibold : .medium))
                                .foregroundStyle(
                                    pane == selectedPane
                                        ? Palette.warmWhite.opacity(0.92)
                                        : Palette.textSecondary
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
            .padding(.horizontal, 8)
            .padding(.top, 10)

            Spacer(minLength: 18)

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)

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
            .padding(8)
        }
        .frame(width: 190)
        .background(Color.white.opacity(0.012))
    }

    private var paneHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Text(selectedPane.indexLabel)
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(width: 22, height: 1)
                Text("06")
            }
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .foregroundStyle(Palette.textTertiary)

            Text(selectedPane.title(language: language))
                .font(.system(size: 25, weight: .semibold))
                .tracking(-0.7)
                .foregroundStyle(Palette.warmWhite)

            Text(selectedPane.detail(language: language))
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.textSecondary)
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
                connectionsOperation: $localAgentConnectionsOperation
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
                "Manage local Agent hooks and the optional Manus cloud connection.",
                language: language
            )
        case .general:
            return L10n.string(
                "Choose how Dev Island behaves when you sign in to this Mac.",
                language: language
            )
        case .notifications:
            return L10n.string(
                "Reserve interruptions for moments that genuinely need your attention.",
                language: language
            )
        case .usage:
            return L10n.string(
                "Read provider-authored usage windows locally, without retaining prompts.",
                language: language
            )
        case .updates:
            return L10n.string(
                "Control authenticated update checks for signed release builds.",
                language: language
            )
        case .support:
            return L10n.string(
                "Inspect private local history and copy a redacted diagnostic summary.",
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
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                Rectangle()
                    .fill(background)
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Palette.warmWhite.opacity(isSelected ? 0.62 : 0))
                    .frame(width: 1, height: 16)
            }
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
        if configuration.isPressed { return Color.white.opacity(0.065) }
        if isSelected { return Color.white.opacity(isHovering ? 0.06 : 0.045) }
        return Color.white.opacity(isHovering ? 0.028 : 0)
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
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(
                Palette.textSecondary.opacity(
                    configuration.isPressed ? 0.55 : (isHovering ? 1 : 0.82)
                )
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                Rectangle()
                    .fill(Color.white.opacity(isHovering ? 0.025 : 0))
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
                    .font(.system(size: 13, weight: .semibold))
                Text(L10n.string(subtitle, language: language))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
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
                .tint(Palette.warmWhite)
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
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.tourPanel)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 0.75)
                    }
            )
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
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
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
                        Text("Codex")
                            .font(.system(size: 12, weight: .semibold))
                        Text(L10n.string(
                            snapshot.isStale() ? "STALE" : "LOCAL",
                            language: language
                        ))
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.7)
                            .foregroundStyle(Palette.textTertiary)
                        Spacer()
                        Button(L10n.string("Refresh", language: language)) {
                            usage.refresh()
                        }
                            .buttonStyle(SettingsControlButtonStyle())
                    }

                    ForEach(snapshot.windows) { window in
                        usageWindow(window)
                    }

                    Text(snapshotFooter(snapshot))
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textTertiary)
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
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(L10n.format(
                    "%lld%% used",
                    language: language,
                    Int64(window.usedPercent.rounded())
                ))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.warmWhite.opacity(0.86))
            }

            ProgressView(value: window.usedPercent, total: 100)
                .progressViewStyle(.linear)
                .tint(usageTint(window.usedPercent))

            Text(resetLabel(window.resetsAt))
                .font(.system(size: 10))
                .foregroundStyle(Palette.textTertiary)
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
                    .font(.system(size: 12, weight: .semibold))
                Text(L10n.string(detail, language: language))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(L10n.string("Refresh", language: language)) { usage.refresh() }
                .buttonStyle(SettingsControlButtonStyle())
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
        if usedPercent >= 90 { return Palette.stateFailed }
        if usedPercent >= 75 { return Palette.stateWaiting }
        return Palette.warmWhite.opacity(0.82)
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
                            .font(.system(size: 13, weight: .semibold))
                        Text(L10n.string(
                            "Updates are verified before extraction and installation.",
                            language: language
                        ))
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                    }

                    Spacer(minLength: 8)

                    Button(L10n.string("Check Now", language: language)) {
                        updates.checkForUpdates()
                    }
                    .buttonStyle(SettingsControlButtonStyle())
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
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.tourPanel)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 0.75)
                    }
            )
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
                            .font(.system(size: 13, weight: .semibold))
                        Text(L10n.string(
                            "Offline review copies bundled with this build. No browser or network is required.",
                            language: language
                        ))
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 8) {
                        ForEach(LegalDocumentKind.allCases) { kind in
                            Button(kind.buttonTitle(language: language)) {
                                selectedLegalDocument = kind
                            }
                            .buttonStyle(SettingsControlButtonStyle())
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
                            .font(.system(size: 13, weight: .semibold))
                        Text(diagnosticsFeedback.message
                             ?? L10n.string(
                                diagnosticsFeedback.copied
                                    ? "Copied — ready to paste into a support message."
                                    : "Aggregate app and session state only. No keys, prompts, paths, titles, URLs, or session IDs.",
                                language: language
                             ))
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textSecondary)
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
                        .buttonStyle(SettingsControlButtonStyle())
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
                        .buttonStyle(SettingsControlButtonStyle())
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
                            .font(.system(size: 13, weight: .semibold))
                        Text(historyMessage
                             ?? L10n.string(
                                "Remove persisted task and progress records from this Mac. Active sessions stay visible.",
                                language: language
                             ))
                            .font(.system(size: 11))
                            .foregroundStyle(historyMessage == nil
                                             ? Palette.textSecondary
                                             : Palette.warmWhite.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 8) {
                        Button(L10n.string("View History", language: language)) {
                            showHistory = true
                        }
                        .buttonStyle(SettingsControlButtonStyle())
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
                            .buttonStyle(SettingsControlButtonStyle(isDestructive: true))
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
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.tourPanel)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 0.75)
                    }
            )
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
                color: Palette.stateWaiting,
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
                    .font(.system(size: 12, weight: .semibold))
                Text(L10n.string(
                    "Dev Island ended before its brief startup health check completed. This can follow a quick Force Quit, restart, power loss, or a crash. No crash report was read or sent.",
                    language: language
                ))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if consecutiveStartupInterruptions >= 2 {
                    Text(L10n.string(
                        "This happened repeatedly. Keep this launch open briefly, then relaunch. If it repeats, copy the private diagnostic summary below.",
                        language: language
                    ))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.stateWaiting.opacity(0.82))
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
                .fill(Palette.stateWaiting.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Palette.stateWaiting.opacity(0.20), lineWidth: 0.75)
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
                            .font(.system(size: 13, weight: .semibold))
                        Text(L10n.string(
                            "Brief, distinct cues for input, failure, and completion.",
                            language: language
                        ))
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                    }

                    Spacer(minLength: 12)

                    Button(L10n.string("Preview", language: language)) {
                        TaskNotifier.shared.previewSignalSound()
                    }
                    .buttonStyle(SettingsControlButtonStyle())
                    .disabled(!signalSounds)

                    Toggle(
                        L10n.string("Signal Sounds", language: language),
                        isOn: $signalSounds
                    )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(Palette.warmWhite)
                        .accessibilityHint(
                            L10n.string(
                                "Plays short cues through macOS notifications.",
                                language: language
                            )
                        )
                }
                .padding(16)

                if notificationsEnabled, let authorizationIssue {
                    settingsDivider.padding(.leading, 16)
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.stateWaiting)
                        Text(L10n.string(authorizationIssue, language: language))
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                        Spacer()
                        Button(L10n.string("Open System Settings", language: language)) {
                            openNotificationSettings()
                        }
                        .buttonStyle(SettingsControlButtonStyle())
                    }
                    .padding(16)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.tourPanel)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 0.75)
                    }
            )
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

private struct ConnectedServicesSection: View {
    let store: TaskStore
    let showsTitle: Bool
    @Binding private var connectionsOperation: LocalAgentConnectionsOperationState
    @State private var searchText = ""
    @State private var installationRefreshToken = UUID()
    @State private var hasManagedLocalHooks = false
    @State private var isRefreshingManagedHookState = true
    @State private var managedHookRefreshID = UUID()
    @State private var showDisconnectAllConfirmation = false
    @State private var liveReadinessCheckState: LocalLiveReadinessCheckState
    @Environment(\.devIslandLanguage) private var language

    init(
        store: TaskStore,
        showsTitle: Bool = true,
        initialLiveReadinessSnapshot: LocalLiveReadinessSnapshot? = nil,
        connectionsOperation: Binding<LocalAgentConnectionsOperationState>
    ) {
        self.store = store
        self.showsTitle = showsTitle
        _connectionsOperation = connectionsOperation
        _liveReadinessCheckState = State(
            initialValue: LocalLiveReadinessCheckState(
                snapshot: initialLiveReadinessSnapshot
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsTitle { sectionTitle("Agent Connections") }

            switch store.localHookServiceStatus {
            case .retrying, .unavailable, .stopped:
                LocalHookServiceNotice(store: store)
            case .starting, .listening:
                EmptyView()
            }

            LocalLiveReadinessCard(
                snapshot: liveReadinessCheckState.snapshot,
                isChecking: liveReadinessCheckState.isChecking,
                isMutationInProgress: connectionsOperation.isMutating,
                onCheck: checkLiveReadiness
            )

            if LocalAgentRegistry.all.count > 6 {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Palette.textTertiary)
                    TextField(
                        L10n.string("Search agents", language: language),
                        text: $searchText
                    )
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Palette.tourPanel)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Palette.hairline, lineWidth: 0.75)
                        }
                )
            }

            ForEach(
                SettingsAgentGroup.ordered(
                    hasLocalAgents: !filteredLocalAgents.isEmpty,
                    showsManus: showsManus
                ),
                id: \.self
            ) { group in
                agentGroup(group)
            }

            if !showsManus && filteredLocalAgents.isEmpty {
                ContentUnavailableView {
                    Label(
                        L10n.string("No matching agents", language: language),
                        systemImage: "magnifyingglass"
                    )
                } description: {
                    Text(L10n.string(
                        "Try a name such as Codex, Claude, or Cursor.",
                        language: language
                    ))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }
        }
        .onAppear { refreshManagedHookState() }
        .onDisappear {
            managedHookRefreshID = UUID()
            liveReadinessCheckState.invalidate()
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

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var showsManus: Bool {
        normalizedSearch.isEmpty || "manus cloud".contains(normalizedSearch)
    }

    private var filteredLocalAgents: [LocalAgentDescriptor] {
        guard !normalizedSearch.isEmpty else { return LocalAgentRegistry.all }
        return LocalAgentRegistry.all.filter { descriptor in
            [descriptor.displayName, descriptor.source, descriptor.settingsSubtitle]
                .joined(separator: " ")
                .lowercased()
                .contains(normalizedSearch)
        }
    }

    private var serviceGroupBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Palette.tourPanel)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Palette.hairline, lineWidth: 0.75)
            }
    }

    @ViewBuilder
    private func agentGroup(_ group: SettingsAgentGroup) -> some View {
        switch group {
        case .local:
            groupLabel("Local Agents")
            VStack(spacing: 0) {
                // Local agents come straight from the registry: adding an
                // agent to LocalAgentRegistry adds its Settings row.
                ForEach(filteredLocalAgents, id: \.source) { descriptor in
                    if descriptor.source != filteredLocalAgents.first?.source { rowDivider }
                    LocalAgentServiceRow(
                        descriptor: descriptor,
                        refreshToken: installationRefreshToken,
                        connectionsOperation: $connectionsOperation
                    )
                }

                if normalizedSearch.isEmpty {
                    rowDivider
                    localAgentMaintenanceRow
                }
            }
            .background(serviceGroupBackground)

        case .cloud:
            groupLabel("Cloud Agent")
            ManusServiceRow(store: store)
                .background(serviceGroupBackground)
        }
    }

    private func groupLabel(_ text: String) -> some View {
        Text(L10n.string(text, language: language))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.textTertiary)
    }

    private var rowDivider: some View {
        settingsDivider.padding(.leading, 16)
    }

    private var localAgentMaintenanceRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("Local Agent Hooks", language: language))
                    .font(.system(size: 12, weight: .semibold))
                Text(maintenanceMessage ?? maintenanceStatusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(maintenanceFailed
                                     ? Palette.stateFailed.opacity(0.9)
                                     : Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                        hasManagedLocalHooks ? "Disconnect All…" : "All Disconnected",
                        language: language
                    ))
                }
                .buttonStyle(SettingsControlButtonStyle(isDestructive: hasManagedLocalHooks))
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
        .padding(.vertical, 12)
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
        guard let checkID = liveReadinessCheckState.begin() else { return }

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
                Text(content.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.warmWhite.opacity(0.92))
                Text(content.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
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
            .buttonStyle(SettingsControlButtonStyle())
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
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.018))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(borderColor, lineWidth: 0.75)
                }
        )
        .accessibilityElement(children: .contain)
    }

    private var buttonTitle: String {
        if isChecking { return "Checking…" }
        return snapshot == nil ? "Check this Mac" : "Check again"
    }

    private var tint: Color {
        switch content.tone {
        case .neutral:   return Palette.textSecondary
        case .checking:  return Palette.stateRunning
        case .retry:     return Palette.stateRunning
        case .ready:     return Palette.stateCompleted
        case .attention: return Palette.stateWaiting
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

    private var borderColor: Color {
        switch content.tone {
        case .neutral: return Palette.hairline
        case .retry: return tint.opacity(0.20)
        case .checking, .ready, .attention: return tint.opacity(0.27)
        }
    }
}

/// Appears only when the shared loopback listener needs attention. Healthy
/// operation stays quiet; failed delivery must not masquerade as a connected
/// integration whose events are silently disappearing.
private struct LocalHookServiceNotice: View {
    let store: TaskStore
    @Environment(\.devIslandLanguage) private var language

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(Circle().fill(tint.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string(title, language: language))
                    .font(.system(size: 12, weight: .semibold))
                Text(L10n.string(detail, language: language))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(L10n.string("Retry Now", language: language)) {
                store.retryLocalHookService()
            }
            .buttonStyle(SettingsControlButtonStyle())
            .accessibilityHint(
                L10n.string("Restarts the local Agent listener", language: language)
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.055))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(tint.opacity(0.28), lineWidth: 0.75)
                }
        )
        .accessibilityElement(children: .contain)
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
            return Palette.stateWaiting
        case .unavailable, .stopped:
            return Palette.stateFailed
        case .starting, .listening:
            return Palette.stateRunning
        }
    }

    private var iconName: String {
        switch store.localHookServiceStatus {
        case .retrying, .starting:
            return "arrow.clockwise"
        case .unavailable, .stopped:
            return "exclamationmark"
        case .listening:
            return "checkmark"
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
            HStack(spacing: 10) {
                AgentLogoBadge(
                    source: "manus",
                    size: 24,
                    ink: Palette.warmWhite.opacity(0.82),
                    badge: Color.white.opacity(0.045)
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Manus").font(.system(size: 13, weight: .semibold))
                    Text(L10n.string(statusLine, language: language))
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                trailingControl
            }

            // Show key entry when not configured / invalid. When valid,
            // show a "Disconnect" button only — no need to expose the key.
            if store.apiKeyStatus != .valid {
                keyField
            }

            if let lastError {
                Text(lastError)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.stateFailed)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
            .buttonStyle(SettingsControlButtonStyle(isDestructive: true))
        } else {
            Button {
                Task { await connect() }
            } label: {
                Text(L10n.string("Connect", language: language))
            }
            .buttonStyle(SettingsControlButtonStyle())
            .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var keyField: some View {
        // Per S's docs/manus-api-field-notes.md, the real API key
        // format is `sk-…` (not the `mk_live_…` from the public docs
        // example). Placeholder updated to match what users actually
        // get from manus.im.
        SecureField("sk-…", text: $apiKeyDraft)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Palette.tourCanvas)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 0.75)
                    }
            )
            .onSubmit {
                guard !apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                Task { await connect() }
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

/// Enables/disables a local agent integration by installing hook entries
/// into its config file (via the generic `LocalHooksInstaller`). Sessions
/// report their lifecycle to the always-running `LocalHookServer` — no API
/// key, no tunnel. Row identity (name, subtitle, config path, logo) comes
/// entirely from the agent's `LocalAgentDescriptor`.
private struct LocalAgentServiceRow: View {
    let descriptor: LocalAgentDescriptor
    let refreshToken: UUID
    @Binding var connectionsOperation: LocalAgentConnectionsOperationState

    @State private var configurationState = LocalAgentInstallationOperationState()
    @State private var lastError: String?
    @State private var isVendorActivationVerified = false
    @State private var isCheckingVendorActivation = false
    @State private var activationCheckToken = UUID()
    @Environment(\.devIslandLanguage) private var language

    private var installer: LocalHooksInstaller { .init(descriptor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AgentLogoBadge(
                    source: descriptor.source,
                    size: 24,
                    ink: Palette.warmWhite.opacity(0.82),
                    badge: Color.white.opacity(0.045)
                )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(descriptor.displayName)
                            .font(.system(size: 13, weight: .semibold))
                        if descriptor.releaseStage == .preview {
                            Text(L10n.string("PREVIEW", language: language))
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.7)
                            .foregroundStyle(Palette.tourAccent.opacity(0.76))
                                .accessibilityLabel(
                                    L10n.string("Preview connector", language: language)
                                )
                        }
                    }
                    Text(L10n.string(statusLine, language: language))
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                if configurationState.isBusy {
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityElement(children: .combine)
                } else {
                    switch configurationState.installationState {
                    case .checking:
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityLabel(
                                L10n.string("Checking agent configuration", language: language)
                            )
                    case .current:
                        HStack(spacing: 7) {
                            if descriptor.hookActivationRequirement.reviewCommand != nil,
                               !isVendorActivationVerified {
                                Button {
                                    refreshVendorActivationIfNeeded()
                                } label: {
                                    Text(L10n.string(
                                        isCheckingVendorActivation ? "Checking…" : "Check again",
                                        language: language
                                    ))
                                }
                                .buttonStyle(SettingsControlButtonStyle())
                                .disabled(
                                    isCheckingVendorActivation
                                        || connectionsOperation.isMutating
                                )
                                .accessibilityHint(
                                    L10n.string(
                                        "Reads Codex Hook status without changing trust or configuration",
                                        language: language
                                    )
                                )
                            }

                            Button(role: .destructive) {
                                apply(.disable)
                            } label: {
                                Text(L10n.string("Disable", language: language))
                            }
                            .buttonStyle(SettingsControlButtonStyle(isDestructive: true))
                            .disabled(connectionsOperation.isMutating)
                        }

                    case .updateRequired:
                        Button {
                            apply(.update)
                        } label: {
                            Text(L10n.string("Update", language: language))
                        }
                        .buttonStyle(SettingsControlButtonStyle())
                        .disabled(connectionsOperation.isMutating)

                    case .absent:
                        Button {
                            apply(.enable)
                        } label: {
                            Text(L10n.string("Enable", language: language))
                        }
                        .buttonStyle(SettingsControlButtonStyle())
                        .disabled(connectionsOperation.isMutating)
                    }
                }
            }

            if let lastError {
                Text(lastError)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.stateFailed)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .onAppear { refreshInstallationState() }
        .onChange(of: refreshToken) { _, _ in refreshInstallationState() }
        .onDisappear {
            configurationState.invalidate()
            activationCheckToken = UUID()
            isCheckingVendorActivation = false
        }
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
        activationCheckToken = UUID()
        isVendorActivationVerified = false
        isCheckingVendorActivation = false
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
            refreshVendorActivationIfNeeded()
        }
    }

    private var statusLine: String {
        if let operation = configurationState.activeMutation {
            return operation.progressLocalizationKey
        }
        switch configurationState.installationState {
        case .checking:
            return "Checking configuration…"
        case .absent:
            return descriptor.settingsSubtitle
        case .current:
            return installedStatusLine
        case .updateRequired:
            return L10n.string("Update available", language: language)
        }
    }

    private func refreshInstallationState() {
        guard let refreshID = configurationState.beginRefresh() else { return }
        activationCheckToken = UUID()
        isCheckingVendorActivation = false
        isVendorActivationVerified = false
        let installer = installer

        Task { @MainActor in
            let state = await LocalAgentConfigurationExecutor.run(
                priority: .utility
            ) {
                LocalAgentConfigurationWorker.inspect(installer: installer)
            }
            guard configurationState.accept(state, for: refreshID) else { return }
            refreshVendorActivationIfNeeded()
        }
    }

    private var installedStatusLine: String {
        if let command = descriptor.hookActivationRequirement.reviewCommand {
            if isCheckingVendorActivation {
                return L10n.format(
                    "Checking %@ Hook trust…",
                    language: language,
                    descriptor.displayName
                )
            }
            if isVendorActivationVerified {
                return L10n.format(
                    "Connected — Hook trust verified by %@",
                    language: language,
                    descriptor.displayName
                )
            }
            return L10n.format(
                "Configured — review and trust the Dev Island entries in %@ %@",
                language: language,
                descriptor.displayName,
                command
            )
        }
        if descriptor.capabilities.permissionRequests == .bidirectional
            || descriptor.capabilities.questionRequests == .bidirectional
            || descriptor.capabilities.planReviews == .bidirectional {
            return L10n.string(
                descriptor.releaseStage == .preview
                    ? "Preview connected — requests work in simulation; real CLI check pending"
                    : "Connected — requests can be handled in the island",
                language: language
            )
        }
        if descriptor.capabilities.permissionRequests == .observeOnly
            || descriptor.capabilities.questionRequests == .observeOnly
            || descriptor.capabilities.planReviews == .observeOnly {
            return L10n.string(
                descriptor.releaseStage == .preview
                    ? "Preview connected — real CLI acceptance pending"
                    : "Connected — attention requests appear automatically",
                language: language
            )
        }
        return L10n.string(
            "Connected — new sessions appear automatically",
            language: language
        )
    }

    private func refreshVendorActivationIfNeeded() {
        let token = UUID()
        activationCheckToken = token
        isVendorActivationVerified = false

        guard configurationState.installationState == .current,
              !configurationState.isBusy,
              descriptor.hookActivationRequirement.reviewCommand != nil else {
            isCheckingVendorActivation = false
            return
        }
        isCheckingVendorActivation = true
        let source = descriptor.source

        Task { @MainActor in
            let snapshot = await Task.detached(priority: .utility) {
                LocalAgentHookDiagnostics.snapshotResolvingVendorActivation()
            }.value
            guard activationCheckToken == token,
                  configurationState.installationState == .current,
                  !configurationState.isBusy else { return }
            isCheckingVendorActivation = false
            isVendorActivationVerified = snapshot.agents.first {
                $0.source == source
            }?.state == .connected
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
                            .font(.system(size: 13, weight: .semibold))
                        Text(L10n.string(
                            "Change Dev Island without changing your Mac language.",
                            language: language
                        ))
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textSecondary)
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
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(Palette.textTertiary)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.warmWhite.opacity(0.82))
                        .padding(.horizontal, 10)
                        .frame(width: 150, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.white.opacity(0.025))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(Palette.hairline, lineWidth: 0.75)
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
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.stateFailed)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

                if !canObserveGlobalKeys {
                    settingsDivider.padding(.leading, 16)
                    escShortcutRow
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.tourPanel)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 0.75)
                    }
            )
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
                .foregroundStyle(Palette.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string("Close the Panel with Esc", language: language))
                    .font(.system(size: 13, weight: .semibold))
                Text(L10n.string(
                    "Needs Accessibility access — Esc is pressed while your editor still has focus. Clicking away always closes the panel.",
                    language: language
                ))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                InputPermissions.openAccessibilitySettings()
            } label: {
                Text(L10n.string("Open System Settings", language: language))
            }
            .buttonStyle(SettingsControlButtonStyle())
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
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Palette.warmWhite.opacity(0.72))
}

private var settingsDivider: some View {
    Rectangle()
        .fill(Palette.hairline)
        .frame(height: 1)
}

struct SettingsControlButtonStyle: ButtonStyle {
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(
                isDestructive
                    ? Palette.stateFailed.opacity(configuration.isPressed ? 0.62 : 0.88)
                    : Palette.warmWhite.opacity(configuration.isPressed ? 0.55 : 0.76)
            )
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.045 : 0.025))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 0.75)
                    }
            )
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

#if PREVIEWS && DEBUG
#Preview("Settings — not configured") {
    SettingsView(previewStore: .presentationFixture())
        .frame(width: 720, height: 520)
}
#endif
