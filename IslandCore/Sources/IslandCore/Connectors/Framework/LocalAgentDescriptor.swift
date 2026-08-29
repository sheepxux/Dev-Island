import Foundation

/// Everything Dev Island needs to know about one local agent, in one table
/// row (contract v1.5.0, J3 — declarative connector framework).
///
/// The descriptor fully drives the four places an agent shows up:
/// - `LocalHooksInstaller` (config file path, subscribed events, entry shape)
/// - `LocalHookServer` (HTTP route + payload decoding)
/// - `LocalAgentConnector` (source label, display name)
/// - Settings UI and `SourceAppResolver` (row text, jump-back app targets)
///
/// Adding an agent = one descriptor + one payload mapping. No new server
/// route, no new connector actor, no Settings edit.
public struct LocalAgentDescriptor: Sendable {

    /// Stable source key: task `source`, logo asset key
    /// (`AgentLogo-<source>`), and hook endpoint (`/hooks/<source>`).
    public let source: String
    /// Human-readable name ("Claude Code").
    public let displayName: String
    /// Settings row subtitle shown while the integration is disabled.
    public let settingsSubtitle: String
    /// Product-readiness label shown in Settings. Preview connectors remain
    /// explicitly marked until their pinned real CLI passes the acceptance
    /// gates; code coverage alone never promotes them to stable.
    public let releaseStage: AgentReleaseStage
    /// Whether writing the managed Hook config is enough to describe the
    /// integration as connected. Some vendors add a separate trust gate after
    /// discovery; their exact trust state may only be available inside the
    /// vendor client, so Dev Island must stop at "configured" until the user
    /// reviews or confirms it there.
    public let hookActivationRequirement: HookActivationRequirement
    /// Hook config file, `~`-relative for display ("~/.claude/settings.json").
    public let configPath: String
    /// Hook event names to subscribe to, in the agent's own vocabulary.
    /// Keep in sync with the payload struct's `Kind`.
    public let hookEvents: [String]
    /// How a hook entry is shaped inside the config file.
    public let hookEntryStyle: HookEntryStyle
    /// Bundle IDs of the agent's own app(s), most specific first — used by
    /// `SourceAppResolver` for "jump back to session".
    public let appCandidates: [String]
    /// Whether CLI sessions of this agent live in a terminal, so resolver
    /// may fall back to activating a running terminal emulator.
    public let usesTerminalFallback: Bool
    /// Verified connector depth. UI controls are gated by this matrix rather
    /// than inferred from an event name.
    public let capabilities: AgentCapabilities
    /// Hook event names whose stdout is a synchronous vendor response.
    public let actionHookEvents: Set<String>
    /// Optional vendor matcher per event. This keeps high-frequency gates such
    /// as Claude Code `PreToolUse` scoped to the one tool Dev Island can
    /// actually answer instead of spawning a hook for every tool call.
    public let hookMatchersByEvent: [String: String]
    /// Unit used by this vendor for command-hook timeout values. Claude-style
    /// configs use seconds; Qwen Code's command hooks use milliseconds.
    public let actionHookTimeoutUnit: HookTimeoutUnit
    /// Decode one raw hook payload into a normalized event. `nil` means
    /// "drop silently" (undecodable body, or a payload without a usable
    /// session id).
    public let decodeEvent: @Sendable (Data) -> LocalAgentEvent?
    /// Decode a synchronous request the island can answer. `nil` for passive
    /// hooks and for connectors without a verified response protocol.
    public let decodeActionRequest: (@Sendable (Data) -> AgentActionRequest?)?
    /// Render the exact stdout JSON expected by the vendor hook. A `nil`
    /// response must decline to decide and preserve the vendor's own prompt.
    public let encodeActionResponse: (@Sendable (AgentActionResponse?) -> String)?
    /// Render a complete, dependency-free local plugin file for vendors whose
    /// integration surface is a plugin module rather than JSON/TOML command
    /// hooks. Only valid with `.standaloneJavaScriptPlugin`.
    public let standalonePluginRenderer: (@Sendable (Int) -> Data)?

    public init(
        source: String,
        displayName: String,
        settingsSubtitle: String,
        releaseStage: AgentReleaseStage = .stable,
        hookActivationRequirement: HookActivationRequirement = .none,
        configPath: String,
        hookEvents: [String],
        hookEntryStyle: HookEntryStyle,
        appCandidates: [String],
        usesTerminalFallback: Bool,
        capabilities: AgentCapabilities = .lifecycleOnly,
        actionHookEvents: Set<String> = [],
        hookMatchersByEvent: [String: String] = [:],
        actionHookTimeoutUnit: HookTimeoutUnit = .seconds,
        decodeActionRequest: (@Sendable (Data) -> AgentActionRequest?)? = nil,
        encodeActionResponse: (@Sendable (AgentActionResponse?) -> String)? = nil,
        standalonePluginRenderer: (@Sendable (Int) -> Data)? = nil,
        decodeEvent: @escaping @Sendable (Data) -> LocalAgentEvent?
    ) {
        // The source key travels into shell command strings (hook curl
        // one-liner), URL routes, and asset names. Constrain it to a safe
        // charset at construction so no downstream consumer ever needs to
        // escape it. Registry rows are code, so a violation is a
        // programmer error — crash loudly in development.
        // ASCII-only: Character.isNumber accepts Unicode numerals (①, ٢…),
        // which would leak into shell commands / routes / asset names.
        precondition(
            !source.isEmpty && source.utf8.allSatisfy {
                ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2D
            },
            "LocalAgentDescriptor.source must be lowercase ASCII alphanumerics/hyphens, got: \(source)"
        )
        self.source = source
        self.displayName = displayName
        self.settingsSubtitle = settingsSubtitle
        self.releaseStage = releaseStage
        self.hookActivationRequirement = hookActivationRequirement
        self.configPath = configPath
        self.hookEvents = hookEvents
        self.hookEntryStyle = hookEntryStyle
        self.appCandidates = appCandidates
        self.usesTerminalFallback = usesTerminalFallback
        self.capabilities = capabilities
        self.actionHookEvents = actionHookEvents
        self.hookMatchersByEvent = hookMatchersByEvent
        self.actionHookTimeoutUnit = actionHookTimeoutUnit
        self.decodeActionRequest = decodeActionRequest
        self.encodeActionResponse = encodeActionResponse
        switch hookEntryStyle {
        case .standaloneJavaScriptPlugin:
            precondition(
                standalonePluginRenderer != nil,
                "Standalone plugin descriptors require a renderer"
            )
        default:
            precondition(
                standalonePluginRenderer == nil,
                "Command-hook descriptors cannot carry a plugin renderer"
            )
        }
        self.standalonePluginRenderer = standalonePluginRenderer
        self.decodeEvent = decodeEvent
    }

    /// Local HTTP endpoint the hook command posts to.
    public var endpointPath: String { "/hooks/\(source)" }

    /// `configPath` with `~` expanded to the current user's home.
    public var configURL: URL {
        URL(fileURLWithPath: (configPath as NSString).expandingTildeInPath)
    }

    /// Shared payload decoding — the same decoder config for every agent
    /// (snake_case keys, as piped by the CLIs' hook commands).
    public static func decodePayload<E: Decodable>(_ data: Data) -> E? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(E.self, from: data)
    }
}

/// A vendor-owned activation step that happens after Dev Island has written a
/// valid Hook definition. The command is display-only guidance; Dev Island
/// never types it into, launches, or takes control of the vendor client.
public enum HookActivationRequirement: Equatable, Sendable {
    case none
    case reviewInAgent(command: String)

    public var reviewCommand: String? {
        guard case .reviewInAgent(let command) = self else { return nil }
        return command
    }
}

public enum AgentReleaseStage: String, Codable, Sendable {
    case stable
    case preview
}

public enum HookTimeoutUnit: Sendable {
    case seconds
    case milliseconds

    func encoded(seconds: Int) -> Int {
        switch self {
        case .seconds:
            return seconds
        case .milliseconds:
            return seconds * 1_000
        }
    }
}

/// The known hook-entry shapes across agent config files. A future agent
/// with a genuinely new shape adds a case here plus its rendering in
/// `LocalHooksInstaller` — the rest of the framework is unaffected.
public enum HookEntryStyle: Sendable {
    /// Claude Code `~/.claude/settings.json` and Gemini CLI
    /// `~/.gemini/settings.json`:
    /// `{"matcher": "", "hooks": [{"type": "command", "command": …}]}`
    case nestedWithEmptyMatcher
    /// Codex `~/.codex/hooks.json`: same nesting, no matcher key
    /// (omitted matcher = match everything).
    case nested
    /// Versioned Hook files with flat `{"command": …}` entries: Cursor's
    /// `~/.cursor/hooks.json` and Dev Island's dedicated Copilot CLI user Hook
    /// file. `"version": 1` is written only when absent.
    case flatVersioned
    /// Kimi Code `~/.kimi-code/config.toml`:
    /// `[[hooks]] event = "…", command = "…", timeout = 5`.
    /// The installer validates the complete TOML document and edits only
    /// explicitly delimited Dev Island blocks, preserving every other byte.
    case tomlArrayOfTables
    /// A dedicated dependency-free JavaScript module loaded directly from a
    /// vendor's global plugin directory. Dev Island owns the complete file;
    /// an unrelated file at the same path is never overwritten or removed.
    case standaloneJavaScriptPlugin
}
