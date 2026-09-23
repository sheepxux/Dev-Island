import XCTest
@testable import IslandAppLib

final class WelcomeTutorialLayoutTests: XCTestCase {
    private let canvas = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let cardSize = CGSize(width: OnboardingMetrics.width, height: 300)

    func testScreenRectConvertsToTopLeftCanvasSpace() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let island = CGRect(x: 830, y: 1052, width: 260, height: 28)

        XCTAssertEqual(
            WelcomeTutorialLayout.canvasRect(fromScreenRect: island, screenFrame: screen),
            CGRect(x: 830, y: 0, width: 260, height: 28)
        )
    }

    func testSecondaryScreenOriginIsRemovedFromCanvasCoordinates() {
        let screen = CGRect(x: 1920, y: -200, width: 1440, height: 900)
        let island = CGRect(x: 2500, y: 672, width: 260, height: 28)

        XCTAssertEqual(
            WelcomeTutorialLayout.canvasRect(fromScreenRect: island, screenFrame: screen),
            CGRect(x: 580, y: 0, width: 260, height: 28)
        )
    }

    func testCardSitsCenteredUnderTheTargetWithAConnector() {
        let target = CGRect(x: 830, y: 0, width: 260, height: 28)

        let placement = WelcomeTutorialLayout.placement(
            target: target,
            cardSize: cardSize,
            canvas: canvas
        )

        XCTAssertEqual(placement.spotlight, target.insetBy(dx: -10, dy: -10))
        XCTAssertEqual(placement.card.midX, target.midX, accuracy: 0.5)
        XCTAssertEqual(
            placement.card.minY,
            target.maxY + WelcomeTutorialLayout.spotlightInset + WelcomeTutorialLayout.connectorLength,
            accuracy: 0.5
        )
        XCTAssertEqual(
            placement.connector,
            WelcomeTutorialLayout.Connector(
                start: CGPoint(x: target.midX, y: target.maxY + WelcomeTutorialLayout.spotlightInset),
                end: CGPoint(x: target.midX, y: placement.card.minY)
            )
        )
    }

    func testCardNearTheRightEdgeStaysInsideAndKeepsTheConnectorOffItsCorner() {
        let statusItem = CGRect(x: 1880, y: 0, width: 24, height: 24)

        let placement = WelcomeTutorialLayout.placement(
            target: statusItem,
            cardSize: cardSize,
            canvas: canvas
        )

        XCTAssertEqual(placement.card.maxX, canvas.maxX - WelcomeTutorialLayout.edgeMargin, accuracy: 0.5)
        XCTAssertEqual(
            placement.connector?.start.x,
            placement.card.maxX - WelcomeTutorialLayout.connectorCornerClearance
        )
        XCTAssertEqual(placement.connector?.start.x, placement.connector?.end.x)
    }

    func testCardWithoutATargetIsCenteredWithoutSpotlightOrConnector() {
        let placement = WelcomeTutorialLayout.placement(
            target: nil,
            cardSize: cardSize,
            canvas: canvas
        )

        XCTAssertNil(placement.spotlight)
        XCTAssertNil(placement.connector)
        XCTAssertEqual(placement.card.midX, canvas.midX, accuracy: 0.5)
        XCTAssertEqual(placement.card.midY, canvas.midY, accuracy: 0.5)
    }

    func testCardTooTallForTheSpaceBelowIsPinnedToTheBottomMarginWithoutAConnector() {
        let panel = CGRect(x: 751, y: 0, width: 418, height: 420)
        let tallCard = CGSize(width: OnboardingMetrics.width, height: 700)

        let placement = WelcomeTutorialLayout.placement(
            target: panel,
            cardSize: tallCard,
            canvas: canvas
        )

        XCTAssertEqual(placement.card.maxY, canvas.maxY - WelcomeTutorialLayout.edgeMargin, accuracy: 0.5)
        XCTAssertNil(placement.connector)
        XCTAssertNotNil(placement.spotlight)
    }
}
