import Foundation
@testable import IslandCore

/// Hermetic secure-storage double shared by the commercial license tests.
/// It has no Security.framework dependency and never touches a login Keychain.
/// It also avoids preferences, HOME directories, and external services.
final class InMemoryCommercialLicenseDocumentStorage:
    CommercialLicenseDocumentStorageBackend,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var document: Data?

    init(document: Data? = nil) {
        self.document = document
    }

    func save(_ document: Data) throws {
        lock.lock()
        self.document = document
        lock.unlock()
    }

    func load() throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return document
    }

    func delete() throws {
        lock.lock()
        document = nil
        lock.unlock()
    }

    func replaceForTesting(with document: Data?) {
        lock.lock()
        self.document = document
        lock.unlock()
    }
}
