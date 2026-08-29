import XCTest
@testable import IslandAppLib
import IslandCore

final class PanelClockPresentationTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_700_000_000)

    func testRunningAndWaitingTasksNeedTicksWhileTerminalRowsStayStatic() {
        XCTAssertTrue(PanelClockPresentation.taskNeedsLiveTick(.running))
        XCTAssertTrue(PanelClockPresentation.taskNeedsLiveTick(.waiting))
        XCTAssertFalse(PanelClockPresentation.taskNeedsLiveTick(.completed))
        XCTAssertFalse(PanelClockPresentation.taskNeedsLiveTick(.failed))
    }

    func testLiveDurationUsesNowAndFormatsHourBoundary() {
        let task = makeTask(status: .running, updatedOffset: 10)

        XCTAssertEqual(
            PanelClockPresentation.taskDuration(
                for: task,
                at: origin.addingTimeInterval(3_661)
            ),
            "1:01:01"
        )
    }

    func testTerminalDurationFreezesAtTaskUpdateTime() {
        let task = makeTask(status: .completed, updatedOffset: 125)

        XCTAssertEqual(
            PanelClockPresentation.taskDuration(
                for: task,
                at: origin.addingTimeInterval(9_999)
            ),
            "2:05"
        )
    }

    func testDurationNeverBecomesNegativeForClockSkew() {
        let task = makeTask(status: .waiting, updatedOffset: 0)

        XCTAssertEqual(
            PanelClockPresentation.taskDuration(
                for: task,
                at: origin.addingTimeInterval(-20)
            ),
            "0:00"
        )
    }

    func testCountdownRoundsUpAndClampsAtZero() {
        let expiry = origin.addingTimeInterval(90)

        XCTAssertEqual(
            PanelClockPresentation.requestCountdown(
                expiresAt: expiry,
                at: origin.addingTimeInterval(0.1)
            ),
            "1:30"
        )
        XCTAssertEqual(
            PanelClockPresentation.requestCountdown(
                expiresAt: expiry,
                at: origin.addingTimeInterval(90.1)
            ),
            "0:00"
        )
    }

    private func makeTask(
        status: TaskStatus,
        updatedOffset: TimeInterval
    ) -> AgentTask {
        AgentTask(
            id: UUID().uuidString,
            source: "codex",
            title: "Clock contract",
            status: status,
            createdAt: origin,
            updatedAt: origin.addingTimeInterval(updatedOffset),
            taskURL: "file:///tmp/clock-contract"
        )
    }
}
