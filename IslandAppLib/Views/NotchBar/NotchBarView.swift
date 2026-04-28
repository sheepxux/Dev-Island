import SwiftUI
import IslandCore

/// Collapsed bar.
///
/// Two visual modes driven by `NotchMetrics.Layout`:
/// - **Notched display**: one connected black shape that protrudes
///   `bottomOverhang` below the hardware notch, with a notch-shaped cutout
///   at top center.
/// - **No-notch display** (Mac mini, external displays): a single capsule
///   sitting `topMargin` below the screen edge.
struct NotchBarView: View {
    let state: BarState
    let taskCount: Int
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
                    bottomLeading: NotchMetrics.cornerRadius,
                    bottomTrailing: NotchMetrics.cornerRadius,
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
            // Content sits in the side extensions, vertically centered against
            // the FULL bar height — the dot and number visually align across
            // the cutout because both extensions share the same center line.
            HStack(spacing: 0) {
                HStack {
                    StatusDot(state: state)
                    Spacer(minLength: 0)
                }
                .frame(width: NotchMetrics.sideExtension)
                .padding(.leading, NotchMetrics.sideInset)

                // Hardware notch corridor — transparent (filled by hardware notch)
                Spacer().frame(width: layout.notchWidth)

                HStack {
                    Spacer(minLength: 0)
                    Text("\(taskCount)")
                        .font(Typo.barCount)
                        .foregroundStyle(.white.opacity(0.85))
                        .monospacedDigit()
                }
                .frame(width: NotchMetrics.sideExtension)
                .padding(.trailing, NotchMetrics.sideInset)
            }
        } else {
            // Synthetic notch: top portion of the bar lives inside the
            // menu-bar zone (where the OS sits on top of arbitrary
            // window content on macOS 26), so leave that empty. A
            // FLEXIBLE Spacer pushes the dot + count down to the visible
            // shelf at the bottom — fixed-height Spacers in a VStack
            // don't always claim their share, so we let SwiftUI
            // distribute the leftover instead.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack {
                    StatusDot(state: state)
                    Spacer(minLength: 8)
                    Text("\(taskCount)")
                        .font(Typo.barCount)
                        .foregroundStyle(.white.opacity(0.85))
                        .monospacedDigit()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
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
    barHeight: 32 + NotchMetrics.bottomOverhang,
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
