import Foundation

/// Installs / removes the Dev Island hook entries in Claude Code's user
/// settings (`~/.claude/settings.json`).
///
/// The hook is a `curl` one-liner that forwards the JSON payload Claude Code
/// pipes on stdin to `LocalHookServer`. It is deliberately fire-and-forget
/// (`-m 2`, trailing `|| true`) so a stopped or crashed Dev Island can never
/// block or fail a Claude Code turn.
///
/// JSON surgery is delegated to `HookConfigEditor` (shared with the Codex
/// installer): existing user hooks and unknown settings keys are preserved,
/// and our entries are recognized by the `/hooks/claude-code` marker.
public enum ClaudeHooksInstaller {

    public static let defaultPort = 7824

    /// Hook events we subscribe to. Keep in sync with `ClaudeCodeEvent.Kind`.
    static let events = [
        "SessionStart", "UserPromptSubmit", "Notification",
        "Stop", "StopFailure", "SessionEnd",
    ]

    static let endpointPath = "/hooks/claude-code"

    public static func hookCommand(port: Int = defaultPort) -> String {
        "curl -sf -m 2 -X POST http://127.0.0.1:\(port)\(endpointPath) "
            + "-H 'Content-Type: application/json' --data-binary @- >/dev/null 2>&1 || true"
    }

    public static var defaultSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    // MARK: - Public API

    public static func isInstalled(settingsURL: URL? = nil) -> Bool {
        HookConfigEditor.isInstalled(
            at: settingsURL ?? defaultSettingsURL,
            events: events,
            marker: endpointPath
        )
    }

    public static func install(settingsURL: URL? = nil, port: Int = defaultPort) throws {
        try HookConfigEditor.install(
            at: settingsURL ?? defaultSettingsURL,
            events: events,
            group: [
                "matcher": "",
                "hooks": [["type": "command", "command": hookCommand(port: port)]],
            ],
            marker: endpointPath
        )
    }

    public static func uninstall(settingsURL: URL? = nil) throws {
        try HookConfigEditor.uninstall(
            at: settingsURL ?? defaultSettingsURL,
            marker: endpointPath
        )
    }
}
