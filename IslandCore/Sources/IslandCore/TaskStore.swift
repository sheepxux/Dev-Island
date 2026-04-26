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
        tasks = []
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
        guard let connector = connectors.first else { return }
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
        tasks = StateReconciler.reconcile(local: tasks, incoming: incoming)
        let store = sqliteStore
        let snapshot = tasks
        Task.detached {
            guard let store else { return }
            for task in snapshot {
                try? await store.insertOrReplace(task: task)
            }
        }
    }

    // MARK: - Bootstrap

    private func bootstrap() async {
        // Open SQLite
        let store = SQLiteStore()
        try? await store.open()
        sqliteStore = store

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
            tasks = initialTasks
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
