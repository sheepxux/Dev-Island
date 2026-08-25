import XCTest
@testable import IslandAppLib

/// `StatusPhase` is the shared time→scale function behind the status dot.
/// Under Reduce Motion every state must come to rest rather than freeze on
/// whichever frame its timeline happened to stop on.
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
        let fullCycle = t0.addingTimeInterval(Motion.waitingBreathPeriod)

        XCTAssertEqual(
            StatusPhase.compute(state: .waiting, at: t0).dotScale,
            StatusPhase.compute(state: .waiting, at: fullCycle).dotScale,
            accuracy: 0.0001
        )
    }

    func testLoopAmplitudesStayRestrained() {
        let runningPeak = t0.addingTimeInterval(Motion.runningBreathPeriod / 4)
        let waitingPeak = t0.addingTimeInterval(Motion.waitingBreathPeriod / 4)

        XCTAssertEqual(
            StatusPhase.compute(state: .running, at: runningPeak).dotScale,
            1.08,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            StatusPhase.compute(state: .waiting, at: waitingPeak).dotScale,
            1.12,
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

    func testReducedMotionIsTimeInvariant() {
        let early = StatusPhase.compute(state: .waiting, at: t0, animated: false)
        let late = StatusPhase.compute(state: .waiting, at: t0.addingTimeInterval(37), animated: false)

        XCTAssertEqual(early.dotScale, late.dotScale)
    }

    func testIdleAndTerminalStatesStayStatic() {
        for state in [BarState.idle, .completed, .failed] {
            for animated in [true, false] {
                let phase = StatusPhase.compute(state: state, at: t0, animated: animated)
                XCTAssertEqual(phase.dotScale, 1.0)
            }
        }
    }

    func testEveryStateDisablesColoredGlow() {
        for state in [BarState.idle, .running, .waiting, .completed, .failed] {
            for animated in [true, false] {
                let phase = StatusPhase.compute(state: state, at: t0, animated: animated)
                XCTAssertEqual(phase.glowRadius, 0)
                XCTAssertEqual(phase.glowOpacity, 0)
            }
        }
    }
}
