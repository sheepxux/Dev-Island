import AppKit
import XCTest
@testable import IslandAppLib

final class IslandWindowKeyboardFocusPolicyTests: XCTestCase {
    func testDirectClickActivatesAfterInteractionIsArmed() {
        XCTAssertTrue(IslandWindowKeyboardFocusPolicy.shouldActivate(
            eventType: .leftMouseDown,
            interactionEnabled: true,
            ignoresMouseEvents: false
        ))
    }

    func testLaunchAndAutomaticExpansionStayPassive() {
        XCTAssertFalse(IslandWindowKeyboardFocusPolicy.shouldActivate(
            eventType: .leftMouseDown,
            interactionEnabled: false,
            ignoresMouseEvents: false
        ))
    }

    func testTransparentHostAreaCannotTakeFocus() {
        XCTAssertFalse(IslandWindowKeyboardFocusPolicy.shouldActivate(
            eventType: .leftMouseDown,
            interactionEnabled: true,
            ignoresMouseEvents: true
        ))
    }

    func testHoverScrollAndKeyboardEventsNeverActivateWindow() {
        for eventType in [
            NSEvent.EventType.mouseMoved,
            .scrollWheel,
            .keyDown,
            .rightMouseDown,
        ] {
            XCTAssertFalse(IslandWindowKeyboardFocusPolicy.shouldActivate(
                eventType: eventType,
                interactionEnabled: true,
                ignoresMouseEvents: false
            ))
        }
    }
}
