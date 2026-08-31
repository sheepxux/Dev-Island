import CryptoKit
import Foundation
import Hummingbird
import HTTPTypes  // [C→S] HTTPField type lives here on macOS Swift 6.3+
import Security

private enum WebhookPublicKeyIdentity {
    static func canonicalDigest(pem: String) -> Data? {
        let stripped = pem
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN RSA PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PUBLIC KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard let derData = Data(base64Encoded: stripped) else { return nil }

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
        ]
        var candidates = [derData]
        if let unwrapped = unwrappedSubjectPublicKeyInfo(derData), unwrapped != derData {
            candidates.append(unwrapped)
        }

        for candidate in candidates {
            var importError: Unmanaged<CFError>?
            guard let key = SecKeyCreateWithData(
                candidate as CFData,
                attributes as CFDictionary,
                &importError
            ) else {
                _ = importError?.takeRetainedValue()
                continue
            }
            guard let keyAttributes = SecKeyCopyAttributes(key) as? [CFString: Any],
                  let keySizeInBits = keyAttributes[kSecAttrKeySizeInBits] as? Int,
                  keySizeInBits >= 2_048 else {
                continue
            }
            var exportError: Unmanaged<CFError>?
            guard let canonicalBytes = SecKeyCopyExternalRepresentation(
                key,
                &exportError
            ) as Data? else {
                _ = exportError?.takeRetainedValue()
                continue
            }
            return Data(SHA256.hash(data: canonicalBytes))
        }
        return nil
    }

    /// Security.framework imports the raw PKCS#1 body consistently across the
    /// two PEM shapes Manus can publish. Unwrap the standard RSA
    /// SubjectPublicKeyInfo envelope before deriving the stable key identity.
    private static func unwrappedSubjectPublicKeyInfo(_ data: Data) -> Data? {
        guard data.count > 26 else { return nil }
        let rsaOID: [UInt8] = [
            0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01,
        ]
        guard Array(data[8..<17]) == rsaOID else { return nil }

        for index in 16..<min(data.count - 2, 30) where data[index] == 0x03 {
            let lengthByte = data[index + 1]
            let bodyOffset: Int
            if lengthByte & 0x80 == 0 {
                bodyOffset = index + 3
            } else {
                let lengthByteCount = Int(lengthByte & 0x7f)
                guard lengthByteCount > 0,
                      index + 2 + lengthByteCount < data.count else { return nil }
                bodyOffset = index + 2 + lengthByteCount + 1
            }
            guard bodyOffset < data.count else { return nil }
            return data.subdata(in: bodyOffset..<data.count)
        }
        return nil
    }
}

struct WebhookRequestAuthenticator: Sendable {
    private let signaturePublicKeyPEM: String
    let canonicalPublicKeyIdentity: Data

    init?(signaturePublicKeyPEM: String) {
        let normalized = signaturePublicKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              WebhookSignature.canImportPublicKey(normalized),
              let canonicalPublicKeyIdentity = WebhookPublicKeyIdentity.canonicalDigest(
                  pem: normalized
              ) else { return nil }
        self.signaturePublicKeyPEM = normalized
        self.canonicalPublicKeyIdentity = canonicalPublicKeyIdentity
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

private struct AuthenticatedWebhookContext: Sendable {
    let request: AuthenticatedWebhookRequest
    let trustGeneration: UUID
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

private struct WebhookTrustConfiguration: Equatable, Sendable {
    let externalURL: String
    let publicKeyIdentity: Data
}

private enum WebhookDeliveryDecision: Sendable {
    case deliver
    case duplicate
    case saturated
    case staleTrustGeneration
}

public actor WebhookServer {  // [C→S] public so the CLI target can use it
    let port: Int
    private var serverTask: Task<Void, Never>?
    private var readinessToken: String?
    private var authenticator: WebhookRequestAuthenticator
    private var externalURL: String?
    private var trustConfiguration: WebhookTrustConfiguration?
    private var trustGeneration = UUID()
    private static let replayCacheLimit = 1_024
    private var replayWindow: WebhookReplayWindow
    private let afterAuthenticationForTesting: (@Sendable () async -> Void)?

    /// A server cannot exist without an explicit non-empty trust anchor.
    /// This keeps every call site fail-closed, including development tools.
    public init?(port: Int = 7823, signaturePublicKeyPEM: String) {
        guard let authenticator = WebhookRequestAuthenticator(
            signaturePublicKeyPEM: signaturePublicKeyPEM
        ) else { return nil }
        self.port = port
        self.authenticator = authenticator
        self.replayWindow = WebhookReplayWindow(capacity: Self.replayCacheLimit)
        self.afterAuthenticationForTesting = nil
    }

    /// Module-internal transport-test seam. Production call sites must use the
    /// public initializer and its fixed 1,024-entry fail-closed window.
    init?(
        port: Int,
        signaturePublicKeyPEM: String,
        replayCapacity: Int,
        afterAuthenticationForTesting: (@Sendable () async -> Void)? = nil
    ) {
        guard replayCapacity > 0,
              let authenticator = WebhookRequestAuthenticator(
                  signaturePublicKeyPEM: signaturePublicKeyPEM
              ) else { return nil }
        self.port = port
        self.authenticator = authenticator
        self.replayWindow = WebhookReplayWindow(capacity: replayCapacity)
        self.afterAuthenticationForTesting = afterAuthenticationForTesting
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
        let candidateConfiguration = WebhookTrustConfiguration(
            externalURL: externalURL,
            publicKeyIdentity: authenticator.canonicalPublicKeyIdentity
        )

        // Replay IDs belong to one exact callback/trust generation. Equivalent
        // PEM encodings of the same RSA key preserve the live window, while a
        // new callback URL or actual key starts a fresh window with the same
        // production/test capacity. Every validation above completes before
        // this actor commits any part of the new tuple.
        if trustConfiguration != candidateConfiguration {
            replayWindow = WebhookReplayWindow(capacity: replayWindow.capacity)
            trustGeneration = UUID()
        }
        self.authenticator = authenticator
        self.externalURL = externalURL
        self.trustConfiguration = candidateConfiguration
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
        let afterAuthenticationForTesting = self.afterAuthenticationForTesting
        self.readinessToken = readinessToken
        let task = Task {
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

                // This optional suspension exists only for a deterministic
                // transport regression. The private trust-generation token
                // below makes this production-safe even if future route work
                // introduces a real suspension between verification and replay
                // registration.
                if let afterAuthenticationForTesting {
                    await afterAuthenticationForTesting()
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
                case .staleTrustGeneration:
                    IslandLogger.webhook.warning(
                        "Webhook trust generation changed during request"
                    )
                    return .unauthorized
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
            self.markServeLoopStopped(readinessToken: readinessToken)
        }
        serverTask = task

        guard await waitForReadiness(token: readinessToken) else {
            task.cancel()
            if self.readinessToken == readinessToken {
                serverTask = nil
                self.readinessToken = nil
            }
            await task.value
            try Task.checkCancellation()
            throw WebhookServerStartError.readinessFailed
        }
        IslandLogger.webhook.info("WebhookServer listening on port \(self.port)")
    }

    public func stop() async {
        let task = serverTask
        task?.cancel()
        serverTask = nil
        readinessToken = nil
        await task?.value
        IslandLogger.webhook.info("WebhookServer stopped")
    }

    func isReady() async -> Bool {
        guard serverTask != nil, let readinessToken else { return false }
        guard await Self.readinessEndpointResponds(
            port: port,
            token: readinessToken
        ) else { return false }
        return self.readinessToken == readinessToken && serverTask != nil
    }

    private func authenticate(
        body: Data,
        signature: String?,
        timestamp: String?
    ) -> AuthenticatedWebhookContext? {
        guard let request = authenticator.authenticate(
            body: body,
            signature: signature,
            timestamp: timestamp,
            externalURL: externalURL
        ) else { return nil }
        return AuthenticatedWebhookContext(
            request: request,
            trustGeneration: trustGeneration
        )
    }

    private func markEventForDelivery(
        _ eventID: String,
        authentication: AuthenticatedWebhookContext
    ) -> WebhookDeliveryDecision {
        guard authentication.trustGeneration == trustGeneration else {
            return .staleTrustGeneration
        }
        switch replayWindow.register(
            eventID: eventID,
            authentication: authentication.request
        ) {
        case .deliver:
            return .deliver
        case .duplicate:
            return .duplicate
        case .saturated:
            return .saturated
        }
    }

    private func waitForReadiness(token: String) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline {
            guard !Task.isCancelled,
                  self.readinessToken == token,
                  serverTask != nil else { return false }
            if await Self.readinessEndpointResponds(port: port, token: token) {
                return !Task.isCancelled
                    && self.readinessToken == token
                    && serverTask != nil
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return false
    }

    private func markServeLoopStopped(readinessToken: String) {
        guard self.readinessToken == readinessToken else { return }
        serverTask = nil
        self.readinessToken = nil
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
