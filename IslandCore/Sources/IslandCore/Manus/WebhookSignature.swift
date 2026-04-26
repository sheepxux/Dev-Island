import Foundation
import Security

// Header name TBD — update docs/manus-api-field-notes.md after real testing
enum WebhookSignature {
    static let headerName = "X-Manus-Signature"

    enum VerificationError: Error {
        case invalidPublicKey
        case invalidSignatureEncoding
        case verificationFailed
    }

    /// Verify RSA-SHA256 signature.
    /// - Parameters:
    ///   - body: Raw HTTP request body bytes
    ///   - signature: Base64-encoded signature string from the webhook header
    ///   - publicKeyPEM: PEM-encoded RSA public key (PKCS#8 "BEGIN PUBLIC KEY" format)
    static func verify(body: Data, signature: String, publicKeyPEM: String) throws -> Bool {
        guard let sigData = Data(base64Encoded: signature) else {
            throw VerificationError.invalidSignatureEncoding
        }

        let key = try importPublicKey(pem: publicKeyPEM)

        var error: Unmanaged<CFError>?
        let result = SecKeyVerifySignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            body as CFData,
            sigData as CFData,
            &error
        )
        if let err = error?.takeRetainedValue() {
            IslandLogger.webhook.error("Signature verification error: \(err)")
            throw VerificationError.verificationFailed
        }
        return result
    }

    private static func importPublicKey(pem: String) throws -> SecKey {
        // Strip PEM headers and decode base64
        let stripped = pem
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN RSA PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PUBLIC KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()

        guard let derData = Data(base64Encoded: stripped) else {
            throw VerificationError.invalidPublicKey
        }

        // Strip PKCS#8 SubjectPublicKeyInfo header (24 bytes) if present.
        // PKCS#8 header for RSA-2048 starts with 0x30 0x82 ...
        // Raw PKCS#1 starts with 0x30 0x82 but differently — check OID prefix.
        let keyData = stripPKCS8HeaderIfNeeded(derData)

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
        ]
        var cfError: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &cfError) else {
            IslandLogger.webhook.error("Failed to import public key: \(cfError?.takeRetainedValue() as Any)")
            throw VerificationError.invalidPublicKey
        }
        return key
    }

    // PKCS#8 SubjectPublicKeyInfo wraps RSA key with a 24-byte header for RSA keys.
    // If the DER starts with the PKCS#8 OID sequence for RSA, strip the header.
    private static func stripPKCS8HeaderIfNeeded(_ data: Data) -> Data {
        // PKCS#8 RSA OID prefix (hex): 30 xx 30 0d 06 09 2a 86 48 86 f7 0d 01 01 01 05 00 03 xx 00
        // We check for the RSA OID bytes at offset 8
        guard data.count > 26 else { return data }
        let rsaOID: [UInt8] = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01]
        let oidRange = data[8..<17]
        if Array(oidRange) == rsaOID {
            // Find the BIT STRING tag (0x03) and skip past it + the 0x00 padding byte
            if let bitStringOffset = findBitStringOffset(data) {
                return data.subdata(in: bitStringOffset..<data.count)
            }
        }
        return data
    }

    private static func findBitStringOffset(_ data: Data) -> Int? {
        // Scan for 0x03 (BIT STRING) tag after the OID sequence
        for i in 16..<min(data.count - 2, 30) {
            if data[i] == 0x03 {
                // skip tag, length byte(s), and 0x00 padding
                let lengthByte = data[i + 1]
                let headerSize: Int
                if lengthByte & 0x80 == 0 {
                    headerSize = i + 3  // tag + 1-byte length + padding
                } else {
                    let numLengthBytes = Int(lengthByte & 0x7f)
                    headerSize = i + 2 + numLengthBytes + 1  // tag + length + padding
                }
                return headerSize
            }
        }
        return nil
    }
}
