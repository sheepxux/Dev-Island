import Foundation
import Observation
import AppKit

@MainActor
@Observable
public final class TaskStore {
    public static let shared = TaskStore()

    // MARK: - Public state (observed by C's SwiftUI views)

    public private(set) var tasks: [AgentTask] = []
    public private(set) var connectionStatus: ConnectionStatus = .disconnected
    public private(set) var apiKeyStatus: APIKeyStatus = .notConfigured

    // MARK: - Private internals

    private var connectors: [any AgentConnector] = []
    private var tunnelManager: TunnelManager?
    private var pollingFallback: PollingFallback?
    private var sqliteStore: SQLiteStore?
    private var pollingOnlyMode = false

    // Local agent pipeline (Claude Code, Codex, Cursor) — independent of the
    // Manus API key and of the tunnel/polling lifecycle: it runs for the
    // app's lifetime.
    private var localHookServer: LocalHookServer?
    private var claudeConnector: ClaudeCodeConnector?
    private var codexConnector: CodexConnector?
    private var cursorConnector: CursorConnector?

    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    // MARK: - Init

    private init() {
        Task { await bootstrap() }
    }

    // MARK: - Public API

    /// Validate key, persist to Keychain, then start all services.
    public func configureAPIKey(_ key: String) async throws {
        let client = ManusAPIClient(apiKey: key)
        // Validate by fetching tasks
        do {
            _ = try await client.listTasks()
        } catch ManusError.unauthorized {
            apiKeyStatus = .invalid
            throw ManusError.unauthorized
        }
        // Persist
        try KeychainStore.save(key)
        apiKeyStatus = .valid
        IslandLogger.store.info("API key configured and validated (key: \(key, privacy: .private))")
        try await startServices(apiKey: key)
    }

    public func clearAPIKey() {
        stopServices()
        try? KeychainStore.delete()
        // Only Manus tasks belong to the API key — local agent sessions
        // (Claude Code) are unaffected by a disconnect.
        tasks = tasks.filter { $0.source != "manus" }
        apiKeyStatus = .notConfigured
        connectionStatus = .disconnected
        IslandLogger.store.info("API key cleared")
    }

    public func openTaskInBrowser(id: String) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        guard let url = URL(string: task.taskURL) else { return }
        NSWorkspace.shared.open(url)
    }

    public func stopTask(id: String) async throws {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        // Only Manus tasks can be stopped remotely; local sessions
        // (Claude Code) are driven by their own CLI.
        guard task.source == "manus", let connector = connectors.first else { return }
        try await connector.stop(taskId: id)
        // Optimistically update status
        tasks = tasks.map { t in
            guard t.id == id else { return t }
            var updated = t
            updated.status = .completed
            updated.updatedAt = Date.now
            return updated
        }
    }

    // MARK: - Internal (called by TunnelManager / PollingFallback)

    internal func ingestWebhookEvent(_ event: WebhookPayload) {
        tasks = StateReconciler.apply(event: event, to: tasks)
        // Write to SQLite in background (best-effort)
        let store = sqliteStore
        Task.detached {
            guard let store else { return }
            switch event.data {
            case .progress(let d):
                try? await store.insertProgressEvent(taskId: d.taskId, type: d.progressType, message: d.message)
            default:
                break
            }
        }
        IslandLogger.store.debug("Ingested event \(event.event.rawValue) for \(event.taskId)")
    }

    internal func applyPollingSnapshot(_ incoming: [AgentTask]) {
        // Polling only covers Manus — scope the reconcile so local agent
        // sessions (claude-code) survive the snapshot merge.
        tasks = StateReconciler.reconcile(local: tasks, incoming: incoming, source: "manus")
        let store = sqliteStore
        let snapshot = tasks.filter { $0.source == "manus" }
        Task.detached {
            guard let store else { return }
            for task in snapshot {
                try? await store.insertOrReplace(task: task)
            }
        }
    }

    /// Replace all tasks of one local source with a fresh snapshot from its
    /// connector (event-sourced, so the connector state is authoritative).
    internal func applyLocalSnapshot(source: String, _ snapshot: [AgentTask]) {
        tasks = tasks.filter { $0.source != source } + snapshot
    }

    // MARK: - Bootstrap

    private func bootstrap() async {
        // Open SQLite
        let store = SQLiteStore()
        try? await store.open()
        sqliteStore = store

        // Local agent pipeline runs regardless of Manus configuration.
        startLocalHookPipeline()

        // Load API key from Keychain
        guard let apiKey = try? KeychainStore.load() else {
            apiKeyStatus = .notConfigured
            IslandLogger.store.info("No API key found in Keychain")
            return
        }

        // Validate key
        let client = ManusAPIClient(apiKey: apiKey)
        do {
            let initialTasks = try await client.listTasks()
            apiKeyStatus = .valid
            applyPollingSnapshot(initialTasks)
        } catch ManusError.unauthorized {
            apiKeyStatus = .invalid
            IslandLogger.store.warning("Stored API key is invalid")
            return
        } catch {
            IslandLogger.store.error("Bootstrap validation failed: \(error)")
            // Still try to start services — might be transient network error
        }

        do {
            try await startServices(apiKey: apiKey)
        } catch {
            IslandLogger.store.error("Failed to start services: \(error)")
            connectionStatus = .degraded(reason: error.localizedDescription)
        }

        registerSleepWakeObservers()
    }

    // MARK: - Local agent pipeline (Claude Code, Codex, Cursor)

    private func startLocalHookPipeline() {
        let claude = ClaudeCodeConnector()
        claudeConnector = claude
        let codex = CodexConnector()
        codexConnector = codex
        let cursor = CursorConnector()
        cursorConnector = cursor
        let server = LocalHookServer()
        localHookServer = server

        Task {
            await server.start(
                onClaudeCodeEvent: { [weak self] event in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let snapshot = await claude.apply(event)
                        self.applyLocalSnapshot(source: claude.source, snapshot)
                    }
                },
                onCodexEvent: { [weak self] event in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let snapshot = await codex.apply(event)
                        self.applyLocalSnapshot(source: codex.source, snapshot)
                    }
                },
                onCursorEvent: { [weak self] event in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let snapshot = await cursor.apply(event)
                        self.applyLocalSnapshot(source: cursor.source, snapshot)
                    }
                }
            )
        }
        IslandLogger.store.info("Local hook pipeline started (claude-code, codex, cursor)")
    }

    // MARK: - Service lifecycle

    private func startServices(apiKey: String) async throws {
        let client = ManusAPIClient(apiKey: apiKey)
        let connector = ManusConnector(client: client)
        connectors = [connector]

        // Start tunnel (with webhook push)
        let server = WebhookServer()
        let tunnel = TunnelManager(client: client, server: server)
        tunnelManager = tunnel

        do {
            try await tunnel.start { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.ingestWebhookEvent(event)
                }
            }
            pollingOnlyMode = false
            connectionStatus = .connected
            IslandLogger.store.info("Services started (tunnel + polling)")
        } catch TunnelError.tooManyRestarts {
            IslandLogger.store.warning("Tunnel unavailable — falling back to polling only")
            connectionStatus = .degraded(reason: "Tunnel unavailable")
            pollingOnlyMode = true
        } catch {
            IslandLogger.store.warning("Tunnel start failed (\(error)) — polling only")
            connectionStatus = .degraded(reason: error.localizedDescription)
            pollingOnlyMode = true
        }

        // Always start polling (as primary in degraded mode, as fallback otherwise)
        let poller = PollingFallback(connector: connector)
        pollingFallback = poller
        poller.start(
            onSnapshot: { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    self?.applyPollingSnapshot(snapshot)
                    // 网络恢复时 onNetworkRestored 会处理状态，这里只做快照合并
                }
            },
            onNetworkError: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.connectionStatus == .connected || self.connectionStatus == .degraded(reason: "Tunnel unavailable") {
                        self.connectionStatus = .reconnecting
                        IslandLogger.store.warning("Network lost — status: reconnecting")
                    }
                }
            },
            onNetworkRestored: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.connectionStatus = self.pollingOnlyMode
                        ? .degraded(reason: "Tunnel unavailable")
                        : .connected
                    IslandLogger.store.info("Network restored — status: \(String(describing: self.connectionStatus))")
                }
            }
        )
    }

    private func stopServices() {
        pollingFallback?.stop()
        pollingFallback = nil
        let tunnel = tunnelManager
        tunnelManager = nil
        connectors = []
        pollingOnlyMode = false
        Task.detached { await tunnel?.stop() }
    }

    // MARK: - Sleep / wake

    private func registerSleepWakeObservers() {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.connectionStatus = .disconnected
                // suspend() stops cloudflared + cleans webhook but keeps HTTP server alive
                let tunnel = self?.tunnelManager
                Task.detached { await tunnel?.suspend() }
                IslandLogger.store.info("System going to sleep")
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.connectionStatus = .reconnecting
                IslandLogger.store.info("System woke — reconnecting")
                // Restart tunnel
                await self.tunnelManager?.handleSleepWake()
                // Immediate poll to sync state
                if let connector = self.connectors.first {
                    do {
                        let snapshot = try await connector.fetchTasks()
                        self.applyPollingSnapshot(snapshot)
                        self.connectionStatus = .connected
                    } catch {
                        IslandLogger.store.error("Post-wake poll failed: \(error)")
                    }
                }
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
