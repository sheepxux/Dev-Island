import XCTest
import Foundation
@testable import IslandCore

/// Framework-level guarantees of the declarative connector table
/// (contract v1.5.0, J3). Per-agent semantics are covered by the
/// dedicated connector/installer suites; this suite pins down the
/// registry invariants everything downstream relies on.
final class LocalAgentFrameworkTests: XCTestCase {

    // MARK: - Registry invariants

    func testRegistrySourcesAreUnique() {
        let sources = LocalAgentRegistry.all.map(\.source)
        XCTAssertEqual(sources.count, Set(sources).count, "duplicate source keys break routing and snapshots")
    }

    func testRegistryContainsTheShippedAgents() {
        XCTAssertEqual(
            LocalAgentRegistry.all.map(\.source),
            ["claude-code", "codex", "cursor"]
        )
    }

    func testDescriptorLookup() {
        XCTAssertEqual(LocalAgentRegistry.descriptor(for: "codex")?.displayName, "Codex")
        XCTAssertNil(LocalAgentRegistry.descriptor(for: "manus"), "remote agents are not registry rows")
        XCTAssertNil(LocalAgentRegistry.descriptor(for: "unknown"))
    }

    func testEndpointPathsFollowTheSourceKey() {
        for descriptor in LocalAgentRegistry.all {
            XCTAssertEqual(descriptor.endpointPath, "/hooks/\(descriptor.source)")
        }
    }

    func testConfigURLExpandsTilde() {
        let url = LocalAgentDescriptor.claudeCode.configURL
        XCTAssertFalse(url.path.contains("~"))
        XCTAssertTrue(url.path.hasSuffix("/.claude/settings.json"))
    }

    // MARK: - Descriptor-driven decoding (the server's route body)

    func testDescriptorDecodesItsOwnPayload() throws {
        let payload = Data("""
        {"session_id":"s1","cwd":"/w/Proj","hook_event_name":"SessionStart"}
        """.utf8)
        let event = try XCTUnwrap(LocalAgentDescriptor.claudeCode.decodeEvent(payload))
        XCTAssertEqual(event.sessionId, "s1")
        XCTAssertEqual(event.action, .running)
    }

    func testDescriptorDropsUndecodablePayload() {
        XCTAssertNil(LocalAgentDescriptor.codex.decodeEvent(Data("not json".utf8)))
        // Decodable but unsubscribed event kinds must also drop.
        XCTAssertNil(LocalAgentDescriptor.codex.decodeEvent(Data("""
        {"session_id":"s1","hook_event_name":"PreToolUse"}
        """.utf8)))
    }

    func testCursorPayloadWithoutIdDropsAtDecode() {
        XCTAssertNil(LocalAgentDescriptor.cursor.decodeEvent(Data("""
        {"hook_event_name":"sessionStart"}
        """.utf8)))
    }

    // MARK: - Generic installer renders per-style entry shapes

    private func installerRoundTrip(_ descriptor: LocalAgentDescriptor) throws -> [String: Any] {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-framework-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")

        let installer = LocalHooksInstaller(descriptor)
        XCTAssertFalse(installer.isInstalled(configURL: url))
        try installer.install(configURL: url)
        XCTAssertTrue(installer.isInstalled(configURL: url))

        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testNestedWithMatcherStyle() throws {
        let root = try installerRoundTrip(.claudeCode)
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        let group = try XCTUnwrap((hooks["Stop"] as? [[String: Any]])?.first)
        XCTAssertEqual(group["matcher"] as? String, "")
        XCTAssertNotNil(group["hooks"], "Claude entries nest commands under 'hooks'")
    }

    func testNestedStyleOmitsMatcher() throws {
        let root = try installerRoundTrip(.codex)
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        let group = try XCTUnwrap((hooks["Stop"] as? [[String: Any]])?.first)
        XCTAssertNil(group["matcher"], "Codex matchers are event-specific; omitted = match all")
        XCTAssertNotNil(group["hooks"])
    }

    func testFlatVersionedStyleWritesVersionKey() throws {
        let root = try installerRoundTrip(.cursor)
        XCTAssertEqual(root["version"] as? Int, 1)
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        let group = try XCTUnwrap((hooks["stop"] as? [[String: Any]])?.first)
        XCTAssertNotNil(group["command"], "Cursor entries are flat")
        XCTAssertNil(group["hooks"])
    }

    func testHookCommandNeverFailsTheTurn() {
        // The trailing `|| true` is a hard requirement for every agent: a
        // dead Dev Island must never surface as a hook error in a session.
        for descriptor in LocalAgentRegistry.all {
            let command = LocalHooksInstaller(descriptor).hookCommand()
            XCTAssertTrue(command.hasSuffix("|| true"), descriptor.source)
            XCTAssertTrue(command.contains("-m 2"), descriptor.source)
            XCTAssertTrue(command.contains(descriptor.endpointPath), descriptor.source)
        }
    }

    // MARK: - Generic connector honors normalized actions

    func testWaitingActionAppliesRegardlessOfAgent() async {
        // .waiting comes from descriptor mappings today (Claude/Codex),
        // but the connector itself must handle it for any future agent.
        let connector = LocalAgentConnector(descriptor: .cursor)
        let tasks = await connector.apply(LocalAgentEvent(
            sessionId: "s1",
            cwd: "/w/Proj",
            action: .waiting(phase: "Needs input", message: "?")
        ))
        XCTAssertEqual(tasks[0].status, .waiting)
        XCTAssertEqual(tasks[0].currentPhase, "Needs input")
    }

    func testIgnoredActionMutatesNothingButStillPrunes() async {
        let connector = LocalAgentConnector(descriptor: .claudeCode)
        let t0 = Date(timeIntervalSince1970: 1_000)
        _ = await connector.apply(
            LocalAgentEvent(sessionId: "old", action: .completed(phase: nil)), now: t0)
        let tasks = await connector.apply(
            LocalAgentEvent(sessionId: "x", action: .ignored),
            now: t0.addingTimeInterval(LocalAgentConnector.finishedTTL + 1))
        XCTAssertTrue(tasks.isEmpty, "ignored events don't create tasks; pruning still ran")
    }
}
