import Foundation
import IslandCore

// MARK: - CLI Integration Test Tool
// Usage: MANUS_API_KEY_DEV=mk_live_xxx swift run IslandCoreCLI
//
// Exercises the full pipeline:
//   1. Start WebhookServer (port 7823)
//   2. Launch cloudflared tunnel → get public URL
//   3. Register webhook with Manus
//   4. Wait 60s for events (create a task in Manus web UI)
//   5. Print all received events
//   6. Cleanup (delete webhook, stop tunnel)

guard let apiKey = ProcessInfo.processInfo.environment["MANUS_API_KEY_DEV"] else {
    print("[CLI] ✗ MANUS_API_KEY_DEV environment variable not set")
    print("[CLI]   export MANUS_API_KEY_DEV=mk_live_xxxxxxxxxxxx")
    exit(1)
}

print("[CLI] Island Core CLI — integration test")
print("[CLI] API key: \(String(apiKey.prefix(12)))...")

Task {
    do {
        // Step 1: API client
        let client = ManusAPIClient(apiKey: apiKey)
        print("[CLI] Validating API key...")
        let initialTasks = try await client.listTasks()
        print("[CLI] ✓ API key valid — \(initialTasks.count) existing tasks")

        // Step 2: Webhook server
        print("[CLI] Starting webhook server on port 7823...")
        let server = WebhookServer(port: 7823)
        var receivedEvents: [String] = []

        await server.start { event in
            let msg = "Event: \(event.event.rawValue) taskId=\(event.taskId)"
            print("[CLI] ← \(msg)")
            receivedEvents.append(msg)
        }
        print("[CLI] ✓ Webhook server running")

        // Step 3: Cloudflared tunnel
        print("[CLI] Launching cloudflared tunnel (30s timeout)...")
        let cloudflared = CloudflaredProcess()
        let publicURL = try await cloudflared.start()
        print("[CLI] ✓ Tunnel URL: \(publicURL.absoluteString)")

        // Step 4: Register webhook
        let webhookURL = publicURL.appendingPathComponent("/webhook").absoluteString
        print("[CLI] Registering webhook: \(webhookURL)")
        let webhookId = try await client.registerWebhook(publicURL: webhookURL)
        print("[CLI] ✓ Webhook registered: \(webhookId)")

        // Step 5: Wait for events
        print("[CLI] Waiting 60 seconds — create a task at https://manus.im to generate events...")
        print("[CLI] (Ctrl+C to stop early)")
        try await Task.sleep(for: .seconds(60))

        // Step 6: Cleanup
        print("[CLI] Cleaning up...")
        try await client.deleteWebhook(id: webhookId)
        cloudflared.stop()
        await server.stop()

        print("[CLI] ✓ Done — received \(receivedEvents.count) event(s)")
        for event in receivedEvents {
            print("[CLI]   \(event)")
        }
        exit(0)
    } catch {
        print("[CLI] ✗ Error: \(error)")
        exit(1)
    }
}

// Keep the process alive for async tasks
RunLoop.main.run()
