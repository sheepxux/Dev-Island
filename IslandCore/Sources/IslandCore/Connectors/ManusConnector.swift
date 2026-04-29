import Foundation

public final class ManusConnector: AgentConnector, Sendable {
    public let source = "manus"
    let client: ManusAPIClient

    public init(client: ManusAPIClient) {
        self.client = client
    }

    public func fetchTasks() async throws -> [AgentTask] {
        try await client.listTasks()
    }

    public func openInBrowser(taskId: String) {
        // URL lookup and NSWorkspace.open are handled by TaskStore.openTaskInBrowser(id:).
        // Direct calls to this method are a no-op by design.
        IslandLogger.store.warning("openInBrowser called directly on ManusConnector — use TaskStore.openTaskInBrowser(id:)")
    }

    public func stop(taskId: String) async throws {
        try await client.stopTask(id: taskId)
    }
}
