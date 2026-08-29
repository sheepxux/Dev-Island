import Foundation
import IslandCore
import Observation

enum AgentUsageLoadStatus: Equatable {
    case idle
    case loading
    case available
    case unavailable
    case failed
}

/// Opt-in, on-demand usage reader for Settings. It never polls in the
/// background and never turns a missing provider file into an app-level error.
@MainActor
@Observable
final class AgentUsageController {
    private(set) var status: AgentUsageLoadStatus = .idle
    private(set) var snapshot: AgentUsageSnapshot?

    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    deinit {
        refreshTask?.cancel()
    }

    func disable() {
        refreshTask?.cancel()
        refreshTask = nil
        snapshot = nil
        status = .idle
    }

    func refresh(reader: CodexLocalUsageReader = CodexLocalUsageReader()) {
        refreshTask?.cancel()
        status = .loading

        refreshTask = Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .utility) {
                do {
                    return UsageLoadResult.loaded(try reader.latestSnapshot())
                } catch {
                    return .failed
                }
            }.value

            guard !Task.isCancelled, let self else { return }
            switch result {
            case .loaded(let snapshot):
                self.snapshot = snapshot
                self.status = snapshot == nil ? .unavailable : .available
            case .failed:
                self.snapshot = nil
                self.status = .failed
            }
        }
    }
}

private enum UsageLoadResult: Sendable {
    case loaded(AgentUsageSnapshot?)
    case failed
}
