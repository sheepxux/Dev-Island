import SwiftUI
import IslandCore

/// Intrinsic height of the panel's content, published to `IslandRootView`
/// so the morphing silhouette can size itself to what's actually inside.
/// Before this existed the expanded height was a fixed 360pt guess, and
/// anything past ~5 tasks pushed the "Connect Service" footer outside the
/// silhouette's clip.
struct PanelContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Expanded panel content. A single warm graphite surface with line-based
/// hierarchy; rows only emerge on hover and task state is never used as a
/// decorative panel accent.
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
    /// Whether the panel is actually on screen. `false` keeps the layout
    /// (the parent measures it to size the silhouette) but stops the clock
    /// below and every per-card animation.
    var isLive: Bool = true

    var body: some View {
        ZStack(alignment: .top) {
            if drawsBackdrop {
                NotchPanelShape(
                    notchWidth: layout.hasNotch ? layout.notchWidth : 0,
                    notchHeight: layout.hasNotch ? layout.notchHeight : 0
                )
                .fill(Palette.islandTop)
            }

            VStack(spacing: 0) {
                topRow
                panelBody
                    .padding(.top, layout.hasNotch ? 8 : 0)
            }
            // Measured on the content stack rather than the outer frame:
            // the parent sizes the silhouette FROM this value, so reading
            // it off the parent-imposed frame would be circular.
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: PanelContentHeightKey.self,
                        value: proxy.size.height
                    )
                }
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
            .padding(.horizontal, 16)
            .padding(.top, 11)
            .padding(.bottom, 9)
        }
    }

    @ViewBuilder
    private var titleLabel: some View {
        HStack(spacing: 6) {
            Text("Sessions")
                .font(Typo.sectionHeader)
                .foregroundStyle(Palette.warmWhite.opacity(0.9))
            Text("\(tasks.count)")
                .font(Typo.barCount)
                .foregroundStyle(Palette.textTertiary)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var trailingCluster: some View {
        HStack(spacing: 7) {
            connectionDot
            Button(action: onConnectTap) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textSecondary.opacity(0.72))
                    .frame(width: 24, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(pressedScale: 0.98))
            .pointingHandCursor()
            .help("Connect an agent")

            Button(action: onSettingsTap) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textSecondary.opacity(0.72))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(pressedScale: 0.96))
            .pointingHandCursor()
        }
    }

    private var sideExtensionWidth: CGFloat {
        (panelWidth - layout.notchWidth) / 2
    }

    @ViewBuilder
    private var connectionDot: some View {
        // The same point-field signature used by task status keeps connection
        // state from falling back to a generic system dot.
        // — keeps the panel header consistent with the rest of the
        // status palette when reconnecting/degraded states flap.
        DotMatrixMark(
            color: connectionColor,
            size: 8,
            pattern: connectionPattern,
            intensity: connectionIntensity
        )
            .animation(Motion.colorTransition, value: connectionStatus)
            .help(connectionTooltip)
    }

    private var connectionColor: Color {
        switch connectionStatus {
        case .connected:                 return Palette.stateCompleted.opacity(0.85)
        case .reconnecting, .degraded:   return Palette.stateWaiting.opacity(0.85)
        case .disconnected:              return Color.white.opacity(0.20)
        }
    }

    private var connectionPattern: DotMatrixMark.Pattern {
        switch connectionStatus {
        case .connected:               return .plus
        case .reconnecting, .degraded: return .ring
        case .disconnected:            return .field
        }
    }

    private var connectionIntensity: Double {
        switch connectionStatus {
        case .connected:               return 0.78
        case .reconnecting, .degraded: return 1.00
        case .disconnected:            return 0.42
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
    private var panelBody: some View {
        // Keep one stable hierarchy across reveal and status changes. Swapping
        // a direct list for a TimelineView rebuilt ScrollViewReader, which
        // could lose both the user's position and notification pre-position.
        TimelineView(
            .animation(
                minimumInterval: 1,
                paused: !isLive || !hasLiveDurations
            )
        ) { context in
            if tasks.isEmpty {
                emptyState
            } else {
                taskList(now: context.date)
            }
        }
    }

    private var hasLiveDurations: Bool {
        tasks.contains { $0.status == .running || $0.status == .waiting }
    }

    private func taskList(now: Date) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 1) {
                    ForEach(tasks, id: \.identity) { task in
                        TaskCard(
                            task: task,
                            isHighlighted: task.identity == highlightedTask,
                            now: now,
                            onTap: { onTaskTap(task) }
                        )
                        .id(task.identity)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .onChange(of: highlightedTask, initial: true) { _, identity in
                guard let identity,
                      tasks.contains(where: { $0.identity == identity }) else { return }
                if isLive {
                    withAnimation(Motion.contentReveal) {
                        proxy.scrollTo(identity, anchor: .center)
                    }
                } else {
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        proxy.scrollTo(identity, anchor: .center)
                    }
                }
            }
        }
        .frame(maxHeight: NotchMetrics.panelTaskListMaxHeight)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing needs you")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.warmWhite.opacity(0.78))

            Text("Agent sessions will appear here automatically.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textTertiary)

            Button(action: onConnectTap) {
                HStack(spacing: 6) {
                    Text("Connect an agent")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .semibold))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.warmWhite.opacity(0.66))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .pointingHandCursor()
            .padding(.top, 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    // MARK: - Geometry

    private var panelWidth: CGFloat {
        NotchMetrics.panelWidth(for: layout)
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
