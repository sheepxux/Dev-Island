import Foundation
import XCTest
@testable import IslandAppLib
@testable import IslandCore

final class TaskHistoryPresentationTests: XCTestCase {
    func testFilteringUsesTitleAndAgentWithoutExposingSessionIDAsSearchSurface() {
        let tasks = [
            task(id: "secret-id", source: "codex", title: "Refine onboarding", status: .completed),
            task(id: "other", source: "claude-code", title: "Review release", status: .failed),
        ]

        XCTAssertEqual(
            TaskHistoryPresentation.filtered(tasks, query: "onboard", filter: .all).map(\.source),
            ["codex"]
        )
        XCTAssertEqual(
            TaskHistoryPresentation.filtered(tasks, query: "Claude", filter: .all).map(\.source),
            ["claude-code"]
        )
        XCTAssertTrue(
            TaskHistoryPresentation.filtered(tasks, query: "secret-id", filter: .all).isEmpty
        )
    }

    func testStatusFiltersKeepCrossAgentIdentityCollisionsDistinct() {
        let tasks = [
            task(id: "shared", source: "codex", title: "A", status: .running),
            task(id: "shared", source: "cursor", title: "B", status: .waiting),
            task(id: "shared", source: "manus", title: "C", status: .completed),
            task(id: "shared", source: "claude-code", title: "D", status: .failed),
        ]

        XCTAssertEqual(
            Set(TaskHistoryPresentation.filtered(tasks, query: "", filter: .inProgress).map(\.identity)),
            [
                TaskIdentity(source: "codex", id: "shared"),
                TaskIdentity(source: "cursor", id: "shared"),
            ]
        )
        XCTAssertEqual(
            TaskHistoryPresentation.filtered(tasks, query: "", filter: .completed).map(\.source),
            ["manus"]
        )
        XCTAssertEqual(
            TaskHistoryPresentation.filtered(tasks, query: "", filter: .failed).map(\.source),
            ["claude-code"]
        )
    }

    func testHistoricalActiveCopyNeverPretendsAStaleRowIsLive() {
        let running = task(id: "one", source: "codex", title: "A", status: .running)
        let waiting = task(id: "two", source: "claude-code", title: "B", status: .waiting)

        XCTAssertEqual(
            TaskHistoryPresentation.statusLabel(for: running, isLive: false, language: .english),
            "Last seen running"
        )
        XCTAssertEqual(
            TaskHistoryPresentation.statusLabel(for: waiting, isLive: false, language: .english),
            "Last seen waiting"
        )
        XCTAssertEqual(
            TaskHistoryPresentation.statusLabel(for: running, isLive: true, language: .english),
            "Running now"
        )
        XCTAssertEqual(
            TaskHistoryPresentation.statusLabel(for: waiting, isLive: true, language: .english),
            "Waiting now"
        )
    }

    func testSourceNamesUseRegistryAndReadableFallback() {
        XCTAssertEqual(TaskHistoryPresentation.sourceName("gemini-cli"), "Gemini CLI")
        XCTAssertEqual(TaskHistoryPresentation.sourceName("future-agent"), "Future Agent")
    }

    func testRelativeAgeCopyStaysCompactInEnglish() {
        let now = Date(timeIntervalSince1970: 1_700_100_000)

        XCTAssertEqual(
            TaskHistoryPresentation.relativeAgeLabel(
                for: now.addingTimeInterval(-4),
                relativeTo: now,
                language: .english
            ),
            "just now"
        )
        XCTAssertEqual(
            TaskHistoryPresentation.relativeAgeLabel(
                for: now.addingTimeInterval(-42),
                relativeTo: now,
                language: .english
            ),
            "42s ago"
        )
        XCTAssertEqual(
            TaskHistoryPresentation.relativeAgeLabel(
                for: now.addingTimeInterval(-310),
                relativeTo: now,
                language: .english
            ),
            "5m ago"
        )
        XCTAssertEqual(
            TaskHistoryPresentation.relativeAgeLabel(
                for: now.addingTimeInterval(-7_200),
                relativeTo: now,
                language: .english
            ),
            "2h ago"
        )
    }

    func testHistoryPresentationFollowsExplicitSimplifiedChineseLanguage() {
        let now = Date(timeIntervalSince1970: 1_700_100_000)
        let waiting = task(id: "waiting", source: "codex", title: "A", status: .waiting)

        XCTAssertEqual(TaskHistoryFilter.inProgress.label(language: .simplifiedChinese), "进行中")
        XCTAssertEqual(
            TaskHistoryPresentation.statusLabel(
                for: waiting,
                isLive: true,
                language: .simplifiedChinese
            ),
            "正在等待"
        )
        XCTAssertEqual(
            TaskHistoryPresentation.relativeAgeLabel(
                for: now.addingTimeInterval(-310),
                relativeTo: now,
                language: .simplifiedChinese
            ),
            "5 分钟前"
        )
    }

    private func task(
        id: String,
        source: String,
        title: String,
        status: TaskStatus
    ) -> AgentTask {
        AgentTask(
            id: id,
            source: source,
            title: title,
            status: status,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            taskURL: ""
        )
    }
}
