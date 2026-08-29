import Foundation
import XCTest
@testable import IslandCore

final class ManagedConfigFileTests: XCTestCase {
    func testSymlinkedManagedJSONIsVisibleButNeverTrustedOrMutated() throws {
        let directory = try temporaryDirectory("managed-config-symlink")
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.json")
        let link = directory.appendingPathComponent("settings.json")

        try ClaudeHooksInstaller.install(settingsURL: target)
        let sentinel = try Data(contentsOf: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let installer = LocalHooksInstaller(.claudeCode)
        XCTAssertTrue(installer.hasManagedEntries(configURL: link))
        XCTAssertFalse(installer.isInstalled(configURL: link))
        XCTAssertTrue(installer.requiresUpdate(configURL: link))
        XCTAssertThrowsError(try installer.install(configURL: link))
        XCTAssertThrowsError(try installer.uninstall(configURL: link))
        XCTAssertEqual(try Data(contentsOf: target), sentinel)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), target.path)
    }

    func testHardLinkedManagedJSONIsNeverTrustedOrMutated() throws {
        let directory = try temporaryDirectory("managed-config-hardlink")
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.json")
        let link = directory.appendingPathComponent("hooks.json")

        try CodexHooksInstaller.install(hooksURL: target)
        let sentinel = try Data(contentsOf: target)
        try FileManager.default.linkItem(at: target, to: link)

        let installer = LocalHooksInstaller(.codex)
        XCTAssertTrue(installer.hasManagedEntries(configURL: link))
        XCTAssertFalse(installer.isInstalled(configURL: link))
        XCTAssertThrowsError(try installer.install(configURL: link))
        XCTAssertThrowsError(try installer.uninstall(configURL: link))
        XCTAssertEqual(try Data(contentsOf: target), sentinel)
        XCTAssertEqual(try Data(contentsOf: link), sentinel)
    }

    func testSymlinkedManagedTOMLIsVisibleButNeverMutated() throws {
        let directory = try temporaryDirectory("managed-config-toml-symlink")
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.toml")
        let link = directory.appendingPathComponent("config.toml")

        let installer = LocalHooksInstaller(.kimiCode)
        try installer.install(configURL: target)
        let sentinel = try Data(contentsOf: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertTrue(installer.hasManagedEntries(configURL: link))
        XCTAssertFalse(installer.isInstalled(configURL: link))
        XCTAssertThrowsError(try installer.install(configURL: link))
        XCTAssertThrowsError(try installer.uninstall(configURL: link))
        XCTAssertEqual(try Data(contentsOf: target), sentinel)
    }

    func testUnsafeStructuredConfigStopsBulkRemovalBeforeAnyWrite() throws {
        let directory = try temporaryDirectory("managed-config-bulk-symlink")
        defer { try? FileManager.default.removeItem(at: directory) }
        let claudeURL = directory.appendingPathComponent("claude.json")
        let codexTarget = directory.appendingPathComponent("codex-target.json")
        let codexLink = directory.appendingPathComponent("codex.json")

        try LocalHooksInstaller(.claudeCode).install(configURL: claudeURL)
        try LocalHooksInstaller(.codex).install(configURL: codexTarget)
        let claudeOriginal = try Data(contentsOf: claudeURL)
        let codexOriginal = try Data(contentsOf: codexTarget)
        try FileManager.default.createSymbolicLink(
            at: codexLink,
            withDestinationURL: codexTarget
        )

        XCTAssertThrowsError(try LocalAgentHookMaintenance.removeAllManagedHooks(
            descriptors: [.claudeCode, .codex],
            configURLsBySource: [
                "claude-code": claudeURL,
                "codex": codexLink,
            ]
        )) { error in
            XCTAssertEqual(
                error as? LocalAgentHookMaintenanceError,
                .couldNotPrepare(source: "codex")
            )
        }
        XCTAssertEqual(try Data(contentsOf: claudeURL), claudeOriginal)
        XCTAssertEqual(try Data(contentsOf: codexTarget), codexOriginal)
    }

    func testOversizedJSONAndDirectoryTargetsFailWithoutMutation() throws {
        let directory = try temporaryDirectory("managed-config-size-kind")
        defer { try? FileManager.default.removeItem(at: directory) }
        let oversizedURL = directory.appendingPathComponent("oversized.json")
        let oversized = Data(
            repeating: 0x20,
            count: ManagedConfigFile.maximumConfigBytes + 1
        )
        try oversized.write(to: oversizedURL)

        XCTAssertThrowsError(try ClaudeHooksInstaller.install(settingsURL: oversizedURL))
        XCTAssertEqual(try Data(contentsOf: oversizedURL), oversized)

        let directoryTarget = directory.appendingPathComponent("directory.json")
        try FileManager.default.createDirectory(at: directoryTarget, withIntermediateDirectories: false)
        XCTAssertThrowsError(try ClaudeHooksInstaller.install(settingsURL: directoryTarget))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directoryTarget.path,
            isDirectory: &isDirectory
        ))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testSnapshotComparisonRejectsInPlaceMutationWithSameInode() throws {
        let directory = try temporaryDirectory("managed-config-in-place")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        let original = Data("{\"theme\":\"dark\"}".utf8)
        try original.write(to: url)
        let snapshot = try XCTUnwrap(ManagedConfigFile.snapshotIfExists(at: url))

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(" ".utf8))
        try handle.close()
        let external = try Data(contentsOf: url)

        XCTAssertThrowsError(
            try ManagedConfigFile.replace(
                Data("{\"theme\":\"light\"}".utf8),
                at: url,
                expecting: .snapshot(snapshot)
            )
        ) { error in
            guard case ManagedConfigFile.FileError.configurationChanged = error else {
                return XCTFail("expected a concurrent-change error, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: url), external)
    }

    func testAbsentCommitNeverOverwritesAFileCreatedAtTheFinalRace() throws {
        let directory = try temporaryDirectory("managed-config-absent-race")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        let external = Data("{\"external\":true}".utf8)

        XCTAssertThrowsError(
            try ManagedConfigFile.replace(
                Data("{\"managed\":true}".utf8),
                at: url,
                expecting: .absent,
                beforeCommit: {
                    try external.write(to: url)
                }
            )
        )
        XCTAssertEqual(try Data(contentsOf: url), external)
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .contains(where: { $0.contains(".dev-island.") })
        )
    }

    func testExistingCommitRestoresAReplacementCreatedAtTheFinalRace() throws {
        let directory = try temporaryDirectory("managed-config-replace-race")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        try Data("{\"theme\":\"dark\"}".utf8).write(to: url)
        let snapshot = try XCTUnwrap(ManagedConfigFile.snapshotIfExists(at: url))
        let external = Data("{\"external\":true}".utf8)

        XCTAssertThrowsError(
            try ManagedConfigFile.replace(
                Data("{\"managed\":true}".utf8),
                at: url,
                expecting: .snapshot(snapshot),
                beforeCommit: {
                    try FileManager.default.removeItem(at: url)
                    try external.write(to: url)
                }
            )
        ) { error in
            guard case ManagedConfigFile.FileError.configurationChanged = error else {
                return XCTFail("expected a concurrent-change error, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: url), external)
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .contains(where: { $0.contains(".dev-island.") })
        )
    }

    func testRemoveRestoresAReplacementCreatedAtTheFinalRace() throws {
        let directory = try temporaryDirectory("managed-config-remove-race")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        try Data("{\"theme\":\"dark\"}".utf8).write(to: url)
        let snapshot = try XCTUnwrap(ManagedConfigFile.snapshotIfExists(at: url))
        let external = Data("{\"external\":true}".utf8)

        XCTAssertThrowsError(
            try ManagedConfigFile.remove(
                at: url,
                expecting: snapshot,
                beforeCommit: {
                    try FileManager.default.removeItem(at: url)
                    try external.write(to: url)
                }
            )
        ) { error in
            guard case ManagedConfigFile.FileError.configurationChanged = error else {
                return XCTFail("expected a concurrent-change error, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: url), external)
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .contains(where: { $0.contains(".dev-island.") })
        )
    }

    func testNewConfigsArePrivateAndExistingPermissionsSurviveUpdate() throws {
        let directory = try temporaryDirectory("managed-config-permissions")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")

        try ClaudeHooksInstaller.install(settingsURL: url)
        XCTAssertEqual(permissions(at: url), 0o600)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o640],
            ofItemAtPath: url.path
        )
        try ClaudeHooksInstaller.install(settingsURL: url)
        XCTAssertEqual(permissions(at: url), 0o640)
    }

    func testSymlinkedParentDirectoryIsSafelyResolvedAndAnchored() throws {
        let directory = try temporaryDirectory("managed-config-parent-link")
        defer { try? FileManager.default.removeItem(at: directory) }
        let realParent = directory.appendingPathComponent("real")
        let linkedParent = directory.appendingPathComponent("linked")
        try FileManager.default.createDirectory(at: realParent, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            at: linkedParent,
            withDestinationURL: realParent
        )
        let url = linkedParent.appendingPathComponent("settings.json")

        try ClaudeHooksInstaller.install(settingsURL: url)
        let concreteURL = realParent.appendingPathComponent("settings.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: concreteURL.path))
        XCTAssertTrue(ClaudeHooksInstaller.isInstalled(settingsURL: url))
        XCTAssertEqual(permissions(at: concreteURL), 0o600)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: linkedParent.path),
            realParent.path
        )
    }

    func testDanglingParentDirectoryLinkIsRejectedWithoutCreatingTarget() throws {
        let directory = try temporaryDirectory("managed-config-dangling-parent")
        defer { try? FileManager.default.removeItem(at: directory) }
        let missingParent = directory.appendingPathComponent("missing")
        let linkedParent = directory.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(
            at: linkedParent,
            withDestinationURL: missingParent
        )
        let url = linkedParent.appendingPathComponent("settings.json")

        XCTAssertThrowsError(try ClaudeHooksInstaller.install(settingsURL: url))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: missingParent.appendingPathComponent("settings.json").path
        ))
    }

    func testGroupWritableParentDirectoryIsRejectedWithoutCreatingTarget() throws {
        let directory = try temporaryDirectory("managed-config-writable-parent")
        defer { try? FileManager.default.removeItem(at: directory) }
        let unsafeParent = directory.appendingPathComponent("unsafe")
        try FileManager.default.createDirectory(at: unsafeParent, withIntermediateDirectories: false)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o770],
            ofItemAtPath: unsafeParent.path
        )
        let url = unsafeParent.appendingPathComponent("settings.json")

        XCTAssertThrowsError(try ClaudeHooksInstaller.install(settingsURL: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    private func temporaryDirectory(_ suffix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-\(suffix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func permissions(at url: URL) -> Int? {
        try? FileManager.default.attributesOfItem(
            atPath: url.path
        )[.posixPermissions] as? Int
    }
}
