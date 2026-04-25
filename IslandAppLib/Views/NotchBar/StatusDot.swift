import SwiftUI

/// Status indicator dot. Static colors only in Task 1; breathing / pulse /
/// ripple animations are layered in Task 3.
struct StatusDot: View {
    let state: BarState
    var size: CGFloat = NotchMetrics.dotSize

    var body: some View {
        Circle()
            .fill(state.color)
            .frame(width: size, height: size)
            .animation(Motion.colorTransition, value: state)
    }
}

extension BarState: Hashable {}

#if PREVIEWS
#Preview("Five states") {
    HStack(spacing: 16) {
        ForEach([BarState.idle, .running, .waiting, .completed, .failed], id: \.self) { state in
            VStack(spacing: 6) {
                StatusDot(state: state)
                Text(String(describing: state))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding()
    .background(Palette.notchBlack)
}
#endif
