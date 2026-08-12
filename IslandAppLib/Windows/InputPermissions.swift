import AppKit
import ApplicationServices

/// Whether the app may observe key presses that are delivered to OTHER
/// applications.
///
/// The island is a background (`.accessory`) app whose window never becomes
/// key, so an Esc pressed while the panel is open goes to whatever app the
/// user is actually working in. The only way to see it is
/// `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)`, which AppKit
/// gates behind Accessibility authorization.
///
/// The gate is silent — the monitor installs successfully and hands back a
/// non-nil token whether or not the process is trusted; it simply never
/// fires. That's why "Esc closes the panel" read as implemented for a long
/// time while doing nothing on a fresh install.
public enum InputPermissions {
    public static var canObserveGlobalKeys: Bool { AXIsProcessTrusted() }

    /// Reveal the Accessibility pane so the user can grant the permission.
    ///
    /// Deliberately not `AXIsProcessTrustedWithOptions(kAXTrustedCheckOptionPrompt)`:
    /// that alert can only ever be shown once per process registration, so a
    /// user who dismisses it has no way back. The pane always works.
    public static func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
