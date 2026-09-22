import SwiftUI
import IslandCore

/// One task row in the panel.
///
/// Layout: status matrix • tool logo • session title + agent·phase·duration
/// • chevron.
/// State leads the row and appears once, in the matrix; the vendor logo is a
/// smaller identity mark after it. Rows stay transparent until hovered so the
/// panel reads as one calm surface instead of a stack of animated cards.
struct TaskCard: View {
    let task: AgentTask
    var isHighlighted: Bool = false
    /// Deterministic override for previews/tests. Production leaves this nil
    /// so each live row owns its one-second clock without invalidating the
    /// surrounding list or sibling rows.
    var now: Date? = nil
    /// Hidden panel rows stop their local status animation completely.
    var isLive: Bool = true
    let onTap: () -> Void

    @State private var isHovering = false
    @State private var branchCache = ProjectBranchCache.shared
    @Environment(\.devIslandLanguage) private var language

    @ViewBuilder
    var body: some View {
        if let now {
            card(at: now)
        } else if PanelClockPresentation.taskNeedsLiveTick(task.status) {
            TimelineView(
                .animation(minimumInterval: task.source == "codex" ? 60 : 1, paused: !isLive)
            ) { context in
                card(at: context.date)
            }
        } else {
            card(at: task.updatedAt)
        }
    }

    private func card(at referenceDate: Date) -> some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                HStack(spacing: TaskCardLeadingIdentityMetrics.spacing) {
                    TaskStatusMatrix(
                        status: task.status,
                        size: TaskCardLeadingIdentityMetrics.statusSize,
                        isLive: isLive
                    )
                    .animation(Motion.colorTransition, value: task.status)

                    toolLogo
                }
                .frame(
                    width: TaskCardLeadingIdentityMetrics.width,
                    alignment: .leading
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(Typo.islandTitle)
                        .foregroundStyle(Palette.warmWhite)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 5) {
                        Text(agentDisplayName)
                            .fixedSize()
                        separator
                        if let branch = projectBranch {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 10, weight: .medium))
                                    .accessibilityHidden(true)
                                Text(branch)
                                    .lineLimit(1)
                            }
                            .layoutPriority(1)
                            separator
                        }
                        if let phase = displayedPhase {
                            Text(phase)
                                .lineLimit(1)
                                .layoutPriority(1)
                            separator
                        }
                        Text(durationString(at: referenceDate))
                            .monospacedDigit()
                            .fixedSize()
                    }
                    .font(Typo.islandMeta)
                    .foregroundStyle(Palette.textSecondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .opacity(isHovering ? 1 : 0)
                    .animation(Motion.hoverHighlight, value: isHovering)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, TaskCardMetrics.horizontalPadding)
            .frame(maxWidth: .infinity, minHeight: TaskCardMetrics.minHeight, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: NotchMetrics.panelRowRadius, style: .continuous)
                    .fill(cardBackground)
                    .animation(Motion.hoverHighlight, value: isHovering)
            }
            .overlay {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: NotchMetrics.panelRowRadius, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 0.75)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { isHovering = $0 }
        .pointingHandCursor()
        .animation(Motion.colorTransition, value: isHighlighted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(at: referenceDate))
        .accessibilityHint(
            L10n.format(
                "Opens this session in %@",
                language: language,
                agentDisplayName
            )
        )
    }

    // MARK: - Pieces

    private var separator: some View {
        Text(verbatim: "·")
            .foregroundStyle(Palette.textTertiary)
            .accessibilityHidden(true)
    }

    private var toolLogo: some View {
        // Real brand logo (template PNG) with monogram fallback —
        // see AgentBrand.
        AgentLogoBadge(
            source: task.source,
            size: TaskCardLeadingIdentityMetrics.logoSize,
            ink: Palette.textSecondary,
            badge: nil
        )
    }

    /// The row the island opened for carries a ring as well as a tint, so
    /// it stays distinct from the row under the pointer (a tint alone was
    /// 1.06:1 against a hovered row).
    private var cardBackground: Color {
        if isHighlighted {
            return Palette.warmWhite.opacity(0.06)
        }
        return isHovering ? Palette.warmWhite.opacity(0.045) : .clear
    }

    private var agentDisplayName: String {
        if task.source == "manus" { return "Manus" }
        return LocalAgentRegistry.descriptor(for: task.source)?.displayName
            ?? task.source.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func durationString(at referenceDate: Date) -> String {
        PanelClockPresentation.taskTimingLabel(for: task, at: referenceDate, language: language)
    }

    /// Branch of the project directory a local session runs in. Remote and
    /// non-git sessions have none; the cache refreshes it off the main
    /// thread so a checkout switch shows up within half a minute.
    private var projectBranch: String? {
        branchCache.branch(forTaskURL: task.taskURL)
    }

    private func accessibilitySummary(at referenceDate: Date) -> String {
        let details = [projectBranch, displayedPhase]
            .compactMap { $0 }
            .map { L10n.format(", %@", language: language, $0) }
            .joined()
        return L10n.format(
            "%@, %@, %@%@, %@",
            language: language,
            agentDisplayName,
            task.title,
            statusLabel,
            details,
            durationString(at: referenceDate)
        )
    }

    private var statusLabel: String {
        if task.source == "codex",
           let response = CodexSessionMonitoringPresentation.responseStatus(task.status, phase: task.currentPhase, language: language) {
            return response
        }
        let key: String
        switch task.status {
        case .running:   key = "Running"
        case .waiting:   key = "Needs attention"
        case .completed: key = "Completed"
        case .failed:    key = "Failed"
        }
        return L10n.string(key, language: language)
    }

    private var displayedPhase: String? {
        if task.source == "codex",
           let response = CodexSessionMonitoringPresentation.responseStatus(task.status, phase: task.currentPhase, language: language) {
            return response
        }
        return task.currentPhase
    }
}

/// Fixed leading geometry keeps the semantic status mark and the vendor logo
/// as two distinct signals. The previous bottom-trailing overlay made dense
/// marks such as Codex read like one malformed composite icon. State is the
/// larger of the two: it is what the row is for.
enum TaskCardLeadingIdentityMetrics {
    static let statusSize: CGFloat = 12
    static let logoSize: CGFloat = 20
    static let spacing: CGFloat = 9
    static let width = statusSize + spacing + logoSize
}

/// Row geometry shared by task rows, response receipts and the panel header
/// so their leading marks sit in one column.
enum TaskCardMetrics {
    static let horizontalPadding: CGFloat = 12
    static let minHeight: CGFloat = 52
}

/// Keeps the continuous opacity loop in Core Animation instead of rebuilding
/// the row, its text layout, or the surrounding LazyVStack every frame.
private struct TaskStatusMatrix: View {
    let status: TaskStatus
    let size: CGFloat
    let isLive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AnimatedDotMatrixMark(
            color: status.color,
            size: size,
            motion: status.matrixMotion,
            pattern: status.matrixPattern,
            intensity: status.matrixIntensity,
            isAnimated: needsAnimation
        )
    }

    private var needsAnimation: Bool {
        guard isLive, !reduceMotion else { return false }
        switch status {
        case .running, .waiting: return true
        case .completed, .failed: return false
        }
    }
}

// PREVIEWS && DEBUG — references TaskStore.previewTasks which is
// inside a #if DEBUG extension, so release builds must strip this.
#if PREVIEWS && DEBUG
#Preview("Task cards — all states") {
    VStack(spacing: 6) {
        ForEach(TaskStore.previewTasks) { task in
            TaskCard(task: task, onTap: {})
        }
        TaskCard(task: AgentTask(
            id: "t4",
            source: "manus",
            title: "Generate quarterly revenue chart with breakdown by region",
            status: .failed,
            currentPhase: "Connection error",
            createdAt: Date(timeIntervalSinceNow: -240),
            updatedAt: Date(),
            taskURL: "https://manus.im/task/t4"
        ), onTap: {})
    }
    .padding(12)
    .frame(width: 380)
    .background(Palette.notchBlack)
}
#endif
