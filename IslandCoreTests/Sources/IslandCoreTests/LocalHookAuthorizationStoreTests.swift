import Foundation
import XCTest
@testable import IslandCore

final class LocalHookAuthorizationStoreTests: XCTestCase {
    func testRotationCreatesPrivateBoundedHeaderAndInvalidatesOldCredential() throws {
        let directory = try temporaryDirectory("rotate")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory
            .appendingPathComponent("private", isDirectory: true)
            .appendingPathComponent("authorization.header")

        let first = try LocalHookAuthorizationStore.rotate(at: url)
        let firstData = try Data(contentsOf: url)
        let second = try LocalHookAuthorizationStore.rotate(at: url)
        let secondData = try Data(contentsOf: url)

        XCTAssertLessThanOrEqual(
            secondData.count,
            LocalHookAuthorizationStore.maximumHeaderFileBytes
        )
        XCTAssertEqual(secondData, second.headerFileData)
        XCTAssertNotEqual(first.headerValue, second.headerValue)
        XCTAssertFalse(second.matches(first.headerValue))
        XCTAssertTrue(second.matches(second.headerValue))
        XCTAssertNotEqual(firstData, secondData)
        XCTAssertEqual(permissions(at: url), 0o600)
        XCTAssertEqual(permissions(at: url.deletingLastPathComponent()), 0o700)
    }

    func testAuthorizationValidationRejectsLengthPrefixCaseAndValueChanges() {
        XCTAssertTrue(localHookTestAuthorization.matches(localHookTestAuthorization.headerValue))
        XCTAssertFalse(localHookTestAuthorization.matches(nil))
        XCTAssertFalse(localHookTestAuthorization.matches(""))
        XCTAssertFalse(localHookTestAuthorization.matches(
            "v2." + String(repeating: "a", count: 64)
        ))
        XCTAssertFalse(localHookTestAuthorization.matches(
            "v1." + String(repeating: "A", count: 64)
        ))
        XCTAssertFalse(localHookTestAuthorization.matches(
            "v1." + String(repeating: "a", count: 63)
        ))
        XCTAssertFalse(localHookTestAuthorization.matches(
            "v1." + String(repeating: "a", count: 63) + "b"
        ))
    }

    func testSymlinkAndHardLinkTargetsFailClosedWithoutMutation() throws {
        let directory = try temporaryDirectory("links")
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.header")
        let symlink = directory.appendingPathComponent("symlink.header")
        let hardLink = directory.appendingPathComponent("hardlink.header")
        let sentinel = Data("do-not-replace".utf8)
        try sentinel.write(to: target)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
        try FileManager.default.linkItem(at: target, to: hardLink)

        XCTAssertThrowsError(try LocalHookAuthorizationStore.rotate(at: symlink))
        XCTAssertThrowsError(try LocalHookAuthorizationStore.rotate(at: hardLink))
        XCTAssertEqual(try Data(contentsOf: target), sentinel)
        XCTAssertEqual(try Data(contentsOf: hardLink), sentinel)
    }

    private func temporaryDirectory(_ suffix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-hook-auth-\(suffix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return url
    }

    private func permissions(at url: URL) -> Int? {
        try? FileManager.default.attributesOfItem(
            atPath: url.path
        )[.posixPermissions] as? Int
    }
}
