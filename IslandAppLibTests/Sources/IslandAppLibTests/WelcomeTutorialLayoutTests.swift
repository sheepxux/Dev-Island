import XCTest
@testable import IslandAppLib

final class WelcomeTutorialLayoutTests: XCTestCase {
    private let canvas = CGRect(x: 0, y: 0, width: 1920, height: 1050)
    private let cardSize = CGSize(width: OnboardingMetrics.width, height: 288)
    private let collapsedIsland = CGRect(x: 830, y: 0, width: 260, height: 0)
    private let panel = CGRect(x: 751, y: -30, width: 418, height: 420)

    func testScreenRectConvertsToTopLeftCanvasSpace() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let island = CGRect(x: 830, y: 1052, width: 260, height: 28)

        XCTAssertEqual(
            WelcomeTutorialLayout.canvasRect(fromScreenRect: island, screenFrame: screen),
            CGRect(x: 830, y: 0, width: 260, height: 28)
        )
    }

    func testStageFrameStopsAtTheMenuBarsLowerEdge() {
        let screen = CGRect(x: 1920, y: -200, width: 1440, height: 900)

        let stage = WelcomeTutorialLayout.stageFrame(screenFrame: screen, menuBarHeight: 37)

        XCTAssertEqual(stage, CGRect(x: 1920, y: -200, width: 1440, height: 863))
        XCTAssertEqual(stage.maxY, screen.maxY - 37, "the band above the stage belongs to the menu bar")
        XCTAssertEqual(
            WelcomeTutorialLayout.stageFrame(screenFrame: screen, menuBarHeight: 0),
            screen
        )
        XCTAssertEqual(
            WelcomeTutorialLayout.stageFrame(screenFrame: screen, menuBarHeight: 2_000).height,
            0
        )
    }

    func testTargetInsideTheMenuBarBandConvertsToTheStagesTopEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let stage = WelcomeTutorialLayout.stageFrame(screenFrame: screen, menuBarHeight: 30)
        let collapsedIsland = CGRect(x: 830, y: 1050, width: 260, height: 30)
        let panel = CGRect(x: 751, y: 660, width: 418, height: 420)

        let islandRect = WelcomeTutorialLayout.canvasRect(fromScreenRect: collapsedIsland, screenFrame: stage)
        XCTAssertEqual(islandRect.maxY, 0, accuracy: 0.001, "the collapsed island ends where the stage begins")

        let panelRect = WelcomeTutorialLayout.canvasRect(fromScreenRect: panel, screenFrame: stage)
        XCTAssertEqual(panelRect.minY, -30, accuracy: 0.001)
        XCTAssertEqual(panelRect.maxY, 390, accuracy: 0.001, "the panel reaches 390pt below the band")
    }

    func testSecondaryScreenOriginIsRemovedFromCanvasCoordinates() {
        let screen = CGRect(x: 1920, y: -200, width: 1440, height: 900)
        let island = CGRect(x: 2500, y: 672, width: 260, height: 28)

        XCTAssertEqual(
            WelcomeTutorialLayout.canvasRect(fromScreenRect: island, screenFrame: screen),
            CGRect(x: 580, y: 0, width: 260, height: 28)
        )
    }

    func testTargetInsideTheBandGetsAShelfAndTheCardSitsOnTheReadingLine() {
        let placement = WelcomeTutorialLayout.placement(
            target: collapsedIsland,
            cardSize: cardSize,
            canvas: canvas
        )

        XCTAssertEqual(WelcomeTutorialLayout.readingLine, 68)
        XCTAssertEqual(
            placement.plate,
            WelcomeTutorialLayout.Plate(
                rect: CGRect(x: 816, y: 0, width: 288, height: WelcomeTutorialLayout.shelfHeight),
                cornerRadius: WelcomeTutorialLayout.shelfCornerRadius
            )
        )
        XCTAssertEqual(placement.card.midX, collapsedIsland.midX, accuracy: 0.5)
        XCTAssertEqual(placement.card.minY, WelcomeTutorialLayout.readingLine, accuracy: 0.5)
        XCTAssertEqual(
            placement.connector,
            WelcomeTutorialLayout.Connector(
                start: CGPoint(x: collapsedIsland.midX, y: WelcomeTutorialLayout.shelfHeight),
                end: CGPoint(x: collapsedIsland.midX, y: WelcomeTutorialLayout.readingLine)
            )
        )
    }

    func testHoveredCollapsedIslandPeekingBelowTheBandKeepsItsShelf() {
        // Hovering the collapsed island grows it by the hover boost below
        // the menu bar; that is still the band, not a 2pt-tall panel.
        let hovered = CGRect(x: 830, y: 0, width: 260, height: WelcomeTutorialLayout.inBandTolerance)
        XCTAssertEqual(WelcomeTutorialLayout.inBandTolerance, NotchMetrics.hoverHeightBoostNotched)

        let placement = WelcomeTutorialLayout.placement(
            target: hovered,
            cardSize: cardSize,
            canvas: canvas
        )
        let resting = WelcomeTutorialLayout.placement(
            target: collapsedIsland,
            cardSize: cardSize,
            canvas: canvas
        )

        XCTAssertEqual(placement.plate?.rect.height, WelcomeTutorialLayout.shelfHeight)
        XCTAssertEqual(placement.plate?.cornerRadius, WelcomeTutorialLayout.shelfCornerRadius)
        XCTAssertEqual(placement.card, resting.card, "the card must not bob when the pointer enters the island")
        XCTAssertEqual(placement.connector, resting.connector)
    }

    func testPanelBelowTheBandIsWrappedConcentrically() {
        let placement = WelcomeTutorialLayout.placement(
            target: panel,
            cardSize: cardSize,
            canvas: canvas
        )

        XCTAssertEqual(
            WelcomeTutorialLayout.plateCornerRadius,
            NotchMetrics.panelCornerRadius + WelcomeTutorialLayout.plateInset
        )
        let plate = try! XCTUnwrap(placement.plate)
        XCTAssertEqual(plate.cornerRadius, WelcomeTutorialLayout.plateCornerRadius)
        XCTAssertEqual(plate.rect.minY, 0, "the plate always hangs from the band's lower edge")
        XCTAssertEqual(plate.rect.minX, panel.minX - WelcomeTutorialLayout.plateInset)
        XCTAssertEqual(plate.rect.maxX, panel.maxX + WelcomeTutorialLayout.plateInset)
        XCTAssertEqual(plate.rect.maxY, panel.maxY + WelcomeTutorialLayout.plateInset)
        XCTAssertEqual(
            placement.card.minY,
            plate.rect.maxY + WelcomeTutorialLayout.connectorLength,
            accuracy: 0.5
        )
        XCTAssertEqual(placement.connector?.start, CGPoint(x: panel.midX, y: plate.rect.maxY))
        XCTAssertEqual(placement.connector?.end, CGPoint(x: panel.midX, y: placement.card.minY))
    }

    func testCardNearTheRightEdgeStaysInsideAndTheShelfReachesTheStem() {
        let statusItem = CGRect(x: 1880, y: 0, width: 24, height: 0)

        let placement = WelcomeTutorialLayout.placement(
            target: statusItem,
            cardSize: cardSize,
            canvas: canvas
        )

        XCTAssertEqual(placement.card.maxX, canvas.maxX - WelcomeTutorialLayout.edgeMargin, accuracy: 0.5)
        XCTAssertEqual(placement.card.minY, WelcomeTutorialLayout.readingLine, accuracy: 0.5)
        let stemX = try! XCTUnwrap(placement.connector?.start.x)
        XCTAssertEqual(stemX, placement.card.maxX - WelcomeTutorialLayout.connectorCornerClearance)
        XCTAssertEqual(placement.connector?.end.x, stemX)
        let plate = try! XCTUnwrap(placement.plate)
        XCTAssertLessThanOrEqual(plate.rect.minX, stemX - WelcomeTutorialLayout.shelfInset)
        XCTAssertGreaterThanOrEqual(plate.rect.maxX, statusItem.maxX + WelcomeTutorialLayout.shelfInset)
        XCTAssertEqual(plate.rect.height, WelcomeTutorialLayout.shelfHeight)
    }

    func testCardWithoutATargetIsCenteredOnTheReadingLineWithoutPlateOrStem() {
        let placement = WelcomeTutorialLayout.placement(
            target: nil,
            cardSize: cardSize,
            canvas: canvas
        )

        XCTAssertNil(placement.plate)
        XCTAssertNil(placement.connector)
        XCTAssertEqual(placement.card.midX, canvas.midX, accuracy: 0.5)
        XCTAssertEqual(placement.card.minY, WelcomeTutorialLayout.readingLine, accuracy: 0.5)
    }

    func testUnusableTargetsFallBackToTheNoTargetLayout() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let band = CGRect(x: 0, y: 1050, width: 1920, height: 30)

        XCTAssertNil(WelcomeTutorialLayout.usableTarget(nil, within: band))
        XCTAssertNil(WelcomeTutorialLayout.usableTarget(.zero, within: band))
        XCTAssertNil(
            WelcomeTutorialLayout.usableTarget(CGRect(x: 1880, y: 500, width: 24, height: 24), within: band),
            "an item the menu bar moved out of the band is not pointed at"
        )
        XCTAssertNil(
            WelcomeTutorialLayout.usableTarget(CGRect(x: -200, y: 1052, width: 24, height: 24), within: band),
            "an overflowed item off the screen is not pointed at"
        )
        let item = CGRect(x: 1880, y: 1052, width: 24, height: 24)
        XCTAssertEqual(WelcomeTutorialLayout.usableTarget(item, within: band), item)
        let island = CGRect(x: 830, y: 1052, width: 260, height: 28)
        XCTAssertEqual(WelcomeTutorialLayout.usableTarget(island, within: screen), island)
    }

    func testPulseTravelsThenRestsHidden() {
        let atPlate = WelcomeTutorialLayout.pulse(phase: 0)
        XCTAssertEqual(atPlate.progress, 0, accuracy: 0.0001)
        XCTAssertEqual(atPlate.opacity, 0, accuracy: 0.0001)

        let halfFadedIn = WelcomeTutorialLayout.pulse(phase: 0.0375)
        XCTAssertEqual(halfFadedIn.progress, 0.05, accuracy: 0.0001)
        XCTAssertEqual(halfFadedIn.opacity, 0.5, accuracy: 0.0001)

        let midway = WelcomeTutorialLayout.pulse(phase: 0.375)
        XCTAssertEqual(midway.progress, 0.5, accuracy: 0.0001)
        XCTAssertEqual(midway.opacity, 1, accuracy: 0.0001)

        let fadingOut = WelcomeTutorialLayout.pulse(phase: 0.7125)
        XCTAssertEqual(fadingOut.progress, 0.95, accuracy: 0.0001)
        XCTAssertEqual(fadingOut.opacity, 0.5, accuracy: 0.0001)

        for phase in [0.75, 0.9, 1.0] {
            let resting = WelcomeTutorialLayout.pulse(phase: phase)
            XCTAssertEqual(resting.progress, 1, accuracy: 0.0001, "\(phase)")
            XCTAssertEqual(resting.opacity, 0, accuracy: 0.0001, "\(phase)")
        }
        for phase in stride(from: 0.0, through: 1.0, by: 0.05) {
            let pulse = WelcomeTutorialLayout.pulse(phase: phase)
            XCTAssertGreaterThanOrEqual(pulse.opacity, 0)
            XCTAssertLessThanOrEqual(pulse.opacity, 1)
            XCTAssertGreaterThanOrEqual(pulse.progress, 0)
            XCTAssertLessThanOrEqual(pulse.progress, 1)
        }
    }

    func testTravellingPointStartsAtThePlateAndArrivesAtTheCard() {
        let connector = WelcomeTutorialLayout.Connector(
            start: CGPoint(x: 960, y: 40),
            end: CGPoint(x: 960, y: 200)
        )

        XCTAssertEqual(WelcomeTutorialLayout.travelPoint(on: connector, phase: 0), connector.start)
        XCTAssertEqual(WelcomeTutorialLayout.travelPoint(on: connector, phase: 1), connector.end)
        XCTAssertEqual(WelcomeTutorialLayout.travelPoint(on: connector, phase: 0.5).y, 120, accuracy: 0.5)
        XCTAssertEqual(WelcomeTutorialLayout.travelPoint(on: connector, phase: 2), connector.end)
        XCTAssertEqual(WelcomeTutorialLayout.travelPoint(on: connector, phase: -1), connector.start)
    }

    func testCardTooTallForTheSpaceBelowIsPinnedToTheBottomMarginWithoutAStem() {
        let tallCard = CGSize(width: OnboardingMetrics.width, height: 700)

        let placement = WelcomeTutorialLayout.placement(
            target: panel,
            cardSize: tallCard,
            canvas: canvas
        )

        XCTAssertEqual(placement.card.maxY, canvas.maxY - WelcomeTutorialLayout.edgeMargin, accuracy: 0.5)
        XCTAssertNil(placement.connector)
        XCTAssertNotNil(placement.plate)
    }
}
