import SwiftUI
import IslandCore

/// One task row in the panel.
///
/// Layout: 3pt state-color stripe • tool logo • title + phase·duration •
/// chevron. Running tasks get a 2pt animated progress bar at the bottom.
struct TaskCard: View {
    let task: AgentTask
    let onTap: () -> Void

    @State private var isHovering = false
    /// Re-tick every second so the duration display stays live without
    /// relying on the parent re-rendering.
    @State private var tick = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
                    .fill(isHovering ? Palette.cardHover : Palette.cardBg)
            }
            .overlay(alignment: .bottom) {
                if task.status == .running {
                    AnimatedProgressBar()
                        .frame(height: 2)
                        .padding(.horizontal, 1)
                        .padding(.bottom, 1)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .onReceive(timer) { tick = $0 }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var toolLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: 26, height: 26)
            Text(logoLetter)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private var logoLetter: String {
        switch task.source {
        case "manus":       return "M"
        case "claude-code": return "C"
        case "cursor":      return "Cu"
        default:            return String(task.source.prefix(1)).uppercased()
        }
    }

    private var durationString: String {
        // tick is referenced so SwiftUI re-evaluates each second
        _ = tick
        let elapsed = max(0, Int(Date().timeIntervalSince(task.createdAt)))
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
private struct AnimatedProgressBar: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, Palette.stateRunning.opacity(0.85), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.4)
            .offset(x: phase * geo.size.width * 1.4)
            .animation(
                .linear(duration: 1.4).repeatForever(autoreverses: false),
                value: phase
            )
            .clipShape(Capsule())
            .frame(width: geo.size.width, alignment: .leading)
            .clipped()
        }
        .background(Color.white.opacity(0.05))
        .clipShape(Capsule())
        .onAppear {
            DispatchQueue.main.async { phase = 1 }
        }
    }
}

#if PREVIEWS
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
