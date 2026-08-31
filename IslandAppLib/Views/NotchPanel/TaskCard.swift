import SwiftUI
import IslandCore

/// One task row in the panel.
///
/// Layout: status matrix • tool logo • session title + agent·phase·duration
/// • chevron.
/// State appears once, in the matrix. Rows stay transparent until hovered so the
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
    @Environment(\.devIslandLanguage) private var language

    @ViewBuilder
    var body: some View {
        if let now {
            card(at: now)
        } else if PanelClockPresentation.taskNeedsLiveTick(task.status) {
            TimelineView(
                .animation(minimumInterval: 1.0, paused: !isLive)
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
                    .compositingGroup()
                    .shadow(color: Palette.islandTop, radius: 1.5)
                    .animation(Motion.colorTransition, value: task.status)

                    toolLogo
                }
                .frame(
                    width: TaskCardLeadingIdentityMetrics.width,
                    alignment: .leading
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(Typo.cardTitle)
                        .foregroundStyle(Palette.warmWhite.opacity(0.88))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 6) {
                        Text(agentDisplayName)
                            .font(Typo.cardMeta)
                            .fixedSize()
                        Text("·")
                            .font(.system(size: 11))
                            .opacity(0.5)
                        if let phase = task.currentPhase {
                            Text(phase)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .layoutPriority(1)
                            Text("·")
                                .font(.system(size: 11))
                                .opacity(0.5)
                        }
                        Text(durationString(at: referenceDate))
                            .font(Typo.cardMeta)
                            .monospacedDigit()
                            .fixedSize()
                    }
                    .foregroundStyle(Palette.textSecondary.opacity(0.72))
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary.opacity(isHovering ? 0.72 : 0))
                    .animation(Motion.hoverHighlight, value: isHovering)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(cardBackground)
                    .animation(Motion.hoverHighlight, value: isHovering)
            }
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Palette.warmWhite.opacity(isHighlighted ? 0.34 : 0))
                    .frame(width: 1, height: 20)
                    .padding(.leading, 1)
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

    private var toolLogo: some View {
        // Real brand logo (template PNG) with monogram fallback —
        // see AgentBrand.
        AgentLogoBadge(
            source: task.source,
            size: TaskCardLeadingIdentityMetrics.logoSize,
            ink: Palette.warmWhite.opacity(0.82),
            badge: nil
        )
    }

    private var cardBackground: Color {
        if isHighlighted {
            return Color.white.opacity(0.055)
        }
        return isHovering ? Color.white.opacity(0.04) : .clear
    }

    private var agentDisplayName: String {
        if task.source == "manus" { return "Manus" }
        return LocalAgentRegistry.descriptor(for: task.source)?.displayName
            ?? task.source.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func durationString(at referenceDate: Date) -> String {
        PanelClockPresentation.taskDuration(for: task, at: referenceDate)
    }

    private func accessibilitySummary(at referenceDate: Date) -> String {
        let phase = task.currentPhase.map {
            L10n.format(", %@", language: language, $0)
        } ?? ""
        return L10n.format(
            "%@, %@, %@%@, %@",
            language: language,
            agentDisplayName,
            task.title,
            statusLabel,
            phase,
            durationString(at: referenceDate)
        )
    }

    private var statusLabel: String {
        let key: String
        switch task.status {
        case .running:   key = "Running"
        case .waiting:   key = "Needs attention"
        case .completed: key = "Completed"
        case .failed:    key = "Failed"
        }
        return L10n.string(key, language: language)
    }
}

/// Fixed leading geometry keeps the semantic status mark and the vendor logo
/// as two distinct signals. The previous bottom-trailing overlay made dense
/// marks such as Codex read like one malformed composite icon.
enum TaskCardLeadingIdentityMetrics {
    static let statusSize: CGFloat = 9
    static let logoSize: CGFloat = 26
    static let spacing: CGFloat = 7
    static let width = statusSize + spacing + logoSize
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
