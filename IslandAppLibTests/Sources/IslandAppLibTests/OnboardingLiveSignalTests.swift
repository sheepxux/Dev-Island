import XCTest
@testable import IslandAppLib
import IslandCore

final class OnboardingLiveSignalTests: XCTestCase {
    private let selected: Set<String> = ["claude-code", "codex"]

    func testWaitingIgnoresSessionsFromUnselectedSources() {
        let state = OnboardingLiveSignalState.waiting
            .advanced(with: [task("cursor", "a", .running)], sources: selected)

        XCTAssertEqual(state, .waiting)
        XCTAssertEqual(
            OnboardingLiveSignalState.waiting.advanced(with: [], sources: selected),
            .waiting
        )
        XCTAssertEqual(
            OnboardingLiveSignalState.waiting.advanced(
                with: [task("claude-code", "a", .running)],
                sources: []
            ),
            .waiting
        )
    }

    func testFirstMatchingSessionLatchesSeen() {
        let running = OnboardingLiveSignalState.waiting.advanced(
            with: [task("cursor", "x", .running), task("codex", "a", .running)],
            sources: selected
        )
        XCTAssertEqual(running, .seen(source: "codex"))

        let waitingForApproval = OnboardingLiveSignalState.waiting.advanced(
            with: [task("claude-code", "a", .waiting)],
            sources: selected
        )
        XCTAssertEqual(waitingForApproval, .seen(source: "claude-code"))
        XCTAssertTrue(waitingForApproval.hasSeenEvent)
    }

    func testSeenAdvancesToCompletedOnlyForItsOwnSource() {
        let seen = OnboardingLiveSignalState.seen(source: "claude-code")

        XCTAssertEqual(
            seen.advanced(
                with: [task("codex", "b", .completed)],
                sources: selected
            ),
            seen
        )
        XCTAssertEqual(
            seen.advanced(
                with: [task("claude-code", "a", .failed)],
                sources: selected
            ),
            seen
        )
        XCTAssertEqual(
            seen.advanced(
                with: [task("claude-code", "a", .completed)],
                sources: selected
            ),
            .completed(source: "claude-code")
        )
    }

    func testAlreadyCompletedSessionLatchesCompletedDirectly() {
        XCTAssertEqual(
            OnboardingLiveSignalState.waiting.advanced(
                with: [task("claude-code", "a", .completed)],
                sources: selected
            ),
            .completed(source: "claude-code")
        )
    }

    func testLatchSurvivesSessionRemovalAndNeverRegresses() {
        // Claude Code's SessionEnd deletes the task moments after Stop; the
        // stage must keep what the user already achieved.
        let seen = OnboardingLiveSignalState.seen(source: "claude-code")
        XCTAssertEqual(seen.advanced(with: [], sources: selected), seen)

        let completed = OnboardingLiveSignalState.completed(source: "claude-code")
        XCTAssertEqual(completed.advanced(with: [], sources: selected), completed)
        XCTAssertEqual(
            completed.advanced(
                with: [task("claude-code", "b", .running)],
                sources: selected
            ),
            completed
        )
        XCTAssertEqual(completed.advanced(with: [], sources: []), completed)
        XCTAssertEqual(completed.source, "claude-code")
    }

    func testRecipeWaitsForTheListenerBeforeSuggestingAnything() {
        for listener: LocalHookServiceStatus in [
            .starting, .stopped, .unavailable, .retrying(attempt: 1, limit: 5),
        ] {
            XCTAssertEqual(
                OnboardingLiveSignalRecipe.resolve(
                    listener: listener,
                    states: ["claude-code": .connected],
                    candidateSources: ["claude-code"]
                ),
                .listenerStarting
            )
        }
    }

    func testRecipePrefersClaudeThenCodexThenCursorThenAnyOther() {
        let sources = ["claude-code", "codex", "cursor", "gemini-cli"]

        XCTAssertEqual(
            resolve(["claude-code": .connected, "codex": .connected], sources),
            .command(source: "claude-code", command: "claude -p \"say hi\"")
        )
        XCTAssertEqual(
            resolve(["codex": .connected, "cursor": .connected], sources),
            .command(source: "codex", command: "codex exec \"say hi\"")
        )
        XCTAssertEqual(
            resolve(["codex": .configured], sources),
            .codexTrust(command: "codex")
        )
        XCTAssertEqual(
            resolve(["cursor": .connected, "gemini-cli": .connected], sources),
            .cursorChat
        )
        XCTAssertEqual(
            resolve(["gemini-cli": .connected], sources),
            .anySession(source: "gemini-cli")
        )
        XCTAssertEqual(
            resolve(["claude-code": .updateRequired, "codex": .disconnected], sources),
            .connectAgent
        )
        XCTAssertEqual(resolve([:], sources), .connectAgent)
    }

    func testSignalSourcesIncludeConnectedAndVendorGatedAgentsOnly() {
        XCTAssertEqual(
            OnboardingLiveSignalRecipe.signalSources(states: [
                "claude-code": .connected,
                "codex": .configured,
                "cursor": .updateRequired,
                "gemini-cli": .disconnected,
            ]),
            ["claude-code", "codex"]
        )
    }

    // MARK: - Helpers

    private func resolve(
        _ states: [String: LocalAgentHookConnectionState],
        _ sources: [String]
    ) -> OnboardingLiveSignalRecipe {
        OnboardingLiveSignalRecipe.resolve(
            listener: .listening,
            states: states,
            candidateSources: sources
        )
    }

    private func task(_ source: String, _ id: String, _ status: TaskStatus) -> AgentTask {
        AgentTask(
            id: id,
            source: source,
            title: "say hi",
            status: status,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            taskURL: ""
        )
    }
}
