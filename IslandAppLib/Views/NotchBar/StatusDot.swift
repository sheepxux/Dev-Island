import SwiftUI

/// Status indicator dot with state-driven animation (CLAUDE_CLIENT.md §6 task 3).
///
/// State → behavior:
/// - **Idle** — static gray, no glow.
/// - **Running** — scale 1.0 ↔ 1.2, 2s easeInOut breath. Soft glow.
/// - **Waiting** — scale 1.0 ↔ 1.4, 1s easeInOut pulse + three concentric
///   ripple rings expanding outward (1.5s easeOut, staggered 0.5s).
/// - **Completed** — one-shot scale jump 1.0 → 1.5 → 1.0 (~450ms total).
///   Holds steady afterward with a soft glow.
/// - **Failed** — static, soft constant glow.
///
/// Implementation note: Running / Waiting / Ripples use `TimelineView` with
/// time-derived phase. This sidesteps SwiftUI's awkward behavior when a
/// `repeatForever` animation needs to retarget on state change — the time
/// source is the same, only the formula changes.
///
/// `StatusPhase` is shared with `NotchBarView` so the bar's outer glow
/// pulses in lockstep with the dot.
struct StatusDot: View {
    let state: BarState
    var size: CGFloat = NotchMetrics.dotSize

    /// Drives the one-shot completed flash. Outside of completed it stays 1.
    @State private var completedScale: CGFloat = 1.0
    @State private var lastFlashedAt: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !needsAnimation)) { context in
            let phase = StatusPhase.compute(state: state, at: context.date)

            ZStack {
                // ── Ripple layer ────────────────────────────────────────
                if state == .waiting {
                    RippleLayer(color: state.color, baseSize: size, time: context.date)
                        .transition(.opacity.animation(.easeInOut(duration: 0.18)))
                }

                // ── Main dot ───────────────────────────────────────────
                Circle()
                    .fill(state.color)
                    .frame(width: size, height: size)
                    .scaleEffect(currentScale(loopScale: phase.dotScale))
                    .shadow(
                        color: state.color.opacity(phase.glowOpacity),
                        radius: phase.glowRadius
                    )
                    .animation(Motion.colorTransition, value: state)
            }
        }
        .onChange(of: state, initial: false) { oldValue, newValue in
            handleStateChange(from: oldValue, to: newValue)
        }
    }

    // MARK: - Derived

    /// Whether the timeline needs to drive frame updates. Idle/failed/completed
    /// (after the flash settles) are static so we let the timeline pause.
    private var needsAnimation: Bool {
        switch state {
        case .running, .waiting: return true
        case .completed:         return lastFlashedAt != nil  // briefly true during flash
        case .idle, .failed:     return false
        }
    }

    /// Compose the live loop scale with the one-shot completed flash so they
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
        if new == .completed && old != .completed {
            // One-shot flash: scale up fast, settle slower.
            withAnimation(.easeOut(duration: 0.18)) {
                completedScale = 1.5
            }
            let flashStart = Date()
            lastFlashedAt = flashStart
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.easeIn(duration: 0.27)) {
                    completedScale = 1.0
                }
                // Allow the timeline to pause after the flash completes.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                    if lastFlashedAt == flashStart { lastFlashedAt = nil }
                }
            }
        } else if new != .completed {
            completedScale = 1.0
            lastFlashedAt = nil
        }
    }
}

// MARK: - Ripple layer (waiting state)

/// Three concentric stroke rings that expand outward and fade. Phase offset
/// 0.5s per ring across a 1.5s cycle so a new ring starts every 0.5s — gives
/// a continuous "broadcast" feel.
private struct RippleLayer: View {
    let color: Color
    let baseSize: CGFloat
    let time: Date

    private let cycleSeconds: Double = 1.5
    private let ringCount: Int = 3

    var body: some View {
        ZStack {
            ForEach(0..<ringCount, id: \.self) { i in
                let phase = ringPhase(for: i)
                Circle()
                    .stroke(color.opacity(0.7 * (1 - phase)), lineWidth: 1.5)
                    .frame(width: baseSize, height: baseSize)
                    .scaleEffect(1.0 + 2.6 * phase)
            }
        }
        .allowsHitTesting(false)
    }

    /// 0..1 over the cycle for ring `i`, offset by `i / ringCount` of the cycle.
    private func ringPhase(for i: Int) -> CGFloat {
        let offset = Double(i) / Double(ringCount)
        let t = time.timeIntervalSinceReferenceDate / cycleSeconds + offset
        let frac = t - floor(t)
        return CGFloat(frac)
    }
}

// MARK: - Phase computation (shared with NotchBarView for synced outer glow)

/// Time-keyed animation phase for the bar/dot. Call `compute(state:at:)`
/// every frame from a `TimelineView` and apply the returned values to
/// `scaleEffect` and `.shadow`.
struct StatusPhase {
    /// Current scale of the dot (loop animations only — completed flash is
    /// handled separately by `StatusDot`).
    let dotScale: CGFloat
    /// Glow radius around the dot/bar.
    let glowRadius: CGFloat
    /// Glow opacity (0–1).
    let glowOpacity: Double

    static func compute(state: BarState, at time: Date) -> StatusPhase {
        let t = time.timeIntervalSinceReferenceDate

        switch state {
        case .running:
            // 2s breath, scale 1.0 ↔ 1.2, glow 4 ↔ 7.
            let p = (sin(t * .pi) + 1) / 2  // 2π/2s = π → 2s period
            return StatusPhase(
                dotScale: 1.0 + 0.2 * p,
                glowRadius: 4 + 3 * p,
                glowOpacity: 0.35 + 0.20 * p
            )

        case .waiting:
            // 1s pulse, scale 1.0 ↔ 1.4, glow 5 ↔ 11.
            let p = (sin(t * 2 * .pi) + 1) / 2  // 2π/1s = 2π → 1s period
            return StatusPhase(
                dotScale: 1.0 + 0.4 * p,
                glowRadius: 5 + 6 * p,
                glowOpacity: 0.45 + 0.25 * p
            )

        case .completed:
            return StatusPhase(dotScale: 1.0, glowRadius: 4, glowOpacity: 0.45)

        case .failed:
            return StatusPhase(dotScale: 1.0, glowRadius: 3, glowOpacity: 0.30)

        case .idle:
            return StatusPhase(dotScale: 1.0, glowRadius: 0, glowOpacity: 0)
        }
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

/// Smoke test the state-transition flash: this preview cycles through states
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
