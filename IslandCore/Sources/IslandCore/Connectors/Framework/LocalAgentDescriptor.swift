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
    /// Decode one raw hook payload into a normalized event. `nil` means
    /// "drop silently" (undecodable body, or a payload without a usable
    /// session id).
    public let decodeEvent: @Sendable (Data) -> LocalAgentEvent?

    public init(
        source: String,
        displayName: String,
        settingsSubtitle: String,
        configPath: String,
        hookEvents: [String],
        hookEntryStyle: HookEntryStyle,
        appCandidates: [String],
        usesTerminalFallback: Bool,
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
        self.configPath = configPath
        self.hookEvents = hookEvents
        self.hookEntryStyle = hookEntryStyle
        self.appCandidates = appCandidates
        self.usesTerminalFallback = usesTerminalFallback
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

/// The known hook-entry shapes across agent config files. A future agent
/// with a genuinely new shape adds a case here plus its rendering in
/// `LocalHooksInstaller` — the rest of the framework is unaffected.
public enum HookEntryStyle: Sendable {
    /// Claude Code `~/.claude/settings.json`:
    /// `{"matcher": "", "hooks": [{"type": "command", "command": …}]}`
    case nestedWithEmptyMatcher
    /// Codex `~/.codex/hooks.json`: same nesting, no matcher key
    /// (omitted matcher = match everything).
    case nested
    /// Cursor `~/.cursor/hooks.json`: flat `{"command": …}` entries plus a
    /// required top-level `"version": 1` (written only when absent).
    case flatVersioned
}
