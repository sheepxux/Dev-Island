import Foundation
import Security

enum KeychainStore {
    /// Keychain service identifier. Matches the bundle identifier so
    /// when the app is rebranded (com.island.app → app.devisland.Island)
    /// the Keychain entry's namespace tracks the change. Existing v0.1.0
    /// users will need to re-enter their API key after the rename — see
    /// Info.plist's CFBundleIdentifier comment.
    static let service    = "app.devisland.Island"
    static let accountKey = "manus_api_key"

    enum KeychainError: Error {
        case saveFailed(OSStatus)
        case loadFailed(OSStatus)
        case deleteFailed(OSStatus)
        case unexpectedData
    }

    static func save(
        _ value: String,
        service: String = KeychainStore.service,
        account: String = KeychainStore.accountKey
    ) throws {
        let valueData = Data(value.utf8)
        let updateQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let updateAttribs: [CFString: Any] = [
            kSecValueData:     valueData,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttribs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = updateQuery
            addQuery[kSecValueData]      = valueData
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.saveFailed(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.saveFailed(updateStatus)
        }
    }

    static func load(
        service: String = KeychainStore.service,
        account: String = KeychainStore.accountKey
    ) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      account,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status)
        }
        guard let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return string
    }

    static func delete(
        service: String = KeychainStore.service,
        account: String = KeychainStore.accountKey
    ) throws {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}
