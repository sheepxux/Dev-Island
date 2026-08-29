import Foundation

/// Merge-based editing of hook config files that share a
/// `{"hooks": {"Event": [entry, …]}}` layout. Two entry shapes exist:
///
/// - nested (Claude Code `~/.claude/settings.json`, Gemini CLI
///   `~/.gemini/settings.json`, Codex `~/.codex/hooks.json`):
///   `{matcher?, hooks: [{type, command}]}`
/// - flat versioned (Cursor and Copilot CLI user Hook files): `{command}`
///   directly
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
        case incompatibleRootValue(URL, String)

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
            case .incompatibleRootValue(let url, let key):
                return "The \(key) value in \(url.path) is incompatible with this Hook format"
            }
        }
    }

    static func isInstalled(
        at url: URL,
        commandsByEvent: [String: String],
        matchersByEvent: [String: String] = [:],
        handlerTimeoutsByEvent: [String: Int] = [:],
        handlerStatusMessagesByEvent: [String: String] = [:],
        requiredRootValues: [String: Any] = [:],
        marker: String
    ) -> Bool {
        guard let root = readRoot(at: url),
              let hooks = root["hooks"] as? [String: Any] else { return false }
        guard requiredRootValues.allSatisfy({ key, expected in
            guard let existing = root[key] else { return false }
            return jsonValuesEqual(existing, expected)
        }) else { return false }
        // Installed = every event carries the current exact command. This
        // intentionally marks an older passive PermissionRequest hook stale
        // so Settings can reinstall the new bidirectional form.
        return commandsByEvent.allSatisfy { event, expectedCommand in
            guard let groups = hooks[event] as? [[String: Any]] else { return false }
            return groups.contains { group in
                guard matchersByEvent[event].map({
                    group["matcher"] as? String == $0
                }) != false else { return false }

                if let handlers = group["hooks"] as? [[String: Any]] {
                    return handlers.contains { handler in
                        guard handler["command"] as? String == expectedCommand else {
                            return false
                        }
                        if let timeout = handlerTimeoutsByEvent[event],
                           handler["timeout"] as? Int != timeout {
                            return false
                        }
                        if let message = handlerStatusMessagesByEvent[event],
                           handler["statusMessage"] as? String != message {
                            return false
                        }
                        return true
                    }
                }
                return group["command"] as? String == expectedCommand
            }
        }
    }

    /// Whether the config contains any entry previously written by Dev
    /// Island, regardless of its exact command version. Settings uses this
    /// to distinguish "Update" from a genuinely new "Enable" action.
    static func containsManagedEntries(at url: URL, marker: String) -> Bool {
        guard let data = ManagedConfigFile.boundedReadForManagedMarker(at: url) else {
            return false
        }
        if let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let hooks = root["hooks"] as? [String: Any] {
            return hooks.values.contains { value in
                guard let groups = value as? [[String: Any]] else {
                    return containsMarker(in: value, marker: marker)
                }
                return groups.contains {
                    commands(in: $0).contains(where: { $0.contains(marker) })
                }
            }
        }
        // A malformed file that still contains our endpoint must not be
        // reported as disconnected. The next edit will fail closed and ask
        // the user to repair the file instead of silently leaving our Hook.
        return dataContainsMarker(data, marker: marker)
    }

    /// `rootDefaults` are top-level keys written only when absent — e.g.
    /// Cursor's hooks file requires `"version": 1`, but a user-set value
    /// must never be overwritten.
    static func install(
        at url: URL,
        groupsByEvent: [String: [String: Any]],
        marker: String,
        rootDefaults: [String: Any] = [:]
    ) throws {
        // A missing file is safe to create. An existing file that cannot be
        // parsed or whose hook containers have incompatible types must remain
        // byte-for-byte untouched; treating it as empty would destroy user
        // settings merely because one integration could not understand them.
        let original = try ManagedConfigFile.snapshotIfExists(at: url)
        var root = try rootForInstall(from: original?.data, at: url)
        for (key, value) in rootDefaults {
            if let existing = root[key] {
                guard jsonValuesEqual(existing, value) else {
                    throw EditError.incompatibleRootValue(url, key)
                }
            } else {
                root[key] = value
            }
        }
        let hooksValue = root["hooks"]
        guard hooksValue == nil || hooksValue is [String: Any] else {
            throw EditError.incompatibleHooks(url)
        }
        var hooks = hooksValue as? [String: Any] ?? [:]

        for event in groupsByEvent.keys.sorted() {
            guard let group = groupsByEvent[event] else { continue }
            let eventValue = hooks[event]
            guard eventValue == nil || eventValue is [[String: Any]] else {
                throw EditError.incompatibleEvent(url, event)
            }
            var groups = eventValue as? [[String: Any]] ?? []
            groups = groups.compactMap {
                removingManagedCommands(from: $0, marker: marker).group
            }
            groups.append(group)
            hooks[event] = groups
        }

        root["hooks"] = hooks
        try writeRoot(
            root,
            to: url,
            expecting: original.map(ManagedConfigFile.ExpectedState.snapshot) ?? .absent
        )
    }

    static func uninstall(at url: URL, marker: String) throws {
        guard let original = try ManagedConfigFile.snapshotIfExists(at: url),
              let data = try preparedUninstall(
                from: original.data,
                at: url,
                marker: marker
              ) else { return }
        try writeData(data, to: url, expecting: .snapshot(original))
    }

    /// Build the exact uninstall bytes without touching disk. Bulk maintenance
    /// can prepare every Agent first, then commit them with rollback instead
    /// of discovering a malformed fourth config after changing the first three.
    static func preparedUninstall(at url: URL, marker: String) throws -> Data? {
        guard let original = try ManagedConfigFile.snapshotIfExists(at: url) else {
            return nil
        }
        return try preparedUninstall(from: original.data, at: url, marker: marker)
    }

    static func preparedUninstall(
        from original: Data,
        at url: URL,
        marker: String
    ) throws -> Data? {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: original)
        } catch {
            guard dataContainsMarker(original, marker: marker) else { return nil }
            throw EditError.unreadableConfig(url, error)
        }
        guard containsMarker(in: json, marker: marker) else { return nil }
        guard var root = json as? [String: Any] else {
            throw EditError.invalidRoot(url)
        }
        guard let hooksValue = root["hooks"] else { return nil }
        guard var hooks = hooksValue as? [String: Any] else {
            if containsMarker(in: hooksValue, marker: marker) {
                throw EditError.incompatibleHooks(url)
            }
            return nil
        }

        var changed = false

        for (event, value) in hooks {
            guard let currentGroups = value as? [[String: Any]] else {
                if containsMarker(in: value, marker: marker) {
                    throw EditError.incompatibleEvent(url, event)
                }
                continue
            }
            var groups: [[String: Any]] = []
            for group in currentGroups {
                let removal = removingManagedCommands(from: group, marker: marker)
                changed = changed || removal.didRemove
                if let group = removal.group { groups.append(group) }
            }
            if groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = groups
            }
        }

        guard changed else { return nil }
        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        return try serializedRoot(root)
    }

    // MARK: - Private

    private static func removingManagedCommands(
        from group: [String: Any],
        marker: String
    ) -> (group: [String: Any]?, didRemove: Bool) {
        if let handlers = group["hooks"] as? [[String: Any]] {
            let kept = handlers.filter { handler in
                guard let command = handler["command"] as? String else { return true }
                return !command.contains(marker)
            }
            guard kept.count != handlers.count else { return (group, false) }
            guard !kept.isEmpty else { return (nil, true) }
            var edited = group
            edited["hooks"] = kept
            return (edited, true)
        }
        if let command = group["command"] as? String, command.contains(marker) {
            return (nil, true)
        }
        return (group, false)
    }

    private static func commands(in group: [String: Any]) -> [String] {
        if let handlers = group["hooks"] as? [[String: Any]] {
            return handlers.compactMap { $0["command"] as? String }
        }
        return (group["command"] as? String).map { [$0] } ?? []
    }

    private static func readRoot(at url: URL) -> [String: Any]? {
        guard let data = try? ManagedConfigFile.snapshotIfExists(at: url)?.data else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func dataContainsMarker(_ data: Data, marker: String) -> Bool {
        let candidates = [marker, marker.replacingOccurrences(of: "/", with: "\\/")]
        return candidates.contains { candidate in
            guard let markerData = candidate.data(using: .utf8) else { return false }
            return data.range(of: markerData) != nil
        }
    }

    private static func containsMarker(in value: Any, marker: String) -> Bool {
        if let string = value as? String { return string.contains(marker) }
        if let array = value as? [Any] {
            return array.contains { containsMarker(in: $0, marker: marker) }
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.contains { containsMarker(in: $0, marker: marker) }
        }
        return false
    }

    /// Config roots come from JSONSerialization, so primitive equality must
    /// use Foundation bridging (`NSNumber(1)` vs Swift `Int(1)`).
    private static func jsonValuesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        guard let left = lhs as? NSObject else { return false }
        return left.isEqual(rhs)
    }

    private static func rootForInstall(
        from data: Data?,
        at url: URL
    ) throws -> [String: Any] {
        guard let data else { return [:] }

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

    private static func writeRoot(
        _ root: [String: Any],
        to url: URL,
        expecting expected: ManagedConfigFile.ExpectedState
    ) throws {
        try writeData(serializedRoot(root), to: url, expecting: expected)
    }

    @discardableResult
    static func writeData(
        _ data: Data,
        to url: URL,
        expecting expected: ManagedConfigFile.ExpectedState,
        permissions: Int? = nil,
        maximumBytes: Int = ManagedConfigFile.maximumConfigBytes
    ) throws -> ManagedConfigFile.Snapshot {
        try ManagedConfigFile.replace(
            data,
            at: url,
            expecting: expected,
            permissions: permissions,
            maximumBytes: maximumBytes
        )
    }

    private static func serializedRoot(_ root: [String: Any]) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
    }
}
