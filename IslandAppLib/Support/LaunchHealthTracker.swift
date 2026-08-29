import Foundation

/// What the current process can safely infer about the preceding launch.
///
/// `startupInterrupted` deliberately does not mean "crashed": a quick Force
/// Quit, power loss, or an OS restart can also end a process before the short
/// startup-health window completes. Dev Island never reads a macOS crash
/// report, and an ambiguous marker imported from the former clean-shutdown
/// scheme is kept separate so it cannot trigger a false warning.
public enum PreviousLaunchState: Equatable, Sendable {
    case firstLaunch
    case ready
    case startupInterrupted
    case legacyUnknown
}

/// Privacy-minimal startup-loop detection for Support diagnostics.
///
/// Shipping state is deliberately bounded: two Booleans, a schema version,
/// and a consecutive-interruption count capped at three. There are no paths,
/// timestamps, crash reports, task details, network calls, or automatic
/// recovery actions. The production singleton is armed explicitly by
/// AppDelegate so the hermetic performance-QA build never touches defaults.
@MainActor
public final class LaunchHealthTracker {
    public static let shared = LaunchHealthTracker(defaults: .standard)

    /// The app must remain alive through this window after constructing the
    /// island and menu-bar surfaces. This catches immediate launch loops while
    /// keeping the marker short-lived; a normal AppKit termination also closes
    /// the marker so a deliberate quick Quit is not treated as an interruption.
    public static let startupStabilityDelay: TimeInterval = 2

    nonisolated public static let maximumConsecutiveStartupInterruptions = 3

    private static let currentSchemaVersion = 2
    private static let schemaVersionKey = "devIsland.launchHealth.schemaVersion"
    private static let didStartKey = "devIsland.launchHealth.didStart"
    private static let startupReadyKey = "devIsland.launchHealth.startupReady"
    private static let interruptionCountKey =
        "devIsland.launchHealth.consecutiveStartupInterruptions"

    /// v1 migration-only key. It could not distinguish a stable process that
    /// was Force Quit from a launch crash, so a false value is never promoted
    /// into the stronger `startupInterrupted` state.
    private static let legacyCleanExitKey = "devIsland.launchHealth.cleanExit"

    private let defaults: UserDefaults
    private var hasBegun = false

    public private(set) var previousLaunchState: PreviousLaunchState = .firstLaunch
    public private(set) var consecutiveStartupInterruptions = 0

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Snapshot the preceding marker, migrate v1 without making a crash claim,
    /// then immediately arm the current launch. Repeated calls in one process
    /// are intentionally no-ops.
    public func beginLaunch() {
        #if DEV_ISLAND_PERFORMANCE_QA
        // Defense in depth: even an accidental caller inside the hermetic
        // measurement bundle cannot create or mutate launch preferences.
        return
        #else
        guard !hasBegun else { return }

        if defaults.integer(forKey: Self.schemaVersionKey)
            == Self.currentSchemaVersion {
            readCurrentSchema()
        } else {
            migrateLegacySchema()
        }

        defaults.set(Self.currentSchemaVersion, forKey: Self.schemaVersionKey)
        defaults.set(true, forKey: Self.didStartKey)
        defaults.set(false, forKey: Self.startupReadyKey)
        defaults.removeObject(forKey: Self.legacyCleanExitKey)
        hasBegun = true
        #endif
    }

    /// Close the startup marker once the island and menu-bar surfaces have
    /// remained alive through the stability window. An unarmed or repeated
    /// call is harmless. Resetting the persisted count here makes the next
    /// interrupted launch the first in a new sequence.
    public func markStartupReady() {
        #if DEV_ISLAND_PERFORMANCE_QA
        return
        #else
        guard hasBegun else { return }
        defaults.set(true, forKey: Self.startupReadyKey)
        defaults.set(0, forKey: Self.interruptionCountKey)
        #endif
    }

    private func readCurrentSchema() {
        guard defaults.bool(forKey: Self.didStartKey) else {
            previousLaunchState = .firstLaunch
            consecutiveStartupInterruptions = 0
            defaults.set(0, forKey: Self.interruptionCountKey)
            return
        }

        if defaults.bool(forKey: Self.startupReadyKey) {
            previousLaunchState = .ready
            consecutiveStartupInterruptions = 0
            defaults.set(0, forKey: Self.interruptionCountKey)
            return
        }

        previousLaunchState = .startupInterrupted
        let priorCount = boundedCount(
            defaults.integer(forKey: Self.interruptionCountKey)
        )
        consecutiveStartupInterruptions = min(
            priorCount + 1,
            Self.maximumConsecutiveStartupInterruptions
        )
        defaults.set(
            consecutiveStartupInterruptions,
            forKey: Self.interruptionCountKey
        )
    }

    private func migrateLegacySchema() {
        consecutiveStartupInterruptions = 0
        defaults.set(0, forKey: Self.interruptionCountKey)

        guard defaults.bool(forKey: Self.didStartKey) else {
            previousLaunchState = .firstLaunch
            return
        }

        // A true v1 clean-exit marker is sufficient evidence that the old
        // process reached a usable lifecycle. A false/missing marker remains
        // ambiguous and is intentionally silent after migration.
        previousLaunchState = defaults.bool(forKey: Self.legacyCleanExitKey)
            ? .ready
            : .legacyUnknown
    }

    private func boundedCount(_ value: Int) -> Int {
        min(max(value, 0), Self.maximumConsecutiveStartupInterruptions)
    }
}
