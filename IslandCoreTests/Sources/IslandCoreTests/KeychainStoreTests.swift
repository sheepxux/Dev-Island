import XCTest
@testable import IslandCore

final class KeychainStoreTests: XCTestCase {

    // Use a unique account key per test run to avoid cross-contamination
    // KeychainStore uses static service/account — we test the real Keychain
    // (macOS SPM test targets run without sandbox, so Keychain is accessible)

    override func setUp() {
        // Clean up any leftover value from a previous test run
        try? KeychainStore.delete()
    }

    override func tearDown() {
        try? KeychainStore.delete()
    }

    func testSaveAndLoad() throws {
        let value = "mk_live_test_key_12345"
        try KeychainStore.save(value)
        let loaded = try KeychainStore.load()
        XCTAssertEqual(loaded, value)
    }

    func testLoadReturnsNilWhenEmpty() throws {
        let loaded = try KeychainStore.load()
        XCTAssertNil(loaded)
    }

    func testSaveOverwritesExistingValue() throws {
        try KeychainStore.save("first_value")
        try KeychainStore.save("second_value")
        let loaded = try KeychainStore.load()
        XCTAssertEqual(loaded, "second_value")
    }

    func testDeleteRemovesValue() throws {
        try KeychainStore.save("to_be_deleted")
        try KeychainStore.delete()
        let loaded = try KeychainStore.load()
        XCTAssertNil(loaded)
    }

    func testDeleteWhenEmptyDoesNotThrow() {
        // Should not throw even when nothing is stored
        XCTAssertNoThrow(try KeychainStore.delete())
    }

    func testSaveAndLoadUnicodeValue() throws {
        let value = "mk_live_🔑_日本語_12345"
        try KeychainStore.save(value)
        let loaded = try KeychainStore.load()
        XCTAssertEqual(loaded, value)
    }

    func testSaveAndLoadEmptyString() throws {
        try KeychainStore.save("")
        let loaded = try KeychainStore.load()
        XCTAssertEqual(loaded, "")
    }
}
