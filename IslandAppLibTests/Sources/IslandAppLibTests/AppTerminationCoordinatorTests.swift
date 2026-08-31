import XCTest
@testable import IslandAppLib

@MainActor
final class AppTerminationCoordinatorTests: XCTestCase {
    func testShippingHardTimeoutIsTwoSeconds() {
        XCTAssertEqual(
            AppTerminationCoordinator.hardTimeoutNanoseconds,
            2_000_000_000
        )
    }

    func testCleanupCompletionRepliesBeforeHardTimeout() async {
        let fixture = Fixture()
        var cleanupCount = 0
        var replyCount = 0

        let decision = fixture.coordinator.requestTermination(
            mode: .owner,
            cleanup: { cleanupCount += 1 },
            reply: { replyCount += 1 }
        )

        XCTAssertEqual(decision, .terminateLater)
        XCTAssertEqual(fixture.cleanup.pendingCount, 1)
        XCTAssertEqual(fixture.timeout.delays, [testTimeout])

        await fixture.cleanup.runNext()
        XCTAssertEqual(cleanupCount, 1)
        XCTAssertEqual(replyCount, 1)

        fixture.timeout.fireNext()
        XCTAssertEqual(replyCount, 1)
    }

    func testHardTimeoutRepliesWhileCleanupIsStillPending() async {
        let fixture = Fixture()
        var cleanupCount = 0
        var replyCount = 0

        XCTAssertEqual(
            fixture.coordinator.requestTermination(
                mode: .owner,
                cleanup: { cleanupCount += 1 },
                reply: { replyCount += 1 }
            ),
            .terminateLater
        )

        fixture.timeout.fireNext()
        XCTAssertEqual(cleanupCount, 0)
        XCTAssertEqual(replyCount, 1)

        await fixture.cleanup.runNext()
        XCTAssertEqual(cleanupCount, 1)
        XCTAssertEqual(replyCount, 1)
    }

    func testCompletionAndTimeoutRaceCanReplyOnlyOnceInEitherOrder() async {
        let completionFirst = Fixture()
        var completionFirstReplies = 0
        _ = completionFirst.coordinator.requestTermination(
            mode: .owner,
            cleanup: {},
            reply: { completionFirstReplies += 1 }
        )
        await completionFirst.cleanup.runNext()
        completionFirst.timeout.fireNext()

        let timeoutFirst = Fixture()
        var timeoutFirstReplies = 0
        _ = timeoutFirst.coordinator.requestTermination(
            mode: .owner,
            cleanup: {},
            reply: { timeoutFirstReplies += 1 }
        )
        timeoutFirst.timeout.fireNext()
        await timeoutFirst.cleanup.runNext()

        XCTAssertEqual(completionFirstReplies, 1)
        XCTAssertEqual(timeoutFirstReplies, 1)
    }

    func testRepeatedOwnerRequestSharesTheFirstCleanupFlight() async {
        let fixture = Fixture()
        var firstCleanupCount = 0
        var secondCleanupCount = 0
        var firstReplyCount = 0
        var secondReplyCount = 0

        let first = fixture.coordinator.requestTermination(
            mode: .owner,
            cleanup: { firstCleanupCount += 1 },
            reply: { firstReplyCount += 1 }
        )
        let second = fixture.coordinator.requestTermination(
            mode: .owner,
            cleanup: { secondCleanupCount += 1 },
            reply: { secondReplyCount += 1 }
        )

        XCTAssertEqual(first, .terminateLater)
        XCTAssertEqual(second, .terminateLater)
        XCTAssertEqual(fixture.cleanup.pendingCount, 1)
        XCTAssertEqual(fixture.timeout.pendingCount, 1)

        await fixture.cleanup.runNext()
        XCTAssertEqual(firstCleanupCount, 1)
        XCTAssertEqual(secondCleanupCount, 0)
        XCTAssertEqual(firstReplyCount, 1)
        XCTAssertEqual(secondReplyCount, 0)
    }

    func testAllThreeBypassModesTerminateNowInPurePolicy() {
        let bypassModes: [AppTerminationMode] = [
            .yieldedDuplicate,
            .performanceQA,
            .hermeticLaunchSmoke,
        ]

        for mode in bypassModes {
            XCTAssertEqual(
                AppTerminationPolicy.decision(for: mode),
                .terminateNow
            )
        }
        XCTAssertEqual(
            AppTerminationPolicy.decision(for: .owner),
            .terminateLater
        )
    }

    func testBypassModesScheduleNoCleanupTimeoutOrReply() {
        let fixture = Fixture()
        var cleanupCount = 0
        var replyCount = 0

        for mode in [
            AppTerminationMode.yieldedDuplicate,
            .performanceQA,
            .hermeticLaunchSmoke,
        ] {
            XCTAssertEqual(
                fixture.coordinator.requestTermination(
                    mode: mode,
                    cleanup: { cleanupCount += 1 },
                    reply: { replyCount += 1 }
                ),
                .terminateNow
            )
        }

        XCTAssertEqual(fixture.cleanup.pendingCount, 0)
        XCTAssertEqual(fixture.timeout.pendingCount, 0)
        XCTAssertEqual(cleanupCount, 0)
        XCTAssertEqual(replyCount, 0)
    }
}

private let testTimeout: UInt64 = 123_456

@MainActor
private struct Fixture {
    let cleanup: ManualCleanupLauncher
    let timeout: ManualTimeoutScheduler
    let coordinator: AppTerminationCoordinator

    init() {
        let cleanup = ManualCleanupLauncher()
        let timeout = ManualTimeoutScheduler()
        self.cleanup = cleanup
        self.timeout = timeout
        coordinator = AppTerminationCoordinator(
            timeoutNanoseconds: testTimeout,
            cleanupLauncher: cleanup.launch,
            timeoutScheduler: timeout.schedule
        )
    }
}

@MainActor
private final class ManualCleanupLauncher {
    private var operations: [@MainActor () async -> Void] = []

    var pendingCount: Int { operations.count }

    func launch(
        operation: @escaping @MainActor () async -> Void
    ) {
        operations.append(operation)
    }

    func runNext() async {
        precondition(!operations.isEmpty, "No cleanup operation is pending")
        let operation = operations.removeFirst()
        await operation()
    }
}

@MainActor
private final class ManualTimeoutScheduler {
    private struct ScheduledTimeout {
        let operation: @MainActor () -> Void
    }

    private var timeouts: [ScheduledTimeout] = []
    private(set) var delays: [UInt64] = []

    var pendingCount: Int { timeouts.count }

    func schedule(
        delayNanoseconds: UInt64,
        operation: @escaping @MainActor () -> Void
    ) {
        delays.append(delayNanoseconds)
        timeouts.append(ScheduledTimeout(operation: operation))
    }

    func fireNext() {
        precondition(!timeouts.isEmpty, "No timeout is pending")
        timeouts.removeFirst().operation()
    }
}
