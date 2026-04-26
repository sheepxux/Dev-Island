import Foundation

enum TunnelError: Error {
    case tooManyRestarts
    case registrationFailed(underlying: Error)
}

actor TunnelManager {
    private let client: ManusAPIClient
    private let server: WebhookServer
    private var cloudflaredProcess: CloudflaredProcess?
    private var currentWebhookId: String?
    private var restartTimestamps: [Date] = []
    private var heartbeatTask: Task<Void, Never>?
    private var onEventReceived: (@Sendable (WebhookPayload) -> Void)?

    static let maxRestartsInWindow  = 3
    static let restartWindowSeconds = 300.0  // 5 minutes
    static let heartbeatInterval    = 300.0  // 5 minutes

    init(client: ManusAPIClient, server: WebhookServer) {
        self.client = client
        self.server = server
    }

    // MARK: - Public

    func start(onEvent: @escaping @Sendable (WebhookPayload) -> Void) async throws {
        self.onEventReceived = onEvent
        await server.start(onEvent: onEvent)
        try await launchAndRegister()
        startHeartbeat()
    }

    /// Full shutdown: stops cloudflared, deletes webhook, stops HTTP server.
    func stop() async {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        await cleanupWebhook()
        cloudflaredProcess?.stop()
        cloudflaredProcess = nil
        await server.stop()
        IslandLogger.tunnel.info("TunnelManager stopped")
    }

    /// Sleep-only suspend: stops cloudflared and cleans webhook,
    /// but keeps the local WebhookServer alive so it can accept connections on wake.
    func suspend() async {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        await cleanupWebhook()
        cloudflaredProcess?.stop()
        cloudflaredProcess = nil
        IslandLogger.tunnel.info("TunnelManager suspended (server kept alive)")
    }

    /// Called on system wake. Restarts cloudflared and re-registers webhook.
    /// Assumes the WebhookServer is still running from before sleep.
    func handleSleepWake() async {
        IslandLogger.tunnel.info("Wake detected — restarting tunnel")
        // Small delay for network to come up after wake
        try? await Task.sleep(for: .seconds(3))
        try? await launchAndRegister()
        startHeartbeat()
    }

    // MARK: - Private

    private func launchAndRegister() async throws {
        guard shouldAllowRestart() else {
            IslandLogger.tunnel.error("Too many tunnel restarts in the last 5 minutes")
            throw TunnelError.tooManyRestarts
        }

        restartTimestamps.append(Date.now)

        let proc = CloudflaredProcess()
        IslandLogger.tunnel.info("Starting cloudflared tunnel...")
        let publicURL: URL
        do {
            publicURL = try await proc.start()
        } catch {
            IslandLogger.tunnel.error("cloudflared failed to start: \(error)")
            throw error
        }
        cloudflaredProcess = proc
        IslandLogger.tunnel.info("Tunnel URL: \(publicURL.absoluteString)")

        let webhookURL = publicURL.appendingPathComponent("/webhook").absoluteString
        do {
            let webhookId = try await client.registerWebhook(publicURL: webhookURL)
            currentWebhookId = webhookId
            UserDefaults(suiteName: "com.island.app")?.set(webhookId, forKey: "webhookId")
            IslandLogger.tunnel.info("Webhook registered: \(webhookId)")
        } catch {
            IslandLogger.tunnel.error("Webhook registration failed: \(error)")
            throw TunnelError.registrationFailed(underlying: error)
        }
    }

    private func cleanupWebhook() async {
        // Clean up stored webhook from a previous session that may have crashed
        let defaults = UserDefaults(suiteName: "com.island.app")
        let storedId = currentWebhookId ?? defaults?.string(forKey: "webhookId")
        guard let id = storedId else { return }
        do {
            try await client.deleteWebhook(id: id)
            IslandLogger.tunnel.info("Webhook deleted: \(id)")
        } catch {
            IslandLogger.tunnel.warning("Failed to delete webhook \(id): \(error)")
        }
        currentWebhookId = nil
        defaults?.removeObject(forKey: "webhookId")
    }

    private func shouldAllowRestart() -> Bool {
        let windowStart = Date.now.addingTimeInterval(-Self.restartWindowSeconds)
        restartTimestamps = restartTimestamps.filter { $0 > windowStart }
        return restartTimestamps.count < Self.maxRestartsInWindow
    }

    private func startHeartbeat() {
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(TunnelManager.heartbeatInterval))
                guard let self, !Task.isCancelled else { return }
                await self.checkProcessHealth()
            }
        }
    }

    private func checkProcessHealth() async {
        guard let proc = cloudflaredProcess, !proc.isRunning else { return }
        IslandLogger.tunnel.warning("cloudflared process died — attempting restart")
        cloudflaredProcess = nil
        // Delete stale webhook before re-registering
        await cleanupWebhook()
        do {
            // WebhookServer is still running; only cloudflared + webhook need restart
            try await launchAndRegister()
        } catch TunnelError.tooManyRestarts {
            IslandLogger.tunnel.error("Giving up on tunnel — switching to polling-only mode")
        } catch {
            IslandLogger.tunnel.error("Restart failed: \(error)")
        }
    }
}
