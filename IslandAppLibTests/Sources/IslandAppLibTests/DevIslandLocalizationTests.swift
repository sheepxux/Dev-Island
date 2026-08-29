import Foundation
import XCTest
@testable import IslandAppLib
import IslandCore

final class DevIslandLocalizationTests: XCTestCase {
    func testSupportedLanguageResolutionIsConservative() {
        XCTAssertEqual(
            DevIslandLanguage.supportedIdentifier(for: ["zh-Hans-CN", "en-US"]),
            "zh-Hans"
        )
        XCTAssertEqual(
            DevIslandLanguage.supportedIdentifier(for: ["zh_CN"]),
            "zh-Hans"
        )
        XCTAssertEqual(
            DevIslandLanguage.supportedIdentifier(for: ["zh-Hant-TW"]),
            "en"
        )
        XCTAssertEqual(
            DevIslandLanguage.supportedIdentifier(for: ["fr-FR"]),
            "en"
        )
        XCTAssertEqual(
            DevIslandLanguage.supportedIdentifier(for: []),
            "en"
        )
    }

    func testLocalizedStringsResolveFromPackageResources() {
        XCTAssertEqual(
            L10n.string("General", language: .english),
            "General"
        )
        XCTAssertEqual(
            L10n.string("General", language: .simplifiedChinese),
            "通用"
        )
        XCTAssertEqual(
            L10n.string("Protect your\nfocus.", language: .simplifiedChinese),
            "守住你的\n专注状态。"
        )
    }

    func testMissingTranslationFallsBackToSourceKey() {
        XCTAssertEqual(
            L10n.string("dev-island.missing-test-key", language: .simplifiedChinese),
            "dev-island.missing-test-key"
        )
    }

    func testSessionCountAndAccessibilityCopyAreLocalized() {
        XCTAssertEqual(
            L10n.sessionCount(1, language: .english),
            "1 session"
        )
        XCTAssertEqual(
            L10n.sessionCount(20, language: .simplifiedChinese),
            "20 个会话"
        )
        XCTAssertEqual(
            TaskStatusSummary(running: 2, waiting: 1)
                .accessibilityLabel(language: .simplifiedChinese),
            "1 个等待中，2 个运行中"
        )
    }

    func testAgentConnectionSummaryUsesReviewedSingularAndPluralCopy() {
        XCTAssertEqual(
            L10n.agentConnectionSummary(
                connected: 2,
                updateRequired: 1,
                configured: 0,
                language: .english
            ),
            "1 update"
        )
        XCTAssertEqual(
            L10n.agentConnectionSummary(
                connected: 2,
                updateRequired: 4,
                configured: 0,
                language: .simplifiedChinese
            ),
            "4 个待更新"
        )
        XCTAssertEqual(
            L10n.agentConnectionSummary(
                connected: 3,
                updateRequired: 0,
                configured: 2,
                language: .english
            ),
            "3 connected · 2 checks"
        )
        XCTAssertEqual(
            L10n.agentConnectionSummary(
                connected: 3,
                updateRequired: 0,
                configured: 1,
                language: .simplifiedChinese
            ),
            "3 个已连接 · 1 个待确认"
        )
    }

    func testEveryLocalAgentSetupSubtitleHasReviewedSimplifiedChineseCopy() {
        for descriptor in LocalAgentRegistry.all {
            let localized = L10n.string(
                descriptor.settingsSubtitle,
                language: .simplifiedChinese
            )
            XCTAssertFalse(localized.isEmpty, descriptor.source)
            XCTAssertNotEqual(
                localized,
                descriptor.settingsSubtitle,
                "\(descriptor.displayName) must not leak an English setup subtitle into Chinese Settings."
            )
        }
    }

    func testEnglishAndSimplifiedChineseCatalogsHaveMatchingKeys() throws {
        let english = try catalog(localization: "en")
        let simplifiedChinese = try catalog(localization: "zh-Hans")

        XCTAssertEqual(
            Set(english.keys),
            Set(simplifiedChinese.keys),
            "Every shipped source string must have a reviewed Simplified Chinese translation."
        )
    }

    private func catalog(localization: String) throws -> [String: String] {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: nil,
                localization: localization
            )
        )
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: String]
        )
    }
}
