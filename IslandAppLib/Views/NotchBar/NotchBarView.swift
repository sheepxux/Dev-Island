import SwiftUI
import IslandCore

/// Collapsed bar.
///
/// Two visual modes driven by `NotchMetrics.Layout`:
/// - **Notched display**: two black extensions flanking the hardware notch,
///   each with a rounded outer-bottom corner.
/// - **No-notch display** (e.g. Mac mini, external display): a single
///   capsule sitting `topMargin` below the screen edge.
///
/// Both modes use the same status dot + task count layout.
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
            NotchBarShape(notchWidth: layout.notchWidth)
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
            HStack(spacing: 0) {
                // Left extension
                HStack {
                    StatusDot(state: state)
                    Spacer(minLength: 0)
                }
                .frame(width: NotchMetrics.sideExtension)
                .padding(.leading, NotchMetrics.sideInset)

                // Hardware notch corridor — transparent
                Spacer().frame(width: layout.notchWidth)

                // Right extension
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
            // No-notch capsule: dot left, count right, both inside the pill
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
    barHeight: 32,
    notchWidth: NotchMetrics.defaultNotchWidth,
    topMargin: 0
)

private let plainLayout = NotchMetrics.Layout(
    hasNotch: false,
    barHeight: 24,
    notchWidth: NotchMetrics.defaultNotchWidth,
    topMargin: NotchMetrics.fallbackTopMargin
)

#Preview("Bar — notched, five states") {
    VStack(spacing: 20) {
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

#Preview("Bar — capsule (no notch), five states") {
    VStack(spacing: 16) {
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

#Preview("Bar — derived from store") {
    let store = TaskStore.mock()
    return NotchBarView(
        state: BarState.derive(from: store.tasks),
        taskCount: store.tasks.filter { $0.status == .running || $0.status == .waiting }.count,
        layout: notchedLayout
    )
    .padding(40)
    .background(Color.gray.opacity(0.25))
}
#endif
