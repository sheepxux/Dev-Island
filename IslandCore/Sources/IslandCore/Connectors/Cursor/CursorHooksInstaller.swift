import Foundation

/// Installs / removes the Dev Island hook entries in Cursor's user-level
/// hooks file (`~/.cursor/hooks.json`).
///
/// Cursor's format differs from Claude Code / Codex in two ways handled by
/// `HookConfigEditor`: entries are flat (`{"command": …}`, no nested
/// `hooks` array, no matcher) and the file requires a top-level
/// `"version": 1`. Event names are camelCase.
///
/// We subscribe only to fire-and-forget lifecycle events — never to gating
/// hooks — so our command's empty response can't block a Cursor action.
/// The command itself is fire-and-forget too (`-m 2`, `|| true`, output
/// discarded): a dead Dev Island can never stall or steer a Cursor turn.
public enum CursorHooksInstaller {

    /// Hook events we subscribe to. Keep in sync with `CursorEvent.Kind`.
    static let events = [
        "sessionStart", "beforeSubmitPrompt", "stop", "sessionEnd",
    ]

    static let endpointPath = "/hooks/cursor"

    public static func hookCommand(port: Int = ClaudeHooksInstaller.defaultPort) -> String {
        "curl -sf -m 2 -X POST http://127.0.0.1:\(port)\(endpointPath) "
            + "-H 'Content-Type: application/json' --data-binary @- >/dev/null 2>&1 || true"
    }

    public static var defaultHooksURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/hooks.json")
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
        try HookConfigEditor.install(
            at: hooksURL ?? defaultHooksURL,
            events: events,
            group: ["command": hookCommand(port: port)],
            marker: endpointPath,
            rootDefaults: ["version": 1]
        )
    }

    public static func uninstall(hooksURL: URL? = nil) throws {
        try HookConfigEditor.uninstall(
            at: hooksURL ?? defaultHooksURL,
            marker: endpointPath
        )
    }
}
