import Foundation

/// Merge-based editing of hook config files that share a
/// `{"hooks": {"Event": [entry, …]}}` layout. Two entry shapes exist:
///
/// - nested (Claude Code `~/.claude/settings.json`, Gemini CLI
///   `~/.gemini/settings.json`, Codex `~/.codex/hooks.json`):
///   `{matcher?, hooks: [{type, command}]}`
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

    enum EditError: LocalizedError {
        case unreadableConfig(URL, Error)
        case invalidRoot(URL)
        case incompatibleHooks(URL)
        case incompatibleEvent(URL, String)

        var errorDescription: String? {
            switch self {
            case .unreadableConfig(let url, let error):
                return "Couldn't read or parse \(url.path): \(error.localizedDescription)"
            case .invalidRoot(let url):
                return "\(url.path) must contain a JSON object"
            case .incompatibleHooks(let url):
                return "The hooks value in \(url.path) must be a JSON object"
            case .incompatibleEvent(let url, let event):
                return "The hooks.\(event) value in \(url.path) must be an array of hook objects"
            }
        }
    }

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
        // Missing files are created, but an existing unreadable or structurally
        // incompatible config is never treated as empty. Silently doing so
        // would overwrite the user's settings just because one integration
        // could not understand them.
        var root = try rootForInstall(at: url)
        for (key, value) in rootDefaults where root[key] == nil {
            root[key] = value
        }
        let hooksValue = root["hooks"]
        guard hooksValue == nil || hooksValue is [String: Any] else {
            throw EditError.incompatibleHooks(url)
        }
        var hooks = hooksValue as? [String: Any] ?? [:]

        for event in events {
            let eventValue = hooks[event]
            guard eventValue == nil || eventValue is [[String: Any]] else {
                throw EditError.incompatibleEvent(url, event)
            }
            var groups = eventValue as? [[String: Any]] ?? []
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

    /// Strict reader for mutation: unlike the read-only probe above, this
    /// distinguishes a missing file (safe to create) from an existing file we
    /// failed to understand (must be preserved byte-for-byte).
    private static func rootForInstall(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw EditError.unreadableConfig(url, error)
        }

        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw EditError.unreadableConfig(url, error)
        }
        guard let root = json as? [String: Any] else {
            throw EditError.invalidRoot(url)
        }
        return root
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
