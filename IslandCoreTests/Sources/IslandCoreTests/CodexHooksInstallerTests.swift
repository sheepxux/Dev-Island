import XCTest
import Foundation
@testable import IslandCore

final class CodexHooksInstallerTests: XCTestCase {

    private var tempDir: URL!
    private var hooksURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-codex-hooks-\(UUID().uuidString)")
        hooksURL = tempDir.appendingPathComponent("hooks.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func readRoot() throws -> [String: Any] {
        let data = try Data(contentsOf: hooksURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Tests

    func testInstallIntoMissingFile() throws {
        XCTAssertFalse(CodexHooksInstaller.isInstalled(hooksURL: hooksURL))
        try CodexHooksInstaller.install(hooksURL: hooksURL)
        XCTAssertTrue(CodexHooksInstaller.isInstalled(hooksURL: hooksURL))

        let hooks = try XCTUnwrap(try readRoot()["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), Set(CodexHooksInstaller.events))
    }

    func testGroupsOmitMatcherKey() throws {
        // Codex matchers are event-specific filters; omitting the key
        // matches everything, and an empty-string regex is undefined
        // territory we deliberately avoid.
        try CodexHooksInstaller.install(hooksURL: hooksURL)
        let hooks = try XCTUnwrap(try readRoot()["hooks"] as? [String: Any])
        for event in CodexHooksInstaller.events {
            let groups = try XCTUnwrap(hooks[event] as? [[String: Any]])
            XCTAssertNil(groups[0]["matcher"], "unexpected matcher on \(event)")
        }
    }

    func testInstallPreservesExistingHooksAndTopLevelKeys() throws {
        let existing: [String: Any] = [
            "description": "My workspace hooks",
            "hooks": [
                "Stop": [
                    ["hooks": [["type": "command", "command": "python3 ~/notify.py"]]]
                ]
            ],
        ]
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: existing).write(to: hooksURL)

        try CodexHooksInstaller.install(hooksURL: hooksURL)

        let root = try readRoot()
        XCTAssertEqual(root["description"] as? String, "My workspace hooks")
        let stopGroups = try XCTUnwrap((root["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])
        XCTAssertEqual(stopGroups.count, 2)  // user's + ours
    }

    func testInstallIsIdempotent() throws {
        try CodexHooksInstaller.install(hooksURL: hooksURL)
        try CodexHooksInstaller.install(hooksURL: hooksURL)

        let hooks = try XCTUnwrap(try readRoot()["hooks"] as? [String: Any])
        for event in CodexHooksInstaller.events {
            let groups = try XCTUnwrap(hooks[event] as? [[String: Any]])
            XCTAssertEqual(groups.count, 1, "duplicate group for \(event)")
        }
    }

    func testUninstallRemovesOnlyOurs() throws {
        let existing: [String: Any] = [
            "hooks": [
                "Stop": [
                    ["hooks": [["type": "command", "command": "python3 ~/notify.py"]]]
                ]
            ]
        ]
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: existing).write(to: hooksURL)

        try CodexHooksInstaller.install(hooksURL: hooksURL)
        try CodexHooksInstaller.uninstall(hooksURL: hooksURL)

        XCTAssertFalse(CodexHooksInstaller.isInstalled(hooksURL: hooksURL))
        let hooks = try XCTUnwrap(try readRoot()["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), ["Stop"])
    }

    func testHookCommandNeverFailsTheTurn() {
        // Exit 0 with no stdout is Codex's definition of "success, continue";
        // `-m 2` + `|| true` + discarded output guarantee exactly that shape.
        let cmd = CodexHooksInstaller.hookCommand()
        XCTAssertTrue(cmd.hasSuffix("|| true"))
        XCTAssertTrue(cmd.contains("-m 2"))
        XCTAssertTrue(cmd.contains(">/dev/null"))
        XCTAssertTrue(cmd.contains("/hooks/codex"))
    }

    func testDistinctEndpointsFromClaude() {
        XCTAssertNotEqual(
            CodexHooksInstaller.hookCommand(),
            ClaudeHooksInstaller.hookCommand()
        )
    }
}
