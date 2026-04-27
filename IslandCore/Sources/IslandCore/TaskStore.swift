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

    // MARK: - Debug Sandbox mutators (CLAUDE_CLIENT.md §6 task 10)
    //
    // The Debug Sandbox window drives `TaskStore.shared` directly so we can
    // exercise every UI path without Manus. These live in this file because
    // `tasks` / `connectionStatus` are `private(set)` — only same-file
    // extensions can mutate them, which is also exactly what we want: the
    // production setter contract stays untouched, the debug write surface
    // is physically scoped to one #if DEBUG block in one file.
    //
    // Naming: prefixed `debug…` so call sites read like sandbox plumbing,
    // not real domain logic. Production code MUST NOT call these.

    /// Replace the entire task list. Triggers an Observation update so
    /// every view bound to `tasks` re-renders (bar count, panel list).
    public func debugSetTasks(_ tasks: [AgentTask]) {
        self.tasks = tasks
    }

    /// Append a single task. Used by the "+ Running / + Waiting / …" row.
    public func debugAppend(_ task: AgentTask) {
        self.tasks.append(task)
    }

    /// Drop every task — also exercises the empty-state rendering path.
    public func debugClearTasks() {
        self.tasks.removeAll()
    }

    /// Override the connection-status indicator (header dot + any future
    /// degraded-bar visuals).
    public func debugSetConnectionStatus(_ status: ConnectionStatus) {
        self.connectionStatus = status
    }

    /// Spawn a synthetic task in the given status with sensible defaults
    /// for the fields the sandbox doesn't care about. Returns the task so
    /// callers can mutate it further if they ever want to.
    @discardableResult
    public func debugSpawn(status: TaskStatus, title: String? = nil) -> AgentTask {
        let now = Date()
        let task = AgentTask(
            id: "dbg-\(UUID().uuidString.prefix(6))",
            source: "debug",
            title: title ?? Self.debugDefaultTitle(for: status),
            status: status,
            currentPhase: Self.debugDefaultPhase(for: status),
            createdAt: now,
            updatedAt: now,
            taskURL: "https://example.invalid/debug",
            waitingMessage: status == .waiting
                ? "Sandbox-injected waiting prompt"
                : nil
        )
        debugAppend(task)
        return task
    }

    private static func debugDefaultTitle(for status: TaskStatus) -> String {
        switch status {
        case .running:   return "Sandbox running task"
        case .waiting:   return "Sandbox waiting task"
        case .completed: return "Sandbox completed task"
        case .failed:    return "Sandbox failed task"
        }
    }

    private static func debugDefaultPhase(for status: TaskStatus) -> String? {
        switch status {
        case .running:   return "Doing fake work"
        case .waiting:   return "Awaiting fake input"
        case .completed: return nil
        case .failed:    return nil
        }
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
