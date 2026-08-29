import Foundation
import XCTest
@testable import IslandCore

final class QwenCodeHooksInstallerTests: XCTestCase {
    private var tempDir: URL!
    private var settingsURL: URL!

    private var installer: LocalHooksInstaller { LocalHooksInstaller(.qwenCode) }

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-qwen-hooks-\(UUID().uuidString)")
        settingsURL = tempDir.appendingPathComponent("settings.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func readRoot() throws -> [String: Any] {
        let data = try Data(contentsOf: settingsURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func writeRoot(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: root).write(to: settingsURL)
    }

    func testDescriptorPinsPreviewBidirectionalContract() {
        let descriptor = LocalAgentDescriptor.qwenCode

        XCTAssertEqual(descriptor.source, "qwen-code")
        XCTAssertEqual(descriptor.displayName, "Qwen Code")
        XCTAssertEqual(descriptor.releaseStage, .preview)
        XCTAssertEqual(descriptor.configPath, "~/.qwen/settings.json")
        XCTAssertEqual(
            descriptor.hookEvents,
            [
                "SessionStart", "UserPromptSubmit", "PermissionRequest", "Notification",
                "Stop", "StopFailure", "SessionEnd",
            ]
        )
        XCTAssertEqual(descriptor.capabilities.permissionRequests, .bidirectional)
        XCTAssertEqual(descriptor.actionHookEvents, ["PermissionRequest"])
        XCTAssertNotNil(descriptor.decodeActionRequest)
        XCTAssertNotNil(descriptor.encodeActionResponse)
        XCTAssertEqual(descriptor.endpointPath, "/hooks/qwen-code")
        switch descriptor.hookEntryStyle {
        case .nestedWithEmptyMatcher:
            break
        default:
            XCTFail("Qwen Code requires nested command groups")
        }
    }

    func testPassiveAndActionCommandsHaveDifferentBlockingBehavior() {
        let passive = installer.hookCommand(for: "SessionStart")
        XCTAssertTrue(passive.contains("-m 2"))
        XCTAssertTrue(passive.contains(">/dev/null 2>&1"))
        XCTAssertTrue(passive.hasSuffix("|| true"))

        let action = installer.hookCommand(for: "PermissionRequest")
        XCTAssertTrue(action.contains("-m 95"))
        XCTAssertTrue(action.contains("http://127.0.0.1:7824/hooks/qwen-code"))
        XCTAssertFalse(action.contains(">/dev/null 2>&1"))
        XCTAssertTrue(action.contains("2>/dev/null"), "stderr stays quiet while stdout carries JSON")
        XCTAssertTrue(action.hasSuffix("|| true"))
    }

    func testInstallUsesQwenMillisecondTimeoutAndPreservesOtherSettings() throws {
        try writeRoot([
            "model": "qwen3-coder-plus",
            "disableAllHooks": false,
            "hooks": [
                "Stop": [[
                    "hooks": [["type": "command", "command": "./user-finish.sh"]],
                ]],
                "PreToolUse": [[
                    "matcher": "write_file",
                    "hooks": [["type": "command", "command": "./audit.sh"]],
                ]],
            ],
        ])

        try installer.install(configURL: settingsURL)
        XCTAssertTrue(installer.isInstalled(configURL: settingsURL))

        let root = try readRoot()
        XCTAssertEqual(root["model"] as? String, "qwen3-coder-plus")
        XCTAssertEqual(root["disableAllHooks"] as? Bool, false)
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertEqual((hooks["Stop"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual((hooks["PreToolUse"] as? [[String: Any]])?.count, 1)

        for event in LocalAgentDescriptor.qwenCode.hookEvents {
            let groups = try XCTUnwrap(hooks[event] as? [[String: Any]])
            let managed = try XCTUnwrap(groups.first { group in
                let handlers = group["hooks"] as? [[String: Any]]
                return handlers?.contains { ($0["command"] as? String)?.contains("/hooks/qwen-code") == true } == true
            })
            XCTAssertEqual(managed["matcher"] as? String, "")
            let handler = try XCTUnwrap((managed["hooks"] as? [[String: Any]])?.first)
            if event == "PermissionRequest" {
                XCTAssertEqual(handler["timeout"] as? Int, 100_000)
                XCTAssertEqual(handler["statusMessage"] as? String, "Waiting for Dev Island")
            } else {
                XCTAssertNil(handler["timeout"])
                XCTAssertNil(handler["statusMessage"])
            }
        }
    }

    func testInstallIsIdempotentAndRepairsStaleManagedCommand() throws {
        try writeRoot([
            "hooks": [
                "PermissionRequest": [[
                    "matcher": "",
                    "hooks": [[
                        "type": "command",
                        "command": "curl http://127.0.0.1:9999/hooks/qwen-code",
                    ]],
                ]],
            ],
        ])
        XCTAssertTrue(installer.requiresUpdate(configURL: settingsURL))

        try installer.install(configURL: settingsURL)
        try installer.install(configURL: settingsURL)

        XCTAssertFalse(installer.requiresUpdate(configURL: settingsURL))
        let hooks = try XCTUnwrap(try readRoot()["hooks"] as? [String: Any])
        for event in LocalAgentDescriptor.qwenCode.hookEvents {
            XCTAssertEqual((hooks[event] as? [[String: Any]])?.count, 1)
        }
    }

    func testWrongLegacyTimeoutIsReportedAsUpdateRequired() throws {
        try installer.install(configURL: settingsURL)
        var root = try readRoot()
        var hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        var groups = try XCTUnwrap(hooks["PermissionRequest"] as? [[String: Any]])
        var group = try XCTUnwrap(groups.first)
        var handlers = try XCTUnwrap(group["hooks"] as? [[String: Any]])
        handlers[0]["timeout"] = 100
        group["hooks"] = handlers
        groups[0] = group
        hooks["PermissionRequest"] = groups
        root["hooks"] = hooks
        try writeRoot(root)

        XCTAssertFalse(installer.isInstalled(configURL: settingsURL))
        XCTAssertTrue(installer.requiresUpdate(configURL: settingsURL))

        try installer.install(configURL: settingsURL)
        XCTAssertTrue(installer.isInstalled(configURL: settingsURL))
    }

    func testUninstallRemovesOnlyManagedHandlers() throws {
        try writeRoot([
            "theme": "dark",
            "hooks": [
                "Stop": [[
                    "matcher": "",
                    "hooks": [["type": "command", "command": "./user-finish.sh"]],
                ]],
            ],
        ])
        try installer.install(configURL: settingsURL)
        try installer.uninstall(configURL: settingsURL)

        XCTAssertFalse(installer.hasManagedEntries(configURL: settingsURL))
        let root = try readRoot()
        XCTAssertEqual(root["theme"] as? String, "dark")
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), ["Stop"])
        XCTAssertEqual((hooks["Stop"] as? [[String: Any]])?.count, 1)
    }

    func testInvalidExistingConfigRemainsByteForByteUnchanged() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let original = Data(#"{"hooks":{"PermissionRequest":"not-an-array"}}"#.utf8)
        try original.write(to: settingsURL)

        XCTAssertThrowsError(try installer.install(configURL: settingsURL))
        XCTAssertEqual(try Data(contentsOf: settingsURL), original)
    }
}
