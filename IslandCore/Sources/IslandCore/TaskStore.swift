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

    /// Task status-transition callback (contract v1.4.0, J1). B side assigns
    /// once at app startup and maps transitions to notifications.
    /// Fires on the main actor after `tasks` is already updated; one call per
    /// changed task; newly appeared tasks fire with `oldStatus == nil`;
    /// removals don't fire. Debug mutators fire too (Debug Sandbox testing).
    public var onTaskTransition: ((TaskTransition) -> Void)?

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
    private var localConnectors: [String: LocalAgentConnector] = [:]

    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    // MARK: - Init

    /// `bootstrap: false` builds an inert store (previews / unit tests) that
    /// never touches SQLite, Keychain, or the local hook server.
    private init(bootstrap: Bool = true) {
        if bootstrap {
            Task { await self.bootstrap() }
        }
    }

    // MARK: - Task mutation funnel

    /// Every `tasks` write goes through here so status transitions are
    /// detected exactly once, in one place (contract v1.4.0).
    private func setTasks(_ newTasks: [AgentTask]) {
        let transitions = TaskTransition.diff(old: tasks, new: newTasks)
        tasks = newTasks
        guard let onTaskTransition else { return }
        for transition in transitions {
            onTaskTransition(transition)
        }
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
        setTasks(tasks.filter { $0.source != "manus" })
        apiKeyStatus = .notConfigured
        connectionStatus = .disconnected
        IslandLogger.store.info("API key cleared")
    }

    public func openTaskInBrowser(id: String) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        guard let url = URL(string: task.taskURL) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Jump back to the session behind a task (contract v1.4.0, J2).
    /// App-level activation of the source app (cursor → Cursor.app,
    /// codex → Codex Desktop or a running terminal, claude-code → a running
    /// terminal); falls back to `openTaskInBrowser` behavior when no
    /// suitable app is running (local tasks → Finder, Manus → browser).
    public func jumpToTask(id: String) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        if SourceAppResolver.activateApp(for: task.source) {
            IslandLogger.store.debug("jumpToTask(\(id)): activated \(task.source) host app")
            return
        }
        openTaskInBrowser(id: id)
    }

    public func stopTask(id: String) async throws {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        // Only Manus tasks can be stopped remotely; local sessions
        // (Claude Code) are driven by their own CLI.
        guard task.source == "manus", let connector = connectors.first else { return }
        try await connector.stop(taskId: id)
        // Optimistically update status
        setTasks(tasks.map { t in
            guard t.id == id else { return t }
            var updated = t
            updated.status = .completed
            updated.updatedAt = Date.now
            return updated
        })
    }

    // MARK: - Internal (called by TunnelManager / PollingFallback)

    internal func ingestWebhookEvent(_ event: WebhookPayload) {
        setTasks(StateReconciler.apply(event: event, to: tasks))
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
        setTasks(StateReconciler.reconcile(local: tasks, incoming: incoming, source: "manus"))
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
        setTasks(tasks.filter { $0.source != source } + snapshot)
    }

    // MARK: - Bootstrap

    private func bootstrap() async {
        // Open SQLite
        let store = SQLiteStore()
        try? await store.open()
        sqliteStore = store

        // Local agent pipeline runs regardless of Manus configuration.
        startLocalHookPipeline()

        // Sleep/wake observers guard the local pipeline too, so they must
        // register even when no Manus key is configured (previously they
        // were only registered at the end of the happy path).
        registerSleepWakeObservers()

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
    }

    // MARK: - Local agent pipeline (registry-driven)

    private func startLocalHookPipeline() {
        // One generic connector per registered agent — the registry is the
        // single source of truth for which agents exist.
        let connectors = Dictionary(uniqueKeysWithValues: LocalAgentRegistry.all.map {
            ($0.source, LocalAgentConnector(descriptor: $0))
        })
        localConnectors = connectors
        let server = LocalHookServer()
        localHookServer = server

        Task {
            await server.start(agents: LocalAgentRegistry.all) { [weak self] source, event in
                Task { @MainActor [weak self] in
                    // Look up through the stored map (not a closure capture)
                    // so the store's property is the single owner and a
                    // future pipeline restart can swap connectors safely.
                    guard let self, let connector = self.localConnectors[source] else { return }
                    let snapshot = await connector.apply(event)
                    self.applyLocalSnapshot(source: source, snapshot)
                }
            }
        }
        let sources = LocalAgentRegistry.all.map(\.source).joined(separator: ", ")
        IslandLogger.store.info("Local hook pipeline started (\(sources))")
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
                IslandLogger.store.info("System woke — health-checking services")
                // Local pipeline first: relaunch the hook server if its
                // serve loop died while we slept (e.g. transient bind error).
                await self.localHookServer?.ensureRunning()
                // Manus side only applies when services are configured.
                guard self.tunnelManager != nil || !self.connectors.isEmpty else { return }
                self.connectionStatus = .reconnecting
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
        // bootstrap: false — previews and unit tests must never bind the
        // hook server port or touch SQLite/Keychain.
        let store = TaskStore(bootstrap: false)
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
    /// Routed through the transition funnel so `onTaskTransition` fires —
    /// the Debug Sandbox is how B tests notifications (contract v1.4.0).
    public func debugSetTasks(_ tasks: [AgentTask]) {
        setTasks(tasks)
    }

    /// Append a single task. Used by the "+ Running / + Waiting / …" row.
    public func debugAppend(_ task: AgentTask) {
        setTasks(tasks + [task])
    }

    /// Drop every task — also exercises the empty-state rendering path.
    public func debugClearTasks() {
        setTasks([])
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
