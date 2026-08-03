import Foundation

/// Installs / removes the Dev Island hook entries for any registered local
/// agent, driven entirely by its `LocalAgentDescriptor`.
///
/// The hook is a `curl` one-liner that forwards the JSON payload the agent
/// pipes on stdin to `LocalHookServer`. It is deliberately fire-and-forget
/// (`-m 2`, trailing `|| true`, output discarded) so a stopped or crashed
/// Dev Island can never block or fail an agent's turn.
///
/// JSON surgery is delegated to `HookConfigEditor`: existing user hooks and
/// unknown config keys are preserved, and our entries are recognized by the
/// endpoint marker inside the command string, making install idempotent and
/// uninstall surgical.
public struct LocalHooksInstaller: Sendable {

    /// The port `LocalHookServer` binds on 127.0.0.1.
    public static let defaultPort = 7824

    public let descriptor: LocalAgentDescriptor

    public init(_ descriptor: LocalAgentDescriptor) {
        self.descriptor = descriptor
    }

    public func hookCommand(port: Int = Self.defaultPort) -> String {
        "curl -sf -m 2 -X POST http://127.0.0.1:\(port)\(descriptor.endpointPath) "
            + "-H 'Content-Type: application/json' --data-binary @- >/dev/null 2>&1 || true"
    }

    /// Installed = every event we need carries our command.
    public func isInstalled(configURL: URL? = nil) -> Bool {
        HookConfigEditor.isInstalled(
            at: configURL ?? descriptor.configURL,
            events: descriptor.hookEvents,
            marker: descriptor.endpointPath
        )
    }

    public func install(configURL: URL? = nil, port: Int = Self.defaultPort) throws {
        let command = hookCommand(port: port)
        let group: [String: Any]
        var rootDefaults: [String: Any] = [:]

        switch descriptor.hookEntryStyle {
        case .nestedWithEmptyMatcher:
            group = [
                "matcher": "",
                "hooks": [["type": "command", "command": command]],
            ]
        case .nested:
            group = ["hooks": [["type": "command", "command": command]]]
        case .flatVersioned:
            group = ["command": command]
            rootDefaults = ["version": 1]
        }

        try HookConfigEditor.install(
            at: configURL ?? descriptor.configURL,
            events: descriptor.hookEvents,
            group: group,
            marker: descriptor.endpointPath,
            rootDefaults: rootDefaults
        )
    }

    public func uninstall(configURL: URL? = nil) throws {
        try HookConfigEditor.uninstall(
            at: configURL ?? descriptor.configURL,
            marker: descriptor.endpointPath
        )
    }
}
