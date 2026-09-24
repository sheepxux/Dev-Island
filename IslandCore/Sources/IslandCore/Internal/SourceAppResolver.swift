import AppKit

/// Resolves which running application to activate for "jump back to the
/// session" (contract v1.4.0, J2 — `TaskStore.jumpToTask`).
///
/// Managed Hooks now provide a bounded host hint, so CLI tasks can prefer the
/// terminal that actually emitted the event. tmux sessions additionally select
/// their original window and pane before the host app is activated. Ordinary
/// terminal tabs still fall back to app-level activation because selecting a
/// tab would require terminal-specific Automation or Accessibility permission.
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
    static func resolveBundleId(
        source: String,
        running: Set<String>,
        preferredTerminalBundleIdentifier: String? = nil
    ) -> String? {
        if LocalAgentRegistry.descriptor(for: source)?.usesTerminalFallback == true,
           let preferredTerminalBundleIdentifier,
           running.contains(preferredTerminalBundleIdentifier) {
            return preferredTerminalBundleIdentifier
        }
        return candidates(for: source).first(where: running.contains)
    }

    /// The running app the resolver would activate for `task`, so the caller
    /// can ask `SessionDeepLinkPolicy` whether that app can open the exact
    /// session instead of merely coming forward.
    @MainActor
    static func resolvedHostBundleIdentifier(for task: AgentTask) -> String? {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return resolveBundleId(
            source: task.source,
            running: running,
            preferredTerminalBundleIdentifier: task.jumpContext?.terminalBundleIdentifier
        )
    }

    /// Activate the resolved app. Returns false when nothing suitable is
    /// running (caller falls back to `openTaskInBrowser` behavior).
    @MainActor
    static func activateApp(for task: AgentTask) -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        let running = Set(apps.compactMap(\.bundleIdentifier))
        let preferred = task.jumpContext?.terminalBundleIdentifier
        guard let bundleId = resolveBundleId(
            source: task.source,
            running: running,
            preferredTerminalBundleIdentifier: preferred
        ),
              let app = apps.first(where: { $0.bundleIdentifier == bundleId })
        else { return false }

        if bundleId == preferred,
           let context = task.jumpContext,
           context.hasPreciseTmuxTarget {
            Task.detached(priority: .userInitiated) {
                _ = TmuxSessionNavigator.selectOriginalPane(context)
                _ = await MainActor.run {
                    NSWorkspace.shared.runningApplications
                        .first(where: { $0.bundleIdentifier == bundleId })
                        .map(activate)
                }
            }
            return true
        }
        return activate(app)
    }

    /// Cooperative activation (macOS 14+): Dev Island is the active app at
    /// this point, because the click that asked for the jump activated it,
    /// so it yields to the host first and asks the host to take activation
    /// from it. A plain `activate()` is only honoured when the system feels
    /// like it; the fallback keeps older behaviour.
    @MainActor
    private static func activate(_ app: NSRunningApplication) -> Bool {
        NSApplication.shared.yieldActivation(to: app)
        if app.activate(from: NSRunningApplication.current, options: []) {
            return true
        }
        return app.activate()
    }
}
