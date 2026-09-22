import XCTest
@testable import IslandAppLib

/// The window palette is ink on the icon's beige tile. These ratios are what
/// the design leans on; a token that drifts below them silently makes
/// Settings hard to read on the light ground.
final class WindowPaletteTests: XCTestCase {
    private typealias C = WindowPaletteContrast

    func testPrimaryInkClearsAAAOnEveryGround() {
        XCTAssertGreaterThanOrEqual(C.ratio(C.ink, on: C.canvas), 7)
        XCTAssertGreaterThanOrEqual(C.ratio(C.ink, on: C.canvasDeep), 7)
        XCTAssertGreaterThanOrEqual(C.ratio(C.onInk, on: C.ink), 7, "primary capsule label")
    }

    func testSupportingCopyClearsAAAndIncreasedContrastGoesDarker() {
        XCTAssertGreaterThanOrEqual(C.ratio(C.textSecondary, on: C.canvas), 4.5)
        XCTAssertGreaterThan(
            C.ratio(C.textSecondaryIncreased, on: C.canvas),
            C.ratio(C.textSecondary, on: C.canvas)
        )
        XCTAssertLessThan(
            C.relativeLuminance(hex: C.textSecondaryIncreased),
            C.relativeLuminance(hex: C.textSecondary),
            "on a light ground Increase Contrast must darken quiet ink, not brighten it"
        )
    }

    func testTertiaryInkSupportsSmallStatusAndAuthorizationText() {
        for ground in [C.canvas, C.canvasDeep, 0xFFFFFF] {
            XCTAssertGreaterThanOrEqual(C.ratio(C.textTertiary, on: ground), 4.5)
        }
    }

    func testSemanticInkReadsAsTextOnTheBeigeGround() {
        for (name, hex) in [
            ("attention", C.attentionText),
            ("destructive", C.destructive),
            ("running", C.stateRunning),
            ("completed", C.stateCompleted),
            ("failed", C.stateFailed),
        ] {
            XCTAssertGreaterThanOrEqual(C.ratio(hex, on: C.canvas), 4.5, name)
        }
    }

    func testContrastMathMatchesWCAGReferencePoints() {
        XCTAssertEqual(C.ratio(0x000000, on: 0xFFFFFF), 21, accuracy: 0.01)
        XCTAssertEqual(C.ratio(0x777777, on: 0xFFFFFF), 4.48, accuracy: 0.02)
    }
}
