import XCTest
@testable import IslandAppLib

final class InteractionFeedbackPolicyTests: XCTestCase {
    func testPressScaleRemainsAtRestUnderReducedMotion() {
        XCTAssertEqual(
            InteractionFeedbackPolicy.pressScale(
                isPressed: true,
                pressedScale: 0.96,
                reduceMotion: true
            ),
            1
        )
    }

    func testPressScaleKeepsSubtleFeedbackWithoutReducedMotion() {
        XCTAssertEqual(
            InteractionFeedbackPolicy.pressScale(
                isPressed: true,
                pressedScale: 0.997,
                reduceMotion: false
            ),
            0.997
        )
        XCTAssertEqual(
            InteractionFeedbackPolicy.pressScale(
                isPressed: false,
                pressedScale: 0.997,
                reduceMotion: false
            ),
            1
        )
    }

    func testSpatialFeedbackPolicyFollowsSystemPreference() {
        XCTAssertFalse(Motion.allowsSpatialFeedback(true))
        XCTAssertTrue(Motion.allowsSpatialFeedback(false))
    }
}
