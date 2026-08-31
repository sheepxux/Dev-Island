import Foundation
import Security

protocol KeychainStoreBackend: Sendable {
    func save(_ value: Data) throws
    func load() throws -> Data?
    func delete() throws
}

struct KeychainStoreClient: Sendable {
    private let backend: any KeychainStoreBackend

    init(backend: any KeychainStoreBackend) {
        self.backend = backend
    }

    func save(_ value: String) throws {
        try backend.save(Data(value.utf8))
    }

    func load() throws -> String? {
        guard let data = try backend.load() else { return nil }
        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainStore.KeychainError.unexpectedData
        }
        return value
    }

    func delete() throws {
        try backend.delete()
    }
}

enum KeychainStore {
    /// Keychain service identifier. Matches the bundle identifier so
    /// when the app is rebranded (com.island.app → app.devisland.Island)
    /// the Keychain entry's namespace tracks the change. Existing v0.1.0
    /// users will need to re-enter their API key after the rename — see
    /// Info.plist's CFBundleIdentifier comment.
    static let service    = "app.devisland.Island"
    static let accountKey = "manus_api_key"

    enum KeychainError: Error, Equatable, Sendable {
        case saveFailed(OSStatus)
        case loadFailed(OSStatus)
        case deleteFailed(OSStatus)
        case unexpectedData
    }

    private static let production = KeychainStoreClient(
        backend: KeychainStoreSecurityBackend(
            service: service,
            account: accountKey
        )
    )

    static func save(_ value: String) throws {
        try production.save(value)
    }

    static func load() throws -> String? {
        try production.load()
    }

    static func delete() throws {
        try production.delete()
    }
}

/// Shipping Security.framework adapter. Its query builders are pure/internal,
/// allowing the ordinary test suite to verify device-only, non-synchronizing
/// policy without opening or mutating the current user's login Keychain.
struct KeychainStoreSecurityBackend: KeychainStoreBackend {
    let service: String
    let account: String

    func save(_ value: Data) throws {
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            storedAttributes(for: value) as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            storedAttributes(for: value).forEach {
                addQuery[$0.key] = $0.value
            }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainStore.KeychainError.saveFailed(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainStore.KeychainError.saveFailed(updateStatus)
        }
    }

    func load() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainStore.KeychainError.loadFailed(status)
        }
        guard let data = result as? Data else {
            throw KeychainStore.KeychainError.unexpectedData
        }
        return data
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStore.KeychainError.deleteFailed(status)
        }
    }

    var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: false,
        ]
    }

    func storedAttributes(for value: Data) -> [CFString: Any] {
        [
            kSecValueData: value,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
    }
}
