import XCTest
@testable import IslandAppLib

final class SettingsAgentGroupOrderTests: XCTestCase {
    func testLocalAgentsStayAheadOfOptionalCloudSetup() {
        XCTAssertEqual(
            SettingsAgentGroup.ordered(
                hasLocalAgents: true,
                showsManus: true
            ),
            [.local, .cloud]
        )
        XCTAssertEqual(
            SettingsAgentGroup.ordered(
                hasLocalAgents: true,
                showsManus: false
            ),
            [.local]
        )
        XCTAssertEqual(
            SettingsAgentGroup.ordered(
                hasLocalAgents: false,
                showsManus: true
            ),
            [.cloud]
        )
        XCTAssertTrue(
            SettingsAgentGroup.ordered(
                hasLocalAgents: false,
                showsManus: false
            ).isEmpty
        )
    }
}
