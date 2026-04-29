import Foundation

public protocol AgentConnector: Sendable {
    var source: String { get }
    func fetchTasks() async throws -> [AgentTask]
    func openInBrowser(taskId: String)
    func stop(taskId: String) async throws
}
