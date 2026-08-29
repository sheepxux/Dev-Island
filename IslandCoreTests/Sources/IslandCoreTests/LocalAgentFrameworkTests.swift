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
        // Superset, not equality: registry expansion is the intended
        // onboarding path and must not break this suite — only accidental
        // *removal* of a shipped agent should.
        let sources = Set(LocalAgentRegistry.all.map(\.source))
        XCTAssertTrue(sources.isSuperset(of: [
            "claude-code", "codex", "gemini-cli", "qwen-code", "copilot-cli", "kimi-code", "opencode", "cursor",
        ]))
    }

    func testDescriptorLookup() {
        XCTAssertEqual(LocalAgentRegistry.descriptor(for: "codex")?.displayName, "Codex")
        XCTAssertNil(LocalAgentRegistry.descriptor(for: "manus"), "remote agents are not registry rows")
        XCTAssertNil(LocalAgentRegistry.descriptor(for: "unknown"))
    }

    func testShippedCapabilityMatrixMatchesVerifiedDepth() {
        XCTAssertEqual(
            LocalAgentDescriptor.codex.capabilities.permissionRequests,
            .bidirectional
        )
        XCTAssertEqual(
            LocalAgentDescriptor.claudeCode.capabilities.permissionRequests,
            .bidirectional
        )
        XCTAssertEqual(
            LocalAgentDescriptor.claudeCode.capabilities.questionRequests,
            .bidirectional
        )
        XCTAssertEqual(
            LocalAgentDescriptor.claudeCode.capabilities.planReviews,
            .bidirectional
        )
        XCTAssertEqual(
            LocalAgentDescriptor.cursor.capabilities.permissionRequests,
            .unavailable
        )
        XCTAssertEqual(
            LocalAgentDescriptor.geminiCLI.capabilities.permissionRequests,
            .observeOnly
        )
        XCTAssertEqual(
            LocalAgentDescriptor.qwenCode.capabilities.permissionRequests,
            .bidirectional
        )
        XCTAssertEqual(
            LocalAgentDescriptor.copilotCLI.capabilities.permissionRequests,
            .observeOnly
        )
        XCTAssertEqual(
            LocalAgentDescriptor.copilotCLI.capabilities.questionRequests,
            .observeOnly
        )
        XCTAssertEqual(
            LocalAgentDescriptor.kimiCode.capabilities.permissionRequests,
            .observeOnly
        )
        XCTAssertEqual(
            LocalAgentDescriptor.openCode.capabilities.permissionRequests,
            .observeOnly
        )
        XCTAssertEqual(LocalAgentDescriptor.codex.actionHookEvents, ["PermissionRequest"])
        XCTAssertEqual(
            LocalAgentDescriptor.claudeCode.actionHookEvents,
            ["PermissionRequest", "PreToolUse"]
        )
        XCTAssertEqual(
            LocalAgentDescriptor.claudeCode.hookMatchersByEvent["PreToolUse"],
            "AskUserQuestion|ExitPlanMode"
        )
        XCTAssertTrue(LocalAgentDescriptor.cursor.actionHookEvents.isEmpty)
        XCTAssertTrue(LocalAgentDescriptor.geminiCLI.actionHookEvents.isEmpty)
        XCTAssertEqual(LocalAgentDescriptor.qwenCode.actionHookEvents, ["PermissionRequest"])
        XCTAssertTrue(LocalAgentDescriptor.copilotCLI.actionHookEvents.isEmpty)
        XCTAssertTrue(LocalAgentDescriptor.kimiCode.actionHookEvents.isEmpty)
        XCTAssertTrue(LocalAgentDescriptor.openCode.actionHookEvents.isEmpty)
        XCTAssertEqual(LocalAgentDescriptor.geminiCLI.releaseStage, .preview)
        XCTAssertEqual(LocalAgentDescriptor.qwenCode.releaseStage, .preview)
        XCTAssertEqual(LocalAgentDescriptor.copilotCLI.releaseStage, .preview)
        XCTAssertEqual(LocalAgentDescriptor.kimiCode.releaseStage, .preview)
        XCTAssertEqual(LocalAgentDescriptor.openCode.releaseStage, .preview)
        XCTAssertEqual(
            LocalAgentDescriptor.codex.hookActivationRequirement,
            .reviewInAgent(command: "/hooks")
        )
        XCTAssertEqual(LocalAgentDescriptor.claudeCode.hookActivationRequirement, .none)
    }

    func testBidirectionalEventsHaveBothWireCodecs() {
        for descriptor in LocalAgentRegistry.all where !descriptor.actionHookEvents.isEmpty {
            XCTAssertNotNil(descriptor.decodeActionRequest, descriptor.source)
            XCTAssertNotNil(descriptor.encodeActionResponse, descriptor.source)
        }
    }

    func testEndpointPathsFollowTheSourceKey() {
        for descriptor in LocalAgentRegistry.all {
            XCTAssertEqual(descriptor.endpointPath, "/hooks/\(descriptor.source)")
        }
    }

    func testSourceKeyRejectsNonASCIIDigits() {
        // Character.isNumber accepts Unicode numerals; we must not.
        // Registry rows are code so a bad key traps at init — verify the
        // shipped rows themselves all satisfy the ASCII contract.
        for descriptor in LocalAgentRegistry.all {
            XCTAssertTrue(
                descriptor.source.utf8.allSatisfy {
                    ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2D
                },
                "source \(descriptor.source) must be ASCII [a-z0-9-]"
            )
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

    func testEmptySessionIdDropsAtDecodeForEveryAgent() {
        // A malformed local request must not be keyed as one shared ""
        // task. Whitespace-only ids are equally unusable.
        let payloads: [(LocalAgentDescriptor, String)] = [
            (.claudeCode, #"{"session_id":"","hook_event_name":"SessionStart"}"#),
            (.claudeCode, #"{"session_id":"  ","hook_event_name":"Stop"}"#),
            (.codex, #"{"session_id":"","hook_event_name":"SessionStart"}"#),
            (.geminiCLI, #"{"session_id":" \n","hook_event_name":"BeforeAgent"}"#),
            (.qwenCode, #"{"session_id":" ","hook_event_name":"SessionStart"}"#),
            (.copilotCLI, #"{"session_id":" ","hook_event_name":"SessionStart"}"#),
            (.kimiCode, #"{"session_id":" ","hook_event_name":"SessionStart"}"#),
            (.openCode, #"{"schema_version":1,"event":"session.created","session_id":" \n"}"#),
            (.cursor, #"{"conversation_id":" ","hook_event_name":"stop"}"#),
        ]
        for (descriptor, json) in payloads {
            XCTAssertNil(
                descriptor.decodeEvent(Data(json.utf8)),
                "\(descriptor.source) accepted an unusable session id"
            )
        }
    }

    func testOversizedAndControlSessionIDsDropAtTheSharedBoundary() {
        let oversized = String(
            repeating: "s",
            count: LocalAgentEvent.maximumSessionIDBytes + 1
        )
        XCTAssertNil(LocalAgentEvent.validSessionId(oversized))
        XCTAssertNil(LocalAgentEvent.validSessionId("session\u{0000}hidden"))

        let root: [String: Any] = [
            "session_id": oversized,
            "cwd": "/w/Proj",
            "hook_event_name": "SessionStart",
        ]
        let data = try? JSONSerialization.data(withJSONObject: root)
        XCTAssertNil(data.flatMap(LocalAgentDescriptor.claudeCode.decodeEvent))
    }

    func testLocalEventBoundsPathGenerationPhaseMessageAndDerivedTitle() async {
        let pathologicalCluster = "a" + String(repeating: "\u{0301}", count: 8_192)
        let event = LocalAgentEvent(
            sessionId: "bounded",
            cwd: "/" + String(
                repeating: "p",
                count: LocalAgentEvent.maximumCWDBytes
            ),
            generationId: String(
                repeating: "g",
                count: LocalAgentEvent.maximumGenerationIDBytes + 1
            ),
            action: .waiting(
                phase: "Phase " + pathologicalCluster,
                message: "Message " + pathologicalCluster
            )
        )

        XCTAssertNil(event.cwd)
        XCTAssertNil(event.generationId)
        guard case .waiting(let phase, let message) = event.action else {
            return XCTFail("Expected bounded waiting action")
        }
        XCTAssertLessThanOrEqual(phase.utf8.count, LocalAgentEvent.maximumPhaseBytes)
        XCTAssertLessThanOrEqual(
            message?.utf8.count ?? .max,
            LocalAgentEvent.maximumMessageBytes
        )

        let connector = LocalAgentConnector(descriptor: .claudeCode)
        let longComponent = String(repeating: "t", count: 2_048)
        let tasks = await connector.apply(LocalAgentEvent(
            sessionId: "long-title",
            cwd: "/Users/dev/\(longComponent)",
            action: .running
        ))
        XCTAssertLessThanOrEqual(
            tasks.first?.title.utf8.count ?? .max,
            LocalSessionTable.maximumTitleBytes
        )
    }

    // MARK: - Generic installer renders per-style entry shapes

    private func installerRoundTrip(_ descriptor: LocalAgentDescriptor) throws -> [String: Any] {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-framework-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")

        let installer = LocalHooksInstaller(descriptor)
        XCTAssertFalse(installer.isInstalled(configURL: url))
        XCTAssertFalse(installer.requiresUpdate(configURL: url))
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
        for descriptor in LocalAgentRegistry.all where descriptor.standalonePluginRenderer == nil {
            let command = LocalHooksInstaller(descriptor).hookCommand()
            XCTAssertTrue(command.hasSuffix("|| true"), descriptor.source)
            XCTAssertTrue(command.contains("-m 2"), descriptor.source)
            XCTAssertTrue(command.contains(descriptor.endpointPath), descriptor.source)
            XCTAssertTrue(
                command.contains("-H '\(LocalHooksInstaller.requestHeaderName): \(LocalHooksInstaller.requestHeaderValue)'"),
                descriptor.source
            )
            XCTAssertTrue(
                command.contains("-H \"@\(LocalHookAuthorizationStore.shellHeaderFilePath)\""),
                descriptor.source
            )
            XCTAssertFalse(command.contains(localHookTestAuthorization.headerValue))
        }
    }

    func testTerminalHooksCaptureOnlyBoundedJumpMetadata() {
        for descriptor in LocalAgentRegistry.all where descriptor.standalonePluginRenderer == nil {
            let command = LocalHooksInstaller(descriptor).hookCommand()
            if descriptor.usesTerminalFallback {
                XCTAssertTrue(command.contains("X-Dev-Island-Terminal-Bundle"), descriptor.source)
                XCTAssertTrue(command.contains("X-Dev-Island-Terminal-Program"), descriptor.source)
                XCTAssertTrue(command.contains("X-Dev-Island-TTY"), descriptor.source)
                XCTAssertTrue(command.contains("X-Dev-Island-Tmux-Pane"), descriptor.source)
                XCTAssertFalse(command.contains("env |"), descriptor.source)
                XCTAssertFalse(command.contains("eval "), descriptor.source)
            } else {
                XCTAssertFalse(command.contains("X-Dev-Island-Terminal-Bundle"), descriptor.source)
            }
        }
    }

    func testStandalonePluginDescriptorUsesNoCommandHookSurface() {
        let descriptor = LocalAgentDescriptor.openCode
        guard case .standaloneJavaScriptPlugin = descriptor.hookEntryStyle else {
            return XCTFail("OpenCode must use its isolated plugin file")
        }
        XCTAssertNotNil(descriptor.standalonePluginRenderer)
        XCTAssertTrue(descriptor.actionHookEvents.isEmpty)
        XCTAssertNil(descriptor.decodeActionRequest)
        XCTAssertNil(descriptor.encodeActionResponse)
        XCTAssertEqual(descriptor.configPath, "~/.config/opencode/plugins/dev-island.js")
        XCTAssertEqual(descriptor.endpointPath, "/hooks/opencode")
    }

    func testInstallRejectsUnreadableConfigWithoutChangingBytes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-framework-invalid-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("settings.json")
        let original = Data(#"{"hooks": [this is not valid JSON]}"#.utf8)
        try original.write(to: url)

        XCTAssertThrowsError(
            try LocalHooksInstaller(.claudeCode).install(configURL: url)
        )
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testInstallRejectsNonObjectRootWithoutChangingBytes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-framework-root-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("settings.json")
        let original = Data(#"["valid", "json", "wrong", "shape"]"#.utf8)
        try original.write(to: url)

        XCTAssertThrowsError(
            try LocalHooksInstaller(.claudeCode).install(configURL: url)
        )
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testInstallRejectsIncompatibleHookContainersWithoutChangingBytes() throws {
        let cases: [[String: Any]] = [
            ["theme": "dark", "hooks": "not-an-object"],
            ["theme": "dark", "hooks": ["Stop": ["command": "./notify.sh"]]],
        ]

        for root in cases {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("island-framework-shape-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("settings.json")
            let original = try JSONSerialization.data(withJSONObject: root)
            try original.write(to: url)

            XCTAssertThrowsError(
                try LocalHooksInstaller(.claudeCode).install(configURL: url)
            )
            XCTAssertEqual(try Data(contentsOf: url), original)
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

    func testConnectorRetainsLastValidatedJumpContextAcrossSparseEvents() async throws {
        let connector = LocalAgentConnector(descriptor: .claudeCode)
        let context = try XCTUnwrap(SessionJumpContext(
            terminalProgram: "ghostty",
            tmuxEnvironment: "/private/tmp/tmux-501/default,8,0",
            tmuxPane: "%4"
        ))
        _ = await connector.apply(LocalAgentEvent(
            sessionId: "s1",
            cwd: "/w/Proj",
            jumpContext: context,
            action: .running
        ))

        let tasks = await connector.apply(LocalAgentEvent(
            sessionId: "s1",
            action: .waiting(phase: "Needs input", message: nil)
        ))

        XCTAssertEqual(tasks.first?.jumpContext, context)
    }

    func testStaleWaitingEventFromFinishedGenerationIsDropped() async {
        // Future descriptors may emit versioned waiting events; the guard
        // must cover them the same way it covers prompts and stops.
        let connector = LocalAgentConnector(descriptor: .cursor)
        _ = await connector.apply(LocalAgentEvent(
            sessionId: "s1", generationId: "g1", action: .running))
        _ = await connector.apply(LocalAgentEvent(
            sessionId: "s1", generationId: "g1", action: .completed(phase: nil)))
        let tasks = await connector.apply(LocalAgentEvent(
            sessionId: "s1", generationId: "g1",
            action: .waiting(phase: "Needs input", message: nil)))
        XCTAssertEqual(tasks[0].status, .completed, "a finished generation's waiting event is stale")
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

    func testSessionCapacityPrefersWaitingAndRejectsNewestWaitingOverflow() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var table = LocalSessionTable(source: "codex", displayName: "Codex")
        for index in 0..<LocalSessionTable.maximumSessions {
            table.upsert(
                id: "running-\(index)",
                cwd: nil,
                jumpContext: nil,
                now: t0.addingTimeInterval(TimeInterval(index))
            ) { $0.status = .running }
        }

        table.upsert(
            id: "needs-attention",
            cwd: nil,
            jumpContext: nil,
            now: t0.addingTimeInterval(10_000)
        ) { $0.status = .waiting }

        XCTAssertEqual(table.snapshot().count, LocalSessionTable.maximumSessions)
        XCTAssertFalse(table.contains(id: "running-0"))
        XCTAssertTrue(table.contains(id: "needs-attention"))

        var waitingOnly = LocalSessionTable(source: "codex", displayName: "Codex")
        for index in 0..<LocalSessionTable.maximumSessions {
            waitingOnly.upsert(
                id: "waiting-\(index)",
                cwd: nil,
                jumpContext: nil,
                now: t0
            ) { $0.status = .waiting }
        }
        waitingOnly.upsert(
            id: "waiting-overflow",
            cwd: nil,
            jumpContext: nil,
            now: t0
        ) { $0.status = .waiting }

        XCTAssertEqual(waitingOnly.snapshot().count, LocalSessionTable.maximumSessions)
        XCTAssertTrue(waitingOnly.contains(id: "waiting-0"))
        XCTAssertTrue(waitingOnly.contains(id: "waiting-127"))
        XCTAssertFalse(waitingOnly.contains(id: "waiting-overflow"))
    }
}
