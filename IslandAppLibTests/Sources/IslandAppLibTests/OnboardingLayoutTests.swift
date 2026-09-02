import XCTest
@testable import IslandAppLib

final class OnboardingLayoutTests: XCTestCase {
    func testEditorialColumnsConsumeTheFixedWindowWithoutImplicitSlack() {
        let occupiedWidth =
            (OnboardingMetrics.contentHorizontalPadding * 2)
            + OnboardingMetrics.editorialWidth
            + OnboardingMetrics.editorialSpacing
            + OnboardingMetrics.stageWidth

        XCTAssertEqual(occupiedWidth, OnboardingMetrics.width)
    }

    func testSurfaceRadiiCreateAQuietWindowToStageHierarchy() {
        XCTAssertGreaterThanOrEqual(OnboardingMetrics.stageRadius, 14)
        XCTAssertGreaterThan(OnboardingMetrics.windowRadius, OnboardingMetrics.stageRadius)
    }

    func testCompactConnectionStatesDoNotLeakDiagnosticsIntoWelcomeGrid() {
        XCTAssertEqual(
            OnboardingConnectionStatusPresentation.compactLabel(
                state: .configured,
                hasError: false
            ),
            "Configured"
        )
        XCTAssertEqual(
            OnboardingConnectionStatusPresentation.compactLabel(
                state: .updateRequired,
                hasError: false
            ),
            "Needs update"
        )
        XCTAssertEqual(
            OnboardingConnectionStatusPresentation.compactLabel(
                state: .connected,
                hasError: true
            ),
            "Try again"
        )
    }

    func testSkipActionDisappearsWhenTheTourHasReachedItsDecisionStep() {
        XCTAssertTrue(OnboardingNavigationPolicy.showsSkipAction(step: 0, stepCount: 4))
        XCTAssertTrue(OnboardingNavigationPolicy.showsSkipAction(step: 1, stepCount: 4))
        XCTAssertTrue(OnboardingNavigationPolicy.showsSkipAction(step: 2, stepCount: 4))
        XCTAssertFalse(OnboardingNavigationPolicy.showsSkipAction(step: 3, stepCount: 4))
        XCTAssertFalse(OnboardingNavigationPolicy.showsSkipAction(step: -1, stepCount: 4))
        XCTAssertFalse(OnboardingNavigationPolicy.showsSkipAction(step: 0, stepCount: 1))
    }
}
