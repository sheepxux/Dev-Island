import SwiftUI
import IslandCore

/// Expanded panel content. Single-column layout per CLAUDE_CLIENT.md §6
/// Task 2: header → scrollable task list → "Connect Service" footer.
struct NotchPanelView: View {
    let tasks: [AgentTask]
    let connectionStatus: ConnectionStatus
    /// Layout snapshot of the host display so the panel knows whether to
    /// reserve space for the hardware notch at the top.
    let layout: NotchMetrics.Layout
    let onTaskTap: (AgentTask) -> Void
    let onSettingsTap: () -> Void
    let onConnectTap: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            NotchPanelShape(
                notchWidth: layout.notchWidth * (layout.hasNotch ? 1 : 0),
                notchHeight: layout.notchHeight
            )
            .fill(Palette.notchBlack)

            VStack(spacing: 0) {
                // Reserve vertical room for the hardware notch on notched
                // displays so the header doesn't fight with it.
                Color.clear.frame(height: notchReserve)

                header
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                taskList

                footerDivider

                connectFooter
            }
        }
        .frame(width: panelWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 6) {
            Text("Tasks")
                .font(Typo.sectionHeader)
                .foregroundStyle(.white)
            Text("(\(tasks.count))")
                .font(Typo.sectionHeader)
                .foregroundStyle(.white.opacity(0.45))
                .monospacedDigit()

            Spacer()

            connectionDot

            Button(action: onSettingsTap) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var connectionDot: some View {
        Circle()
            .fill(connectionColor)
            .frame(width: 6, height: 6)
            .help(connectionTooltip)
    }

    private var connectionColor: Color {
        switch connectionStatus {
        case .connected:                 return Palette.stateCompleted
        case .reconnecting:              return Palette.stateWaiting
        case .disconnected, .degraded:   return Palette.stateFailed
        }
    }

    private var connectionTooltip: String {
        switch connectionStatus {
        case .connected:                 return "Connected"
        case .reconnecting:              return "Reconnecting…"
        case .disconnected:              return "Disconnected"
        case .degraded(let reason):      return reason
        }
    }

    @ViewBuilder
    private var taskList: some View {
        if tasks.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(tasks) { task in
                        TaskCard(task: task, onTap: { onTaskTap(task) })
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 320)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
            Text("No active tasks")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    @ViewBuilder
    private var footerDivider: some View {
        Rectangle()
            .fill(Palette.divider)
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    @ViewBuilder
    private var connectFooter: some View {
        Button(action: onConnectTap) {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text("Connect Service")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Geometry

    private var panelWidth: CGFloat {
        if layout.hasNotch {
            // Wide enough that the notch corridor (top center) doesn't
            // squeeze the header content. Cap at panelMaxWidth.
            return min(NotchMetrics.panelMaxWidth, layout.notchWidth + 240)
        }
        return NotchMetrics.panelWidth
    }

    private var notchReserve: CGFloat {
        layout.hasNotch ? layout.notchHeight + 4 : 0
    }
}

#if PREVIEWS
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
        connectionStatus: .connected,
        layout: previewLayoutNoNotch,
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
        connectionStatus: .connected,
        layout: previewLayoutNotched,
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
        connectionStatus: .reconnecting,
        layout: previewLayoutNoNotch,
        onTaskTap: { _ in },
        onSettingsTap: {},
        onConnectTap: {}
    )
    .padding(40)
    .background(Color.gray.opacity(0.25))
}
#endif
