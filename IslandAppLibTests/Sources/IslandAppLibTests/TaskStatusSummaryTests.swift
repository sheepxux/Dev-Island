import XCTest
@testable import IslandAppLib
import IslandCore

final class TaskStatusSummaryTests: XCTestCase {
    func testActiveSegmentsUseAttentionFirstOrder() {
        let summary = TaskStatusSummary(running: 2, waiting: 1, failed: 1, completed: 4)

        XCTAssertEqual(summary.segments.map(\.status), [.waiting, .failed, .running])
        XCTAssertEqual(summary.segments.map(\.count), [1, 1, 2])
    }

    func testCompletedOnlyAppearsWhenNothingIsActive() {
        XCTAssertEqual(
            TaskStatusSummary(completed: 3).segments,
            [.init(status: .completed, count: 3)]
        )
        XCTAssertTrue(TaskStatusSummary().segments.isEmpty)
    }

    func testAccessibilityLabelIncludesEveryState() {
        let summary = TaskStatusSummary(running: 2, waiting: 1, failed: 1, completed: 4)

        XCTAssertEqual(summary.accessibilityLabel, "1 waiting, 1 failed, 2 running, 4 completed")
    }
}
