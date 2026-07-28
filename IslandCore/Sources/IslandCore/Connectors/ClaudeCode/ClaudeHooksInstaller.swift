import Foundation

/// Installs / removes the Dev Island hook entries in Claude Code's user
/// settings (`~/.claude/settings.json`).
///
/// The hook is a `curl` one-liner that forwards the JSON payload Claude Code
/// pipes on stdin to `LocalHookServer`. It is deliberately fire-and-forget
/// (`-m 2`, trailing `|| true`) so a stopped or crashed Dev Island can never
/// block or fail a Claude Code turn.
///
/// All edits are merge-based via `JSONSerialization`: existing user hooks,
/// unknown settings keys, and unrelated hook groups are preserved verbatim.
/// Our entries are recognized by the `/hooks/claude-code` marker in the
/// command string, which makes install idempotent and uninstall surgical.
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
        let url = settingsURL ?? defaultSettingsURL
        guard let root = readSettings(at: url),
              let hooks = root["hooks"] as? [String: Any] else { return false }
        // Consider installed when every event we need carries our command.
        return events.allSatisfy { event in
            guard let groups = hooks[event] as? [[String: Any]] else { return false }
            return groups.contains(where: isOurGroup)
        }
    }

    public static func install(settingsURL: URL? = nil, port: Int = defaultPort) throws {
        let url = settingsURL ?? defaultSettingsURL
        var root = readSettings(at: url) ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        let ourGroup: [String: Any] = [
            "matcher": "",
            "hooks": [["type": "command", "command": hookCommand(port: port)]],
        ]

        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.removeAll(where: isOurGroup)  // drop stale versions of ours
            groups.append(ourGroup)
            hooks[event] = groups
        }

        root["hooks"] = hooks
        try writeSettings(root, to: url)
    }

    public static func uninstall(settingsURL: URL? = nil) throws {
        let url = settingsURL ?? defaultSettingsURL
        guard var root = readSettings(at: url),
              var hooks = root["hooks"] as? [String: Any] else { return }

        for (event, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            groups.removeAll(where: isOurGroup)
            if groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = groups
            }
        }

        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        try writeSettings(root, to: url)
    }

    // MARK: - Private

    /// A matcher group is "ours" when every command in it targets our
    /// local endpoint (user-authored groups are never all-ours).
    private static func isOurGroup(_ group: [String: Any]) -> Bool {
        guard let handlers = group["hooks"] as? [[String: Any]], !handlers.isEmpty else {
            return false
        }
        return handlers.allSatisfy { handler in
            (handler["command"] as? String)?.contains(endpointPath) == true
        }
    }

    private static func readSettings(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func writeSettings(_ root: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
    }
}
