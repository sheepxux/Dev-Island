import XCTest
@testable import IslandAppLib

/// `StatusPhase` is the shared time→appearance function behind the status
/// dot and the bar's glow. Both read it every frame, so the two have to
/// agree, and under Reduce Motion both have to come to rest rather than
/// freeze on whatever frame their timeline happened to stop on.
final class StatusPhaseTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    func testLoopStatesBreatheOverTime() {
        // A quarter of the running period apart lands on different points
        // of the sine ramp, so the dot must be a different size.
        let quarterCycle = t0.addingTimeInterval(Motion.runningBreathPeriod / 4)

        XCTAssertNotEqual(
            StatusPhase.compute(state: .running, at: t0).dotScale,
            StatusPhase.compute(state: .running, at: quarterCycle).dotScale
        )
    }

    func testLoopPeriodsAreHonored() {
        // One full period later the phase must repeat, or the dot would
        // visibly jump when a paused timeline resumes.
        let fullCycle = t0.addingTimeInterval(Motion.waitingPulsePeriod)

        XCTAssertEqual(
            StatusPhase.compute(state: .waiting, at: t0).dotScale,
            StatusPhase.compute(state: .waiting, at: fullCycle).dotScale,
            accuracy: 0.0001
        )
    }

    func testReducedMotionHoldsTheDotAtRest() {
        for state in [BarState.running, .waiting] {
            for offset in stride(from: 0.0, to: 2.0, by: 0.25) {
                let phase = StatusPhase.compute(
                    state: state,
                    at: t0.addingTimeInterval(offset),
                    animated: false
                )
                XCTAssertEqual(phase.dotScale, 1.0, "\(state) should not scale under Reduce Motion")
            }
        }
    }

    func testReducedMotionKeepsStateReadableAsGlow() {
        // Scale is what we drop; the colored glow is the remaining signal
        // that separates running/waiting from idle, so it must survive.
        let running = StatusPhase.compute(state: .running, at: t0, animated: false)
        let waiting = StatusPhase.compute(state: .waiting, at: t0, animated: false)

        XCTAssertGreaterThan(running.glowOpacity, 0)
        XCTAssertGreaterThan(waiting.glowOpacity, running.glowOpacity)
    }

    func testReducedMotionIsTimeInvariant() {
        let early = StatusPhase.compute(state: .waiting, at: t0, animated: false)
        let late = StatusPhase.compute(state: .waiting, at: t0.addingTimeInterval(37), animated: false)

        XCTAssertEqual(early.glowRadius, late.glowRadius)
        XCTAssertEqual(early.glowOpacity, late.glowOpacity)
    }

    func testIdleIsAlwaysDark() {
        for animated in [true, false] {
            let phase = StatusPhase.compute(state: .idle, at: t0, animated: animated)
            XCTAssertEqual(phase.dotScale, 1.0)
            XCTAssertEqual(phase.glowRadius, 0)
            XCTAssertEqual(phase.glowOpacity, 0)
        }
    }
}
