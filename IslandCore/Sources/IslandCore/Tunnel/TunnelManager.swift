import Foundation

enum TunnelError: Error {
    case tooManyRestarts
    case serverUnavailable
    case trustConfigurationFailed(underlying: Error)
    case registrationFailed(underlying: Error)
    case lifecycleSuperseded
}

/// Narrow internal seams keep the public Manus, HTTP-server, and process
/// implementations intact while making the realtime lifecycle deterministic
/// under test. All conformers are actors in production.
protocol ManusWebhookClientProtocol: Sendable {
    func webhookPublicKey() async throws -> String
    func registerWebhook(publicURL: String) async throws -> String
    func deleteWebhook(id: String) async throws
}

protocol WebhookServerProtocol: Sendable {
    func configure(externalURL: String, signaturePublicKeyPEM: String) async throws
    func start(onEvent: @escaping @Sendable (WebhookPayload) -> Void) async throws
    func isReady() async -> Bool
    func stop() async
}

protocol TunnelProcessProtocol: Sendable {
    var isRunning: Bool { get async }
    func start() async throws -> URL
    func stop() async
}

/// The narrow lifecycle surface TaskStore needs across system sleep/wake.
/// Keeping it protocol-backed makes notification ordering and late-result
/// behavior testable without opening a local server or public tunnel.
protocol ManusTunnelLifecycleProtocol: Sendable {
    func start(
        onEvent: @escaping @Sendable (WebhookPayload) -> Void,
        onRealtimeUnavailable: @escaping @Sendable () async -> Void
    ) async throws
    func stop() async
    func suspend() async
    func handleSleepWake() async throws
}

extension WebhookServer: WebhookServerProtocol {}
extension CloudflaredProcess: TunnelProcessProtocol {}

enum TunnelRuntimeStatus: Equatable, Sendable {
    case stopped
    case serverOnly
    case registered
}

actor TunnelManager {
    private struct RegisteredTransport: Sendable {
        let token: UUID
        let process: any TunnelProcessProtocol
        let webhookID: String
    }

    private let client: any ManusWebhookClientProtocol
    private let server: any WebhookServerProtocol
    private let processFactory: @Sendable () -> any TunnelProcessProtocol
    private let preferences: UserDefaults?
    private let wakeDelay: Duration
    private let heartbeatDelay: Duration

    /// A process is never promoted to `activeTransport` until Manus has
    /// returned a webhook ID. This makes "process alive but no webhook"
    /// unrepresentable as a connected realtime state.
    private var activeTransport: RegisteredTransport?
    private var restartTimestamps: [Date] = []
    private var heartbeatTask: Task<Void, Never>?
    private var onEventReceived: (@Sendable (WebhookPayload) -> Void)?
    private var onRealtimeUnavailable: (@Sendable () async -> Void)?
    private var isServerStarted = false
    private var lifecycleGeneration: UInt64 = 0

    static let maxRestartsInWindow = 3
    static let restartWindowSeconds = 300.0  // 5 minutes
    static let heartbeatInterval = 300.0     // 5 minutes
    static let wakeNetworkDelay = 3.0

    init(
        client: any ManusWebhookClientProtocol,
        server: any WebhookServerProtocol,
        processFactory: @escaping @Sendable () -> any TunnelProcessProtocol = {
            CloudflaredProcess()
        },
        preferences: UserDefaults? = UserDefaults(suiteName: "app.devisland.Island"),
        wakeDelay: Duration = .seconds(TunnelManager.wakeNetworkDelay),
        heartbeatDelay: Duration = .seconds(TunnelManager.heartbeatInterval)
    ) {
        self.client = client
        self.server = server
        self.processFactory = processFactory
        self.preferences = preferences
        self.wakeDelay = wakeDelay
        self.heartbeatDelay = heartbeatDelay
    }

    // MARK: - Public

    func start(
        onEvent: @escaping @Sendable (WebhookPayload) -> Void,
        onRealtimeUnavailable: @escaping @Sendable () async -> Void = {}
    ) async throws {
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        self.onEventReceived = onEvent
        self.onRealtimeUnavailable = onRealtimeUnavailable
        isServerStarted = true

        do {
            try await server.start(onEvent: onEvent)
            try requireCurrentLifecycle(generation)
            // A crash may have left an ID in preferences. Delete it before
            // registering another endpoint so reconnects do not accumulate.
            await cleanupStoredWebhook()
            try requireCurrentLifecycle(generation)
            try await launchAndRegister(generation: generation)
            startHeartbeat()
        } catch {
            // `start` is transactional: a thrown start never leaves a local
            // server or public transport running behind the caller's back.
            if generation == lifecycleGeneration {
                await stopServerOnly()
            }
            throw error
        }
    }

    /// Full shutdown: stops cloudflared, deletes webhook, stops HTTP server.
    func stop() async {
        lifecycleGeneration &+= 1
        cancelHeartbeat()
        await cleanupActiveTransport()
        await cleanupStoredWebhook()
        await stopServerOnly()
        onEventReceived = nil
        onRealtimeUnavailable = nil
        IslandLogger.tunnel.info("TunnelManager stopped")
    }

    /// Sleep-only suspend: stops cloudflared and cleans webhook,
    /// but keeps the local WebhookServer alive so it can accept connections on wake.
    func suspend() async {
        lifecycleGeneration &+= 1
        cancelHeartbeat()
        await cleanupActiveTransport()
        await cleanupStoredWebhook()
        IslandLogger.tunnel.info("TunnelManager suspended (server kept alive)")
    }

    /// Called on system wake. Restarts cloudflared and re-registers webhook.
    /// The caller must handle failure by entering polling-only mode; a wake
    /// failure is never swallowed or represented as a healthy connection.
    func handleSleepWake() async throws {
        IslandLogger.tunnel.info("Wake detected — restarting tunnel")
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        cancelHeartbeat()
        try await Task.sleep(for: wakeDelay)
        do {
            try requireCurrentLifecycle(generation)
            try await launchAndRegister(generation: generation)
            startHeartbeat()
        } catch {
            await cleanupActiveTransport()
            throw error
        }
    }

    func statusSnapshot() -> TunnelRuntimeStatus {
        if activeTransport != nil { return .registered }
        if isServerStarted { return .serverOnly }
        return .stopped
    }

    // MARK: - Lifecycle internals

    private func launchAndRegister(generation: UInt64) async throws {
        try requireCurrentLifecycle(generation)
        guard await server.isReady() else {
            IslandLogger.tunnel.error("WebhookServer readiness proof failed")
            throw TunnelError.serverUnavailable
        }
        guard shouldAllowRestart() else {
            IslandLogger.tunnel.error("Too many tunnel restarts in the last 5 minutes")
            throw TunnelError.tooManyRestarts
        }

        restartTimestamps.append(Date.now)

        let process = processFactory()
        IslandLogger.tunnel.info("Starting cloudflared tunnel")
        let publicURL: URL
        do {
            publicURL = try await process.start()
        } catch {
            // `start()` may fail after the child process was launched (for
            // example while waiting for its URL). Always close that process.
            await process.stop()
            IslandLogger.tunnel.error("cloudflared failed to start")
            throw error
        }
        do {
            try requireCurrentLifecycle(generation)
        } catch {
            await process.stop()
            throw error
        }
        IslandLogger.tunnel.info("Cloudflare tunnel URL acquired")

        let webhookURL = publicURL.appendingPathComponent("/webhook").absoluteString
        let publicKey: String
        do {
            publicKey = try await client.webhookPublicKey()
        } catch {
            await process.stop()
            IslandLogger.tunnel.error("Manus webhook trust refresh failed")
            throw TunnelError.trustConfigurationFailed(underlying: error)
        }
        do {
            try requireCurrentLifecycle(generation)
        } catch {
            await process.stop()
            throw error
        }
        do {
            try await server.configure(
                externalURL: webhookURL,
                signaturePublicKeyPEM: publicKey
            )
        } catch {
            await process.stop()
            IslandLogger.tunnel.error("Webhook verifier configuration failed")
            throw TunnelError.trustConfigurationFailed(underlying: error)
        }
        do {
            try requireCurrentLifecycle(generation)
        } catch {
            await process.stop()
            throw error
        }
        guard await server.isReady() else {
            await process.stop()
            IslandLogger.tunnel.error("WebhookServer became unavailable before registration")
            throw TunnelError.serverUnavailable
        }

        let webhookID: String
        do {
            webhookID = try await client.registerWebhook(publicURL: webhookURL)
        } catch {
            // The quick tunnel has no realtime value without a registered
            // webhook. Stop it immediately instead of letting heartbeat treat
            // a live process as a live Manus connection.
            await process.stop()
            IslandLogger.tunnel.error("Manus webhook registration failed")
            throw TunnelError.registrationFailed(underlying: error)
        }

        do {
            try requireCurrentLifecycle(generation)
        } catch {
            // Stop/suspend can interleave while registration is in flight.
            // If Manus accepted that now-obsolete request, delete it before
            // returning so no orphan public endpoint survives the race.
            await deleteWebhook(webhookID)
            await process.stop()
            throw error
        }
        guard await server.isReady() else {
            await deleteWebhook(webhookID)
            await process.stop()
            IslandLogger.tunnel.error("WebhookServer became unavailable after registration")
            throw TunnelError.serverUnavailable
        }

        activeTransport = RegisteredTransport(
            token: UUID(),
            process: process,
            webhookID: webhookID
        )
        preferences?.set(webhookID, forKey: "webhookId")
        IslandLogger.tunnel.info("Manus webhook registered")
    }

    private func cleanupActiveTransport() async {
        guard let transport = activeTransport else { return }
        activeTransport = nil
        preferences?.removeObject(forKey: "webhookId")
        await deleteWebhook(transport.webhookID)
        await transport.process.stop()
    }

    private func cleanupStoredWebhook() async {
        guard activeTransport == nil,
              let storedID = preferences?.string(forKey: "webhookId") else { return }
        preferences?.removeObject(forKey: "webhookId")
        await deleteWebhook(storedID)
    }

    private func deleteWebhook(_ id: String) async {
        do {
            try await client.deleteWebhook(id: id)
            IslandLogger.tunnel.info("Manus webhook deleted")
        } catch {
            IslandLogger.tunnel.warning("Failed to delete Manus webhook")
        }
    }

    private func stopServerOnly() async {
        guard isServerStarted else { return }
        await server.stop()
        isServerStarted = false
    }

    private func shouldAllowRestart() -> Bool {
        let windowStart = Date.now.addingTimeInterval(-Self.restartWindowSeconds)
        restartTimestamps = restartTimestamps.filter { $0 > windowStart }
        return restartTimestamps.count < Self.maxRestartsInWindow
    }

    private func requireCurrentLifecycle(_ generation: UInt64) throws {
        guard generation == lifecycleGeneration else {
            throw TunnelError.lifecycleSuperseded
        }
    }

    private func cancelHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    private func startHeartbeat() {
        cancelHeartbeat()
        guard activeTransport != nil else { return }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = self.heartbeatDelay
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                await self.checkProcessHealth()
            }
        }
    }

    /// Internal for deterministic lifecycle regression tests. Production only
    /// reaches this method through the bounded heartbeat above.
    func checkProcessHealth() async {
        guard let transport = activeTransport else {
            await transitionToRealtimeUnavailable()
            return
        }

        let serverReady = await server.isReady()
        guard activeTransport?.token == transport.token else { return }
        guard serverReady else {
            IslandLogger.tunnel.warning("WebhookServer readiness lost — switching to polling-only mode")
            await transitionToRealtimeUnavailable()
            return
        }

        let isRunning = await transport.process.isRunning
        guard activeTransport?.token == transport.token else { return }
        guard !isRunning else { return }

        IslandLogger.tunnel.warning("cloudflared process died — attempting restart")
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        activeTransport = nil
        preferences?.removeObject(forKey: "webhookId")
        await deleteWebhook(transport.webhookID)
        await transport.process.stop()

        do {
            // WebhookServer is still running; only cloudflared + webhook need restart.
            try await launchAndRegister(generation: generation)
        } catch TunnelError.tooManyRestarts {
            IslandLogger.tunnel.error("Giving up on tunnel — switching to polling-only mode")
            await transitionToRealtimeUnavailable()
        } catch {
            IslandLogger.tunnel.error("Tunnel restart failed — switching to polling-only mode")
            await transitionToRealtimeUnavailable()
        }
    }

    private func transitionToRealtimeUnavailable() async {
        cancelHeartbeat()
        await cleanupActiveTransport()
        guard let callback = onRealtimeUnavailable else { return }
        // Deliver once. TaskStore owns the user-visible degradation and then
        // stops this server; repeated heartbeat signals must not race it.
        onRealtimeUnavailable = nil
        await callback()
    }
}

extension TunnelManager: ManusTunnelLifecycleProtocol {}
