import Foundation
import Hummingbird

actor WebhookServer {
    let port: Int
    private var serverTask: Task<Void, Error>?
    // Public key PEM for signature verification — set before starting.
    // If nil, signature verification is skipped (dev mode).
    var webhookPublicKeyPEM: String?

    init(port: Int = 7823) {
        self.port = port
    }

    func start(onEvent: @escaping @Sendable (WebhookPayload) -> Void) {
        serverTask = Task {
            let router = Router()
            let pem = webhookPublicKeyPEM  // capture for closure

            router.post("/webhook") { request, _ -> HTTPResponse.Status in
                var buffer = try await request.body.collect(upTo: 1_048_576)
                let data = Data(buffer.readableBytesView)

                // Signature verification (skipped if no PEM configured)
                if let pem {
                    let fieldName = HTTPField.Name(WebhookSignature.headerName)
                    let signature = fieldName.flatMap { request.headers[$0] }
                    guard let signature else {
                        IslandLogger.webhook.warning("Missing signature header, rejecting")
                        return .unauthorized
                    }
                    guard (try? WebhookSignature.verify(body: data, signature: signature, publicKeyPEM: pem)) == true else {
                        IslandLogger.webhook.warning("Signature verification failed")
                        return .unauthorized
                    }
                }

                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                guard let payload = try? decoder.decode(WebhookPayload.self, from: data) else {
                    IslandLogger.webhook.error("Failed to decode webhook payload")
                    return .badRequest
                }

                IslandLogger.webhook.info("Received event: \(payload.event.rawValue) taskId=\(payload.taskId)")
                onEvent(payload)
                return .ok
            }

            let app = Application(
                router: router,
                configuration: .init(address: .hostname("127.0.0.1", port: self.port))
            )
            IslandLogger.webhook.info("WebhookServer listening on port \(self.port)")
            try await app.run()
        }
    }

    func stop() {
        serverTask?.cancel()
        serverTask = nil
        IslandLogger.webhook.info("WebhookServer stopped")
    }
}
