import SwiftUI
import IslandCore

/// One task row in the panel.
///
/// Layout: status matrix • tool logo • title + phase·duration • chevron.
/// State appears once, in the matrix. Rows stay transparent until hovered so the
/// panel reads as one calm surface instead of a stack of animated cards.
struct TaskCard: View {
    let task: AgentTask
    var isHighlighted: Bool = false
    /// Shared clock owned by the containing panel — one tick for the whole
    /// list, and only while the list is on screen.
    var now: Date = Date()
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                ZStack(alignment: .bottomTrailing) {
                    toolLogo
                    DotMatrixMark(
                        color: task.status.color,
                        size: 9,
                        pattern: task.status.matrixPattern,
                        intensity: task.status.matrixIntensity
                    )
                        .compositingGroup()
                        .shadow(color: Palette.islandTop, radius: 1.5)
                        .offset(x: 1, y: 1)
                        .animation(Motion.colorTransition, value: task.status)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(Typo.cardTitle)
                        .foregroundStyle(Palette.warmWhite.opacity(0.88))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 6) {
                        if let phase = task.currentPhase {
                            Text(phase)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .layoutPriority(1)
                            Text("·")
                                .font(.system(size: 11))
                                .opacity(0.5)
                        }
                        Text(durationString)
                            .font(Typo.cardMeta)
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
    }

    // MARK: - Pieces

    private var toolLogo: some View {
        // Real brand logo (template PNG) with monogram fallback —
        // see AgentBrand.
        AgentLogoBadge(
            source: task.source,
            size: 26,
            ink: Palette.warmWhite.opacity(0.82),
            badge: Color.white.opacity(0.045)
        )
    }

    private var cardBackground: Color {
        if isHighlighted {
            return Color.white.opacity(0.055)
        }
        return isHovering ? Color.white.opacity(0.04) : .clear
    }

    private var durationString: String {
        let referenceDate: Date
        switch task.status {
        case .running, .waiting:
            referenceDate = now
        case .completed, .failed:
            referenceDate = task.updatedAt
        }
        let elapsed = max(0, Int(referenceDate.timeIntervalSince(task.createdAt)))
        let m = elapsed / 60
        let s = elapsed % 60
        if m >= 60 {
            let h = m / 60
            return String(format: "%d:%02d:%02d", h, m % 60, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// PREVIEWS && DEBUG — references TaskStore.previewTasks which is
// inside a #if DEBUG extension, so release builds must strip this.
#if PREVIEWS && DEBUG
#Preview("Task cards — all states") {
    VStack(spacing: 6) {
        ForEach(TaskStore.previewTasks) { task in
            TaskCard(task: task, onTap: { print("tap \(task.id)") })
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
