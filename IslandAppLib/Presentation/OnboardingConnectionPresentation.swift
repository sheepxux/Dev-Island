import Foundation
import IslandCore

/// Owns the lifetime of Welcome's read-only Hook scan and its user-initiated
/// configuration transaction. Refreshes are latest-wins; one mutation owns
/// the surface until its atomic filesystem work and final read-back finish.
/// Invalidating the state only drops UI ownership—it never cancels a write
/// that may already have entered a managed-config transaction.
struct OnboardingConnectionOperationState: Equatable {
    private(set) var activeRefreshID: UUID?
    private(set) var activeMutationID: UUID?
    private(set) var workingSources: Set<String> = []
    private(set) var isBulkUpdating = false

    var isBusy: Bool {
        activeRefreshID != nil || activeMutationID != nil
    }

    @discardableResult
    mutating func beginRefresh(id: UUID = UUID()) -> UUID? {
        guard activeMutationID == nil else { return nil }
        activeRefreshID = id
        return id
    }

    @discardableResult
    mutating func beginMutation(
        sources: Set<String>,
        isBulk: Bool,
        id: UUID = UUID()
    ) -> UUID? {
        guard activeMutationID == nil, !sources.isEmpty else { return nil }

        // A mutation is newer than every scan already in flight. The scan is
        // allowed to finish its read-only work, but can no longer update UI.
        activeRefreshID = nil
        activeMutationID = id
        workingSources = sources
        isBulkUpdating = isBulk
        return id
    }

    @discardableResult
    mutating func completeRefresh(id: UUID) -> Bool {
        guard activeRefreshID == id else { return false }
        activeRefreshID = nil
        return true
    }

    @discardableResult
    mutating func completeMutation(id: UUID) -> Bool {
        guard activeMutationID == id else { return false }
        activeMutationID = nil
        workingSources = []
        isBulkUpdating = false
        return true
    }

    mutating func invalidate() {
        activeRefreshID = nil
        activeMutationID = nil
        workingSources = []
        isBulkUpdating = false
    }
}

/// The mutation result includes a fresh diagnostic snapshot. Welcome must not
/// infer Connected merely because `install()` returned: a partial/external
/// edit or vendor trust gate is represented by the state actually read back.
struct OnboardingConnectionMutationOutcome: Equatable, Sendable {
    let snapshot: LocalAgentHookHealthSnapshot
    let failedSources: Set<String>
}

enum OnboardingConnectionWorker {
    static func inspect() -> LocalAgentHookHealthSnapshot {
        LocalAgentHookDiagnostics.snapshotResolvingVendorActivation()
    }

    static func install(
        _ descriptors: [LocalAgentDescriptor]
    ) -> OnboardingConnectionMutationOutcome {
        var writeFailedSources: Set<String> = []

        for descriptor in descriptors {
            do {
                try LocalHooksInstaller(descriptor).install()
            } catch {
                writeFailedSources.insert(descriptor.source)
            }
        }

        return classifyMutation(
            targetSources: Set(descriptors.map(\.source)),
            writeFailedSources: writeFailedSources,
            snapshot: inspect()
        )
    }

    /// Pure classification seam used by regression tests. A target is only a
    /// success when the write completed and the final diagnostic is either
    /// connected or configured pending a documented vendor trust review.
    static func classifyMutation(
        targetSources: Set<String>,
        writeFailedSources: Set<String>,
        snapshot: LocalAgentHookHealthSnapshot
    ) -> OnboardingConnectionMutationOutcome {
        let states = Dictionary(uniqueKeysWithValues: snapshot.agents.map {
            ($0.source, $0.state)
        })
        let failedSources = Set(targetSources.filter { source in
            guard !writeFailedSources.contains(source) else { return true }
            switch states[source] {
            case .connected?, .configured?: return false
            case .updateRequired?, .disconnected?, nil: return true
            }
        })

        return OnboardingConnectionMutationOutcome(
            snapshot: snapshot,
            failedSources: failedSources
        )
    }
}
