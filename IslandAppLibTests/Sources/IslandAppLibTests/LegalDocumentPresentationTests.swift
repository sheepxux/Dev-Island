import Darwin
import Foundation
import XCTest
@testable import IslandAppLib

final class LegalDocumentPresentationTests: XCTestCase {
    func testEnglishAndChineseSectionsUseExactReviewedTitlesAndDates() throws {
        let english = try LegalDocumentParser.decode(
            fixtureData,
            kind: .privacy,
            language: .english
        )
        XCTAssertEqual(english.title, "Dev Island Privacy Notice")
        XCTAssertEqual(english.lastUpdated, "Last updated: August 29, 2026")
        XCTAssertEqual(
            english.blocks.first,
            .callout("Engineering-verified draft for owner and legal review.")
        )

        let chinese = try LegalDocumentParser.decode(
            fixtureData,
            kind: .privacy,
            language: .simplifiedChinese
        )
        XCTAssertEqual(chinese.title, "Dev Island 隐私说明")
        XCTAssertEqual(chinese.lastUpdated, "最后更新：2026 年 8 月 29 日")
        XCTAssertEqual(
            chinese.blocks.first,
            .callout("这是供产品负责人和法律专业人士审阅的草案。")
        )
    }

    func testBlockParserPreservesHeadingsBulletsAndWrappedLanguageRhythm() throws {
        let english = try LegalDocumentParser.decode(
            fixtureData,
            kind: .privacy,
            language: .english
        )
        XCTAssertTrue(english.blocks.contains(.heading(level: 2, text: "1. Local data")))
        XCTAssertTrue(english.blocks.contains(.bullet("agent and session identifiers;")))
        XCTAssertTrue(english.blocks.contains(.paragraph(
            "Dev Island processes bounded state on this Mac only."
        )))

        let chinese = try LegalDocumentParser.decode(
            fixtureData,
            kind: .privacy,
            language: .simplifiedChinese
        )
        XCTAssertTrue(chinese.blocks.contains(.paragraph(
            "Dev Island 仅在这台 Mac 上处理有界状态。"
        )))
    }

    func testMalformedBilingualStructureFailsClosed() {
        let duplicateSeparator = fixtureText.replacingOccurrences(
            of: "\n---\n\n",
            with: "\n---\n\n---\n\n"
        )
        XCTAssertThrowsError(try LegalDocumentParser.decode(
            Data(duplicateSeparator.utf8),
            kind: .privacy,
            language: .english
        )) { error in
            XCTAssertEqual(error as? LegalDocumentError, .invalidStructure)
        }

        let wrongTitle = fixtureText.replacingOccurrences(
            of: "# Dev Island 隐私说明",
            with: "# Unreviewed"
        )
        XCTAssertThrowsError(try LegalDocumentParser.decode(
            Data(wrongTitle.utf8),
            kind: .privacy,
            language: .simplifiedChinese
        )) { error in
            XCTAssertEqual(error as? LegalDocumentError, .invalidStructure)
        }
    }

    func testByteAndEncodingBoundsFailBeforePresentation() {
        XCTAssertThrowsError(try LegalDocumentParser.decode(
            Data(repeating: 0x61, count: LegalDocumentParser.maximumDocumentBytes + 1),
            kind: .privacy,
            language: .english
        )) { error in
            XCTAssertEqual(error as? LegalDocumentError, .unsafeResource)
        }

        XCTAssertThrowsError(try LegalDocumentParser.decode(
            Data([0xFF, 0xFE]),
            kind: .privacy,
            language: .english
        )) { error in
            XCTAssertEqual(error as? LegalDocumentError, .invalidEncoding)
        }
    }

    func testDescriptorReaderAcceptsOnlyBoundedSingleLinkRegularFile() throws {
        try withTemporaryDirectory { directory in
            let resource = directory.appendingPathComponent("document.md")
            let expected = Data(repeating: 0x61, count: 2 * 1024)
            try expected.write(to: resource)

            XCTAssertEqual(
                try DescriptorBackedResourceReader.read(at: resource),
                expected
            )
        }
    }

    func testDescriptorReaderRejectsSymbolicLinks() throws {
        try withTemporaryDirectory { directory in
            let target = directory.appendingPathComponent("target.md")
            let symbolicLink = directory.appendingPathComponent("document.md")
            try Data(repeating: 0x61, count: 2 * 1024).write(to: target)
            try FileManager.default.createSymbolicLink(
                at: symbolicLink,
                withDestinationURL: target
            )

            assertUnsafeResource {
                try DescriptorBackedResourceReader.read(at: symbolicLink)
            }
        }
    }

    func testDescriptorReaderRejectsHardLinks() throws {
        try withTemporaryDirectory { directory in
            let resource = directory.appendingPathComponent("document.md")
            let secondLink = directory.appendingPathComponent("second-link.md")
            try Data(repeating: 0x61, count: 2 * 1024).write(to: resource)
            try FileManager.default.linkItem(at: resource, to: secondLink)

            assertUnsafeResource {
                try DescriptorBackedResourceReader.read(at: resource)
            }
        }
    }

    func testDescriptorReaderRejectsGroupOrWorldWritableResources() throws {
        try withTemporaryDirectory { directory in
            let resource = directory.appendingPathComponent("document.md")
            try Data(repeating: 0x61, count: 2 * 1024).write(to: resource)
            let result = resource.withUnsafeFileSystemRepresentation { path in
                path.map { Darwin.chmod($0, 0o666) } ?? -1
            }
            XCTAssertEqual(result, 0)

            assertUnsafeResource {
                try DescriptorBackedResourceReader.read(at: resource)
            }
        }
    }

    func testDescriptorReaderRejectsFilesOutsideOneTo512KiBBoundary() throws {
        try withTemporaryDirectory { directory in
            let undersized = directory.appendingPathComponent("undersized.md")
            let oversized = directory.appendingPathComponent("oversized.md")
            try Data(
                repeating: 0x61,
                count: DescriptorBackedResourceReader.minimumDocumentBytes - 1
            ).write(to: undersized)
            try Data(
                repeating: 0x61,
                count: LegalDocumentParser.maximumDocumentBytes + 1
            ).write(to: oversized)

            assertUnsafeResource {
                try DescriptorBackedResourceReader.read(at: undersized)
            }
            assertUnsafeResource {
                try DescriptorBackedResourceReader.read(at: oversized)
            }
        }
    }

    func testDescriptorReaderRejectsPathReplacementDuringRead() throws {
        try withTemporaryDirectory { directory in
            let resource = directory.appendingPathComponent("document.md")
            let replacement = directory.appendingPathComponent("replacement.md")
            try Data(repeating: 0x61, count: 2 * 1024).write(to: resource)
            try Data(repeating: 0x62, count: 2 * 1024).write(to: replacement)
            var replacementResult: Int32 = -1

            assertUnsafeResource {
                try DescriptorBackedResourceReader.read(
                    at: resource,
                    afterInitialValidation: {
                        replacementResult = replacement.withUnsafeFileSystemRepresentation { source in
                            resource.withUnsafeFileSystemRepresentation { destination in
                                guard let source, let destination else { return -1 }
                                return Darwin.rename(source, destination)
                            }
                        }
                    }
                )
            }
            XCTAssertEqual(replacementResult, 0)
        }
    }

    func testOnlyReviewedMailAndProductLinksCanLeaveTheSheet() throws {
        XCTAssertTrue(LegalDocumentLinkPolicy.allows(
            try XCTUnwrap(URL(string: "mailto:alsoaxu@gmail.com"))
        ))
        XCTAssertTrue(LegalDocumentLinkPolicy.allows(
            try XCTUnwrap(URL(string: "https://devisland.app/privacy"))
        ))
        XCTAssertFalse(LegalDocumentLinkPolicy.allows(
            try XCTUnwrap(URL(string: "mailto:other@example.com"))
        ))
        XCTAssertFalse(LegalDocumentLinkPolicy.allows(
            try XCTUnwrap(URL(string: "https://example.com/privacy"))
        ))
        XCTAssertFalse(LegalDocumentLinkPolicy.allows(
            try XCTUnwrap(URL(string: "file:///tmp/PRIVACY.md"))
        ))
    }

    func testInlineMarkdownStripsUnreviewedDestinations() {
        let rendered = LegalDocumentLinkPolicy.attributedText(
            "[Support](mailto:alsoaxu@gmail.com) [License](LICENSE) [Other](https://example.com)"
        )
        let links = rendered.runs.compactMap(\.link)
        XCTAssertEqual(links.map(\.absoluteString), ["mailto:alsoaxu@gmail.com"])
        XCTAssertTrue(String(rendered.characters).contains("License"))
        XCTAssertTrue(String(rendered.characters).contains("Other"))
    }

    private var fixtureData: Data { Data(fixtureText.utf8) }

    private func assertUnsafeResource<T>(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? LegalDocumentError,
                .unsafeResource,
                file: file,
                line: line
            )
        }
    }

    private func withTemporaryDirectory(
        _ operation: (URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DevIsland-LegalReader-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try operation(directory)
    }

    private var fixtureText: String {
        """
        # Dev Island Privacy Notice

        > Engineering-verified draft for owner and legal review.

        Last updated: August 29, 2026

        ## 1. Local data

        - agent and session
          identifiers;

        Dev Island processes bounded state
        on this Mac only.

        ---

        # Dev Island 隐私说明

        > 这是供产品负责人和法律专业人士审阅的草案。

        最后更新：2026 年 8 月 29 日

        ## 1. 本机数据

        Dev Island 仅在这台 Mac 上处理
        有界状态。
        """
    }
}
