import XCTest
@testable import IslandAppLib

/// Every product color is authored in OKLCH. These tests pin the conversion
/// against reviewed sRGB values and the rules the palette is built on: one
/// hue across the neutral ramp, lightness that only descends, and state
/// chroma that ranks urgency.
final class OKLCHPaletteTests: XCTestCase {
    func testConversionMatchesReviewedSandValues() {
        let expected: [(String, OKLCH, UInt32)] = [
            ("s0", Sand.s0, 0xFDFCFA),
            ("s25", Sand.s25, 0xFAF7F3),
            ("s50", Sand.s50, 0xF6F2EB),
            ("s100", Sand.s100, 0xEDE9E0),
            ("s150", Sand.s150, 0xE4DFD5),
            ("s200", Sand.s200, 0xD9D4C9),
            ("s300", Sand.s300, 0xBFBAAF),
            ("s400", Sand.s400, 0x9F9B92),
            ("s500", Sand.s500, 0x848078),
            ("s600", Sand.s600, 0x6C6961),
            ("s700", Sand.s700, 0x58554E),
            ("s800", Sand.s800, 0x3A3833),
            ("s850", Sand.s850, 0x2A2926),
            ("s900", Sand.s900, 0x1C1B18),
            ("s950", Sand.s950, 0x121110),
            ("s1000", Sand.s1000, 0x0C0B0A),
        ]
        for (name, color, hex) in expected {
            assertHex(color.hex, equals: hex, name)
        }
    }

    func testConversionMatchesReviewedSignalValues() {
        assertHex(Signal.attentionOnDark.hex, equals: 0xE5B476, "attentionOnDark")
        assertHex(Signal.failureOnDark.hex, equals: 0xE49C90, "failureOnDark")
        assertHex(Signal.successOnDark.hex, equals: 0xA6C8AA, "successOnDark")
        assertHex(Signal.attentionOnLight.hex, equals: 0x7B5D37, "attentionOnLight")
        assertHex(Signal.failureOnLight.hex, equals: 0x9E4336, "failureOnLight")
        assertHex(Signal.successOnLight.hex, equals: 0x4C6D50, "successOnLight")
        assertHex(Signal.attentionFill.hex, equals: 0xEDB163, "attentionFill")
        assertHex(Signal.attentionWash.hex, equals: 0xFDEDDB, "attentionWash")
    }

    func testEveryRampStepSharesTheIconHue() {
        for step in Sand.ramp {
            XCTAssertEqual(step.h, Sand.hue)
        }
    }

    func testRampLightnessOnlyDescends() {
        for (lighter, darker) in zip(Sand.ramp, Sand.ramp.dropFirst()) {
            XCTAssertGreaterThan(lighter.l, darker.l)
        }
    }

    func testOutOfGamutChromaIsClampedWithoutLeavingSRGB() {
        let vivid = OKLCH(0.70, 0.40, 150)
        let (red, green, blue) = vivid.srgb
        for channel in [red, green, blue] {
            XCTAssertGreaterThanOrEqual(channel, 0)
            XCTAssertLessThanOrEqual(channel, 1)
        }
        XCTAssertGreaterThan(green, red, "clamping keeps the hue")
    }

    /// Waiting must be the most vivid mark in the menu bar, a failure next,
    /// a finished response barely tinted, and running work neutral.
    func testStateChromaRanksUrgency() {
        XCTAssertGreaterThan(Signal.attentionOnDark.c, Signal.failureOnDark.c)
        XCTAssertGreaterThan(Signal.failureOnDark.c, Signal.successOnDark.c)
        XCTAssertGreaterThan(Signal.successOnDark.c, Sand.s50.c)
    }

    /// The island's quiet text roles must stay readable on the island ground
    /// in both contrast modes.
    func testIslandTextRolesClearAAOnTheIslandGround() {
        let ground = Sand.s950.hex
        for role in [InterfaceContrastPolicy.Role.secondaryText, .tertiaryText, .idleState] {
            for increased in [false, true] {
                let tone = InterfaceContrastPolicy.tone(for: role, increased: increased)
                let hex = UInt32((tone.red * 255).rounded()) << 16
                    | UInt32((tone.green * 255).rounded()) << 8
                    | UInt32((tone.blue * 255).rounded())
                XCTAssertGreaterThanOrEqual(
                    WindowPaletteContrast.ratio(hex, on: ground),
                    4.5,
                    "\(role) increased=\(increased)"
                )
            }
        }
    }

    func testIslandStateMarksReadOnTheIslandGround() {
        let ground = Sand.s950.hex
        for (name, color) in [
            ("waiting", Signal.attentionOnDark),
            ("failed", Signal.failureOnDark),
            ("completed", Signal.successOnDark),
        ] {
            XCTAssertGreaterThanOrEqual(WindowPaletteContrast.ratio(color.hex, on: ground), 7, name)
        }
    }

    private func assertHex(
        _ actual: UInt32,
        equals expected: UInt32,
        _ name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            String(format: "%06X", actual),
            String(format: "%06X", expected),
            name,
            file: file,
            line: line
        )
    }
}
