import SwiftUI

/// Status indicator rendered as Dev Island's circular 3×3 point field.
///
/// State → behavior:
/// - **Idle** — static gray.
/// - **Running** — a bright point orbits clockwise around the matrix.
/// - **Waiting** — a slightly quicker centre-out signal.
/// - **Completed** — bright cardinal points inside the fixed nine-dot grid.
/// - **Failed** — static red.
///
/// Running and waiting use compositor-owned opacity keyframes. This preserves
/// the fluid loop without forcing SwiftUI to rebuild the island every frame.
/// Color alone keeps every state legible when Reduce Motion is enabled.
struct StatusDot: View {
    let state: BarState
    var size: CGFloat = NotchMetrics.dotSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AnimatedDotMatrixMark(
            color: state.color,
            size: size,
            motion: state.matrixMotion,
            pattern: state.matrixPattern,
            intensity: state.matrixIntensity,
            isAnimated: needsAnimation
        )
    }

    // MARK: - Derived

    /// Under Reduce Motion nothing loops, so the mark is rendered at rest.
    private var needsAnimation: Bool {
        guard !reduceMotion else { return false }
        switch state {
        case .running, .waiting: return true
        case .idle, .completed, .failed: return false
        }
    }
}

// MARK: - Phase computation

/// Pure time-keyed phase model shared by compositor synchronization, previews,
/// and tests. It makes loop timing deterministic without owning a view clock.
struct StatusPhase {
    /// Normalized 0…1 cycle for internal point brightness movement.
    let matrixPhase: CGFloat
    /// Kept at zero as a regression contract: state motion belongs to the nine
    /// points and must never reintroduce a large colored halo around the bar.
    let glowRadius: CGFloat = 0
    let glowOpacity: Double = 0

    /// - Parameter animated: `false` for Reduce Motion. The state keeps its
    ///   semantic color but rests at its natural size.
    static func compute(state: BarState, at time: Date, animated: Bool = true) -> StatusPhase {
        let t = time.timeIntervalSinceReferenceDate

        switch state {
        case .running:
            let p = animated ? cyclePhase(t, period: Motion.runningOrbitPeriod) : 0.5
            return StatusPhase(matrixPhase: p)

        case .waiting:
            let p = animated ? cyclePhase(t, period: Motion.waitingBreathPeriod) : 0.5
            return StatusPhase(matrixPhase: p)

        case .idle, .completed, .failed:
            return StatusPhase(matrixPhase: 0.5)
        }
    }

    /// Linear 0…1 cycle over `period` seconds. Each point applies its own
    /// easing and phase offset, producing continuous motion without moving
    /// the mark's outer footprint.
    static func cyclePhase(_ t: TimeInterval, period: TimeInterval) -> CGFloat {
        CGFloat(t.truncatingRemainder(dividingBy: period) / period)
    }
}

extension BarState: Hashable {}

#if PREVIEWS
#Preview("Five states — animated") {
    HStack(spacing: 24) {
        ForEach([BarState.idle, .running, .waiting, .completed, .failed], id: \.self) { state in
            VStack(spacing: 10) {
                StatusDot(state: state)
                    .frame(width: 40, height: 40)
                Text(String(describing: state))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding(32)
    .background(Palette.notchBlack)
}

/// Smoke test the state-transition feedback: this preview cycles through states
/// every 2 seconds so you can watch transitions live.
#Preview("State cycler — transitions") {
    StateCyclerHarness()
        .padding(40)
        .background(Palette.notchBlack)
}

private struct StateCyclerHarness: View {
    @State private var index = 0
    private let states: [BarState] = [.idle, .running, .waiting, .completed, .failed]
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            StatusDot(state: states[index])
                .frame(width: 60, height: 60)
            Text(String(describing: states[index]))
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.7))
        }
        .onReceive(timer) { _ in
            index = (index + 1) % states.count
        }
    }
}
#endif
