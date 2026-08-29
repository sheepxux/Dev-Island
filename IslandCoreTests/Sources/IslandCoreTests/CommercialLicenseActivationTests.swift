import CryptoKit
import Foundation
import XCTest
@testable import IslandCore

final class CommercialLicenseActivationTests: XCTestCase {
    private let keyID = "license-activation-test"
    private let nowSeconds: Int64 = 1_788_163_260
    private let firstLicenseID = "f4c24d5b-ff4a-40f8-9315-e489b0cfe2d8"
    private let secondLicenseID = "6aeb8ff8-51d1-4b25-8d87-ed83eac7409b"

    private var store: CommercialLicenseDocumentStore!
    private var privateKey: Curve25519.Signing.PrivateKey!
    private var verifier: CommercialLicenseVerifier!

    override func setUpWithError() throws {
        store = CommercialLicenseDocumentStore(
            service: "app.devisland.Island.activation-tests.\(UUID().uuidString.lowercased())",
            account: "commercial-license-activation-test"
        )
        try? store.delete()

        privateKey = Curve25519.Signing.PrivateKey()
        verifier = try CommercialLicenseVerifier(
            trustedKeys: [
                TrustedCommercialLicenseKey(
                    id: keyID,
                    rawRepresentation: privateKey.publicKey.rawRepresentation
                )
            ]
        )
    }

    override func tearDownWithError() throws {
        try? store.delete()
        verifier = nil
        privateKey = nil
        store = nil
    }

    func testActivationCodeUsesBoundedAlphabetAndAlwaysRedacts() throws {
        let rawCode = "DEV1-2345-6789-ABCD"
        let code = try CommercialActivationCode(rawCode)

        XCTAssertEqual(String(describing: code), "<redacted activation code>")
        XCTAssertEqual(String(reflecting: code), "<redacted activation code>")
        XCTAssertFalse(String(describing: code).contains(rawCode))

        XCTAssertNoThrow(try CommercialActivationCode(String(repeating: "a", count: 16)))
        XCTAssertNoThrow(try CommercialActivationCode(String(repeating: "Z", count: 128)))
        XCTAssertThrowsError(
            try CommercialActivationCode(String(repeating: "a", count: 15))
        ) { error in
            XCTAssertEqual(error as? CommercialActivationCodeError, .invalidLength)
        }
        XCTAssertThrowsError(
            try CommercialActivationCode(String(repeating: "a", count: 129))
        ) { error in
            XCTAssertEqual(error as? CommercialActivationCodeError, .invalidLength)
        }
        for invalid in [
            "DEV1 2345 6789 ABCD",
            "DEV1\n2345-6789-ABCD",
            "DEV1/2345/6789/ABCD",
            "DEV1-2345-6789-🍎",
        ] {
            XCTAssertThrowsError(try CommercialActivationCode(invalid)) { error in
                XCTAssertEqual(
                    error as? CommercialActivationCodeError,
                    .invalidCharacters
                )
            }
        }

        let document = Data("signed-document-secret".utf8)
        XCTAssertFalse(
            String(describing: CommercialActivationTransportResponse
                .licenseDocument(document))
                .contains("signed-document-secret")
        )
    }

    func testActivationCodeUsesSharedDedicatedStorageAndSecureErase() throws {
        let rawCode = "DEV1-2345-6789-ABCD"
        let code = try CommercialActivationCode(rawCode)
        let copiedCode = code

        let firstAddress = code.withUnsafeUTF8Bytes { buffer in
            UInt(bitPattern: buffer.baseAddress!)
        }
        let secondAddress = copiedCode.withUnsafeUTF8Bytes { buffer in
            UInt(bitPattern: buffer.baseAddress!)
        }
        let scopedValue = copiedCode.withUnsafeUTF8Bytes { buffer in
            String(decoding: buffer, as: UTF8.self)
        }

        XCTAssertEqual(firstAddress, secondAddress)
        XCTAssertEqual(scopedValue, rawCode)

        var scratch = Array(rawCode.utf8)
        let didErase = scratch.withUnsafeMutableBufferPointer {
            CommercialActivationSecretStorage.secureErase($0)
        }
        XCTAssertTrue(didErase)
        XCTAssertEqual(scratch, Array(repeating: 0, count: rawCode.utf8.count))
    }

    func testDisabledVerifierRejectsBeforeCallingTransport() async throws {
        let transport = ImmediateActivationTransport(
            result: .success(.rejected(.codeRejected))
        )
        let service = CommercialLicenseActivationService(
            verifier: CommercialLicenseVerifier(),
            store: store,
            transport: transport
        )

        let outcome = await service.activate(code: activationCode("disabled"))
        let requestCount = await transport.requestCount

        XCTAssertEqual(outcome, .failed(.commercialModeDisabled))
        XCTAssertEqual(requestCount, 0)
    }

    func testSuccessfulActivationVerifiesAndRoundTripsThroughKeychain() async throws {
        let document = try makeDocument(licenseID: firstLicenseID)
        let transport = ImmediateActivationTransport(
            result: .success(.licenseDocument(document))
        )
        let service = makeService(transport: transport)

        let outcome = await service.activate(code: activationCode("success"))

        guard case .activated(let activatedLicense) = outcome else {
            return XCTFail("Expected activation, got \(outcome)")
        }
        XCTAssertEqual(
            activatedLicense.licenseID.uuidString.lowercased(),
            firstLicenseID
        )
        XCTAssertEqual(
            try store.evaluateStored(using: verifier, now: evaluationDate),
            .valid(activatedLicense)
        )
    }

    func testTamperedAndOversizedResponsesNeverReplaceValidDocument() async throws {
        let originalDocument = try makeDocument(licenseID: firstLicenseID)
        let originalEvaluation = try store.importDocument(
            originalDocument,
            using: verifier,
            now: evaluationDate
        )
        let tamperedDocument = try makeTamperedDocument(
            from: makeDocument(licenseID: secondLicenseID)
        )
        let oversizedDocument = Data(
            repeating: 0x61,
            count: CommercialLicenseDocumentStore.maximumDocumentBytes + 1
        )
        let transport = QueuedActivationTransport(responses: [
            .licenseDocument(tamperedDocument),
            .licenseDocument(oversizedDocument),
        ])
        let service = makeService(transport: transport)

        let tamperedOutcome = await service.activate(code: activationCode("tampered"))
        XCTAssertEqual(tamperedOutcome, .failed(.licenseRejected))
        XCTAssertEqual(
            try store.evaluateStored(using: verifier, now: evaluationDate),
            originalEvaluation
        )

        let oversizedOutcome = await service.activate(code: activationCode("oversized"))
        XCTAssertEqual(oversizedOutcome, .failed(.licenseRejected))
        XCTAssertEqual(
            try store.evaluateStored(using: verifier, now: evaluationDate),
            originalEvaluation
        )
    }

    func testTransportErrorsAreNormalizedWithoutLeakingRawDetails() async throws {
        let rawError = ActivationTransportFixtureError(
            description: "upstream user@example.com DEV1-SECRET-CODE"
        )
        let transport = ImmediateActivationTransport(result: .failure(rawError))
        let service = makeService(transport: transport)

        let outcome = await service.activate(code: activationCode("transport-error"))
        let rendered = String(reflecting: outcome)

        XCTAssertEqual(outcome, .failed(.transportUnavailable))
        XCTAssertFalse(rendered.contains("user@example.com"))
        XCTAssertFalse(rendered.contains("DEV1-SECRET-CODE"))
        XCTAssertFalse(rendered.contains(rawError.description))
    }

    func testLatestConcurrentActivationIsTheOnlyDocumentSaved() async throws {
        let firstCode = activationCode("first-operation")
        let secondCode = activationCode("second-operation")
        let firstDocument = try makeDocument(licenseID: firstLicenseID)
        let secondDocument = try makeDocument(licenseID: secondLicenseID)
        let transport = ControlledActivationTransport()
        let service = makeService(transport: transport)

        let first = Task {
            await service.activate(code: firstCode)
        }
        try await waitUntil { await transport.requestCount == 1 }

        let second = Task {
            await service.activate(code: secondCode)
        }
        try await waitUntil { await transport.requestCount == 2 }

        await transport.complete(
            code: secondCode,
            with: .licenseDocument(secondDocument)
        )
        let secondOutcome = await second.value

        await transport.complete(
            code: firstCode,
            with: .licenseDocument(firstDocument)
        )
        let firstOutcome = await first.value

        XCTAssertEqual(firstOutcome, .superseded)
        guard case .activated(let latestLicense) = secondOutcome else {
            return XCTFail("Expected latest activation, got \(secondOutcome)")
        }
        XCTAssertEqual(
            latestLicense.licenseID.uuidString.lowercased(),
            secondLicenseID
        )
        XCTAssertEqual(
            try store.evaluateStored(using: verifier, now: evaluationDate),
            .valid(latestLicense)
        )
    }

    func testResponseIsEvaluatedAtCommitTimeNotRequestStart() async throws {
        let code = activationCode("expires-in-flight")
        let document = try makeDocument(
            licenseID: firstLicenseID,
            expiresAt: nowSeconds + 1
        )
        let transport = ControlledActivationTransport()
        let clock = CommercialActivationTestClock(evaluationDate)
        let service = makeService(
            transport: transport,
            evaluationClock: { clock.currentDate }
        )

        let activation = Task {
            await service.activate(code: code)
        }
        try await waitUntil { await transport.requestCount == 1 }

        clock.set(
            Date(timeIntervalSince1970: TimeInterval(nowSeconds + 1))
        )
        await transport.complete(code: code, with: .licenseDocument(document))
        let outcome = await activation.value

        XCTAssertEqual(outcome, .failed(.licenseRejected))
        XCTAssertEqual(
            try store.evaluateStored(using: verifier, now: evaluationDate),
            .missingDocument
        )
    }

    func testSignedRollbackIsRejectedWithoutReplacingCurrentLicense() async throws {
        let currentDocument = try makeDocument(
            licenseID: firstLicenseID,
            generation: 2
        )
        let currentEvaluation = try store.importDocument(
            currentDocument,
            using: verifier,
            now: evaluationDate
        )
        let staleDocument = try makeDocument(
            licenseID: firstLicenseID,
            generation: 1
        )
        let service = makeService(
            transport: ImmediateActivationTransport(
                result: .success(.licenseDocument(staleDocument))
            )
        )

        let outcome = await service.activate(
            code: activationCode("stale-license")
        )
        XCTAssertEqual(outcome, .failed(.licenseRejected))
        XCTAssertEqual(
            try store.evaluateStored(using: verifier, now: evaluationDate),
            currentEvaluation
        )
    }

    func testExplicitCancellationRejectsLateTransportResponse() async throws {
        let code = activationCode("cancelled-operation")
        let document = try makeDocument(licenseID: firstLicenseID)
        let transport = ControlledActivationTransport()
        let service = makeService(transport: transport)

        let activation = Task {
            await service.activate(code: code)
        }
        try await waitUntil { await transport.requestCount == 1 }

        let didCancel = await service.cancelPendingActivation()
        XCTAssertTrue(didCancel)
        await transport.complete(code: code, with: .licenseDocument(document))

        let outcome = await activation.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(
            try store.evaluateStored(using: verifier, now: evaluationDate),
            .missingDocument
        )
        let didCancelAgain = await service.cancelPendingActivation()
        XCTAssertFalse(didCancelAgain)
    }

    private var evaluationDate: Date {
        Date(timeIntervalSince1970: TimeInterval(nowSeconds))
    }

    private func activationCode(_ suffix: String) -> CommercialActivationCode {
        try! CommercialActivationCode("DEV1-\(suffix)-0000")
    }

    private func makeService(
        transport: any CommercialActivationTransport,
        evaluationClock: (@Sendable () -> Date)? = nil
    ) -> CommercialLicenseActivationService {
        let fixedDate = evaluationDate
        return CommercialLicenseActivationService(
            verifier: verifier,
            store: store,
            transport: transport,
            evaluationClock: evaluationClock ?? { fixedDate }
        )
    }

    private func makeDocument(
        licenseID: String,
        generation: Int64 = 1,
        issuedAt: Int64? = nil,
        expiresAt: Int64? = nil,
        tier: String = "pro"
    ) throws -> Data {
        let payload = try JSONSerialization.data(
            withJSONObject: [
                "version": 1,
                "issuer": CommercialLicenseVerifier.expectedIssuer,
                "productID": CommercialLicenseVerifier.expectedProductID,
                "licenseID": licenseID,
                "generation": generation,
                "issuedAt": issuedAt ?? nowSeconds - 60,
                "notBefore": nowSeconds,
                "expiresAt": expiresAt.map { NSNumber(value: $0) } ?? NSNull(),
                "tier": tier,
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

    private func makeTamperedDocument(from document: Data) throws -> Data {
        var lines = try XCTUnwrap(String(data: document, encoding: .utf8))
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let payload = try XCTUnwrap(Data(base64Encoded: lines[2]))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: payload) as? [String: Any]
        )
        object["tier"] = "team"
        lines[2] = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        ).base64EncodedString()
        return Data(lines.joined(separator: "\n").utf8)
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw URLError(.timedOut)
    }
}

private final class CommercialActivationTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    var currentDate: Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func set(_ date: Date) {
        lock.lock()
        self.date = date
        lock.unlock()
    }
}

private struct ActivationTransportFixtureError: Error, Sendable,
    CustomStringConvertible
{
    let description: String
}

private actor ImmediateActivationTransport: CommercialActivationTransport {
    private let result: Result<
        CommercialActivationTransportResponse,
        ActivationTransportFixtureError
    >
    private(set) var requestCount = 0

    init(
        result: Result<
            CommercialActivationTransportResponse,
            ActivationTransportFixtureError
        >
    ) {
        self.result = result
    }

    func exchange(
        activationCode: CommercialActivationCode
    ) throws -> CommercialActivationTransportResponse {
        requestCount += 1
        return try result.get()
    }
}

private actor QueuedActivationTransport: CommercialActivationTransport {
    private var responses: [CommercialActivationTransportResponse]

    init(responses: [CommercialActivationTransportResponse]) {
        self.responses = responses
    }

    func exchange(
        activationCode: CommercialActivationCode
    ) -> CommercialActivationTransportResponse {
        precondition(!responses.isEmpty, "Missing activation response fixture")
        return responses.removeFirst()
    }
}

private actor ControlledActivationTransport: CommercialActivationTransport {
    private(set) var requestCount = 0
    private var continuations: [
        String: CheckedContinuation<CommercialActivationTransportResponse, Error>
    ] = [:]

    func exchange(
        activationCode: CommercialActivationCode
    ) async throws -> CommercialActivationTransportResponse {
        let key = codeKey(activationCode)
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            precondition(continuations[key] == nil, "Duplicate activation code fixture")
            continuations[key] = continuation
        }
    }

    func complete(
        code: CommercialActivationCode,
        with response: CommercialActivationTransportResponse
    ) {
        let key = codeKey(code)
        guard let continuation = continuations.removeValue(forKey: key) else {
            preconditionFailure("No pending activation fixture for \(key)")
        }
        continuation.resume(returning: response)
    }

    private func codeKey(_ code: CommercialActivationCode) -> String {
        code.withUnsafeUTF8Bytes { bytes in
            String(decoding: bytes, as: UTF8.self)
        }
    }
}
