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

    func testBloomFollowsTheSpotlightAndFallsBackToTheCard() {
        let target = CGRect(x: 830, y: 0, width: 260, height: 28)
        let pointed = WelcomeTutorialLayout.placement(target: target, cardSize: cardSize, canvas: canvas)
        let centered = WelcomeTutorialLayout.placement(target: nil, cardSize: cardSize, canvas: canvas)

        XCTAssertEqual(
            WelcomeTutorialLayout.bloomCenter(of: pointed),
            CGPoint(x: pointed.spotlight!.midX, y: pointed.spotlight!.midY)
        )
        XCTAssertEqual(
            WelcomeTutorialLayout.bloomCenter(of: centered),
            CGPoint(x: centered.card.midX, y: centered.card.midY)
        )
    }

    func testBreathingRingRestsAtItsQuietOpacityAndPeaksMidCycle() {
        XCTAssertEqual(WelcomeTutorialLayout.breathOpacity(phase: 0), WelcomeTutorialLayout.restOpacity, accuracy: 0.0001)
        XCTAssertEqual(WelcomeTutorialLayout.breathOpacity(phase: 1), WelcomeTutorialLayout.restOpacity, accuracy: 0.0001)
        XCTAssertEqual(WelcomeTutorialLayout.breathOpacity(phase: 0.5), 1, accuracy: 0.0001)
        for phase in stride(from: 0.0, through: 1.0, by: 0.05) {
            let opacity = WelcomeTutorialLayout.breathOpacity(phase: phase)
            XCTAssertGreaterThanOrEqual(opacity, WelcomeTutorialLayout.restOpacity)
            XCTAssertLessThanOrEqual(opacity, 1)
        }
    }

    func testTravellingPointStartsAtTheSpotlightAndArrivesAtTheCard() {
        let connector = WelcomeTutorialLayout.Connector(
            start: CGPoint(x: 960, y: 38),
            end: CGPoint(x: 960, y: 200)
        )

        XCTAssertEqual(WelcomeTutorialLayout.travelPoint(on: connector, phase: 0), connector.start)
        XCTAssertEqual(WelcomeTutorialLayout.travelPoint(on: connector, phase: 1), connector.end)
        XCTAssertEqual(WelcomeTutorialLayout.travelPoint(on: connector, phase: 0.5).y, 119, accuracy: 0.5)
        XCTAssertEqual(WelcomeTutorialLayout.travelPoint(on: connector, phase: 2), connector.end)
        XCTAssertEqual(WelcomeTutorialLayout.travelPoint(on: connector, phase: -1), connector.start)
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
