import CryptoKit
import Foundation
import XCTest
@testable import IslandCore

final class OpenCodePluginInstallerTests: XCTestCase {
    private var directory: URL!
    private var pluginURL: URL!
    private let installer = LocalHooksInstaller(.openCode)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-opencode-\(UUID().uuidString)")
        pluginURL = directory
            .appendingPathComponent("plugins", isDirectory: true)
            .appendingPathComponent("dev-island.js")
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    func testRendererIsExactAndPinsReviewedUpstreamContract() throws {
        let data = OpenCodePlugin.render(port: 17_824)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()

        XCTAssertEqual(digest, "a74ad4e5c4a5c07b05d235b3bedce3136842ae6113d96ce172ed4e1871c1d57b")
        XCTAssertTrue(text.hasPrefix("// \(OpenCodePlugin.managedMarker) v2\n"))
        XCTAssertTrue(text.contains("OpenCode \(OpenCodePlugin.pinnedVersion)"))
        XCTAssertTrue(text.contains("interface \(OpenCodePlugin.pinnedCommit)"))
        XCTAssertTrue(text.contains(#"const endpoint = "http://127.0.0.1:17824/hooks/opencode""#))
        XCTAssertTrue(text.contains(
            #""\#(LocalHooksInstaller.requestHeaderName)": "\#(LocalHooksInstaller.requestHeaderValue)""#
        ))
        XCTAssertTrue(text.contains(LocalHookAuthorizationStore.relativeHeaderFilePath))
        XCTAssertTrue(text.contains("Bun.file(authorizationPath)"))
        XCTAssertTrue(text.contains("file.slice(0, 129)"))
        XCTAssertTrue(text.contains(#""X-Dev-Island-Authorization": credential"#))
        XCTAssertFalse(text.contains(localHookTestAuthorization.headerValue))
        XCTAssertEqual(text.components(separatedBy: "schema_version: 1").count - 1, 1)
    }

    func testRendererIsDependencyFreePrivacyMinimalAndFailOpen() throws {
        let text = try XCTUnwrap(String(
            data: OpenCodePlugin.render(port: 7_824),
            encoding: .utf8
        ))

        XCTAssertFalse(text.contains("import "))
        XCTAssertFalse(text.contains("require("))
        XCTAssertFalse(text.contains("permission.ask"))
        XCTAssertFalse(text.contains("output."))
        XCTAssertFalse(text.contains("prompt"))
        XCTAssertFalse(text.contains("title"))
        XCTAssertFalse(text.contains("message."))
        XCTAssertFalse(text.contains("tool."))
        XCTAssertFalse(text.contains("error.message"))
        XCTAssertTrue(text.contains("void fetch(endpoint"))
        XCTAssertFalse(text.contains("await fetch(endpoint"))
        XCTAssertTrue(text.contains("setTimeout(() => controller.abort(), 1000)"))
        XCTAssertTrue(text.contains(".catch(() => {}).finally(() => clearTimeout(timeout))"))

        let events = [
            "session.created", "session.status", "session.idle",
            "session.deleted", "session.error", "permission.updated",
            "permission.replied",
        ]
        for event in events {
            XCTAssertEqual(
                text.components(separatedBy: #"case "\#(event)":"#).count - 1,
                1,
                event
            )
        }
        XCTAssertEqual(text.components(separatedBy: "case \"").count - 1, events.count)
    }

    func testInstallIsIdempotentUpdatesOwnedFileAndUninstalls() throws {
        XCTAssertFalse(installer.isInstalled(configURL: pluginURL))
        try installer.install(configURL: pluginURL)
        let expected = OpenCodePlugin.render(port: LocalHooksInstaller.defaultPort)
        XCTAssertEqual(try Data(contentsOf: pluginURL), expected)
        XCTAssertTrue(installer.isInstalled(configURL: pluginURL))
        XCTAssertFalse(installer.requiresUpdate(configURL: pluginURL))
        XCTAssertEqual(try permissions(at: pluginURL), 0o600)

        try installer.install(configURL: pluginURL)
        XCTAssertEqual(try Data(contentsOf: pluginURL), expected)

        try installer.install(configURL: pluginURL, port: 18_888)
        XCTAssertEqual(try Data(contentsOf: pluginURL), OpenCodePlugin.render(port: 18_888))
        XCTAssertTrue(installer.requiresUpdate(configURL: pluginURL))

        try installer.install(configURL: pluginURL)
        XCTAssertEqual(try Data(contentsOf: pluginURL), expected)
        XCTAssertFalse(installer.requiresUpdate(configURL: pluginURL))

        try installer.uninstall(configURL: pluginURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: pluginURL.path))
        XCTAssertFalse(installer.hasManagedEntries(configURL: pluginURL))
        try installer.uninstall(configURL: pluginURL)
    }

    func testIdempotentInstallRepairsPermissionsWithoutChangingBytes() throws {
        try installer.install(configURL: pluginURL)
        let expected = try Data(contentsOf: pluginURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: pluginURL.path
        )

        try installer.install(configURL: pluginURL)

        XCTAssertEqual(try Data(contentsOf: pluginURL), expected)
        XCTAssertEqual(try permissions(at: pluginURL), 0o600)
    }

    func testUnownedCollisionIsNeverOverwrittenOrRemoved() throws {
        try FileManager.default.createDirectory(
            at: pluginURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = Data("export const UserPlugin = async () => ({})\n".utf8)
        try original.write(to: pluginURL)

        XCTAssertThrowsError(try installer.install(configURL: pluginURL))
        XCTAssertEqual(try Data(contentsOf: pluginURL), original)
        XCTAssertFalse(installer.hasManagedEntries(configURL: pluginURL))

        try installer.uninstall(configURL: pluginURL)
        XCTAssertEqual(try Data(contentsOf: pluginURL), original)
    }

    func testSymlinkAndDirectoryCollisionsFailClosed() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("target.js")
        let targetBytes = OpenCodePlugin.render(port: 7_824)
        try targetBytes.write(to: target)
        try FileManager.default.createDirectory(
            at: pluginURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            atPath: pluginURL.path,
            withDestinationPath: target.path
        )

        XCTAssertFalse(installer.isInstalled(configURL: pluginURL))
        XCTAssertThrowsError(try installer.install(configURL: pluginURL))
        XCTAssertThrowsError(try installer.uninstall(configURL: pluginURL))
        XCTAssertEqual(try Data(contentsOf: target), targetBytes)

        try FileManager.default.removeItem(at: pluginURL)
        try FileManager.default.createDirectory(at: pluginURL, withIntermediateDirectories: true)
        XCTAssertThrowsError(try installer.install(configURL: pluginURL))
        XCTAssertThrowsError(try installer.uninstall(configURL: pluginURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pluginURL.path))
    }

    func testOversizedManagedLookingFileIsNeverReadAsOwnedOrChanged() throws {
        try FileManager.default.createDirectory(
            at: pluginURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var original = Data("// \(OpenCodePlugin.managedMarker) v1\n".utf8)
        original.append(Data(
            repeating: 0x78,
            count: StandalonePluginFileEditor.maximumPluginBytes - original.count + 1
        ))
        try original.write(to: pluginURL)

        XCTAssertFalse(installer.hasManagedEntries(configURL: pluginURL))
        XCTAssertThrowsError(try installer.install(configURL: pluginURL))
        XCTAssertThrowsError(try installer.uninstall(configURL: pluginURL))
        XCTAssertEqual(try Data(contentsOf: pluginURL), original)
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? Int)
    }
}
