import Foundation
import IslandCore

/// One mutation owner for the complete Settings Agent Connections surface.
/// The value is stored by `SettingsView`, above the selected-pane switch, so
/// changing panes cannot forget a configuration transaction that is still
/// running in the background.
enum LocalAgentConnectionsMutation: Equatable, Sendable {
    case agent(source: String, operation: LocalAgentConfigurationOperation)
    case disconnectAll
}

enum LocalAgentMaintenanceOutcome: Equatable, Sendable {
    case noChanges
    case disconnected(count: Int)
    case failed
}

struct LocalAgentConnectionsOperationState: Equatable {
    private(set) var activeOperationID: UUID?
    private(set) var activeMutation: LocalAgentConnectionsMutation?
    private(set) var maintenanceOutcome: LocalAgentMaintenanceOutcome?
    private(set) var completionGeneration: UInt64 = 0

    var isMutating: Bool { activeOperationID != nil }
    var isDisconnectingAll: Bool { activeMutation == .disconnectAll }

    @discardableResult
    mutating func beginAgentMutation(
        source: String,
        operation: LocalAgentConfigurationOperation,
        id: UUID = UUID()
    ) -> UUID? {
        guard activeOperationID == nil else { return nil }
        activeOperationID = id
        activeMutation = .agent(source: source, operation: operation)
        maintenanceOutcome = nil
        return id
    }

    @discardableResult
    mutating func beginDisconnectAll(id: UUID = UUID()) -> UUID? {
        guard activeOperationID == nil else { return nil }
        activeOperationID = id
        activeMutation = .disconnectAll
        maintenanceOutcome = nil
        return id
    }

    @discardableResult
    mutating func cancel(_ id: UUID) -> Bool {
        guard activeOperationID == id else { return false }
        activeOperationID = nil
        activeMutation = nil
        return true
    }

    @discardableResult
    mutating func completeAgentMutation(_ id: UUID) -> Bool {
        guard activeOperationID == id else { return false }
        guard case .agent = activeMutation else { return false }
        activeOperationID = nil
        activeMutation = nil
        completionGeneration &+= 1
        return true
    }

    @discardableResult
    mutating func completeDisconnectAll(
        _ outcome: LocalAgentMaintenanceOutcome,
        for id: UUID
    ) -> Bool {
        guard activeOperationID == id,
              activeMutation == .disconnectAll else { return false }
        activeOperationID = nil
        activeMutation = nil
        maintenanceOutcome = outcome
        completionGeneration &+= 1
        return true
    }

    mutating func clearMaintenanceOutcome() {
        maintenanceOutcome = nil
    }
}

/// Low-cardinality adapter around the cross-file maintenance transaction.
/// Raw file paths, sources, and rollback errors stay inside the worker.
enum LocalAgentMaintenanceWorker {
    static func disconnectAll() -> LocalAgentMaintenanceOutcome {
        do {
            let result = try LocalAgentHookMaintenance.removeAllManagedHooks()
            return result.wasNoOp
                ? .noChanges
                : .disconnected(count: result.removedCount)
        } catch {
            return .failed
        }
    }
}
