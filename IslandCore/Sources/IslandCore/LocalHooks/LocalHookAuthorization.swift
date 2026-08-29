import Darwin
import Foundation
import Security

/// Per-listener credential for state-changing local Agent Hook requests.
///
/// The fixed `X-Dev-Island-Hook` marker closes the browser simple-request
/// boundary. This independent random value closes the cross-user localhost
/// boundary: it is never embedded in Agent configuration, plugin source, or
/// process arguments, and is exposed only through a current-user `0600`
/// header file consumed at request time.
struct LocalHookAuthorization: Sendable {
    static let headerName = "X-Dev-Island-Authorization"
    static let versionPrefix = "v1."
    static let randomByteCount = 32
    static let encodedValueByteCount = versionPrefix.utf8.count + randomByteCount * 2

    private let valueBytes: [UInt8]

    init(headerValue: String) {
        let bytes = Array(headerValue.utf8)
        precondition(Self.isValid(bytes), "Local Hook authorization value is malformed")
        valueBytes = bytes
    }

    var headerValue: String {
        String(decoding: valueBytes, as: UTF8.self)
    }

    var headerFileData: Data {
        var data = Data(Self.headerName.utf8)
        data.append(contentsOf: [0x3A, 0x20]) // ": "
        data.append(contentsOf: valueBytes)
        data.append(0x0A)
        return data
    }

    /// Compare a public-length, fixed-alphabet credential without revealing
    /// a matching prefix through the ordinary short-circuiting String path.
    func matches(_ candidate: String?) -> Bool {
        guard let candidate else { return false }
        let candidateBytes = Array(candidate.utf8)
        guard candidateBytes.count == valueBytes.count else { return false }
        var difference: UInt8 = 0
        for index in valueBytes.indices {
            difference |= valueBytes[index] ^ candidateBytes[index]
        }
        return difference == 0
    }

    private static func isValid(_ bytes: [UInt8]) -> Bool {
        let prefix = Array(versionPrefix.utf8)
        guard bytes.count == encodedValueByteCount,
              bytes.starts(with: prefix) else { return false }
        return bytes.dropFirst(prefix.count).allSatisfy { byte in
            (0x30...0x39).contains(byte) || (0x61...0x66).contains(byte)
        }
    }
}

enum LocalHookAuthorizationStore {
    static let maximumHeaderFileBytes = 128
    static let relativeHeaderFilePath =
        "Library/Application Support/island-app/local-hook-authorization.header"
    static let shellHeaderFilePath = "${HOME}/\(relativeHeaderFilePath)"

    enum StoreError: Error {
        case applicationSupportUnavailable
        case randomGenerationFailed
        case unsafeCommittedFile
    }

    static var defaultHeaderFileURL: URL {
        get throws {
            guard let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw StoreError.applicationSupportUnavailable
            }
            return applicationSupport
                .appendingPathComponent("island-app", isDirectory: true)
                .appendingPathComponent("local-hook-authorization.header")
        }
    }

    /// Rotate before every serve-loop epoch. Hooks read the file for each
    /// request, so a restarted listener never needs to persist an old bearer
    /// value or rewrite user-owned Agent configuration.
    static func rotate(at url: URL? = nil) throws -> LocalHookAuthorization {
        let target = try url ?? defaultHeaderFileURL
        let authorization = try makeEphemeralAuthorization()
        let current = try ManagedConfigFile.snapshotIfExists(
            at: target,
            maximumBytes: maximumHeaderFileBytes
        )
        let committed = try ManagedConfigFile.replace(
            authorization.headerFileData,
            at: target,
            expecting: current.map(ManagedConfigFile.ExpectedState.snapshot) ?? .absent,
            permissions: ManagedConfigFile.privatePermissions,
            maximumBytes: maximumHeaderFileBytes
        )
        guard committed.permissions == ManagedConfigFile.privatePermissions,
              committed.data == authorization.headerFileData else {
            throw StoreError.unsafeCommittedFile
        }
        return authorization
    }

    /// Create a listener credential without reading or writing the persistent
    /// Header file. The production server immediately commits this value via
    /// `rotate(at:)`; isolated transport diagnostics inject it directly into
    /// a listener that exposes no Agent routes.
    static func makeEphemeralAuthorization() throws -> LocalHookAuthorization {
        var randomBytes = [UInt8](repeating: 0, count: LocalHookAuthorization.randomByteCount)
        let status = randomBytes.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw StoreError.randomGenerationFailed
        }
        defer {
            randomBytes.withUnsafeMutableBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return }
                _ = memset_s(baseAddress, bytes.count, 0, bytes.count)
            }
        }
        let suffix = randomBytes.map { String(format: "%02x", $0) }.joined()
        return LocalHookAuthorization(
            headerValue: LocalHookAuthorization.versionPrefix + suffix
        )
    }
}
