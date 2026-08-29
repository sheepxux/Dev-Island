import Foundation
import XCTest
@testable import IslandCore

final class LocalAgentHookDiagnosticsTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-hook-diagnostics-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testSnapshotDistinguishesConnectedConfiguredUpdateAndDisconnected() throws {
        let claudeURL = temporaryDirectory.appendingPathComponent("claude.json")
        let codexURL = temporaryDirectory.appendingPathComponent("codex.json")
        let cursorURL = temporaryDirectory.appendingPathComponent("cursor.json")
        let qwenURL = temporaryDirectory.appendingPathComponent("qwen.json")

        try LocalHooksInstaller(.claudeCode).install(configURL: claudeURL)
        try LocalHooksInstaller(.codex).install(configURL: codexURL)
        try LocalHooksInstaller(.cursor).install(configURL: cursorURL, port: 9_999)
        let claudeBefore = try Data(contentsOf: claudeURL)
        let codexBefore = try Data(contentsOf: codexURL)
        let cursorBefore = try Data(contentsOf: cursorURL)

        let snapshot = LocalAgentHookDiagnostics.snapshot(
            descriptors: [.claudeCode, .codex, .cursor, .qwenCode],
            configURLsBySource: [
                "claude-code": claudeURL,
                "codex": codexURL,
                "cursor": cursorURL,
                "qwen-code": qwenURL,
            ]
        )

        XCTAssertEqual(
            snapshot.agents.map(\.source),
            ["claude-code", "codex", "cursor", "qwen-code"]
        )
        XCTAssertEqual(
            snapshot.agents.map(\.state),
            [.connected, .configured, .updateRequired, .disconnected]
        )
        XCTAssertEqual(snapshot.connectedCount, 1)
        XCTAssertEqual(snapshot.configuredCount, 1)
        XCTAssertEqual(snapshot.updateRequiredCount, 1)
        XCTAssertEqual(snapshot.disconnectedCount, 1)
        XCTAssertEqual(try Data(contentsOf: claudeURL), claudeBefore)
        XCTAssertEqual(try Data(contentsOf: codexURL), codexBefore)
        XCTAssertEqual(try Data(contentsOf: cursorURL), cursorBefore)
    }

    func testSnapshotDoesNotCreateMissingConfiguration() {
        let missingURL = temporaryDirectory.appendingPathComponent("missing.json")

        let snapshot = LocalAgentHookDiagnostics.snapshot(
            descriptors: [.cursor],
            configURLsBySource: ["cursor": missingURL]
        )

        XCTAssertEqual(snapshot.agents.first?.state, .disconnected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingURL.path))
    }

    func testVerifiedVendorActivationPromotesOnlyItsConfiguredSource() throws {
        let codexURL = temporaryDirectory.appendingPathComponent("codex.json")
        let claudeURL = temporaryDirectory.appendingPathComponent("claude.json")
        try LocalHooksInstaller(.codex).install(configURL: codexURL)
        try LocalHooksInstaller(.claudeCode).install(configURL: claudeURL)

        let snapshot = LocalAgentHookDiagnostics.snapshot(
            descriptors: [.claudeCode, .codex],
            configURLsBySource: [
                "claude-code": claudeURL,
                "codex": codexURL,
            ],
            verifiedActivatedSources: ["codex"]
        )

        XCTAssertEqual(snapshot.agents.map(\.state), [.connected, .connected])
        XCTAssertEqual(snapshot.connectedCount, 2)
        XCTAssertEqual(snapshot.configuredCount, 0)
    }
}
