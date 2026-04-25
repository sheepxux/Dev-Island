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

    var body: some View {
        ZStack {
            backdrop
            content
        }
        .frame(width: layout.totalWidth, height: layout.barHeight)
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
            Capsule()
                .fill(Palette.capsuleBlack)
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
            HStack {
                StatusDot(state: state)
                Spacer(minLength: 8)
                Text("\(taskCount)")
                    .font(Typo.barCount)
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
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
