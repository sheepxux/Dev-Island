import XCTest
@testable import IslandAppLib
import IslandCore

final class LocalLiveReadinessPresentationTests: XCTestCase {
    func testCheckStateAcceptsOnlyItsActiveResult() throws {
        var state = LocalLiveReadinessCheckState()
        let checkID = try XCTUnwrap(state.begin())
        XCTAssertTrue(state.isChecking)
        XCTAssertNil(state.begin())

        let result = snapshot(
            listener: .listening,
            claude: (.verified, .connected, .notRequired),
            codex: (.verified, .connected, .verified)
        )
        XCTAssertFalse(state.accept(result, for: UUID()))
        XCTAssertTrue(state.isChecking)
        XCTAssertNil(state.snapshot)

        XCTAssertTrue(state.accept(result, for: checkID))
        XCTAssertFalse(state.isChecking)
        XCTAssertEqual(state.snapshot, result)
    }

    func testSingleAgentCheckDoesNotAskForAnUnrelatedTool() throws {
        var state = LocalLiveReadinessCheckState()
        let checkID = try XCTUnwrap(state.begin(source: "codex"))
        let result = snapshot(
            listener: .listening,
            claude: (.unavailable, .disconnected, .notRequired),
            codex: (.verified, .connected, .verified)
        )
        XCTAssertTrue(state.accept(result, for: checkID))
        XCTAssertEqual(state.snapshot?.agents.map(\.source), ["codex"])
        let content = LocalLiveReadinessPresentation.content(snapshot: state.snapshot, isChecking: false, language: .english)
        XCTAssertEqual(content.tone, .ready)
        XCTAssertTrue(content.detail.contains("Codex"))
        XCTAssertFalse(content.detail.contains("Claude"))
        XCTAssertTrue(content.detail.contains("real request"))
        state.invalidate()
        XCTAssertNil(state.source)
    }

    func testInvalidationRejectsLateResultAndAllowsFreshCheck() throws {
        let previousResult = snapshot(
            listener: .listening,
            claude: (.verified, .connected, .notRequired),
            codex: (.verified, .connected, .verified)
        )
        var state = LocalLiveReadinessCheckState(snapshot: previousResult)
        let staleCheckID = try XCTUnwrap(state.begin())
        state.invalidate()
        XCTAssertNil(state.snapshot)

        let freshCheckID = try XCTUnwrap(state.begin())
        XCTAssertNotEqual(freshCheckID, staleCheckID)

        let staleResult = snapshot(
            listener: .unavailable,
            claude: (.verified, .updateRequired, .notRequired),
            codex: (.verified, .updateRequired, .reviewRequired)
        )
        XCTAssertFalse(state.accept(staleResult, for: staleCheckID))
        XCTAssertNil(state.snapshot)
        XCTAssertTrue(state.isChecking)

        let freshResult = snapshot(
            listener: .listening,
            claude: (.verified, .connected, .notRequired),
            codex: (.verified, .connected, .verified)
        )
        XCTAssertTrue(state.accept(freshResult, for: freshCheckID))
        XCTAssertEqual(state.snapshot, freshResult)
        XCTAssertFalse(state.isChecking)
    }

    func testIdleAndCheckingCopyExplainTheReadOnlyBoundary() {
        XCTAssertEqual(
            LocalLiveReadinessPresentation.content(
                snapshot: nil,
                isChecking: false,
                language: .english
            ),
            .init(
                title: "Live connection check",
                detail: "Verify Claude Code and Codex before your first real approval.",
                tone: .neutral,
                actionCount: 0
            )
        )
        XCTAssertEqual(
            LocalLiveReadinessPresentation.content(
                snapshot: nil,
                isChecking: true,
                language: .english
            ).detail,
            "Checking this Mac without changing Agent configuration."
        )
    }

    func testReadyCopyRequiresBothAgentsAndListener() {
        let content = LocalLiveReadinessPresentation.content(
            snapshot: snapshot(
                listener: .listening,
                claude: (.verified, .connected, .notRequired),
                codex: (.verified, .connected, .verified)
            ),
            isChecking: false,
            language: .english
        )

        XCTAssertEqual(content.title, "Local setup checks passed")
        XCTAssertEqual(content.tone, .ready)
        XCTAssertEqual(content.actionCount, 0)
    }

    func testListenerAndTwoStaleHooksProduceThreeActionsAndOneNextStep() {
        let content = LocalLiveReadinessPresentation.content(
            snapshot: snapshot(
                listener: .unavailable,
                claude: (.verified, .updateRequired, .notRequired),
                codex: (.verified, .updateRequired, .reviewRequired)
            ),
            isChecking: false,
            language: .english
        )

        XCTAssertEqual(content.title, "3 setup actions remain")
        XCTAssertEqual(content.detail, "The local Agent listener is offline.")
        XCTAssertEqual(content.tone, .attention)
    }

    func testUpdateGuidanceCombinesAgentNamesWithoutRepeatingRows() {
        let content = LocalLiveReadinessPresentation.content(
            snapshot: snapshot(
                listener: .listening,
                claude: (.verified, .updateRequired, .notRequired),
                codex: (.verified, .updateRequired, .reviewRequired)
            ),
            isChecking: false,
            language: .english
        )

        XCTAssertEqual(content.title, "2 setup actions remain")
        XCTAssertEqual(content.detail, "Update Claude Code and Codex below.")
    }

    func testCodexTrustGuidanceNamesTheDocumentedReviewSurface() {
        let content = LocalLiveReadinessPresentation.content(
            snapshot: snapshot(
                listener: .listening,
                claude: (.verified, .connected, .notRequired),
                codex: (.verified, .configured, .reviewRequired)
            ),
            isChecking: false,
            language: .english
        )

        XCTAssertEqual(content.title, "1 setup action remains")
        XCTAssertEqual(
            content.detail,
            "For manual setup, use /hooks in Codex CLI to trust only Dev Island entries. "
                + "Otherwise, use Review and authorize hooks below."
        )
    }

    func testSimplifiedChineseCodexTrustGuidanceExplainsTheBypassRisk() {
        let content = LocalLiveReadinessPresentation.content(
            snapshot: snapshot(
                listener: .listening,
                claude: (.verified, .connected, .notRequired),
                codex: (.verified, .configured, .reviewRequired)
            ),
            isChecking: false,
            language: .simplifiedChinese
        )

        XCTAssertEqual(content.title, "还需完成 1 项设置")
        XCTAssertEqual(
            content.detail,
            "手动设置时，请在 Codex CLI 中输入 /hooks，仅信任 Dev Island 条目；"
                + "也可以使用下方的“审阅并授权 Hook”。"
        )
    }

    func testFailedVersionCheckAsksForRetryWithoutClaimingCompatibilityReview() {
        let content = LocalLiveReadinessPresentation.content(
            snapshot: snapshot(
                listener: .listening,
                claude: (.checkFailed, .connected, .notRequired),
                codex: (.verified, .connected, .verified)
            ),
            isChecking: false,
            language: .english
        )

        XCTAssertEqual(content.title, "Live check incomplete")
        XCTAssertEqual(content.detail, "Couldn't verify Claude Code right now.")
        XCTAssertEqual(content.tone, .retry)
        XCTAssertEqual(content.actionCount, 0)
    }

    func testSimplifiedChineseFailedVersionCheckKeepsRetryMeaning() {
        let content = LocalLiveReadinessPresentation.content(
            snapshot: snapshot(
                listener: .listening,
                claude: (.verified, .connected, .notRequired),
                codex: (.checkFailed, .connected, .verified)
            ),
            isChecking: false,
            language: .simplifiedChinese
        )

        XCTAssertEqual(content.title, "实时检查未完成")
        XCTAssertEqual(content.detail, "暂时无法验证 Codex。")
        XCTAssertEqual(content.tone, .retry)
        XCTAssertEqual(content.actionCount, 0)
    }

    func testFailedVersionCheckDoesNotMaskAKnownSetupAction() {
        let content = LocalLiveReadinessPresentation.content(
            snapshot: snapshot(
                listener: .listening,
                claude: (.checkFailed, .connected, .notRequired),
                codex: (.verified, .updateRequired, .reviewRequired)
            ),
            isChecking: false,
            language: .english
        )

        XCTAssertEqual(content.title, "1 setup action remains")
        XCTAssertEqual(content.detail, "Update Codex below.")
        XCTAssertEqual(content.tone, .attention)
        XCTAssertEqual(content.actionCount, 1)
    }

    func testSimplifiedChineseKeepsNamesAndCommandTechnicallyExact() {
        let content = LocalLiveReadinessPresentation.content(
            snapshot: snapshot(
                listener: .listening,
                claude: (.verified, .updateRequired, .notRequired),
                codex: (.verified, .updateRequired, .reviewRequired)
            ),
            isChecking: false,
            language: .simplifiedChinese
        )

        XCTAssertEqual(content.title, "还需完成 2 项设置")
        XCTAssertEqual(content.detail, "请在下方更新 Claude Code 和 Codex。")
    }

    private func snapshot(
        listener: LocalHookListenerReadinessState,
        claude: (
            LocalAgentCLIReadinessState,
            LocalAgentHookConnectionState,
            LocalAgentActivationReadinessState
        ),
        codex: (
            LocalAgentCLIReadinessState,
            LocalAgentHookConnectionState,
            LocalAgentActivationReadinessState
        )
    ) -> LocalLiveReadinessSnapshot {
        .init(listener: listener, agents: [
            .init(source: "claude-code", cli: claude.0, hook: claude.1, activation: claude.2),
            .init(source: "codex", cli: codex.0, hook: codex.1, activation: codex.2),
        ])
    }
}
