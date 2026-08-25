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

    func testFailedPromotionRetriesAutomaticallyOnTheNextTurn() async {
        let recorder = PolicyRecorder(results: [true, false, true])
        let coordinator = makeCoordinator(recorder)

        coordinator.synchronize()
        _ = coordinator.acquire(.settings)
        await settleScheduledRetry()

        XCTAssertEqual(recorder.policies, [.accessory, .regular, .regular])
        XCTAssertEqual(coordinator.desiredPolicy, .regular)
    }

    func testFailedDemotionRetriesAutomaticallyOnTheNextTurn() async {
        let recorder = PolicyRecorder(results: [true, true, false, true])
        let coordinator = makeCoordinator(recorder)

        coordinator.synchronize()
        let settings = coordinator.acquire(.settings)
        coordinator.release(settings)
        await settleScheduledRetry()

        XCTAssertEqual(
            recorder.policies,
            [.accessory, .regular, .accessory, .accessory]
        )
        XCTAssertEqual(coordinator.desiredPolicy, .accessory)
    }

    func testRepeatedPromotionFailuresRemainBoundedAndCanRecover() async {
        let recorder = PolicyRecorder(
            results: [true, false, false, false, true]
        )
        let coordinator = makeCoordinator(recorder)

        coordinator.synchronize()
        _ = coordinator.acquire(.settings)
        await settleScheduledRetry()

        XCTAssertEqual(
            recorder.policies,
            [.accessory, .regular, .regular, .regular, .regular]
        )
        XCTAssertEqual(coordinator.desiredPolicy, .regular)
    }

    func testAutomaticRetriesStopAfterTheBound() async {
        let recorder = PolicyRecorder(
            results: [true, false, false, false, false, true]
        )
        let coordinator = makeCoordinator(recorder)

        coordinator.synchronize()
        _ = coordinator.acquire(.settings)
        await settleScheduledRetry()

        XCTAssertEqual(
            recorder.policies,
            [.accessory, .regular, .regular, .regular, .regular]
        )
        XCTAssertEqual(coordinator.desiredPolicy, .regular)
    }

    func testPendingPromotionRetryUsesLatestStateAfterRelease() async {
        let recorder = PolicyRecorder(results: [true, false])
        let coordinator = makeCoordinator(recorder)

        coordinator.synchronize()
        let settings = coordinator.acquire(.settings)
        coordinator.release(settings)
        await settleScheduledRetry()

        XCTAssertEqual(recorder.policies, [.accessory, .regular])
        XCTAssertEqual(coordinator.desiredPolicy, .accessory)
    }

    func testPendingDemotionRetryUsesLatestStateAfterNewLease() async {
        let recorder = PolicyRecorder(results: [true, true, false])
        let coordinator = makeCoordinator(recorder)

        coordinator.synchronize()
        let first = coordinator.acquire(.settings)
        coordinator.release(first)
        _ = coordinator.acquire(.onboarding)
        await settleScheduledRetry()

        XCTAssertEqual(
            recorder.policies,
            [.accessory, .regular, .accessory]
        )
        XCTAssertEqual(coordinator.desiredPolicy, .regular)
    }

    func testExplicitSynchronizeCanRecoverAfterRetryLimit() async {
        let recorder = PolicyRecorder(
            results: [true, false, false, false, false, true]
        )
        let coordinator = makeCoordinator(recorder)

        coordinator.synchronize()
        _ = coordinator.acquire(.settings)
        await settleScheduledRetry()
        coordinator.synchronize()

        XCTAssertEqual(
            recorder.policies,
            [.accessory, .regular, .regular, .regular, .regular, .regular]
        )
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

    private func settleScheduledRetry() async {
        // Production uses one-frame exponential backoff (16 + 32 + 64 ms)
        // so retries cross real AppKit run-loop turns. Cover the full bounded
        // sequence, then yield once so its final actor hop can finish.
        try? await Task.sleep(for: .milliseconds(250))
        await Task.yield()
    }

    private func makeCoordinator(
        _ recorder: PolicyRecorder
    ) -> DockVisibilityCoordinator {
        DockVisibilityCoordinator { policy in
            recorder.apply(policy)
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
