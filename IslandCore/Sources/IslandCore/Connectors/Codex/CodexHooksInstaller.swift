import Foundation

/// Installs / removes the Dev Island hook entries in Codex's user-level
/// hooks file (`~/.codex/hooks.json`).
///
/// Codex loads hooks from `hooks.json` next to `config.toml` — same event
/// nesting as Claude Code's settings, so `HookConfigEditor` does the JSON
/// surgery. We deliberately use `hooks.json` instead of inline TOML: it's
/// mergeable without a TOML dependency, and Codex warns if both exist in
/// one layer (we never touch `config.toml`).
///
/// The command is fire-and-forget (`-m 2`, `|| true`, output discarded):
/// exit 0 with no stdout is defined by Codex as "success, continue", so a
/// dead Dev Island can never stall or steer a Codex turn.
public enum CodexHooksInstaller {

    /// Hook events we subscribe to. Keep in sync with `CodexEvent.Kind`.
    static let events = [
        "SessionStart", "UserPromptSubmit", "PermissionRequest",
        "Stop", "SessionEnd",
    ]

    static let endpointPath = "/hooks/codex"

    public static func hookCommand(port: Int = ClaudeHooksInstaller.defaultPort) -> String {
        "curl -sf -m 2 -X POST http://127.0.0.1:\(port)\(endpointPath) "
            + "-H 'Content-Type: application/json' --data-binary @- >/dev/null 2>&1 || true"
    }

    public static var defaultHooksURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/hooks.json")
    }

    // MARK: - Public API

    public static func isInstalled(hooksURL: URL? = nil) -> Bool {
        HookConfigEditor.isInstalled(
            at: hooksURL ?? defaultHooksURL,
            events: events,
            marker: endpointPath
        )
    }

    public static func install(hooksURL: URL? = nil, port: Int = ClaudeHooksInstaller.defaultPort) throws {
        // No "matcher" key: Codex matchers are event-specific (SessionStart
        // filters start source, PermissionRequest filters tool name) and an
        // omitted matcher matches everything, which is what we want.
        try HookConfigEditor.install(
            at: hooksURL ?? defaultHooksURL,
            events: events,
            group: [
                "hooks": [["type": "command", "command": hookCommand(port: port)]]
            ],
            marker: endpointPath
        )
    }

    public static func uninstall(hooksURL: URL? = nil) throws {
        try HookConfigEditor.uninstall(
            at: hooksURL ?? defaultHooksURL,
            marker: endpointPath
        )
    }
}
