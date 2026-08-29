import XCTest
@testable import IslandAppLib
import IslandCore

final class StatusMenuPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_787_710_400)

    func testHeadlineUsesAttentionPriorityAndCorrectGrammar() {
        let tasks = [
            task("running", status: .running),
            task("waiting-one", status: .waiting),
            task("waiting-two", status: .waiting),
            task("failed", status: .failed),
        ]

        XCTAssertEqual(
            StatusMenuPresentation.headline(tasks: tasks, now: now, language: .english),
            "2 sessions need attention"
        )
        XCTAssertEqual(
            StatusMenuPresentation.headline(
                tasks: [task("waiting", status: .waiting)],
                now: now,
                language: .english
            ),
            "1 session needs attention"
        )
    }

    func testHeadlineLetsStaleCompletionYieldToRunningAndHandlesIdle() {
        let oldCompletion = AgentTask(
            id: "completed",
            source: "codex",
            title: "private",
            status: .completed,
            createdAt: now.addingTimeInterval(-120),
            updatedAt: now.addingTimeInterval(
                -TaskPresentationPolicy.recentResultDuration - 1
            ),
            taskURL: ""
        )

        XCTAssertEqual(
            StatusMenuPresentation.headline(
                tasks: [oldCompletion, task("running", status: .running)],
                now: now,
                language: .english
            ),
            "1 session running"
        )
        XCTAssertEqual(
            StatusMenuPresentation.headline(tasks: [], now: now, language: .english),
            "Dev Island is running"
        )
    }

    func testOverviewKeepsAttentionPriorityAndAddsTotalSessionCount() {
        let tasks = [
            task("running", status: .running),
            task("waiting", status: .waiting),
            task("failed", status: .failed),
        ]

        XCTAssertEqual(
            StatusMenuPresentation.overview(
                tasks: tasks,
                now: now,
                language: .english
            ),
            "1 session needs attention · 3 sessions total"
        )
        XCTAssertEqual(
            StatusMenuPresentation.overview(
                tasks: tasks,
                now: now,
                language: .simplifiedChinese
            ),
            "1 个会话需要关注 · 共 3 个会话"
        )
        XCTAssertEqual(
            StatusMenuPresentation.overview(
                tasks: [],
                now: now,
                language: .english
            ),
            "Dev Island is running"
        )
    }

    func testSnapshotAccessibilityValueIsLowCardinalityAndPrivate() {
        let privateTask = AgentTask(
            id: "secret-session-id",
            source: "codex",
            title: "/Users/customer/PrivateProject",
            status: .waiting,
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now,
            taskURL: ""
        )
        let privateReason = "token=private-provider-detail"
        let snapshot = StatusMenuPresentation.snapshot(
            tasks: [privateTask],
            localAgentStatus: .listening,
            apiKeyStatus: .valid,
            connectionStatus: .degraded(reason: privateReason),
            now: now,
            language: .english
        )

        XCTAssertEqual(
            snapshot.accessibilityValue,
            "1 session needs attention · 1 session total, Local agents: Ready, Manus: Polling only"
        )
        for secret in [privateTask.id, privateTask.title, privateReason] {
            XCTAssertFalse(snapshot.accessibilityValue.contains(secret))
        }
    }

    func testNextRefreshDateUsesOnlyEarliestFutureCompletionExpiry() {
        let earlier = AgentTask(
            id: "earlier",
            source: "codex",
            title: "private",
            status: .completed,
            createdAt: now.addingTimeInterval(-100),
            updatedAt: now.addingTimeInterval(-2),
            taskURL: ""
        )
        let later = AgentTask(
            id: "later",
            source: "claude-code",
            title: "private",
            status: .completed,
            createdAt: now.addingTimeInterval(-100),
            updatedAt: now.addingTimeInterval(-1),
            taskURL: ""
        )
        let expired = AgentTask(
            id: "expired",
            source: "codex",
            title: "private",
            status: .completed,
            createdAt: now.addingTimeInterval(-100),
            updatedAt: now.addingTimeInterval(
                -TaskPresentationPolicy.recentResultDuration - 1
            ),
            taskURL: ""
        )

        XCTAssertEqual(
            StatusMenuPresentation.nextRefreshDate(
                tasks: [later, task("running", status: .running), expired, earlier],
                now: now
            ),
            earlier.updatedAt.addingTimeInterval(
                TaskPresentationPolicy.recentResultDuration
            )
        )
        XCTAssertNil(
            StatusMenuPresentation.nextRefreshDate(
                tasks: [expired, task("running", status: .running)],
                now: now
            )
        )
    }

    func testLocalAgentHealthUsesCompactTransportOnlyCopy() {
        XCTAssertEqual(
            StatusMenuPresentation.localAgents(.starting, language: .english),
            "Local agents: Starting…"
        )
        XCTAssertEqual(
            StatusMenuPresentation.localAgents(.listening, language: .english),
            "Local agents: Ready"
        )
        XCTAssertEqual(
            StatusMenuPresentation.localAgents(
                .retrying(attempt: 2, limit: 5),
                language: .english
            ),
            "Local agents: Reconnecting (2/5)"
        )
        XCTAssertEqual(
            StatusMenuPresentation.localAgents(.unavailable, language: .english),
            "Local agents: Offline"
        )
        XCTAssertEqual(
            StatusMenuPresentation.localAgents(.stopped, language: .english),
            "Local agents: Stopped"
        )
    }

    func testManusAndUpdateCopyNeverExposeRawReason() {
        let secret = "token=/Users/customer/private-project"
        XCTAssertEqual(
            StatusMenuPresentation.manus(
                apiKeyStatus: .valid,
                connectionStatus: .degraded(reason: secret),
                language: .english
            ),
            "Manus: Polling only"
        )
        XCTAssertFalse(
            StatusMenuPresentation.manus(
                apiKeyStatus: .valid,
                connectionStatus: .degraded(reason: secret),
                language: .english
            ).contains(secret)
        )
        XCTAssertEqual(
            StatusMenuPresentation.manus(
                apiKeyStatus: .invalid,
                connectionStatus: .connected,
                language: .english
            ),
            "Manus: Reconnect required"
        )
        XCTAssertEqual(
            StatusMenuPresentation.updateHelp(
                status: .unavailable,
                canCheckForUpdates: false,
                language: .english
            ),
            "Available in signed release builds."
        )
        XCTAssertNil(
            StatusMenuPresentation.updateHelp(
                status: .ready,
                canCheckForUpdates: true,
                language: .english
            )
        )
        XCTAssertEqual(
            StatusMenuPresentation.updateHelp(
                status: .failed,
                canCheckForUpdates: false,
                language: .english
            ),
            "Update service couldn't start. Restart Dev Island to try again."
        )
        XCTAssertEqual(
            StatusMenuPresentation.updateHelp(
                status: .checking,
                canCheckForUpdates: false,
                language: .simplifiedChinese
            ),
            "正在检查更新…"
        )
    }

    func testMenuHealthCopyFollowsExplicitSimplifiedChineseLanguage() {
        XCTAssertEqual(
            StatusMenuPresentation.headline(
                tasks: [task("waiting", status: .waiting)],
                now: now,
                language: .simplifiedChinese
            ),
            "1 个会话需要关注"
        )
        XCTAssertEqual(
            StatusMenuPresentation.localAgents(
                .retrying(attempt: 2, limit: 5),
                language: .simplifiedChinese
            ),
            "本地 Agent：正在重新连接（2/5）"
        )
        XCTAssertEqual(
            StatusMenuPresentation.manus(
                apiKeyStatus: .valid,
                connectionStatus: .degraded(reason: "private"),
                language: .simplifiedChinese
            ),
            "Manus：仅轮询"
        )
    }

    private func task(_ id: String, status: TaskStatus) -> AgentTask {
        AgentTask(
            id: id,
            source: "codex",
            title: "private-\(id)",
            status: status,
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now,
            taskURL: ""
        )
    }
}
