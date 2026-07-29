import XCTest
import Foundation
@testable import IslandCore

final class CursorHooksInstallerTests: XCTestCase {

    private var tempDir: URL!
    private var hooksURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-cursor-hooks-\(UUID().uuidString)")
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
        XCTAssertFalse(CursorHooksInstaller.isInstalled(hooksURL: hooksURL))
        try CursorHooksInstaller.install(hooksURL: hooksURL)
        XCTAssertTrue(CursorHooksInstaller.isInstalled(hooksURL: hooksURL))

        let root = try readRoot()
        XCTAssertEqual(root["version"] as? Int, 1)  // Cursor requires it
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), Set(CursorHooksInstaller.events))
    }

    func testEntriesAreFlat() throws {
        // Cursor entries carry `command` directly — no nested `hooks`
        // array, no matcher wrapper.
        try CursorHooksInstaller.install(hooksURL: hooksURL)
        let hooks = try XCTUnwrap(try readRoot()["hooks"] as? [String: Any])
        for event in CursorHooksInstaller.events {
            let entries = try XCTUnwrap(hooks[event] as? [[String: Any]])
            XCTAssertNotNil(entries[0]["command"] as? String, "flat command missing on \(event)")
            XCTAssertNil(entries[0]["hooks"], "unexpected nested hooks on \(event)")
            XCTAssertNil(entries[0]["matcher"], "unexpected matcher on \(event)")
        }
    }

    func testInstallPreservesExistingHooksAndVersion() throws {
        let existing: [String: Any] = [
            "version": 1,
            "hooks": [
                "afterFileEdit": [["command": "./hooks/format.sh"]]
            ],
        ]
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: existing).write(to: hooksURL)

        try CursorHooksInstaller.install(hooksURL: hooksURL)

        let root = try readRoot()
        XCTAssertEqual(root["version"] as? Int, 1)
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        let formatEntries = try XCTUnwrap(hooks["afterFileEdit"] as? [[String: Any]])
        XCTAssertEqual(formatEntries.count, 1)
        XCTAssertEqual(formatEntries[0]["command"] as? String, "./hooks/format.sh")
    }

    func testUserEntryOnSubscribedEventSurvives() throws {
        let existing: [String: Any] = [
            "version": 1,
            "hooks": [
                "stop": [["command": "./hooks/notify.sh"]]
            ],
        ]
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: existing).write(to: hooksURL)

        try CursorHooksInstaller.install(hooksURL: hooksURL)
        try CursorHooksInstaller.uninstall(hooksURL: hooksURL)

        XCTAssertFalse(CursorHooksInstaller.isInstalled(hooksURL: hooksURL))
        let hooks = try XCTUnwrap(try readRoot()["hooks"] as? [String: Any])
        let stopEntries = try XCTUnwrap(hooks["stop"] as? [[String: Any]])
        XCTAssertEqual(stopEntries.count, 1)
        XCTAssertEqual(stopEntries[0]["command"] as? String, "./hooks/notify.sh")
    }

    func testInstallIsIdempotent() throws {
        try CursorHooksInstaller.install(hooksURL: hooksURL)
        try CursorHooksInstaller.install(hooksURL: hooksURL)

        let hooks = try XCTUnwrap(try readRoot()["hooks"] as? [String: Any])
        for event in CursorHooksInstaller.events {
            let entries = try XCTUnwrap(hooks[event] as? [[String: Any]])
            XCTAssertEqual(entries.count, 1, "duplicate entry for \(event)")
        }
    }

    func testHookCommandNeverBlocksATurn() {
        let cmd = CursorHooksInstaller.hookCommand()
        XCTAssertTrue(cmd.hasSuffix("|| true"))
        XCTAssertTrue(cmd.contains("-m 2"))
        XCTAssertTrue(cmd.contains(">/dev/null"))
        XCTAssertTrue(cmd.contains("/hooks/cursor"))
    }

    func testSubscribesOnlyToFireAndForgetEvents() {
        // Gating hooks (beforeShellExecution, preToolUse, …) expect a JSON
        // permission answer; our silent curl must never be wired to one.
        let gating = ["beforeShellExecution", "beforeMCPExecution",
                      "preToolUse", "beforeReadFile", "subagentStart"]
        for event in gating {
            XCTAssertFalse(CursorHooksInstaller.events.contains(event))
        }
    }

    func testDistinctEndpointsAcrossConnectors() {
        XCTAssertNotEqual(CursorHooksInstaller.hookCommand(), ClaudeHooksInstaller.hookCommand())
        XCTAssertNotEqual(CursorHooksInstaller.hookCommand(), CodexHooksInstaller.hookCommand())
    }
}
