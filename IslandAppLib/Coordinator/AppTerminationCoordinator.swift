import Foundation

/// The process role that owns an AppKit termination request.
///
/// Only the primary app owns live services that need a bounded graceful
/// shutdown. Launch-arbitration losers and hermetic QA processes must remain
/// side-effect free all the way through termination.
public enum AppTerminationMode: Equatable, Sendable {
    case owner
    case yieldedDuplicate
    case performanceQA
    case hermeticLaunchSmoke
}

/// AppKit-independent result used by the executable target to choose its
/// `NSApplication.TerminateReply` without putting AppKit in unit tests.
public enum AppTerminationDecision: Equatable, Sendable {
    case terminateNow
    case terminateLater
}

/// Pure policy boundary for the process-role bypasses.
public enum AppTerminationPolicy {
    public static func decision(
        for mode: AppTerminationMode
    ) -> AppTerminationDecision {
        switch mode {
        case .owner:
            return .terminateLater
        case .yieldedDuplicate, .performanceQA, .hermeticLaunchSmoke:
            return .terminateNow
        }
    }
}

/// Gives the primary app one bounded opportunity to finish service cleanup
/// before AppKit exits the process.
///
/// Cleanup and the hard timeout are deliberately launched as independent
/// unstructured tasks. A task group would wait for an unresponsive cleanup
/// child even after its timeout branch won, defeating the hard deadline.
@MainActor
public final class AppTerminationCoordinator {
    public typealias Cleanup = @MainActor () async -> Void
    public typealias Reply = @MainActor () -> Void

    typealias CleanupLauncher = @MainActor (
        _ operation: @escaping @MainActor () async -> Void
    ) -> Void
    typealias TimeoutScheduler = @MainActor (
        _ delayNanoseconds: UInt64,
        _ operation: @escaping @MainActor () -> Void
    ) -> Void

    public static let hardTimeoutNanoseconds: UInt64 = 2_000_000_000

    private let cleanupLauncher: CleanupLauncher
    private let timeoutScheduler: TimeoutScheduler
    private let timeoutNanoseconds: UInt64

    /// A coordinator represents one process lifetime, so its first owner
    /// request permanently owns the token. Keeping the token after replying
    /// prevents a repeated AppKit query from starting a second cleanup during
    /// the small interval before process exit.
    private var terminationToken: UUID?
    private var pendingReply: Reply?

    public init() {
        cleanupLauncher = Self.launchCleanup
        timeoutScheduler = Self.scheduleHardTimeout
        timeoutNanoseconds = Self.hardTimeoutNanoseconds
    }

    /// Deterministic seam for unit tests. Shipping always uses an independent
    /// cleanup task and the two-second hard timeout above.
    init(
        timeoutNanoseconds: UInt64,
        cleanupLauncher: @escaping CleanupLauncher,
        timeoutScheduler: @escaping TimeoutScheduler
    ) {
        self.cleanupLauncher = cleanupLauncher
        self.timeoutScheduler = timeoutScheduler
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    /// Starts at most one cleanup flight. Completion and timeout both attempt
    /// to finish the same token; only the first can consume `pendingReply`.
    @discardableResult
    public func requestTermination(
        mode: AppTerminationMode,
        cleanup: @escaping Cleanup,
        reply: @escaping Reply
    ) -> AppTerminationDecision {
        let decision = AppTerminationPolicy.decision(for: mode)
        guard decision == .terminateLater else { return decision }

        guard terminationToken == nil else {
            return .terminateLater
        }

        let token = UUID()
        terminationToken = token
        pendingReply = reply

        cleanupLauncher { [weak self] in
            await cleanup()
            self?.finish(token: token)
        }
        timeoutScheduler(timeoutNanoseconds) { [weak self] in
            self?.finish(token: token)
        }

        return .terminateLater
    }

    private func finish(token: UUID) {
        guard terminationToken == token,
              let reply = pendingReply else {
            return
        }
        pendingReply = nil
        reply()
    }

    private static func launchCleanup(
        _ operation: @escaping @MainActor () async -> Void
    ) {
        Task { @MainActor in
            await operation()
        }
    }

    private static func scheduleHardTimeout(
        _ delayNanoseconds: UInt64,
        _ operation: @escaping @MainActor () -> Void
    ) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            operation()
        }
    }
}
