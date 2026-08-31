import CryptoKit
import Darwin
import Foundation

/// A low-cardinality, in-memory checklist for the one-time Manus v2 live
/// acceptance run. The CLI feeds this type only after `WebhookServer` has
/// authenticated and decoded a delivery.
///
/// Task and event identifiers are retained only long enough to correlate a
/// stopped event with a task created during the same run. They are never
/// exposed by `Snapshot` and are cleared when local transports stop.
public final class ManusLiveAcceptanceChecklist: @unchecked Sendable {
    public enum Observation: String, Sendable {
        case signedRegistrationProbe = "signed_registration_probe"
        case taskCreated = "task_created"
        case taskStoppedFinish = "task_stopped_finish"
        case taskStoppedAsk = "task_stopped_ask"
    }

    public struct Snapshot: Equatable, Sendable {
        public let trustAnchorValidated: Bool
        public let recoveryJournalPersisted: Bool
        public let registrationStarted: Bool
        public let signedRegistrationProbeObserved: Bool
        public let registrationAccepted: Bool
        public let taskCreatedObserved: Bool
        public let taskStoppedFinishObserved: Bool
        public let taskStoppedAskObserved: Bool
        public let webhookDeleted: Bool
        public let recoveryJournalCleared: Bool
        public let transportsStopped: Bool

        public var lifecycleComplete: Bool {
            trustAnchorValidated
                && recoveryJournalPersisted
                && signedRegistrationProbeObserved
                && registrationAccepted
                && taskCreatedObserved
                && taskStoppedFinishObserved
                && taskStoppedAskObserved
        }

        public var fullyAccepted: Bool {
            lifecycleComplete
                && webhookDeleted
                && recoveryJournalCleared
                && transportsStopped
        }
    }

    private let lock = NSLock()
    private var trustAnchorValidated = false
    private var recoveryJournalPersisted = false
    private var registrationStarted = false
    private var registrationInFlight = false
    private var signedRegistrationProbeObserved = false
    private var registrationAccepted = false
    private var taskCreatedObserved = false
    private var taskStoppedFinishObserved = false
    private var taskStoppedAskObserved = false
    private var webhookDeleted = false
    private var recoveryJournalCleared = false
    private var transportsStopped = false
    private var createdTaskIDs = Set<String>()

    public init() {}

    public func markTrustAnchorValidated() {
        lock.withLock {
            trustAnchorValidated = true
        }
    }

    public func beginRegistration() {
        lock.withLock {
            registrationStarted = true
            registrationInFlight = true
        }
    }

    public func markRecoveryJournalPersisted() {
        lock.withLock {
            recoveryJournalPersisted = true
        }
    }

    public func markRegistrationAccepted() {
        lock.withLock {
            registrationInFlight = false
            registrationAccepted = true
        }
    }

    public func markRegistrationFailed() {
        lock.withLock {
            registrationInFlight = false
        }
    }

    /// Records one already-authenticated delivery and returns only a safe
    /// category when it advances the checklist. No provider identifier or
    /// vendor-authored content crosses this boundary.
    @discardableResult
    public func record(_ payload: WebhookPayload) -> Observation? {
        lock.withLock {
            if registrationInFlight {
                guard !signedRegistrationProbeObserved else { return nil }
                signedRegistrationProbeObserved = true
                return .signedRegistrationProbe
            }

            guard registrationAccepted, !payload.taskId.isEmpty else {
                return nil
            }

            switch payload.data {
            case .created:
                createdTaskIDs.insert(payload.taskId)
                guard !taskCreatedObserved else { return nil }
                taskCreatedObserved = true
                return .taskCreated

            case .stopped(let stopped):
                // A late event from a task that predates this acceptance run
                // must not make the new integration appear complete.
                guard createdTaskIDs.contains(payload.taskId) else { return nil }
                switch stopped.stopReason {
                case .finish:
                    guard !taskStoppedFinishObserved else { return nil }
                    taskStoppedFinishObserved = true
                    return .taskStoppedFinish
                case .ask:
                    guard !taskStoppedAskObserved else { return nil }
                    taskStoppedAskObserved = true
                    return .taskStoppedAsk
                }
            }
        }
    }

    public func markWebhookDeleted() {
        lock.withLock {
            webhookDeleted = true
        }
    }

    public func markRecoveryJournalCleared() {
        lock.withLock {
            recoveryJournalCleared = true
        }
    }

    public func markTransportsStopped() {
        lock.withLock {
            transportsStopped = true
            createdTaskIDs.removeAll(keepingCapacity: false)
        }
    }

    public var snapshot: Snapshot {
        lock.withLock {
            Snapshot(
                trustAnchorValidated: trustAnchorValidated,
                recoveryJournalPersisted: recoveryJournalPersisted,
                registrationStarted: registrationStarted,
                signedRegistrationProbeObserved: signedRegistrationProbeObserved,
                registrationAccepted: registrationAccepted,
                taskCreatedObserved: taskCreatedObserved,
                taskStoppedFinishObserved: taskStoppedFinishObserved,
                taskStoppedAskObserved: taskStoppedAskObserved,
                webhookDeleted: webhookDeleted,
                recoveryJournalCleared: recoveryJournalCleared,
                transportsStopped: transportsStopped
            )
        }
    }
}

/// The only durable state created by the explicit live-account harness. It
/// contains no credential or callback URL: only a one-way callback digest, the
/// bounded request time, and provider IDs already proven to belong to that
/// request. A single versioned record makes SIGKILL recovery independent of
/// in-memory cleanup state.
public struct ManusLiveAcceptanceRecoveryRecord:
    Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public let version: Int
    public let callbackURLSHA256: String
    public let startedAtUnixSeconds: Int64
    public let webhookIDs: [String]

    init(
        version: Int = Self.schemaVersion,
        callbackURLSHA256: String,
        startedAtUnixSeconds: Int64,
        webhookIDs: [String]
    ) {
        self.version = version
        self.callbackURLSHA256 = callbackURLSHA256
        self.startedAtUnixSeconds = startedAtUnixSeconds
        self.webhookIDs = webhookIDs
    }
}

private enum ManusLiveAcceptanceJournalError: Error {
    case invalidPath
    case unsafeParent
    case unsafeFile
    case invalidRecord
    case ioFailure
}

/// A caller-supplied owner-private journal. The harness never invents a
/// persistent location: CLI and tests must pass an absolute path whose parent
/// already exists, is owned by this user, contains no symlink component, and
/// grants no access to group or other users.
///
/// macOS discretionary permissions cannot isolate two hostile processes that
/// already run as the same effective user. That capability is outside this
/// journal's boundary. Within the owner-private boundary, parent and file
/// descriptors are held across each mutation and observable identity swaps
/// fail closed before rename/unlink.
public struct ManusLiveAcceptanceRecoveryJournal: Sendable {
    public static let maximumBytes = 64 * 1_024
    public static let maximumWebhookIDs = 1_024

    private struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
        let owner: uid_t
        let mode: mode_t
        let links: nlink_t
        let size: off_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int

        init(_ metadata: stat) {
            device = metadata.st_dev
            inode = metadata.st_ino
            owner = metadata.st_uid
            mode = metadata.st_mode
            links = metadata.st_nlink
            size = metadata.st_size
            modifiedSeconds = metadata.st_mtimespec.tv_sec
            modifiedNanoseconds = metadata.st_mtimespec.tv_nsec
            changedSeconds = metadata.st_ctimespec.tv_sec
            changedNanoseconds = metadata.st_ctimespec.tv_nsec
        }
    }

    private struct ParentIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
        let owner: uid_t
        let mode: mode_t

        init(_ metadata: stat) {
            device = metadata.st_dev
            inode = metadata.st_ino
            owner = metadata.st_uid
            mode = metadata.st_mode
        }
    }

    private struct OpenedSnapshot {
        let record: ManusLiveAcceptanceRecoveryRecord
        let identity: FileIdentity
    }

    private let parentPath: String
    private let journalName: String

    public init(path: String) throws {
        guard !path.isEmpty,
              path.utf8.count <= 4_096,
              path.first == "/",
              !path.utf8.contains(0) else {
            throw ManusLiveAcceptanceJournalError.invalidPath
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.path == path,
              url.lastPathComponent != ".",
              url.lastPathComponent != ".." else {
            throw ManusLiveAcceptanceJournalError.invalidPath
        }
        let parent = url.deletingLastPathComponent().standardizedFileURL
        guard parent.path != "/",
              parent.resolvingSymlinksInPath().path == parent.path else {
            throw ManusLiveAcceptanceJournalError.unsafeParent
        }
        self.parentPath = parent.path
        self.journalName = url.lastPathComponent
        try validatePrivateParent()
        if let metadata = try Self.lstatIfPresent(path) {
            try Self.validateJournalMetadata(metadata)
        }
    }

    /// Read a descriptor-anchored snapshot. Missing means there is no recovery
    /// capability; malformed or mutable files throw and therefore fail closed.
    public func snapshot() throws -> ManusLiveAcceptanceRecoveryRecord? {
        let parentDescriptor = try openPrivateParentDirectory()
        defer { Darwin.close(parentDescriptor) }
        return try openedSnapshot(parentDescriptor: parentDescriptor)?.record
    }

    private func openedSnapshot(
        parentDescriptor: Int32
    ) throws -> OpenedSnapshot? {
        guard let pathMetadata = try Self.metadataIfPresent(
            parentDescriptor: parentDescriptor,
            name: journalName
        ) else { return nil }
        try Self.validateJournalMetadata(pathMetadata)

        let descriptor = journalName.withCString {
            Darwin.openat(
                parentDescriptor,
                $0,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW
            )
        }
        guard descriptor >= 0 else {
            throw ManusLiveAcceptanceJournalError.ioFailure
        }
        defer { Darwin.close(descriptor) }

        var openedMetadata = stat()
        guard fstat(descriptor, &openedMetadata) == 0 else {
            throw ManusLiveAcceptanceJournalError.ioFailure
        }
        try Self.validateJournalMetadata(openedMetadata)
        guard FileIdentity(pathMetadata) == FileIdentity(openedMetadata) else {
            throw ManusLiveAcceptanceJournalError.unsafeFile
        }

        let expectedCount = Int(openedMetadata.st_size)
        var bytes = [UInt8](repeating: 0, count: expectedCount)
        var offset = 0
        while offset < expectedCount {
            let count = bytes.withUnsafeMutableBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return -1 }
                return Darwin.read(
                    descriptor,
                    base.advanced(by: offset),
                    expectedCount - offset
                )
            }
            guard count > 0 else {
                throw ManusLiveAcceptanceJournalError.ioFailure
            }
            offset += count
        }
        var trailingByte: UInt8 = 0
        guard Darwin.read(descriptor, &trailingByte, 1) == 0 else {
            throw ManusLiveAcceptanceJournalError.unsafeFile
        }

        var finalMetadata = stat()
        guard fstat(descriptor, &finalMetadata) == 0,
              FileIdentity(openedMetadata) == FileIdentity(finalMetadata),
              let finalPathMetadata = try Self.metadataIfPresent(
                  parentDescriptor: parentDescriptor,
                  name: journalName
              ),
              FileIdentity(finalPathMetadata) == FileIdentity(finalMetadata) else {
            throw ManusLiveAcceptanceJournalError.unsafeFile
        }

        let record: ManusLiveAcceptanceRecoveryRecord
        do {
            record = try JSONDecoder().decode(
                ManusLiveAcceptanceRecoveryRecord.self,
                from: Data(bytes)
            )
        } catch {
            throw ManusLiveAcceptanceJournalError.invalidRecord
        }
        guard Self.isValid(record) else {
            throw ManusLiveAcceptanceJournalError.invalidRecord
        }
        return OpenedSnapshot(
            record: record,
            identity: FileIdentity(finalMetadata)
        )
    }

    /// Persist the callback identity before the registration request can leave
    /// the process. An existing record is never overwritten by a new run.
    public func beginRegistration(
        callbackURL: String,
        startedAtUnixSeconds: Int64 = max(
            0,
            Int64(Date.now.timeIntervalSince1970)
        )
    ) throws {
        guard try snapshot() == nil,
              let digest = Self.callbackURLSHA256(callbackURL),
              startedAtUnixSeconds >= 0 else {
            throw ManusLiveAcceptanceJournalError.invalidRecord
        }
        try write(
            ManusLiveAcceptanceRecoveryRecord(
                callbackURLSHA256: digest,
                startedAtUnixSeconds: startedAtUnixSeconds,
                webhookIDs: []
            ),
            replacing: nil
        )
    }

    /// Bind provider IDs before any accepted-registration checkpoint or delete
    /// call. This is idempotent only for the exact same already-bound set.
    public func bindWebhookIDs(_ identifiers: [String]) throws {
        guard let record = try snapshot(),
              !identifiers.isEmpty,
              identifiers.count <= Self.maximumWebhookIDs,
              Set(identifiers).count == identifiers.count,
              identifiers.allSatisfy({
                  ManusRemoteContentPolicy.isValidOpaqueIdentifier($0)
              }) else {
            throw ManusLiveAcceptanceJournalError.invalidRecord
        }
        if record.webhookIDs == identifiers { return }
        guard record.webhookIDs.isEmpty else {
            throw ManusLiveAcceptanceJournalError.invalidRecord
        }
        try write(
            ManusLiveAcceptanceRecoveryRecord(
                callbackURLSHA256: record.callbackURLSHA256,
                startedAtUnixSeconds: record.startedAtUnixSeconds,
                webhookIDs: identifiers
            ),
            replacing: record
        )
    }

    /// Remove the exact validated journal only after every provider delete has
    /// succeeded (including the client's strict idempotent not_found case).
    public func clear() throws {
        let parentDescriptor = try openPrivateParentDirectory()
        defer { Darwin.close(parentDescriptor) }
        guard let opened = try openedSnapshot(
            parentDescriptor: parentDescriptor
        ) else { return }
        guard let currentMetadata = try Self.metadataIfPresent(
                  parentDescriptor: parentDescriptor,
                  name: journalName
              ),
              FileIdentity(currentMetadata) == opened.identity else {
            throw ManusLiveAcceptanceJournalError.unsafeFile
        }
        let result = journalName.withCString {
            Darwin.unlinkat(parentDescriptor, $0, 0)
        }
        guard result == 0,
              try Self.metadataIfPresent(
                  parentDescriptor: parentDescriptor,
                  name: journalName
              ) == nil,
              Darwin.fsync(parentDescriptor) == 0 else {
            throw ManusLiveAcceptanceJournalError.ioFailure
        }
    }

    private func write(
        _ record: ManusLiveAcceptanceRecoveryRecord,
        replacing expectedRecord: ManusLiveAcceptanceRecoveryRecord?
    ) throws {
        guard Self.isValid(record) else {
            throw ManusLiveAcceptanceJournalError.invalidRecord
        }
        let parentDescriptor = try openPrivateParentDirectory()
        defer { Darwin.close(parentDescriptor) }
        let existing = try openedSnapshot(parentDescriptor: parentDescriptor)
        guard existing?.record == expectedRecord else {
            throw ManusLiveAcceptanceJournalError.invalidRecord
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        guard !data.isEmpty, data.count <= Self.maximumBytes else {
            throw ManusLiveAcceptanceJournalError.invalidRecord
        }

        let temporaryName = ".manus-live-journal-"
            + UUID().uuidString + ".tmp"
        var temporaryExists = false
        defer {
            if temporaryExists {
                _ = temporaryName.withCString {
                    Darwin.unlinkat(parentDescriptor, $0, 0)
                }
            }
        }
        let descriptor = temporaryName.withCString {
            Darwin.openat(
                parentDescriptor,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            throw ManusLiveAcceptanceJournalError.ioFailure
        }
        temporaryExists = true
        var writeError: Error?
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(
                    descriptor,
                    base.advanced(by: offset),
                    buffer.count - offset
                )
                if count <= 0 {
                    writeError = ManusLiveAcceptanceJournalError.ioFailure
                    return
                }
                offset += count
            }
        }
        if writeError == nil, fsync(descriptor) != 0 {
            writeError = ManusLiveAcceptanceJournalError.ioFailure
        }
        var writtenMetadata = stat()
        if writeError == nil,
           (fstat(descriptor, &writtenMetadata) != 0
                || writtenMetadata.st_size != data.count) {
            writeError = ManusLiveAcceptanceJournalError.ioFailure
        }
        guard Darwin.close(descriptor) == 0, writeError == nil else {
            throw writeError ?? ManusLiveAcceptanceJournalError.ioFailure
        }
        try Self.validateJournalMetadata(writtenMetadata)
        let currentIdentity = try Self.metadataIfPresent(
            parentDescriptor: parentDescriptor,
            name: journalName
        ).map(FileIdentity.init)
        guard currentIdentity == existing?.identity else {
            throw ManusLiveAcceptanceJournalError.unsafeFile
        }
        guard temporaryName.withCString({ source in
            journalName.withCString { destination in
                Darwin.renameat(
                    parentDescriptor,
                    source,
                    parentDescriptor,
                    destination
                )
            }
        }) == 0,
        Darwin.fsync(parentDescriptor) == 0 else {
            throw ManusLiveAcceptanceJournalError.ioFailure
        }
        temporaryExists = false
        guard try snapshot() == record else {
            throw ManusLiveAcceptanceJournalError.ioFailure
        }
    }

    private func validatePrivateParent() throws {
        let descriptor = try openPrivateParentDirectory()
        guard Darwin.close(descriptor) == 0 else {
            throw ManusLiveAcceptanceJournalError.ioFailure
        }
    }

    /// Keep the checked directory open across rename/unlink and directory
    /// `fsync`, so a path replacement cannot redirect the durable mutation.
    private func openPrivateParentDirectory() throws -> Int32 {
        guard parentPath.resolvingFileSymlinks() == parentPath,
              let pathMetadata = try Self.lstatIfPresent(parentPath) else {
            throw ManusLiveAcceptanceJournalError.unsafeParent
        }
        try Self.validatePrivateParentMetadata(pathMetadata)

        let descriptor = parentPath.withCString {
            Darwin.open(
                $0,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_DIRECTORY
            )
        }
        guard descriptor >= 0 else {
            throw ManusLiveAcceptanceJournalError.unsafeParent
        }
        do {
            var openedMetadata = stat()
            guard Darwin.fstat(descriptor, &openedMetadata) == 0 else {
                throw ManusLiveAcceptanceJournalError.ioFailure
            }
            try Self.validatePrivateParentMetadata(openedMetadata)
            guard ParentIdentity(pathMetadata) == ParentIdentity(openedMetadata),
                  parentPath.resolvingFileSymlinks() == parentPath,
                  let finalPathMetadata = try Self.lstatIfPresent(parentPath),
                  ParentIdentity(finalPathMetadata)
                    == ParentIdentity(openedMetadata) else {
                throw ManusLiveAcceptanceJournalError.unsafeParent
            }
            return descriptor
        } catch {
            _ = Darwin.close(descriptor)
            throw error
        }
    }

    private static func lstatIfPresent(_ path: String) throws -> stat? {
        var metadata = stat()
        let result = path.withCString { Darwin.lstat($0, &metadata) }
        if result == 0 { return metadata }
        if errno == ENOENT { return nil }
        throw ManusLiveAcceptanceJournalError.ioFailure
    }

    private static func metadataIfPresent(
        parentDescriptor: Int32,
        name: String
    ) throws -> stat? {
        var metadata = stat()
        let result = name.withCString {
            Darwin.fstatat(
                parentDescriptor,
                $0,
                &metadata,
                AT_SYMLINK_NOFOLLOW
            )
        }
        if result == 0 { return metadata }
        if errno == ENOENT { return nil }
        throw ManusLiveAcceptanceJournalError.ioFailure
    }

    private static func validatePrivateParentMetadata(
        _ metadata: stat
    ) throws {
        guard (metadata.st_mode & S_IFMT) == S_IFDIR,
              metadata.st_uid == geteuid(),
              metadata.st_nlink >= 1,
              (metadata.st_mode & 0o077) == 0 else {
            throw ManusLiveAcceptanceJournalError.unsafeParent
        }
    }

    private static func validateJournalMetadata(_ metadata: stat) throws {
        guard (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_uid == geteuid(),
              metadata.st_nlink == 1,
              (metadata.st_mode & 0o077) == 0,
              metadata.st_size > 0,
              metadata.st_size <= Self.maximumBytes else {
            throw ManusLiveAcceptanceJournalError.unsafeFile
        }
    }

    private static func isValid(
        _ record: ManusLiveAcceptanceRecoveryRecord
    ) -> Bool {
        record.version == ManusLiveAcceptanceRecoveryRecord.schemaVersion
            && record.callbackURLSHA256.count == 64
            && record.callbackURLSHA256.allSatisfy({
                "0123456789abcdef".contains($0)
            })
            && record.startedAtUnixSeconds >= 0
            && record.webhookIDs.count <= Self.maximumWebhookIDs
            && Set(record.webhookIDs).count == record.webhookIDs.count
            && record.webhookIDs.allSatisfy({
                ManusRemoteContentPolicy.isValidOpaqueIdentifier($0)
            })
    }

    static func callbackURLSHA256(_ value: String) -> String? {
        guard value.utf8.count <= 2_048,
              let components = URLComponents(string: value),
              components.scheme == "https",
              let host = components.host,
              !host.isEmpty,
              host == host.lowercased(),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              !components.path.isEmpty,
              components.url?.absoluteString == value else {
            return nil
        }
        return SHA256.hash(data: Data(value.utf8)).map {
            String(format: "%02x", $0)
        }.joined()
    }
}

private extension String {
    func resolvingFileSymlinks() -> String {
        URL(fileURLWithPath: self).resolvingSymlinksInPath().path
    }
}

/// Keeps malformed or terminal-control-bearing values out of the HTTP header
/// before a live acceptance request is attempted. Prefixes are deliberately
/// not pinned: the already-verified v1 account and current v2 documentation
/// use different example formats.
public enum ManusLiveAcceptanceCredential {
    public static let minimumLength = ManusCredentialPolicy.minimumLength
    public static let maximumLength = ManusCredentialPolicy.maximumLength

    public static func validated(_ candidate: String) -> String? {
        ManusCredentialPolicy.validated(candidate)
    }
}

/// Narrow, public seams for the one-time live acceptance harness. They are
/// intentionally separate from the shipping `TunnelManager` protocols: the
/// harness has stricter evidence and cleanup requirements and must remain
/// deterministic under cancellation tests.
public protocol ManusLiveAcceptanceClientProtocol: Sendable {
    func webhookPublicKey() async throws -> String
    func registerWebhook(publicURL: String) async throws -> String
    func listWebhooks() async throws -> [ManusWebhook]
    func deleteWebhook(id: String) async throws
}

public protocol ManusLiveAcceptanceServerProtocol: Sendable {
    func configure(externalURL: String, signaturePublicKeyPEM: String) async throws
    func start(onEvent: @escaping @Sendable (WebhookPayload) -> Void) async throws
    func stop() async
}

public protocol ManusLiveAcceptanceTunnelProtocol: Sendable {
    func start() async throws -> URL
    func stop() async
}

extension ManusAPIClient: ManusLiveAcceptanceClientProtocol {}
extension WebhookServer: ManusLiveAcceptanceServerProtocol {}
extension CloudflaredProcess: ManusLiveAcceptanceTunnelProtocol {}

public enum ManusLiveAcceptanceCheckpoint: String, Sendable {
    case trustAnchorValidated = "trust_anchor_validated"
    case serverStarted = "server_started"
    case tunnelStarted = "tunnel_started"
    case recoveryJournalPersisted = "recovery_journal_persisted"
    case registrationStarted = "registration_started"
    case signedRegistrationProbe = "signed_registration_probe"
    case registrationAccepted = "registration_accepted"
    case taskCreated = "task_created"
    case taskStoppedFinish = "task_stopped_finish"
    case taskStoppedAsk = "task_stopped_ask"
    case webhookDeleted = "webhook_deleted"
    case recoveryJournalValidated = "recovery_journal_validated"
    case recoveryInventoryChecked = "recovery_inventory_checked"
    case recoveryWebhookBound = "recovery_webhook_bound"
    case recoveryJournalCleared = "recovery_journal_cleared"
    case transportsStopped = "transports_stopped"
    case manualWebhookReviewRequired = "manual_webhook_review_required"
}

public enum ManusLiveAcceptanceFailureStage: String, Sendable {
    case trustAnchor = "trust_anchor"
    case serverStartup = "server_startup"
    case serverConfiguration = "server_configuration"
    case tunnelStartup = "tunnel_startup"
    case registration = "registration"
    case lifecycle = "lifecycle"
}

public enum ManusLiveAcceptanceTermination: Equatable, Sendable {
    case accepted
    case timedOut
    case cancelled
    case failed(ManusLiveAcceptanceFailureStage)
}

public struct ManusLiveAcceptanceReport: Equatable, Sendable {
    public let termination: ManusLiveAcceptanceTermination
    public let snapshot: ManusLiveAcceptanceChecklist.Snapshot
    public let manualWebhookReviewRequired: Bool

    public var accepted: Bool {
        termination == .accepted
            && snapshot.fullyAccepted
            && !manualWebhookReviewRequired
    }
}

public enum ManusLiveAcceptanceRecoveryResult: Equatable, Sendable {
    case recovered
    case noJournal
    case manualReviewRequired
}

/// Explicit recovery for a previous process that may have died at any point
/// after registration began. It never creates a server, tunnel, task, or new
/// webhook. An unbound attempt needs one and only one active, exact-digest row
/// inside the reviewed time window; every other outcome preserves the journal.
public actor ManusLiveAcceptanceRecoveryRunner {
    public typealias CheckpointHandler = @Sendable (
        ManusLiveAcceptanceCheckpoint
    ) -> Void

    private static let timestampToleranceSeconds: Int64 = 300

    private let client: any ManusLiveAcceptanceClientProtocol
    private let journal: ManusLiveAcceptanceRecoveryJournal
    private let checkpointHandler: CheckpointHandler

    public init(
        client: any ManusLiveAcceptanceClientProtocol,
        journal: ManusLiveAcceptanceRecoveryJournal,
        checkpointHandler: @escaping CheckpointHandler = { _ in }
    ) {
        self.client = client
        self.journal = journal
        self.checkpointHandler = checkpointHandler
    }

    public func recover() async -> ManusLiveAcceptanceRecoveryResult {
        let initialRecord: ManusLiveAcceptanceRecoveryRecord
        do {
            guard let record = try journal.snapshot() else { return .noJournal }
            initialRecord = record
        } catch {
            checkpointHandler(.manualWebhookReviewRequired)
            return .manualReviewRequired
        }
        checkpointHandler(.recoveryJournalValidated)

        var identifiers = initialRecord.webhookIDs
        if identifiers.isEmpty {
            let webhooks: [ManusWebhook]
            do {
                webhooks = try await client.listWebhooks()
            } catch {
                checkpointHandler(.manualWebhookReviewRequired)
                return .manualReviewRequired
            }
            checkpointHandler(.recoveryInventoryChecked)

            let lowerBound = max(
                0,
                initialRecord.startedAtUnixSeconds
                    - Self.timestampToleranceSeconds
            )
            let upper = initialRecord.startedAtUnixSeconds
                .addingReportingOverflow(Self.timestampToleranceSeconds)
            let upperBound = upper.overflow ? Int64.max : upper.partialValue
            let matches = webhooks.filter { webhook in
                webhook.status == .active
                    && webhook.createdAt >= lowerBound
                    && webhook.createdAt <= upperBound
                    && ManusLiveAcceptanceRecoveryJournal
                        .callbackURLSHA256(webhook.url)
                        == initialRecord.callbackURLSHA256
            }
            guard matches.count == 1 else {
                checkpointHandler(.manualWebhookReviewRequired)
                return .manualReviewRequired
            }
            identifiers = [matches[0].id]
            do {
                try journal.bindWebhookIDs(identifiers)
            } catch {
                checkpointHandler(.manualWebhookReviewRequired)
                return .manualReviewRequired
            }
            checkpointHandler(.recoveryWebhookBound)
        }

        for identifier in identifiers {
            do {
                try await client.deleteWebhook(id: identifier)
            } catch {
                checkpointHandler(.manualWebhookReviewRequired)
                return .manualReviewRequired
            }
        }
        checkpointHandler(.webhookDeleted)
        do {
            try journal.clear()
        } catch {
            checkpointHandler(.manualWebhookReviewRequired)
            return .manualReviewRequired
        }
        checkpointHandler(.recoveryJournalCleared)
        return .recovered
    }
}

/// Transactional runner for the explicit Manus live-account acceptance tool.
///
/// The runner never exposes provider identifiers, URLs, payload content or
/// vendor-authored errors. Any code path that may have created a remote
/// webhook enters a non-cancelled cleanup task before returning. A run that
/// cannot prove remote deletion is reported for manual account review.
public actor ManusLiveAcceptanceRunner {
    public typealias ServerFactory = @Sendable (
        _ trustAnchor: String
    ) -> (any ManusLiveAcceptanceServerProtocol)?
    public typealias TunnelFactory = @Sendable () -> any ManusLiveAcceptanceTunnelProtocol
    public typealias CheckpointHandler = @Sendable (ManusLiveAcceptanceCheckpoint) -> Void

    private enum RuntimeFailure: Error {
        case stage(ManusLiveAcceptanceFailureStage)
    }

    private let client: any ManusLiveAcceptanceClientProtocol
    private let journal: ManusLiveAcceptanceRecoveryJournal
    private let serverFactory: ServerFactory
    private let tunnelFactory: TunnelFactory
    private let checkpointHandler: CheckpointHandler
    private let checklist = ManusLiveAcceptanceChecklist()

    private var server: (any ManusLiveAcceptanceServerProtocol)?
    private var tunnel: (any ManusLiveAcceptanceTunnelProtocol)?
    private var webhookID: String?
    private var registrationAttempted = false
    private var registrationResultUncertain = false
    private var hasRun = false

    public init(
        client: any ManusLiveAcceptanceClientProtocol,
        journal: ManusLiveAcceptanceRecoveryJournal,
        serverFactory: @escaping ServerFactory = { trustAnchor in
            WebhookServer(port: 7823, signaturePublicKeyPEM: trustAnchor)
        },
        tunnelFactory: @escaping TunnelFactory = {
            CloudflaredProcess()
        },
        checkpointHandler: @escaping CheckpointHandler = { _ in }
    ) {
        self.client = client
        self.journal = journal
        self.serverFactory = serverFactory
        self.tunnelFactory = tunnelFactory
        self.checkpointHandler = checkpointHandler
    }

    public func run(timeout: Duration = .seconds(600)) async -> ManusLiveAcceptanceReport {
        guard !hasRun else {
            return ManusLiveAcceptanceReport(
                termination: .failed(.lifecycle),
                snapshot: checklist.snapshot,
                manualWebhookReviewRequired: registrationResultUncertain
            )
        }
        hasRun = true

        let termination: ManusLiveAcceptanceTermination
        do {
            do {
                guard try journal.snapshot() == nil else {
                    registrationResultUncertain = true
                    throw RuntimeFailure.stage(.lifecycle)
                }
            } catch let failure as RuntimeFailure {
                throw failure
            } catch {
                registrationResultUncertain = true
                throw RuntimeFailure.stage(.lifecycle)
            }
            try await prepareAndRegister()
            termination = try await waitForLifecycle(timeout: timeout)
        } catch is CancellationError {
            termination = .cancelled
        } catch let RuntimeFailure.stage(stage) {
            termination = .failed(stage)
        } catch {
            // No dynamic error description crosses the acceptance boundary.
            termination = .failed(.lifecycle)
        }

        // `Task.detached` is deliberate: SIGINT/SIGTERM cancels the run task,
        // but cancellation must never prevent deletion and transport stop.
        let cleanup = await Task.detached(priority: .userInitiated) {
            await self.cleanup()
        }.value

        let finalTermination: ManusLiveAcceptanceTermination
        if termination == .accepted, !cleanup.snapshot.fullyAccepted {
            finalTermination = .failed(.lifecycle)
        } else {
            finalTermination = termination
        }
        return ManusLiveAcceptanceReport(
            termination: finalTermination,
            snapshot: cleanup.snapshot,
            manualWebhookReviewRequired: cleanup.manualWebhookReviewRequired
        )
    }

    private func prepareAndRegister() async throws {
        let trustAnchor: String
        do {
            trustAnchor = try await client.webhookPublicKey()
        } catch {
            throw RuntimeFailure.stage(.trustAnchor)
        }
        try Task.checkCancellation()

        guard let server = serverFactory(trustAnchor) else {
            throw RuntimeFailure.stage(.trustAnchor)
        }
        self.server = server
        checklist.markTrustAnchorValidated()
        checkpointHandler(.trustAnchorValidated)

        let checklist = self.checklist
        let checkpointHandler = self.checkpointHandler
        do {
            try await server.start { payload in
                guard let observation = checklist.record(payload) else { return }
                switch observation {
                case .signedRegistrationProbe:
                    checkpointHandler(.signedRegistrationProbe)
                case .taskCreated:
                    checkpointHandler(.taskCreated)
                case .taskStoppedFinish:
                    checkpointHandler(.taskStoppedFinish)
                case .taskStoppedAsk:
                    checkpointHandler(.taskStoppedAsk)
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RuntimeFailure.stage(.serverStartup)
        }
        checkpointHandler(.serverStarted)
        try Task.checkCancellation()

        let tunnel = tunnelFactory()
        self.tunnel = tunnel
        let publicURL: URL
        do {
            publicURL = try await tunnel.start()
        } catch {
            throw RuntimeFailure.stage(.tunnelStartup)
        }
        checkpointHandler(.tunnelStarted)
        try Task.checkCancellation()

        let webhookURL = publicURL.appendingPathComponent("/webhook").absoluteString
        do {
            try await server.configure(
                externalURL: webhookURL,
                signaturePublicKeyPEM: trustAnchor
            )
        } catch {
            throw RuntimeFailure.stage(.serverConfiguration)
        }
        try Task.checkCancellation()

        do {
            try journal.beginRegistration(callbackURL: webhookURL)
        } catch {
            throw RuntimeFailure.stage(.registration)
        }
        checklist.markRecoveryJournalPersisted()
        checkpointHandler(.recoveryJournalPersisted)
        registrationAttempted = true
        checklist.beginRegistration()
        checkpointHandler(.registrationStarted)
        do {
            let identifier = try await client.registerWebhook(publicURL: webhookURL)
            webhookID = identifier
            do {
                try journal.bindWebhookIDs([identifier])
            } catch {
                checklist.markRegistrationFailed()
                registrationResultUncertain = true
                throw RuntimeFailure.stage(.registration)
            }
            checklist.markRegistrationAccepted()
            checkpointHandler(.registrationAccepted)
        } catch {
            checklist.markRegistrationFailed()
            registrationResultUncertain = true
            throw RuntimeFailure.stage(.registration)
        }
        try Task.checkCancellation()
    }

    private func waitForLifecycle(timeout: Duration) async throws -> ManusLiveAcceptanceTermination {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !checklist.snapshot.lifecycleComplete {
            try Task.checkCancellation()
            guard clock.now < deadline else { return .timedOut }
            try await Task.sleep(for: .milliseconds(100))
        }
        return .accepted
    }

    private func cleanup() async -> (
        snapshot: ManusLiveAcceptanceChecklist.Snapshot,
        manualWebhookReviewRequired: Bool
    ) {
        var requiresManualReview = false

        if let webhookID {
            do {
                try await client.deleteWebhook(id: webhookID)
                checklist.markWebhookDeleted()
                checkpointHandler(.webhookDeleted)
                do {
                    try journal.clear()
                    checklist.markRecoveryJournalCleared()
                    checkpointHandler(.recoveryJournalCleared)
                } catch {
                    requiresManualReview = true
                }
            } catch {
                requiresManualReview = true
            }
        } else if registrationAttempted || registrationResultUncertain {
            // Registration may have reached Manus even when the response was
            // lost. The explicit recovery command must reconcile this journal.
            requiresManualReview = true
        }

        if let tunnel { await tunnel.stop() }
        if let server { await server.stop() }
        checklist.markTransportsStopped()
        checkpointHandler(.transportsStopped)

        if requiresManualReview {
            checkpointHandler(.manualWebhookReviewRequired)
        }
        return (checklist.snapshot, requiresManualReview)
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}
