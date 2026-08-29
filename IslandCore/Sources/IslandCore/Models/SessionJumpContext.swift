import Foundation

/// Ephemeral, non-content metadata captured by a managed local Hook so a task
/// click can return to the terminal that actually hosted the CLI session.
///
/// The raw Hook environment is never retained. Values are bounded and
/// grammar-checked at the loopback boundary; only the normalized fields below
/// reach `AgentTask`, and SQLite intentionally does not persist them.
public struct SessionJumpContext: Codable, Hashable, Sendable {
    public let terminalBundleIdentifier: String?
    public let terminalProgram: String?
    public let tty: String?
    public let tmuxSocketPath: String?
    public let tmuxPane: String?

    public init?(
        terminalBundleIdentifier: String? = nil,
        terminalProgram: String? = nil,
        tty: String? = nil,
        tmuxEnvironment: String? = nil,
        tmuxPane: String? = nil
    ) {
        let program = Self.safeToken(terminalProgram, maximumLength: 64)
        let explicitBundle = Self.safeBundleIdentifier(terminalBundleIdentifier)
        self.terminalBundleIdentifier = explicitBundle
            ?? program.flatMap(Self.bundleIdentifier(forTerminalProgram:))
        self.terminalProgram = program
        self.tty = Self.safeTTY(tty)

        let pane = Self.safeTmuxPane(tmuxPane)
        let socket = pane.flatMap { _ in Self.safeTmuxSocket(from: tmuxEnvironment) }
        self.tmuxSocketPath = socket
        self.tmuxPane = socket == nil ? nil : pane

        guard self.terminalBundleIdentifier != nil
            || self.terminalProgram != nil
            || self.tty != nil
            || self.tmuxPane != nil else {
            return nil
        }
    }

    var hasPreciseTmuxTarget: Bool {
        tmuxSocketPath != nil && tmuxPane != nil
    }

    private static func safeBundleIdentifier(_ raw: String?) -> String? {
        guard let candidate = trimmed(raw, maximumLength: 255),
              candidate.contains("."),
              candidate.utf8.allSatisfy({ byte in
                  (byte >= 0x41 && byte <= 0x5A)
                      || (byte >= 0x61 && byte <= 0x7A)
                      || (byte >= 0x30 && byte <= 0x39)
                      || byte == 0x2D || byte == 0x2E
              }) else { return nil }
        return candidate
    }

    private static func safeToken(_ raw: String?, maximumLength: Int) -> String? {
        guard let candidate = trimmed(raw, maximumLength: maximumLength),
              candidate.utf8.allSatisfy({ byte in
                  (byte >= 0x41 && byte <= 0x5A)
                      || (byte >= 0x61 && byte <= 0x7A)
                      || (byte >= 0x30 && byte <= 0x39)
                      || byte == 0x2D || byte == 0x2E || byte == 0x5F
              }) else { return nil }
        return candidate
    }

    private static func safeTTY(_ raw: String?) -> String? {
        guard let candidate = trimmed(raw, maximumLength: 80), candidate != "??",
              candidate.utf8.allSatisfy({ byte in
                  (byte >= 0x41 && byte <= 0x5A)
                      || (byte >= 0x61 && byte <= 0x7A)
                      || (byte >= 0x30 && byte <= 0x39)
                      || byte == 0x2D || byte == 0x2E || byte == 0x2F || byte == 0x5F
              }) else { return nil }
        return candidate
    }

    private static func safeTmuxPane(_ raw: String?) -> String? {
        guard let candidate = trimmed(raw, maximumLength: 24),
              candidate.first == "%",
              candidate.dropFirst().allSatisfy(\.isNumber),
              candidate.dropFirst().allSatisfy({ $0.isASCII }) else { return nil }
        return candidate
    }

    /// `$TMUX` is `<socket path>,<server pid>,<session index>`. Parse from the
    /// right so an unusual but valid socket path containing a comma still works.
    private static func safeTmuxSocket(from raw: String?) -> String? {
        guard let value = trimmed(raw, maximumLength: 1_024) else { return nil }
        let components = value.split(separator: ",", omittingEmptySubsequences: false)
        guard components.count >= 3,
              components[components.count - 2].allSatisfy(\.isNumber),
              components[components.count - 1].allSatisfy(\.isNumber) else { return nil }

        let path = components.dropLast(2).joined(separator: ",")
        guard path.hasPrefix("/"), !path.contains("\0") else { return nil }
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard standardized.hasPrefix("/"), standardized.count <= 900 else { return nil }
        return standardized
    }

    private static func trimmed(_ raw: String?, maximumLength: Int) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= maximumLength,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return nil }
        return value
    }

    private static func bundleIdentifier(forTerminalProgram program: String) -> String? {
        switch program.lowercased() {
        case "apple_terminal": return "com.apple.Terminal"
        case "iterm.app", "iterm2": return "com.googlecode.iterm2"
        case "ghostty": return "com.mitchellh.ghostty"
        case "warpterminal", "warp": return "dev.warp.Warp-Stable"
        case "kitty": return "net.kovidgoyal.kitty"
        case "alacritty": return "org.alacritty"
        case "wezterm": return "com.github.wez.wezterm"
        case "vscode": return "com.microsoft.VSCode"
        default: return nil
        }
    }
}
