import CryptoKit
import Foundation
import Security
import XCTest
@testable import IslandCore

final class CommercialLicenseDocumentStoreTests: XCTestCase {
    private let keyID = "license-storage-test"
    private let nowSeconds: Int64 = 1_788_163_260
    private let firstLicenseID = "f4c24d5b-ff4a-40f8-9315-e489b0cfe2d8"
    private let secondLicenseID = "6aeb8ff8-51d1-4b25-8d87-ed83eac7409b"

    private var service: String!
    private var account: String!
    private var store: CommercialLicenseDocumentStore!
    private var privateKey: Curve25519.Signing.PrivateKey!
    private var verifier: CommercialLicenseVerifier!

    override func setUpWithError() throws {
        service = "app.devisland.Island.tests.\(UUID().uuidString.lowercased())"
        account = "commercial-license-test"
        store = CommercialLicenseDocumentStore(service: service, account: account)
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
        account = nil
        service = nil
    }

    func testVerifiedImportRoundTripsAndReplacesDocument() throws {
        let first = try makeDocument(licenseID: firstLicenseID)
        let second = try makeDocument(licenseID: secondLicenseID)

        let firstEvaluation = try store.importDocument(
            first,
            using: verifier,
            now: evaluationDate
        )
        XCTAssertEqual(
            try store.evaluateStored(using: verifier, now: evaluationDate),
            firstEvaluation
        )

        let secondEvaluation = try store.importDocument(
            second,
            using: verifier,
            now: evaluationDate
        )
        XCTAssertEqual(
            try store.evaluateStored(using: verifier, now: evaluationDate),
            secondEvaluation
        )
    }

    func testOlderGenerationCannotReplaceNewerStoredLicense() throws {
        let current = try makeDocument(
            licenseID: firstLicenseID,
            generation: 2,
            expiresAt: nowSeconds + 1
        )
        let stale = try makeDocument(
            licenseID: firstLicenseID,
            generation: 1
        )
        let currentEvaluation = try store.importDocument(
            current,
            using: verifier,
            now: evaluationDate
        )

        XCTAssertThrowsError(
            try store.importDocument(
                stale,
                using: verifier,
                now: Date(timeIntervalSince1970: TimeInterval(nowSeconds + 2))
            )
        ) { error in
            XCTAssertEqual(
                error as? CommercialLicenseDocumentStoreError,
                .rollbackRejected
            )
        }
        XCTAssertEqual(
            try store.evaluateStored(using: verifier, now: evaluationDate),
            currentEvaluation
        )
    }

    func testEqualGenerationIsIdempotentButConflictingBytesAreRejected() throws {
        let original = try makeDocument(
            licenseID: firstLicenseID,
            generation: 4,
            tier: "pro"
        )
        let conflict = try makeDocument(
            licenseID: firstLicenseID,
            generation: 4,
            tier: "team"
        )
        let originalEvaluation = try store.importDocument(
            original,
            using: verifier,
            now: evaluationDate
        )

        XCTAssertEqual(
            try store.importDocument(
                original,
                using: verifier,
                now: evaluationDate
            ),
            originalEvaluation
        )
        XCTAssertThrowsError(
            try store.importDocument(
                conflict,
                using: verifier,
                now: evaluationDate
            )
        ) { error in
            XCTAssertEqual(
                error as? CommercialLicenseDocumentStoreError,
                .conflictingGeneration
            )
        }
        XCTAssertEqual(
            try store.evaluateStored(using: verifier, now: evaluationDate),
            originalEvaluation
        )
    }

    func testHigherGenerationCannotMoveSignedIssuanceTimeBackward() throws {
        let current = try makeDocument(
            licenseID: firstLicenseID,
            generation: 5,
            issuedAt: nowSeconds - 30
        )
        let inconsistentSuccessor = try makeDocument(
            licenseID: firstLicenseID,
            generation: 6,
            issuedAt: nowSeconds - 60
        )
        let currentEvaluation = try store.importDocument(
            current,
            using: verifier,
            now: evaluationDate
        )

        XCTAssertThrowsError(
            try store.importDocument(
                inconsistentSuccessor,
                using: verifier,
                now: evaluationDate
            )
        ) { error in
            XCTAssertEqual(
                error as? CommercialLicenseDocumentStoreError,
                .rollbackRejected
            )
        }
        XCTAssertEqual(
            try store.evaluateStored(using: verifier, now: evaluationDate),
            currentEvaluation
        )
    }

    func testConcurrentImportsCannotLeaveAnOlderGenerationStored() throws {
        let targetStore = try XCTUnwrap(store)
        let targetVerifier = try XCTUnwrap(verifier)
        let targetDate = evaluationDate
        let older = try makeDocument(
            licenseID: firstLicenseID,
            generation: 1
        )
        let newer = try makeDocument(
            licenseID: firstLicenseID,
            generation: 2
        )

        for _ in 0..<12 {
            try targetStore.delete()
            let unexpectedErrors = CommercialStoreErrorCollector()
            DispatchQueue.concurrentPerform(iterations: 2) { index in
                do {
                    try targetStore.importDocument(
                        index == 0 ? older : newer,
                        using: targetVerifier,
                        now: targetDate
                    )
                } catch CommercialLicenseDocumentStoreError.rollbackRejected {
                    // Expected only when the newer import wins the lock first.
                } catch {
                    unexpectedErrors.append(error)
                }
            }

            XCTAssertTrue(unexpectedErrors.isEmpty)
            guard case .valid(let stored) = try targetStore.evaluateStored(
                using: targetVerifier,
                now: targetDate
            ) else {
                return XCTFail("Expected a stored license")
            }
            XCTAssertEqual(stored.generation, 2)
        }
    }

    func testMissingEvaluationAndRepeatedDeleteAreIdempotent() throws {
        XCTAssertEqual(
            try store.evaluateStored(using: verifier, now: evaluationDate),
            .missingDocument
        )
        XCTAssertNoThrow(try store.delete())
        XCTAssertNoThrow(try store.delete())
    }

    func testDisabledOrInvalidReplacementPreservesVerifiedDocument() throws {
        let original = try makeDocument(licenseID: firstLicenseID)
        let originalEvaluation = try store.importDocument(
            original,
            using: verifier,
            now: evaluationDate
        )

        XCTAssertEqual(
            try store.importDocument(
                try makeDocument(licenseID: secondLicenseID),
                using: CommercialLicenseVerifier(),
                now: evaluationDate
            ),
            .commercialModeDisabled
        )
        XCTAssertEqual(
            try store.importDocument(Data(), using: verifier, now: evaluationDate),
            .missingDocument
        )
        XCTAssertEqual(
            try store.importDocument(
                Data(
                    repeating: 0x61,
                    count: CommercialLicenseDocumentStore.maximumDocumentBytes + 1
                ),
                using: verifier,
                now: evaluationDate
            ),
            .rejected(.documentTooLarge)
        )

        XCTAssertEqual(
            try store.evaluateStored(using: verifier, now: evaluationDate),
            originalEvaluation
        )
    }

    func testStoredOversizedDocumentFailsClosedOnEvaluation() throws {
        let oversized = Data(
            repeating: 0x61,
            count: CommercialLicenseDocumentStore.maximumDocumentBytes + 1
        )
        let status = SecItemAdd(
            keychainQuery(value: oversized) as CFDictionary,
            nil
        )
        XCTAssertEqual(status, errSecSuccess)

        XCTAssertThrowsError(
            try store.evaluateStored(using: verifier, now: evaluationDate)
        ) { error in
            XCTAssertEqual(
                error as? CommercialLicenseDocumentStoreError,
                .storedDocumentTooLarge
            )
        }
    }

    func testImportedDocumentUsesDeviceOnlyNonSynchronizingProtection() throws {
        let document = try makeDocument(licenseID: firstLicenseID)
        try store.importDocument(document, using: verifier, now: evaluationDate)

        var query = keychainQuery()
        query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: AnyObject?
        XCTAssertEqual(
            SecItemCopyMatching(query as CFDictionary, &result),
            errSecSuccess
        )
        XCTAssertEqual(result as? Data, document)

        var synchronizingQuery = keychainQuery()
        synchronizingQuery[kSecAttrSynchronizable] = true
        synchronizingQuery[kSecReturnData] = true
        synchronizingQuery[kSecMatchLimit] = kSecMatchLimitOne
        result = nil
        XCTAssertEqual(
            SecItemCopyMatching(synchronizingQuery as CFDictionary, &result),
            errSecItemNotFound
        )
    }

    private var evaluationDate: Date {
        Date(timeIntervalSince1970: TimeInterval(nowSeconds))
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

    private func keychainQuery(value: Data? = nil) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service as String,
            kSecAttrAccount: account as String,
            kSecAttrSynchronizable: false,
        ]
        if let value {
            query[kSecValueData] = value
            query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        return query
    }
}

private final class CommercialStoreErrorCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [Error] = []

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return errors.isEmpty
    }

    func append(_ error: Error) {
        lock.lock()
        errors.append(error)
        lock.unlock()
    }
}
