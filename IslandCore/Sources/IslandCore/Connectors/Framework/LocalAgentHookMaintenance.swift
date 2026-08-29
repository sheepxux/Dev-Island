import Foundation

public struct LocalAgentHookRemovalResult: Equatable, Sendable {
    public let removedSources: [String]

    public var removedCount: Int { removedSources.count }
    public var wasNoOp: Bool { removedSources.isEmpty }
}

public enum LocalAgentHookMaintenanceError: LocalizedError, Equatable, Sendable {
    case couldNotPrepare(source: String)
    case configurationChanged(source: String, rollbackConflicts: [String])
    case writeFailed(source: String, rollbackConflicts: [String])

    public var requiresManualReview: Bool {
        switch self {
        case .couldNotPrepare:
            false
        case .configurationChanged(_, let conflicts), .writeFailed(_, let conflicts):
            !conflicts.isEmpty
        }
    }

    public var errorDescription: String? {
        switch self {
        case .couldNotPrepare(let source):
            return "Couldn't safely read the \(source) configuration. No changes were made."
        case .configurationChanged(let source, let conflicts):
            if conflicts.isEmpty {
                return "The \(source) configuration changed during disconnect. Earlier changes were restored."
            }
            return "The \(source) configuration changed during disconnect. Review \(conflicts.joined(separator: ", ")) manually."
        case .writeFailed(let source, let conflicts):
            if conflicts.isEmpty {
                return "Couldn't disconnect \(source). Earlier changes were restored."
            }
            return "Couldn't disconnect \(source). Review \(conflicts.joined(separator: ", ")) manually."
        }
    }
}

/// Cross-file maintenance for the registry-driven local Agent integrations.
/// Every edit is prepared before the first write. A later failure rolls back
/// only files that still equal our planned bytes, so an external edit is never
/// overwritten merely to simulate transactionality across separate files.
public enum LocalAgentHookMaintenance {
    public static func hasManagedHooks() -> Bool {
        LocalAgentRegistry.all.contains {
            LocalHooksInstaller($0).hasManagedEntries()
        }
    }

    @discardableResult
    public static func removeAllManagedHooks() throws -> LocalAgentHookRemovalResult {
        try removeAllManagedHooks(
            descriptors: LocalAgentRegistry.all,
            configURLsBySource: [:]
        )
    }

    // Internal injection points keep production behavior registry-driven while
    // allowing deterministic rollback/concurrent-edit tests in temporary dirs.
    @discardableResult
    static func removeAllManagedHooks(
        descriptors: [LocalAgentDescriptor],
        configURLsBySource: [String: URL],
        beforeWrite: ((_ source: String, _ url: URL, _ index: Int) throws -> Void)? = nil
    ) throws -> LocalAgentHookRemovalResult {
        let grouped = groupedTargets(
            descriptors: descriptors,
            configURLsBySource: configURLsBySource
        )
        var changes: [PreparedChange] = []

        // Prepare every file first. No bytes have changed if any config is
        // unreadable, malformed around our marker, or structurally unsafe.
        for group in grouped {
            guard StandalonePluginFileEditor.pathEntryExists(at: group.url) else { continue }
            let original: Data
            let permissions: Int?
            let originalSnapshot: ManagedConfigFile.Snapshot
            let maximumBytes: Int
            let isStandalonePlugin = group.targets.contains {
                if case .standaloneJavaScriptPlugin = $0.descriptor.hookEntryStyle {
                    return true
                }
                return false
            }
            do {
                // A complete-file plugin cannot safely share one path with a
                // structured JSON/TOML editor (or another plugin owner).
                guard !isStandalonePlugin || group.targets.count == 1 else {
                    throw LocalAgentHookMaintenanceError.couldNotPrepare(
                        source: group.targets.first?.descriptor.source ?? "local Agent"
                    )
                }
                if isStandalonePlugin {
                    let snapshot = try StandalonePluginFileEditor.snapshot(at: group.url)
                    original = snapshot.data
                    permissions = snapshot.permissions
                    originalSnapshot = snapshot.fileSnapshot
                    maximumBytes = StandalonePluginFileEditor.maximumPluginBytes
                } else {
                    guard let snapshot = try ManagedConfigFile.snapshotIfExists(at: group.url) else {
                        throw LocalAgentHookMaintenanceError.couldNotPrepare(
                            source: group.targets.first?.descriptor.source ?? "local Agent"
                        )
                    }
                    original = snapshot.data
                    permissions = snapshot.permissions
                    originalSnapshot = snapshot
                    maximumBytes = ManagedConfigFile.maximumConfigBytes
                }
            } catch {
                let source = group.targets.first?.descriptor.source ?? "local Agent"
                IslandLogger.store.error("Couldn't snapshot local Hook configuration for \(source)")
                throw LocalAgentHookMaintenanceError.couldNotPrepare(source: source)
            }

            var updated: Data? = original
            var removedSources: [String] = []
            for target in group.targets {
                do {
                    guard let current = updated else {
                        throw LocalAgentHookMaintenanceError.couldNotPrepare(
                            source: target.descriptor.source
                        )
                    }
                    switch try LocalHooksInstaller(target.descriptor)
                        .preparedUninstall(from: current, at: group.url) {
                    case .unchanged:
                        break
                    case .replace(let next):
                        updated = next
                        removedSources.append(target.descriptor.source)
                    case .removeFile:
                        updated = nil
                        removedSources.append(target.descriptor.source)
                    }
                } catch {
                    IslandLogger.store.error("Couldn't prepare local Hook removal for \(target.descriptor.source)")
                    throw LocalAgentHookMaintenanceError.couldNotPrepare(
                        source: target.descriptor.source
                    )
                }
            }

            guard updated != Optional(original) else { continue }
            changes.append(PreparedChange(
                url: group.url,
                original: original,
                updated: updated,
                permissions: permissions,
                originalSnapshot: originalSnapshot,
                maximumBytes: maximumBytes,
                sources: removedSources,
                isStandalonePlugin: isStandalonePlugin
            ))
        }

        var written: [WrittenChange] = []
        for (index, change) in changes.enumerated() {
            let source = change.sources.first ?? "local Agent"
            do {
                try beforeWrite?(source, change.url, index)
                let committedSnapshot: ManagedConfigFile.Snapshot?
                if let updated = change.updated {
                    committedSnapshot = try HookConfigEditor.writeData(
                        updated,
                        to: change.url,
                        expecting: .snapshot(change.originalSnapshot),
                        permissions: change.permissions,
                        maximumBytes: change.maximumBytes
                    )
                } else {
                    try ManagedConfigFile.remove(
                        at: change.url,
                        expecting: change.originalSnapshot,
                        maximumBytes: change.maximumBytes
                    )
                    committedSnapshot = nil
                }
                written.append(WrittenChange(
                    change: change,
                    committedSnapshot: committedSnapshot
                ))
            } catch let error as LocalAgentHookMaintenanceError {
                throw error
            } catch ManagedConfigFile.FileError.configurationChanged {
                let conflicts = rollback(written)
                throw LocalAgentHookMaintenanceError.configurationChanged(
                    source: source,
                    rollbackConflicts: conflicts
                )
            } catch {
                IslandLogger.store.error("Couldn't write local Hook removal for \(source)")
                let conflicts = rollback(written)
                throw LocalAgentHookMaintenanceError.writeFailed(
                    source: source,
                    rollbackConflicts: conflicts
                )
            }
        }

        return LocalAgentHookRemovalResult(
            removedSources: changes.flatMap(\.sources)
        )
    }

    private struct Target {
        let descriptor: LocalAgentDescriptor
    }

    private struct TargetGroup {
        let url: URL
        var targets: [Target]
    }

    private struct PreparedChange {
        let url: URL
        let original: Data
        let updated: Data?
        let permissions: Int?
        let originalSnapshot: ManagedConfigFile.Snapshot
        let maximumBytes: Int
        let sources: [String]
        let isStandalonePlugin: Bool
    }

    private struct WrittenChange {
        let change: PreparedChange
        let committedSnapshot: ManagedConfigFile.Snapshot?
    }

    private static func groupedTargets(
        descriptors: [LocalAgentDescriptor],
        configURLsBySource: [String: URL]
    ) -> [TargetGroup] {
        var groups: [TargetGroup] = []
        for descriptor in descriptors {
            let url = configURLsBySource[descriptor.source] ?? descriptor.configURL
            if let index = groups.firstIndex(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
                groups[index].targets.append(Target(descriptor: descriptor))
            } else {
                groups.append(TargetGroup(url: url, targets: [Target(descriptor: descriptor)]))
            }
        }
        return groups
    }

    private static func rollback(_ changes: [WrittenChange]) -> [String] {
        var conflicts: [String] = []
        for written in changes.reversed() {
            let change = written.change
            do {
                let expected: ManagedConfigFile.ExpectedState
                if let committed = written.committedSnapshot {
                    expected = .snapshot(committed)
                } else {
                    expected = .absent
                }
                try HookConfigEditor.writeData(
                    change.original,
                    to: change.url,
                    expecting: expected,
                    permissions: change.permissions,
                    maximumBytes: change.maximumBytes
                )
            } catch {
                conflicts.append(contentsOf: change.sources)
            }
        }
        return conflicts
    }
}
