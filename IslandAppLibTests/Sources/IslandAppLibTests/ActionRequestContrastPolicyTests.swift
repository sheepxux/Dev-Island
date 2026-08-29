import AppKit
import SwiftUI
import XCTest
@testable import IslandAppLib

final class InterfaceContrastPolicyTests: XCTestCase {
    func testNormalAndIncreasedSystemContrastRemainDistinct() {
        XCTAssertFalse(InterfaceContrastPolicy.isIncreased(.standard))
        XCTAssertTrue(InterfaceContrastPolicy.isIncreased(.increased))

    }

    func testHighContrastPaletteStrengthensEveryQuietRole() throws {
        for role in InterfaceContrastPolicy.Role.allCases {
            let standard = InterfaceContrastPolicy.tone(
                for: role,
                increased: false
            )
            let increased = InterfaceContrastPolicy.tone(
                for: role,
                increased: true
            )

            if role == .hairline || role == .islandBorder {
                XCTAssertGreaterThan(increased.alpha, standard.alpha)
            } else {
                XCTAssertGreaterThan(
                    relativeLuminance(increased),
                    relativeLuminance(standard)
                )
            }
        }
    }

    func testRequiredTextRolesRetainAndIncreaseContrastOnRaisedSurface() {
        let raisedSurface = InterfaceContrastPolicy.Tone(hex: 0x111111)

        for role in [
            InterfaceContrastPolicy.Role.secondaryText,
            .tertiaryText,
        ] {
            let standard = InterfaceContrastPolicy.tone(
                for: role,
                increased: false
            )
            let increased = InterfaceContrastPolicy.tone(
                for: role,
                increased: true
            )
            let standardRatio = contrastRatio(standard, raisedSurface)
            let increasedRatio = contrastRatio(increased, raisedSurface)

            XCTAssertGreaterThanOrEqual(standardRatio, 4.5)
            XCTAssertGreaterThan(increasedRatio, standardRatio)
        }
    }

    func testIncreasedBorderWidthNeverThinsExistingGeometry() {
        XCTAssertEqual(
            InterfaceContrastPolicy.borderWidth(
                increased: false,
                standard: 0.5
            ),
            0.5
        )
        XCTAssertEqual(
            InterfaceContrastPolicy.borderWidth(
                increased: true,
                standard: 0.5
            ),
            1
        )
        XCTAssertEqual(
            InterfaceContrastPolicy.borderWidth(
                increased: true,
                standard: 1.5
            ),
            1.5
        )
    }

    private func contrastRatio(
        _ first: InterfaceContrastPolicy.Tone,
        _ second: InterfaceContrastPolicy.Tone
    ) -> Double {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(
        _ tone: InterfaceContrastPolicy.Tone
    ) -> Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(tone.red)
            + 0.7152 * linear(tone.green)
            + 0.0722 * linear(tone.blue)
    }
}
