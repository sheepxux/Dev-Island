import XCTest
import Foundation
@testable import IslandCore

final class ClaudeHooksInstallerTests: XCTestCase {

    private var tempDir: URL!
    private var settingsURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-hooks-\(UUID().uuidString)")
        settingsURL = tempDir.appendingPathComponent("settings.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func readRoot() throws -> [String: Any] {
        let data = try Data(contentsOf: settingsURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Tests

    func testInstallIntoMissingFile() throws {
        XCTAssertFalse(ClaudeHooksInstaller.isInstalled(settingsURL: settingsURL))
        try ClaudeHooksInstaller.install(settingsURL: settingsURL)
        XCTAssertTrue(ClaudeHooksInstaller.isInstalled(settingsURL: settingsURL))

        let hooks = try XCTUnwrap(try readRoot()["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), Set(ClaudeHooksInstaller.events))
    }

    func testInstallPreservesExistingSettingsAndHooks() throws {
        let existing: [String: Any] = [
            "model": "opus",
            "hooks": [
                "Stop": [
                    ["matcher": "", "hooks": [["type": "command", "command": "terminal-notifier -message done"]]]
                ]
            ],
        ]
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: existing).write(to: settingsURL)

        try ClaudeHooksInstaller.install(settingsURL: settingsURL)

        let root = try readRoot()
        XCTAssertEqual(root["model"] as? String, "opus")
        let stopGroups = try XCTUnwrap((root["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])
        XCTAssertEqual(stopGroups.count, 2)  // user's + ours
        let commands = stopGroups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["command"] as? String }
        XCTAssertTrue(commands.contains { $0.contains("terminal-notifier") })
        XCTAssertTrue(commands.contains { $0.contains("/hooks/claude-code") })
    }

    func testInstallIsIdempotent() throws {
        try ClaudeHooksInstaller.install(settingsURL: settingsURL)
        try ClaudeHooksInstaller.install(settingsURL: settingsURL)

        let hooks = try XCTUnwrap(try readRoot()["hooks"] as? [String: Any])
        for event in ClaudeHooksInstaller.events {
            let groups = try XCTUnwrap(hooks[event] as? [[String: Any]])
            XCTAssertEqual(groups.count, 1, "duplicate group for \(event)")
        }
    }

    func testUninstallRemovesOnlyOurs() throws {
        let existing: [String: Any] = [
            "hooks": [
                "Stop": [
                    ["matcher": "", "hooks": [["type": "command", "command": "terminal-notifier -message done"]]]
                ]
            ]
        ]
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: existing).write(to: settingsURL)

        try ClaudeHooksInstaller.install(settingsURL: settingsURL)
        try ClaudeHooksInstaller.uninstall(settingsURL: settingsURL)

        XCTAssertFalse(ClaudeHooksInstaller.isInstalled(settingsURL: settingsURL))
        let hooks = try XCTUnwrap(try readRoot()["hooks"] as? [String: Any])
        // The user's Stop hook survives; our event keys are gone entirely.
        XCTAssertEqual(Set(hooks.keys), ["Stop"])
        let stopGroups = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        XCTAssertEqual(stopGroups.count, 1)
    }

    func testUninstallFromCleanInstallRemovesHooksKey() throws {
        try ClaudeHooksInstaller.install(settingsURL: settingsURL)
        try ClaudeHooksInstaller.uninstall(settingsURL: settingsURL)
        XCTAssertNil(try readRoot()["hooks"])
    }

    func testHookCommandNeverFailsTheTurn() {
        // The trailing `|| true` is a hard requirement: a dead Dev Island
        // must never surface as a hook error inside Claude Code.
        XCTAssertTrue(ClaudeHooksInstaller.hookCommand().hasSuffix("|| true"))
        XCTAssertTrue(ClaudeHooksInstaller.hookCommand().contains("-m 2"))
    }

    func testPermissionRequestIsSynchronousAndKeepsStdout() {
        let command = LocalHooksInstaller(.claudeCode)
            .hookCommand(for: "PermissionRequest")
        XCTAssertTrue(command.contains("-m 95"))
        XCTAssertFalse(command.contains("@- >/dev/null"))
        XCTAssertTrue(command.hasSuffix("|| true"))
    }

    func testPermissionRequestWritesTimeoutAndStatus() throws {
        try ClaudeHooksInstaller.install(settingsURL: settingsURL)
        let hooks = try XCTUnwrap(try readRoot()["hooks"] as? [String: Any])
        let groups = try XCTUnwrap(hooks["PermissionRequest"] as? [[String: Any]])
        let handlers = try XCTUnwrap(groups.first?["hooks"] as? [[String: Any]])
        let handler = try XCTUnwrap(handlers.first)
        XCTAssertEqual(handler["timeout"] as? Int, 100)
        XCTAssertEqual(handler["statusMessage"] as? String, "Waiting for Dev Island")
    }

    func testInteractiveToolsHookIsMatcherScopedAndSynchronous() throws {
        try ClaudeHooksInstaller.install(settingsURL: settingsURL)
        let hooks = try XCTUnwrap(try readRoot()["hooks"] as? [String: Any])
        let groups = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        let group = try XCTUnwrap(groups.first)
        XCTAssertEqual(group["matcher"] as? String, "AskUserQuestion|ExitPlanMode")

        let handlers = try XCTUnwrap(group["hooks"] as? [[String: Any]])
        let handler = try XCTUnwrap(handlers.first)
        let command = try XCTUnwrap(handler["command"] as? String)
        XCTAssertTrue(command.contains("-m 95"))
        XCTAssertFalse(command.contains("@- >/dev/null"))
        XCTAssertEqual(handler["timeout"] as? Int, 100)
        XCTAssertEqual(handler["statusMessage"] as? String, "Waiting for Dev Island")
    }

    func testUnscopedInteractiveToolsHookIsPresentedAsUpdate() throws {
        try ClaudeHooksInstaller.install(settingsURL: settingsURL)
        var root = try readRoot()
        var hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        var groups = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        groups[0]["matcher"] = ""
        hooks["PreToolUse"] = groups
        root["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: root).write(to: settingsURL)

        let installer = LocalHooksInstaller(.claudeCode)
        XCTAssertFalse(installer.isInstalled(configURL: settingsURL))
        XCTAssertTrue(installer.requiresUpdate(configURL: settingsURL))
    }

    func testPreviousManagedInstallIsPresentedAsAnUpdate() throws {
        try ClaudeHooksInstaller.install(settingsURL: settingsURL)
        var root = try readRoot()
        var hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        hooks.removeValue(forKey: "PermissionRequest")
        root["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: root).write(to: settingsURL)

        let installer = LocalHooksInstaller(.claudeCode)
        XCTAssertFalse(installer.isInstalled(configURL: settingsURL))
        XCTAssertTrue(installer.requiresUpdate(configURL: settingsURL))
    }
}
