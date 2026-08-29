import Foundation
import Hummingbird
import HTTPTypes  // [C→S] HTTPField type lives here on macOS Swift 6.3+

struct WebhookRequestAuthenticator: Sendable {
    private let signaturePublicKeyPEM: String

    init?(signaturePublicKeyPEM: String) {
        let normalized = signaturePublicKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              WebhookSignature.canImportPublicKey(normalized) else { return nil }
        self.signaturePublicKeyPEM = normalized
    }

    func isAuthentic(
        body: Data,
        signature: String?,
        timestamp: String?,
        externalURL: String?,
        now: Date = .now
    ) -> Bool {
        authenticate(
            body: body,
            signature: signature,
            timestamp: timestamp,
            externalURL: externalURL,
            now: now
        ) != nil
    }

    func authenticate(
        body: Data,
        signature: String?,
        timestamp: String?,
        externalURL: String?,
        now: Date = .now
    ) -> AuthenticatedWebhookRequest? {
        guard let signature, !signature.isEmpty,
              let timestamp, !timestamp.isEmpty,
              let timestampSeconds = TimeInterval(timestamp),
              timestampSeconds.isFinite,
              now.timeIntervalSince1970.isFinite,
              let externalURL, !externalURL.isEmpty else { return nil }
        guard (try? WebhookSignature.verify(
            body: body,
            signature: signature,
            timestamp: timestamp,
            externalURL: externalURL,
            publicKeyPEM: signaturePublicKeyPEM,
            now: now
        )) == true else { return nil }
        return AuthenticatedWebhookRequest(
            signedAt: Date(timeIntervalSince1970: timestampSeconds),
            acceptedAt: now
        )
    }
}

struct AuthenticatedWebhookRequest: Equatable, Sendable {
    let signedAt: Date
    let acceptedAt: Date
}

/// Bounded in-memory replay protection for one registered callback URL.
/// Entries expire only after their authenticated signature timestamp is no
/// longer acceptable. When the live window reaches capacity, new events fail
/// closed instead of evicting an ID that could still be replayed.
struct WebhookReplayWindow: Sendable {
    enum Decision: Equatable, Sendable {
        case deliver
        case duplicate
        case saturated
    }

    let capacity: Int
    private(set) var expirationByEventID: [String: TimeInterval] = [:]

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    mutating func register(
        eventID: String,
        authentication: AuthenticatedWebhookRequest
    ) -> Decision {
        let acceptedAt = authentication.acceptedAt.timeIntervalSince1970
        expirationByEventID = expirationByEventID.filter {
            // A signature exactly on the five-minute boundary is still valid.
            $0.value >= acceptedAt
        }

        let expiration = authentication.signedAt.timeIntervalSince1970
            + WebhookSignature.maximumClockSkew
        if let retainedExpiration = expirationByEventID[eventID] {
            // A provider retry can carry a newer authenticated timestamp.
            // Extend retention so that later captured retry cannot become
            // replayable when only the first signature expires.
            expirationByEventID[eventID] = max(retainedExpiration, expiration)
            return .duplicate
        }
        guard expirationByEventID.count < capacity else { return .saturated }
        expirationByEventID[eventID] = expiration
        return .deliver
    }
}

enum WebhookServerConfigurationError: Error {
    case invalidTrustMaterial
    case invalidExternalURL
}

enum WebhookServerStartError: Error, Equatable {
    case readinessFailed
}

public actor WebhookServer {  // [C→S] public so the CLI target can use it
    let port: Int
    private var serverTask: Task<Void, Never>?
    private var readinessToken: String?
    private var authenticator: WebhookRequestAuthenticator
    private var externalURL: String?
    private static let replayCacheLimit = 1_024
    private var replayWindow: WebhookReplayWindow

    /// A server cannot exist without an explicit non-empty trust anchor.
    /// This keeps every call site fail-closed, including development tools.
    public init?(port: Int = 7823, signaturePublicKeyPEM: String) {
        guard let authenticator = WebhookRequestAuthenticator(
            signaturePublicKeyPEM: signaturePublicKeyPEM
        ) else { return nil }
        self.port = port
        self.authenticator = authenticator
        self.replayWindow = WebhookReplayWindow(capacity: Self.replayCacheLimit)
    }

    /// Module-internal transport-test seam. Production call sites must use the
    /// public initializer and its fixed 1,024-entry fail-closed window.
    init?(
        port: Int,
        signaturePublicKeyPEM: String,
        replayCapacity: Int
    ) {
        guard replayCapacity > 0,
              let authenticator = WebhookRequestAuthenticator(
                  signaturePublicKeyPEM: signaturePublicKeyPEM
              ) else { return nil }
        self.port = port
        self.authenticator = authenticator
        self.replayWindow = WebhookReplayWindow(capacity: replayCapacity)
    }

    /// Update the exact public callback URL and the currently authenticated
    /// Manus verification key before registration. A running local server
    /// remains fail-closed until this succeeds.
    public func configure(externalURL: String, signaturePublicKeyPEM: String) throws {
        guard let url = URL(string: externalURL),
              url.scheme?.lowercased() == "https",
              url.host != nil,
              url.absoluteString == externalURL else {
            throw WebhookServerConfigurationError.invalidExternalURL
        }
        guard let authenticator = WebhookRequestAuthenticator(
            signaturePublicKeyPEM: signaturePublicKeyPEM
        ) else {
            throw WebhookServerConfigurationError.invalidTrustMaterial
        }
        self.authenticator = authenticator
        self.externalURL = externalURL
    }

    public func start(
        onEvent: @escaping @Sendable (WebhookPayload) -> Void
    ) async throws {
        try Task.checkCancellation()
        if serverTask != nil {
            guard await isReady() else {
                throw WebhookServerStartError.readinessFailed
            }
            return
        }

        let readinessToken = UUID().uuidString.lowercased()
        self.readinessToken = readinessToken
        serverTask = Task {
            let router = Router()

            router.get(RouterPath("/_dev-island/webhook-ready/\(readinessToken)")) {
                _, _ -> String in
                readinessToken
            }

            router.post("/webhook") { request, _ -> HTTPResponse.Status in
                let buffer = try await request.body.collect(upTo: 1_048_576)
                let data = Data(buffer.readableBytesView)

                let signatureField = HTTPField.Name(WebhookSignature.headerName)
                let timestampField = HTTPField.Name(WebhookSignature.timestampHeaderName)
                let signature = signatureField.flatMap { request.headers[$0] }
                let timestamp = timestampField.flatMap { request.headers[$0] }
                guard let authentication = await self.authenticate(
                    body: data,
                    signature: signature,
                    timestamp: timestamp
                ) else {
                    IslandLogger.webhook.warning("Missing or invalid webhook signature, rejecting")
                    return .unauthorized
                }

                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                guard let payload = try? decoder.decode(WebhookPayload.self, from: data) else {
                    IslandLogger.webhook.error("Failed to decode webhook payload")
                    return .badRequest
                }

                // Timestamp validation narrows replay to five minutes. Keep
                // every accepted ID until its exact signature window expires;
                // saturation fails closed instead of making a live ID
                // replayable through FIFO eviction.
                switch await self.markEventForDelivery(
                    payload.eventID,
                    authentication: authentication
                ) {
                case .duplicate:
                    return .ok
                case .saturated:
                    IslandLogger.webhook.warning("Webhook replay window is saturated")
                    return .serviceUnavailable
                case .deliver:
                    break
                }

                IslandLogger.webhook.info(
                    "Received Manus event: \(payload.event.rawValue, privacy: .public)"
                )
                onEvent(payload)
                return .ok
            }

            let app = Application(
                router: router,
                configuration: .init(address: .hostname("127.0.0.1", port: self.port))
            )
            do {
                try await app.run()
            } catch is CancellationError {
                // Expected during transactional shutdown.
            } catch {
                IslandLogger.webhook.error("WebhookServer serve loop stopped unexpectedly")
            }
        }

        guard await waitForReadiness(token: readinessToken) else {
            serverTask?.cancel()
            serverTask = nil
            self.readinessToken = nil
            try Task.checkCancellation()
            throw WebhookServerStartError.readinessFailed
        }
        IslandLogger.webhook.info("WebhookServer listening on port \(self.port)")
    }

    public func stop() {
        serverTask?.cancel()
        serverTask = nil
        readinessToken = nil
        IslandLogger.webhook.info("WebhookServer stopped")
    }

    func isReady() async -> Bool {
        guard serverTask != nil, let readinessToken else { return false }
        return await Self.readinessEndpointResponds(
            port: port,
            token: readinessToken
        )
    }

    private func authenticate(
        body: Data,
        signature: String?,
        timestamp: String?
    ) -> AuthenticatedWebhookRequest? {
        authenticator.authenticate(
            body: body,
            signature: signature,
            timestamp: timestamp,
            externalURL: externalURL
        )
    }

    private func markEventForDelivery(
        _ eventID: String,
        authentication: AuthenticatedWebhookRequest
    ) -> WebhookReplayWindow.Decision {
        replayWindow.register(eventID: eventID, authentication: authentication)
    }

    private func waitForReadiness(token: String) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline {
            guard !Task.isCancelled,
                  self.readinessToken == token,
                  serverTask != nil else { return false }
            if await Self.readinessEndpointResponds(port: port, token: token) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return false
    }

    private nonisolated static func readinessEndpointResponds(
        port: Int,
        token: String
    ) async -> Bool {
        await LoopbackHTTPReadinessProbe.responds(
            port: port,
            path: "/_dev-island/webhook-ready/\(token)",
            expectedResponse: Data(token.utf8)
        )
    }
}
