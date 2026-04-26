import Foundation

public enum ManusError: Error, Sendable {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval)
    case httpError(statusCode: Int, body: String)
    case decodingError(underlying: Error)
    case invalidURL
    case networkUnavailable
}

public actor ManusAPIClient {
    let apiKey: String
    private let session: URLSession
    private let decoder: JSONDecoder

    // 429 指数退避: 第1次30s, 第2次90s, 第3次及以后300s (§8)
    private static let backoffSteps: [TimeInterval] = [30, 90, 300]
    private var consecutive429Count = 0
    private var rateLimitedUntil: Date?

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        // 日期由 DTO 手动解析（Manus 用 Unix 时间戳字符串，非 ISO 8601）
        self.decoder = d
    }

    // MARK: - Public API

    public func listTasks() async throws -> [AgentTask] {
        let req = ManusEndpoints.listTasks(apiKey: apiKey)
        let response: ManusListResponse = try await execute(req)
        return response.data.map { $0.toAgentTask() }
    }

    public func registerWebhook(publicURL: String) async throws -> String {
        let req = ManusEndpoints.registerWebhook(apiKey: apiKey, publicURL: publicURL)
        let response: WebhookRegistrationResponse = try await execute(req)
        return response.id
    }

    public func deleteWebhook(id: String) async throws {
        let req = ManusEndpoints.deleteWebhook(apiKey: apiKey, webhookId: id)
        try await executeVoid(req)
    }

    public func getTask(id: String) async throws -> AgentTask {
        let req = ManusEndpoints.getTask(apiKey: apiKey, taskId: id)
        let dto: ManusTaskDTO = try await execute(req)
        return dto.toAgentTask()
    }

    public func stopTask(id: String) async throws {
        let req = ManusEndpoints.stopTask(apiKey: apiKey, taskId: id)
        try await executeVoid(req)
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
        return max(step, serverHint)
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        try checkRateLimit()
        IslandLogger.api.debug("→ \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
        let data: Data
        let http: HTTPURLResponse
        do {
            let (d, r) = try await session.data(for: request)
            data = d
            http = r as! HTTPURLResponse
        } catch let urlError as URLError where urlError.isNetworkUnavailable {
            throw ManusError.networkUnavailable
        }
        IslandLogger.api.debug("← \(http.statusCode)")
        switch http.statusCode {
        case 200...299:
            consecutive429Count = 0
            rateLimitedUntil = nil
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                IslandLogger.api.error("Decode error: \(error)\nBody: \(String(data: data, encoding: .utf8) ?? "")")
                throw ManusError.decodingError(underlying: error)
            }
        case 401:
            throw ManusError.unauthorized
        case 429:
            let hint = parseRetryAfter(from: http)
            let backoff = nextBackoffInterval(serverHint: hint)
            rateLimitedUntil = Date.now.addingTimeInterval(backoff)
            IslandLogger.api.warning("Rate limited — backing off \(backoff)s (attempt \(consecutive429Count))")
            throw ManusError.rateLimited(retryAfter: backoff)
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ManusError.httpError(statusCode: http.statusCode, body: body)
        }
    }

    private func executeVoid(_ request: URLRequest) async throws {
        try checkRateLimit()
        IslandLogger.api.debug("→ \(request.httpMethod ?? "POST") \(request.url?.absoluteString ?? "")")
        let data: Data
        let http: HTTPURLResponse
        do {
            let (d, r) = try await session.data(for: request)
            data = d
            http = r as! HTTPURLResponse
        } catch let urlError as URLError where urlError.isNetworkUnavailable {
            throw ManusError.networkUnavailable
        }
        IslandLogger.api.debug("← \(http.statusCode)")
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
            IslandLogger.api.warning("Rate limited — backing off \(backoff)s (attempt \(consecutive429Count))")
            throw ManusError.rateLimited(retryAfter: backoff)
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ManusError.httpError(statusCode: http.statusCode, body: body)
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

/// Webhook registration response: { "id": "..." }
private struct WebhookRegistrationResponse: Decodable {
    let id: String
}
