import Foundation
import XCTest
@testable import IslandAppLib

@MainActor
final class LaunchHealthTrackerTests: XCTestCase {
    private let schemaVersionKey = "devIsland.launchHealth.schemaVersion"
    private let didStartKey = "devIsland.launchHealth.didStart"
    private let startupReadyKey = "devIsland.launchHealth.startupReady"
    private let interruptionCountKey =
        "devIsland.launchHealth.consecutiveStartupInterruptions"
    private let legacyCleanExitKey = "devIsland.launchHealth.cleanExit"

    func testFirstInterruptedAndReadyLaunchesUseStartupMilestone() throws {
        let defaults = try makeDefaults()

        let first = LaunchHealthTracker(defaults: defaults)
        first.beginLaunch()
        XCTAssertEqual(first.previousLaunchState, .firstLaunch)
        XCTAssertEqual(first.consecutiveStartupInterruptions, 0)

        // A second process observes that the first never reached the startup
        // milestone. The state remains broader than "crashed" because a quick
        // Force Quit, restart, or power loss has the same evidence.
        let interrupted = LaunchHealthTracker(defaults: defaults)
        interrupted.beginLaunch()
        XCTAssertEqual(interrupted.previousLaunchState, .startupInterrupted)
        XCTAssertEqual(interrupted.consecutiveStartupInterruptions, 1)
        interrupted.markStartupReady()

        let ready = LaunchHealthTracker(defaults: defaults)
        ready.beginLaunch()
        XCTAssertEqual(ready.previousLaunchState, .ready)
        XCTAssertEqual(ready.consecutiveStartupInterruptions, 0)
    }

    func testStableProcessNeedsNoCleanTerminationRecord() throws {
        let defaults = try makeDefaults()
        let process = LaunchHealthTracker(defaults: defaults)
        process.beginLaunch()
        process.markStartupReady()

        // This models Force Quit, restart, or power loss after the two-second
        // health window: applicationWillTerminate never needs to run.
        let relaunched = LaunchHealthTracker(defaults: defaults)
        relaunched.beginLaunch()
        XCTAssertEqual(relaunched.previousLaunchState, .ready)
        XCTAssertEqual(relaunched.consecutiveStartupInterruptions, 0)
    }

    func testRepeatedStartupInterruptionsAreCappedAndReadyResetsSequence() throws {
        let defaults = try makeDefaults()
        LaunchHealthTracker(defaults: defaults).beginLaunch()

        var latest: LaunchHealthTracker?
        for _ in 0..<8 {
            let process = LaunchHealthTracker(defaults: defaults)
            process.beginLaunch()
            latest = process
        }

        XCTAssertEqual(latest?.previousLaunchState, .startupInterrupted)
        XCTAssertEqual(
            latest?.consecutiveStartupInterruptions,
            LaunchHealthTracker.maximumConsecutiveStartupInterruptions
        )

        latest?.markStartupReady()
        let recovered = LaunchHealthTracker(defaults: defaults)
        recovered.beginLaunch()
        XCTAssertEqual(recovered.previousLaunchState, .ready)
        XCTAssertEqual(recovered.consecutiveStartupInterruptions, 0)
    }

    func testAmbiguousLegacyUncleanRecordMigratesWithoutFalseWarning() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: didStartKey)
        defaults.set(false, forKey: legacyCleanExitKey)

        let migrated = LaunchHealthTracker(defaults: defaults)
        migrated.beginLaunch()

        XCTAssertEqual(migrated.previousLaunchState, .legacyUnknown)
        XCTAssertEqual(migrated.consecutiveStartupInterruptions, 0)
        XCTAssertEqual(defaults.integer(forKey: schemaVersionKey), 2)
        XCTAssertNil(defaults.object(forKey: legacyCleanExitKey))

        // Once v2 is armed, a genuinely uncompleted readiness marker becomes
        // the first bounded startup interruption.
        let interrupted = LaunchHealthTracker(defaults: defaults)
        interrupted.beginLaunch()
        XCTAssertEqual(interrupted.previousLaunchState, .startupInterrupted)
        XCTAssertEqual(interrupted.consecutiveStartupInterruptions, 1)
    }

    func testLegacyCleanRecordMigratesAsReady() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: didStartKey)
        defaults.set(true, forKey: legacyCleanExitKey)

        let migrated = LaunchHealthTracker(defaults: defaults)
        migrated.beginLaunch()

        XCTAssertEqual(migrated.previousLaunchState, .ready)
        XCTAssertEqual(migrated.consecutiveStartupInterruptions, 0)
        XCTAssertNil(defaults.object(forKey: legacyCleanExitKey))
    }

    func testLifecycleCallsAreIdempotentAndUnarmedReadyWritesNothing() throws {
        let defaults = try makeDefaults()
        let unarmed = LaunchHealthTracker(defaults: defaults)
        unarmed.markStartupReady()
        XCTAssertNil(defaults.object(forKey: schemaVersionKey))
        XCTAssertNil(defaults.object(forKey: didStartKey))
        XCTAssertNil(defaults.object(forKey: startupReadyKey))
        XCTAssertNil(defaults.object(forKey: interruptionCountKey))

        let first = LaunchHealthTracker(defaults: defaults)
        first.beginLaunch()
        first.beginLaunch()
        XCTAssertEqual(first.previousLaunchState, .firstLaunch)
        first.markStartupReady()
        first.markStartupReady()

        let next = LaunchHealthTracker(defaults: defaults)
        next.beginLaunch()
        XCTAssertEqual(next.previousLaunchState, .ready)
    }

    func testPersistedStateIsSmallBoundedAndContainsNoCrashArtifactMetadata() throws {
        let defaults = try makeDefaults()
        defaults.set(2, forKey: schemaVersionKey)
        defaults.set(true, forKey: didStartKey)
        defaults.set(false, forKey: startupReadyKey)
        defaults.set(Int.max, forKey: interruptionCountKey)

        let tracker = LaunchHealthTracker(defaults: defaults)
        tracker.beginLaunch()

        XCTAssertEqual(
            tracker.consecutiveStartupInterruptions,
            LaunchHealthTracker.maximumConsecutiveStartupInterruptions
        )
        XCTAssertEqual(LaunchHealthTracker.startupStabilityDelay, 2)

        let stored = defaults.dictionaryRepresentation().filter {
            $0.key.hasPrefix("devIsland.launchHealth.")
        }
        XCTAssertEqual(Set(stored.keys), Set([
            schemaVersionKey,
            didStartKey,
            startupReadyKey,
            interruptionCountKey,
        ]))
        XCTAssertTrue(stored.values.allSatisfy { $0 is NSNumber })
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "app.devisland.Island.tests.launch-health.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
        }
        return defaults
    }
}
