import Darwin
import Foundation

/// Filesystem ownership boundary for the private SQLite history store.
///
/// SQLite.swift does not currently expose `SQLITE_OPEN_NOFOLLOW`. This layer
/// therefore anchors both the final directory and database with no-follow
/// descriptors, performs entry operations relative to the directory anchor,
/// and verifies both path identities before schema or maintenance mutation.
enum SQLiteFileBoundary {
    static let privateDirectoryPermissions = 0o700
    static let privateFilePermissions = 0o600

    private static let sidecarSuffixes = ["-wal", "-shm", "-journal"]

    enum BoundaryError: LocalizedError {
        case invalidURL
        case unsafeDirectory
        case unsafeDatabase
        case unsafeSidecar
        case permissionUpdateFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "The local history database location is invalid."
            case .unsafeDirectory:
                return "The local history folder is not a private regular directory."
            case .unsafeDatabase:
                return "The local history path is not a private regular file."
            case .unsafeSidecar:
                return "A local history sidecar path is unsafe."
            case .permissionUpdateFailed:
                return "The local history permissions could not be made private."
            }
        }
    }

    struct PreparedDatabase {
        let url: URL
        fileprivate let directoryAnchor: OpenAnchor
        fileprivate let databaseAnchor: OpenAnchor
    }

    fileprivate struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t

        init(_ information: stat) {
            device = information.st_dev
            inode = information.st_ino
        }
    }

    fileprivate final class OpenAnchor {
        let descriptor: Int32
        let identity: FileIdentity

        init(descriptor: Int32, identity: FileIdentity) {
            self.descriptor = descriptor
            self.identity = identity
        }

        deinit {
            _ = Darwin.close(descriptor)
        }
    }

    static func prepare(at requestedURL: URL) throws -> PreparedDatabase {
        guard requestedURL.isFileURL else { throw BoundaryError.invalidURL }
        let url = requestedURL.standardizedFileURL
        guard !url.path.isEmpty, !url.path.utf8.contains(0) else {
            throw BoundaryError.invalidURL
        }

        let directory = url.deletingLastPathComponent()
        let directoryAnchor = try preparePrivateDirectory(directory)
        try secureExistingSidecars(
            for: url,
            directoryDescriptor: directoryAnchor.descriptor
        )
        try verifyDirectoryIdentity(
            at: directory,
            expected: directoryAnchor.identity
        )

        let prepared = PreparedDatabase(
            url: url,
            directoryAnchor: directoryAnchor,
            databaseAnchor: try openPrivateDatabaseFile(
                at: url,
                directoryDescriptor: directoryAnchor.descriptor
            )
        )
        try verify(prepared)
        return prepared
    }

    static func verify(_ prepared: PreparedDatabase) throws {
        try verifyDirectoryIdentity(
            at: prepared.url.deletingLastPathComponent(),
            expected: prepared.directoryAnchor.identity
        )
        try verifyDatabaseIdentity(
            at: prepared.url,
            expected: prepared.databaseAnchor.identity,
            directoryDescriptor: prepared.directoryAnchor.descriptor
        )
    }

    static func secureExistingSidecars(for prepared: PreparedDatabase) throws {
        try verify(prepared)
        try secureExistingSidecars(
            for: prepared.url,
            directoryDescriptor: prepared.directoryAnchor.descriptor
        )
        try verify(prepared)
    }

    private static func preparePrivateDirectory(_ directory: URL) throws -> OpenAnchor {
        guard directory.isFileURL,
              !directory.path.isEmpty,
              !directory.path.utf8.contains(0) else {
            throw BoundaryError.invalidURL
        }

        var information = stat()
        var result = directory.path.withCString { Darwin.lstat($0, &information) }
        if result != 0 {
            guard errno == ENOENT else { throw BoundaryError.unsafeDirectory }
            result = directory.path.withCString {
                Darwin.mkdir($0, mode_t(privateDirectoryPermissions))
            }
            guard result == 0 || errno == EEXIST else {
                throw BoundaryError.unsafeDirectory
            }
        }

        let descriptor = directory.path.withCString {
            Darwin.open(
                $0,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
            )
        }
        guard descriptor >= 0 else { throw BoundaryError.unsafeDirectory }

        var descriptorIsOpen = true
        defer {
            if descriptorIsOpen { _ = Darwin.close(descriptor) }
        }

        guard Darwin.fstat(descriptor, &information) == 0,
              information.st_mode & S_IFMT == S_IFDIR,
              information.st_uid == geteuid() else {
            throw BoundaryError.unsafeDirectory
        }
        guard Darwin.fchmod(
            descriptor,
            mode_t(privateDirectoryPermissions)
        ) == 0 else {
            throw BoundaryError.permissionUpdateFailed
        }

        let identity = FileIdentity(information)
        try verifyDirectoryIdentity(at: directory, expected: identity)
        descriptorIsOpen = false
        return OpenAnchor(descriptor: descriptor, identity: identity)
    }

    private static func openPrivateDatabaseFile(
        at url: URL,
        directoryDescriptor: Int32
    ) throws -> OpenAnchor {
        let name = try databaseFileName(for: url)
        try rejectUnsafeExistingFile(
            named: name,
            directoryDescriptor: directoryDescriptor,
            sidecar: false
        )

        let descriptor = name.withCString {
            Darwin.openat(
                directoryDescriptor,
                $0,
                O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK,
                mode_t(privateFilePermissions)
            )
        }
        guard descriptor >= 0 else { throw BoundaryError.unsafeDatabase }

        var descriptorIsOpen = true
        defer {
            if descriptorIsOpen { _ = Darwin.close(descriptor) }
        }

        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              information.st_mode & S_IFMT == S_IFREG,
              information.st_uid == geteuid(),
              information.st_nlink == 1 else {
            throw BoundaryError.unsafeDatabase
        }
        guard Darwin.fchmod(descriptor, mode_t(privateFilePermissions)) == 0 else {
            throw BoundaryError.permissionUpdateFailed
        }

        let identity = FileIdentity(information)
        try verifyDatabaseIdentity(
            at: url,
            expected: identity,
            directoryDescriptor: directoryDescriptor
        )
        descriptorIsOpen = false
        return OpenAnchor(descriptor: descriptor, identity: identity)
    }

    private static func verifyDirectoryIdentity(
        at directory: URL,
        expected: FileIdentity
    ) throws {
        var information = stat()
        guard directory.path.withCString({ Darwin.lstat($0, &information) }) == 0,
              information.st_mode & S_IFMT == S_IFDIR,
              information.st_uid == geteuid(),
              FileIdentity(information) == expected,
              Int(information.st_mode & 0o777) == privateDirectoryPermissions else {
            throw BoundaryError.unsafeDirectory
        }
    }

    private static func verifyDatabaseIdentity(
        at url: URL,
        expected: FileIdentity,
        directoryDescriptor: Int32
    ) throws {
        let name = try databaseFileName(for: url)
        var anchored = stat()
        guard name.withCString({ Darwin.fstatat(
            directoryDescriptor,
            $0,
            &anchored,
            AT_SYMLINK_NOFOLLOW
        ) }) == 0,
              anchored.st_mode & S_IFMT == S_IFREG,
              anchored.st_uid == geteuid(),
              anchored.st_nlink == 1,
              FileIdentity(anchored) == expected,
              Int(anchored.st_mode & 0o777) == privateFilePermissions else {
            throw BoundaryError.unsafeDatabase
        }

        var information = stat()
        guard url.path.withCString({ Darwin.lstat($0, &information) }) == 0,
              information.st_mode & S_IFMT == S_IFREG,
              information.st_uid == geteuid(),
              information.st_nlink == 1,
              FileIdentity(information) == expected,
              Int(information.st_mode & 0o777) == privateFilePermissions else {
            throw BoundaryError.unsafeDatabase
        }
    }

    private static func secureExistingSidecars(
        for databaseURL: URL,
        directoryDescriptor: Int32
    ) throws {
        let databaseName = try databaseFileName(for: databaseURL)
        for suffix in sidecarSuffixes {
            let sidecarName = databaseName + suffix
            try rejectUnsafeExistingFile(
                named: sidecarName,
                directoryDescriptor: directoryDescriptor,
                sidecar: true
            )

            let descriptor = sidecarName.withCString {
                Darwin.openat(
                    directoryDescriptor,
                    $0,
                    O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
                )
            }
            if descriptor < 0 {
                guard errno == ENOENT else { throw BoundaryError.unsafeSidecar }
                continue
            }
            defer { _ = Darwin.close(descriptor) }

            var information = stat()
            guard Darwin.fstat(descriptor, &information) == 0,
                  information.st_mode & S_IFMT == S_IFREG,
                  information.st_uid == geteuid(),
                  information.st_nlink == 1 else {
                throw BoundaryError.unsafeSidecar
            }
            guard Darwin.fchmod(
                descriptor,
                mode_t(privateFilePermissions)
            ) == 0 else {
                throw BoundaryError.permissionUpdateFailed
            }

            var verified = stat()
            guard sidecarName.withCString({ Darwin.fstatat(
                directoryDescriptor,
                $0,
                &verified,
                AT_SYMLINK_NOFOLLOW
            ) }) == 0,
                  verified.st_mode & S_IFMT == S_IFREG,
                  verified.st_uid == geteuid(),
                  verified.st_nlink == 1,
                  FileIdentity(verified) == FileIdentity(information),
                  Int(verified.st_mode & 0o777) == privateFilePermissions else {
                throw BoundaryError.unsafeSidecar
            }
        }
    }

    private static func rejectUnsafeExistingFile(
        named name: String,
        directoryDescriptor: Int32,
        sidecar: Bool
    ) throws {
        var information = stat()
        let result = name.withCString {
            Darwin.fstatat(
                directoryDescriptor,
                $0,
                &information,
                AT_SYMLINK_NOFOLLOW
            )
        }
        if result != 0 {
            guard errno == ENOENT else {
                throw sidecar ? BoundaryError.unsafeSidecar : BoundaryError.unsafeDatabase
            }
            return
        }
        guard information.st_mode & S_IFMT == S_IFREG,
              information.st_uid == geteuid(),
              information.st_nlink == 1 else {
            throw sidecar ? BoundaryError.unsafeSidecar : BoundaryError.unsafeDatabase
        }
    }

    private static func databaseFileName(for url: URL) throws -> String {
        let name = url.lastPathComponent
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.utf8.contains(0),
              !name.contains("/") else {
            throw BoundaryError.invalidURL
        }
        return name
    }
}
