import Foundation
import Observation

/// Single source of truth for agent tasks.
///
/// Public surface is the contract between IslandApp (C) and IslandCore (S).
/// Any change to public symbols requires a CR per `docs/INTERFACE_CONTRACT.md`.
@Observable
public final class TaskStore {
    public static let shared = TaskStore()

    public private(set) var tasks: [AgentTask] = []
    public private(set) var connectionStatus: ConnectionStatus = .disconnected
    public private(set) var apiKeyStatus: APIKeyStatus = .notConfigured

    private init() {}

    public func configureAPIKey(_ key: String) async throws {
        // STUB: owned by S — Manus validate + Keychain write
        throw StubError.notImplemented("configureAPIKey")
    }

    public func clearAPIKey() {
        // STUB: owned by S — Keychain delete
    }

    public func openTaskInBrowser(id: String) {
        // STUB: owned by S — NSWorkspace.shared.open(taskURL)
    }

    public func stopTask(id: String) async throws {
        // STUB: owned by S — Manus cancel API
        throw StubError.notImplemented("stopTask")
    }

    private enum StubError: LocalizedError {
        case notImplemented(String)
        var errorDescription: String? {
            switch self {
            case .notImplemented(let name):
                return "TaskStore.\(name) is not yet implemented (S-owned)."
            }
        }
    }
}

#if DEBUG
extension TaskStore {
    /// Build an in-memory store with mock data for SwiftUI Previews and the
    /// Debug Sandbox. C-side only — S, please preserve this `#if DEBUG` block
    /// when replacing the stubs above.
    public static func mock(
        tasks: [AgentTask] = TaskStore.previewTasks,
        connection: ConnectionStatus = .connected,
        apiKey: APIKeyStatus = .valid
    ) -> TaskStore {
        let store = TaskStore()
        store.tasks = tasks
        store.connectionStatus = connection
        store.apiKeyStatus = apiKey
        return store
    }

    public static let previewTasks: [AgentTask] = [
        AgentTask(
            id: "t1",
            source: "manus",
            title: "Research competitive landscape for notch apps",
            status: .running,
            currentPhase: "Browsing GitHub trending",
            createdAt: Date(timeIntervalSinceNow: -180),
            updatedAt: Date(),
            taskURL: "https://manus.im/task/t1"
        ),
        AgentTask(
            id: "t2",
            source: "manus",
            title: "Draft launch tweet thread",
            status: .waiting,
            currentPhase: "Awaiting tone preference",
            createdAt: Date(timeIntervalSinceNow: -420),
            updatedAt: Date(timeIntervalSinceNow: -30),
            taskURL: "https://manus.im/task/t2",
            waitingMessage: "Should the thread be technical or playful?"
        ),
        AgentTask(
            id: "t3",
            source: "manus",
            title: "Summarize last week's PRs",
            status: .completed,
            currentPhase: nil,
            createdAt: Date(timeIntervalSinceNow: -3600),
            updatedAt: Date(timeIntervalSinceNow: -600),
            taskURL: "https://manus.im/task/t3"
        ),
    ]
}
#endif
