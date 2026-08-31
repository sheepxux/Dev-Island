import Foundation

public enum ManusError: Error, Sendable {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval)
    case httpError(statusCode: Int, responseBytes: Int)
    case decodingError(underlying: Error)
    case invalidURL
    case invalidResponse
    case networkUnavailable
}

/// One account-owned Manus v2 webhook returned by the authenticated list API.
/// Provider-authored fields cross the public boundary only after strict local
/// validation, so recovery code never has to interpret an arbitrary URL or ID.
public struct ManusWebhook: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case active
        case inactive
    }

    public let id: String
    public let url: String
    public let status: Status
    public let createdAt: Int64

    init(
        id: String,
        url: String,
        status: Status,
        createdAt: Int64
    ) {
        self.id = id
        self.url = url
        self.status = status
        self.createdAt = createdAt
    }
}

private enum ManusAPIOperation: String, Sendable {
    case listTasks = "list_tasks"
    case registerWebhook = "register_webhook"
    case listWebhooks = "list_webhooks"
    case deleteWebhook = "delete_webhook"
    case webhookPublicKey = "webhook_public_key"
    case getTask = "get_task"
    case stopTask = "stop_task"
}

/// Manus requests carry a reusable API credential. Production networking must
/// therefore be stateless and must never follow even a same-origin redirect:
/// the two API origins and exact routes are part of the reviewed trust path.
final class ManusNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

enum ManusTransportSecurityPolicy {
    private static let redirectDelegate = ManusNoRedirectDelegate()

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return URLSession(
            configuration: configuration,
            delegate: redirectDelegate,
            delegateQueue: nil
        )
    }

    static func responseOriginMatches(
        _ response: HTTPURLResponse,
        request: URLRequest
    ) -> Bool {
        guard let requestURL = request.url,
              let responseURL = response.url,
              requestURL.scheme?.lowercased() == "https",
              responseURL.scheme?.lowercased() == "https",
              requestURL.host?.lowercased() == responseURL.host?.lowercased(),
              effectivePort(requestURL) == effectivePort(responseURL),
              requestURL.user == nil,
              requestURL.password == nil,
              responseURL.user == nil,
              responseURL.password == nil else {
            return false
        }
        return true
    }

    private static func effectivePort(_ url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : nil)
    }
}

public actor ManusAPIClient {
    let apiKey: String
    private let session: URLSession
    private let decoder: JSONDecoder

    // 429 指数退避: 第1次30s, 第2次90s, 第3次及以后300s (§8)
    private static let backoffSteps: [TimeInterval] = [30, 90, 300]
    private static let maximumBackoff: TimeInterval = 300
    private var consecutive429Count = 0
    private var rateLimitedUntil: Date?
    private var cachedWebhookPublicKey: CachedWebhookPublicKey?

    private struct CachedWebhookPublicKey: Sendable {
        let pem: String
        let expiresAt: Date
    }

    private static let webhookPublicKeyTTL: TimeInterval = 3_600

    public init(apiKey: String, session: URLSession? = nil) {
        self.apiKey = apiKey
        self.session = session ?? ManusTransportSecurityPolicy.makeSession()
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        // 日期由 DTO 手动解析（Manus 用 Unix 时间戳字符串，非 ISO 8601）
        self.decoder = d
    }

    // MARK: - Public API

    public func listTasks() async throws -> [AgentTask] {
        let req = try ManusEndpoints.listTasks(apiKey: apiKey)
        let response: ManusListResponse = try await execute(req, operation: .listTasks)
        return response.data.map { $0.toAgentTask() }
    }

    public func registerWebhook(publicURL: String) async throws -> String {
        let req = try ManusEndpoints.registerWebhook(apiKey: apiKey, publicURL: publicURL)
        let response: WebhookRegistrationResponse = try await execute(
            req,
            operation: .registerWebhook
        )
        guard response.ok,
              let webhook = response.webhook.validated(),
              webhook.url == publicURL,
              webhook.status == .active else {
            throw ManusError.invalidResponse
        }
        return webhook.id
    }

    /// Return the complete, bounded set exposed by Manus' authenticated
    /// `webhook.list` endpoint. Duplicate IDs make the provider snapshot
    /// ambiguous and therefore fail closed instead of being deduplicated.
    public func listWebhooks() async throws -> [ManusWebhook] {
        let req = try ManusEndpoints.listWebhooks(apiKey: apiKey)
        let response: WebhookListResponse = try await execute(
            req,
            operation: .listWebhooks
        )
        guard response.ok,
              let rows = response.data,
              rows.count <= ManusWebhookPolicy.maximumWebhookCount else {
            throw ManusError.invalidResponse
        }

        var identifiers = Set<String>()
        var webhooks: [ManusWebhook] = []
        webhooks.reserveCapacity(rows.count)
        for row in rows {
            guard let webhook = row.validated(),
                  identifiers.insert(webhook.id).inserted else {
                throw ManusError.invalidResponse
            }
            webhooks.append(webhook)
        }
        return webhooks
    }

    public func deleteWebhook(id: String) async throws {
        let req = try ManusEndpoints.deleteWebhook(apiKey: apiKey, webhookId: id)
        let response: WebhookDeletionResponse = try await execute(
            req,
            operation: .deleteWebhook,
            idempotentNotFoundValue: WebhookDeletionResponse(ok: true)
        )
        guard response.ok else { throw ManusError.invalidResponse }
    }

    /// Fetch Manus' RSA verification key from its authenticated, hard-coded
    /// v2 origin. The official guidance recommends a one-hour cache; refreshes
    /// happen naturally when a tunnel is registered after that TTL.
    public func webhookPublicKey() async throws -> String {
        if let cachedWebhookPublicKey,
           cachedWebhookPublicKey.expiresAt > Date.now {
            return cachedWebhookPublicKey.pem
        }

        let req = try ManusEndpoints.webhookPublicKey(apiKey: apiKey)
        let response: WebhookPublicKeyResponse = try await execute(
            req,
            operation: .webhookPublicKey
        )
        let pem = response.publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard response.ok,
              response.algorithm == "RSA-SHA256",
              pem.count <= 16_384,
              pem.hasPrefix("-----BEGIN PUBLIC KEY-----") ||
                pem.hasPrefix("-----BEGIN RSA PUBLIC KEY-----") else {
            throw ManusError.invalidResponse
        }

        cachedWebhookPublicKey = CachedWebhookPublicKey(
            pem: pem,
            expiresAt: Date.now.addingTimeInterval(Self.webhookPublicKeyTTL)
        )
        return pem
    }

    public func getTask(id: String) async throws -> AgentTask {
        let req = try ManusEndpoints.getTask(apiKey: apiKey, taskId: id)
        let dto: ManusTaskDTO = try await execute(req, operation: .getTask)
        guard dto.id == id else { throw ManusError.invalidResponse }
        return dto.toAgentTask()
    }

    public func stopTask(id: String) async throws {
        let req = try ManusEndpoints.stopTask(apiKey: apiKey, taskId: id)
        try await executeVoid(req, operation: .stopTask)
    }

    // MARK: - Private execute helpers

    private func checkRateLimit() throws {
        if let until = rateLimitedUntil, Date.now < until {
            throw ManusError.rateLimited(retryAfter: until.timeIntervalSinceNow)
        }
    }

    private func nextBackoffInterval(serverHint: TimeInterval) -> TimeInterval {
        let step = Self.backoffSteps[min(consecutive429Count, Self.backoffSteps.count - 1)]
        consecutive429Count += 1
        let boundedHint: TimeInterval
        if serverHint.isFinite {
            boundedHint = min(max(serverHint, 0), Self.maximumBackoff)
        } else {
            boundedHint = 0
        }
        return min(max(step, boundedHint), Self.maximumBackoff)
    }

    private func execute<T: Decodable>(
        _ request: URLRequest,
        operation: ManusAPIOperation,
        idempotentNotFoundValue: T? = nil
    ) async throws -> T {
        try checkRateLimit()
        IslandLogger.api.debug("Manus request started: \(operation.rawValue, privacy: .public)")
        let data: Data
        let response: URLResponse
        do {
            let (d, r) = try await session.data(for: request)
            data = d
            response = r
        } catch let urlError as URLError where urlError.isNetworkUnavailable {
            throw ManusError.networkUnavailable
        }
        guard let http = response as? HTTPURLResponse else {
            IslandLogger.api.error(
                "Manus request returned a non-HTTP response: \(operation.rawValue, privacy: .public)"
            )
            throw ManusError.invalidResponse
        }
        guard ManusTransportSecurityPolicy.responseOriginMatches(http, request: request) else {
            IslandLogger.api.error(
                "Manus response origin mismatch: \(operation.rawValue, privacy: .public)"
            )
            throw ManusError.invalidResponse
        }
        guard data.count <= ManusRemoteContentPolicy.maximumResponseBytes else {
            IslandLogger.api.error(
                "Manus response exceeded the bounded decode limit: \(operation.rawValue, privacy: .public)"
            )
            throw ManusError.invalidResponse
        }
        IslandLogger.api.debug(
            "Manus response: \(operation.rawValue, privacy: .public) status=\(http.statusCode)"
        )
        switch http.statusCode {
        case 200...299:
            consecutive429Count = 0
            rateLimitedUntil = nil
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                let errorType = String(reflecting: type(of: error))
                IslandLogger.api.error(
                    "Decode failed: type=\(errorType, privacy: .public) responseBytes=\(data.count, privacy: .public)"
                )
                throw ManusError.decodingError(underlying: error)
            }
        case 401:
            throw ManusError.unauthorized
        case 429:
            let hint = parseRetryAfter(from: http)
            let backoff = nextBackoffInterval(serverHint: hint)
            rateLimitedUntil = Date.now.addingTimeInterval(backoff)
            IslandLogger.api.warning("Rate limited — backing off \(backoff)s (attempt \(self.consecutive429Count))")
            throw ManusError.rateLimited(retryAfter: backoff)
        case 404:
            guard operation == .deleteWebhook,
                  let idempotentNotFoundValue,
                  let response = try? decoder.decode(ManusAPIErrorResponse.self, from: data),
                  response.ok == false,
                  response.error.code == "not_found" else {
                throw ManusError.httpError(
                    statusCode: http.statusCode,
                    responseBytes: data.count
                )
            }
            // A crash may occur after Manus deletes the webhook but before the
            // local cleanup ledger is cleared. The official `not_found` error
            // is therefore the only non-2xx response that confirms the desired
            // delete postcondition. Treat it like a successful request for
            // backoff accounting as well as for the caller's result.
            consecutive429Count = 0
            rateLimitedUntil = nil
            return idempotentNotFoundValue
        default:
            throw ManusError.httpError(statusCode: http.statusCode, responseBytes: data.count)
        }
    }

    private func executeVoid(
        _ request: URLRequest,
        operation: ManusAPIOperation
    ) async throws {
        try checkRateLimit()
        IslandLogger.api.debug("Manus request started: \(operation.rawValue, privacy: .public)")
        let data: Data
        let response: URLResponse
        do {
            let (d, r) = try await session.data(for: request)
            data = d
            response = r
        } catch let urlError as URLError where urlError.isNetworkUnavailable {
            throw ManusError.networkUnavailable
        }
        guard let http = response as? HTTPURLResponse else {
            IslandLogger.api.error(
                "Manus request returned a non-HTTP response: \(operation.rawValue, privacy: .public)"
            )
            throw ManusError.invalidResponse
        }
        guard ManusTransportSecurityPolicy.responseOriginMatches(http, request: request) else {
            IslandLogger.api.error(
                "Manus response origin mismatch: \(operation.rawValue, privacy: .public)"
            )
            throw ManusError.invalidResponse
        }
        guard data.count <= ManusRemoteContentPolicy.maximumResponseBytes else {
            IslandLogger.api.error(
                "Manus response exceeded the bounded decode limit: \(operation.rawValue, privacy: .public)"
            )
            throw ManusError.invalidResponse
        }
        IslandLogger.api.debug(
            "Manus response: \(operation.rawValue, privacy: .public) status=\(http.statusCode)"
        )
        switch http.statusCode {
        case 200...299:
            consecutive429Count = 0
            rateLimitedUntil = nil
        case 401:
            throw ManusError.unauthorized
        case 429:
            let hint = parseRetryAfter(from: http)
            let backoff = nextBackoffInterval(serverHint: hint)
            rateLimitedUntil = Date.now.addingTimeInterval(backoff)
            IslandLogger.api.warning("Rate limited — backing off \(backoff)s (attempt \(self.consecutive429Count))")
            throw ManusError.rateLimited(retryAfter: backoff)
        default:
            throw ManusError.httpError(statusCode: http.statusCode, responseBytes: data.count)
        }
    }

    private func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval {
        if let value = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Double(value) { return seconds }
        return 0
    }
}

// MARK: - URLError network detection

private extension URLError {
    var isNetworkUnavailable: Bool {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .timedOut:
            return true
        default:
            return false
        }
    }
}

// MARK: - Internal DTOs (map real Manus API shape → AgentTask)

/// Real Manus API list response: { "object": "list", "data": [...] }
private struct ManusListResponse: Decodable {
    let data: [ManusTaskDTO]

    private enum CodingKeys: String, CodingKey {
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let data = try container.decode([ManusTaskDTO].self, forKey: .data)
        guard data.count <= ManusRemoteContentPolicy.maximumTaskCount else {
            throw DecodingError.dataCorruptedError(
                forKey: .data,
                in: container,
                debugDescription: "Manus task list exceeds the bounded item limit"
            )
        }
        self.data = data
    }
}

/// Real Manus task shape (as returned by GET /v1/tasks and GET /v1/tasks/{id})
struct ManusTaskDTO: Decodable {
    let id: String
    let createdAt: String   // Unix timestamp as string, e.g. "1777072176"
    let updatedAt: String
    let status: ManusStatus
    let metadata: Metadata

    struct Metadata: Decodable {
        let taskTitle: String
        let taskUrl: String
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, updatedAt, status, metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        status = try container.decode(ManusStatus.self, forKey: .status)
        metadata = try container.decode(Metadata.self, forKey: .metadata)

        guard ManusRemoteContentPolicy.isValidOpaqueIdentifier(id),
              ManusRemoteContentPolicy.isValidTimestamp(createdAt),
              ManusRemoteContentPolicy.isValidTimestamp(updatedAt),
              ManusRemoteContentPolicy.isValidTitle(metadata.taskTitle),
              TaskDestinationPolicy.manusDestination(
                  rawValue: metadata.taskUrl,
                  taskID: id
              ) != nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .metadata,
                in: container,
                debugDescription: "Manus task contains an unsafe or unbounded field"
            )
        }
    }

    /// Manus API status values → our TaskStatus enum
    enum ManusStatus: String, Decodable {
        case pending    // task is queued
        case running    // actively executing
        case completed
        case failed
        case paused     // paused, needs input → .waiting
        case stopped    // stopped by ask-user → .waiting

        var taskStatus: TaskStatus {
            switch self {
            case .pending, .running: return .running
            case .completed:         return .completed
            case .failed:            return .failed
            case .paused, .stopped:  return .waiting
            }
        }
    }

    func toAgentTask() -> AgentTask {
        let createdDate = Double(createdAt).map { Date(timeIntervalSince1970: $0) } ?? Date.now
        let updatedDate = Double(updatedAt).map { Date(timeIntervalSince1970: $0) } ?? Date.now
        return AgentTask(
            id: id,
            source: "manus",
            title: metadata.taskTitle,
            status: status.taskStatus,
            createdAt: createdDate,
            updatedAt: updatedDate,
            taskURL: metadata.taskUrl
        )
    }
}

private enum ManusWebhookPolicy {
    static let maximumWebhookCount = 1_024
    private static let maximumURLBytes = 2_048

    static func isCanonicalHTTPSURL(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.utf8.count <= maximumURLBytes,
              let components = URLComponents(string: value),
              components.scheme == "https",
              components.user == nil,
              components.password == nil,
              components.fragment == nil,
              let host = components.host,
              !host.isEmpty,
              host == host.lowercased(),
              components.url?.absoluteString == value else {
            return false
        }
        return true
    }
}

/// Exact webhook object shared by the official create and list responses.
/// The OpenAPI document does not mark its properties `required`, so ordinary
/// decoding deliberately requires all four fields before validation begins.
private struct ManusWebhookDTO: Decodable {
    let id: String
    let url: String
    let status: String
    let createdAt: Int64

    func validated() -> ManusWebhook? {
        guard ManusRemoteContentPolicy.isValidOpaqueIdentifier(id),
              ManusWebhookPolicy.isCanonicalHTTPSURL(url),
              let status = ManusWebhook.Status(rawValue: status),
              createdAt >= 0 else {
            return nil
        }
        return ManusWebhook(
            id: id,
            url: url,
            status: status,
            createdAt: createdAt
        )
    }
}

/// Official v2 webhook registration response.
private struct WebhookRegistrationResponse: Decodable {
    let ok: Bool
    let webhook: ManusWebhookDTO
}

/// Official v2 webhook list response. `data` is optional only so `ok:false`
/// can be classified as an explicit invalid response instead of accidentally
/// accepting a missing collection; successful calls require it below.
private struct WebhookListResponse: Decodable {
    let ok: Bool
    let data: [ManusWebhookDTO]?
}

/// Official v2 webhook deletion response. A successful HTTP status alone does
/// not confirm that Manus removed the remote webhook.
private struct WebhookDeletionResponse: Decodable {
    let ok: Bool
}

/// Minimal projection of Manus' official error envelope. The shared execute
/// path bounds the response body before decoding; deletion recovery only
/// inspects the exact machine-readable code and ignores human-facing text.
private struct ManusAPIErrorResponse: Decodable {
    struct Details: Decodable {
        let code: String
    }

    let ok: Bool
    let error: Details
}

/// Official v2 authenticated public-key response.
private struct WebhookPublicKeyResponse: Decodable {
    let ok: Bool
    let publicKey: String
    let algorithm: String
}
