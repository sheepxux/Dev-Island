import Foundation

/// A bounded, log-safe secret accepted by the future commercial activation
/// flow. The raw value is deliberately private and is never returned by
/// `description` or `debugDescription`.
public struct CommercialActivationCode: Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    public static let minimumUTF8Bytes = 16
    public static let maximumUTF8Bytes = 128

    /// Copies of the value share one immutable allocation instead of creating
    /// additional secret-bearing `Data` values. The allocation is erased when
    /// its final owner is released.
    private let storage: CommercialActivationSecretStorage

    public init(_ value: String) throws {
        let bytes = value.utf8
        guard bytes.count >= Self.minimumUTF8Bytes,
              bytes.count <= Self.maximumUTF8Bytes else {
            throw CommercialActivationCodeError.invalidLength
        }
        guard bytes.allSatisfy(Self.isAllowedByte) else {
            throw CommercialActivationCodeError.invalidCharacters
        }
        storage = CommercialActivationSecretStorage(copying: bytes)
    }

    /// A scoped escape hatch for a reviewed transport implementation. It
    /// avoids publishing a reusable String/Data property and prevents the
    /// backing storage from escaping through the pointer itself.
    public func withUnsafeUTF8Bytes<Result>(
        _ body: (UnsafeBufferPointer<UInt8>) throws -> Result
    ) rethrows -> Result {
        try storage.withUnsafeBytes(body)
    }

    public var description: String { "<redacted activation code>" }
    public var debugDescription: String { description }

    private static func isAllowedByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x30...0x39, // 0-9
             0x41...0x5A, // A-Z
             0x61...0x7A, // a-z
             0x2D, 0x2E, 0x5F: // - . _
            return true
        default:
            return false
        }
    }
}

/// Dedicated immutable storage for accepted activation-code bytes.
///
/// Swift value copies retain this one allocation. Concurrent scoped reads are
/// safe because bytes never mutate during the allocation's lifetime; `deinit`
/// can only run after the final reference and all non-escaping reads are gone.
/// `memset_s` prevents the compiler from eliding the final erase immediately
/// before deallocation.
final class CommercialActivationSecretStorage: @unchecked Sendable {
    private let pointer: UnsafeMutablePointer<UInt8>
    private let count: Int

    init<Bytes: Collection>(copying bytes: Bytes) where Bytes.Element == UInt8 {
        precondition(!bytes.isEmpty)
        count = bytes.count
        pointer = .allocate(capacity: count)

        var destination = pointer
        for byte in bytes {
            destination.initialize(to: byte)
            destination = destination.advanced(by: 1)
        }
    }

    deinit {
        _ = Self.secureErase(
            UnsafeMutableBufferPointer(start: pointer, count: count)
        )
        pointer.deinitialize(count: count)
        pointer.deallocate()
    }

    func withUnsafeBytes<Result>(
        _ body: (UnsafeBufferPointer<UInt8>) throws -> Result
    ) rethrows -> Result {
        try body(UnsafeBufferPointer(start: pointer, count: count))
    }

    /// Internal so the exact primitive remains regression-testable without
    /// publishing a raw-value or manual-zeroization API to transport clients.
    @discardableResult
    static func secureErase(
        _ buffer: UnsafeMutableBufferPointer<UInt8>
    ) -> Bool {
        guard let baseAddress = buffer.baseAddress, !buffer.isEmpty else {
            return true
        }
        return memset_s(
            baseAddress,
            buffer.count,
            0,
            buffer.count
        ) == 0
    }
}

public enum CommercialActivationCodeError: Error, Equatable, Sendable {
    case invalidLength
    case invalidCharacters
}

/// Intentionally coarse server-side outcomes. Invalid, expired, redeemed, or
/// otherwise unusable codes share one case so the client contract cannot be
/// used as an account or entitlement oracle.
public enum CommercialActivationTransportRejection: Equatable, Sendable {
    case codeRejected
    case rateLimited
    case serviceUnavailable
}

/// The only values a provider-specific transport may return to the activation
/// core. Signed document bytes are untrusted until the offline verifier accepts
/// them and the verify-before-save store persists the exact same bytes.
public enum CommercialActivationTransportResponse: Equatable, Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case licenseDocument(Data)
    case rejected(CommercialActivationTransportRejection)

    public var description: String {
        switch self {
        case .licenseDocument:
            return "licenseDocument(<redacted>)"
        case .rejected(let rejection):
            return "rejected(\(rejection))"
        }
    }

    public var debugDescription: String { description }
}

/// Provider-neutral exchange boundary. It deliberately has no URL, account,
/// email, device identifier, payment metadata, or retry policy.
public protocol CommercialActivationTransport: Sendable {
    func exchange(
        activationCode: CommercialActivationCode
    ) async throws -> CommercialActivationTransportResponse
}

/// Low-cardinality client failures. Parser, CryptoKit, transport, Keychain,
/// and provider implementation errors never cross this boundary.
public enum CommercialLicenseActivationFailure: Equatable, Sendable {
    case commercialModeDisabled
    case transportUnavailable
    case licenseRejected
    case secureStorageUnavailable
}

public enum CommercialLicenseActivationOutcome: Equatable, Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case activated(VerifiedCommercialLicense)
    case rejected(CommercialActivationTransportRejection)
    case failed(CommercialLicenseActivationFailure)
    case superseded
    case cancelled

    public var description: String {
        switch self {
        case .activated:
            return "activated"
        case .rejected(let rejection):
            return "rejected(\(rejection))"
        case .failed(let failure):
            return "failed(\(failure))"
        case .superseded:
            return "superseded"
        case .cancelled:
            return "cancelled"
        }
    }

    public var debugDescription: String { description }
}

/// Coordinates one activation attempt at a time without enabling commercial
/// mode in the shipping app. Dependencies must be injected deliberately; the
/// app target still creates neither a trusted verifier nor a document store.
///
/// A newer activation supersedes and cancels the previous transport task.
/// Explicit cancellation and caller-task cancellation also invalidate the
/// operation, so a transport that returns late can never replace Keychain
/// state. The exact response is persisted only through `importDocument`, which
/// keeps verification and storage as one fail-closed boundary.
public actor CommercialLicenseActivationService {
    private let verifier: CommercialLicenseVerifier
    private let store: CommercialLicenseDocumentStore
    private let transport: any CommercialActivationTransport
    private let evaluationClock: @Sendable () -> Date

    private var nextOperationID: UInt64 = 0
    private var pendingOperation: PendingOperation?

    public init(
        verifier: CommercialLicenseVerifier,
        store: CommercialLicenseDocumentStore,
        transport: any CommercialActivationTransport
    ) {
        self.init(
            verifier: verifier,
            store: store,
            transport: transport,
            evaluationClock: { .now }
        )
    }

    /// Internal clock injection makes the response-time validity boundary
    /// deterministic in tests without publishing a caller-controlled time
    /// override in the commercial activation API.
    init(
        verifier: CommercialLicenseVerifier,
        store: CommercialLicenseDocumentStore,
        transport: any CommercialActivationTransport,
        evaluationClock: @escaping @Sendable () -> Date
    ) {
        self.verifier = verifier
        self.store = store
        self.transport = transport
        self.evaluationClock = evaluationClock
    }

    public func activate(
        code: CommercialActivationCode
    ) async -> CommercialLicenseActivationOutcome {
        // Fail before creating or invoking a transport task. This prevents an
        // inert/keyless build from consuming a one-time activation code.
        guard verifier.evaluate(document: nil, now: evaluationClock())
            != .commercialModeDisabled else {
            return .failed(.commercialModeDisabled)
        }

        if let previous = pendingOperation {
            previous.state.invalidate(as: .superseded)
            previous.task.cancel()
        }

        nextOperationID &+= 1
        let operationID = nextOperationID
        let state = OperationState()
        let transport = self.transport
        let transportTask = Task {
            try await transport.exchange(activationCode: code)
        }
        pendingOperation = PendingOperation(
            id: operationID,
            task: transportTask,
            state: state
        )

        let transportResult = await withTaskCancellationHandler {
            await transportTask.result
        } onCancel: {
            state.invalidate(as: .cancelled)
            transportTask.cancel()
        }

        if pendingOperation?.id == operationID {
            pendingOperation = nil
        }

        if let invalidation = state.currentInvalidation {
            switch invalidation {
            case .superseded:
                return .superseded
            case .cancelled:
                return .cancelled
            }
        }
        guard !Task.isCancelled else { return .cancelled }

        let response: CommercialActivationTransportResponse
        switch transportResult {
        case .success(let value):
            response = value
        case .failure:
            return .failed(.transportUnavailable)
        }

        switch response {
        case .rejected(let rejection):
            return .rejected(rejection)

        case .licenseDocument(let document):
            guard !document.isEmpty,
                  document.count <= CommercialLicenseDocumentStore.maximumDocumentBytes else {
                return .failed(.licenseRejected)
            }
            // Cancellation and commit share one lock-backed boundary. If
            // cancellation wins, no persistence begins; once commit is
            // claimed, the synchronous verify-before-save operation completes
            // atomically from the actor's perspective.
            guard state.claimCommit() else {
                switch state.currentInvalidation {
                case .superseded:
                    return .superseded
                case .cancelled, .none:
                    return .cancelled
                }
            }

            do {
                let evaluation = try store.importDocument(
                    document,
                    using: verifier,
                    now: evaluationClock()
                )
                switch evaluation {
                case .valid(let license):
                    return .activated(license)
                case .commercialModeDisabled:
                    return .failed(.commercialModeDisabled)
                case .missingDocument, .rejected:
                    return .failed(.licenseRejected)
                }
            } catch CommercialLicenseDocumentStoreError.rollbackRejected,
                    CommercialLicenseDocumentStoreError.conflictingGeneration {
                return .failed(.licenseRejected)
            } catch {
                return .failed(.secureStorageUnavailable)
            }
        }
    }

    /// Cancels and invalidates the current attempt. Even if a transport ignores
    /// cancellation and returns later, its operation state prevents saving.
    @discardableResult
    public func cancelPendingActivation() -> Bool {
        guard let pendingOperation else { return false }
        pendingOperation.state.invalidate(as: .cancelled)
        pendingOperation.task.cancel()
        self.pendingOperation = nil
        return true
    }
}

private extension CommercialLicenseActivationService {
    struct PendingOperation: Sendable {
        let id: UInt64
        let task: Task<CommercialActivationTransportResponse, Error>
        let state: OperationState
    }

    enum Invalidation: Sendable {
        case superseded
        case cancelled
    }

    final class OperationState: @unchecked Sendable {
        private let lock = NSLock()
        private var invalidation: Invalidation?
        private var commitClaimed = false

        var currentInvalidation: Invalidation? {
            lock.lock()
            defer { lock.unlock() }
            return invalidation
        }

        func invalidate(as reason: Invalidation) {
            lock.lock()
            defer { lock.unlock() }
            guard invalidation == nil, !commitClaimed else { return }
            invalidation = reason
        }

        func claimCommit() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard invalidation == nil, !commitClaimed else { return false }
            commitClaimed = true
            return true
        }
    }
}
