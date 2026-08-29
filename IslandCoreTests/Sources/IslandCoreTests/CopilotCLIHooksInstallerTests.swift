import Foundation
import XCTest
@testable import IslandCore

final class CopilotCLIHooksInstallerTests: XCTestCase {
    private var tempDir: URL!
    private var hooksURL: URL!

    private var installer: LocalHooksInstaller { LocalHooksInstaller(.copilotCLI) }

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-copilot-hooks-\(UUID().uuidString)")
        hooksURL = tempDir.appendingPathComponent("dev-island.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func readRoot() throws -> [String: Any] {
        let data = try Data(contentsOf: hooksURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func writeRoot(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: root).write(to: hooksURL)
    }

    func testDescriptorPinsPreviewObserveOnlyContract() {
        let descriptor = LocalAgentDescriptor.copilotCLI

        XCTAssertEqual(descriptor.source, "copilot-cli")
        XCTAssertEqual(descriptor.displayName, "GitHub Copilot CLI")
        XCTAssertEqual(descriptor.releaseStage, .preview)
        XCTAssertEqual(descriptor.configPath, "~/.copilot/hooks/dev-island.json")
        XCTAssertEqual(
            descriptor.hookEvents,
            [
                "SessionStart", "UserPromptSubmit", "Notification",
                "Stop", "ErrorOccurred", "SessionEnd",
            ]
        )
        XCTAssertEqual(descriptor.capabilities.permissionRequests, .observeOnly)
        XCTAssertEqual(descriptor.capabilities.questionRequests, .observeOnly)
        XCTAssertTrue(descriptor.actionHookEvents.isEmpty)
        XCTAssertNil(descriptor.decodeActionRequest)
        XCTAssertNil(descriptor.encodeActionResponse)
        XCTAssertEqual(descriptor.endpointPath, "/hooks/copilot-cli")
        switch descriptor.hookEntryStyle {
        case .flatVersioned:
            break
        default:
            XCTFail("Copilot's dedicated user Hook file is flat and versioned")
        }
    }

    func testPassiveCommandIsBoundedFailOpenAndDiscardsOutput() {
        let command = installer.hookCommand()
        XCTAssertTrue(command.contains("--noproxy 127.0.0.1"))
        XCTAssertTrue(command.contains("-m 2"))
        XCTAssertTrue(command.contains("http://127.0.0.1:7824/hooks/copilot-cli"))
        XCTAssertTrue(command.contains("--data-binary @-"))
        XCTAssertTrue(command.contains(">/dev/null 2>&1"))
        XCTAssertTrue(command.hasSuffix("|| true"))
    }

    func testInstallRendersDedicatedVersionedFlatFile() throws {
        XCTAssertFalse(installer.isInstalled(configURL: hooksURL))
        try installer.install(configURL: hooksURL)
        XCTAssertTrue(installer.isInstalled(configURL: hooksURL))

        let root = try readRoot()
        XCTAssertEqual(root["version"] as? Int, 1)
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), Set(LocalAgentDescriptor.copilotCLI.hookEvents))
        for event in LocalAgentDescriptor.copilotCLI.hookEvents {
            let groups = try XCTUnwrap(hooks[event] as? [[String: Any]])
            XCTAssertEqual(groups.count, 1)
            XCTAssertEqual(groups[0]["command"] as? String, installer.hookCommand())
            XCTAssertNil(groups[0]["hooks"])
            XCTAssertNil(groups[0]["matcher"])
        }
    }

    func testInstallPreservesUserFieldsAndHooksAndIsIdempotent() throws {
        try writeRoot([
            "version": 1,
            "disableAllHooks": false,
            "ownerNote": "keep me",
            "hooks": [
                "SessionStart": [["command": "./user-start.sh"]],
                "preToolUse": [["command": "./user-policy.sh", "matcher": "bash"]],
            ],
        ])

        try installer.install(configURL: hooksURL)
        try installer.install(configURL: hooksURL)

        let root = try readRoot()
        XCTAssertEqual(root["version"] as? Int, 1)
        XCTAssertEqual(root["disableAllHooks"] as? Bool, false)
        XCTAssertEqual(root["ownerNote"] as? String, "keep me")
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertEqual((hooks["SessionStart"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual((hooks["preToolUse"] as? [[String: Any]])?.count, 1)
        for event in LocalAgentDescriptor.copilotCLI.hookEvents {
            let groups = try XCTUnwrap(hooks[event] as? [[String: Any]])
            XCTAssertEqual(
                groups.filter { ($0["command"] as? String)?.contains("/hooks/copilot-cli") == true }.count,
                1
            )
        }
    }

    func testStaleManagedCommandRequiresUpdateAndIsRepaired() throws {
        try writeRoot([
            "version": 1,
            "hooks": [
                "SessionStart": [[
                    "command": "curl http://127.0.0.1:9999/hooks/copilot-cli",
                ]],
            ],
        ])
        XCTAssertTrue(installer.requiresUpdate(configURL: hooksURL))

        try installer.install(configURL: hooksURL)
        XCTAssertTrue(installer.isInstalled(configURL: hooksURL))
        XCTAssertFalse(installer.requiresUpdate(configURL: hooksURL))
    }

    func testUninstallRemovesOnlyManagedCommands() throws {
        try writeRoot([
            "version": 1,
            "ownerNote": "keep me",
            "hooks": [
                "SessionStart": [["command": "./user-start.sh"]],
            ],
        ])
        try installer.install(configURL: hooksURL)
        try installer.uninstall(configURL: hooksURL)

        XCTAssertFalse(installer.hasManagedEntries(configURL: hooksURL))
        let root = try readRoot()
        XCTAssertEqual(root["version"] as? Int, 1)
        XCTAssertEqual(root["ownerNote"] as? String, "keep me")
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), ["SessionStart"])
        XCTAssertEqual((hooks["SessionStart"] as? [[String: Any]])?.count, 1)
    }

    func testInvalidJSONAndWrongVersionRemainByteForByteUnchanged() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let originals = [
            Data(#"{"hooks": [not valid JSON]}"#.utf8),
            try JSONSerialization.data(withJSONObject: [
                "version": 2,
                "hooks": ["SessionStart": [["command": "./user.sh"]]],
            ]),
        ]

        for original in originals {
            try original.write(to: hooksURL)
            XCTAssertThrowsError(try installer.install(configURL: hooksURL))
            XCTAssertEqual(try Data(contentsOf: hooksURL), original)
        }
    }
}
