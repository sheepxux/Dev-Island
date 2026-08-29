import Darwin
import Foundation

/// Descriptor-backed file boundary for user-owned Agent configuration files.
///
/// Managed Hook updates are explicit user actions, but the target path can
/// still change between the Settings check and the write. This boundary keeps
/// every read and atomic replacement anchored to one opened parent directory,
/// rejects links and non-regular files, bounds parsing input, and compares the
/// exact snapshot again immediately before commit.
enum ManagedConfigFile {
    static let maximumConfigBytes = 4 * 1_024 * 1_024
    static let privatePermissions = 0o600

    enum FileError: LocalizedError {
        case invalidPath(URL)
        case unsafeParent(URL)
        case unsafeFile(URL)
        case unreadableFile(URL)
        case fileTooLarge(URL)
        case configurationChanged(URL)
        case writeFailed(URL)

        var errorDescription: String? {
            switch self {
            case .invalidPath:
                return "The Agent configuration path is invalid."
            case .unsafeParent:
                return "The Agent configuration directory is not safe to edit."
            case .unsafeFile:
                return "The Agent configuration path is not a safe regular file."
            case .unreadableFile:
                return "The Agent configuration file could not be read safely."
            case .fileTooLarge:
                return "The Agent configuration file is too large to edit safely."
            case .configurationChanged:
                return "The Agent configuration changed during the update. No changes were made."
            case .writeFailed:
                return "The Agent configuration could not be written safely."
            }
        }
    }

    struct Snapshot {
        let data: Data
        let permissions: Int
        fileprivate let identity: Identity
    }

    enum ExpectedState {
        case absent
        case snapshot(Snapshot)
    }

    fileprivate struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    static func pathEntryExists(at url: URL) -> Bool {
        guard validatedPath(for: url) != nil else { return true }
        var information = stat()
        let result = url.path.withCString { path in
            lstat(path, &information)
        }
        return result == 0 || errno != ENOENT
    }

    static func snapshotIfExists(
        at url: URL,
        maximumBytes: Int = maximumConfigBytes
    ) throws -> Snapshot? {
        let path = try requireValidatedPath(for: url)
        let parentDescriptor: Int32
        do {
            parentDescriptor = try openParent(path.parent, createIfMissing: false)
        } catch FileError.unsafeParent {
            if !pathEntryExists(at: path.parent) { return nil }
            throw FileError.unsafeParent(path.parent)
        }
        defer { Darwin.close(parentDescriptor) }
        return try snapshotIfExists(
            in: parentDescriptor,
            name: path.name,
            url: url,
            maximumBytes: maximumBytes
        )
    }

    @discardableResult
    static func replace(
        _ data: Data,
        at url: URL,
        expecting expected: ExpectedState,
        permissions requestedPermissions: Int? = nil,
        maximumBytes: Int = maximumConfigBytes,
        beforeCommit: (() throws -> Void)? = nil
    ) throws -> Snapshot {
        guard data.count <= maximumBytes else { throw FileError.fileTooLarge(url) }
        let path = try requireValidatedPath(for: url)
        let parentDescriptor = try openParent(path.parent, createIfMissing: true)
        defer { Darwin.close(parentDescriptor) }

        let current = try snapshotIfExists(
            in: parentDescriptor,
            name: path.name,
            url: url,
            maximumBytes: maximumBytes
        )
        try require(expected, matches: current, at: url)

        let permissions = requestedPermissions
            ?? current?.permissions
            ?? privatePermissions
        let temporaryName = ".\(path.name).dev-island.\(UUID().uuidString).tmp"
        var temporaryExists = false
        defer {
            if temporaryExists {
                temporaryName.withCString { name in
                    _ = unlinkat(parentDescriptor, name, 0)
                }
            }
        }

        let temporaryDescriptor = temporaryName.withCString { name in
            openat(
                parentDescriptor,
                name,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                mode_t(privatePermissions)
            )
        }
        guard temporaryDescriptor >= 0 else { throw FileError.writeFailed(url) }
        temporaryExists = true

        let stagedIdentity: Identity
        do {
            defer { Darwin.close(temporaryDescriptor) }
            try writeAll(data, to: temporaryDescriptor, at: url)
            guard fchmod(temporaryDescriptor, mode_t(permissions & 0o777)) == 0,
                  fsync(temporaryDescriptor) == 0 else {
                throw FileError.writeFailed(url)
            }
            var stagedInformation = stat()
            guard fstat(temporaryDescriptor, &stagedInformation) == 0 else {
                throw FileError.writeFailed(url)
            }
            try validate(stagedInformation, at: url, maximumBytes: maximumBytes)
            stagedIdentity = identity(of: stagedInformation)
        }

        // Re-read through the anchored directory after staging. A link, hard
        // link, in-place mutation, or path replacement aborts before rename.
        let currentBeforeCommit = try snapshotIfExists(
            in: parentDescriptor,
            name: path.name,
            url: url,
            maximumBytes: maximumBytes
        )
        try require(expected, matches: currentBeforeCommit, at: url)
        try beforeCommit?()

        switch expected {
        case .absent:
            // Close the final absent-path race: a file created after our
            // second check is never overwritten.
            let renameResult = temporaryName.withCString { temporary in
                path.name.withCString { destination in
                    renameatx_np(
                        parentDescriptor,
                        temporary,
                        parentDescriptor,
                        destination,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
            guard renameResult == 0 else {
                if errno == EEXIST { throw FileError.configurationChanged(url) }
                throw FileError.writeFailed(url)
            }
            temporaryExists = false

        case .snapshot(let expectedSnapshot):
            // `renameat` would still overwrite a replacement created in the
            // tiny window after the second snapshot. Swap atomically instead:
            // the displaced file remains at our private staging name until we
            // prove it is the exact snapshot the editor prepared from.
            let swapResult = temporaryName.withCString { temporary in
                path.name.withCString { destination in
                    renameatx_np(
                        parentDescriptor,
                        temporary,
                        parentDescriptor,
                        destination,
                        UInt32(RENAME_SWAP)
                    )
                }
            }
            guard swapResult == 0 else { throw FileError.writeFailed(url) }

            do {
                let displaced = try snapshotIfExists(
                    in: parentDescriptor,
                    name: temporaryName,
                    url: url,
                    maximumBytes: maximumBytes
                )
                try require(.snapshot(expectedSnapshot), matches: displaced, at: url)
            } catch {
                // If the destination is still our staged inode, swapping back
                // restores the concurrent editor's exact file without loss.
                // If another writer has already superseded our inode, keep the
                // displaced file at the unpredictable staging path instead of
                // deleting or overwriting either writer's bytes.
                let restored = restoreAfterFailedSwap(
                    parentDescriptor: parentDescriptor,
                    temporaryName: temporaryName,
                    destinationName: path.name,
                    stagedIdentity: stagedIdentity,
                    stagedData: data,
                    url: url,
                    maximumBytes: maximumBytes
                )
                if restored { throw FileError.configurationChanged(url) }
                temporaryExists = false
                throw FileError.writeFailed(url)
            }

            let unlinkResult = temporaryName.withCString { name in
                unlinkat(parentDescriptor, name, 0)
            }
            guard unlinkResult == 0 else { throw FileError.writeFailed(url) }
            temporaryExists = false
        }
        guard fsync(parentDescriptor) == 0 else { throw FileError.writeFailed(url) }

        guard let committed = try snapshotIfExists(
            in: parentDescriptor,
            name: path.name,
            url: url,
            maximumBytes: maximumBytes
        ), committed.data == data else {
            throw FileError.writeFailed(url)
        }
        return committed
    }

    static func remove(
        at url: URL,
        expecting expected: Snapshot,
        maximumBytes: Int = maximumConfigBytes,
        beforeCommit: (() throws -> Void)? = nil
    ) throws {
        let path = try requireValidatedPath(for: url)
        let parentDescriptor = try openParent(path.parent, createIfMissing: false)
        defer { Darwin.close(parentDescriptor) }

        let current = try snapshotIfExists(
            in: parentDescriptor,
            name: path.name,
            url: url,
            maximumBytes: maximumBytes
        )
        try require(.snapshot(expected), matches: current, at: url)
        try beforeCommit?()

        // Move first, validate second, delete last. A plain `unlinkat` after
        // the snapshot check could delete a replacement written in the final
        // race window. The quarantine name is private to this operation and
        // stays on disk if a safe restore cannot be proven.
        let quarantineName = ".\(path.name).dev-island.\(UUID().uuidString).remove"
        let moveResult = path.name.withCString { name in
            quarantineName.withCString { quarantine in
                renameatx_np(
                    parentDescriptor,
                    name,
                    parentDescriptor,
                    quarantine,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard moveResult == 0 else {
            if errno == ENOENT { throw FileError.configurationChanged(url) }
            throw FileError.writeFailed(url)
        }
        do {
            let quarantined = try snapshotIfExists(
                in: parentDescriptor,
                name: quarantineName,
                url: url,
                maximumBytes: maximumBytes
            )
            try require(.snapshot(expected), matches: quarantined, at: url)
        } catch {
            let restored = restoreQuarantinedFile(
                parentDescriptor: parentDescriptor,
                quarantineName: quarantineName,
                destinationName: path.name
            )
            if restored { throw FileError.configurationChanged(url) }
            // Preserve the quarantined bytes when a new destination prevents
            // a non-overwriting restore. Manual review is safer than cleanup.
            throw FileError.writeFailed(url)
        }

        let unlinkResult = quarantineName.withCString { quarantine in
            unlinkat(parentDescriptor, quarantine, 0)
        }
        guard unlinkResult == 0 else { throw FileError.writeFailed(url) }
        guard fsync(parentDescriptor) == 0 else { throw FileError.writeFailed(url) }
    }

    /// Read-only compatibility probe. It may follow a final symlink only to
    /// keep an unsafe stale Dev Island marker visible as update-required;
    /// every mutating path above independently rejects it.
    static func boundedReadForManagedMarker(
        at url: URL,
        maximumBytes: Int = maximumConfigBytes
    ) -> Data? {
        let resolved = url.resolvingSymlinksInPath()
        let descriptor = resolved.path.withCString { path in
            Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }

        var information = stat()
        guard fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFREG,
              information.st_uid == geteuid(),
              information.st_size >= 0,
              information.st_size <= maximumBytes
        else { return nil }
        return try? readAll(
            from: descriptor,
            expectedSize: Int(information.st_size),
            maximumBytes: maximumBytes,
            at: url
        )
    }

    // MARK: - Descriptor internals

    private struct ValidatedPath {
        let parent: URL
        let name: String
    }

    private static func validatedPath(for url: URL) -> ValidatedPath? {
        guard url.isFileURL else { return nil }
        let standardized = url.standardizedFileURL
        let name = standardized.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
            return nil
        }
        // Config directories are commonly symlinked into a dotfiles tree.
        // Resolve that directory once, then anchor the concrete destination
        // descriptor; later link changes cannot redirect this operation.
        let configuredParent = standardized.deletingLastPathComponent()
        let parent = configuredParent.resolvingSymlinksInPath()
        if isSymbolicLink(at: configuredParent),
           !FileManager.default.fileExists(atPath: parent.path) {
            return nil
        }
        guard parent.path != standardized.path else { return nil }
        return ValidatedPath(parent: parent, name: name)
    }

    private static func isSymbolicLink(at url: URL) -> Bool {
        var information = stat()
        let result = url.path.withCString { path in
            lstat(path, &information)
        }
        return result == 0 && (information.st_mode & S_IFMT) == S_IFLNK
    }

    private static func requireValidatedPath(for url: URL) throws -> ValidatedPath {
        guard let path = validatedPath(for: url) else { throw FileError.invalidPath(url) }
        return path
    }

    private static func openParent(_ parent: URL, createIfMissing: Bool) throws -> Int32 {
        if createIfMissing {
            do {
                try FileManager.default.createDirectory(
                    at: parent,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                throw FileError.unsafeParent(parent)
            }
        }

        let descriptor = parent.path.withCString { path in
            Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else { throw FileError.unsafeParent(parent) }

        var information = stat()
        guard fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFDIR,
              information.st_uid == geteuid(),
              (information.st_mode & 0o022) == 0 else {
            Darwin.close(descriptor)
            throw FileError.unsafeParent(parent)
        }
        return descriptor
    }

    private static func snapshotIfExists(
        in parentDescriptor: Int32,
        name: String,
        url: URL,
        maximumBytes: Int
    ) throws -> Snapshot? {
        var pathInformation = stat()
        let status = name.withCString { filename in
            fstatat(parentDescriptor, filename, &pathInformation, AT_SYMLINK_NOFOLLOW)
        }
        if status != 0 {
            if errno == ENOENT { return nil }
            throw FileError.unreadableFile(url)
        }
        try validate(pathInformation, at: url, maximumBytes: maximumBytes)

        let descriptor = name.withCString { filename in
            openat(parentDescriptor, filename, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else { throw FileError.unsafeFile(url) }
        defer { Darwin.close(descriptor) }

        var openedInformation = stat()
        guard fstat(descriptor, &openedInformation) == 0 else {
            throw FileError.unreadableFile(url)
        }
        try validate(openedInformation, at: url, maximumBytes: maximumBytes)
        guard identity(of: pathInformation) == identity(of: openedInformation) else {
            throw FileError.configurationChanged(url)
        }

        let data = try readAll(
            from: descriptor,
            expectedSize: Int(openedInformation.st_size),
            maximumBytes: maximumBytes,
            at: url
        )

        var finalOpenedInformation = stat()
        var finalPathInformation = stat()
        let finalPathStatus = name.withCString { filename in
            fstatat(parentDescriptor, filename, &finalPathInformation, AT_SYMLINK_NOFOLLOW)
        }
        guard fstat(descriptor, &finalOpenedInformation) == 0,
              finalPathStatus == 0,
              identity(of: openedInformation) == identity(of: finalOpenedInformation),
              identity(of: openedInformation) == identity(of: finalPathInformation),
              finalOpenedInformation.st_size == data.count else {
            throw FileError.configurationChanged(url)
        }
        try validate(finalOpenedInformation, at: url, maximumBytes: maximumBytes)

        return Snapshot(
            data: data,
            permissions: Int(finalOpenedInformation.st_mode & 0o777),
            identity: identity(of: finalOpenedInformation)
        )
    }

    private static func validate(
        _ information: stat,
        at url: URL,
        maximumBytes: Int
    ) throws {
        guard (information.st_mode & S_IFMT) == S_IFREG,
              information.st_nlink == 1,
              information.st_uid == geteuid() else {
            throw FileError.unsafeFile(url)
        }
        guard information.st_size >= 0,
              information.st_size <= maximumBytes else {
            throw FileError.fileTooLarge(url)
        }
    }

    private static func identity(of information: stat) -> Identity {
        Identity(device: information.st_dev, inode: information.st_ino)
    }

    private static func restoreAfterFailedSwap(
        parentDescriptor: Int32,
        temporaryName: String,
        destinationName: String,
        stagedIdentity: Identity,
        stagedData: Data,
        url: URL,
        maximumBytes: Int
    ) -> Bool {
        guard let destination = try? snapshotIfExists(
            in: parentDescriptor,
            name: destinationName,
            url: url,
            maximumBytes: maximumBytes
        ), destination.identity == stagedIdentity,
           destination.data == stagedData else {
            return false
        }
        let result = temporaryName.withCString { temporary in
            destinationName.withCString { destination in
                renameatx_np(
                    parentDescriptor,
                    temporary,
                    parentDescriptor,
                    destination,
                    UInt32(RENAME_SWAP)
                )
            }
        }
        return result == 0 && fsync(parentDescriptor) == 0
    }

    private static func restoreQuarantinedFile(
        parentDescriptor: Int32,
        quarantineName: String,
        destinationName: String
    ) -> Bool {
        let result = quarantineName.withCString { quarantine in
            destinationName.withCString { destination in
                renameatx_np(
                    parentDescriptor,
                    quarantine,
                    parentDescriptor,
                    destination,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        return result == 0 && fsync(parentDescriptor) == 0
    }

    private static func require(
        _ expected: ExpectedState,
        matches current: Snapshot?,
        at url: URL
    ) throws {
        switch expected {
        case .absent:
            guard current == nil else { throw FileError.configurationChanged(url) }
        case .snapshot(let snapshot):
            guard let current,
                  current.identity == snapshot.identity,
                  current.data == snapshot.data else {
                throw FileError.configurationChanged(url)
            }
        }
    }

    private static func readAll(
        from descriptor: Int32,
        expectedSize: Int,
        maximumBytes: Int,
        at url: URL
    ) throws -> Data {
        var data = Data()
        data.reserveCapacity(expectedSize)
        var buffer = [UInt8](repeating: 0, count: 16 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw FileError.unreadableFile(url)
            }
            guard data.count <= maximumBytes - count else {
                throw FileError.fileTooLarge(url)
            }
            data.append(buffer, count: count)
        }
        guard data.count == expectedSize else { throw FileError.configurationChanged(url) }
        return data
    }

    private static func writeAll(_ data: Data, to descriptor: Int32, at url: URL) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(
                    descriptor,
                    bytes.baseAddress?.advanced(by: offset),
                    bytes.count - offset
                )
                if count < 0 {
                    if errno == EINTR { continue }
                    throw FileError.writeFailed(url)
                }
                guard count > 0 else { throw FileError.writeFailed(url) }
                offset += count
            }
        }
    }
}
