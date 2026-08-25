import AppKit
import os

/// A semantic reason for keeping Dev Island in the Dock. Reasons are stored
/// per lease rather than as a set so two independent windows of the same kind
/// can never release each other's Dock presence.
public enum DockVisibilityReason: Equatable, Sendable {
    case settings
    case onboarding
    case debugSandbox
}

/// Opaque ownership token returned by `DockVisibilityCoordinator.acquire`.
/// The caller that opens a conventional flow owns its lease until the flow
/// finishes; order-out, miniaturize, notification handoff, and app
/// deactivation do not release it.
public struct DockVisibilityLease: Hashable, Sendable {
    fileprivate let id = UUID()
}

/// Converts conventional-window lifetimes into the app's activation policy.
///
/// Dev Island launches as an `LSUIElement` agent and normally remains an
/// `.accessory`. The first full-window lease promotes it to `.regular`, which
/// gives the window a Dock and Command-Tab identity. Releasing the final lease
/// returns it to the quiet menu-bar-only state.
@MainActor
public final class DockVisibilityCoordinator {
    public typealias PolicyApplier = @MainActor (
        NSApplication.ActivationPolicy
    ) -> Bool

    private let applyPolicy: PolicyApplier
    private var leases: [DockVisibilityLease: DockVisibilityReason] = [:]
    private var appliedPolicy: NSApplication.ActivationPolicy?
    private var retryID = UUID()
    private let maximumAutomaticRetries = 3
    private let logger = Logger(
        subsystem: "app.devisland.Island",
        category: "DockVisibility"
    )

    public init(
        applyPolicy: @escaping PolicyApplier = {
            NSApplication.shared.setActivationPolicy($0)
        }
    ) {
        self.applyPolicy = applyPolicy
    }

    public var desiredPolicy: NSApplication.ActivationPolicy {
        leases.isEmpty ? .accessory : .regular
    }

    /// Apply the current derived state. Launch calls this once after the
    /// always-on island window is ordered front, preserving AppKit's startup
    /// ordering requirement while avoiding a transient Dock icon.
    public func synchronize() {
        reconcile()
    }

    @discardableResult
    public func acquire(_ reason: DockVisibilityReason) -> DockVisibilityLease {
        let lease = DockVisibilityLease()
        leases[lease] = reason
        reconcile()
        return lease
    }

    public func release(_ lease: DockVisibilityLease) {
        guard leases.removeValue(forKey: lease) != nil else { return }
        reconcile()
    }

    private func reconcile(retryAttempt: Int = 0) {
        let policy = desiredPolicy
        guard appliedPolicy != policy else { return }

        if applyPolicy(policy) {
            retryID = UUID()
            appliedPolicy = policy
        } else {
            logger.error(
                "Could not apply activation policy rawValue=\(policy.rawValue, privacy: .public)"
            )
            guard retryAttempt < maximumAutomaticRetries else {
                logger.fault(
                    "Activation policy remained unapplied after \(retryAttempt + 1, privacy: .public) attempts rawValue=\(policy.rawValue, privacy: .public)"
                )
                return
            }

            // AppKit can reject a policy transform while it is finishing a
            // preceding activation change. Retry on a few bounded main-actor
            // turns; a generation token cancels stale retries after the lease
            // state changes, while the hard cap prevents a persistent loop.
            let scheduledRetryID = UUID()
            retryID = scheduledRetryID
            let delayMilliseconds = 16 << retryAttempt
            Task { @MainActor [weak self] in
                try? await Task.sleep(
                    for: .milliseconds(delayMilliseconds)
                )
                guard let self, self.retryID == scheduledRetryID else { return }
                self.reconcile(retryAttempt: retryAttempt + 1)
            }
        }
    }
}
