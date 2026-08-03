import Foundation

/// Compatibility facade over `LocalHooksInstaller(.codex)` — kept so call
/// sites and tests written against the pre-framework API keep working.
/// New code should use the generic installer via `LocalAgentRegistry`.
public enum CodexHooksInstaller {

    static var events: [String] { LocalAgentDescriptor.codex.hookEvents }

    private static var installer: LocalHooksInstaller { .init(.codex) }

    public static func hookCommand(port: Int = LocalHooksInstaller.defaultPort) -> String {
        installer.hookCommand(port: port)
    }

    public static var defaultHooksURL: URL {
        LocalAgentDescriptor.codex.configURL
    }

    public static func isInstalled(hooksURL: URL? = nil) -> Bool {
        installer.isInstalled(configURL: hooksURL)
    }

    public static func install(hooksURL: URL? = nil, port: Int = LocalHooksInstaller.defaultPort) throws {
        try installer.install(configURL: hooksURL, port: port)
    }

    public static func uninstall(hooksURL: URL? = nil) throws {
        try installer.uninstall(configURL: hooksURL)
    }
}
