import XCTest
@testable import IslandAppLib

/// Guards the invariant that the expanded panel can always draw everything
/// it builds. The panel's silhouette clips to its own height, so when the
/// height was a fixed 360pt guess a full task list could extend outside the
/// silhouette and get clipped.
final class PanelGeometryTests: XCTestCase {
    /// Worst-case chrome wrapped around the task list, measured off
    /// `NotchPanelView`: a notched header (the menu-bar band, ~40pt at the
    /// top of the current hardware range), the 8pt gap above the list, and
    /// 10pt bottom list padding.
    private let chromeBudget: CGFloat = 40 + 8 + 10

    func testPanelCeilingFitsAFullTaskListPlusChrome() {
        XCTAssertGreaterThanOrEqual(
            NotchMetrics.panelMaxHeight,
            NotchMetrics.panelTaskListMaxHeight + chromeBudget,
            "Raising the task-list cap or adding panel chrome also needs a taller panelMaxHeight, or the panel clips its content."
        )
    }

    func testMeasuredContentHeightIsUsedVerbatimInsideTheRange() {
        let content = NotchMetrics.panelTaskListMaxHeight
        XCTAssertEqual(NotchMetrics.panelHeight(forContentHeight: content), content)
    }

    func testHeightIsClampedAtBothEnds() {
        // A zero measurement happens for one layout pass before the panel
        // has reported its size; it must not collapse the silhouette.
        XCTAssertEqual(
            NotchMetrics.panelHeight(forContentHeight: 0),
            NotchMetrics.panelMinHeight
        )
        XCTAssertEqual(
            NotchMetrics.panelHeight(forContentHeight: 10_000),
            NotchMetrics.panelMaxHeight
        )
    }

    func testFloorIsBelowCeiling() {
        XCTAssertLessThan(NotchMetrics.panelMinHeight, NotchMetrics.panelMaxHeight)
    }
}
