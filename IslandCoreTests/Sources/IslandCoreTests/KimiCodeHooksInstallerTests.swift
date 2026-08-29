import Foundation
import XCTest
@testable import IslandCore

final class KimiCodeHooksInstallerTests: XCTestCase {
    private var tempDir: URL!
    private var configURL: URL!

    private var installer: LocalHooksInstaller { LocalHooksInstaller(.kimiCode) }
    private var marker: String { LocalAgentDescriptor.kimiCode.endpointPath }

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-kimi-hooks-\(UUID().uuidString)")
        configURL = tempDir.appendingPathComponent("config.toml")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func write(_ string: String) throws {
        try write(Data(string.utf8))
    }

    private func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try data.write(to: configURL)
    }

    private func readString() throws -> String {
        String(decoding: try Data(contentsOf: configURL), as: UTF8.self)
    }

    func testDescriptorPinsKimiCode038ObserveOnlyContract() {
        let descriptor = LocalAgentDescriptor.kimiCode

        XCTAssertEqual(descriptor.source, "kimi-code")
        XCTAssertEqual(descriptor.displayName, "Kimi Code CLI")
        XCTAssertEqual(descriptor.releaseStage, .preview)
        XCTAssertEqual(descriptor.configPath, "~/.kimi-code/config.toml")
        XCTAssertEqual(
            descriptor.hookEvents,
            [
                "SessionStart", "TurnStarted",
                "PermissionRequest", "PermissionResult",
                "Stop", "StopFailure", "Interrupt", "SessionEnd",
            ]
        )
        XCTAssertEqual(descriptor.capabilities.permissionRequests, .observeOnly)
        XCTAssertTrue(descriptor.actionHookEvents.isEmpty)
        XCTAssertNil(descriptor.decodeActionRequest)
        XCTAssertNil(descriptor.encodeActionResponse)
        XCTAssertEqual(descriptor.endpointPath, "/hooks/kimi-code")
        switch descriptor.hookEntryStyle {
        case .tomlArrayOfTables:
            break
        default:
            XCTFail("Kimi Code requires TOML array-of-tables Hooks")
        }
    }

    func testInstallIntoMissingFileRendersAllPassiveRows() throws {
        XCTAssertFalse(installer.isInstalled(configURL: configURL))
        try installer.install(configURL: configURL)
        XCTAssertTrue(installer.isInstalled(configURL: configURL))

        let text = try readString()
        XCTAssertEqual(text.components(separatedBy: "[[hooks]]").count - 1, 8)
        XCTAssertEqual(text.components(separatedBy: "timeout = 5").count - 1, 8)
        XCTAssertEqual(text.components(separatedBy: "# >>> Dev Island managed Hook \(marker)").count - 1, 8)
        XCTAssertEqual(text.components(separatedBy: "# <<< Dev Island managed Hook \(marker)").count - 1, 8)
        for event in LocalAgentDescriptor.kimiCode.hookEvents {
            XCTAssertTrue(text.contains("event = \"\(event)\""), event)
        }
        let command = installer.hookCommand()
        XCTAssertTrue(command.contains("--noproxy 127.0.0.1"))
        XCTAssertTrue(command.contains("-m 2"))
        XCTAssertTrue(command.contains("http://127.0.0.1:7824/hooks/kimi-code"))
        XCTAssertTrue(command.contains("X-Dev-Island-Tmux-Pane"))
        XCTAssertTrue(command.contains(">/dev/null 2>&1"))
        XCTAssertTrue(command.hasSuffix("|| true"))
    }

    func testInstallAndUninstallPreserveComplexUserTOMLByteForByte() throws {
        let original = Data(#"""
        # User comment and intentional order stay untouched.
        default_model = "kimi-k2"
        enabled = true
        retries = 3
        released = 2026-08-26
        colors = ["gray", "yellow"]

        [providers.moonshot]
        base_url = "https://api.moonshot.cn/v1"
        metadata = { owner = "user", keep = true }

        [[hooks]]
        event = "Stop"
        command = "./user-notify.sh"
        timeout = 7

        """#.utf8)
        try write(original)

        try installer.install(configURL: configURL)
        let installed = try Data(contentsOf: configURL)
        XCTAssertEqual(installed.prefix(original.count), original)
        XCTAssertTrue(installer.isInstalled(configURL: configURL))

        try installer.uninstall(configURL: configURL)
        XCTAssertEqual(try Data(contentsOf: configURL), original)
        XCTAssertFalse(installer.hasManagedEntries(configURL: configURL))
    }

    func testNoTrailingNewlineRoundTripIsExactlyLosslessAndIdempotent() throws {
        let original = Data("model = \"kimi-k2\" # no terminal newline".utf8)
        try write(original)

        try installer.install(configURL: configURL)
        let firstInstall = try Data(contentsOf: configURL)
        XCTAssertTrue(try readString().contains("[owns leading newline]"))

        try installer.install(configURL: configURL)
        XCTAssertEqual(try Data(contentsOf: configURL), firstInstall)

        try installer.uninstall(configURL: configURL)
        XCTAssertEqual(try Data(contentsOf: configURL), original)
    }

    func testMarkerLookingTextInsideMultilineStringsIsNeverEdited() throws {
        let original = Data(#"""
        description = """
        # >>> Dev Island managed Hook /hooks/kimi-code
        [[hooks]]
        command = "not a real table"
        # <<< Dev Island managed Hook /hooks/kimi-code
        """

        literal = '''
        # >>> Dev Island managed Hook /hooks/kimi-code
        # <<< Dev Island managed Hook /hooks/kimi-code
        '''
        """#.utf8)
        try write(original)

        XCTAssertFalse(installer.hasManagedEntries(configURL: configURL))
        try installer.install(configURL: configURL)
        XCTAssertTrue(installer.isInstalled(configURL: configURL))
        try installer.uninstall(configURL: configURL)
        XCTAssertEqual(try Data(contentsOf: configURL), original)
    }

    func testStaleManagedRowsAreUpdatedWithoutDuplicatingBlocks() throws {
        try write("model = \"kimi-k2\"\n")
        try installer.install(configURL: configURL)
        let installed = try readString()
        let stale = installed.replacingOccurrences(of: "-m 2", with: "-m 1")
        try write(stale)

        XCTAssertFalse(installer.isInstalled(configURL: configURL))
        XCTAssertTrue(installer.requiresUpdate(configURL: configURL))

        try installer.install(configURL: configURL)
        XCTAssertTrue(installer.isInstalled(configURL: configURL))
        XCTAssertFalse(installer.requiresUpdate(configURL: configURL))
        let repaired = try readString()
        XCTAssertEqual(repaired.components(separatedBy: "[[hooks]]").count - 1, 8)
        XCTAssertFalse(repaired.contains("-m 1"))
        XCTAssertTrue(repaired.hasPrefix("model = \"kimi-k2\"\n"))
    }

    func testUnknownFieldInsideManagedBlockFailsClosed() throws {
        try installer.install(configURL: configURL)
        let installed = try readString()
        let edited = installed.replacingOccurrences(
            of: "timeout = 5\n# <<< Dev Island managed Hook /hooks/kimi-code",
            with: "timeout = 5\nfuture_field = \"manual edit\"\n# <<< Dev Island managed Hook /hooks/kimi-code",
            options: [],
            range: installed.range(of: "timeout = 5\n# <<< Dev Island managed Hook /hooks/kimi-code")
        )
        XCTAssertNotEqual(edited, installed)
        let original = Data(edited.utf8)
        try write(original)

        XCTAssertTrue(installer.hasManagedEntries(configURL: configURL))
        XCTAssertThrowsError(try installer.install(configURL: configURL))
        XCTAssertEqual(try Data(contentsOf: configURL), original)
        XCTAssertThrowsError(try installer.uninstall(configURL: configURL))
        XCTAssertEqual(try Data(contentsOf: configURL), original)
    }

    func testMalformedIncompleteAndUnwrappedManagedEntriesFailClosed() throws {
        let cases: [Data] = [
            Data("model = [\n# /hooks/kimi-code\n".utf8),
            Data(#"""
            # >>> Dev Island managed Hook /hooks/kimi-code
            [[hooks]]
            event = "SessionStart"
            command = "curl http://127.0.0.1:7824/hooks/kimi-code"
            timeout = 5
            """#.utf8),
            Data(#"""
            model = "kimi-k2"
            [[hooks]]
            event = "SessionStart"
            command = "curl http://127.0.0.1:7824/hooks/kimi-code"
            timeout = 5
            """#.utf8),
        ]

        for original in cases {
            try write(original)
            XCTAssertTrue(installer.hasManagedEntries(configURL: configURL))
            XCTAssertThrowsError(try installer.install(configURL: configURL))
            XCTAssertEqual(try Data(contentsOf: configURL), original)
            XCTAssertThrowsError(try installer.uninstall(configURL: configURL))
            XCTAssertEqual(try Data(contentsOf: configURL), original)
        }
    }

    func testUninstallRemovesOnlyDevIslandBlocks() throws {
        let original = Data(#"""
        model = "kimi-k2"

        [[hooks]]
        event = "SessionEnd"
        matcher = "user-owned"
        command = "./archive.sh"
        timeout = 12

        """#.utf8)
        try write(original)
        try installer.install(configURL: configURL)
        try installer.uninstall(configURL: configURL)

        XCTAssertEqual(try Data(contentsOf: configURL), original)
        XCTAssertFalse(installer.hasManagedEntries(configURL: configURL))
    }
}
