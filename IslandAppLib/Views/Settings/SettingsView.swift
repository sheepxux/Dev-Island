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
            VStack(alignment: .leading, spacing: 28) {
                header

                ConnectedServicesSection(store: store)

                GeneralSection()

                NotificationsSection()

                Divider()

                footer
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 520, minHeight: 440)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(size: 22, weight: .semibold))
            Text("Configure your agent connections and app preferences.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Button("View Welcome Tour") {
                NotificationCenter.default.post(name: .islandOpenOnboardingRequested, object: nil)
            }
            Spacer()
            Button("Quit Island") {
                NSApp.terminate(nil)
            }
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
                    subtitle: "Notify when a task needs input or fails.",
                    isOn: $attentionRequired
                )

                Divider().padding(.leading, 16)

                notificationToggle(
                    title: "Task Completed",
                    subtitle: "Optionally notify when a task finishes.",
                    isOn: $completions
                )

                if notificationsEnabled, let authorizationIssue {
                    Divider().padding(.leading, 16)
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(authorizationIssue)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open System Settings") {
                            openNotificationSettings()
                        }
                        .controlSize(.small)
                    }
                    .padding(16)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
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
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
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

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search agents", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

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
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 16)
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
                    ink: .primary,
                    badge: Color.primary.opacity(0.06)
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Manus").font(.system(size: 13, weight: .semibold))
                    Text(statusLine)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    ServiceStatusBadge(label: badgeLabel, color: statusColor)
                    trailingControl
                }
            }

            // Show key entry when not configured / invalid. When valid,
            // show a "Disconnect" button only — no need to expose the key.
            if store.apiKeyStatus != .valid {
                keyField
            }

            if let lastError {
                Text(lastError)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red)
            }
        }
        .padding(16)
    }

    private var statusColor: Color {
        switch store.apiKeyStatus {
        case .valid:
            switch store.connectionStatus {
            case .connected: return .green
            case .reconnecting, .degraded: return .orange
            case .disconnected: return .red
            }
        case .invalid:       return .red
        case .notConfigured: return Color.secondary.opacity(0.5)
        }
    }

    private var badgeLabel: String {
        switch store.apiKeyStatus {
        case .invalid: return "Needs attention"
        case .notConfigured: return "Not connected"
        case .valid:
            switch store.connectionStatus {
            case .connected: return "Connected"
            case .reconnecting: return "Reconnecting"
            case .degraded: return "Degraded"
            case .disconnected: return "Disconnected"
            }
        }
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
        } else {
            Button("Connect") {
                Task { await connect() }
            }
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
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))
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
                    ink: .primary,
                    badge: Color.primary.opacity(0.06)
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.displayName).font(.system(size: 13, weight: .semibold))
                    Text(installed
                         ? "Hooks installed — sessions report status live"
                         : descriptor.settingsSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    ServiceStatusBadge(
                        label: installed ? "Enabled" : "Not enabled",
                        color: installed ? .green : Color.secondary.opacity(0.5)
                    )
                    if installed {
                        Button("Disable", role: .destructive) {
                            toggle({ try installer.uninstall() }, to: false)
                        }
                    } else {
                        Button("Enable") {
                            toggle({ try installer.install() }, to: true)
                        }
                    }
                }
            }

            if installed {
                Text("Applies to \(descriptor.displayName) sessions started after enabling.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let lastError {
                Text(lastError)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red)
            }
        }
        .padding(16)
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
                            .foregroundStyle(.secondary)
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
                        .foregroundStyle(Color.red)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

                if !canObserveGlobalKeys {
                    Divider().padding(.leading, 16)
                    escShortcutRow
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
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
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Close the Panel with Esc")
                    .font(.system(size: 13, weight: .semibold))
                Text("Needs Accessibility access — Esc is pressed while your editor still has focus. Clicking away always closes the panel.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Open System Settings") {
                InputPermissions.openAccessibilitySettings()
            }
            .controlSize(.small)
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
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
}

private struct ServiceStatusBadge: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .lineLimit(1)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.12))
        )
    }
}

#if PREVIEWS && DEBUG
#Preview("Settings — not configured") {
    SettingsView()
        .frame(width: 560, height: 480)
}
#endif
