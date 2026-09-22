import IslandCore
import XCTest
@testable import IslandAppLib

final class LocalAgentReportingPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(_ agents: [(String, String, LocalAgentReportingState)]) -> LocalAgentReportingSnapshot {
        LocalAgentReportingSnapshot(
            agents: agents.map {
                LocalAgentReportingHealth(source: $0.0, displayName: $0.1, hookState: .configured, state: $0.2)
            },
            observedAt: now
        )
    }

    func testNoNoticeWhenEveryAgentReportsOrNothingIsKnown() {
        XCTAssertNil(LocalAgentReportingPresentation.notice(nil, language: .english))
        XCTAssertNil(LocalAgentReportingPresentation.notice(
            snapshot([("codex", "Codex", .reporting), ("claude-code", "Claude Code", .idle), ("cursor", "Cursor", .unknown)]),
            language: .english
        ))
    }

    func testCodexNoticePointsAtTheReviewCommandInBothLanguages() {
        let notice = LocalAgentReportingPresentation.notice(
            snapshot([("claude-code", "Claude Code", .notReporting), ("codex", "Codex", .notReporting)]),
            language: .english
        )
        XCTAssertEqual(notice?.source, "codex", "Codex first: its trust gate is the common cause")
        XCTAssertEqual(notice?.title, "No recent hook events from Codex")
        XCTAssertEqual(notice?.hint, "Local activity was detected. Check task monitoring and approval authorization separately.")

        let chinese = LocalAgentReportingPresentation.notice(
            snapshot([("codex", "Codex", .notReporting)]),
            language: .simplifiedChinese
        )
        XCTAssertEqual(chinese?.title, "尚未收到 Codex 的近期 Hook 事件")
        XCTAssertEqual(chinese?.hint, "已检测到本地活动。请分别检查任务监控与审批授权。")
    }

    func testOtherAgentsPointAtSettings() {
        let notice = LocalAgentReportingPresentation.notice(
            snapshot([("claude-code", "Claude Code", .notReporting)]),
            language: .english
        )
        XCTAssertEqual(notice?.title, "No recent hook events from Claude Code")
        XCTAssertEqual(notice?.hint, "Local activity was detected. Check whether this connection can send events.")
        let chinese = LocalAgentReportingPresentation.notice(
            snapshot([("claude-code", "Claude Code", .notReporting)]),
            language: .simplifiedChinese
        )
        XCTAssertEqual(chinese?.hint, "已检测到本地活动。请检查此连接能否送达事件。")
    }

    func testVisibleTaskSuppressesStaleNoticeWithoutHidingAnotherAgentsIssue() {
        let health = snapshot([("codex", "Codex", .notReporting), ("claude-code", "Claude Code", .notReporting)])
        XCTAssertEqual(LocalAgentReportingPresentation.notice(
            health, visibleTaskSources: ["codex"], language: .english
        )?.source, "claude-code")
        XCTAssertNil(LocalAgentReportingPresentation.notice(
            health, visibleTaskSources: ["codex", "claude-code"], language: .english
        ))
    }

    func testNoticeCarriesNoPathsOrSessionIdentifiers() {
        let notice = LocalAgentReportingPresentation.notice(
            snapshot([("codex", "Codex", .notReporting)]),
            language: .english
        )
        XCTAssertFalse(notice?.accessibilityLabel.contains("/Users") ?? true)
        XCTAssertFalse(notice?.accessibilityLabel.contains("rollout") ?? true)
    }
}
