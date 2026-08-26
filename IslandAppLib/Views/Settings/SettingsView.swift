import SwiftUI
import IslandCore
import ServiceManagement

/// Top-level Settings UI (CLAUDE_CLIENT.md §6 task 6). Three sections:
///
/// - **Connected Services** — Manus row with API key entry + connect/
///   disconnect controls; Claude Code, Codex and Cursor rows toggle local
///   hook installation (no API key needed).
/// - **General** — Launch at Login toggle wired through `SMAppService`.
/// - **Footer** — Quit button (NSApp.terminate). Closing the window
///   alone won't quit, since we're an `.accessory` activation app.
///
/// Bound directly to `TaskStore.shared` so the Manus row's status dot
/// reflects live `apiKeyStatus` / `connectionStatus` without manual
/// notification plumbing.
public struct SettingsView: View {
    @State private var store = TaskStore.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                ConnectedServicesSection(store: store)

                GeneralSection()

                NotificationsSection()

                settingsDivider

                footer
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 520, minHeight: 440)
        .background(Palette.tourCanvas)
        .foregroundStyle(Palette.warmWhite)
        .tint(Palette.warmWhite)
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(size: 25, weight: .regular, design: .serif))
                .tracking(-0.35)
                .foregroundStyle(Palette.warmWhite)
            Text("Configure your agent connections and app preferences.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var footer: some View {
        HStack {
            Button("Welcome Tour") {
                NotificationCenter.default.post(name: .islandOpenOnboardingRequested, object: nil)
            }
            .buttonStyle(SettingsTextButtonStyle())
            Spacer()
            Button("Quit Dev Island") {
                NSApp.terminate(nil)
            }
            .buttonStyle(SettingsTextButtonStyle(isDestructive: true))
            .keyboardShortcut("q", modifiers: [.command])
        }
    }
}

// MARK: - Notifications

private struct NotificationsSection: View {
    @AppStorage(TaskNotificationPreferences.attentionRequiredKey)
    private var attentionRequired = true

    @AppStorage(TaskNotificationPreferences.completionsKey)
    private var completions = false

    @State private var authorizationIssue: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Notifications")

            VStack(spacing: 0) {
                notificationToggle(
                    title: "Attention Required",
                    subtitle: "Bring the island forward when a task needs input or fails.",
                    isOn: $attentionRequired
                )

                settingsDivider.padding(.leading, 16)

                notificationToggle(
                    title: "Task Completed",
                    subtitle: "Optionally notify when a task finishes.",
                    isOn: $completions
                )

                if notificationsEnabled, let authorizationIssue {
                    settingsDivider.padding(.leading, 16)
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.stateWaiting)
                        Text(authorizationIssue)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                        Spacer()
                        Button("Open System Settings") {
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

    private func notificationToggle(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .toggleStyle(.switch)
        .tint(Palette.warmWhite)
        .padding(16)
    }
}

// MARK: - Connected Services

private struct ConnectedServicesSection: View {
    let store: TaskStore
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Agent Connections")

            if LocalAgentRegistry.all.count > 6 {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Palette.textTertiary)
                    TextField("Search agents", text: $searchText)
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

            if showsManus {
                groupLabel("Cloud Agent")
                ManusServiceRow(store: store)
                    .background(serviceGroupBackground)
            }

            if !filteredLocalAgents.isEmpty {
                groupLabel("Local Agents")
                VStack(spacing: 0) {
                    // Local agents come straight from the registry: adding an
                    // agent to LocalAgentRegistry adds its Settings row.
                    ForEach(filteredLocalAgents, id: \.source) { descriptor in
                        if descriptor.source != filteredLocalAgents.first?.source { rowDivider }
                        LocalAgentServiceRow(descriptor: descriptor)
                    }
                }
                .background(serviceGroupBackground)
            }

            if !showsManus && filteredLocalAgents.isEmpty {
                ContentUnavailableView(
                    "No matching agents",
                    systemImage: "magnifyingglass",
                    description: Text("Try a name such as Codex, Claude, Cursor, or Gemini.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }
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

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.textTertiary)
    }

    private var rowDivider: some View {
        settingsDivider.padding(.leading, 16)
    }
}

// MARK: - Manus row

private struct ManusServiceRow: View {
    let store: TaskStore

    @State private var apiKeyDraft: String = ""
    @State private var isSubmitting = false
    @State private var lastError: String?

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
                    Text(statusLine)
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
        switch store.apiKeyStatus {
        case .valid:
            switch store.connectionStatus {
            case .connected:           return "Connected"
            case .reconnecting:        return "Reconnecting…"
            case .disconnected:        return "Disconnected"
            case .degraded(let why):   return "Degraded — \(why)"
            }
        case .invalid:       return "Stored key is invalid"
        case .notConfigured: return "Not connected — paste an API key below"
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        if isSubmitting {
            ProgressView().controlSize(.small)
        } else if store.apiKeyStatus == .valid {
            Button("Disconnect", role: .destructive) {
                disconnect()
            }
            .buttonStyle(SettingsControlButtonStyle(isDestructive: true))
        } else {
            Button("Connect") {
                Task { await connect() }
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
            lastError = friendlyMessage(for: error)
        }
    }

    @MainActor
    private func disconnect() {
        store.clearAPIKey()
        apiKeyDraft = ""
        lastError = nil
    }

    private func friendlyMessage(for error: Error) -> String {
        let raw = "\(error)"
        if raw.contains("unauthorized") {
            return "API key rejected by Manus. Double-check the value."
        }
        if raw.contains("networkUnavailable") {
            return "Network unavailable. Check your connection and retry."
        }
        return "Couldn't connect: \(raw)"
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

    @State private var installed = false
    @State private var lastError: String?

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
                    Text(descriptor.displayName).font(.system(size: 13, weight: .semibold))
                    Text(installed
                         ? "Connected — new sessions appear automatically"
                         : descriptor.settingsSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                if installed {
                    Button("Disable", role: .destructive) {
                        toggle({ try installer.uninstall() }, to: false)
                    }
                    .buttonStyle(SettingsControlButtonStyle(isDestructive: true))
                } else {
                    Button("Enable") {
                        toggle({ try installer.install() }, to: true)
                    }
                    .buttonStyle(SettingsControlButtonStyle())
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
        .onAppear { installed = installer.isInstalled() }
    }

    private func toggle(_ action: () throws -> Void, to newState: Bool) {
        do {
            try action()
            installed = newState
            lastError = nil
        } catch {
            lastError = "Couldn't update \(descriptor.configPath): \(error.localizedDescription)"
        }
    }
}

// MARK: - General section (Launch at Login)

private struct GeneralSection: View {
    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)
    @State private var lastError: String?
    @State private var canObserveGlobalKeys = InputPermissions.canObserveGlobalKeys

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("General")

            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: $launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Open Island automatically when you log in.")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .toggleStyle(.switch)
                .padding(16)
                .onChange(of: launchAtLogin) { _, new in
                    apply(launchAtLogin: new)
                }

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
                Text("Close the Panel with Esc")
                    .font(.system(size: 13, weight: .semibold))
                Text("Needs Accessibility access — Esc is pressed while your editor still has focus. Clicking away always closes the panel.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Open System Settings") {
                InputPermissions.openAccessibilitySettings()
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
            lastError = "Couldn't update Login Items: \(error.localizedDescription)"
            self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }
}

// MARK: - Helpers

@ViewBuilder
private func sectionTitle(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Palette.warmWhite.opacity(0.72))
}

private var settingsDivider: some View {
    Rectangle()
        .fill(Palette.hairline)
        .frame(height: 1)
}

private struct SettingsTextButtonStyle: ButtonStyle {
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(
                isDestructive
                    ? Palette.stateFailed.opacity(configuration.isPressed ? 0.65 : 0.88)
                    : Palette.warmWhite.opacity(configuration.isPressed ? 0.52 : 0.68)
            )
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .animation(Motion.press, value: configuration.isPressed)
    }
}

private struct SettingsControlButtonStyle: ButtonStyle {
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
    SettingsView()
        .frame(width: 560, height: 480)
}
#endif
