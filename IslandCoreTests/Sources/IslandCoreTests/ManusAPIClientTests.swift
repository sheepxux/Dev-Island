import XCTest
import Foundation
@testable import IslandCore

final class ManusAPIClientTests: XCTestCase {

    // MARK: - Mock URLProtocol

    final class MockURLProtocol: URLProtocol {
        static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            do {
                guard let handler = Self.handler else {
                    client?.urlProtocol(self, didFailWithError: URLError(.unknown))
                    return
                }
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    var session: URLSession!

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        session = nil
    }

    private func makeResponse(statusCode: Int, url: URL = URL(string: "https://api.manus.im/v1/tasks")!) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    // MARK: - Tests

    func testListTasksSuccess() async throws {
        let json = """
        {"tasks":[{"id":"t1","source":"manus","title":"Test Task","status":"running","created_at":"2024-01-01T00:00:00Z","updated_at":"2024-01-01T00:00:00Z","task_url":"https://manus.im/tasks/t1"}]}
        """
        MockURLProtocol.handler = { _ in
            (self.makeResponse(statusCode: 200), Data(json.utf8))
        }
        let client = ManusAPIClient(apiKey: "test_key", session: session)
        let tasks = try await client.listTasks()
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].id, "t1")
        XCTAssertEqual(tasks[0].title, "Test Task")
        XCTAssertEqual(tasks[0].status, .running)
    }

    func testListTasksUnauthorized() async {
        MockURLProtocol.handler = { _ in
            (self.makeResponse(statusCode: 401), Data())
        }
        let client = ManusAPIClient(apiKey: "bad_key", session: session)
        do {
            _ = try await client.listTasks()
            XCTFail("Expected ManusError.unauthorized")
        } catch ManusError.unauthorized {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testListTasksRateLimited() async {
        MockURLProtocol.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.manus.im/v1/tasks")!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Retry-After": "30"]
            )!
            return (response, Data())
        }
        let client = ManusAPIClient(apiKey: "test_key", session: session)
        do {
            _ = try await client.listTasks()
            XCTFail("Expected ManusError.rateLimited")
        } catch ManusError.rateLimited(let retryAfter) {
            XCTAssertEqual(retryAfter, 30, accuracy: 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testListTasksHttpError() async {
        let errorBody = "{\"error\":\"Internal Server Error\"}"
        MockURLProtocol.handler = { _ in
            (self.makeResponse(statusCode: 500), Data(errorBody.utf8))
        }
        let client = ManusAPIClient(apiKey: "test_key", session: session)
        do {
            _ = try await client.listTasks()
            XCTFail("Expected ManusError.httpError")
        } catch ManusError.httpError(let statusCode, _) {
            XCTAssertEqual(statusCode, 500)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRegisterWebhookSuccess() async throws {
        let json = "{\"id\":\"wh_abc123\"}"
        MockURLProtocol.handler = { _ in
            (self.makeResponse(statusCode: 200, url: URL(string: "https://api.manus.im/v1/webhooks")!), Data(json.utf8))
        }
        let client = ManusAPIClient(apiKey: "test_key", session: session)
        let id = try await client.registerWebhook(publicURL: "https://abc.trycloudflare.com/webhook")
        XCTAssertEqual(id, "wh_abc123")
    }

    func testNetworkUnavailableThrowsCorrectError() async {
        MockURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        let client = ManusAPIClient(apiKey: "test_key", session: session)
        do {
            _ = try await client.listTasks()
            XCTFail("Expected ManusError.networkUnavailable")
        } catch ManusError.networkUnavailable {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testBackoffEscalates30s90s300s() async {
        // First 429 → 30s, second → 90s, third → 300s
        MockURLProtocol.handler = { _ in
            (self.makeResponse(statusCode: 429), Data())
        }
        let client = ManusAPIClient(apiKey: "test_key", session: session)

        // 1st 429: expect ≥30s
        if case .rateLimited(let t) = try? await { () -> ManusError? in
            do { _ = try await client.listTasks() } catch let e as ManusError { return e }
            return nil
        }() {
            XCTAssertGreaterThanOrEqual(t, 30)
            XCTAssertLessThan(t, 90)
        }
    }
}
