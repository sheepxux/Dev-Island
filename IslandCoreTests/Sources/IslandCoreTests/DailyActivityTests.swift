import Foundation
import XCTest
@testable import IslandCore

final class DailyActivityTests: XCTestCase {
    private let noon = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13 UTC

    private func task(
        _ id: String,
        createdAt: Date,
        activeFor seconds: TimeInterval,
        status: TaskStatus = .completed
    ) -> AgentTask {
        AgentTask(
            id: id,
            source: "codex",
            title: "/Users/customer/Private",
            status: status,
            createdAt: createdAt,
            updatedAt: createdAt.addingTimeInterval(seconds),
            taskURL: "file:///Users/customer/Private/"
        )
    }

    func testDayWindowIsHalfOpenLocalCalendarDay() {
        let window = DailyActivitySummary.dayWindow(containing: noon)
        XCTAssertEqual(window.start, Calendar.current.startOfDay(for: noon))
        XCTAssertEqual(window.end.timeIntervalSince(window.start), 86_400, accuracy: 3_700)
        XCTAssertLessThan(window.start, noon)
        XCTAssertGreaterThan(window.end, noon)
    }

    func testSQLiteAggregateCountsOnlySessionsThatStartedToday() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-daily-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sqlite = SQLiteStore(databaseURL: directory.appendingPathComponent("tasks.sqlite"))
        try await sqlite.open()

        let window = DailyActivitySummary.dayWindow(containing: noon)
        try await sqlite.insertOrReplace(tasks: [
            task("today-a", createdAt: window.start.addingTimeInterval(60), activeFor: 600),
            task("today-b", createdAt: noon, activeFor: 90, status: .running),
            task("clock-skew", createdAt: noon, activeFor: -30),
            task("yesterday", createdAt: window.start.addingTimeInterval(-1), activeFor: 3_600),
            task("tomorrow", createdAt: window.end, activeFor: 3_600),
        ])

        let aggregate = try await sqlite.dailyActivity(dayStart: window.start, dayEnd: window.end)
        XCTAssertEqual(aggregate.sessionCount, 3)
        XCTAssertEqual(aggregate.activeSeconds, 690, accuracy: 0.001)

        let empty = try await sqlite.dailyActivity(dayStart: window.end, dayEnd: window.start)
        XCTAssertEqual(empty, .init(sessionCount: 0, activeSeconds: 0))
    }

    func testDecisionCounterBucketsByLocalDayAndCaps() {
        let suite = "DailyActivityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let counter = DailyDecisionCounter(defaults: defaults)

        XCTAssertEqual(counter.approvalCount(at: noon), 0)
        XCTAssertEqual(counter.recordApproval(at: noon), 1)
        XCTAssertEqual(counter.recordApproval(at: noon.addingTimeInterval(120)), 2)

        let tomorrow = DailyActivitySummary.dayWindow(containing: noon).end.addingTimeInterval(1)
        XCTAssertEqual(counter.approvalCount(at: tomorrow), 0, "a new day starts from zero")
        XCTAssertEqual(counter.recordApproval(at: tomorrow), 1)
        XCTAssertEqual(counter.approvalCount(at: noon), 0, "the old bucket is gone")

        defaults.set(DailyDecisionCounter.maximumCount + 50, forKey: DailyDecisionCounter.approvalCountKey)
        XCTAssertEqual(counter.approvalCount(at: tomorrow), DailyDecisionCounter.maximumCount)
        XCTAssertEqual(counter.recordApproval(at: tomorrow), DailyDecisionCounter.maximumCount)

        defaults.set(-7, forKey: DailyDecisionCounter.approvalCountKey)
        XCTAssertEqual(counter.approvalCount(at: tomorrow), 0)

        counter.reset()
        XCTAssertEqual(counter.approvalCount(at: tomorrow), 0)
        XCTAssertNil(defaults.object(forKey: DailyDecisionCounter.dayStartKey))
    }

    @MainActor
    func testTaskStoreRefreshesTodayActivityAndClearHistoryResetsIt() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-daily-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sqlite = SQLiteStore(databaseURL: directory.appendingPathComponent("tasks.sqlite"))
        try await sqlite.open()
        let store = TaskStore.maintenanceTestStore(sqliteStore: sqlite, tasks: [])

        let now = Date.now
        await store.applyLocalSnapshot(source: "codex", [
            task("live", createdAt: now.addingTimeInterval(-300), activeFor: 300, status: .running),
        ])
        let refreshed = await store.refreshTodayActivity(now: now)
        XCTAssertTrue(refreshed)
        let summary = try XCTUnwrap(store.todayActivity)
        XCTAssertEqual(summary.sessionCount, 1)
        XCTAssertEqual(summary.activeSeconds, 300, accuracy: 0.001)
        XCTAssertFalse(summary.isEmpty)

        let cleared = await store.clearStoredTaskHistory()
        XCTAssertTrue(cleared)
        XCTAssertNil(store.todayActivity)
        let refreshedAgain = await store.refreshTodayActivity(now: now)
        XCTAssertTrue(refreshedAgain)
        XCTAssertEqual(store.todayActivity?.sessionCount, 0)
    }

    func testSummaryClampsCorruptInputs() {
        let summary = DailyActivitySummary(
            dayStart: noon,
            sessionCount: -3,
            activeSeconds: .nan,
            approvalCount: -1
        )
        XCTAssertEqual(summary.sessionCount, 0)
        XCTAssertEqual(summary.activeSeconds, 0)
        XCTAssertEqual(summary.approvalCount, 0)
        XCTAssertTrue(summary.isEmpty)
    }
}
