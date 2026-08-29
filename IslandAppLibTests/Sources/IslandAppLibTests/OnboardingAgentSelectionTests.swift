import XCTest
@testable import IslandAppLib
import IslandCore

final class OnboardingAgentSelectionTests: XCTestCase {
    func testBoundedWelcomeSelectionNeverLetsPreviewDisplaceStableConnector() {
        let selection = OnboardingAgentSelection.descriptors(
            from: LocalAgentRegistry.all
        )
        let selectedSources = selection.map(\.source)
        let stableSources = LocalAgentRegistry.all
            .filter { $0.releaseStage == .stable }
            .map(\.source)

        XCTAssertEqual(selection.count, OnboardingAgentSelection.maximumLocalAgents)
        for source in stableSources {
            XCTAssertTrue(selectedSources.contains(source), source)
        }
        XCTAssertEqual(
            selectedSources,
            [
                "claude-code", "codex", "cursor", "gemini-cli",
                "qwen-code", "copilot-cli", "kimi-code",
            ]
        )
        XCTAssertFalse(
            selectedSources.contains("opencode"),
            "OpenCode remains discoverable in complete Settings while Preview"
        )
    }

    func testBulkUpdatePlanIncludesOnlyShownAgentsThatNeedRefresh() {
        let selection = OnboardingAgentSelection.descriptors(
            from: LocalAgentRegistry.all
        )
        let states: [String: LocalAgentHookConnectionState] = [
            "claude-code": .updateRequired,
            "codex": .connected,
            "cursor": .disconnected,
            "gemini-cli": .updateRequired,
            "opencode": .updateRequired,
        ]

        XCTAssertEqual(
            OnboardingAgentSelection.descriptorsNeedingUpdate(
                from: selection,
                states: states
            ).map(\.source),
            ["claude-code", "gemini-cli"]
        )
    }

    func testConnectionRefreshIsLatestWins() {
        var state = OnboardingConnectionOperationState()
        let first = UUID()
        let second = UUID()

        XCTAssertEqual(state.beginRefresh(id: first), first)
        XCTAssertEqual(state.beginRefresh(id: second), second)
        XCTAssertFalse(state.completeRefresh(id: first))
        XCTAssertTrue(state.completeRefresh(id: second))
        XCTAssertFalse(state.isBusy)
    }

    func testMutationSupersedesRefreshAndOwnsAllWorkingSources() {
        var state = OnboardingConnectionOperationState()
        let refresh = UUID()
        let mutation = UUID()
        let sources: Set<String> = ["claude-code", "codex"]

        XCTAssertEqual(state.beginRefresh(id: refresh), refresh)
        XCTAssertEqual(
            state.beginMutation(sources: sources, isBulk: true, id: mutation),
            mutation
        )
        XCTAssertFalse(state.completeRefresh(id: refresh))
        XCTAssertEqual(state.workingSources, sources)
        XCTAssertTrue(state.isBulkUpdating)
        XCTAssertNil(
            state.beginMutation(
                sources: ["cursor"],
                isBulk: false,
                id: UUID()
            )
        )
        XCTAssertNil(state.beginRefresh(id: UUID()))
        XCTAssertTrue(state.completeMutation(id: mutation))
        XCTAssertTrue(state.workingSources.isEmpty)
        XCTAssertFalse(state.isBulkUpdating)
        XCTAssertFalse(state.isBusy)
    }

    func testDepartedWelcomeRejectsLateMutationResult() {
        var state = OnboardingConnectionOperationState()
        let mutation = UUID()

        XCTAssertEqual(
            state.beginMutation(
                sources: ["claude-code"],
                isBulk: false,
                id: mutation
            ),
            mutation
        )
        state.invalidate()

        XCTAssertFalse(state.completeMutation(id: mutation))
        XCTAssertTrue(state.workingSources.isEmpty)
        XCTAssertFalse(state.isBusy)
    }

    func testMutationClassificationRequiresFinalReadBack() {
        let snapshot = hookSnapshot([
            ("claude-code", .connected),
            ("codex", .configured),
            ("cursor", .updateRequired),
            ("gemini-cli", .connected),
        ])

        let outcome = OnboardingConnectionWorker.classifyMutation(
            targetSources: [
                "claude-code", "codex", "cursor", "gemini-cli", "missing",
            ],
            writeFailedSources: ["gemini-cli"],
            snapshot: snapshot
        )

        XCTAssertEqual(
            outcome.failedSources,
            ["cursor", "gemini-cli", "missing"]
        )
        XCTAssertEqual(outcome.snapshot, snapshot)
    }

    private func hookSnapshot(
        _ states: [(String, LocalAgentHookConnectionState)]
    ) -> LocalAgentHookHealthSnapshot {
        LocalAgentHookHealthSnapshot(
            agents: states.map { source, state in
                LocalAgentHookConnection(
                    source: source,
                    displayName: source,
                    state: state
                )
            }
        )
    }
}
