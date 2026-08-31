import Foundation

enum ManusEndpoints {
    /// Legacy task endpoints were verified against a live account in April
    /// 2026 and remain the shipping polling/stop path until the v2 task API
    /// receives the same account-level acceptance pass.
    static let baseURL = URL(string: "https://api.manus.im")!
    /// Current official webhook API. Do not make this configurable at runtime:
    /// system TLS plus this pinned origin is the trust path for key rotation.
    static let realtimeBaseURL = URL(string: "https://api.manus.ai")!

    static func listTasks(apiKey: String) throws -> URLRequest {
        var req = try authenticatedRequest(
            url: baseURL.appendingPathComponent("v1/tasks"),
            apiKey: apiKey,
            header: "API_KEY"
        )
        req.httpMethod = "GET"
        return req
    }

    static func registerWebhook(apiKey: String, publicURL: String) throws -> URLRequest {
        guard validWebhookCallback(publicURL) else { throw ManusError.invalidURL }
        var req = try authenticatedRequest(
            url: realtimeBaseURL.appendingPathComponent("v2/webhook.create"),
            apiKey: apiKey,
            header: "x-manus-api-key"
        )
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["url": publicURL]
        req.httpBody = try JSONEncoder().encode(body)
        return req
    }

    static func listWebhooks(apiKey: String) throws -> URLRequest {
        var req = try authenticatedRequest(
            url: realtimeBaseURL.appendingPathComponent("v2/webhook.list"),
            apiKey: apiKey,
            header: "x-manus-api-key"
        )
        req.httpMethod = "GET"
        return req
    }

    static func deleteWebhook(apiKey: String, webhookId: String) throws -> URLRequest {
        guard validIdentifier(webhookId) else { throw ManusError.invalidURL }
        var req = try authenticatedRequest(
            url: realtimeBaseURL.appendingPathComponent("v2/webhook.delete"),
            apiKey: apiKey,
            header: "x-manus-api-key"
        )
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["webhook_id": webhookId])
        return req
    }

    static func webhookPublicKey(apiKey: String) throws -> URLRequest {
        var req = try authenticatedRequest(
            url: realtimeBaseURL.appendingPathComponent("v2/webhook.publicKey"),
            apiKey: apiKey,
            header: "x-manus-api-key"
        )
        req.httpMethod = "GET"
        return req
    }

    static func getTask(apiKey: String, taskId: String) throws -> URLRequest {
        guard validIdentifier(taskId) else { throw ManusError.invalidURL }
        var req = try authenticatedRequest(
            url: baseURL.appendingPathComponent("v1/tasks/\(taskId)"),
            apiKey: apiKey,
            header: "API_KEY"
        )
        req.httpMethod = "GET"
        return req
    }

    static func stopTask(apiKey: String, taskId: String) throws -> URLRequest {
        guard validIdentifier(taskId) else { throw ManusError.invalidURL }
        var req = try authenticatedRequest(
            url: baseURL.appendingPathComponent("v1/tasks/\(taskId)/stop"),
            apiKey: apiKey,
            header: "API_KEY"
        )
        req.httpMethod = "POST"
        return req
    }

    /// API keys become HTTP header values, so reject controls, whitespace and
    /// unbounded input before URLSession sees them. Manus' observed `sk-…`
    /// credentials are printable ASCII and comfortably below this limit.
    private static func authenticatedRequest(
        url: URL,
        apiKey: String,
        header: String
    ) throws -> URLRequest {
        guard ManusCredentialPolicy.validated(apiKey) != nil else {
            throw ManusError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: header)
        return request
    }

    /// Remote task/webhook IDs are data, never path syntax. Restrict them to
    /// the provider's observed opaque-ID alphabet before interpolation so `/`,
    /// `..`, percent escapes and controls cannot select a different API route.
    private static func validIdentifier(_ value: String) -> Bool {
        ManusRemoteContentPolicy.isValidOpaqueIdentifier(value)
    }

    /// Realtime registration must point to the exact quick-tunnel callback
    /// produced by CloudflaredProcess. Do not let an unexpected caller spend
    /// the user's Manus credential registering an unrelated endpoint.
    private static func validWebhookCallback(_ value: String) -> Bool {
        guard value.utf8.count <= 2_048,
              let components = URLComponents(string: value),
              components.scheme == "https",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil,
              components.percentEncodedPath == "/webhook",
              let host = components.host?.lowercased(),
              host == components.host,
              host.hasSuffix(".trycloudflare.com"),
              host.count > ".trycloudflare.com".count,
              host.dropLast(".trycloudflare.com".count).allSatisfy({
                  $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")
              }),
              components.url?.absoluteString == value else {
            return false
        }
        return true
    }
}
