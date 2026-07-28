import Foundation

final class PollingFallback: Sendable {
    private let connector: any AgentConnector
    private let interval: TimeInterval
    nonisolated(unsafe) private var pollingTask: Task<Void, Never>?

    init(connector: any AgentConnector, interval: TimeInterval = 60) {
        self.connector = connector
        self.interval = interval
    }

    func start(
        onSnapshot: @escaping @Sendable ([AgentTask]) -> Void,
        onNetworkError: @escaping @Sendable () -> Void,
        onNetworkRestored: @escaping @Sendable () -> Void
    ) {
        var wasOffline = false
        pollingTask = Task {
            while !Task.isCancelled {
                do {
                    let tasks = try await connector.fetchTasks()
                    if wasOffline {
                        wasOffline = false
                        onNetworkRestored()
                    }
                    onSnapshot(tasks)
                    IslandLogger.sync.debug("Poll succeeded — \(tasks.count) tasks")
                } catch ManusError.networkUnavailable {
                    if !wasOffline {
                        wasOffline = true
                        onNetworkError()
                    }
                    IslandLogger.sync.warning("Network unavailable — will retry in \(Int(self.interval))s")
                } catch ManusError.rateLimited(let retryAfter) {
                    // 等待指定退避时间再重试，不重置 wasOffline 状态
                    IslandLogger.sync.warning("Poll rate limited — waiting \(Int(retryAfter))s")
                    try? await Task.sleep(for: .seconds(retryAfter))
                    continue
                } catch ManusError.unauthorized {
                    // 401 由 TaskStore 处理，停止轮询
                    IslandLogger.sync.error("Poll unauthorized — stopping")
                    return
                } catch {
                    IslandLogger.sync.error("Poll error: \(error)")
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        IslandLogger.sync.info("Polling stopped")
    }
}
