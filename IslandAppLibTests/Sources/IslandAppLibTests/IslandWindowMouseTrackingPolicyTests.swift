import XCTest
@testable import IslandAppLib

final class IslandWindowMouseTrackingPolicyTests: XCTestCase {
    func testIdleWatchdogIsAtMostOneWakeupPerSecond() {
        XCTAssertEqual(
            IslandWindowMouseTrackingPolicy.idleWatchdogInterval,
            1.0
        )
        XCTAssertEqual(
            IslandWindowMouseTrackingPolicy.maximumIdleWakeupsPerMinute,
            60
        )
        XCTAssertEqual(
            IslandWindowMouseTrackingPolicy.interval(
                pointerInside: false,
                mode: .collapsed
            ),
            IslandWindowMouseTrackingPolicy.idleWatchdogInterval
        )
        XCTAssertEqual(
            IslandWindowMouseTrackingPolicy.interval(
                pointerInside: false,
                mode: .expanded
            ),
            IslandWindowMouseTrackingPolicy.idleWatchdogInterval
        )
    }

    func testCompactPointerInsideKeepsResponsiveCursorCadence() {
        XCTAssertEqual(
            IslandWindowMouseTrackingPolicy.activeInterval,
            0.04
        )
        XCTAssertEqual(
            IslandWindowMouseTrackingPolicy.interval(
                pointerInside: true,
                mode: .collapsed
            ),
            IslandWindowMouseTrackingPolicy.activeInterval
        )
        XCTAssertLessThanOrEqual(
            IslandWindowMouseTrackingPolicy.activeInterval,
            0.05
        )
    }

    func testExpandedPointerInsideReturnsToIdleWatchdogCadence() {
        XCTAssertEqual(
            IslandWindowMouseTrackingPolicy.interval(
                pointerInside: true,
                mode: .expanded
            ),
            IslandWindowMouseTrackingPolicy.idleWatchdogInterval
        )
    }
}
