import XCTest
@testable import IslandAppLib

final class IslandPanelActivityTimingTests: XCTestCase {
    func testLiveEffectsWaitUntilGeometryMorphHasSettled() {
        XCTAssertGreaterThan(
            IslandPanelActivityTiming.liveEffectsDelay,
            Motion.islandMorphDuration
        )
        XCTAssertGreaterThan(
            IslandPanelActivityTiming.liveEffectsDelay,
            IslandPanelActivityTiming.contentRevealDelay
        )
    }

    func testReducedMotionDoesNotAddASpatialSettleDelay() {
        XCTAssertEqual(
            IslandPanelActivityTiming.liveEffectsDelay(reduceMotion: true),
            0
        )
        XCTAssertEqual(
            IslandPanelActivityTiming.liveEffectsDelay(reduceMotion: false),
            IslandPanelActivityTiming.liveEffectsDelay
        )
    }
}
