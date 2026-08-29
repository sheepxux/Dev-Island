import Foundation
import Security

/// Fail-closed storage errors for a future signed commercial license document.
/// No error includes document bytes, so callers can report aggregate state
/// without putting a bearer entitlement into logs or diagnostics.
public enum CommercialLicenseDocumentStoreError: Error, Equatable, Sendable {
    case invalidDocumentSize
    case storedDocumentTooLarge
    case storedDocumentRejected
    case rollbackRejected
    case conflictingGeneration
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case unexpectedData
}

/// Device-local Keychain storage for a verified license document.
///
/// The public import boundary authenticates the exact bytes before persisting
/// them. It never activates, refreshes, issues, or grants entitlements. The
/// current app does not instantiate this store, so commercial mode remains
/// disabled.
public struct CommercialLicenseDocumentStore: Sendable {
    public static let maximumDocumentBytes =
        CommercialLicenseVerifier.maximumDocumentBytes

    static let defaultService = "app.devisland.Island"
    static let defaultAccount = "commercial_license_v1"

    private let service: String
    private let account: String
    private static let mutationLock = CommercialLicenseStoreMutationLock()

    public init() {
        self.init(service: Self.defaultService, account: Self.defaultAccount)
    }

    /// Internal injection keeps tests isolated from the production Keychain
    /// namespace without making an arbitrary service/account override part of
    /// the shipping API.
    init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    /// Authenticate and persist the exact same bytes only when the verifier
    /// returns `.valid`. Every disabled/missing/rejected result leaves the
    /// previous device-local document untouched.
    @discardableResult
    public func importDocument(
        _ document: Data,
        using verifier: CommercialLicenseVerifier,
        now: Date = .now
    ) throws -> CommercialLicenseEvaluation {
        return try Self.mutationLock.withLock {
            let evaluation = verifier.evaluate(document: document, now: now)
            guard case .valid(let incomingLicense) = evaluation else {
                return evaluation
            }

            if let storedDocument = try loadDocument() {
                let storedLicense: VerifiedCommercialLicense
                do {
                    // Authenticate the old claims without applying today's
                    // validity window. Expiry must not erase the revision
                    // floor that protects a later import from rollback.
                    storedLicense = try verifier.authenticate(
                        document: storedDocument
                    )
                } catch {
                    // A corrupted or no-longer-trusted stored document must be
                    // removed through the explicit recovery boundary. Silently
                    // replacing it would let corruption bypass monotonicity.
                    throw CommercialLicenseDocumentStoreError
                        .storedDocumentRejected
                }

                if storedLicense.licenseID == incomingLicense.licenseID {
                    guard incomingLicense.generation
                        >= storedLicense.generation else {
                        throw CommercialLicenseDocumentStoreError
                            .rollbackRejected
                    }

                    if incomingLicense.generation == storedLicense.generation {
                        guard document == storedDocument else {
                            throw CommercialLicenseDocumentStoreError
                                .conflictingGeneration
                        }
                        return evaluation
                    }

                    // A higher generation may extend or reduce entitlement,
                    // but its signed issuance time cannot move backward.
                    guard incomingLicense.issuedAt >= storedLicense.issuedAt else {
                        throw CommercialLicenseDocumentStoreError
                            .rollbackRejected
                    }
                }
            }

            try saveAuthenticated(document)
            return evaluation
        }
    }

    /// Evaluate the stored document without exposing bearer bytes to callers.
    public func evaluateStored(
        using verifier: CommercialLicenseVerifier,
        now: Date = .now
    ) throws -> CommercialLicenseEvaluation {
        try Self.mutationLock.withLock {
            verifier.evaluate(document: try loadDocument(), now: now)
        }
    }

    private func saveAuthenticated(_ document: Data) throws {
        guard !document.isEmpty,
              document.count <= Self.maximumDocumentBytes else {
            throw CommercialLicenseDocumentStoreError.invalidDocumentSize
        }

        let query = baseQuery
        let updatedAttributes: [CFString: Any] = [
            kSecValueData: document,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            updatedAttributes as CFDictionary
        )

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            updatedAttributes.forEach { addQuery[$0.key] = $0.value }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CommercialLicenseDocumentStoreError.saveFailed(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw CommercialLicenseDocumentStoreError.saveFailed(updateStatus)
        }
    }

    private func loadDocument() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw CommercialLicenseDocumentStoreError.loadFailed(status)
        }
        guard let document = result as? Data, !document.isEmpty else {
            throw CommercialLicenseDocumentStoreError.unexpectedData
        }
        guard document.count <= Self.maximumDocumentBytes else {
            throw CommercialLicenseDocumentStoreError.storedDocumentTooLarge
        }
        return document
    }

    public func delete() throws {
        try Self.mutationLock.withLock {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CommercialLicenseDocumentStoreError.deleteFailed(status)
            }
        }
    }

    private var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: false,
        ]
    }
}

/// Serializes the read/compare/write replacement boundary inside one process.
/// Security.framework does not expose compare-and-swap for generic-password
/// values; a future multi-process writer must add an inter-process protocol
/// rather than assuming this lock crosses process boundaries.
private final class CommercialLicenseStoreMutationLock: @unchecked Sendable {
    private let lock = NSLock()

    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
