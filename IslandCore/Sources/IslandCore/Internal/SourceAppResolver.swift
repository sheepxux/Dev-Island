import AppKit

/// Resolves which running application to activate for "jump back to the
/// session" (contract v1.4.0, J2 — `TaskStore.jumpToTask`).
///
/// Strategy is deliberately app-level, not window-level: macOS gives us no
/// sanctioned way to find *which* terminal window hosts a given CLI session
/// without Accessibility permissions, so v1 activates the most plausible
/// host app and lets the user land on their last-used window.
enum SourceAppResolver {

    /// Terminal emulators that commonly host CLI agents, ordered by how
    /// likely a developer is to have exactly one of them as their daily
    /// driver. Only *running* apps are considered, so order rarely matters
    /// in practice.
    private static let terminalCandidates = [
        "com.googlecode.iterm2",         // iTerm2
        "com.mitchellh.ghostty",         // Ghostty
        "dev.warp.Warp-Stable",          // Warp
        "net.kovidgoyal.kitty",          // kitty
        "org.alacritty",                 // Alacritty
        "com.github.wez.wezterm",        // WezTerm
        "com.apple.Terminal",            // Terminal.app (last: everyone has it)
    ]

    /// Candidate bundle IDs per task source, most specific first — driven
    /// by the agent's registry row (own app first, then terminals when its
    /// CLI sessions live in one). Sources without a registry entry (manus
    /// & friends) resolve to nothing and the caller falls back.
    static func candidates(for source: String) -> [String] {
        guard let descriptor = LocalAgentRegistry.descriptor(for: source) else { return [] }
        return descriptor.appCandidates
            + (descriptor.usesTerminalFallback ? terminalCandidates : [])
    }

    /// Pure resolution step, unit-testable: pick the first candidate that
    /// is actually running.
    static func resolveBundleId(source: String, running: Set<String>) -> String? {
        candidates(for: source).first(where: running.contains)
    }

    /// Activate the resolved app. Returns false when nothing suitable is
    /// running (caller falls back to `openTaskInBrowser` behavior).
    @MainActor
    static func activateApp(for source: String) -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        let running = Set(apps.compactMap(\.bundleIdentifier))
        guard let bundleId = resolveBundleId(source: source, running: running),
              let app = apps.first(where: { $0.bundleIdentifier == bundleId })
        else { return false }
        return app.activate()
    }
}
