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
    let highlightedTask: TaskIdentity?
    let onTaskTap: (AgentTask) -> Void
    let onSettingsTap: () -> Void
    let onConnectTap: () -> Void
    /// When `false` the view renders content only — the parent
    /// (`IslandRootView`) is drawing a shared backdrop that spans both bar
    /// and panel states for a single SwiftUI morph.
    var drawsBackdrop: Bool = true

    var body: some View {
        ZStack(alignment: .top) {
            if drawsBackdrop {
                NotchPanelShape(
                    notchWidth: layout.hasNotch ? layout.notchWidth : 0,
                    notchHeight: layout.hasNotch ? layout.notchHeight : 0
                )
                .fill(Palette.notchBlack)
            }

            VStack(spacing: 0) {
                topRow
                taskList
                    .padding(.top, layout.hasNotch ? 8 : 0)
                footerDivider
                connectFooter
            }
        }
        .frame(width: panelWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Top row (header)

    /// On notched displays, header content is split into the side extensions
    /// flanking the hardware notch so the otherwise-empty space is used.
    /// On synthetic-notch displays, the header sits at the top of the
    /// panel below a small padding.
    @ViewBuilder
    private var topRow: some View {
        if layout.hasNotch {
            HStack(spacing: 0) {
                titleLabel
                    .padding(.leading, 14)
                    .frame(width: sideExtensionWidth, alignment: .leading)

                // Hardware notch corridor — transparent
                Spacer().frame(width: layout.notchWidth)

                trailingCluster
                    .padding(.trailing, 10)
                    .frame(width: sideExtensionWidth, alignment: .trailing)
            }
            .frame(height: layout.notchHeight)
        } else {
            HStack(spacing: 6) {
                titleLabel
                Spacer()
                trailingCluster
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private var titleLabel: some View {
        HStack(spacing: 6) {
            Text("Tasks")
                .font(Typo.sectionHeader)
                .foregroundStyle(.white)
            Text("(\(tasks.count))")
                .font(Typo.sectionHeader)
                .foregroundStyle(.white.opacity(0.45))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var trailingCluster: some View {
        HStack(spacing: 8) {
            connectionDot
            Button(action: onSettingsTap) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(pressedScale: 0.9))
            .pointingHandCursor()
        }
    }

    private var sideExtensionWidth: CGFloat {
        (panelWidth - layout.notchWidth) / 2
    }

    @ViewBuilder
    private var connectionDot: some View {
        // 250ms cross-fade matches the bar's StatusDot color transition
        // — keeps the panel header consistent with the rest of the
        // status palette when reconnecting/degraded states flap.
        Circle()
            .fill(connectionColor)
            .frame(width: 6, height: 6)
            .animation(Motion.colorTransition, value: connectionStatus)
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
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(tasks, id: \.identity) { task in
                            TaskCard(
                                task: task,
                                isHighlighted: task.identity == highlightedTask,
                                onTap: { onTaskTap(task) }
                            )
                            .id(task.identity)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
                .onChange(of: highlightedTask, initial: true) { _, identity in
                    guard let identity,
                          tasks.contains(where: { $0.identity == identity }) else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(identity, anchor: .center)
                    }
                }
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
        .buttonStyle(PressableButtonStyle())
        .pointingHandCursor()
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

}

// PREVIEWS && DEBUG — these previews reference TaskStore.previewTasks
// which lives behind a #if DEBUG extension; release builds (CI / Cask
// release artifact) need the block stripped entirely.
#if PREVIEWS && DEBUG
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
        highlightedTask: nil,
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
        highlightedTask: TaskStore.previewTasks.first?.identity,
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
        highlightedTask: nil,
        onTaskTap: { _ in },
        onSettingsTap: {},
        onConnectTap: {}
    )
    .padding(40)
    .background(Color.gray.opacity(0.25))
}
#endif
