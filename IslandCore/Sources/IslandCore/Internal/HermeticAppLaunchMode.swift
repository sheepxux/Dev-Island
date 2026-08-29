import Foundation

/// Explicit, side-effect-free launch mode used only by repository-owned
/// production-App smoke verification.
///
/// Both an exact argument and an exact environment value are required so an
/// unrelated parent environment or an accidental command-line fragment cannot
/// silently disable the shipping service bootstrap. The mode grants no extra
/// capability: it only prevents SQLite, Keychain, local listeners and remote
/// services from starting while the real production UI is launched from a
/// private App snapshot.
public enum HermeticAppLaunchMode: Sendable {
    public static let argument = "--dev-island-hermetic-launch-smoke-v1"
    public static let environmentKey = "DEV_ISLAND_HERMETIC_LAUNCH_SMOKE"
    public static let environmentValue = "v1"

    public static func isEnabled(
        arguments: [String],
        environment: [String: String]
    ) -> Bool {
        arguments.filter { $0 == argument }.count == 1
            && environment[environmentKey] == environmentValue
    }

    public static var isEnabledForCurrentProcess: Bool {
        isEnabled(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
    }
}
