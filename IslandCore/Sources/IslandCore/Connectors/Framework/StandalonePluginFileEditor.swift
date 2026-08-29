import Foundation

/// Safe ownership boundary for a vendor-loaded standalone plugin file.
///
/// Unlike JSON/TOML Hook configs, a local plugin path contains no user-owned
/// siblings inside the file: Dev Island either owns the complete marked file
/// or leaves it untouched. Symlinks, directories, devices, oversized files
/// and unmarked collisions fail closed.
enum StandalonePluginFileEditor {
    static let maximumPluginBytes = 256 * 1_024
    static let installedPermissions = 0o600

    enum EditError: LocalizedError {
        case occupied(URL)
        case unsafeFile(URL)
        case unreadableFile(URL)
        case invalidGeneratedPlugin

        var errorDescription: String? {
            switch self {
            case .occupied:
                return "A non-Dev-Island plugin already exists at this path."
            case .unsafeFile:
                return "The plugin path is not a safe regular file."
            case .unreadableFile:
                return "The plugin file could not be read safely."
            case .invalidGeneratedPlugin:
                return "The generated plugin is missing its ownership marker."
            }
        }
    }

    struct Snapshot {
        let data: Data
        let permissions: Int?
        let fileSnapshot: ManagedConfigFile.Snapshot
    }

    /// Snapshot used by cross-file maintenance. It applies the same bounded,
    /// no-symlink regular-file boundary as individual install/uninstall paths
    /// before any other connector file can be changed.
    static func snapshot(at url: URL) throws -> Snapshot {
        guard let snapshot = try ManagedConfigFile.snapshotIfExists(
            at: url,
            maximumBytes: maximumPluginBytes
        ) else { throw EditError.unsafeFile(url) }
        return Snapshot(
            data: snapshot.data,
            permissions: snapshot.permissions,
            fileSnapshot: snapshot
        )
    }

    static func currentDataForComparison(at url: URL) throws -> Data {
        try snapshot(at: url).data
    }

    /// `FileManager.fileExists` follows links and reports false for dangling
    /// links. Maintenance needs an lstat-style answer so an externally
    /// recreated dangling link is treated as a rollback conflict, never
    /// silently replaced.
    static func pathEntryExists(at url: URL) -> Bool {
        ManagedConfigFile.pathEntryExists(at: url)
    }

    static func isInstalled(
        at url: URL,
        expected: Data,
        marker: String
    ) -> Bool {
        guard expectedContainsMarker(expected, marker: marker),
              let current = try? ManagedConfigFile.snapshotIfExists(
                at: url,
                maximumBytes: maximumPluginBytes
              )?.data
        else { return false }
        return current == expected
    }

    /// Read-only and intentionally conservative. Following a symlink here is
    /// acceptable only to surface "managed but unsafe" as update-required;
    /// every mutating path independently rejects the symlink with `lstat`.
    static func containsManagedEntries(at url: URL, marker: String) -> Bool {
        guard let data = ManagedConfigFile.boundedReadForManagedMarker(
            at: url,
            maximumBytes: maximumPluginBytes
        ) else { return false }
        return containsMarker(data, marker: marker)
    }

    static func install(
        at url: URL,
        expected: Data,
        marker: String
    ) throws {
        guard expectedContainsMarker(expected, marker: marker),
              expected.count <= maximumPluginBytes
        else { throw EditError.invalidGeneratedPlugin }

        let current = try ManagedConfigFile.snapshotIfExists(
            at: url,
            maximumBytes: maximumPluginBytes
        )
        if let current {
            guard current.data == expected || containsMarker(current.data, marker: marker) else {
                throw EditError.occupied(url)
            }
            try HookConfigEditor.writeData(
                expected,
                to: url,
                expecting: .snapshot(current),
                permissions: installedPermissions,
                maximumBytes: maximumPluginBytes
            )
        } else {
            try HookConfigEditor.writeData(
                expected,
                to: url,
                expecting: .absent,
                permissions: installedPermissions,
                maximumBytes: maximumPluginBytes
            )
        }
    }

    static func uninstall(at url: URL, marker: String) throws {
        guard let current = try ManagedConfigFile.snapshotIfExists(
            at: url,
            maximumBytes: maximumPluginBytes
        ) else { return }
        guard containsMarker(current.data, marker: marker) else { return }
        try ManagedConfigFile.remove(
            at: url,
            expecting: current,
            maximumBytes: maximumPluginBytes
        )
    }

    static func shouldRemoveManagedFile(
        from data: Data,
        at url: URL,
        marker: String
    ) throws -> Bool {
        guard data.count <= maximumPluginBytes else {
            throw EditError.unreadableFile(url)
        }
        guard let current = try ManagedConfigFile.snapshotIfExists(
            at: url,
            maximumBytes: maximumPluginBytes
        ), current.data == data else { throw EditError.unsafeFile(url) }
        return containsMarker(data, marker: marker)
    }

    private static func expectedContainsMarker(_ data: Data, marker: String) -> Bool {
        !marker.isEmpty && containsMarker(data, marker: marker)
    }

    private static func containsMarker(_ data: Data, marker: String) -> Bool {
        data.range(of: Data(marker.utf8)) != nil
    }
}
