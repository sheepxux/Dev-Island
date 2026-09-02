import IslandCore
import XCTest
@testable import IslandAppLib

final class DailyActivityPresentationTests: XCTestCase {
    private let dayStart = Date(timeIntervalSince1970: 1_700_000_000)

    private func summary(sessions: Int, seconds: TimeInterval, approvals: Int) -> DailyActivitySummary {
        DailyActivitySummary(
            dayStart: dayStart,
            sessionCount: sessions,
            activeSeconds: seconds,
            approvalCount: approvals
        )
    }

    func testEmptyDayHidesTheLine() {
        XCTAssertNil(DailyActivityPresentation.summaryLine(nil, language: .english))
        XCTAssertNil(DailyActivityPresentation.summaryLine(
            summary(sessions: 0, seconds: 0, approvals: 0),
            language: .english
        ))
    }

    func testFullLineInEnglishAndSimplifiedChinese() {
        let full = summary(sessions: 14, seconds: 2 * 3_600 + 10 * 60 + 30, approvals: 3)
        XCTAssertEqual(
            DailyActivityPresentation.summaryLine(full, language: .english),
            "Today: 14 sessions · 3 approvals · 2h 10m of agent time"
        )
        XCTAssertEqual(
            DailyActivityPresentation.summaryLine(full, language: .simplifiedChinese),
            "今天：14 个会话 · 3 次审批 · Agent 运行 2 小时 10 分钟"
        )
    }

    func testSingularAndApprovalFreeVariants() {
        let single = summary(sessions: 1, seconds: 45, approvals: 1)
        XCTAssertEqual(
            DailyActivityPresentation.summaryLine(single, language: .english),
            "Today: 1 session · 1 approval · under a minute of agent time"
        )
        let noApprovals = summary(sessions: 2, seconds: 25 * 60, approvals: 0)
        XCTAssertEqual(
            DailyActivityPresentation.summaryLine(noApprovals, language: .english),
            "Today: 2 sessions · 25m of agent time"
        )
        XCTAssertEqual(
            DailyActivityPresentation.summaryLine(noApprovals, language: .simplifiedChinese),
            "今天：2 个会话 · Agent 运行 25 分钟"
        )
    }

    func testLineNeverCarriesSessionOrProjectContent() {
        let line = DailyActivityPresentation.summaryLine(
            summary(sessions: 5, seconds: 100, approvals: 2),
            language: .english
        ) ?? ""
        XCTAssertFalse(line.contains("/"))
        XCTAssertFalse(line.contains("codex"))
    }
}
