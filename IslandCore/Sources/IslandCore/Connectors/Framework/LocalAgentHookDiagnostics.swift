import Foundation

/// Read-only health of the Dev Island entries inside one local Agent's
/// configuration. This is intentionally separate from `LocalHookServiceStatus`:
/// a Hook can be installed while the loopback listener is offline, and the
/// listener can be healthy while no Agent has been connected yet.
public enum LocalAgentHookConnectionState: String, Equatable, Sendable {
    case connected
    /// The exact managed definition is present, but the vendor has a separate
    /// activation/trust gate that Dev Island cannot verify from config alone.
    case configured
    case updateRequired = "update-required"
    case disconnected
}

/// Low-cardinality, privacy-safe status for one registry entry.
///
/// Config paths and file contents are deliberately absent so this value can
/// be shown in Support diagnostics without exposing a username or workspace.
public struct LocalAgentHookConnection: Equatable, Sendable {
    public let source: String
    public let displayName: String
    public let state: LocalAgentHookConnectionState

    public init(
        source: String,
        displayName: String,
        state: LocalAgentHookConnectionState
    ) {
        self.source = source
        self.displayName = displayName
        self.state = state
    }
}

/// One point-in-time, read-only view of all local Agent Hook connections.
public struct LocalAgentHookHealthSnapshot: Equatable, Sendable {
    public let agents: [LocalAgentHookConnection]

    public init(agents: [LocalAgentHookConnection]) {
        self.agents = agents
    }

    public var connectedCount: Int {
        agents.count { $0.state == .connected }
    }

    public var configuredCount: Int {
        agents.count { $0.state == .configured }
    }

    public var updateRequiredCount: Int {
        agents.count { $0.state == .updateRequired }
    }

    public var disconnectedCount: Int {
        agents.count { $0.state == .disconnected }
    }
}

/// Registry-driven Hook diagnostics used by the CLI, Welcome Tour, and
/// privacy-safe Support report. Evaluation only reads the known config files;
/// it never creates, repairs, logs, or rewrites them.
public enum LocalAgentHookDiagnostics {
    public static func snapshot() -> LocalAgentHookHealthSnapshot {
        snapshot(
            descriptors: LocalAgentRegistry.all,
            configURLsBySource: [:],
            verifiedActivatedSources: []
        )
    }

    /// Resolves vendor-owned activation gates through documented, read-only
    /// protocol surfaces. Any unavailable executable, timeout, schema drift,
    /// parse error, disabled Hook, or non-trusted definition stays
    /// conservatively `configured`.
    public static func snapshotResolvingVendorActivation() -> LocalAgentHookHealthSnapshot {
        let codexInstaller = LocalHooksInstaller(.codex)
        let verified: Set<String>
        if codexInstaller.isInstalled(), CodexHookTrustProbe().verifiesCurrentInstall() {
            verified = [LocalAgentDescriptor.codex.source]
        } else {
            verified = []
        }
        return snapshot(
            descriptors: LocalAgentRegistry.all,
            configURLsBySource: [:],
            verifiedActivatedSources: verified
        )
    }

    // Internal injection keeps tests hermetic without putting filesystem
    // paths into the public diagnostic model.
    static func snapshot(
        descriptors: [LocalAgentDescriptor],
        configURLsBySource: [String: URL],
        verifiedActivatedSources: Set<String> = []
    ) -> LocalAgentHookHealthSnapshot {
        let agents = descriptors.map { descriptor in
            let installer = LocalHooksInstaller(descriptor)
            let configURL = configURLsBySource[descriptor.source]
            let state: LocalAgentHookConnectionState

            if installer.isInstalled(configURL: configURL) {
                switch descriptor.hookActivationRequirement {
                case .none:
                    state = .connected
                case .reviewInAgent:
                    state = verifiedActivatedSources.contains(descriptor.source)
                        ? .connected
                        : .configured
                }
            } else if installer.requiresUpdate(configURL: configURL) {
                state = .updateRequired
            } else {
                state = .disconnected
            }

            return LocalAgentHookConnection(
                source: descriptor.source,
                displayName: descriptor.displayName,
                state: state
            )
        }
        return LocalAgentHookHealthSnapshot(agents: agents)
    }
}
