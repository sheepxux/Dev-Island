import Foundation
import Security
import XCTest
@testable import IslandCore

final class KeychainStoreTests: XCTestCase {
    private var storage: InMemoryKeychainStoreBackend!
    private var client: KeychainStoreClient!

    override func setUp() {
        storage = InMemoryKeychainStoreBackend()
        client = KeychainStoreClient(backend: storage)
    }

    override func tearDown() {
        client = nil
        storage = nil
    }

    func testSaveAndLoad() throws {
        let value = "mk_live_test_key_12345"
        try client.save(value)
        let loaded = try client.load()
        XCTAssertEqual(loaded, value)
    }

    func testLoadReturnsNilWhenEmpty() throws {
        let loaded = try client.load()
        XCTAssertNil(loaded)
    }

    func testSaveOverwritesExistingValue() throws {
        try client.save("first_value")
        try client.save("second_value")
        let loaded = try client.load()
        XCTAssertEqual(loaded, "second_value")
    }

    func testDeleteRemovesValue() throws {
        try client.save("to_be_deleted")
        try client.delete()
        let loaded = try client.load()
        XCTAssertNil(loaded)
    }

    func testDeleteWhenEmptyDoesNotThrow() {
        // Should not throw even when nothing is stored
        XCTAssertNoThrow(try client.delete())
    }

    func testSaveAndLoadUnicodeValue() throws {
        let value = "mk_live_🔑_日本語_12345"
        try client.save(value)
        let loaded = try client.load()
        XCTAssertEqual(loaded, value)
    }

    func testSaveAndLoadEmptyString() throws {
        try client.save("")
        let loaded = try client.load()
        XCTAssertEqual(loaded, "")
    }

    func testInvalidUTF8FailsClosedWithoutExposingBytes() {
        storage.replaceForTesting(with: Data([0xFF]))

        XCTAssertThrowsError(try client.load()) { error in
            XCTAssertEqual(error as? KeychainStore.KeychainError, .unexpectedData)
        }
    }

    func testShippingPolicyIsDeviceOnlyAndNonSynchronizing() {
        let value = Data("secret".utf8)
        let backend = KeychainStoreSecurityBackend(
            service: KeychainStore.service,
            account: KeychainStore.accountKey
        )
        let query = backend.baseQuery
        let attributes = backend.storedAttributes(for: value)

        XCTAssertEqual(
            query[kSecClass] as? String,
            kSecClassGenericPassword as String
        )
        XCTAssertEqual(query[kSecAttrService] as? String, KeychainStore.service)
        XCTAssertEqual(query[kSecAttrAccount] as? String, KeychainStore.accountKey)
        XCTAssertEqual(query[kSecAttrSynchronizable] as? Bool, false)
        XCTAssertEqual(attributes[kSecValueData] as? Data, value)
        XCTAssertEqual(
            attributes[kSecAttrAccessible] as? String,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
    }
}

private final class InMemoryKeychainStoreBackend:
    KeychainStoreBackend,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var value: Data?

    func save(_ value: Data) throws {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func load() throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func delete() throws {
        lock.lock()
        value = nil
        lock.unlock()
    }

    func replaceForTesting(with value: Data?) {
        lock.lock()
        self.value = value
        lock.unlock()
    }
}
