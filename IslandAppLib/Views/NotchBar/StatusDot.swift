import SwiftUI

/// Status indicator dot with restrained state-driven animation.
///
/// State → behavior:
/// - **Idle** — static gray.
/// - **Running** — scale 1.0 ↔ 1.08 with a slow breath.
/// - **Waiting** — scale 1.0 ↔ 1.12 with a slightly quicker breath.
/// - **Completed** — one restrained 1.0 → 1.18 → 1.0 acknowledgement.
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

            Circle()
                .fill(state.color)
                .frame(width: size, height: size)
                .scaleEffect(currentScale(loopScale: phase.dotScale))
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

    /// Compose the live loop scale with the one-shot completed feedback so they
    /// don't fight. Running/waiting drive `loopScale`; completed multiplies in
    /// `completedScale` instead.
    private func currentScale(loopScale: CGFloat) -> CGFloat {
        switch state {
        case .running, .waiting: return loopScale
        case .completed:         return completedScale
        case .idle, .failed:     return 1.0
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
                completedScale = 1.18
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

/// Time-keyed animation phase for the bar/dot. Call `compute(state:at:)`
/// from a `TimelineView` and apply `dotScale` to the indicator.
struct StatusPhase {
    /// Current scale of the dot (loop animations only — completed feedback is
    /// handled separately by `StatusDot`).
    let dotScale: CGFloat
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
            let p = animated ? loopPhase(t, period: Motion.runningBreathPeriod) : 0.5
            return StatusPhase(dotScale: animated ? 1.0 + 0.08 * p : 1.0)

        case .waiting:
            let p = animated ? loopPhase(t, period: Motion.waitingBreathPeriod) : 0.5
            return StatusPhase(dotScale: animated ? 1.0 + 0.12 * p : 1.0)

        case .idle, .completed, .failed:
            return StatusPhase(dotScale: 1.0)
        }
    }

    /// 0…1 sine ramp over `period` seconds.
    private static func loopPhase(_ t: TimeInterval, period: TimeInterval) -> CGFloat {
        CGFloat((sin(t * 2 * .pi / period) + 1) / 2)
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
