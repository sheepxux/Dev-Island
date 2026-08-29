import XCTest
import Foundation
@testable import IslandCore

final class GeminiCLIHooksInstallerTests: XCTestCase {

    private var tempDir: URL!
    private var settingsURL: URL!

    private var installer: LocalHooksInstaller {
        LocalHooksInstaller(.geminiCLI)
    }

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-gemini-hooks-\(UUID().uuidString)")
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

    func testDescriptorPinsPassiveObserveOnlyContract() {
        let descriptor = LocalAgentDescriptor.geminiCLI

        XCTAssertEqual(descriptor.source, "gemini-cli")
        XCTAssertEqual(descriptor.configPath, "~/.gemini/settings.json")
        XCTAssertEqual(
            descriptor.hookEvents,
            ["SessionStart", "BeforeAgent", "Notification", "AfterAgent", "SessionEnd"]
        )
        XCTAssertEqual(descriptor.capabilities.permissionRequests, .observeOnly)
        XCTAssertTrue(descriptor.actionHookEvents.isEmpty)
        XCTAssertNil(descriptor.decodeActionRequest)
        XCTAssertNil(descriptor.encodeActionResponse)
        XCTAssertEqual(descriptor.endpointPath, "/hooks/gemini-cli")
        switch descriptor.hookEntryStyle {
        case .nestedWithEmptyMatcher:
            break
        default:
            XCTFail("Gemini CLI requires nested command groups with an empty matcher")
        }
    }

    func testPassiveCommandIsBoundedFailOpenAndDiscardsOutput() {
        let command = installer.hookCommand()
        XCTAssertTrue(command.contains("--noproxy 127.0.0.1"))
        XCTAssertTrue(command.contains("-m 2"))
        XCTAssertTrue(command.contains("http://127.0.0.1:7824/hooks/gemini-cli"))
        XCTAssertTrue(command.contains("--data-binary @-"))
        XCTAssertTrue(command.contains(">/dev/null 2>&1"))
        XCTAssertTrue(command.hasSuffix("|| true"))
    }

    func testInstallRendersNestedGroupsWithEmptyMatcher() throws {
        XCTAssertFalse(installer.isInstalled(configURL: settingsURL))
        try installer.install(configURL: settingsURL)
        XCTAssertTrue(installer.isInstalled(configURL: settingsURL))

        let hooks = try XCTUnwrap(try readRoot()["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), Set(LocalAgentDescriptor.geminiCLI.hookEvents))

        for event in LocalAgentDescriptor.geminiCLI.hookEvents {
            let groups = try XCTUnwrap(hooks[event] as? [[String: Any]])
            XCTAssertEqual(groups.count, 1, "unexpected group count for \(event)")
            XCTAssertEqual(groups[0]["matcher"] as? String, "")
            XCTAssertNil(groups[0]["command"])

            let handlers = try XCTUnwrap(groups[0]["hooks"] as? [[String: Any]])
            XCTAssertEqual(handlers.count, 1)
            XCTAssertEqual(handlers[0]["type"] as? String, "command")
            XCTAssertEqual(handlers[0]["command"] as? String, installer.hookCommand())
            XCTAssertNil(handlers[0]["timeout"], "passive Gemini hooks must not block for UI")
            XCTAssertNil(handlers[0]["statusMessage"])
        }
    }

    func testInstallIsIdempotentAndRepairsStaleManagedCommands() throws {
        try writeRoot([
            "hooks": [
                "SessionStart": [[
                    "matcher": "",
                    "hooks": [[
                        "type": "command",
                        "command": "curl http://127.0.0.1:9999/hooks/gemini-cli",
                    ]],
                ]],
            ],
        ])
        XCTAssertTrue(installer.requiresUpdate(configURL: settingsURL))

        try installer.install(configURL: settingsURL)
        try installer.install(configURL: settingsURL)

        XCTAssertFalse(installer.requiresUpdate(configURL: settingsURL))
        let hooks = try XCTUnwrap(try readRoot()["hooks"] as? [String: Any])
        for event in LocalAgentDescriptor.geminiCLI.hookEvents {
            XCTAssertEqual((hooks[event] as? [[String: Any]])?.count, 1)
        }
    }

    func testInstallPreservesExistingSettingsAndHooks() throws {
        try writeRoot([
            "model": "gemini-2.5-pro",
            "theme": "Default",
            "hooks": [
                "AfterAgent": [
                    ["matcher": "", "hooks": [["type": "command", "command": "./notify.sh"]]],
                ],
                "BeforeTool": [
                    ["matcher": "run_shell_command", "hooks": [["type": "command", "command": "./audit.sh"]]],
                ],
            ],
        ])

        try installer.install(configURL: settingsURL)

        let root = try readRoot()
        XCTAssertEqual(root["model"] as? String, "gemini-2.5-pro")
        XCTAssertEqual(root["theme"] as? String, "Default")
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertEqual((hooks["AfterAgent"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual((hooks["BeforeTool"] as? [[String: Any]])?.count, 1)
    }

    func testUninstallRemovesOnlyDevIslandGroups() throws {
        try writeRoot([
            "model": "gemini-2.5-pro",
            "hooks": [
                "AfterAgent": [
                    ["matcher": "", "hooks": [["type": "command", "command": "./notify.sh"]]],
                ],
                "BeforeTool": [
                    ["matcher": "run_shell_command", "hooks": [["type": "command", "command": "./audit.sh"]]],
                ],
            ],
        ])

        try installer.install(configURL: settingsURL)
        try installer.uninstall(configURL: settingsURL)

        XCTAssertFalse(installer.isInstalled(configURL: settingsURL))
        let root = try readRoot()
        XCTAssertEqual(root["model"] as? String, "gemini-2.5-pro")
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), ["AfterAgent", "BeforeTool"])
        XCTAssertEqual((hooks["AfterAgent"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((hooks["BeforeTool"] as? [[String: Any]])?.count, 1)
    }

    func testInstallRejectsInvalidJSONAndIncompatibleContainersWithoutMutation() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let originals: [Data] = [
            Data(#"{"hooks": [this is not valid JSON]}"#.utf8),
            Data(#"["valid", "json", "wrong", "root"]"#.utf8),
            try JSONSerialization.data(withJSONObject: ["hooks": "not-an-object"]),
            try JSONSerialization.data(withJSONObject: ["hooks": ["AfterAgent": "not-an-array"]]),
        ]

        for original in originals {
            try original.write(to: settingsURL)
            XCTAssertThrowsError(try installer.install(configURL: settingsURL))
            XCTAssertEqual(
                try Data(contentsOf: settingsURL),
                original,
                "failed install must preserve the existing Gemini config byte-for-byte"
            )
        }
    }
}
