import XCTest
@testable import IslandCore

final class KeychainStoreTests: XCTestCase {

    // SPM tests access the real macOS Keychain. Use a unique service for every
    // test so the suite can never read, overwrite, or delete the app's stored
    // Manus API key.
    private var testService = ""
    private let testAccount = "manus_api_key"

    override func setUp() {
        testService = "app.devisland.Island.tests.\(UUID().uuidString)"
        // Clean up any leftover value from a previous test run
        try? KeychainStore.delete(service: testService, account: testAccount)
    }

    override func tearDown() {
        try? KeychainStore.delete(service: testService, account: testAccount)
    }

    func testSaveAndLoad() throws {
        let value = "mk_live_test_key_12345"
        try KeychainStore.save(value, service: testService, account: testAccount)
        let loaded = try KeychainStore.load(service: testService, account: testAccount)
        XCTAssertEqual(loaded, value)
    }

    func testLoadReturnsNilWhenEmpty() throws {
        let loaded = try KeychainStore.load(service: testService, account: testAccount)
        XCTAssertNil(loaded)
    }

    func testSaveOverwritesExistingValue() throws {
        try KeychainStore.save("first_value", service: testService, account: testAccount)
        try KeychainStore.save("second_value", service: testService, account: testAccount)
        let loaded = try KeychainStore.load(service: testService, account: testAccount)
        XCTAssertEqual(loaded, "second_value")
    }

    func testDeleteRemovesValue() throws {
        try KeychainStore.save("to_be_deleted", service: testService, account: testAccount)
        try KeychainStore.delete(service: testService, account: testAccount)
        let loaded = try KeychainStore.load(service: testService, account: testAccount)
        XCTAssertNil(loaded)
    }

    func testDeleteWhenEmptyDoesNotThrow() {
        // Should not throw even when nothing is stored
        XCTAssertNoThrow(try KeychainStore.delete(service: testService, account: testAccount))
    }

    func testSaveAndLoadUnicodeValue() throws {
        let value = "mk_live_🔑_日本語_12345"
        try KeychainStore.save(value, service: testService, account: testAccount)
        let loaded = try KeychainStore.load(service: testService, account: testAccount)
        XCTAssertEqual(loaded, value)
    }

    func testSaveAndLoadEmptyString() throws {
        try KeychainStore.save("", service: testService, account: testAccount)
        let loaded = try KeychainStore.load(service: testService, account: testAccount)
        XCTAssertEqual(loaded, "")
    }
}
