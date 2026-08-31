import CryptoKit
import Darwin
import Foundation
import Hummingbird
import HTTPTypes
import XCTest
@testable import IslandCore

/// Exercises the provider-neutral commercial core through a real loopback
/// HTTP connection without selecting a seller, provider protocol, production
/// endpoint, trust key, or policy. The shipping App never links this test
/// target and continues to instantiate no commercial service.
final class CommercialActivationSandboxTests: XCTestCase {
    private let keyID = "sandbox-license-key"
    private let nowSeconds: Int64 = 1_788_163_260
    private let licenseID = "e3433e35-804c-445d-ab75-9d2e90d7af54"

    func testSandboxTransportAcceptsOnlyExactNumericLoopbackEndpoint() throws {
        XCTAssertNoThrow(
            try CommercialActivationLoopbackTransport(
                endpoint: XCTUnwrap(
                    URL(string: "http://127.0.0.1:49152/v1/activate")
                )
            )
        )

        for rawURL in [
            "http://127.0.0.1/v1/activate",
            "http://127.0.0.1:0/v1/activate",
            "https://127.0.0.1:49152/v1/activate",
            "http://localhost:49152/v1/activate",
            "http://192.0.2.1:49152/v1/activate",
            "http://user@127.0.0.1:49152/v1/activate",
            "http://127.0.0.1:49152/other",
            "http://127.0.0.1:49152/v1/activate?code=secret",
            "http://127.0.0.1:49152/v1/activate#fragment",
        ] {
            let endpoint = try XCTUnwrap(URL(string: rawURL))
            XCTAssertThrowsError(
                try CommercialActivationLoopbackTransport(endpoint: endpoint),
                rawURL
            ) { error in
                XCTAssertEqual(
                    error as? CommercialActivationSandboxError,
                    .invalidEndpoint,
                    rawURL
                )
            }
        }
    }

    func testRealLoopbackRoundTripVerifiesAndStoresSignedLicense() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let verifier = try makeVerifier(privateKey: privateKey)
        let document = try makeDocument(privateKey: privateKey)
        let recorder = CommercialActivationSandboxRecorder()
        let server = try CommercialActivationLoopbackServer(
            responseBody: document,
            recorder: recorder
        )
        try await server.start()
        defer { server.cancel() }

        let storage = InMemoryCommercialLicenseDocumentStorage()
        let store = CommercialLicenseDocumentStore(backend: storage)
        let transport = try CommercialActivationLoopbackTransport(
            endpoint: server.activationEndpoint
        )
        let evaluationDate = Date(
            timeIntervalSince1970: TimeInterval(nowSeconds)
        )
        let service = CommercialLicenseActivationService(
            verifier: verifier,
            store: store,
            transport: transport,
            evaluationClock: { evaluationDate }
        )
        let code = try CommercialActivationCode("DEV1-SANDBOX-HTTP-0001")
        let expectedCodeDigest = code.withUnsafeUTF8Bytes {
            Data(SHA256.hash(data: Data($0)))
        }

        let outcome = await service.activate(code: code)

        guard case .activated(let license) = outcome else {
            await server.stop()
            return XCTFail("Expected sandbox activation, got \(outcome)")
        }
        XCTAssertEqual(license.licenseID.uuidString.lowercased(), licenseID)
        XCTAssertEqual(license.generation, 1)
        XCTAssertEqual(license.tier, "pro")
        XCTAssertEqual(license.features, ["agent-unlimited", "updates"])
        XCTAssertEqual(
            try store.evaluateStored(using: verifier, now: evaluationDate),
            .valid(license)
        )

        let recordedRequest = await recorder.request
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v1/activate")
        XCTAssertEqual(request.bodyByteCount, 22)
        XCTAssertEqual(request.bodySHA256, expectedCodeDigest)
        XCTAssertEqual(request.contentType, "application/octet-stream")

        await server.stop()
    }

    func testUnsignedLoopbackResponseFailsClosedWithoutStorage() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let verifier = try makeVerifier(privateKey: privateKey)
        let recorder = CommercialActivationSandboxRecorder()
        let server = try CommercialActivationLoopbackServer(
            responseBody: Data("unsigned-provider-response".utf8),
            recorder: recorder
        )
        try await server.start()
        defer { server.cancel() }

        let storage = InMemoryCommercialLicenseDocumentStorage()
        let store = CommercialLicenseDocumentStore(backend: storage)
        let transport = try CommercialActivationLoopbackTransport(
            endpoint: server.activationEndpoint
        )
        let evaluationDate = Date(
            timeIntervalSince1970: TimeInterval(nowSeconds)
        )
        let service = CommercialLicenseActivationService(
            verifier: verifier,
            store: store,
            transport: transport,
            evaluationClock: { evaluationDate }
        )

        let outcome = await service.activate(
            code: try CommercialActivationCode("DEV1-SANDBOX-HTTP-0002")
        )

        XCTAssertEqual(outcome, .failed(.licenseRejected))
        XCTAssertEqual(
            try store.evaluateStored(using: verifier, now: evaluationDate),
            .missingDocument
        )
        let recordedRequest = await recorder.request
        XCTAssertEqual(recordedRequest?.bodyByteCount, 22)

        await server.stop()
    }

    func testRealLoopbackStatusMappingIsLowCardinalityAndNeverStoresBodies() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let verifier = try makeVerifier(privateKey: privateKey)
        let cases: [(statusCode: Int, expected: CommercialLicenseActivationOutcome)] = [
            (400, .rejected(.codeRejected)),
            (401, .rejected(.codeRejected)),
            (404, .rejected(.codeRejected)),
            (429, .rejected(.rateLimited)),
            (500, .rejected(.serviceUnavailable)),
            (503, .rejected(.serviceUnavailable)),
        ]

        for testCase in cases {
            let recorder = CommercialActivationSandboxRecorder()
            let server = try CommercialActivationLoopbackServer(
                statusCode: testCase.statusCode,
                responseBody: Data("provider-private-error-body".utf8),
                recorder: recorder
            )
            try await server.start()

            let storage = InMemoryCommercialLicenseDocumentStorage()
            let store = CommercialLicenseDocumentStore(backend: storage)
            let service = CommercialLicenseActivationService(
                verifier: verifier,
                store: store,
                transport: try CommercialActivationLoopbackTransport(
                    endpoint: server.activationEndpoint
                ),
                evaluationClock: {
                    Date(timeIntervalSince1970: TimeInterval(self.nowSeconds))
                }
            )

            let outcome = await service.activate(
                code: try CommercialActivationCode(
                    "DEV1-SANDBOX-STATUS-\(testCase.statusCode)"
                )
            )
            let recordedRequest = await recorder.request
            await server.stop()

            XCTAssertEqual(outcome, testCase.expected, "HTTP \(testCase.statusCode)")
            XCTAssertFalse(
                String(describing: outcome).contains("provider-private-error-body")
            )
            XCTAssertEqual(recordedRequest?.path, "/v1/activate")
            XCTAssertEqual(
                try store.evaluateStored(
                    using: verifier,
                    now: Date(timeIntervalSince1970: TimeInterval(nowSeconds))
                ),
                .missingDocument,
                "HTTP \(testCase.statusCode)"
            )
        }
    }

    func testRedirectUnknownStatusAndOversizedBodyFailClosedWithoutStorage() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let verifier = try makeVerifier(privateKey: privateKey)
        let cases: [(
            statusCode: Int,
            responseBody: Data,
            redirectPath: String?
        )] = [
            (302, Data("redirect-attempt".utf8), "/redirect-target"),
            (418, Data("unknown-status".utf8), nil),
            (
                200,
                Data(
                    repeating: 0x61,
                    count: CommercialLicenseDocumentStore.maximumDocumentBytes + 1
                ),
                nil
            ),
        ]

        for testCase in cases {
            let recorder = CommercialActivationSandboxRecorder()
            let server = try CommercialActivationLoopbackServer(
                statusCode: testCase.statusCode,
                responseBody: testCase.responseBody,
                redirectPath: testCase.redirectPath,
                recorder: recorder
            )
            try await server.start()

            let storage = InMemoryCommercialLicenseDocumentStorage()
            let store = CommercialLicenseDocumentStore(backend: storage)
            let service = CommercialLicenseActivationService(
                verifier: verifier,
                store: store,
                transport: try CommercialActivationLoopbackTransport(
                    endpoint: server.activationEndpoint
                ),
                evaluationClock: {
                    Date(timeIntervalSince1970: TimeInterval(self.nowSeconds))
                }
            )

            let outcome = await service.activate(
                code: try CommercialActivationCode(
                    "DEV1-SANDBOX-FAIL-\(testCase.statusCode)"
                )
            )
            let redirectTargetRequestCount = await recorder.redirectTargetRequestCount
            await server.stop()

            XCTAssertEqual(
                outcome,
                .failed(.transportUnavailable),
                "HTTP \(testCase.statusCode)"
            )
            XCTAssertEqual(redirectTargetRequestCount, 0)
            XCTAssertEqual(
                try store.evaluateStored(
                    using: verifier,
                    now: Date(timeIntervalSince1970: TimeInterval(nowSeconds))
                ),
                .missingDocument,
                "HTTP \(testCase.statusCode)"
            )
        }
    }

    func testExplicitCancelRejectsCancellationInsensitiveRealHTTPResponse() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let verifier = try makeVerifier(privateKey: privateKey)
        let recorder = CommercialActivationSandboxRecorder()
        let server = try CommercialActivationLoopbackServer(
            responseBody: try makeDocument(privateKey: privateKey),
            responseDelayMilliseconds: 200,
            recorder: recorder
        )
        try await server.start()
        defer { server.cancel() }

        let storage = InMemoryCommercialLicenseDocumentStorage()
        let store = CommercialLicenseDocumentStore(backend: storage)
        let service = CommercialLicenseActivationService(
            verifier: verifier,
            store: store,
            transport: try CommercialActivationLoopbackTransport(
                endpoint: server.activationEndpoint,
                ignoresCallerCancellation: true
            ),
            evaluationClock: {
                Date(timeIntervalSince1970: TimeInterval(self.nowSeconds))
            }
        )
        let activation = Task {
            await service.activate(
                code: try! CommercialActivationCode("DEV1-SANDBOX-CANCEL-0001")
            )
        }

        let requestArrived = await waitForRequestCount(1, recorder: recorder)
        XCTAssertTrue(requestArrived)
        let didCancel = await service.cancelPendingActivation()
        let outcome = await activation.value
        let responseReturned = await waitForResponseCount(1, recorder: recorder)

        XCTAssertTrue(didCancel)
        XCTAssertTrue(responseReturned)
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(
            try store.evaluateStored(
                using: verifier,
                now: Date(timeIntervalSince1970: TimeInterval(nowSeconds))
            ),
            .missingDocument
        )

        await server.stop()
    }

    func testLatestOperationWinsWhenSupersededRealHTTPResponseArrives() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let verifier = try makeVerifier(privateKey: privateKey)
        let recorder = CommercialActivationSandboxRecorder()
        let server = try CommercialActivationLoopbackServer(
            responseBody: try makeDocument(privateKey: privateKey),
            responseDelayMilliseconds: 200,
            recorder: recorder
        )
        try await server.start()
        defer { server.cancel() }

        let storage = InMemoryCommercialLicenseDocumentStorage()
        let store = CommercialLicenseDocumentStore(backend: storage)
        let service = CommercialLicenseActivationService(
            verifier: verifier,
            store: store,
            transport: try CommercialActivationLoopbackTransport(
                endpoint: server.activationEndpoint,
                ignoresCallerCancellation: true
            ),
            evaluationClock: {
                Date(timeIntervalSince1970: TimeInterval(self.nowSeconds))
            }
        )
        let firstActivation = Task {
            await service.activate(
                code: try! CommercialActivationCode("DEV1-SANDBOX-OLDER-0001")
            )
        }
        let firstRequestArrived = await waitForRequestCount(1, recorder: recorder)
        XCTAssertTrue(firstRequestArrived)

        let secondActivation = Task {
            await service.activate(
                code: try! CommercialActivationCode("DEV1-SANDBOX-NEWER-0002")
            )
        }
        let bothRequestsArrived = await waitForRequestCount(2, recorder: recorder)
        XCTAssertTrue(bothRequestsArrived)

        let firstOutcome = await firstActivation.value
        let secondOutcome = await secondActivation.value
        let bothResponsesReturned = await waitForResponseCount(2, recorder: recorder)

        XCTAssertTrue(bothResponsesReturned)
        XCTAssertEqual(firstOutcome, .superseded)
        guard case .activated(let license) = secondOutcome else {
            await server.stop()
            return XCTFail("Expected latest real-HTTP activation, got \(secondOutcome)")
        }
        XCTAssertEqual(license.licenseID.uuidString.lowercased(), licenseID)
        XCTAssertEqual(
            try store.evaluateStored(
                using: verifier,
                now: Date(timeIntervalSince1970: TimeInterval(nowSeconds))
            ),
            .valid(license)
        )

        await server.stop()
    }

    func testPreCancelledActivationCannotSupersedeOrSendRealHTTPRequest() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let verifier = try makeVerifier(privateKey: privateKey)
        let recorder = CommercialActivationSandboxRecorder()
        let server = try CommercialActivationLoopbackServer(
            responseBody: try makeDocument(privateKey: privateKey),
            responseDelayMilliseconds: 200,
            recorder: recorder
        )
        try await server.start()
        defer { server.cancel() }

        let storage = InMemoryCommercialLicenseDocumentStorage()
        let store = CommercialLicenseDocumentStore(backend: storage)
        let service = CommercialLicenseActivationService(
            verifier: verifier,
            store: store,
            transport: try CommercialActivationLoopbackTransport(
                endpoint: server.activationEndpoint,
                ignoresCallerCancellation: true
            ),
            evaluationClock: {
                Date(timeIntervalSince1970: TimeInterval(self.nowSeconds))
            }
        )

        let firstActivation = Task {
            await service.activate(
                code: try! CommercialActivationCode("DEV1-SANDBOX-OWNER-0001")
            )
        }
        let firstRequestArrived = await waitForRequestCount(1, recorder: recorder)
        XCTAssertTrue(firstRequestArrived)

        let preCancelledActivation = Task {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return await service.activate(
                code: try! CommercialActivationCode("DEV1-SANDBOX-CANCELLED-0002")
            )
        }
        let cancelledOutcome = await preCancelledActivation.value
        let requestCountAfterCancellation = await recorder.requestCount

        XCTAssertEqual(cancelledOutcome, .cancelled)
        XCTAssertEqual(requestCountAfterCancellation, 1)

        let firstOutcome = await firstActivation.value
        let firstResponseReturned = await waitForResponseCount(1, recorder: recorder)
        let finalRequestCount = await recorder.requestCount
        let finalResponseCount = await recorder.responseCount

        XCTAssertTrue(firstResponseReturned)
        XCTAssertEqual(finalRequestCount, 1)
        XCTAssertEqual(finalResponseCount, 1)
        guard case .activated(let license) = firstOutcome else {
            await server.stop()
            return XCTFail("Expected original real-HTTP activation, got \(firstOutcome)")
        }
        XCTAssertEqual(license.licenseID.uuidString.lowercased(), licenseID)
        XCTAssertEqual(
            try store.evaluateStored(
                using: verifier,
                now: Date(timeIntervalSince1970: TimeInterval(nowSeconds))
            ),
            .valid(license)
        )

        await server.stop()
    }

    private func waitForRequestCount(
        _ expectedCount: Int,
        recorder: CommercialActivationSandboxRecorder
    ) async -> Bool {
        for _ in 0..<100 {
            if await recorder.requestCount >= expectedCount { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func waitForResponseCount(
        _ expectedCount: Int,
        recorder: CommercialActivationSandboxRecorder
    ) async -> Bool {
        for _ in 0..<100 {
            if await recorder.responseCount >= expectedCount { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func makeVerifier(
        privateKey: Curve25519.Signing.PrivateKey
    ) throws -> CommercialLicenseVerifier {
        try CommercialLicenseVerifier(trustedKeys: [
            TrustedCommercialLicenseKey(
                id: keyID,
                rawRepresentation: privateKey.publicKey.rawRepresentation
            )
        ])
    }

    private func makeDocument(
        privateKey: Curve25519.Signing.PrivateKey
    ) throws -> Data {
        let payload = try JSONSerialization.data(
            withJSONObject: [
                "version": 1,
                "issuer": CommercialLicenseVerifier.expectedIssuer,
                "productID": CommercialLicenseVerifier.expectedProductID,
                "licenseID": licenseID,
                "generation": 1,
                "issuedAt": nowSeconds - 60,
                "notBefore": nowSeconds,
                "expiresAt": NSNull(),
                "tier": "pro",
                "features": ["agent-unlimited", "updates"],
            ],
            options: [.sortedKeys]
        )
        let signature = try privateKey.signature(
            for: CommercialLicenseVerifier.signingMessage(
                keyID: keyID,
                payload: payload
            )
        )
        return Data(
            [
                CommercialLicenseVerifier.envelopeHeader,
                keyID,
                payload.base64EncodedString(),
                signature.base64EncodedString(),
            ]
            .joined(separator: "\n")
            .utf8
        )
    }
}

private enum CommercialActivationSandboxError: Error, Equatable {
    case invalidEndpoint
    case portUnavailable
    case readinessTimedOut
    case invalidResponse
    case responseTooLarge
}

/// Test-only HTTP transport. It deliberately accepts only a numeric loopback
/// endpoint and has no redirect, cookie, cache, proxy, retry, account, device,
/// or payment behavior. A future provider transport requires an independent
/// reviewed protocol and must not copy this fixture into the shipping App.
private struct CommercialActivationLoopbackTransport:
    CommercialActivationTransport,
    @unchecked Sendable
{
    private let endpoint: URL
    private let session: URLSession
    /// Test-only attack mode: keep the bounded URLSession request alive after
    /// the caller task is cancelled so the activation actor must reject a
    /// genuinely returned late response by operation ownership, not merely
    /// rely on cooperative network cancellation.
    private let ignoresCallerCancellation: Bool

    init(
        endpoint: URL,
        ignoresCallerCancellation: Bool = false
    ) throws {
        guard endpoint.scheme == "http",
              endpoint.host == "127.0.0.1",
              let port = endpoint.port,
              port > 0,
              endpoint.path == "/v1/activate",
              endpoint.user == nil,
              endpoint.password == nil,
              endpoint.query == nil,
              endpoint.fragment == nil else {
            throw CommercialActivationSandboxError.invalidEndpoint
        }
        self.endpoint = endpoint
        self.ignoresCallerCancellation = ignoresCallerCancellation

        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 2
        session = URLSession(
            configuration: configuration,
            delegate: CommercialActivationNoRedirectDelegate(),
            delegateQueue: nil
        )
    }

    func exchange(
        activationCode: CommercialActivationCode
    ) async throws -> CommercialActivationTransportResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 2
        request.setValue(
            "application/octet-stream",
            forHTTPHeaderField: "Content-Type"
        )

        var body = activationCode.withUnsafeUTF8Bytes { Data($0) }
        defer {
            body.resetBytes(in: body.startIndex..<body.endIndex)
        }
        request.httpBody = body

        let responseBody: Data
        let response: URLResponse
        if ignoresCallerCancellation {
            let requestTask = Task.detached {
                try await session.data(for: request)
            }
            (responseBody, response) = try await requestTask.value
        } else {
            (responseBody, response) = try await session.data(for: request)
        }
        guard let response = response as? HTTPURLResponse,
              response.url == endpoint else {
            throw CommercialActivationSandboxError.invalidResponse
        }
        guard responseBody.count <= CommercialLicenseDocumentStore.maximumDocumentBytes else {
            throw CommercialActivationSandboxError.responseTooLarge
        }

        switch response.statusCode {
        case 200:
            return .licenseDocument(responseBody)
        case 400, 401, 404:
            return .rejected(.codeRejected)
        case 429:
            return .rejected(.rateLimited)
        case 500...599:
            return .rejected(.serviceUnavailable)
        default:
            throw CommercialActivationSandboxError.invalidResponse
        }
    }
}

private final class CommercialActivationNoRedirectDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable
{
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

private actor CommercialActivationSandboxRecorder {
    struct Request: Equatable, Sendable {
        let method: String
        let path: String
        let contentType: String?
        let bodyByteCount: Int
        let bodySHA256: Data
    }

    private(set) var request: Request?
    private(set) var requestCount = 0
    private(set) var responseCount = 0
    private(set) var redirectTargetRequestCount = 0

    func record(
        method: String,
        path: String,
        contentType: String?,
        body: Data
    ) {
        requestCount += 1
        request = Request(
            method: method,
            path: path,
            contentType: contentType,
            bodyByteCount: body.count,
            bodySHA256: Data(SHA256.hash(data: body))
        )
    }

    func recordRedirectTargetRequest() {
        redirectTargetRequestCount += 1
    }

    func recordResponse() {
        responseCount += 1
    }
}

private final class CommercialActivationLoopbackServer: @unchecked Sendable {
    let activationEndpoint: URL

    private let port: Int
    private let readinessToken = UUID().uuidString.lowercased()
    private let statusCode: Int
    private let responseBody: Data
    private let redirectPath: String?
    private let responseDelayMilliseconds: Int
    private let recorder: CommercialActivationSandboxRecorder
    private var serverTask: Task<Void, Never>?

    init(
        statusCode: Int = 200,
        responseBody: Data,
        redirectPath: String? = nil,
        responseDelayMilliseconds: Int = 0,
        recorder: CommercialActivationSandboxRecorder
    ) throws {
        guard let port = Self.availableLoopbackPort(),
              let endpoint = URL(
                string: "http://127.0.0.1:\(port)/v1/activate"
              ) else {
            throw CommercialActivationSandboxError.portUnavailable
        }
        self.port = port
        activationEndpoint = endpoint
        self.statusCode = statusCode
        self.responseBody = responseBody
        self.redirectPath = redirectPath
        precondition((0...2_000).contains(responseDelayMilliseconds))
        self.responseDelayMilliseconds = responseDelayMilliseconds
        self.recorder = recorder
    }

    func start() async throws {
        precondition(serverTask == nil)
        let router = Router()
        let readinessToken = self.readinessToken
        let statusCode = self.statusCode
        let responseText = String(decoding: responseBody, as: UTF8.self)
        let redirectPath = self.redirectPath
        let responseDelayMilliseconds = self.responseDelayMilliseconds
        let port = self.port
        let recorder = self.recorder

        router.get(RouterPath("/_sandbox/ready/\(readinessToken)")) {
            _, _ -> String in
            readinessToken
        }
        router.post("/v1/activate") { request, _ -> Response in
            let buffer = try await request.body.collect(
                upTo: CommercialActivationCode.maximumUTF8Bytes
            )
            let body = Data(buffer.readableBytesView)
            let contentTypeName = HTTPField.Name("Content-Type")
            await recorder.record(
                method: request.method.rawValue,
                path: request.uri.path,
                contentType: contentTypeName.flatMap {
                    request.headers[$0]
                },
                body: body
            )
            if responseDelayMilliseconds > 0 {
                try await Task.sleep(
                    for: .milliseconds(responseDelayMilliseconds)
                )
            }
            await recorder.recordResponse()
            var headers = HTTPFields()
            if let redirectPath {
                let locationName = HTTPField.Name("Location")!
                headers[locationName] = "http://127.0.0.1:\(port)\(redirectPath)"
            }
            return Response(
                status: HTTPResponse.Status(code: statusCode),
                headers: headers,
                body: .init(byteBuffer: ByteBuffer(string: responseText))
            )
        }
        router.get("/redirect-target") { _, _ -> HTTPResponse.Status in
            await recorder.recordRedirectTargetRequest()
            return .ok
        }

        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname("127.0.0.1", port: port)
            ),
            logger: IslandLogger.silentFramework
        )
        serverTask = Task {
            do {
                try await app.run()
            } catch is CancellationError {
                // Normal bounded test shutdown.
            } catch {
                // Readiness or the client request will fail with a bounded,
                // low-cardinality test error; do not echo framework details.
            }
        }

        guard await waitUntilReady() else {
            cancel()
            throw CommercialActivationSandboxError.readinessTimedOut
        }
    }

    func cancel() {
        serverTask?.cancel()
    }

    func stop() async {
        guard let serverTask else { return }
        serverTask.cancel()
        await serverTask.value
        self.serverTask = nil
    }

    private func waitUntilReady() async -> Bool {
        guard let url = URL(
            string: "http://127.0.0.1:\(port)/_sandbox/ready/\(readinessToken)"
        ) else { return false }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 0.2
        configuration.timeoutIntervalForResource = 0.2
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        for _ in 0..<100 {
            if Task.isCancelled { return false }
            if let (data, response) = try? await session.data(from: url),
               (response as? HTTPURLResponse)?.statusCode == 200,
               data == Data(readinessToken.utf8) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private static func availableLoopbackPort() -> Int? {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let didBind = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(
                    descriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        } == 0
        guard didBind else { return nil }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let didRead = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        } == 0
        guard didRead else { return nil }
        return Int(UInt16(bigEndian: address.sin_port))
    }
}
