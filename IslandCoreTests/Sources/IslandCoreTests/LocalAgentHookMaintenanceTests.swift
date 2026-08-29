import Foundation
import XCTest
@testable import IslandCore

final class LocalAgentHookMaintenanceTests: XCTestCase {
    private enum InjectedFailure: Error { case stop }

    func testBulkRemovalPreservesUserConfigAndFilePermissions() throws {
        let directory = temporaryDirectory("success")
        defer { try? FileManager.default.removeItem(at: directory) }
        let descriptors: [LocalAgentDescriptor] = [.claudeCode, .codex, .cursor]
        let urls = urlsForDescriptors(descriptors, in: directory)

        for descriptor in descriptors {
            let url = try XCTUnwrap(urls[descriptor.source])
            try LocalHooksInstaller(descriptor).install(configURL: url)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o640],
                ofItemAtPath: url.path
            )
        }
        // Add a user-owned field after installation to prove bulk removal is
        // surgical rather than replacing the root with a generated template.
        let claudeURL = try XCTUnwrap(urls["claude-code"])
        var claudeRoot = try readRoot(claudeURL)
        claudeRoot["theme"] = "user-owned"
        try writeRoot(claudeRoot, to: claudeURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: claudeURL.path)

        let result = try LocalAgentHookMaintenance.removeAllManagedHooks(
            descriptors: descriptors,
            configURLsBySource: urls
        )

        XCTAssertEqual(result.removedSources, ["claude-code", "codex", "cursor"])
        XCTAssertFalse(result.wasNoOp)
        for descriptor in descriptors {
            let url = try XCTUnwrap(urls[descriptor.source])
            XCTAssertFalse(LocalHooksInstaller(descriptor).hasManagedEntries(configURL: url))
            let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
            XCTAssertEqual(permissions, 0o640)
        }
        XCTAssertEqual(try readRoot(claudeURL)["theme"] as? String, "user-owned")
    }

    func testBulkRemovalAcrossDescriptorsSharingOneFileComposesEdits() throws {
        let directory = temporaryDirectory("shared")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("shared.json")
        let descriptors: [LocalAgentDescriptor] = [.claudeCode, .codex]
        let urls = ["claude-code": url, "codex": url]

        try LocalHooksInstaller(.claudeCode).install(configURL: url)
        try LocalHooksInstaller(.codex).install(configURL: url)
        XCTAssertTrue(LocalHooksInstaller(.claudeCode).hasManagedEntries(configURL: url))
        XCTAssertTrue(LocalHooksInstaller(.codex).hasManagedEntries(configURL: url))

        let result = try LocalAgentHookMaintenance.removeAllManagedHooks(
            descriptors: descriptors,
            configURLsBySource: urls
        )
        XCTAssertEqual(result.removedSources, ["claude-code", "codex"])
        XCTAssertFalse(LocalHooksInstaller(.claudeCode).hasManagedEntries(configURL: url))
        XCTAssertFalse(LocalHooksInstaller(.codex).hasManagedEntries(configURL: url))
    }

    func testBulkRemovalComposesJSONAndTOMLWithoutReformattingUserConfig() throws {
        let directory = temporaryDirectory("json-toml")
        defer { try? FileManager.default.removeItem(at: directory) }
        let claudeURL = directory.appendingPathComponent("claude.json")
        let kimiURL = directory.appendingPathComponent("kimi.toml")
        let descriptors: [LocalAgentDescriptor] = [.claudeCode, .kimiCode]
        let urls = ["claude-code": claudeURL, "kimi-code": kimiURL]
        let kimiOriginal = Data(#"""
        # Preserve this exact Kimi Code configuration.
        model = "kimi-k2"

        [[hooks]]
        event = "Stop"
        command = "./user-notify.sh"
        timeout = 8

        """#.utf8)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try kimiOriginal.write(to: kimiURL)
        try LocalHooksInstaller(.claudeCode).install(configURL: claudeURL)
        try LocalHooksInstaller(.kimiCode).install(configURL: kimiURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: kimiURL.path)

        let result = try LocalAgentHookMaintenance.removeAllManagedHooks(
            descriptors: descriptors,
            configURLsBySource: urls
        )

        XCTAssertEqual(result.removedSources, ["claude-code", "kimi-code"])
        XCTAssertFalse(LocalHooksInstaller(.claudeCode).hasManagedEntries(configURL: claudeURL))
        XCTAssertFalse(LocalHooksInstaller(.kimiCode).hasManagedEntries(configURL: kimiURL))
        XCTAssertEqual(try Data(contentsOf: kimiURL), kimiOriginal)
        let permissions = try FileManager.default.attributesOfItem(atPath: kimiURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o640)
    }

    func testMalformedTOMLStopsDisconnectAllBeforeAnyJSONWrite() throws {
        let directory = temporaryDirectory("toml-prepare-failure")
        defer { try? FileManager.default.removeItem(at: directory) }
        let claudeURL = directory.appendingPathComponent("claude.json")
        let kimiURL = directory.appendingPathComponent("kimi.toml")
        let descriptors: [LocalAgentDescriptor] = [.claudeCode, .kimiCode]
        let urls = ["claude-code": claudeURL, "kimi-code": kimiURL]

        try LocalHooksInstaller(.claudeCode).install(configURL: claudeURL)
        let claudeOriginal = try Data(contentsOf: claudeURL)
        let malformed = Data(#"""
        # >>> Dev Island managed Hook /hooks/kimi-code
        [[hooks]]
        event = "SessionStart"
        command = "curl http://127.0.0.1:7824/hooks/kimi-code"
        """#.utf8)
        try malformed.write(to: kimiURL)

        XCTAssertThrowsError(try LocalAgentHookMaintenance.removeAllManagedHooks(
            descriptors: descriptors,
            configURLsBySource: urls
        )) { error in
            XCTAssertEqual(
                error as? LocalAgentHookMaintenanceError,
                .couldNotPrepare(source: "kimi-code")
            )
        }
        XCTAssertEqual(try Data(contentsOf: claudeURL), claudeOriginal)
        XCTAssertEqual(try Data(contentsOf: kimiURL), malformed)
    }

    func testTOMLWriteFailureRollsBackEarlierJSONByteForByte() throws {
        let directory = temporaryDirectory("toml-rollback")
        defer { try? FileManager.default.removeItem(at: directory) }
        let claudeURL = directory.appendingPathComponent("claude.json")
        let kimiURL = directory.appendingPathComponent("kimi.toml")
        let descriptors: [LocalAgentDescriptor] = [.claudeCode, .kimiCode]
        let urls = ["claude-code": claudeURL, "kimi-code": kimiURL]

        try LocalHooksInstaller(.claudeCode).install(configURL: claudeURL)
        try LocalHooksInstaller(.kimiCode).install(configURL: kimiURL)
        let claudeOriginal = try Data(contentsOf: claudeURL)
        let kimiOriginal = try Data(contentsOf: kimiURL)

        XCTAssertThrowsError(try LocalAgentHookMaintenance.removeAllManagedHooks(
            descriptors: descriptors,
            configURLsBySource: urls,
            beforeWrite: { _, _, index in
                if index == 1 { throw InjectedFailure.stop }
            }
        )) { error in
            XCTAssertEqual(
                error as? LocalAgentHookMaintenanceError,
                .writeFailed(source: "kimi-code", rollbackConflicts: [])
            )
        }
        XCTAssertEqual(try Data(contentsOf: claudeURL), claudeOriginal)
        XCTAssertEqual(try Data(contentsOf: kimiURL), kimiOriginal)
    }

    func testBulkRemovalDeletesOwnedOpenCodePluginFile() throws {
        let directory = temporaryDirectory("opencode-remove")
        defer { try? FileManager.default.removeItem(at: directory) }
        let pluginURL = directory.appendingPathComponent("dev-island.js")
        let urls = ["opencode": pluginURL]

        try LocalHooksInstaller(.openCode).install(configURL: pluginURL)
        XCTAssertTrue(LocalHooksInstaller(.openCode).isInstalled(configURL: pluginURL))

        let result = try LocalAgentHookMaintenance.removeAllManagedHooks(
            descriptors: [.openCode],
            configURLsBySource: urls
        )

        XCTAssertEqual(result.removedSources, ["opencode"])
        XCTAssertFalse(StandalonePluginFileEditor.pathEntryExists(at: pluginURL))
    }

    func testLaterWriteFailureRestoresDeletedOpenCodePluginAndPermissions() throws {
        let directory = temporaryDirectory("opencode-rollback")
        defer { try? FileManager.default.removeItem(at: directory) }
        let pluginURL = directory.appendingPathComponent("dev-island.js")
        let codexURL = directory.appendingPathComponent("codex.json")
        let urls = ["opencode": pluginURL, "codex": codexURL]

        try LocalHooksInstaller(.openCode).install(configURL: pluginURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o640],
            ofItemAtPath: pluginURL.path
        )
        try LocalHooksInstaller(.codex).install(configURL: codexURL)
        let pluginOriginal = try Data(contentsOf: pluginURL)
        let codexOriginal = try Data(contentsOf: codexURL)

        XCTAssertThrowsError(try LocalAgentHookMaintenance.removeAllManagedHooks(
            descriptors: [.openCode, .codex],
            configURLsBySource: urls,
            beforeWrite: { _, _, index in
                if index == 1 { throw InjectedFailure.stop }
            }
        )) { error in
            XCTAssertEqual(
                error as? LocalAgentHookMaintenanceError,
                .writeFailed(source: "codex", rollbackConflicts: [])
            )
        }

        XCTAssertEqual(try Data(contentsOf: pluginURL), pluginOriginal)
        XCTAssertEqual(try Data(contentsOf: codexURL), codexOriginal)
        let permissions = try FileManager.default.attributesOfItem(
            atPath: pluginURL.path
        )[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o640)
    }

    func testRollbackNeverOverwritesExternallyRecreatedPluginFile() throws {
        let directory = temporaryDirectory("opencode-external-rebuild")
        defer { try? FileManager.default.removeItem(at: directory) }
        let pluginURL = directory.appendingPathComponent("dev-island.js")
        let codexURL = directory.appendingPathComponent("codex.json")
        let urls = ["opencode": pluginURL, "codex": codexURL]
        let external = Data("export const ExternalPlugin = true\n".utf8)

        try LocalHooksInstaller(.openCode).install(configURL: pluginURL)
        try LocalHooksInstaller(.codex).install(configURL: codexURL)
        let codexOriginal = try Data(contentsOf: codexURL)

        XCTAssertThrowsError(try LocalAgentHookMaintenance.removeAllManagedHooks(
            descriptors: [.openCode, .codex],
            configURLsBySource: urls,
            beforeWrite: { _, _, index in
                if index == 1 {
                    try external.write(to: pluginURL, options: .atomic)
                    throw InjectedFailure.stop
                }
            }
        )) { error in
            XCTAssertEqual(
                error as? LocalAgentHookMaintenanceError,
                .writeFailed(source: "codex", rollbackConflicts: ["opencode"])
            )
        }

        XCTAssertEqual(try Data(contentsOf: pluginURL), external)
        XCTAssertEqual(try Data(contentsOf: codexURL), codexOriginal)
    }

    func testRollbackTreatsDanglingPluginSymlinkAsExternalConflict() throws {
        let directory = temporaryDirectory("opencode-dangling-link")
        defer { try? FileManager.default.removeItem(at: directory) }
        let pluginURL = directory.appendingPathComponent("dev-island.js")
        let codexURL = directory.appendingPathComponent("codex.json")
        let missingTarget = directory.appendingPathComponent("external-missing.js")
        let urls = ["opencode": pluginURL, "codex": codexURL]

        try LocalHooksInstaller(.openCode).install(configURL: pluginURL)
        try LocalHooksInstaller(.codex).install(configURL: codexURL)

        XCTAssertThrowsError(try LocalAgentHookMaintenance.removeAllManagedHooks(
            descriptors: [.openCode, .codex],
            configURLsBySource: urls,
            beforeWrite: { _, _, index in
                if index == 1 {
                    try FileManager.default.createSymbolicLink(
                        atPath: pluginURL.path,
                        withDestinationPath: missingTarget.path
                    )
                    throw InjectedFailure.stop
                }
            }
        )) { error in
            XCTAssertEqual(
                error as? LocalAgentHookMaintenanceError,
                .writeFailed(source: "codex", rollbackConflicts: ["opencode"])
            )
        }

        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: pluginURL.path),
            missingTarget.path
        )
    }

    func testUnsafeOpenCodeSymlinkStopsDisconnectAllBeforeAnyWrite() throws {
        let directory = temporaryDirectory("opencode-symlink-prepare")
        defer { try? FileManager.default.removeItem(at: directory) }
        let claudeURL = directory.appendingPathComponent("claude.json")
        let pluginURL = directory.appendingPathComponent("dev-island.js")
        let pluginTarget = directory.appendingPathComponent("plugin-target.js")
        let urls = ["claude-code": claudeURL, "opencode": pluginURL]

        try LocalHooksInstaller(.claudeCode).install(configURL: claudeURL)
        let claudeOriginal = try Data(contentsOf: claudeURL)
        let targetOriginal = OpenCodePlugin.render(port: 7_824)
        try targetOriginal.write(to: pluginTarget)
        try FileManager.default.createSymbolicLink(
            atPath: pluginURL.path,
            withDestinationPath: pluginTarget.path
        )

        XCTAssertThrowsError(try LocalAgentHookMaintenance.removeAllManagedHooks(
            descriptors: [.claudeCode, .openCode],
            configURLsBySource: urls
        )) { error in
            XCTAssertEqual(
                error as? LocalAgentHookMaintenanceError,
                .couldNotPrepare(source: "opencode")
            )
        }

        XCTAssertEqual(try Data(contentsOf: claudeURL), claudeOriginal)
        XCTAssertEqual(try Data(contentsOf: pluginTarget), targetOriginal)
    }

    func testNoManagedFilesIsANoOp() throws {
        let directory = temporaryDirectory("noop")
        defer { try? FileManager.default.removeItem(at: directory) }
        let descriptors: [LocalAgentDescriptor] = [.claudeCode, .codex]
        let urls = urlsForDescriptors(descriptors, in: directory)

        let result = try LocalAgentHookMaintenance.removeAllManagedHooks(
            descriptors: descriptors,
            configURLsBySource: urls
        )
        XCTAssertTrue(result.wasNoOp)
        XCTAssertEqual(result.removedCount, 0)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testMalformedManagedConfigFailsBeforeAnyWrite() throws {
        let directory = temporaryDirectory("malformed")
        defer { try? FileManager.default.removeItem(at: directory) }
        let descriptors: [LocalAgentDescriptor] = [.claudeCode, .codex]
        let urls = urlsForDescriptors(descriptors, in: directory)
        let claudeURL = try XCTUnwrap(urls["claude-code"])
        let codexURL = try XCTUnwrap(urls["codex"])

        try LocalHooksInstaller(.claudeCode).install(configURL: claudeURL)
        let claudeOriginal = try Data(contentsOf: claudeURL)
        let malformed = Data("{ broken \(LocalAgentDescriptor.codex.endpointPath)".utf8)
        try FileManager.default.createDirectory(
            at: codexURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try malformed.write(to: codexURL)

        XCTAssertThrowsError(try LocalAgentHookMaintenance.removeAllManagedHooks(
            descriptors: descriptors,
            configURLsBySource: urls
        )) { error in
            XCTAssertEqual(
                error as? LocalAgentHookMaintenanceError,
                .couldNotPrepare(source: "codex")
            )
        }
        XCTAssertEqual(try Data(contentsOf: claudeURL), claudeOriginal)
        XCTAssertEqual(try Data(contentsOf: codexURL), malformed)
    }

    func testLaterWriteFailureRollsBackEarlierFilesByteForByte() throws {
        let setup = try installedPair("rollback")
        defer { try? FileManager.default.removeItem(at: setup.directory) }

        XCTAssertThrowsError(try LocalAgentHookMaintenance.removeAllManagedHooks(
            descriptors: setup.descriptors,
            configURLsBySource: setup.urls,
            beforeWrite: { _, _, index in
                if index == 1 { throw InjectedFailure.stop }
            }
        )) { error in
            XCTAssertEqual(
                error as? LocalAgentHookMaintenanceError,
                .writeFailed(source: "codex", rollbackConflicts: [])
            )
        }
        XCTAssertEqual(try Data(contentsOf: setup.claudeURL), setup.claudeOriginal)
        XCTAssertEqual(try Data(contentsOf: setup.codexURL), setup.codexOriginal)
    }

    func testConcurrentEditIsPreservedAndEarlierWriteRollsBack() throws {
        let setup = try installedPair("concurrent")
        defer { try? FileManager.default.removeItem(at: setup.directory) }
        let external = Data(#"{"external":true}"#.utf8)

        XCTAssertThrowsError(try LocalAgentHookMaintenance.removeAllManagedHooks(
            descriptors: setup.descriptors,
            configURLsBySource: setup.urls,
            beforeWrite: { _, url, index in
                if index == 1 { try external.write(to: url, options: .atomic) }
            }
        )) { error in
            XCTAssertEqual(
                error as? LocalAgentHookMaintenanceError,
                .configurationChanged(source: "codex", rollbackConflicts: [])
            )
        }
        XCTAssertEqual(try Data(contentsOf: setup.claudeURL), setup.claudeOriginal)
        XCTAssertEqual(try Data(contentsOf: setup.codexURL), external)
    }

    func testRollbackNeverOverwritesAnExternalEdit() throws {
        let setup = try installedPair("rollback-conflict")
        defer { try? FileManager.default.removeItem(at: setup.directory) }
        let external = Data(#"{"external":"keep me"}"#.utf8)

        XCTAssertThrowsError(try LocalAgentHookMaintenance.removeAllManagedHooks(
            descriptors: setup.descriptors,
            configURLsBySource: setup.urls,
            beforeWrite: { _, _, index in
                if index == 1 {
                    try external.write(to: setup.claudeURL, options: .atomic)
                    throw InjectedFailure.stop
                }
            }
        )) { error in
            let typed = error as? LocalAgentHookMaintenanceError
            XCTAssertEqual(
                typed,
                .writeFailed(source: "codex", rollbackConflicts: ["claude-code"])
            )
            XCTAssertEqual(typed?.requiresManualReview, true)
        }
        XCTAssertEqual(try Data(contentsOf: setup.claudeURL), external)
        XCTAssertEqual(try Data(contentsOf: setup.codexURL), setup.codexOriginal)
    }

    func testIndividualUninstallRemovesOnlyManagedHandlerFromMixedGroup() throws {
        let directory = temporaryDirectory("mixed")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        let managed = LocalHooksInstaller(.claudeCode).hookCommand()
        let root: [String: Any] = [
            "hooks": [
                "Stop": [[
                    "matcher": "",
                    "hooks": [
                        ["type": "command", "command": managed],
                        ["type": "command", "command": "./user-owned.sh"],
                    ],
                ]],
            ],
        ]
        try writeRoot(root, to: url)

        let installer = LocalHooksInstaller(.claudeCode)
        XCTAssertTrue(installer.hasManagedEntries(configURL: url))
        try installer.uninstall(configURL: url)

        let updated = try readRoot(url)
        let hooks = try XCTUnwrap(updated["hooks"] as? [String: Any])
        let group = try XCTUnwrap((hooks["Stop"] as? [[String: Any]])?.first)
        let handlers = try XCTUnwrap(group["hooks"] as? [[String: Any]])
        XCTAssertEqual(handlers.count, 1)
        XCTAssertEqual(handlers.first?["command"] as? String, "./user-owned.sh")
    }

    func testIndividualUninstallFailsClosedForMalformedManagedFile() throws {
        let directory = temporaryDirectory("individual-malformed")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = Data("not-json /hooks/claude-code".utf8)
        try original.write(to: url)
        let installer = LocalHooksInstaller(.claudeCode)

        XCTAssertTrue(installer.hasManagedEntries(configURL: url))
        XCTAssertThrowsError(try installer.uninstall(configURL: url))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    private typealias InstalledPair = (
        directory: URL,
        descriptors: [LocalAgentDescriptor],
        urls: [String: URL],
        claudeURL: URL,
        codexURL: URL,
        claudeOriginal: Data,
        codexOriginal: Data
    )

    private func installedPair(_ label: String) throws -> InstalledPair {
        let directory = temporaryDirectory(label)
        let descriptors: [LocalAgentDescriptor] = [.claudeCode, .codex]
        let urls = urlsForDescriptors(descriptors, in: directory)
        let claudeURL = try XCTUnwrap(urls["claude-code"])
        let codexURL = try XCTUnwrap(urls["codex"])
        try LocalHooksInstaller(.claudeCode).install(configURL: claudeURL)
        try LocalHooksInstaller(.codex).install(configURL: codexURL)
        return (
            directory,
            descriptors,
            urls,
            claudeURL,
            codexURL,
            try Data(contentsOf: claudeURL),
            try Data(contentsOf: codexURL)
        )
    }

    private func temporaryDirectory(_ label: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-bulk-\(label)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func urlsForDescriptors(
        _ descriptors: [LocalAgentDescriptor],
        in directory: URL
    ) -> [String: URL] {
        Dictionary(uniqueKeysWithValues: descriptors.map {
            ($0.source, directory.appendingPathComponent("\($0.source).json"))
        })
    }

    private func readRoot(_ url: URL) throws -> [String: Any] {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try XCTUnwrap(json as? [String: Any])
    }

    private func writeRoot(_ root: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
