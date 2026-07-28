import SwiftUI
import IslandCore

/// Collapsed bar.
///
/// Two visual modes driven by `NotchMetrics.Layout`:
/// - **Notched display**: a solid black silhouette flush with the screen
///   top, sized to the menubar height. Content lives in side wings
///   flanking the hardware notch — status dot left, task count right —
///   so nothing renders behind the camera.
/// - **No-notch display** (Mac mini, external displays): a single capsule
///   sitting `topMargin` below the screen edge.
struct NotchBarView: View {
    let state: BarState
    let taskCount: Int
    var title: String = "No tasks"
    let layout: NotchMetrics.Layout
    /// Whether to show the status dot + count inside the bar. Normal
    /// collapsed state keeps this on for both hardware-notch and
    /// synthetic-notch displays; previews can still toggle it directly.
    var showsContent: Bool = true
    /// When `false` the view renders content only — no background shape and
    /// no outer glow. Use this when the parent (`IslandRootView`) is drawing
    /// a single morphing shape that spans both bar and panel modes; the
    /// content is laid on top of that shared shape.
    var drawsBackdrop: Bool = true

    var body: some View {
        if drawsBackdrop {
            // Glow is keyed off the same `StatusPhase` time source as
            // `StatusDot` so the bar's outer halo pulses in lockstep with
            // the indicator dot. For idle/failed/completed the phase is
            // static so we let the timeline pause; running/waiting need the
            // per-frame tick.
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !needsTimeline)) { context in
                let phase = StatusPhase.compute(state: state, at: context.date)
                ZStack {
                    backdrop
                        .shadow(
                            color: state.color.opacity(phase.glowOpacity * 0.55),
                            radius: phase.glowRadius * 1.3
                        )
                        .animation(Motion.colorTransition, value: state)
                    content
                        .opacity(showsContent ? 1 : 0)
                }
                .frame(width: layout.totalWidth, height: layout.barHeight)
            }
        } else {
            // Content-only mode: no shape, no glow. Caller composes its own
            // shared backdrop.
            content
                .opacity(showsContent ? 1 : 0)
                .frame(width: layout.totalWidth, height: layout.barHeight)
        }
    }

    /// Whether the timeline should drive frames. Only running/waiting have
    /// time-varying glow; the rest are static and the timeline can pause.
    private var needsTimeline: Bool {
        state == .running || state == .waiting
    }

    // MARK: - Backdrop (shape + color)

    @ViewBuilder
    private var backdrop: some View {
        if layout.hasNotch {
            NotchBarShape(
                notchWidth: layout.notchWidth,
                notchHeight: layout.notchHeight
            )
            .fill(Palette.notchBlack)
        } else {
            // Synthetic notch: flat top flush with the screen edge,
            // continuous-curvature rounded bottom corners. Same colour as
            // the hardware notch so the visual language is unified across
            // notched and non-notched Macs.
            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: 0,
                    bottomLeading: NotchMetrics.syntheticCornerRadius,
                    bottomTrailing: NotchMetrics.syntheticCornerRadius,
                    topTrailing: 0
                ),
                style: .continuous
            )
            .fill(Palette.notchBlack)
        }
    }

    // MARK: - Content (status dot + task count)

    @ViewBuilder
    private var content: some View {
        if layout.hasNotch {
            // Dynamic-Island-style side wings: status dot in the left wing,
            // task count in the right, both hugging the notch so the eye
            // reads "[●] [📷] [N]" as one cluster. The notch's own width is
            // left as a transparent gap so nothing renders behind the
            // camera.
            let wingWidth = max(0, (layout.totalWidth - layout.notchWidth) / 2)
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    StatusDot(state: state)
                }
                .padding(.horizontal, NotchMetrics.sideInset)
                .frame(width: wingWidth, height: layout.menuBarHeight)

                Color.clear
                    .frame(width: layout.notchWidth, height: layout.menuBarHeight)

                HStack(spacing: 6) {
                    Text("\(taskCount)")
                        .font(Typo.barCount)
                        .foregroundStyle(.white.opacity(0.85))
                        .monospacedDigit()
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, NotchMetrics.sideInset)
                .frame(width: wingWidth, height: layout.menuBarHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            // Synthetic notch: mirror a Dynamic Island compact layout.
            // Left = state, center = current task label, right = count.
            HStack(spacing: 12) {
                StatusDot(state: state)
                    .frame(width: 16, height: 16)

                Text(title)
                    .font(Typo.barTitle)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(taskCount)")
                    .font(Typo.barBadge)
                    .foregroundStyle(.white.opacity(0.82))
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.13))
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: min(28, layout.barHeight), alignment: .center)
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(.leading, 18)
            .padding(.trailing, 16)
        }
    }
}

// MARK: - Previews

#if PREVIEWS
private struct BarPreviewSample {
    let label: String
    let state: BarState
    let count: Int
}

private let barPreviewCases: [BarPreviewSample] = [
    .init(label: "Idle",      state: .idle,      count: 0),
    .init(label: "Running",   state: .running,   count: 1),
    .init(label: "Waiting",   state: .waiting,   count: 2),
    .init(label: "Completed", state: .completed, count: 3),
    .init(label: "Failed",    state: .failed,    count: 1),
]

private let notchedLayout = NotchMetrics.Layout(
    hasNotch: true,
    barHeight: 32,
    notchHeight: 32,
    menuBarHeight: 32,
    notchWidth: NotchMetrics.defaultNotchWidth,
    topMargin: 0
)

private let plainLayout = NotchMetrics.Layout(
    hasNotch: false,
    barHeight: 24,                    // idle within a 28pt menu bar
    notchHeight: 0,
    menuBarHeight: 28,
    notchWidth: NotchMetrics.defaultNotchWidth,
    topMargin: 0
)

#Preview("Bar — notched, five states") {
    VStack(spacing: 18) {
        ForEach(barPreviewCases, id: \.label) { sample in
            VStack(spacing: 6) {
                NotchBarView(state: sample.state, taskCount: sample.count, layout: notchedLayout)
                Text(sample.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding(32)
    .background(Color.gray.opacity(0.25))
}

#Preview("Bar — capsule (no notch)") {
    VStack(spacing: 14) {
        ForEach(barPreviewCases, id: \.label) { sample in
            VStack(spacing: 6) {
                NotchBarView(state: sample.state, taskCount: sample.count, layout: plainLayout)
                Text(sample.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding(32)
    .background(Color.gray.opacity(0.25))
}
#endif
