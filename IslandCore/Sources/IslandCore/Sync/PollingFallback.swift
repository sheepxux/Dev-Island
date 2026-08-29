import Foundation

/// Cancellation-safe Manus polling. Actor isolation replaces the former
/// unsafely shared task slot and a lifecycle generation suppresses late
/// connector results after stop or restart.
actor PollingFallback {
    private let connector: any AgentConnector
    private let interval: TimeInterval
    private var pollingTask: Task<Void, Never>?
    private var lifecycleGeneration: UInt64 = 0

    init(connector: any AgentConnector, interval: TimeInterval = 60) {
        self.connector = connector
        self.interval = interval
    }

    func start(
        onSnapshot: @escaping @Sendable ([AgentTask]) async -> Void,
        onNetworkError: @escaping @Sendable () async -> Void,
        onNetworkRestored: @escaping @Sendable () async -> Void,
        onUnauthorized: @escaping @Sendable () async -> Void
    ) {
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            await self?.run(
                generation: generation,
                onSnapshot: onSnapshot,
                onNetworkError: onNetworkError,
                onNetworkRestored: onNetworkRestored,
                onUnauthorized: onUnauthorized
            )
        }
    }

    func stop() {
        lifecycleGeneration &+= 1
        pollingTask?.cancel()
        pollingTask = nil
        IslandLogger.sync.info("Polling stopped")
    }

    private func run(
        generation: UInt64,
        onSnapshot: @escaping @Sendable ([AgentTask]) async -> Void,
        onNetworkError: @escaping @Sendable () async -> Void,
        onNetworkRestored: @escaping @Sendable () async -> Void,
        onUnauthorized: @escaping @Sendable () async -> Void
    ) async {
        var wasOffline = false
        defer {
            if generation == lifecycleGeneration {
                pollingTask = nil
            }
        }

        while isCurrent(generation) {
            do {
                let tasks = try await connector.fetchTasks()
                guard isCurrent(generation) else { return }

                if wasOffline {
                    wasOffline = false
                    await onNetworkRestored()
                    guard isCurrent(generation) else { return }
                }

                await onSnapshot(tasks)
                guard isCurrent(generation) else { return }
                IslandLogger.sync.debug("Poll succeeded — \(tasks.count) tasks")
            } catch ManusError.networkUnavailable {
                guard isCurrent(generation) else { return }
                if !wasOffline {
                    wasOffline = true
                    await onNetworkError()
                    guard isCurrent(generation) else { return }
                }
                IslandLogger.sync.warning(
                    "Network unavailable — will retry in \(Int(self.interval))s"
                )
            } catch ManusError.rateLimited(let retryAfter) {
                guard isCurrent(generation) else { return }
                // Respect the provider backoff without resetting offline state.
                IslandLogger.sync.warning(
                    "Poll rate limited — waiting \(Int(retryAfter))s"
                )
                try? await Task.sleep(for: .seconds(retryAfter))
                continue
            } catch ManusError.unauthorized {
                guard isCurrent(generation) else { return }
                IslandLogger.sync.error("Poll unauthorized — stopping")
                await onUnauthorized()
                return
            } catch {
                guard isCurrent(generation) else { return }
                IslandLogger.sync.error("Manus poll failed")
            }

            try? await Task.sleep(for: .seconds(self.interval))
        }
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        generation == lifecycleGeneration && !Task.isCancelled
    }
}
