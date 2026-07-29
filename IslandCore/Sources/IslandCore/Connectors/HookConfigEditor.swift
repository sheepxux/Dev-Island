import Foundation

/// Merge-based editing of hook config files that share a
/// `{"hooks": {"Event": [entry, …]}}` layout. Two entry shapes exist:
///
/// - nested (Claude Code `~/.claude/settings.json`, Codex
///   `~/.codex/hooks.json`): `{matcher?, hooks: [{type, command}]}`
/// - flat (Cursor `~/.cursor/hooks.json`): `{command}` directly
///
/// Both shapes are recognized transparently — an entry is "ours" when its
/// command string(s) contain the endpoint marker.
///
/// Guarantees:
/// - unknown top-level keys and user-authored hook groups survive untouched
/// - our groups are recognized by an endpoint marker inside the command
///   string, making install idempotent and uninstall surgical
enum HookConfigEditor {

    static func isInstalled(at url: URL, events: [String], marker: String) -> Bool {
        guard let root = readRoot(at: url),
              let hooks = root["hooks"] as? [String: Any] else { return false }
        // Installed = every event we need carries our command.
        return events.allSatisfy { event in
            guard let groups = hooks[event] as? [[String: Any]] else { return false }
            return groups.contains { isOurGroup($0, marker: marker) }
        }
    }

    /// `rootDefaults` are top-level keys written only when absent — e.g.
    /// Cursor's hooks file requires `"version": 1`, but a user-set value
    /// must never be overwritten.
    static func install(
        at url: URL,
        events: [String],
        group: [String: Any],
        marker: String,
        rootDefaults: [String: Any] = [:]
    ) throws {
        var root = readRoot(at: url) ?? [:]
        for (key, value) in rootDefaults where root[key] == nil {
            root[key] = value
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.removeAll { isOurGroup($0, marker: marker) }  // drop stale versions
            groups.append(group)
            hooks[event] = groups
        }

        root["hooks"] = hooks
        try writeRoot(root, to: url)
    }

    static func uninstall(at url: URL, marker: String) throws {
        guard var root = readRoot(at: url),
              var hooks = root["hooks"] as? [String: Any] else { return }

        for (event, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            groups.removeAll { isOurGroup($0, marker: marker) }
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
        try writeRoot(root, to: url)
    }

    // MARK: - Private

    /// An entry is "ours" when every command in it targets our endpoint
    /// (user-authored entries are never all-ours). Nested entries carry an
    /// inner `hooks` array; flat entries carry `command` directly.
    private static func isOurGroup(_ group: [String: Any], marker: String) -> Bool {
        if let handlers = group["hooks"] as? [[String: Any]], !handlers.isEmpty {
            return handlers.allSatisfy { handler in
                (handler["command"] as? String)?.contains(marker) == true
            }
        }
        return (group["command"] as? String)?.contains(marker) == true
    }

    private static func readRoot(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func writeRoot(_ root: [String: Any], to url: URL) throws {
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
