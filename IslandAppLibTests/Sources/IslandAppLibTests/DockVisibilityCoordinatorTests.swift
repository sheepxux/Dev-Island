import AppKit
import XCTest
@testable import IslandAppLib

@MainActor
final class DockVisibilityCoordinatorTests: XCTestCase {
    func testSynchronizeStartsAccessoryAndDoesNotRepeatTheWrite() {
        let recorder = PolicyRecorder()
        let coordinator = makeCoordinator(recorder)

        coordinator.synchronize()
        coordinator.synchronize()

        XCTAssertEqual(recorder.policies, [.accessory])
    }

    func testFirstLeaseShowsDockAndLastReleaseHidesIt() {
        let recorder = PolicyRecorder()
        let coordinator = makeCoordinator(recorder)
        coordinator.synchronize()

        let settings = coordinator.acquire(.settings)
        let onboarding = coordinator.acquire(.onboarding)
        coordinator.release(settings)

        XCTAssertEqual(recorder.policies, [.accessory, .regular])

        coordinator.release(onboarding)
        XCTAssertEqual(recorder.policies, [.accessory, .regular, .accessory])
    }

    func testDuplicateReleaseIsHarmless() {
        let recorder = PolicyRecorder()
        let coordinator = makeCoordinator(recorder)
        coordinator.synchronize()

        let lease = coordinator.acquire(.settings)
        coordinator.release(lease)
        coordinator.release(lease)

        XCTAssertEqual(recorder.policies, [.accessory, .regular, .accessory])
    }

    func testSettingsToOnboardingHandoffNeverDropsDockPresence() {
        let recorder = PolicyRecorder()
        let coordinator = makeCoordinator(recorder)
        coordinator.synchronize()

        let settings = coordinator.acquire(.settings)
        let onboarding = coordinator.acquire(.onboarding)
        coordinator.release(onboarding)

        XCTAssertEqual(recorder.policies, [.accessory, .regular])

        coordinator.release(settings)
        XCTAssertEqual(recorder.policies, [.accessory, .regular, .accessory])
    }

    func testTwoSettingsWindowsHaveIndependentLeases() {
        let recorder = PolicyRecorder()
        let coordinator = makeCoordinator(recorder)
        coordinator.synchronize()

        let first = coordinator.acquire(.settings)
        let second = coordinator.acquire(.settings)
        coordinator.release(first)

        XCTAssertEqual(coordinator.desiredPolicy, .regular)
        XCTAssertEqual(recorder.policies, [.accessory, .regular])

        coordinator.release(second)
        XCTAssertEqual(coordinator.desiredPolicy, .accessory)
    }

    func testFailedPromotionRetriesAutomaticallyOnTheNextTurn() {
        let recorder = PolicyRecorder(results: [true, false, true])
        let scheduler = RetrySchedulerRecorder()
        let coordinator = makeCoordinator(recorder, scheduler: scheduler)

        coordinator.synchronize()
        _ = coordinator.acquire(.settings)
        scheduler.drain()

        XCTAssertEqual(recorder.policies, [.accessory, .regular, .regular])
        XCTAssertEqual(scheduler.delays, [16])
        XCTAssertEqual(coordinator.desiredPolicy, .regular)
    }

    func testFailedDemotionRetriesAutomaticallyOnTheNextTurn() {
        let recorder = PolicyRecorder(results: [true, true, false, true])
        let scheduler = RetrySchedulerRecorder()
        let coordinator = makeCoordinator(recorder, scheduler: scheduler)

        coordinator.synchronize()
        let settings = coordinator.acquire(.settings)
        coordinator.release(settings)
        scheduler.drain()

        XCTAssertEqual(
            recorder.policies,
            [.accessory, .regular, .accessory, .accessory]
        )
        XCTAssertEqual(scheduler.delays, [16])
        XCTAssertEqual(coordinator.desiredPolicy, .accessory)
    }

    func testRepeatedPromotionFailuresRemainBoundedAndCanRecover() {
        let recorder = PolicyRecorder(
            results: [true, false, false, false, true]
        )
        let scheduler = RetrySchedulerRecorder()
        let coordinator = makeCoordinator(recorder, scheduler: scheduler)

        coordinator.synchronize()
        _ = coordinator.acquire(.settings)
        scheduler.drain()

        XCTAssertEqual(
            recorder.policies,
            [.accessory, .regular, .regular, .regular, .regular]
        )
        XCTAssertEqual(scheduler.delays, [16, 32, 64])
        XCTAssertEqual(coordinator.desiredPolicy, .regular)
    }

    func testAutomaticRetriesStopAfterTheBound() {
        let recorder = PolicyRecorder(
            results: [true, false, false, false, false, true]
        )
        let scheduler = RetrySchedulerRecorder()
        let coordinator = makeCoordinator(recorder, scheduler: scheduler)

        coordinator.synchronize()
        _ = coordinator.acquire(.settings)
        scheduler.drain()

        XCTAssertEqual(
            recorder.policies,
            [.accessory, .regular, .regular, .regular, .regular]
        )
        XCTAssertEqual(scheduler.delays, [16, 32, 64])
        XCTAssertEqual(coordinator.desiredPolicy, .regular)
    }

    func testPendingPromotionRetryUsesLatestStateAfterRelease() {
        let recorder = PolicyRecorder(results: [true, false])
        let scheduler = RetrySchedulerRecorder()
        let coordinator = makeCoordinator(recorder, scheduler: scheduler)

        coordinator.synchronize()
        let settings = coordinator.acquire(.settings)
        coordinator.release(settings)
        scheduler.drain()

        XCTAssertEqual(recorder.policies, [.accessory, .regular])
        XCTAssertEqual(scheduler.delays, [16])
        XCTAssertEqual(coordinator.desiredPolicy, .accessory)
    }

    func testPendingDemotionRetryUsesLatestStateAfterNewLease() {
        let recorder = PolicyRecorder(results: [true, true, false])
        let scheduler = RetrySchedulerRecorder()
        let coordinator = makeCoordinator(recorder, scheduler: scheduler)

        coordinator.synchronize()
        let first = coordinator.acquire(.settings)
        coordinator.release(first)
        _ = coordinator.acquire(.onboarding)
        scheduler.drain()

        XCTAssertEqual(
            recorder.policies,
            [.accessory, .regular, .accessory]
        )
        XCTAssertEqual(scheduler.delays, [16])
        XCTAssertEqual(coordinator.desiredPolicy, .regular)
    }

    func testExplicitSynchronizeCanRecoverAfterRetryLimit() {
        let recorder = PolicyRecorder(
            results: [true, false, false, false, false, true]
        )
        let scheduler = RetrySchedulerRecorder()
        let coordinator = makeCoordinator(recorder, scheduler: scheduler)

        coordinator.synchronize()
        _ = coordinator.acquire(.settings)
        scheduler.drain()
        coordinator.synchronize()

        XCTAssertEqual(
            recorder.policies,
            [.accessory, .regular, .regular, .regular, .regular, .regular]
        )
        XCTAssertEqual(scheduler.delays, [16, 32, 64])
        XCTAssertEqual(coordinator.desiredPolicy, .regular)
    }

    func testStaleReleasedTokenCannotAffectANewerLease() {
        let recorder = PolicyRecorder()
        let coordinator = makeCoordinator(recorder)
        coordinator.synchronize()

        let stale = coordinator.acquire(.settings)
        coordinator.release(stale)
        let current = coordinator.acquire(.settings)
        coordinator.release(stale)

        XCTAssertEqual(coordinator.desiredPolicy, .regular)
        XCTAssertEqual(
            recorder.policies,
            [.accessory, .regular, .accessory, .regular]
        )

        coordinator.release(current)
        XCTAssertEqual(recorder.policies.last, .accessory)
    }

    private func makeCoordinator(
        _ recorder: PolicyRecorder,
        scheduler: RetrySchedulerRecorder? = nil
    ) -> DockVisibilityCoordinator {
        if let scheduler {
            return DockVisibilityCoordinator(
                applyPolicy: { policy in recorder.apply(policy) },
                retryScheduler: scheduler.schedule
            )
        }
        return DockVisibilityCoordinator { policy in
            recorder.apply(policy)
        }
    }
}

@MainActor
private final class RetrySchedulerRecorder {
    private struct ScheduledRetry {
        let operation: @MainActor () -> Void
    }

    private var retries: [ScheduledRetry] = []
    private(set) var delays: [Int] = []

    func schedule(
        delayMilliseconds: Int,
        operation: @escaping @MainActor () -> Void
    ) {
        delays.append(delayMilliseconds)
        retries.append(ScheduledRetry(operation: operation))
    }

    func drain() {
        var executed = 0
        while !retries.isEmpty {
            precondition(executed < 16, "Retry scheduler did not converge")
            let retry = retries.removeFirst()
            retry.operation()
            executed += 1
        }
    }
}

@MainActor
private final class PolicyRecorder {
    private var results: [Bool]
    private(set) var policies: [NSApplication.ActivationPolicy] = []

    init(results: [Bool] = []) {
        self.results = results
    }

    func apply(_ policy: NSApplication.ActivationPolicy) -> Bool {
        policies.append(policy)
        return results.isEmpty ? true : results.removeFirst()
    }
}
