import AppKit
import SwiftUI
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

    func testCollapseReleasesActivationWheneverTheIslandIsKey() {
        XCTAssertTrue(IslandWindowKeyboardFocusPolicy.shouldReleaseActivation(
            islandIsKey: true,
            activatedByDirectEngagement: false,
            conventionalSurfaceIsKey: false
        ))
    }

    func testCollapseReturnsFocusTakenByAClickEvenWhenNoIslandWindowIsKey() {
        XCTAssertTrue(IslandWindowKeyboardFocusPolicy.shouldReleaseActivation(
            islandIsKey: false,
            activatedByDirectEngagement: true,
            conventionalSurfaceIsKey: false
        ))
    }

    func testCollapseLeavesASettingsOrTourWindowInCharge() {
        XCTAssertFalse(IslandWindowKeyboardFocusPolicy.shouldReleaseActivation(
            islandIsKey: false,
            activatedByDirectEngagement: true,
            conventionalSurfaceIsKey: true
        ))
    }

    func testCollapseNeverDeactivatesAnAppTheIslandDidNotActivate() {
        XCTAssertFalse(IslandWindowKeyboardFocusPolicy.shouldReleaseActivation(
            islandIsKey: false,
            activatedByDirectEngagement: false,
            conventionalSurfaceIsKey: false
        ))
    }

    @MainActor
    func testIslandContentAcceptsTheFirstClickWithoutAnActivationRoundTrip() {
        let host = FirstMouseHostingView(rootView: Color.clear)
        XCTAssertTrue(host.acceptsFirstMouse(for: nil))
        XCTAssertFalse(NSHostingView(rootView: Color.clear).acceptsFirstMouse(for: nil))
    }
}
