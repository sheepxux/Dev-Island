import Foundation
import Hummingbird

/// Localhost-only HTTP server that receives lifecycle events from local
/// agent CLIs (Claude Code today; Codex is expected to reuse this).
///
/// Deliberately separate from `WebhookServer`: that one is exposed to the
/// public internet through the cloudflared tunnel for Manus, while this one
/// must never leave 127.0.0.1. No signature verification is needed — the
/// bind address is the trust boundary.
///
/// Always returns 200 (even for undecodable bodies) so a hook misfire can
/// never surface as an error inside the user's Claude Code session.
public actor LocalHookServer {
    public let port: Int
    private var serverTask: Task<Void, Error>?

    public init(port: Int = ClaudeHooksInstaller.defaultPort) {
        self.port = port
    }

    public func start(onClaudeCodeEvent: @escaping @Sendable (ClaudeCodeEvent) -> Void) {
        serverTask = Task {
            let router = Router()

            router.post("/hooks/claude-code") { request, _ -> HTTPResponse.Status in
                var buffer = try await request.body.collect(upTo: 1_048_576)
                let data = Data(buffer.readableBytesView)

                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                guard let event = try? decoder.decode(ClaudeCodeEvent.self, from: data) else {
                    IslandLogger.webhook.debug("Ignoring undecodable Claude Code hook payload")
                    return .ok
                }

                IslandLogger.webhook.info(
                    "Claude Code event: \(event.hookEventName.rawValue) session=\(event.sessionId)")
                onClaudeCodeEvent(event)
                return .ok
            }

            let app = Application(
                router: router,
                configuration: .init(address: .hostname("127.0.0.1", port: self.port))
            )
            IslandLogger.webhook.info("LocalHookServer listening on 127.0.0.1:\(self.port)")
            try await app.run()
        }
    }

    public func stop() {
        serverTask?.cancel()
        serverTask = nil
        IslandLogger.webhook.info("LocalHookServer stopped")
    }
}
