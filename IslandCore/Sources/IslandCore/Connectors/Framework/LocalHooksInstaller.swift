import Foundation

/// Installs / removes the Dev Island hook entries for any registered local
/// agent, driven entirely by its `LocalAgentDescriptor`.
///
/// Hooks forward the JSON payload an agent pipes on stdin to
/// `LocalHookServer`. Lifecycle hooks are fire-and-forget (`-m 2`, output
/// discarded). Verified action hooks remain synchronous long enough for a
/// decision and preserve the server's stdout JSON for the agent.
///
/// Every command ends in `|| true`: if Dev Island is not running, the vendor
/// sees no decision and falls back to its normal approval UI instead of
/// failing or blocking the turn.
///
/// The fixed protocol Header is written into the managed definition, but the
/// per-listener random authorization value is not: curl loads it directly from
/// a current-user private Header file so neither configuration nor argv becomes
/// a bearer credential.
///
/// JSON surgery is delegated to `HookConfigEditor`: existing user hooks and
/// unknown config keys are preserved, and our entries are recognized by the
/// endpoint marker inside the command string, making install idempotent and
/// uninstall surgical.
public struct LocalHooksInstaller: Sendable {

    /// The port `LocalHookServer` binds on 127.0.0.1.
    public static let defaultPort = 7824

    /// Every state-changing loopback Hook request must carry this exact
    /// non-simple header. It is not a same-user authentication secret; its
    /// purpose is to force browser fetches through CORS preflight and to make
    /// ordinary HTML form POSTs fail closed at the listener.
    static let requestHeaderName = "X-Dev-Island-Hook"
    static let requestHeaderValue = "v1"

    public let descriptor: LocalAgentDescriptor

    public init(_ descriptor: LocalAgentDescriptor) {
        self.descriptor = descriptor
    }

    public func hookCommand(port: Int = Self.defaultPort) -> String {
        passiveHookCommand(port: port)
    }

    public func hookCommand(for event: String, port: Int = Self.defaultPort) -> String {
        guard descriptor.actionHookEvents.contains(event) else {
            return passiveHookCommand(port: port)
        }
        let curlTimeout = Int(AgentActionRequest.defaultTimeout) + 5
        return "curl --noproxy 127.0.0.1 -sf -m \(curlTimeout) -X POST http://127.0.0.1:\(port)\(descriptor.endpointPath) "
            + "-H 'Content-Type: application/json' \(requestContractHeader)\(requestAuthorizationHeader)\(terminalContextHeaders)"
            + "--data-binary @- 2>/dev/null || true"
    }

    private func passiveHookCommand(port: Int) -> String {
        "curl --noproxy 127.0.0.1 -sf -m 2 -X POST http://127.0.0.1:\(port)\(descriptor.endpointPath) "
            + "-H 'Content-Type: application/json' \(requestContractHeader)\(requestAuthorizationHeader)\(terminalContextHeaders)"
            + "--data-binary @- >/dev/null 2>&1 || true"
    }

    private var requestContractHeader: String {
        "-H '\(Self.requestHeaderName): \(Self.requestHeaderValue)' "
    }

    /// Curl reads the random credential from a private header file. The value
    /// therefore never enters Agent configuration or the process argument
    /// list, while a missing/stale file preserves the existing fail-open turn.
    private var requestAuthorizationHeader: String {
        "-H \"@\(LocalHookAuthorizationStore.shellHeaderFilePath)\" "
    }

    /// Capture only low-cardinality process-location metadata. Double-quoted
    /// shell expansions stay one curl argument; values are validated again at
    /// the HTTP boundary before they enter task state.
    private var terminalContextHeaders: String {
        guard descriptor.usesTerminalFallback else { return "" }
        return "-H \"X-Dev-Island-Terminal-Bundle: ${__CFBundleIdentifier:-}\" "
            + "-H \"X-Dev-Island-Terminal-Program: ${TERM_PROGRAM:-}\" "
            + "-H \"X-Dev-Island-TTY: $(/bin/ps -o tty= -p $$ | /usr/bin/tr -d '[:space:]')\" "
            + "-H \"X-Dev-Island-Tmux: ${TMUX:-}\" "
            + "-H \"X-Dev-Island-Tmux-Pane: ${TMUX_PANE:-}\" "
    }

    /// Installed = every event we need carries our command.
    public func isInstalled(configURL: URL? = nil) -> Bool {
        let url = configURL ?? descriptor.configURL
        if case .standaloneJavaScriptPlugin = descriptor.hookEntryStyle {
            return StandalonePluginFileEditor.isInstalled(
                at: url,
                expected: standalonePluginData(),
                marker: standalonePluginMarker
            )
        }
        if case .tomlArrayOfTables = descriptor.hookEntryStyle {
            return TomlHookConfigEditor.isInstalled(
                at: url,
                definitions: tomlDefinitions(),
                marker: descriptor.endpointPath
            )
        }
        let requiredRootValues: [String: Any]
        if case .flatVersioned = descriptor.hookEntryStyle {
            requiredRootValues = ["version": 1]
        } else {
            requiredRootValues = [:]
        }
        let commands = Dictionary(uniqueKeysWithValues: descriptor.hookEvents.map { event in
            (event, hookCommand(for: event))
        })
        let handlerTimeouts = Dictionary(uniqueKeysWithValues: descriptor.actionHookEvents.map {
            ($0, descriptor.actionHookTimeoutUnit.encoded(
                seconds: Int(AgentActionRequest.defaultTimeout) + 10
            ))
        })
        let statusMessages = Dictionary(uniqueKeysWithValues: descriptor.actionHookEvents.map {
            ($0, "Waiting for Dev Island")
        })
        return HookConfigEditor.isInstalled(
            at: url,
            commandsByEvent: commands,
            matchersByEvent: descriptor.hookMatchersByEvent,
            handlerTimeoutsByEvent: handlerTimeouts,
            handlerStatusMessagesByEvent: statusMessages,
            requiredRootValues: requiredRootValues,
            marker: descriptor.endpointPath
        )
    }

    /// True when Dev Island owns entries in this config, but they no longer
    /// match the current command set (for example, an older passive approval
    /// hook that needs the verified synchronous response command).
    public func requiresUpdate(configURL: URL? = nil) -> Bool {
        let url = configURL ?? descriptor.configURL
        return hasManagedEntries(configURL: url) && !isInstalled(configURL: url)
    }

    /// Any Dev Island endpoint marker, including a stale command version or
    /// an entry inside a malformed file. Used by bulk maintenance so Settings
    /// never declares "all disconnected" while a managed Hook remains.
    public func hasManagedEntries(configURL: URL? = nil) -> Bool {
        let url = configURL ?? descriptor.configURL
        if case .standaloneJavaScriptPlugin = descriptor.hookEntryStyle {
            return StandalonePluginFileEditor.containsManagedEntries(
                at: url,
                marker: standalonePluginMarker
            )
        }
        if case .tomlArrayOfTables = descriptor.hookEntryStyle {
            return TomlHookConfigEditor.containsManagedEntries(
                at: url,
                marker: descriptor.endpointPath
            )
        }
        return HookConfigEditor.containsManagedEntries(at: url, marker: descriptor.endpointPath)
    }

    public func install(configURL: URL? = nil, port: Int = Self.defaultPort) throws {
        let url = configURL ?? descriptor.configURL
        if case .standaloneJavaScriptPlugin = descriptor.hookEntryStyle {
            try StandalonePluginFileEditor.install(
                at: url,
                expected: standalonePluginData(port: port),
                marker: standalonePluginMarker
            )
            return
        }
        if case .tomlArrayOfTables = descriptor.hookEntryStyle {
            try TomlHookConfigEditor.install(
                at: url,
                definitions: tomlDefinitions(port: port),
                marker: descriptor.endpointPath
            )
            return
        }
        var rootDefaults: [String: Any] = [:]
        if case .flatVersioned = descriptor.hookEntryStyle {
            rootDefaults = ["version": 1]
        }

        let groupsByEvent = Dictionary(uniqueKeysWithValues: descriptor.hookEvents.map { event in
            (event, hookGroup(for: event, port: port))
        })

        try HookConfigEditor.install(
            at: url,
            groupsByEvent: groupsByEvent,
            marker: descriptor.endpointPath,
            rootDefaults: rootDefaults
        )
    }

    public func uninstall(configURL: URL? = nil) throws {
        let url = configURL ?? descriptor.configURL
        if case .standaloneJavaScriptPlugin = descriptor.hookEntryStyle {
            try StandalonePluginFileEditor.uninstall(
                at: url,
                marker: standalonePluginMarker
            )
        } else if case .tomlArrayOfTables = descriptor.hookEntryStyle {
            try TomlHookConfigEditor.uninstall(at: url, marker: descriptor.endpointPath)
        } else {
            try HookConfigEditor.uninstall(at: url, marker: descriptor.endpointPath)
        }
    }

    /// Build uninstall bytes without writing. Disconnect All uses this common
    /// entry point so JSON and TOML configs participate in the same
    /// prepare-first, compare-before-write, rollback-safe transaction.
    func preparedUninstall(
        from data: Data,
        at url: URL
    ) throws -> PreparedHookUninstall {
        if case .standaloneJavaScriptPlugin = descriptor.hookEntryStyle {
            return try StandalonePluginFileEditor.shouldRemoveManagedFile(
                from: data,
                at: url,
                marker: standalonePluginMarker
            ) ? .removeFile : .unchanged
        }
        if case .tomlArrayOfTables = descriptor.hookEntryStyle {
            return try TomlHookConfigEditor.preparedUninstall(
                from: data,
                at: url,
                marker: descriptor.endpointPath
            ).map(PreparedHookUninstall.replace) ?? .unchanged
        }
        return try HookConfigEditor.preparedUninstall(
            from: data,
            at: url,
            marker: descriptor.endpointPath
        ).map(PreparedHookUninstall.replace) ?? .unchanged
    }

    private func hookGroup(for event: String, port: Int) -> [String: Any] {
        let command = hookCommand(for: event, port: port)
        switch descriptor.hookEntryStyle {
        case .nestedWithEmptyMatcher:
            var handler: [String: Any] = ["type": "command", "command": command]
            if descriptor.actionHookEvents.contains(event) {
                handler["timeout"] = descriptor.actionHookTimeoutUnit.encoded(
                    seconds: Int(AgentActionRequest.defaultTimeout) + 10
                )
                handler["statusMessage"] = "Waiting for Dev Island"
            }
            return [
                "matcher": descriptor.hookMatchersByEvent[event] ?? "",
                "hooks": [handler],
            ]
        case .nested:
            var handler: [String: Any] = ["type": "command", "command": command]
            if descriptor.actionHookEvents.contains(event) {
                handler["timeout"] = descriptor.actionHookTimeoutUnit.encoded(
                    seconds: Int(AgentActionRequest.defaultTimeout) + 10
                )
                handler["statusMessage"] = "Waiting for Dev Island"
            }
            return ["hooks": [handler]]
        case .flatVersioned:
            return ["command": command]
        case .tomlArrayOfTables:
            preconditionFailure("TOML Hooks are rendered by TomlHookConfigEditor")
        case .standaloneJavaScriptPlugin:
            preconditionFailure("Standalone plugins are rendered by their descriptor")
        }
    }

    private func tomlDefinitions(port: Int = Self.defaultPort) -> [TomlHookDefinition] {
        descriptor.hookEvents.map { event in
            TomlHookDefinition(
                event: event,
                matcher: descriptor.hookMatchersByEvent[event],
                command: hookCommand(for: event, port: port),
                timeout: 5
            )
        }
    }

    private var standalonePluginMarker: String {
        "Dev Island managed local plugin: \(descriptor.source)"
    }

    private func standalonePluginData(port: Int = Self.defaultPort) -> Data {
        guard let renderer = descriptor.standalonePluginRenderer else {
            preconditionFailure("Standalone plugin renderer is missing")
        }
        return renderer(port)
    }
}

enum PreparedHookUninstall {
    case unchanged
    case replace(Data)
    case removeFile
}
