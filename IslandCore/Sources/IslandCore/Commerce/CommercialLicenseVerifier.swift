import CryptoKit
import Foundation

/// A reviewed Ed25519 public key that may verify commercial license documents.
/// Private signing material is intentionally not representable by this API.
public struct TrustedCommercialLicenseKey: Sendable {
    public let id: String
    fileprivate let publicKey: Curve25519.Signing.PublicKey

    public init(id: String, rawRepresentation: Data) throws {
        guard CommercialLicenseVerifier.isCanonicalToken(id, maximumLength: 64) else {
            throw CommercialLicenseTrustError.invalidKeyIdentifier
        }
        do {
            publicKey = try Curve25519.Signing.PublicKey(
                rawRepresentation: rawRepresentation
            )
        } catch {
            throw CommercialLicenseTrustError.invalidPublicKey
        }
        self.id = id
    }
}

public enum CommercialLicenseTrustError: Error, Equatable, Sendable {
    case invalidKeyIdentifier
    case invalidPublicKey
    case duplicateKeyIdentifier
}

/// Stable, privacy-minimal fields recovered only after signature verification.
public struct VerifiedCommercialLicense: Equatable, Sendable {
    public let licenseID: UUID
    /// Issuer-controlled, strictly positive revision for this license ID.
    /// The device-local store uses it to reject signed-document rollback.
    public let generation: Int64
    public let tier: String
    public let features: [String]
    public let issuedAt: Date
    public let notBefore: Date
    public let expiresAt: Date?
    public let signingKeyID: String

    public func grants(_ feature: String) -> Bool {
        features.contains(feature)
    }
}

public enum CommercialLicenseRejection: Error, Equatable, Sendable {
    case noTrustAnchors
    case documentTooLarge
    case invalidUTF8
    case malformedEnvelope
    case invalidKeyIdentifier
    case unknownSigningKey
    case nonCanonicalBase64
    case payloadTooLarge
    case invalidSignatureLength
    case invalidSignature
    case malformedPayload
    case nonCanonicalPayload
    case unsupportedPayloadVersion
    case wrongIssuer
    case wrongProduct
    case invalidLicenseIdentifier
    case invalidGeneration
    case invalidTier
    case invalidFeatures
    case invalidTimestamps
    case invalidEvaluationTime
    case notYetValid
    case expired
}

public enum CommercialLicenseEvaluation: Equatable, Sendable {
    /// The shipping beta remains free and unchanged until reviewed public keys
    /// and an owner-approved commercial policy are deliberately wired in.
    case commercialModeDisabled
    case missingDocument
    case valid(VerifiedCommercialLicense)
    case rejected(CommercialLicenseRejection)
}

/// Strict offline verifier for the future commercial distribution layer.
///
/// Trust is fail-closed: the default initializer has no trust anchors and
/// returns `.commercialModeDisabled`. Enabling it requires a code-reviewed
/// Ed25519 public key. There is no environment, preferences, or remote-key
/// override, and no private-key or license-issuance API in the app target.
public struct CommercialLicenseVerifier: Sendable {
    public static let expectedIssuer = "devisland.app"
    public static let expectedProductID = "app.devisland.Island"

    static let envelopeHeader = "DEV-ISLAND-LICENSE/1"
    static let domainSeparator = "DevIsland.CommercialLicense\0v1\0"

    static let maximumDocumentBytes = 32 * 1_024
    private static let maximumPayloadBytes = 8 * 1_024
    private static let expectedSignatureBytes = 64
    private static let minimumTimestamp: Int64 = 1_577_836_800 // 2020-01-01
    private static let maximumTimestamp: Int64 = 4_102_444_800 // 2100-01-01
    private static let payloadKeys: Set<String> = [
        "version",
        "issuer",
        "productID",
        "licenseID",
        "generation",
        "issuedAt",
        "notBefore",
        "expiresAt",
        "tier",
        "features",
    ]

    private let trustedKeys: [String: Curve25519.Signing.PublicKey]

    /// Safe default for the current beta: no document can enable paid state.
    public init() {
        trustedKeys = [:]
    }

    public init(trustedKeys keys: [TrustedCommercialLicenseKey]) throws {
        var result: [String: Curve25519.Signing.PublicKey] = [:]
        for key in keys {
            guard result.updateValue(key.publicKey, forKey: key.id) == nil else {
                throw CommercialLicenseTrustError.duplicateKeyIdentifier
            }
        }
        trustedKeys = result
    }

    public func evaluate(
        document: Data?,
        now: Date = .now
    ) -> CommercialLicenseEvaluation {
        guard !trustedKeys.isEmpty else { return .commercialModeDisabled }
        guard let document, !document.isEmpty else { return .missingDocument }

        do {
            return .valid(try verify(document: document, now: now))
        } catch let rejection as CommercialLicenseRejection {
            return .rejected(rejection)
        } catch {
            // Avoid leaking parser or CryptoKit implementation details into
            // UI/logging while still returning deterministic product state.
            return .rejected(.malformedPayload)
        }
    }

    private func verify(document: Data, now: Date) throws -> VerifiedCommercialLicense {
        let license = try authenticate(document: document)
        try Self.validateEvaluationTime(license, now: now)
        return license
    }

    /// Authenticates and validates signed claims without applying the current
    /// validity window. The storage boundary needs this internal view to
    /// compare a previously accepted (possibly now expired) generation before
    /// replacing its bytes. It is intentionally not public entitlement state.
    func authenticate(document: Data) throws -> VerifiedCommercialLicense {
        guard !trustedKeys.isEmpty else {
            throw CommercialLicenseRejection.noTrustAnchors
        }
        let envelope = try Self.parseEnvelope(document)
        guard let publicKey = trustedKeys[envelope.keyID] else {
            throw CommercialLicenseRejection.unknownSigningKey
        }

        let signingMessage = Self.signingMessage(
            keyID: envelope.keyID,
            payload: envelope.payload
        )
        guard publicKey.isValidSignature(
            envelope.signature,
            for: signingMessage
        ) else {
            throw CommercialLicenseRejection.invalidSignature
        }

        // Parse only authenticated bytes. This keeps malformed, attacker-made
        // JSON outside the semantic decoder and bounds all remaining work.
        let payload = try Self.decodePayload(envelope.payload)
        return try Self.validateClaims(
            payload,
            keyID: envelope.keyID
        )
    }

    static func signingMessage(keyID: String, payload: Data) -> Data {
        var message = Data(domainSeparator.utf8)
        message.append(contentsOf: keyID.utf8)
        message.append(0)
        message.append(payload)
        return message
    }

    static func isCanonicalToken(_ value: String, maximumLength: Int) -> Bool {
        guard !value.isEmpty, value.utf8.count <= maximumLength else { return false }
        return value.utf8.allSatisfy { byte in
            switch byte {
            case 0x30...0x39, 0x61...0x7A, 0x2D, 0x2E, 0x5F:
                return true
            default:
                return false
            }
        }
    }

    private static func parseEnvelope(_ document: Data) throws -> Envelope {
        guard document.count <= maximumDocumentBytes else {
            throw CommercialLicenseRejection.documentTooLarge
        }
        guard let text = String(data: document, encoding: .utf8) else {
            throw CommercialLicenseRejection.invalidUTF8
        }
        guard !text.contains("\r") else {
            throw CommercialLicenseRejection.malformedEnvelope
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count == 4, lines[0] == Substring(envelopeHeader) else {
            throw CommercialLicenseRejection.malformedEnvelope
        }

        let keyID = String(lines[1])
        guard isCanonicalToken(keyID, maximumLength: 64) else {
            throw CommercialLicenseRejection.invalidKeyIdentifier
        }
        let payload = try decodeCanonicalBase64(String(lines[2]))
        guard !payload.isEmpty, payload.count <= maximumPayloadBytes else {
            throw CommercialLicenseRejection.payloadTooLarge
        }
        let signature = try decodeCanonicalBase64(String(lines[3]))
        guard signature.count == expectedSignatureBytes else {
            throw CommercialLicenseRejection.invalidSignatureLength
        }

        return Envelope(keyID: keyID, payload: payload, signature: signature)
    }

    private static func decodeCanonicalBase64(_ value: String) throws -> Data {
        guard let decoded = Data(base64Encoded: value),
              decoded.base64EncodedString() == value else {
            throw CommercialLicenseRejection.nonCanonicalBase64
        }
        return decoded
    }

    private static func decodePayload(_ data: Data) throws -> WirePayload {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CommercialLicenseRejection.malformedPayload
        }
        guard let dictionary = object as? [String: Any],
              Set(dictionary.keys) == payloadKeys else {
            throw CommercialLicenseRejection.malformedPayload
        }
        let canonical: Data
        do {
            canonical = try JSONSerialization.data(
                withJSONObject: dictionary,
                options: [.sortedKeys]
            )
        } catch {
            throw CommercialLicenseRejection.malformedPayload
        }
        guard canonical == data else {
            // Besides making issuer output reproducible, exact canonical bytes
            // reject duplicate JSON keys, whitespace variants, and alternate
            // number spellings that permissive parsers could interpret
            // differently across platforms.
            throw CommercialLicenseRejection.nonCanonicalPayload
        }

        do {
            return try JSONDecoder().decode(WirePayload.self, from: data)
        } catch {
            throw CommercialLicenseRejection.malformedPayload
        }
    }

    private static func validateClaims(
        _ payload: WirePayload,
        keyID: String
    ) throws -> VerifiedCommercialLicense {
        guard payload.version == 1 else {
            throw CommercialLicenseRejection.unsupportedPayloadVersion
        }
        guard payload.issuer == expectedIssuer else {
            throw CommercialLicenseRejection.wrongIssuer
        }
        guard payload.productID == expectedProductID else {
            throw CommercialLicenseRejection.wrongProduct
        }
        guard let licenseID = UUID(uuidString: payload.licenseID),
              licenseID.uuidString.lowercased() == payload.licenseID else {
            throw CommercialLicenseRejection.invalidLicenseIdentifier
        }
        guard payload.generation > 0 else {
            throw CommercialLicenseRejection.invalidGeneration
        }
        guard isCanonicalToken(payload.tier, maximumLength: 32) else {
            throw CommercialLicenseRejection.invalidTier
        }
        guard payload.features.count <= 32,
              payload.features.allSatisfy({ isCanonicalToken($0, maximumLength: 48) }),
              Set(payload.features).count == payload.features.count,
              payload.features == payload.features.sorted() else {
            throw CommercialLicenseRejection.invalidFeatures
        }

        guard timestampIsSane(payload.issuedAt),
              timestampIsSane(payload.notBefore),
              payload.issuedAt <= payload.notBefore else {
            throw CommercialLicenseRejection.invalidTimestamps
        }
        if let expiresAt = payload.expiresAt {
            guard timestampIsSane(expiresAt), expiresAt > payload.notBefore else {
                throw CommercialLicenseRejection.invalidTimestamps
            }
        }

        return VerifiedCommercialLicense(
            licenseID: licenseID,
            generation: payload.generation,
            tier: payload.tier,
            features: payload.features,
            issuedAt: Date(timeIntervalSince1970: TimeInterval(payload.issuedAt)),
            notBefore: Date(timeIntervalSince1970: TimeInterval(payload.notBefore)),
            expiresAt: payload.expiresAt.map {
                Date(timeIntervalSince1970: TimeInterval($0))
            },
            signingKeyID: keyID
        )
    }

    private static func validateEvaluationTime(
        _ license: VerifiedCommercialLicense,
        now: Date
    ) throws {
        let nowInterval = now.timeIntervalSince1970
        guard nowInterval.isFinite,
              nowInterval >= Double(Int64.min),
              nowInterval <= Double(Int64.max) else {
            throw CommercialLicenseRejection.invalidEvaluationTime
        }
        let nowSeconds = Int64(nowInterval.rounded(.down))
        let notBefore = Int64(license.notBefore.timeIntervalSince1970)
        guard nowSeconds >= notBefore else {
            throw CommercialLicenseRejection.notYetValid
        }
        if let expiresAt = license.expiresAt.map({
            Int64($0.timeIntervalSince1970)
        }), nowSeconds >= expiresAt {
            throw CommercialLicenseRejection.expired
        }
    }

    private static func timestampIsSane(_ value: Int64) -> Bool {
        value >= minimumTimestamp && value <= maximumTimestamp
    }
}

private extension CommercialLicenseVerifier {
    struct Envelope {
        let keyID: String
        let payload: Data
        let signature: Data
    }

    struct WirePayload: Decodable {
        let version: Int
        let issuer: String
        let productID: String
        let licenseID: String
        let generation: Int64
        let issuedAt: Int64
        let notBefore: Int64
        let expiresAt: Int64?
        let tier: String
        let features: [String]
    }
}
