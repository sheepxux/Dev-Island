import AppKit
import SwiftUI

/// Notch + bar geometry, computed live from the active display so the bar
/// matches whatever menu-bar / notch height the OS is using.
public enum NotchMetrics {

    // MARK: - Geometry constants

    /// Width of each black side extension flanking the notch.
    public static let sideExtension: CGFloat = 90
    /// Inner inset for content inside each side extension.
    public static let sideInset: CGFloat = 10
    /// Status dot diameter.
    public static let dotSize: CGFloat = 12
    /// Outer-bottom corner radius for the notch bar extensions and the
    /// no-notch capsule. Also the design language for the panel (Task 2).
    public static let cornerRadius: CGFloat = 14
    /// Conservative default notch width (14" ≈ 200, 16" ≈ 220) used when
    /// the OS doesn't expose the real one.
    public static let defaultNotchWidth: CGFloat = 200

    // No-notch fallback (per CLAUDE_CLIENT.md §6 task 7)
    public static let fallbackWidth: CGFloat = 140
    public static let fallbackTopMargin: CGFloat = 4

    // MARK: - Layout descriptor

    /// Snapshot of the geometry for a particular screen. Capture once per
    /// `didChangeScreenParametersNotification` and pass it through the view
    /// tree so the same values drive Window framing + Shape drawing.
    public struct Layout: Equatable {
        public let hasNotch: Bool
        public let barHeight: CGFloat
        public let notchWidth: CGFloat
        public let topMargin: CGFloat   // distance from screen top edge to bar top

        public var totalWidth: CGFloat {
            hasNotch
                ? notchWidth + 2 * NotchMetrics.sideExtension
                : NotchMetrics.fallbackWidth
        }
    }

    // MARK: - Live measurement

    /// Current layout for the main display. Falls back to sensible defaults
    /// if `NSScreen.main` is unavailable (e.g. headless test).
    public static func current() -> Layout {
        guard let screen = NSScreen.main else {
            return Layout(
                hasNotch: false,
                barHeight: NSStatusBar.system.thickness,
                notchWidth: defaultNotchWidth,
                topMargin: fallbackTopMargin
            )
        }
        return layout(for: screen)
    }

    public static func layout(for screen: NSScreen) -> Layout {
        let safeTop = screen.safeAreaInsets.top
        let hasNotch = safeTop > 20

        if hasNotch {
            return Layout(
                hasNotch: true,
                barHeight: safeTop,
                notchWidth: detectNotchWidth(on: screen),
                topMargin: 0
            )
        } else {
            // Match the OS menu bar height so the capsule reads as part of
            // the menu bar visually. NSStatusBar.system.thickness accounts
            // for "Larger Text" + scaling tweaks the user may have set.
            return Layout(
                hasNotch: false,
                barHeight: NSStatusBar.system.thickness,
                notchWidth: defaultNotchWidth,
                topMargin: fallbackTopMargin
            )
        }
    }

    /// Best-effort notch width using the auxiliary top-area APIs introduced
    /// in macOS 12. Falls back to a 14"-class default.
    private static func detectNotchWidth(on screen: NSScreen) -> CGFloat {
        let leftAux = screen.auxiliaryTopLeftArea?.width ?? 0
        let rightAux = screen.auxiliaryTopRightArea?.width ?? 0
        let measured = screen.frame.width - leftAux - rightAux
        // Clamp — sometimes the API reports the full screen as left-aux on
        // displays without a real notch.
        guard measured > 100, measured < 400 else { return defaultNotchWidth }
        return measured
    }
}
