import XCTest
@testable import IslandAppLib

/// `StatusPhase` is the shared time→cycle function behind the status matrix.
/// Under Reduce Motion every state must come to rest rather than freeze on
/// whichever frame its timeline happened to stop on.
final class StatusPhaseTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    func testLoopStatesFlowOverTime() {
        // A quarter of the running period apart lands on different points
        // of the matrix cycle.
        let quarterCycle = t0.addingTimeInterval(Motion.runningOrbitPeriod / 4)

        XCTAssertNotEqual(
            StatusPhase.compute(state: .running, at: t0).matrixPhase,
            StatusPhase.compute(state: .running, at: quarterCycle).matrixPhase
        )
    }

    func testLoopPeriodsAreHonored() {
        // One full period later the phase must repeat, or the dot would
        // visibly jump when a paused timeline resumes.
        let fullCycle = t0.addingTimeInterval(Motion.waitingBreathPeriod)

        XCTAssertEqual(
            StatusPhase.compute(state: .waiting, at: t0).matrixPhase,
            StatusPhase.compute(state: .waiting, at: fullCycle).matrixPhase,
            accuracy: 0.0001
        )
    }

    func testLoopPhasesStayNormalized() {
        for state in [BarState.running, .waiting] {
            for offset in stride(from: 0.0, to: 4.0, by: 0.125) {
                let phase = StatusPhase.compute(
                    state: state,
                    at: t0.addingTimeInterval(offset)
                )
                XCTAssertGreaterThanOrEqual(phase.matrixPhase, 0)
                XCTAssertLessThan(phase.matrixPhase, 1)
            }
        }
    }

    func testReducedMotionHoldsTheMatrixAtRest() {
        for state in [BarState.running, .waiting] {
            for offset in stride(from: 0.0, to: 2.0, by: 0.25) {
                let phase = StatusPhase.compute(
                    state: state,
                    at: t0.addingTimeInterval(offset),
                    animated: false
                )
                XCTAssertEqual(phase.matrixPhase, 0.5, "\(state) should not flow under Reduce Motion")
            }
        }
    }

    func testReducedMotionIsTimeInvariant() {
        let early = StatusPhase.compute(state: .waiting, at: t0, animated: false)
        let late = StatusPhase.compute(state: .waiting, at: t0.addingTimeInterval(37), animated: false)

        XCTAssertEqual(early.matrixPhase, late.matrixPhase)
    }

    func testIdleAndTerminalStatesStayStatic() {
        for state in [BarState.idle, .completed, .failed] {
            for animated in [true, false] {
                let phase = StatusPhase.compute(state: state, at: t0, animated: animated)
                XCTAssertEqual(phase.matrixPhase, 0.5)
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

    func testSemanticStatesHaveDistinctMatrixSignatures() {
        XCTAssertEqual(BarState.idle.matrixPattern, .field)
        XCTAssertEqual(BarState.running.matrixPattern, .orbit)
        XCTAssertEqual(BarState.waiting.matrixPattern, .ring)
        XCTAssertEqual(BarState.completed.matrixPattern, .plus)
        XCTAssertEqual(BarState.failed.matrixPattern, .cross)

        XCTAssertEqual(BarState.running.matrixMotion, .orbiting)
        XCTAssertEqual(BarState.waiting.matrixMotion, .attention)
        XCTAssertEqual(BarState.completed.matrixMotion, .still)
        XCTAssertEqual(BarState.failed.matrixMotion, .still)
    }

    func testAttentionCarriesTheStrongestSignal() {
        XCTAssertLessThan(BarState.idle.matrixIntensity, BarState.completed.matrixIntensity)
        XCTAssertLessThan(BarState.completed.matrixIntensity, BarState.running.matrixIntensity)
        XCTAssertLessThan(BarState.running.matrixIntensity, BarState.failed.matrixIntensity)
        XCTAssertLessThan(BarState.failed.matrixIntensity, BarState.waiting.matrixIntensity)
    }

    func testIdleFieldKeepsAllNinePointsVisibleAtCompactSize() {
        let opacities = (0..<3).flatMap { row in
            (0..<3).map { column in
                DotMatrixMark.opacity(
                    pattern: BarState.idle.matrixPattern,
                    motion: BarState.idle.matrixMotion,
                    intensity: BarState.idle.matrixIntensity,
                    row: row,
                    column: column,
                    phase: 0.5
                )
            }
        }

        XCTAssertEqual(opacities.count, 9)
        XCTAssertGreaterThanOrEqual(opacities.min() ?? 0, 0.36)
        XCTAssertGreaterThan(opacities[4], opacities[0])
        XCTAssertLessThan(BarState.idle.matrixIntensity, BarState.completed.matrixIntensity)
    }

    func testCompositorOpacityCurvesAreBoundedAndLoopWithoutAJump() {
        let animatedSignatures: [(
            pattern: DotMatrixMark.Pattern,
            motion: DotMatrixMark.MotionStyle,
            intensity: Double
        )] = [
            (.orbit, .orbiting, BarState.running.matrixIntensity),
            (.ring, .attention, BarState.waiting.matrixIntensity),
        ]

        for signature in animatedSignatures {
            for row in 0..<3 {
                for column in 0..<3 {
                    let start = DotMatrixMark.opacity(
                        pattern: signature.pattern,
                        motion: signature.motion,
                        intensity: signature.intensity,
                        row: row,
                        column: column,
                        phase: 0
                    )
                    let end = DotMatrixMark.opacity(
                        pattern: signature.pattern,
                        motion: signature.motion,
                        intensity: signature.intensity,
                        row: row,
                        column: column,
                        phase: 1
                    )
                    XCTAssertEqual(start, end, accuracy: 0.000_001)

                    for sample in 0...48 {
                        let opacity = DotMatrixMark.opacity(
                            pattern: signature.pattern,
                            motion: signature.motion,
                            intensity: signature.intensity,
                            row: row,
                            column: column,
                            phase: CGFloat(sample) / 48
                        )
                        XCTAssertGreaterThanOrEqual(opacity, 0)
                        XCTAssertLessThanOrEqual(opacity, 1)
                    }
                }
            }
        }
    }

    func testRunningOrbitMovesThePerimeterButKeepsItsCenterAnchored() {
        let topAtStart = DotMatrixMark.opacity(
            pattern: .orbit,
            motion: .orbiting,
            intensity: BarState.running.matrixIntensity,
            row: 0,
            column: 1,
            phase: 0
        )
        let topQuarterCycleLater = DotMatrixMark.opacity(
            pattern: .orbit,
            motion: .orbiting,
            intensity: BarState.running.matrixIntensity,
            row: 0,
            column: 1,
            phase: 0.25
        )
        XCTAssertNotEqual(topAtStart, topQuarterCycleLater, accuracy: 0.01)

        let centerAtStart = DotMatrixMark.opacity(
            pattern: .orbit,
            motion: .orbiting,
            intensity: BarState.running.matrixIntensity,
            row: 1,
            column: 1,
            phase: 0
        )
        let centerLater = DotMatrixMark.opacity(
            pattern: .orbit,
            motion: .orbiting,
            intensity: BarState.running.matrixIntensity,
            row: 1,
            column: 1,
            phase: 0.37
        )
        XCTAssertEqual(centerAtStart, centerLater, accuracy: 0.000_001)
    }
}
