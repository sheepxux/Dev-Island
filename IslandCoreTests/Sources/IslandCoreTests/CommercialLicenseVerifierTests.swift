import CryptoKit
import Foundation
import XCTest
@testable import IslandCore

final class CommercialLicenseVerifierTests: XCTestCase {
    private let keyID = "license-2026-01"
    private let issuedAt: Int64 = 1_788_163_200
    private let notBefore: Int64 = 1_788_163_260
    private let licenseID = "f4c24d5b-ff4a-40f8-9315-e489b0cfe2d8"

    private var privateKey: Curve25519.Signing.PrivateKey!
    private var verifier: CommercialLicenseVerifier!

    override func setUpWithError() throws {
        privateKey = Curve25519.Signing.PrivateKey()
        let trustedKey = try TrustedCommercialLicenseKey(
            id: keyID,
            rawRepresentation: privateKey.publicKey.rawRepresentation
        )
        verifier = try CommercialLicenseVerifier(trustedKeys: [trustedKey])
    }

    func testSafeDefaultCannotEnableCommercialState() throws {
        let document = try makeDocument(payload: makePayload())
        XCTAssertEqual(
            CommercialLicenseVerifier().evaluate(document: document),
            .commercialModeDisabled
        )
    }

    func testConfiguredVerifierReportsMissingDocument() {
        XCTAssertEqual(verifier.evaluate(document: nil), .missingDocument)
        XCTAssertEqual(verifier.evaluate(document: Data()), .missingDocument)
    }

    func testValidLifetimeLicenseReturnsPrivacyMinimalEntitlements() throws {
        let document = try makeDocument(payload: makePayload())
        let evaluation = verifier.evaluate(
            document: document,
            now: Date(timeIntervalSince1970: TimeInterval(notBefore))
        )

        guard case .valid(let license) = evaluation else {
            return XCTFail("expected valid license, got \(evaluation)")
        }
        XCTAssertEqual(license.licenseID.uuidString.lowercased(), licenseID)
        XCTAssertEqual(license.generation, 1)
        XCTAssertEqual(license.tier, "pro")
        XCTAssertEqual(license.features, ["agent-unlimited", "updates"])
        XCTAssertTrue(license.grants("updates"))
        XCTAssertFalse(license.grants("unknown"))
        XCTAssertNil(license.expiresAt)
        XCTAssertEqual(license.signingKeyID, keyID)
    }

    func testValidityWindowUsesInclusiveStartAndExclusiveExpiry() throws {
        let expiry = notBefore + 600
        let document = try makeDocument(
            payload: makePayload(expiresAt: expiry)
        )

        XCTAssertEqual(
            rejection(document, now: notBefore - 1),
            .notYetValid
        )
        XCTAssertNil(rejection(document, now: notBefore))
        XCTAssertNil(rejection(document, now: expiry - 1))
        XCTAssertEqual(rejection(document, now: expiry), .expired)
    }

    func testPayloadTamperingInvalidatesSignatureBeforeSemantics() throws {
        let originalPayload = makePayload(tier: "pro")
        let signature = try privateKey.signature(
            for: CommercialLicenseVerifier.signingMessage(
                keyID: keyID,
                payload: originalPayload
            )
        )
        let tamperedPayload = makePayload(tier: "team")
        let document = makeEnvelope(
            keyID: keyID,
            payload: tamperedPayload,
            signature: signature
        )

        XCTAssertEqual(rejection(document), .invalidSignature)
    }

    func testUnauthenticatedMalformedPayloadIsNotParsed() throws {
        let originalPayload = makePayload()
        let signature = try privateKey.signature(
            for: CommercialLicenseVerifier.signingMessage(
                keyID: keyID,
                payload: originalPayload
            )
        )
        let malformedTampering = makeEnvelope(
            keyID: keyID,
            payload: Data([0xFF, 0x00, 0x7B]),
            signature: signature
        )
        XCTAssertEqual(rejection(malformedTampering), .invalidSignature)
    }

    func testSigningKeyIdentifierIsDomainBound() throws {
        let secondID = "license-2026-02"
        let secondTrustEntry = try TrustedCommercialLicenseKey(
            id: secondID,
            rawRepresentation: privateKey.publicKey.rawRepresentation
        )
        let firstTrustEntry = try TrustedCommercialLicenseKey(
            id: keyID,
            rawRepresentation: privateKey.publicKey.rawRepresentation
        )
        let rotatingVerifier = try CommercialLicenseVerifier(
            trustedKeys: [firstTrustEntry, secondTrustEntry]
        )
        let payload = makePayload()
        let signature = try privateKey.signature(
            for: CommercialLicenseVerifier.signingMessage(
                keyID: keyID,
                payload: payload
            )
        )
        let substituted = makeEnvelope(
            keyID: secondID,
            payload: payload,
            signature: signature
        )

        XCTAssertEqual(
            rejection(substituted, using: rotatingVerifier),
            .invalidSignature
        )
    }

    func testRawPayloadSignatureCannotCrossIntoLicenseProtocol() throws {
        let payload = makePayload()
        let rawSignature = try privateKey.signature(for: payload)
        let document = makeEnvelope(
            keyID: keyID,
            payload: payload,
            signature: rawSignature
        )
        XCTAssertEqual(rejection(document), .invalidSignature)
    }

    func testUnknownSigningKeyFailsBeforeSignatureAcceptance() throws {
        let payload = makePayload()
        let unknownID = "license-unknown"
        let signature = try privateKey.signature(
            for: CommercialLicenseVerifier.signingMessage(
                keyID: unknownID,
                payload: payload
            )
        )
        let document = makeEnvelope(
            keyID: unknownID,
            payload: payload,
            signature: signature
        )
        XCTAssertEqual(rejection(document), .unknownSigningKey)
    }

    func testEnvelopeGrammarRejectsCRLFExtraLinesAndInvalidKeyID() throws {
        let valid = try makeDocument(payload: makePayload())
        let text = try XCTUnwrap(String(data: valid, encoding: .utf8))

        XCTAssertEqual(
            rejection(Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8)),
            .malformedEnvelope
        )
        XCTAssertEqual(rejection(Data((text + "\n").utf8)), .malformedEnvelope)

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let invalidKey = [String(lines[0]), "LICENSE UPPER", String(lines[2]), String(lines[3])]
            .joined(separator: "\n")
        XCTAssertEqual(
            rejection(Data(invalidKey.utf8)),
            .invalidKeyIdentifier
        )
    }

    func testEnvelopeRejectsNonCanonicalBase64AndWrongSignatureLength() {
        let payload = makePayload()
        let nonCanonical = [
            CommercialLicenseVerifier.envelopeHeader,
            keyID,
            "YQ",
            Data(repeating: 0, count: 64).base64EncodedString(),
        ].joined(separator: "\n")
        XCTAssertEqual(
            rejection(Data(nonCanonical.utf8)),
            .nonCanonicalBase64
        )

        let shortSignature = makeEnvelope(
            keyID: keyID,
            payload: payload,
            signature: Data(repeating: 0, count: 63)
        )
        XCTAssertEqual(
            rejection(shortSignature),
            .invalidSignatureLength
        )
    }

    func testEnvelopeRejectsInvalidUTF8AndOversizedDocuments() {
        XCTAssertEqual(rejection(Data([0xFF, 0xFE])), .invalidUTF8)
        XCTAssertEqual(
            rejection(Data(repeating: 0x61, count: 32 * 1_024 + 1)),
            .documentTooLarge
        )
    }

    func testAuthenticatedPayloadRejectsUnknownOrMissingFields() throws {
        let withEmail = makePayload(additionalFields: ["email": "person@example.com"])
        XCTAssertEqual(
            rejection(try makeDocument(payload: withEmail)),
            .malformedPayload
        )

        let missingTier = makePayload(omitting: ["tier"])
        XCTAssertEqual(
            rejection(try makeDocument(payload: missingTier)),
            .malformedPayload
        )
    }

    func testAuthenticatedPayloadMustUseCanonicalJSON() throws {
        let canonical = makePayload()
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: canonical) as? [String: Any]
        )
        let prettyPrinted = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        XCTAssertEqual(
            rejection(try makeDocument(payload: prettyPrinted)),
            .nonCanonicalPayload
        )

        let duplicateTier = Data(
            "{\"expiresAt\":null,\"features\":[\"agent-unlimited\",\"updates\"],\"generation\":1,\"issuedAt\":1788163200,\"issuer\":\"devisland.app\",\"licenseID\":\"f4c24d5b-ff4a-40f8-9315-e489b0cfe2d8\",\"notBefore\":1788163260,\"productID\":\"app.devisland.Island\",\"tier\":\"pro\",\"tier\":\"team\",\"version\":1}".utf8
        )
        XCTAssertEqual(
            rejection(try makeDocument(payload: duplicateTier)),
            .nonCanonicalPayload
        )
    }

    func testAuthenticatedPayloadPinsVersionIssuerAndProduct() throws {
        XCTAssertEqual(
            rejection(try makeDocument(payload: makePayload(version: 2))),
            .unsupportedPayloadVersion
        )
        XCTAssertEqual(
            rejection(try makeDocument(payload: makePayload(issuer: "example.com"))),
            .wrongIssuer
        )
        XCTAssertEqual(
            rejection(try makeDocument(payload: makePayload(productID: "other.app"))),
            .wrongProduct
        )
    }

    func testAuthenticatedPayloadRequiresCanonicalIdentityTierAndFeatures() throws {
        XCTAssertEqual(
            rejection(try makeDocument(payload: makePayload(licenseID: licenseID.uppercased()))),
            .invalidLicenseIdentifier
        )
        XCTAssertEqual(
            rejection(try makeDocument(payload: makePayload(tier: "Pro"))),
            .invalidTier
        )
        XCTAssertEqual(
            rejection(try makeDocument(payload: makePayload(features: ["updates", "agent-unlimited"]))),
            .invalidFeatures
        )
        XCTAssertEqual(
            rejection(try makeDocument(payload: makePayload(features: ["updates", "updates"]))),
            .invalidFeatures
        )
    }

    func testAuthenticatedPayloadRequiresPositiveGeneration() throws {
        XCTAssertEqual(
            rejection(try makeDocument(payload: makePayload(generation: 0))),
            .invalidGeneration
        )
        XCTAssertEqual(
            rejection(try makeDocument(payload: makePayload(generation: -1))),
            .invalidGeneration
        )
    }

    func testAuthenticatedPayloadRejectsImpossibleTimestamps() throws {
        XCTAssertEqual(
            rejection(
                try makeDocument(
                    payload: makePayload(issuedAt: notBefore + 1)
                )
            ),
            .invalidTimestamps
        )
        XCTAssertEqual(
            rejection(
                try makeDocument(
                    payload: makePayload(expiresAt: notBefore)
                )
            ),
            .invalidTimestamps
        )
        XCTAssertEqual(
            rejection(
                try makeDocument(
                    payload: makePayload(issuedAt: 1_000, notBefore: 1_001)
                )
            ),
            .invalidTimestamps
        )
    }

    func testInvalidEvaluationClockFailsClosed() throws {
        let document = try makeDocument(payload: makePayload())
        XCTAssertEqual(
            verifier.evaluate(
                document: document,
                now: Date(timeIntervalSince1970: .infinity)
            ),
            .rejected(.invalidEvaluationTime)
        )
    }

    func testTrustConfigurationRejectsBadAndDuplicateKeys() throws {
        XCTAssertThrowsError(
            try TrustedCommercialLicenseKey(
                id: "UPPERCASE",
                rawRepresentation: privateKey.publicKey.rawRepresentation
            )
        ) { error in
            XCTAssertEqual(error as? CommercialLicenseTrustError, .invalidKeyIdentifier)
        }
        XCTAssertThrowsError(
            try TrustedCommercialLicenseKey(
                id: keyID,
                rawRepresentation: Data(repeating: 0, count: 31)
            )
        ) { error in
            XCTAssertEqual(error as? CommercialLicenseTrustError, .invalidPublicKey)
        }

        let key = try TrustedCommercialLicenseKey(
            id: keyID,
            rawRepresentation: privateKey.publicKey.rawRepresentation
        )
        XCTAssertThrowsError(
            try CommercialLicenseVerifier(trustedKeys: [key, key])
        ) { error in
            XCTAssertEqual(error as? CommercialLicenseTrustError, .duplicateKeyIdentifier)
        }
    }

    private func rejection(
        _ document: Data,
        using target: CommercialLicenseVerifier? = nil,
        now: Int64? = nil
    ) -> CommercialLicenseRejection? {
        let evaluation = (target ?? verifier).evaluate(
            document: document,
            now: Date(timeIntervalSince1970: TimeInterval(now ?? notBefore))
        )
        if case .rejected(let reason) = evaluation { return reason }
        return nil
    }

    private func makePayload(
        version: Int = 1,
        issuer: String = CommercialLicenseVerifier.expectedIssuer,
        productID: String = CommercialLicenseVerifier.expectedProductID,
        licenseID: String? = nil,
        generation: Int64 = 1,
        issuedAt: Int64? = nil,
        notBefore: Int64? = nil,
        expiresAt: Int64? = nil,
        tier: String = "pro",
        features: [String] = ["agent-unlimited", "updates"],
        additionalFields: [String: Any] = [:],
        omitting omittedKeys: Set<String> = []
    ) -> Data {
        var object: [String: Any] = [
            "version": version,
            "issuer": issuer,
            "productID": productID,
            "licenseID": licenseID ?? self.licenseID,
            "generation": generation,
            "issuedAt": issuedAt ?? self.issuedAt,
            "notBefore": notBefore ?? self.notBefore,
            "expiresAt": expiresAt.map { NSNumber(value: $0) } ?? NSNull(),
            "tier": tier,
            "features": features,
        ]
        additionalFields.forEach { object[$0.key] = $0.value }
        omittedKeys.forEach { object.removeValue(forKey: $0) }
        return try! JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
    }

    private func makeDocument(payload: Data, signingKeyID: String? = nil) throws -> Data {
        let targetKeyID = signingKeyID ?? keyID
        let signature = try privateKey.signature(
            for: CommercialLicenseVerifier.signingMessage(
                keyID: targetKeyID,
                payload: payload
            )
        )
        return makeEnvelope(
            keyID: targetKeyID,
            payload: payload,
            signature: signature
        )
    }

    private func makeEnvelope(
        keyID: String,
        payload: Data,
        signature: Data
    ) -> Data {
        Data(
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
