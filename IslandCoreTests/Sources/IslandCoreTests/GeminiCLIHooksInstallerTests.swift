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

    func testDescriptorPinsVerifiedHookContract() {
        let descriptor = LocalAgentDescriptor.geminiCLI

        XCTAssertEqual(descriptor.source, "gemini-cli")
        XCTAssertEqual(descriptor.configPath, "~/.gemini/settings.json")
        XCTAssertEqual(
            descriptor.hookEvents,
            ["SessionStart", "BeforeAgent", "Notification", "AfterAgent", "SessionEnd"]
        )
        switch descriptor.hookEntryStyle {
        case .nestedWithEmptyMatcher:
            break
        default:
            XCTFail("Gemini CLI hooks require nested command groups with an empty matcher")
        }
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
            XCTAssertNil(groups[0]["command"], "Gemini commands belong in the nested hooks array")

            let commands = try XCTUnwrap(groups[0]["hooks"] as? [[String: Any]])
            XCTAssertEqual(commands.count, 1)
            XCTAssertEqual(commands[0]["type"] as? String, "command")
            XCTAssertTrue(
                (commands[0]["command"] as? String)?.contains("/hooks/gemini-cli") == true,
                "Gemini command must target its dedicated endpoint"
            )
        }
    }

    func testInstallIsIdempotent() throws {
        try installer.install(configURL: settingsURL)
        try installer.install(configURL: settingsURL)

        let hooks = try XCTUnwrap(try readRoot()["hooks"] as? [String: Any])
        for event in LocalAgentDescriptor.geminiCLI.hookEvents {
            let groups = try XCTUnwrap(hooks[event] as? [[String: Any]])
            XCTAssertEqual(groups.count, 1, "duplicate Gemini group for \(event)")
        }
    }

    func testInstallRejectsInvalidJSONWithoutChangingFile() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let original = Data(#"{"hooks": [this is not valid JSON]}"#.utf8)
        try original.write(to: settingsURL)

        XCTAssertThrowsError(try installer.install(configURL: settingsURL))
        XCTAssertEqual(
            try Data(contentsOf: settingsURL),
            original,
            "a failed install must preserve the malformed file byte-for-byte"
        )
    }

    func testInstallRejectsMalformedHookContainersWithoutChangingFile() throws {
        let cases: [(name: String, root: [String: Any])] = [
            (
                "top-level hooks is not an object",
                ["model": "gemini-2.5-pro", "hooks": "not-an-object"]
            ),
            (
                "subscribed event is not an array",
                [
                    "model": "gemini-2.5-pro",
                    "hooks": ["AfterAgent": ["command": "./notify.sh"]],
                ]
            ),
        ]

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        for testCase in cases {
            let original = try JSONSerialization.data(withJSONObject: testCase.root)
            try original.write(to: settingsURL)

            XCTAssertThrowsError(
                try installer.install(configURL: settingsURL),
                testCase.name
            )
            XCTAssertEqual(
                try Data(contentsOf: settingsURL),
                original,
                "\(testCase.name) must be preserved byte-for-byte"
            )
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
        let afterAgent = try XCTUnwrap(hooks["AfterAgent"] as? [[String: Any]])
        XCTAssertEqual(afterAgent.count, 2, "the user's subscribed-event hook must survive")
        let beforeTool = try XCTUnwrap(hooks["BeforeTool"] as? [[String: Any]])
        XCTAssertEqual(beforeTool.count, 1, "unrelated Gemini hook events must survive")
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
}
