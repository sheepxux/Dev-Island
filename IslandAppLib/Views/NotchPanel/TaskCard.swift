import SwiftUI
import IslandCore

/// One task row in the panel.
///
/// Layout: 3pt state-color stripe • tool logo • title + phase·duration •
/// chevron. Running tasks get a 2pt animated progress bar at the bottom.
struct TaskCard: View {
    let task: AgentTask
    var isHighlighted: Bool = false
    /// Shared clock owned by the containing panel — one tick for the whole
    /// list, and only while the list is on screen.
    var now: Date = Date()
    /// Whether the card is actually visible. Gates the running shimmer,
    /// which would otherwise loop forever behind a collapsed panel.
    var isLive: Bool = true
    let onTap: () -> Void

    @State private var isHovering = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // 3pt state-color stripe (left edge)
                Rectangle()
                    .fill(task.status.color)
                    .frame(width: 3)

                HStack(spacing: 10) {
                    toolLogo
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .font(Typo.cardTitle)
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        HStack(spacing: 6) {
                            if let phase = task.currentPhase {
                                Text(phase)
                                    .lineLimit(1)
                                Text("·")
                                    .opacity(0.5)
                            }
                            Text(durationString)
                        }
                        .font(Typo.cardMeta)
                        .foregroundStyle(.white.opacity(0.5))
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.leading, 10)
                .padding(.trailing, 12)
                .padding(.vertical, 9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(cardBackground)
                    // Ease the highlight in/out — the hard cut read as
                    // flicker when skimming the cursor down the list.
                    .animation(Motion.hoverHighlight, value: isHovering)
            }
            .overlay {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(task.status.color.opacity(0.9), lineWidth: 1.5)
                        .shadow(color: task.status.color.opacity(0.55), radius: 7)
                }
            }
            .overlay(alignment: .bottom) {
                if task.status == .running {
                    AnimatedProgressBar(animated: isLive && !reduceMotion)
                        .frame(height: 2)
                        .padding(.horizontal, 1)
                        .padding(.bottom, 1)
                }
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
        AgentLogoBadge(source: task.source)
    }

    private var cardBackground: Color {
        if isHighlighted {
            return task.status.color.opacity(0.18)
        }
        return isHovering ? Palette.cardHover : Palette.cardBg
    }

    private var durationString: String {
        let elapsed = max(0, Int(now.timeIntervalSince(task.createdAt)))
        let m = elapsed / 60
        let s = elapsed % 60
        if m >= 60 {
            let h = m / 60
            return String(format: "%d:%02d:%02d", h, m % 60, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

/// Indeterminate 2pt progress bar — a thin gradient shimmer that loops.
///
/// `animated == false` renders the same bar as a static band. The loop is a
/// `repeatForever` animation, which SwiftUI keeps driving regardless of
/// whether anything can see it, so the caller has to switch it off when the
/// panel is collapsed or the user asked for reduced motion.
private struct AnimatedProgressBar: View {
    var animated: Bool = true

    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, Palette.stateRunning.opacity(0.85), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.4)
            .offset(x: (animated ? phase : 0) * geo.size.width * 1.4)
            .animation(
                animated
                    ? .linear(duration: Motion.progressShimmerPeriod).repeatForever(autoreverses: false)
                    : nil,
                value: animated ? phase : 0
            )
            .clipShape(Capsule())
            .frame(width: geo.size.width, alignment: .leading)
            .clipped()
        }
        .background(Color.white.opacity(0.05))
        .clipShape(Capsule())
        // Restart on every off→on flip, not just on first appearance: a
        // card that was built while the panel was collapsed would
        // otherwise stay frozen at its start offset once shown.
        .onChange(of: animated, initial: true) { _, isAnimated in
            guard isAnimated else {
                phase = -1
                return
            }
            // Commit the reset before retargeting, or SwiftUI collapses
            // both into one update and skips the animation.
            DispatchQueue.main.async { phase = 1 }
        }
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
