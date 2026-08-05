import Foundation

/// Compatibility facade over `LocalHooksInstaller(.claudeCode)` — kept so
/// call sites and tests written against the pre-framework API keep working.
/// New code should use the generic installer via `LocalAgentRegistry`.
public enum ClaudeHooksInstaller {

    public static let defaultPort = LocalHooksInstaller.defaultPort

    static var events: [String] { LocalAgentDescriptor.claudeCode.hookEvents }

    private static var installer: LocalHooksInstaller { .init(.claudeCode) }

    public static func hookCommand(port: Int = defaultPort) -> String {
        installer.hookCommand(port: port)
    }

    public static var defaultSettingsURL: URL {
        LocalAgentDescriptor.claudeCode.configURL
    }

    public static func isInstalled(settingsURL: URL? = nil) -> Bool {
        installer.isInstalled(configURL: settingsURL)
    }

    public static func install(settingsURL: URL? = nil, port: Int = defaultPort) throws {
        try installer.install(configURL: settingsURL, port: port)
    }

    public static func uninstall(settingsURL: URL? = nil) throws {
        try installer.uninstall(configURL: settingsURL)
    }
}
