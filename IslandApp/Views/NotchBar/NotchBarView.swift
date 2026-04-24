import SwiftUI
import IslandCore

/// Collapsed bar view: black extensions hugging both sides of the hardware
/// notch, with a status dot on the left and the running task count on the right.
struct NotchBarView: View {
    let state: BarState
    let taskCount: Int

    var body: some View {
        ZStack {
            NotchBarShape()
                .fill(Palette.notchBlack)

            HStack(spacing: 0) {
                // Left extension content
                HStack {
                    StatusDot(state: state)
                    Spacer(minLength: 0)
                }
                .frame(width: NotchMetrics.sideExtension)
                .padding(.leading, NotchMetrics.sideInset)

                // Hardware notch corridor — left empty
                Spacer()
                    .frame(width: NotchMetrics.notchWidth)

                // Right extension content
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
        }
        .frame(width: NotchMetrics.totalWidth, height: NotchMetrics.barHeight)
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

#Preview("Bar — five states") {
    VStack(spacing: 20) {
        ForEach(barPreviewCases, id: \.label) { sample in
            VStack(spacing: 6) {
                NotchBarView(state: sample.state, taskCount: sample.count)
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
        taskCount: store.tasks.filter { $0.status == .running || $0.status == .waiting }.count
    )
    .padding(40)
    .background(Color.gray.opacity(0.25))
}
#endif
