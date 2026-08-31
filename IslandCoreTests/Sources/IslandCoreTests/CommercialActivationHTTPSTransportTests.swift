import Foundation
import XCTest
@testable import IslandCore

final class CommercialActivationHTTPSTransportTests: XCTestCase {
    private let endpoint = URL(
        string: "https://activate.devisland.app/v1/activate"
    )!

    override func tearDown() {
        CommercialActivationHTTPSURLProtocol.reset()
        super.tearDown()
    }

    func testEndpointPolicyAcceptsOnlyExactPublicDNSHTTPSOrigin() throws {
        XCTAssertNoThrow(
            try CommercialActivationHTTPSTransport(endpoint: endpoint)
        )
        XCTAssertNoThrow(
            try CommercialActivationHTTPSTransport(
                endpoint: URL(
                    string: "https://activate.devisland.app:443/v1/activate"
                )!
            )
        )

        for rawURL in [
            "http://activate.devisland.app/v1/activate",
            "https://activate.devisland.app:8443/v1/activate",
            "https://user@activate.devisland.app/v1/activate",
            "https://user:password@activate.devisland.app/v1/activate",
            "https://activate.devisland.app/other",
            "https://activate.devisland.app/v1/activate/",
            "https://activate.devisland.app/%76%31/activate",
            "https://activate.devisland.app/v1/activate?code=secret",
            "https://activate.devisland.app/v1/activate#fragment",
            "https://localhost/v1/activate",
            "https://127.0.0.1/v1/activate",
            "https://[::1]/v1/activate",
            "https://activation.local/v1/activate",
            "https://activation.internal/v1/activate",
            "https://activation.invalid/v1/activate",
            "https://activation.localhost/v1/activate",
            "https://activation.test/v1/activate",
            "https://single-label/v1/activate",
            "https://empty..label/v1/activate",
            "https://-invalid.example/v1/activate",
            "https://invalid-.example/v1/activate",
        ] {
            XCTAssertThrowsError(
                try CommercialActivationHTTPSTransport(
                    endpoint: try XCTUnwrap(URL(string: rawURL))
                ),
                rawURL
            ) { error in
                XCTAssertEqual(
                    error as? CommercialActivationHTTPSTransportError,
                    .invalidEndpoint,
                    rawURL
                )
            }
        }
    }

    func testSessionConfigurationIsEphemeralBoundedAndCredentialFree() {
        let session = CommercialActivationHTTPSTransport.makeSession()
        defer { session.invalidateAndCancel() }
        let configuration = session.configuration

        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertNil(configuration.urlCache)
        XCTAssertEqual(
            configuration.requestCachePolicy,
            .reloadIgnoringLocalCacheData
        )
        XCTAssertEqual(
            configuration.timeoutIntervalForRequest,
            CommercialActivationHTTPSTransport.requestTimeout
        )
        XCTAssertEqual(
            configuration.timeoutIntervalForResource,
            CommercialActivationHTTPSTransport.requestTimeout
        )
        XCTAssertFalse(configuration.waitsForConnectivity)
        XCTAssertEqual(configuration.httpMaximumConnectionsPerHost, 1)
        XCTAssertEqual(configuration.connectionProxyDictionary?.count, 0)
        XCTAssertTrue(
            session.delegate is CommercialActivationHTTPSNoRedirectDelegate
        )
    }

    func testRedirectDelegateNeverAcceptsReplacementRequest() throws {
        let session = CommercialActivationHTTPSTransport.makeSession()
        defer { session.invalidateAndCancel() }
        let delegate = CommercialActivationHTTPSNoRedirectDelegate()
        let original = URLRequest(url: endpoint)
        let task = session.dataTask(with: original)
        defer { task.cancel() }
        let response = try XCTUnwrap(HTTPURLResponse(
            url: endpoint,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Location": "https://collector.invalid/activation-code",
            ]
        ))
        let redirected = URLRequest(
            url: URL(string: "https://collector.invalid/activation-code")!
        )
        var completionCalled = false
        var acceptedRedirect: URLRequest? = redirected

        delegate.urlSession(
            session,
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

    func testExactRequestAndStreamedDocumentResponse() async throws {
        let document = Data("signed-license-document".utf8)
        let recorder = CommercialActivationHTTPSRequestRecorder()
        CommercialActivationHTTPSURLProtocol.install { request in
            recorder.record(request)
            return .init(
                statusCode: 200,
                headers: [
                    "Content-Type": "application/vnd.devisland.license; charset=binary",
                    "Content-Length": "\(document.count)",
                ],
                chunks: [
                    document.prefix(7),
                    document.dropFirst(7).prefix(5),
                    document.dropFirst(12),
                ].map { Data($0) }
            )
        }
        let transport = try makeTransport()
        let rawCode = "DEV1-HTTPS-STREAM-0001"

        let response = try await transport.exchange(
            activationCode: CommercialActivationCode(rawCode)
        )

        XCTAssertEqual(response, .licenseDocument(document))
        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url, endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "application/octet-stream"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Accept"),
            CommercialActivationHTTPSTransport.licenseContentType
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Cache-Control"),
            "no-store"
        )
        XCTAssertEqual(recorder.body, Data(rawCode.utf8))
        XCTAssertFalse(request.url?.absoluteString.contains(rawCode) == true)
        XCTAssertFalse(
            request.allHTTPHeaderFields?.values.contains(where: {
                $0.contains(rawCode)
            }) == true
        )
    }

    func testStatusMappingNeverReturnsProviderBody() async throws {
        let cases: [(Int, CommercialActivationTransportResponse)] = [
            (400, .rejected(.codeRejected)),
            (401, .rejected(.codeRejected)),
            (404, .rejected(.codeRejected)),
            (429, .rejected(.rateLimited)),
            (500, .rejected(.serviceUnavailable)),
            (503, .rejected(.serviceUnavailable)),
        ]

        for (statusCode, expected) in cases {
            CommercialActivationHTTPSURLProtocol.install { _ in
                .init(
                    statusCode: statusCode,
                    headers: ["Content-Type": "text/plain"],
                    chunks: [Data("private provider error".utf8)]
                )
            }
            let response = try await makeTransport().exchange(
                activationCode: CommercialActivationCode(
                    "DEV1-HTTPS-STATUS-\(statusCode)"
                )
            )
            XCTAssertEqual(response, expected)
            XCTAssertFalse(String(reflecting: response).contains("private"))
        }
    }

    func testDeclaredAndStreamedOversizeResponsesFailBeforeReturningBytes() async throws {
        let maximum = CommercialLicenseDocumentStore.maximumDocumentBytes
        CommercialActivationHTTPSURLProtocol.install { _ in
            .init(
                statusCode: 200,
                headers: [
                    "Content-Type": CommercialActivationHTTPSTransport
                        .licenseContentType,
                    "Content-Length": "\(maximum + 1)",
                ],
                chunks: []
            )
        }
        await assertExchangeError(.responseTooLarge)

        CommercialActivationHTTPSURLProtocol.install { _ in
            .init(
                statusCode: 200,
                headers: [
                    "Content-Type": CommercialActivationHTTPSTransport
                        .licenseContentType,
                ],
                chunks: [
                    Data(repeating: 0x61, count: maximum),
                    Data([0x62]),
                ]
            )
        }
        await assertExchangeError(.responseTooLarge)
    }

    func testMaximumUnknownLengthResponseIsAcceptedExactlyAtBoundary() async throws {
        let document = Data(
            repeating: 0x61,
            count: CommercialLicenseDocumentStore.maximumDocumentBytes
        )
        CommercialActivationHTTPSURLProtocol.install { _ in
            .init(
                statusCode: 200,
                headers: [
                    "Content-Type": CommercialActivationHTTPSTransport
                        .licenseContentType,
                ],
                chunks: [document.prefix(17_000), document.dropFirst(17_000)]
                    .map { Data($0) }
            )
        }

        let response = try await makeTransport().exchange(
            activationCode: CommercialActivationCode(
                "DEV1-HTTPS-BOUNDARY-0001"
            )
        )
        XCTAssertEqual(
            response,
            .licenseDocument(document)
        )
    }

    func testEmptyWrongMediaTypeUnknownStatusAndMismatchedURLFailClosed() async {
        let fixtures = [
            CommercialActivationHTTPSURLProtocol.Fixture(
                statusCode: 200,
                headers: [
                    "Content-Type": CommercialActivationHTTPSTransport
                        .licenseContentType,
                ],
                chunks: []
            ),
            CommercialActivationHTTPSURLProtocol.Fixture(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                chunks: [Data("{}".utf8)]
            ),
            CommercialActivationHTTPSURLProtocol.Fixture(
                statusCode: 418,
                headers: ["Content-Type": "text/plain"],
                chunks: [Data("teapot".utf8)]
            ),
            CommercialActivationHTTPSURLProtocol.Fixture(
                responseURL: URL(
                    string: "https://other.devisland.app/v1/activate"
                ),
                statusCode: 200,
                headers: [
                    "Content-Type": CommercialActivationHTTPSTransport
                        .licenseContentType,
                ],
                chunks: [Data("signed".utf8)]
            ),
        ]

        for fixture in fixtures {
            CommercialActivationHTTPSURLProtocol.install { _ in fixture }
            await assertExchangeError(.invalidResponse)
        }
    }

    func testTransportErrorIsNormalizedAndCodeNeverAppearsInErrors() async {
        CommercialActivationHTTPSURLProtocol.install { _ in
            throw CommercialActivationHTTPSFixtureError(
                detail: "user@example.com DEV1-HTTPS-NETWORK-0001"
            )
        }
        do {
            _ = try await makeTransport().exchange(
                activationCode: CommercialActivationCode(
                    "DEV1-HTTPS-NETWORK-0001"
                )
            )
            XCTFail("Expected unavailable")
        } catch {
            XCTAssertEqual(
                error as? CommercialActivationHTTPSTransportError,
                .unavailable
            )
            XCTAssertFalse(String(reflecting: error).contains("user@example.com"))
            XCTAssertFalse(String(reflecting: error).contains("DEV1-HTTPS"))
        }
    }

    func testCallerCancellationStopsInFlightRequestAndStaysCancellation() async throws {
        let requestStarted = expectation(description: "request started")
        let requestStopped = expectation(description: "request stopped")
        CommercialActivationHTTPSURLProtocol.install(onStop: {
            requestStopped.fulfill()
        }) { _ in
            requestStarted.fulfill()
            return .init(
                statusCode: 200,
                headers: [
                    "Content-Type": CommercialActivationHTTPSTransport
                        .licenseContentType,
                ],
                chunks: [Data("late-license-document".utf8)],
                responseDelayMilliseconds: 1_000
            )
        }
        let transport = try makeTransport()
        let exchange = Task {
            try await transport.exchange(
                activationCode: CommercialActivationCode(
                    "DEV1-HTTPS-CANCEL-0001"
                )
            )
        }
        await fulfillment(of: [requestStarted], timeout: 1)

        exchange.cancel()
        await fulfillment(of: [requestStopped], timeout: 1)

        do {
            _ = try await exchange.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "Unexpected \(error)")
        }
    }

    private func makeTransport() throws -> CommercialActivationHTTPSTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CommercialActivationHTTPSURLProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(
            configuration: configuration,
            delegate: CommercialActivationHTTPSNoRedirectDelegate(),
            delegateQueue: nil
        )
        return try CommercialActivationHTTPSTransport(
            endpoint: endpoint,
            session: session
        )
    }

    private func assertExchangeError(
        _ expected: CommercialActivationHTTPSTransportError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await makeTransport().exchange(
                activationCode: CommercialActivationCode(
                    "DEV1-HTTPS-FAILURE-0001"
                )
            )
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? CommercialActivationHTTPSTransportError,
                expected,
                file: file,
                line: line
            )
        }
    }
}

private struct CommercialActivationHTTPSFixtureError: Error {
    let detail: String
}

private final class CommercialActivationHTTPSRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequest: URLRequest?
    private var storedBody: Data?

    var request: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedRequest
    }

    var body: Data? {
        lock.lock()
        defer { lock.unlock() }
        return storedBody
    }

    func record(_ request: URLRequest) {
        let body = request.httpBody ?? Self.read(stream: request.httpBodyStream)
        lock.lock()
        storedRequest = request
        storedBody = body
        lock.unlock()
    }

    private static func read(stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }

        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 256)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            body.append(buffer, count: count)
        }
        return body
    }
}

private final class CommercialActivationHTTPSURLProtocol:
    URLProtocol,
    @unchecked Sendable
{
    struct Fixture: Sendable {
        var responseURL: URL?
        let statusCode: Int
        let headers: [String: String]
        let chunks: [Data]
        let responseDelayMilliseconds: Int

        init(
            responseURL: URL? = nil,
            statusCode: Int,
            headers: [String: String],
            chunks: [Data],
            responseDelayMilliseconds: Int = 0
        ) {
            precondition((0...1_000).contains(responseDelayMilliseconds))
            self.responseURL = responseURL
            self.statusCode = statusCode
            self.headers = headers
            self.chunks = chunks
            self.responseDelayMilliseconds = responseDelayMilliseconds
        }
    }

    private static let state = State()
    private let deliveryLock = NSLock()
    private var stopped = false
    private var stopHandler: (@Sendable () -> Void)?

    static func install(
        onStop: (@Sendable () -> Void)? = nil,
        _ handler: @escaping @Sendable (URLRequest) throws -> Fixture
    ) {
        state.set(handler: handler, onStop: onStop)
    }

    static func reset() {
        state.set(handler: nil, onStop: nil)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let (fixture, configuredStopHandler) = try Self.state.fixture(
                for: request
            )
            deliveryLock.lock()
            let wasAlreadyStopped = stopped
            if wasAlreadyStopped {
                stopHandler = nil
            } else {
                stopHandler = configuredStopHandler
            }
            deliveryLock.unlock()
            if wasAlreadyStopped {
                configuredStopHandler?()
                return
            }
            if fixture.responseDelayMilliseconds == 0 {
                deliver(fixture)
            } else {
                DispatchQueue.global().asyncAfter(
                    deadline: .now()
                        + .milliseconds(fixture.responseDelayMilliseconds)
                ) { [weak self] in
                    self?.deliver(fixture)
                }
            }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        deliveryLock.lock()
        stopped = true
        let handler = stopHandler
        stopHandler = nil
        deliveryLock.unlock()
        handler?()
    }

    private func deliver(_ fixture: Fixture) {
        deliveryLock.lock()
        let shouldDeliver = !stopped
        deliveryLock.unlock()
        guard shouldDeliver else { return }

        do {
            let response = try XCTUnwrap(HTTPURLResponse(
                url: fixture.responseURL ?? request.url!,
                statusCode: fixture.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: fixture.headers
            ))
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            for chunk in fixture.chunks {
                client?.urlProtocol(self, didLoad: chunk)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private final class State: @unchecked Sendable {
        typealias Handler = @Sendable (URLRequest) throws -> Fixture

        private let lock = NSLock()
        private var handler: Handler?
        private var stopHandler: (@Sendable () -> Void)?

        func set(
            handler: Handler?,
            onStop: (@Sendable () -> Void)?
        ) {
            lock.lock()
            self.handler = handler
            stopHandler = onStop
            lock.unlock()
        }

        func fixture(
            for request: URLRequest
        ) throws -> (Fixture, (@Sendable () -> Void)?) {
            lock.lock()
            let handler = self.handler
            let stopHandler = self.stopHandler
            lock.unlock()
            guard let handler else {
                throw CommercialActivationHTTPSFixtureError(
                    detail: "missing fixture"
                )
            }
            return (try handler(request), stopHandler)
        }
    }
}
