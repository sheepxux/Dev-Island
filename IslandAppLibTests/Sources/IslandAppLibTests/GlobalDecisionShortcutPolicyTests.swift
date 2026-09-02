import IslandCore
import XCTest
@testable import IslandAppLib

final class GlobalDecisionShortcutPolicyTests: XCTestCase {
    private func permission(_ session: String) -> AgentActionRequest {
        AgentActionRequest(
            source: "codex",
            sessionId: session,
            kind: .permission,
            title: "Run tests",
            message: "swift test"
        )
    }

    func testEmptyQueueRevealsIslandWithoutTarget() {
        XCTAssertEqual(
            GlobalDecisionShortcutPolicy.action(for: .allow, in: []),
            .revealIsland(nil)
        )
        XCTAssertEqual(
            GlobalDecisionShortcutPolicy.action(for: .deny, in: []),
            .revealIsland(nil)
        )
    }

    func testFrontPermissionRequestOwnsBothChords() {
        let first = permission("a")
        let second = permission("b")

        XCTAssertEqual(
            GlobalDecisionShortcutPolicy.action(for: .allow, in: [first, second]),
            .respond(requestID: first.id, decision: .allow)
        )
        XCTAssertEqual(
            GlobalDecisionShortcutPolicy.action(for: .deny, in: [first, second]),
            .respond(requestID: first.id, decision: .deny)
        )
    }

    func testQuestionAndPlanReviewAreNeverDecidedBlindly() {
        let question = AgentActionRequest(
            source: "claude-code",
            sessionId: "q",
            kind: .question,
            title: "Choose",
            message: "Pick one",
            questions: [
                AgentQuestion(
                    question: "Tone?",
                    header: "Tone",
                    options: [AgentQuestionOption(label: "Warm")]
                ),
            ]
        )
        let plan = AgentActionRequest(
            source: "claude-code",
            sessionId: "p",
            kind: .planReview,
            title: "Review plan",
            message: "Ready",
            planReview: AgentPlanReview(
                markdown: "# Plan",
                originalInputJSON: Data("{}".utf8)
            )
        )

        for shortcut in GlobalDecisionShortcut.allCases {
            XCTAssertEqual(
                GlobalDecisionShortcutPolicy.action(for: shortcut, in: [question, permission("later")]),
                .revealIsland(question.taskIdentity)
            )
            XCTAssertEqual(
                GlobalDecisionShortcutPolicy.action(for: shortcut, in: [plan]),
                .revealIsland(plan.taskIdentity)
            )
        }
    }

    func testChordsAreDistinctAndUseAllThreeModifiers() {
        let keyCodes = Set(GlobalDecisionShortcut.allCases.map(\.carbonKeyCode))
        XCTAssertEqual(keyCodes.count, GlobalDecisionShortcut.allCases.count)
        XCTAssertEqual(Set(GlobalDecisionShortcut.allCases.map(\.displayString)).count, 2)
        for glyphs in GlobalDecisionShortcut.allCases.map(\.displayString) {
            XCTAssertTrue(glyphs.hasPrefix("⌃⌥⌘"))
        }
        XCTAssertEqual(GlobalDecisionShortcut.allow.decision, .allow)
        XCTAssertEqual(GlobalDecisionShortcut.deny.decision, .deny)
    }

    func testPreferenceDefaultsOnAndFollowsUserOverride() {
        let suite = "GlobalDecisionShortcutPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        GlobalDecisionShortcutPreferences.registerDefaults(in: defaults)
        XCTAssertTrue(GlobalDecisionShortcutPreferences.isEnabled(in: defaults))

        defaults.set(false, forKey: GlobalDecisionShortcutPreferences.enabledKey)
        XCTAssertFalse(GlobalDecisionShortcutPreferences.isEnabled(in: defaults))
    }
}
