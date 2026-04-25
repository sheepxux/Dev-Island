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
    public static let cornerRadius: CGFloat = 11
    /// How far the bar protrudes BELOW the hardware notch on notched
    /// displays. Gives a longer straight vertical edge before the corner
    /// curve starts (Dynamic Island feel).
    public static let bottomOverhang: CGFloat = 7

    // Hover affordance — how much the bar grows when the mouse enters,
    // signalling "clickable". Pre-Task-2 polish; the panel expansion that
    // fires after 120ms still belongs to Task 2.
    //
    // Notched displays grow downward by hoverHeightBoostNotched. No-notch
    // capsules grow to fill the OS status bar exactly (no overflow), so
    // idle height is `thickness - capsuleVerticalInset` and hover height
    // is `thickness`.
    public static let hoverWidthBoostNotched: CGFloat = 30   // 15pt each side
    public static let hoverHeightBoostNotched: CGFloat = 4
    public static let hoverWidthBoostCapsule: CGFloat = 50
    /// Conservative default notch width (14" ≈ 200, 16" ≈ 220) used when
    /// the OS doesn't expose the real one.
    public static let defaultNotchWidth: CGFloat = 200

    // No-notch fallback (per CLAUDE_CLIENT.md §6 task 7)
    public static let fallbackWidth: CGFloat = 140
    /// How much shorter the idle capsule is than the OS menu-bar height,
    /// leaving breathing room top + bottom inside the status-bar zone.
    /// Hover removes this inset so the capsule fills the status bar exactly.
    public static let capsuleVerticalInset: CGFloat = 6

    // MARK: - Layout descriptor

    /// Snapshot of the geometry for a particular screen. Capture once per
    /// `didChangeScreenParametersNotification` and pass it through the view
    /// tree so the same values drive Window framing + Shape drawing.
    public struct Layout: Equatable {
        public let hasNotch: Bool
        /// Full bar height. On notched displays this is `notchHeight + bottomOverhang`.
        public let barHeight: CGFloat
        /// Hardware notch height. 0 on no-notch displays. Used to size the
        /// cutout in `NotchBarShape`.
        public let notchHeight: CGFloat
        public let notchWidth: CGFloat
        public let topMargin: CGFloat   // distance from screen top edge to bar top
        /// Extra width applied on top of the base extensions / fallback
        /// pill. Non-zero on hover.
        public var widthBoost: CGFloat = 0

        public var totalWidth: CGFloat {
            let base: CGFloat = hasNotch
                ? notchWidth + 2 * NotchMetrics.sideExtension
                : NotchMetrics.fallbackWidth
            return base + widthBoost
        }

        /// Hover-expanded variant. Wider + slightly taller; the cutout
        /// stays at the original notch dimensions because the hardware
        /// notch never moves.
        public func hovered() -> Layout {
            if hasNotch {
                return Layout(
                    hasNotch: true,
                    barHeight: barHeight + NotchMetrics.hoverHeightBoostNotched,
                    notchHeight: notchHeight,
                    notchWidth: notchWidth,
                    topMargin: topMargin,
                    widthBoost: NotchMetrics.hoverWidthBoostNotched
                )
            } else {
                // Fill the OS status bar exactly — no overflow.
                return Layout(
                    hasNotch: false,
                    barHeight: NSStatusBar.system.thickness,
                    notchHeight: 0,
                    notchWidth: notchWidth,
                    topMargin: topMargin,
                    widthBoost: NotchMetrics.hoverWidthBoostCapsule
                )
            }
        }
    }

    // MARK: - Live measurement

    /// Current layout for the main display. Falls back to sensible defaults
    /// if `NSScreen.main` is unavailable (e.g. headless test).
    public static func current() -> Layout {
        guard let screen = NSScreen.main else {
            let thickness = NSStatusBar.system.thickness
            return Layout(
                hasNotch: false,
                barHeight: max(0, thickness - capsuleVerticalInset),
                notchHeight: 0,
                notchWidth: defaultNotchWidth,
                topMargin: 0
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
                barHeight: safeTop + bottomOverhang,
                notchHeight: safeTop,
                notchWidth: detectNotchWidth(on: screen),
                topMargin: 0
            )
        } else {
            // Idle capsule is `capsuleVerticalInset` shorter than the OS
            // status bar so it sits inside it with margin. Hover grows it
            // to the full status-bar height. NSStatusBar.system.thickness
            // tracks "Larger Text" + display scaling automatically.
            let thickness = NSStatusBar.system.thickness
            return Layout(
                hasNotch: false,
                barHeight: max(0, thickness - capsuleVerticalInset),
                notchHeight: 0,
                notchWidth: defaultNotchWidth,
                topMargin: 0
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
