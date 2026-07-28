import SwiftUI
import IslandCore
import ServiceManagement

/// Top-level Settings UI (CLAUDE_CLIENT.md §6 task 6). Three sections:
///
/// - **Connected Services** — Manus row with API key entry + connect/
///   disconnect controls; Claude Code and Cursor rows show a grayed-out
///   "Coming Soon" badge per spec.
/// - **General** — Launch at Login toggle wired through `SMAppService`.
/// - **Footer** — Quit button (NSApp.terminate). Closing the window
///   alone won't quit, since we're an `.accessory` activation app.
///
/// Bound directly to `TaskStore.shared` so the Manus row's status dot
/// reflects live `apiKeyStatus` / `connectionStatus` without manual
/// notification plumbing.
struct SettingsView: View {
    @State private var store = TaskStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                ConnectedServicesSection(store: store)

                GeneralSection()

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
            Text("Configure your Manus connection and app preferences.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Quit Island") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }
}

// MARK: - Connected Services

private struct ConnectedServicesSection: View {
    let store: TaskStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Connected Services")

            VStack(spacing: 0) {
                ManusServiceRow(store: store)
                rowDivider
                ComingSoonRow(name: "Claude Code", subtitle: "Local agent integration")
                rowDivider
                ComingSoonRow(name: "Cursor", subtitle: "Editor-side task ingestion")
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
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
                statusDot
                VStack(alignment: .leading, spacing: 2) {
                    Text("Manus").font(.system(size: 13, weight: .semibold))
                    Text(statusLine)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
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
                    .foregroundStyle(Color.red)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        switch store.apiKeyStatus {
        case .valid:        return .green
        case .invalid:      return .red
        case .notConfigured: return Color.secondary.opacity(0.5)
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

// MARK: - Coming Soon row

private struct ComingSoonRow: View {
    let name: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Coming Soon")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.secondary.opacity(0.12))
                )
        }
        .padding(16)
        .opacity(0.7)
    }
}

// MARK: - General section (Launch at Login)

private struct GeneralSection: View {
    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)
    @State private var lastError: String?

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
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
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

#if PREVIEWS && DEBUG
#Preview("Settings — not configured") {
    SettingsView()
        .frame(width: 560, height: 480)
}
#endif
