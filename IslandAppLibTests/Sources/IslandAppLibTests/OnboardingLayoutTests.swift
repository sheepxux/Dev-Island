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
        XCTAssertGreaterThanOrEqual(OnboardingMetrics.stageRadius, 10)
        XCTAssertGreaterThan(OnboardingMetrics.windowRadius, OnboardingMetrics.stageRadius)
    }

    func testSkipActionDisappearsWhenTheTourHasReachedItsDecisionStep() {
        XCTAssertTrue(OnboardingNavigationPolicy.showsSkipAction(step: 0, stepCount: 3))
        XCTAssertTrue(OnboardingNavigationPolicy.showsSkipAction(step: 1, stepCount: 3))
        XCTAssertFalse(OnboardingNavigationPolicy.showsSkipAction(step: 2, stepCount: 3))
        XCTAssertFalse(OnboardingNavigationPolicy.showsSkipAction(step: -1, stepCount: 3))
        XCTAssertFalse(OnboardingNavigationPolicy.showsSkipAction(step: 0, stepCount: 1))
    }
}
