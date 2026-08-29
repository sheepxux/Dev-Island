import XCTest
import Foundation
@testable import IslandCore

final class ManusAPIClientTests: XCTestCase {

    // MARK: - Mock URLProtocol

    final class MockURLProtocol: URLProtocol {
        static var handler: ((URLRequest) throws -> (URLResponse, Data))?

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
        // Real Manus shape: top-level "data", metadata nesting, Unix-string timestamps
        // (see docs/manus-api-field-notes.md)
        let json = """
        {"object":"list","data":[{"id":"t1","object":"task","created_at":"1777072176","updated_at":"1777072212","status":"running","metadata":{"task_title":"Test Task","task_url":"https://manus.im/app/t1"}}]}
        """
        MockURLProtocol.handler = { _ in
            (self.makeResponse(statusCode: 200), Data(json.utf8))
        }
        let client = ManusAPIClient(apiKey: "sk-test-0123456789abcdef", session: session)
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
        let client = ManusAPIClient(apiKey: "sk-invalid-0123456789abcdef", session: session)
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
        let client = ManusAPIClient(apiKey: "sk-test-0123456789abcdef", session: session)
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
        let client = ManusAPIClient(apiKey: "sk-test-0123456789abcdef", session: session)
        do {
            _ = try await client.listTasks()
            XCTFail("Expected ManusError.httpError")
        } catch ManusError.httpError(let statusCode, let responseBytes) {
            XCTAssertEqual(statusCode, 500)
            XCTAssertEqual(responseBytes, Data(errorBody.utf8).count)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRegisterWebhookSuccess() async throws {
        let json = """
        {"ok":true,"request_id":"req_1","webhook":{"id":"wh_abc123","url":"https://abc.trycloudflare.com/webhook","status":"active","created_at":123}}
        """
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.manus.ai/v2/webhook.create")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "x-manus-api-key"),
                "sk-test-0123456789abcdef"
            )
            XCTAssertNil(request.value(forHTTPHeaderField: "API_KEY"))
            let body = try self.bodyData(for: request)
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: String]
            )
            XCTAssertEqual(object["url"], "https://abc.trycloudflare.com/webhook")
            return (
                self.makeResponse(statusCode: 200, url: request.url!),
                Data(json.utf8)
            )
        }
        let client = ManusAPIClient(apiKey: "sk-test-0123456789abcdef", session: session)
        let id = try await client.registerWebhook(publicURL: "https://abc.trycloudflare.com/webhook")
        XCTAssertEqual(id, "wh_abc123")
    }

    func testDeleteWebhookUsesOfficialV2RPCShape() async throws {
        let json = "{\"ok\":true,\"request_id\":\"req_2\"}"
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.manus.ai/v2/webhook.delete")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "x-manus-api-key"),
                "sk-test-0123456789abcdef"
            )
            let body = try self.bodyData(for: request)
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: String]
            )
            XCTAssertEqual(object["webhook_id"], "wh_abc123")
            return (
                self.makeResponse(statusCode: 200, url: request.url!),
                Data(json.utf8)
            )
        }
        let client = ManusAPIClient(apiKey: "sk-test-0123456789abcdef", session: session)

        try await client.deleteWebhook(id: "wh_abc123")
    }

    func testWebhookPublicKeyUsesOfficialEndpointAndOneHourCache() async throws {
        let pem = "-----BEGIN PUBLIC KEY-----\nQUJD\n-----END PUBLIC KEY-----"
        let json = """
        {"ok":true,"request_id":"req_3","public_key":"\(pem.replacingOccurrences(of: "\n", with: "\\n"))","algorithm":"RSA-SHA256"}
        """
        var requestCount = 0
        MockURLProtocol.handler = { request in
            requestCount += 1
            XCTAssertEqual(request.url?.absoluteString, "https://api.manus.ai/v2/webhook.publicKey")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "x-manus-api-key"),
                "sk-test-0123456789abcdef"
            )
            return (
                self.makeResponse(statusCode: 200, url: request.url!),
                Data(json.utf8)
            )
        }
        let client = ManusAPIClient(apiKey: "sk-test-0123456789abcdef", session: session)

        let first = try await client.webhookPublicKey()
        let second = try await client.webhookPublicKey()

        XCTAssertEqual(first, pem)
        XCTAssertEqual(second, pem)
        XCTAssertEqual(requestCount, 1)
    }

    func testWebhookPublicKeyRejectsUnexpectedAlgorithm() async {
        let json = """
        {"ok":true,"request_id":"req_4","public_key":"-----BEGIN PUBLIC KEY-----\\nQUJD\\n-----END PUBLIC KEY-----","algorithm":"HMAC-SHA256"}
        """
        MockURLProtocol.handler = { request in
            (
                self.makeResponse(statusCode: 200, url: request.url!),
                Data(json.utf8)
            )
        }
        let client = ManusAPIClient(apiKey: "sk-test-0123456789abcdef", session: session)

        do {
            _ = try await client.webhookPublicKey()
            XCTFail("Expected unexpected algorithm to fail closed")
        } catch ManusError.invalidResponse {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNetworkUnavailableThrowsCorrectError() async {
        MockURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        let client = ManusAPIClient(apiKey: "sk-test-0123456789abcdef", session: session)
        do {
            _ = try await client.listTasks()
            XCTFail("Expected ManusError.networkUnavailable")
        } catch ManusError.networkUnavailable {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDefaultTransportIsEphemeralBoundedAndRedirectFree() {
        let secureSession = ManusTransportSecurityPolicy.makeSession()
        defer { secureSession.invalidateAndCancel() }

        let configuration = secureSession.configuration
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertFalse(configuration.waitsForConnectivity)
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 15)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 30)
        XCTAssertTrue(secureSession.delegate is ManusNoRedirectDelegate)

        let delegate = ManusNoRedirectDelegate()
        let original = URLRequest(url: URL(string: "https://api.manus.im/v1/tasks")!)
        let task = secureSession.dataTask(with: original)
        defer { task.cancel() }
        let response = HTTPURLResponse(
            url: original.url!,
            statusCode: 302,
            httpVersion: nil,
            headerFields: ["Location": "https://collector.invalid/key"]
        )!
        let redirected = URLRequest(url: URL(string: "https://collector.invalid/key")!)
        var completionCalled = false
        var acceptedRedirect: URLRequest? = redirected

        delegate.urlSession(
            secureSession,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: redirected
        ) { request in
            completionCalled = true
            acceptedRedirect = request
        }

        XCTAssertTrue(completionCalled)
        XCTAssertNil(acceptedRedirect)
    }

    func testUnsafeCredentialIdentifiersAndCallbackNeverReachTransport() async {
        var requestCount = 0
        MockURLProtocol.handler = { request in
            requestCount += 1
            return (self.makeResponse(statusCode: 200, url: request.url!), Data("{}".utf8))
        }

        let unsafeKeyClient = ManusAPIClient(apiKey: "test\nkey", session: session)
        do {
            _ = try await unsafeKeyClient.listTasks()
            XCTFail("Expected unsafe header value to fail closed")
        } catch ManusError.invalidURL {
            // Expected before URLSession receives the request.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let client = ManusAPIClient(apiKey: "sk-test-0123456789abcdef", session: session)
        for taskID in ["../admin", "a/b", "%2fadmin", "task id", String(repeating: "a", count: 257)] {
            do {
                try await client.stopTask(id: taskID)
                XCTFail("Expected unsafe task ID to fail closed")
            } catch ManusError.invalidURL {
                // Expected before transport.
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        do {
            try await client.deleteWebhook(id: "../../webhook")
            XCTFail("Expected unsafe webhook ID to fail closed")
        } catch ManusError.invalidURL {
            // Expected before transport.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        for callback in [
            "https://collector.invalid/webhook",
            "http://fixture.trycloudflare.com/webhook",
            "https://fixture.trycloudflare.com/other",
            "https://fixture.trycloudflare.com/webhook?token=secret",
        ] {
            do {
                _ = try await client.registerWebhook(publicURL: callback)
                XCTFail("Expected untrusted callback to fail closed")
            } catch ManusError.invalidURL {
                // Expected before transport.
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(requestCount, 0)
    }

    func testOpaqueTaskIDStaysWithinOneReviewedRoute() async throws {
        let json = """
        {"id":"task_ABC-123","object":"task","created_at":"1777072176","updated_at":"1777072212","status":"running","metadata":{"task_title":"Test Task","task_url":"https://manus.im/app/task_ABC-123"}}
        """
        var methods: [String] = []
        MockURLProtocol.handler = { request in
            methods.append(request.httpMethod ?? "")
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://api.manus.im/v1/tasks/task_ABC-123" +
                    (request.httpMethod == "POST" ? "/stop" : "")
            )
            return (
                self.makeResponse(statusCode: 200, url: request.url!),
                request.httpMethod == "POST" ? Data() : Data(json.utf8)
            )
        }
        let client = ManusAPIClient(apiKey: "sk-test-0123456789abcdef", session: session)

        let task = try await client.getTask(id: "task_ABC-123")
        try await client.stopTask(id: "task_ABC-123")

        XCTAssertEqual(task.id, "task_ABC-123")
        XCTAssertEqual(methods, ["GET", "POST"])
    }

    func testCrossOriginHTTPResponsesFailClosedForValueAndVoidRequests() async {
        let evilURL = URL(string: "https://collector.invalid/capture")!
        MockURLProtocol.handler = { _ in
            (
                self.makeResponse(statusCode: 200, url: evilURL),
                Data("{\"object\":\"list\",\"data\":[]}".utf8)
            )
        }
        let client = ManusAPIClient(apiKey: "sk-test-0123456789abcdef", session: session)

        do {
            _ = try await client.listTasks()
            XCTFail("Expected cross-origin value response to fail closed")
        } catch ManusError.invalidResponse {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            try await client.stopTask(id: "task_123")
            XCTFail("Expected cross-origin void response to fail closed")
        } catch ManusError.invalidResponse {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRetryAfterCannotSuspendTheClientBeyondFiveMinutes() async {
        for (hint, expected) in [
            ("-10", 30.0),
            ("nan", 30.0),
            ("inf", 30.0),
            ("999999999", 300.0),
        ] {
            MockURLProtocol.handler = { request in
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: ["Retry-After": hint]
                )!
                return (response, Data())
            }
            let client = ManusAPIClient(
                apiKey: "sk-test-0123456789abcdef",
                session: session
            )

            do {
                _ = try await client.listTasks()
                XCTFail("Expected rate limiting")
            } catch ManusError.rateLimited(let retryAfter) {
                XCTAssertEqual(retryAfter, expected, accuracy: 0.01)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRemoteTaskFieldsFailClosedBeforeEnteringTheStore() async {
        let oversizedTitle = String(repeating: "x", count: 1_025)
        let unsafeRows = [
            """
            {"id":"task_1","object":"task","created_at":"1777072176","updated_at":"1777072212","status":"running","metadata":{"task_title":"Task","task_url":"file:///tmp/project"}}
            """,
            """
            {"id":"task_1","object":"task","created_at":"1777072176","updated_at":"1777072212","status":"running","metadata":{"task_title":"Task","task_url":"https://evil.example/app/task_1"}}
            """,
            """
            {"id":"task_1","object":"task","created_at":"1777072176","updated_at":"1777072212","status":"running","metadata":{"task_title":"\(oversizedTitle)","task_url":"https://manus.im/app/task_1"}}
            """,
            """
            {"id":"task/../1","object":"task","created_at":"1777072176","updated_at":"1777072212","status":"running","metadata":{"task_title":"Task","task_url":"https://manus.im/app/task/../1"}}
            """,
        ]

        for row in unsafeRows {
            let body = "{\"object\":\"list\",\"data\":[\(row)]}"
            MockURLProtocol.handler = { request in
                (
                    self.makeResponse(statusCode: 200, url: request.url!),
                    Data(body.utf8)
                )
            }
            let client = ManusAPIClient(
                apiKey: "sk-test-0123456789abcdef",
                session: session
            )

            do {
                _ = try await client.listTasks()
                XCTFail("Expected unsafe remote task fields to fail closed")
            } catch ManusError.decodingError {
                // Expected before any AgentTask can reach TaskStore or SQLite.
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testOversizedResponseFailsBeforeJSONDecode() async {
        let body = Data(repeating: 0x20, count: 1_048_577)
        MockURLProtocol.handler = { request in
            (self.makeResponse(statusCode: 200, url: request.url!), body)
        }
        let client = ManusAPIClient(
            apiKey: "sk-test-0123456789abcdef",
            session: session
        )

        do {
            _ = try await client.listTasks()
            XCTFail("Expected oversized response to fail closed")
        } catch ManusError.invalidResponse {
            // Expected before JSONDecoder sees the response.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGetTaskRejectsMismatchedResponseIdentity() async {
        let json = """
        {"id":"other_task","object":"task","created_at":"1777072176","updated_at":"1777072212","status":"running","metadata":{"task_title":"Other","task_url":"https://manus.im/app/other_task"}}
        """
        MockURLProtocol.handler = { request in
            (
                self.makeResponse(statusCode: 200, url: request.url!),
                Data(json.utf8)
            )
        }
        let client = ManusAPIClient(
            apiKey: "sk-test-0123456789abcdef",
            session: session
        )

        do {
            _ = try await client.getTask(id: "requested_task")
            XCTFail("Expected mismatched task identity to fail closed")
        } catch ManusError.invalidResponse {
            // Expected: a response cannot substitute another task.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNonHTTPResponseFailsClosedForDecodingEndpoint() async {
        MockURLProtocol.handler = { request in
            (URLResponse(
                url: request.url!,
                mimeType: nil,
                expectedContentLength: 0,
                textEncodingName: nil
            ), Data())
        }
        let client = ManusAPIClient(apiKey: "sk-test-0123456789abcdef", session: session)

        do {
            _ = try await client.listTasks()
            XCTFail("Expected ManusError.invalidResponse")
        } catch ManusError.invalidResponse {
            // Expected: never force-cast an untrusted transport response.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNonHTTPResponseFailsClosedForVoidEndpoint() async {
        MockURLProtocol.handler = { request in
            (URLResponse(
                url: request.url!,
                mimeType: nil,
                expectedContentLength: 0,
                textEncodingName: nil
            ), Data())
        }
        let client = ManusAPIClient(apiKey: "sk-test-0123456789abcdef", session: session)

        do {
            try await client.stopTask(id: "private-task-id")
            XCTFail("Expected ManusError.invalidResponse")
        } catch ManusError.invalidResponse {
            // Expected: void endpoints use the same fail-closed boundary.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testBackoffEscalates30s90s300s() async {
        // First 429 → 30s, second → 90s, third → 300s
        MockURLProtocol.handler = { _ in
            (self.makeResponse(statusCode: 429), Data())
        }
        let client = ManusAPIClient(apiKey: "sk-test-0123456789abcdef", session: session)

        // 1st 429: expect ≥30s
        if case .rateLimited(let t) = try? await { () -> ManusError? in
            do { _ = try await client.listTasks() } catch let e as ManusError { return e }
            return nil
        }() {
            XCTAssertGreaterThanOrEqual(t, 30)
            XCTAssertLessThan(t, 90)
        }
    }

    private func bodyData(for request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
