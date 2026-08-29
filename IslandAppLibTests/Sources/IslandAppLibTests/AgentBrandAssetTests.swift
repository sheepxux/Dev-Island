import AppKit
import XCTest
@testable import IslandAppLib

@MainActor
final class AgentBrandAssetTests: XCTestCase {
    override func tearDown() {
        AgentBrand.resourceDirectoryOverride = nil
        super.tearDown()
    }

    func testOfficialOpenCodeMarkLoadsAsAdaptiveTemplateAsset() throws {
        AgentBrand.resourceDirectoryOverride = repositoryRoot
            .appendingPathComponent("IslandApp/Resources", isDirectory: true)

        let image = try XCTUnwrap(AgentBrand.logo(for: "opencode"))
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 40, height: 40))
        XCTAssertEqual(AgentBrand.monogram(for: "opencode"), "O")
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
