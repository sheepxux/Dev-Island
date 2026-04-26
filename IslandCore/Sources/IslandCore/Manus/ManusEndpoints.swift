import Foundation

enum ManusEndpoints {
    static let baseURL = URL(string: "https://api.manus.im")!

    static func listTasks(apiKey: String) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/tasks"))
        req.httpMethod = "GET"
        req.setValue(apiKey, forHTTPHeaderField: "API_KEY")
        return req
    }

    static func registerWebhook(apiKey: String, publicURL: String) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/webhooks"))
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "API_KEY")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["url": publicURL]
        req.httpBody = try? JSONEncoder().encode(body)
        return req
    }

    static func deleteWebhook(apiKey: String, webhookId: String) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/webhooks/\(webhookId)"))
        req.httpMethod = "DELETE"
        req.setValue(apiKey, forHTTPHeaderField: "API_KEY")
        return req
    }

    static func getTask(apiKey: String, taskId: String) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/tasks/\(taskId)"))
        req.httpMethod = "GET"
        req.setValue(apiKey, forHTTPHeaderField: "API_KEY")
        return req
    }

    static func stopTask(apiKey: String, taskId: String) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/tasks/\(taskId)/stop"))
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "API_KEY")
        return req
    }
}
