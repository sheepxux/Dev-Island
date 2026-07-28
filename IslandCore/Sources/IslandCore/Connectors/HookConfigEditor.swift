import Foundation

/// Merge-based editing of hook config files that share the
/// `{"hooks": {"Event": [{matcher?, hooks: [{type, command}]}]}}` nesting —
/// Claude Code's `~/.claude/settings.json` and Codex's `~/.codex/hooks.json`
/// use the identical structure.
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

    static func install(at url: URL, events: [String], group: [String: Any], marker: String) throws {
        var root = readRoot(at: url) ?? [:]
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

    /// A matcher group is "ours" when every command in it targets our
    /// endpoint (user-authored groups are never all-ours).
    private static func isOurGroup(_ group: [String: Any], marker: String) -> Bool {
        guard let handlers = group["hooks"] as? [[String: Any]], !handlers.isEmpty else {
            return false
        }
        return handlers.allSatisfy { handler in
            (handler["command"] as? String)?.contains(marker) == true
        }
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
