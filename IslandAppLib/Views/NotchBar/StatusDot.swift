import SwiftUI

/// Status indicator rendered as Dev Island's circular 3×3 point field.
///
/// State → behavior:
/// - **Idle** — static gray.
/// - **Running** — a bright point orbits clockwise around the matrix.
/// - **Waiting** — a slightly quicker centre-out signal.
/// - **Completed** — one restrained 1.0 → 1.12 → 1.0 acknowledgement.
/// - **Failed** — static red.
///
/// Running and waiting use a time-derived phase rather than a repeating
/// animation, so changing state never has to retarget an in-flight loop.
/// Color alone keeps every state legible when Reduce Motion is enabled.
struct StatusDot: View {
    let state: BarState
    var size: CGFloat = NotchMetrics.dotSize

    /// Drives the one-shot completed feedback. Outside of completed it stays 1.
    @State private var completedScale: CGFloat = 1.0
    @State private var completedFeedbackID = UUID()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !needsAnimation)) { context in
            let phase = StatusPhase.compute(state: state, at: context.date, animated: !reduceMotion)

            DotMatrixMark(
                color: state.color,
                size: size,
                phase: phase.matrixPhase,
                motion: state.matrixMotion,
                pattern: state.matrixPattern,
                intensity: state.matrixIntensity
            )
                .scaleEffect(state == .completed ? completedScale : 1)
                .animation(Motion.colorTransition, value: state)
        }
        .onChange(of: state, initial: false) { oldValue, newValue in
            handleStateChange(from: oldValue, to: newValue)
        }
    }

    // MARK: - Derived

    /// Whether the timeline needs to drive frame updates. Idle and terminal
    /// states are static, so their timelines stay parked.
    /// Under Reduce Motion nothing loops, so the timeline stays parked and
    /// the dot costs zero frames.
    private var needsAnimation: Bool {
        guard !reduceMotion else { return false }
        switch state {
        case .running, .waiting: return true
        case .idle, .completed, .failed: return false
        }
    }

    // MARK: - Effects

    private func handleStateChange(from old: BarState, to new: BarState) {
        let feedbackID = UUID()
        completedFeedbackID = feedbackID

        if new == .completed && old != .completed {
            // A scale jump is spatial travel, so Reduce Motion gets the
            // state color on its own.
            guard !reduceMotion else {
                completedScale = 1.0
                return
            }

            completedScale = 1.0
            withAnimation(.easeOut(duration: Motion.completedFeedbackRise)) {
                completedScale = 1.12
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Motion.completedFeedbackRise) {
                guard completedFeedbackID == feedbackID else { return }
                withAnimation(.easeIn(duration: Motion.completedFeedbackSettle)) {
                    completedScale = 1.0
                }
            }
        } else if new != .completed {
            completedScale = 1.0
        }
    }
}

// MARK: - Phase computation

/// Time-keyed animation phase for the status matrix. Call `compute(state:at:)`
/// from a `TimelineView` and pass `matrixPhase` into `DotMatrixMark`.
struct StatusPhase {
    /// Normalized 0…1 cycle for internal point movement. Completed feedback
    /// is handled separately by `StatusDot`.
    let matrixPhase: CGFloat
    /// Kept at zero while the standalone `NotchBarView` still reads the shared
    /// phase. This guarantees that path cannot reintroduce a colored halo.
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
    private static func cyclePhase(_ t: TimeInterval, period: TimeInterval) -> CGFloat {
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
