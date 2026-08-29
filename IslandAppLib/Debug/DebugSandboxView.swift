#if DEBUG
import SwiftUI
import IslandCore

/// In-app debug controls (CLAUDE_CLIENT.md §6 task 10). Hosted by
/// `DebugSandboxWindow`, gated on `DEBUG`. Three groups:
///
/// - **Coordinator** — drive `IslandCoordinator` directly: expand /
///   collapse / toggle / re-pin window after a screen change.
/// - **Tasks** — inject one synthetic task per status, or wipe them all.
///   Hooks into `TaskStore.shared` via the `#if DEBUG` mutators in
///   `TaskStore+Debug.swift`.
/// - **Connection** — flip `connectionStatus` to exercise the panel's
///   header dot and any future degraded-bar visuals.
///
/// Live state preview at the bottom (task count + current mode + connection)
/// so you can see your effects without tabbing back to the island.
struct DebugSandboxView: View {
    private let coordinator = IslandCoordinator.shared
    @State private var store = TaskStore.shared

    /// Optional hook so the host (DebugSandboxWindow / AppDelegate) can
    /// reposition the IslandWindow on demand. Kept as a closure rather
    /// than a direct reference so this view doesn't pull in AppKit types.
    var onReposition: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Coordinator")
            coordinatorRow

            sectionHeader("Tasks")
            taskRow

            sectionHeader("Connection")
            connectionRow

            sectionHeader("Signal language")
            signalLanguagePreview

            Divider().padding(.vertical, 4)

            livePreview
        }
        .padding(16)
        .frame(width: 360)
    }

    // MARK: - Sections

    private var coordinatorRow: some View {
        HStack(spacing: 8) {
            Button("Expand")   { coordinator.expand() }
            Button("Collapse") { coordinator.collapse() }
            Button("Toggle")   { coordinator.toggle() }
            Spacer()
            Button("Reposition") { onReposition?() }
                .disabled(onReposition == nil)
        }
    }

    private var taskRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button("+ Running")   { store.debugSpawn(status: .running) }
                Button("+ Waiting")   { store.debugSpawn(status: .waiting) }
                Button("+ Completed") { store.debugSpawn(status: .completed) }
                Button("+ Failed")    { store.debugSpawn(status: .failed) }
            }
            HStack(spacing: 6) {
                Button("Seed 3 (preview set)") {
                    store.debugSetTasks(TaskStore.previewTasks)
                }
                Button("+ Codex Approval") {
                    store.debugSpawnApprovalRequest()
                }
                Button("+ Claude Question") {
                    store.debugSpawnQuestionRequest()
                }
            }
            HStack(spacing: 6) {
                Button("+ Claude Plan") {
                    store.debugSpawnPlanReview()
                }
                Spacer()
                Button("Clear all", role: .destructive) {
                    store.debugClearTasks()
                }
            }
        }
    }

    private var connectionRow: some View {
        HStack(spacing: 8) {
            Button("Connected")    { store.debugSetConnectionStatus(.connected) }
            Button("Reconnecting") { store.debugSetConnectionStatus(.reconnecting) }
            Button("Disconnected") { store.debugSetConnectionStatus(.disconnected) }
        }
    }

    private var signalLanguagePreview: some View {
        HStack(spacing: 0) {
            signalSample("Idle", state: .idle)
            signalSample("Run", state: .running)
            signalSample("Wait", state: .waiting)
            signalSample("Done", state: .completed)
            signalSample("Fail", state: .failed)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.notchBlack)
        )
    }

    private func signalSample(_ label: String, state: BarState) -> some View {
        VStack(spacing: 6) {
            StatusDot(state: state, size: 14)
                .frame(width: 20, height: 20)
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Live preview

    private var livePreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Live state")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                statLabel("mode",       value: "\(coordinator.mode)")
                statLabel("tasks",      value: "\(store.tasks.count)")
                statLabel("requests",   value: "\(store.pendingActionRequests.count)")
                statLabel("connection", value: connectionShortLabel)
            }
            .font(.system(size: 11, design: .monospaced))
        }
    }

    private var connectionShortLabel: String {
        switch store.connectionStatus {
        case .connected:        return "connected"
        case .reconnecting:     return "reconnecting"
        case .disconnected:     return "disconnected"
        case .degraded:         return "degraded"
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func statLabel(_ name: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text("\(name):").foregroundStyle(.secondary)
            Text(value)
        }
    }
}

#Preview("Debug Sandbox") {
    DebugSandboxView(onReposition: {})
}
#endif
