import XCTest
@testable import IslandAppLib

final class TaskCardLeadingIdentityMetricsTests: XCTestCase {
    func testStatusMatrixAndAgentLogoUseSeparateNonOverlappingSlots() {
        XCTAssertGreaterThan(TaskCardLeadingIdentityMetrics.spacing, 0)
        XCTAssertEqual(
            TaskCardLeadingIdentityMetrics.width,
            TaskCardLeadingIdentityMetrics.statusSize
                + TaskCardLeadingIdentityMetrics.spacing
                + TaskCardLeadingIdentityMetrics.logoSize
        )

        let statusTrailingEdge = TaskCardLeadingIdentityMetrics.statusSize
        let logoLeadingEdge = statusTrailingEdge
            + TaskCardLeadingIdentityMetrics.spacing
        XCTAssertGreaterThan(logoLeadingEdge, statusTrailingEdge)
    }
}
