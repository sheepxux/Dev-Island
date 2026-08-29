import Foundation
import IslandCore

/// UI-facing configuration state for one local Agent. The initial checking
/// state prevents Settings from briefly presenting an unsafe Enable action
/// before the existing configuration has been inspected off the main actor.
enum LocalAgentInstallationState: Equatable, Sendable {
    case checking
    case absent
    case current
    case updateRequired
}

/// The only user-initiated mutations exposed by a local-Agent row. Keeping the
/// expected terminal state explicit lets a successful filesystem call that is
/// immediately superseded by an external edit surface as a failure instead of
/// showing a false Connected state.
enum LocalAgentConfigurationOperation: Equatable, Sendable {
    case enable
    case update
    case disable

    var expectedState: LocalAgentInstallationState {
        switch self {
        case .enable, .update: return .current
        case .disable: return .absent
        }
    }

    var progressLocalizationKey: String {
        switch self {
        case .enable: return "Enabling…"
        case .update: return "Updating…"
        case .disable: return "Disabling…"
        }
    }
}

/// Latest-operation-wins coordinator for Settings configuration I/O. Refreshes
/// may supersede older refreshes, while a mutation is exclusive and cannot be
/// overwritten by a late scan. The filesystem work itself is intentionally
/// outside this value and always runs in a detached task.
struct LocalAgentInstallationOperationState: Equatable {
    private(set) var installationState: LocalAgentInstallationState
    private(set) var activeOperationID: UUID?
    private(set) var activeMutation: LocalAgentConfigurationOperation?

    init(installationState: LocalAgentInstallationState = .checking) {
        self.installationState = installationState
    }

    var isBusy: Bool { activeOperationID != nil }
    var isApplyingChange: Bool { activeMutation != nil }

    @discardableResult
    mutating func beginRefresh(id: UUID = UUID()) -> UUID? {
        guard activeMutation == nil else { return nil }
        activeOperationID = id
        return id
    }

    @discardableResult
    mutating func beginMutation(
        _ operation: LocalAgentConfigurationOperation,
        id: UUID = UUID()
    ) -> UUID? {
        guard activeOperationID == nil else { return nil }
        activeOperationID = id
        activeMutation = operation
        return id
    }

    @discardableResult
    mutating func accept(
        _ state: LocalAgentInstallationState,
        for id: UUID
    ) -> Bool {
        guard activeOperationID == id else { return false }
        installationState = state
        activeOperationID = nil
        activeMutation = nil
        return true
    }

    mutating func invalidate() {
        activeOperationID = nil
        activeMutation = nil
    }
}

struct LocalAgentConfigurationMutationOutcome: Equatable, Sendable {
    let installationState: LocalAgentInstallationState
    let succeeded: Bool
}

/// One testable hop from the main actor to blocking configuration work.
/// Settings and Welcome use this boundary for scans, installs and removals
/// instead of calling filesystem parsers or `fsync` paths directly.
enum LocalAgentConfigurationExecutor {
    static func run<Value: Sendable>(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () -> Value
    ) async -> Value {
        await Task.detached(priority: priority, operation: operation).value
    }
}

/// Synchronous worker functions called only through
/// `LocalAgentConfigurationExecutor`. They own no UI state and return only
/// low-cardinality results, so configuration bytes, paths and parser errors
/// never cross back to the main actor.
enum LocalAgentConfigurationWorker {
    static func inspect(
        installer: LocalHooksInstaller
    ) -> LocalAgentInstallationState {
        if installer.isInstalled() { return .current }
        return installer.hasManagedEntries() ? .updateRequired : .absent
    }

    static func perform(
        _ operation: LocalAgentConfigurationOperation,
        installer: LocalHooksInstaller
    ) -> LocalAgentConfigurationMutationOutcome {
        let writeCompleted: Bool
        do {
            switch operation {
            case .enable, .update:
                try installer.install()
            case .disable:
                try installer.uninstall()
            }
            writeCompleted = true
        } catch {
            writeCompleted = false
        }

        let state = inspect(installer: installer)
        return LocalAgentConfigurationMutationOutcome(
            installationState: state,
            succeeded: writeCompleted && state == operation.expectedState
        )
    }
}
