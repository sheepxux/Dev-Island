import XCTest
@testable import IslandAppLib

final class OnboardingLayoutTests: XCTestCase {
    /// Every step lays out on one central axis: the column plus the chrome
    /// margins must fit the fixed window, and the island specimen opens wider
    /// than it rests without ever leaving the column.
    func testFloatColumnSitsOnTheWindowAxisInsideTheChromeMargins() {
        XCTAssertLessThanOrEqual(
            OnboardingMetrics.columnWidth + (OnboardingMetrics.contentHorizontalPadding * 2),
            OnboardingMetrics.width
        )
        XCTAssertGreaterThan(
            OnboardingMetrics.islandRequestWidth,
            OnboardingMetrics.islandCompactWidth
        )
        XCTAssertLessThanOrEqual(
            OnboardingMetrics.islandRequestWidth,
            OnboardingMetrics.columnWidth
        )
    }

    /// The specimen is the island, not a lookalike: its open corner is the
    /// real panel's corner, and the window's corner stays the largest radius.
    func testSpecimenRadiiMirrorTheRealIslandInsideAQuieterWindow() {
        XCTAssertEqual(OnboardingMetrics.islandRequestRadius, NotchMetrics.panelCornerRadius)
        XCTAssertGreaterThan(OnboardingMetrics.windowRadius, Palette.Window.Radius.group)
    }

    func testCompactConnectionStatesDoNotLeakDiagnosticsIntoWelcomeGrid() {
        XCTAssertEqual(
            OnboardingConnectionStatusPresentation.compactLabel(
                state: .configured,
                hasError: false
            ),
            "Needs authorization"
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
