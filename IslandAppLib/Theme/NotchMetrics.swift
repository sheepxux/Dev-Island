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
    /// Status point-field diameter.
    public static let dotSize: CGFloat = 14
    /// Outer-bottom corner radius for the hardware-notch bar extensions.
    public static let cornerRadius: CGFloat = 11
    /// Outer-bottom corner radius for the synthetic notch on non-notched Macs.
    public static let syntheticCornerRadius: CGFloat = 12
    /// Outer-bottom corner radius for the expanded panel (Task 2).
    public static let panelCornerRadius: CGFloat = 14
    /// Default panel width (synthetic-notch displays).
    public static let panelWidth: CGFloat = 420
    /// Maximum panel width on notched displays — never exceed this.
    public static let panelMaxWidth: CGFloat = 440
    /// Vertical space the task list may occupy before it starts scrolling.
    public static let panelTaskListMaxHeight: CGFloat = 320
    /// Ceiling for the expanded panel. The silhouette clips its content, so
    /// this must stay above the tallest layout the panel can produce:
    /// header + a full `panelTaskListMaxHeight` list + panel padding.
    public static let panelMaxHeight: CGFloat = 392
    /// Floor for the expanded panel, so a transient zero/short measurement
    /// can't collapse the silhouette into a sliver mid-morph.
    public static let panelMinHeight: CGFloat = 104

    /// Clamp a measured panel-content height into the range the silhouette
    /// (and its host window) can actually display.
    public static func panelHeight(forContentHeight content: CGFloat) -> CGFloat {
        min(max(content, panelMinHeight), panelMaxHeight)
    }

    /// Expanded width for a display layout. Keeping this here prevents the
    /// host root and panel content from drifting apart during future tuning.
    public static func panelWidth(for layout: Layout) -> CGFloat {
        layout.hasNotch
            ? min(panelMaxWidth, layout.notchWidth + 240)
            : panelWidth
    }

    // Hover affordance — how much the bar grows when the mouse enters,
    // signalling "clickable". Pre-Task-2 polish; the panel expansion that
    // fires after 120ms still belongs to Task 2.
    //
    // Notched displays grow downward by hoverHeightBoostNotched. No-notch
    // capsules grow to fill the OS status bar exactly (no overflow), so
    // idle height is `thickness - capsuleVerticalInset` and hover height
    // is `thickness`.
    public static let hoverWidthBoostNotched: CGFloat = 12
    public static let hoverHeightBoostNotched: CGFloat = 2
    public static let hoverWidthBoostCapsule: CGFloat = 12
    /// Extra height the synthetic notch drops below the menu bar on hover.
    public static let hoverHeightBoostCapsule: CGFloat = 2

    /// Padding around the bar inside the window so SwiftUI .shadow renders
    /// fully (the NSWindow content view clips otherwise).
    public static let shadowPadding: CGFloat = 28
    /// Conservative default notch width (14" ≈ 200, 16" ≈ 220) used when
    /// the OS doesn't expose the real one.
    public static let defaultNotchWidth: CGFloat = 200

    // No-notch fallback (per CLAUDE_CLIENT.md §6 task 7)
    /// Synthetic island width on displays without a hardware notch. Keep
    /// enough room for the current task and the all-session count to coexist
    /// without turning ordinary status copy into ellipses.
    public static let fallbackWidth: CGFloat = 260
    public static let fallbackBarHeight: CGFloat = 28


    // MARK: - Layout descriptor

    /// Snapshot of the geometry for a particular screen. Capture once per
    /// `didChangeScreenParametersNotification` and pass it through the view
    /// tree so the same values drive Window framing + Shape drawing.
    public struct Layout: Equatable {
        public let hasNotch: Bool
        /// Full bar height. On notched displays this equals `notchHeight`
        /// — content lives in the side wings within the menubar zone, so
        /// no overhang is needed below the notch.
        public let barHeight: CGFloat
        /// Hardware notch height. 0 on no-notch displays. Used to size the
        /// cutout in `NotchBarShape`.
        public let notchHeight: CGFloat
        /// True OS menu-bar height for this screen. Drives the window
        /// container height so the capsule centers in the status bar zone
        /// exactly. On notched displays this equals `notchHeight`.
        public let menuBarHeight: CGFloat
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
                    menuBarHeight: menuBarHeight,
                    notchWidth: notchWidth,
                    topMargin: topMargin,
                    widthBoost: NotchMetrics.hoverWidthBoostNotched
                )
            } else {
                // Drop slightly past the menu bar bottom on hover for a
                // Dynamic-Island-style anticipation of the panel expansion.
                return Layout(
                    hasNotch: false,
                    barHeight: barHeight + NotchMetrics.hoverHeightBoostCapsule,
                    notchHeight: 0,
                    menuBarHeight: menuBarHeight,
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
                barHeight: thickness,
                notchHeight: 0,
                menuBarHeight: thickness,
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
                barHeight: safeTop,
                notchHeight: safeTop,
                menuBarHeight: safeTop,
                notchWidth: detectNotchWidth(on: screen),
                topMargin: 0
            )
        } else {
            // Synthetic notch: keep the simulated island within the menu
            // bar band so it feels like a status-bar replacement rather
            // than a large floating panel.
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            let measured = menuBar > 0 ? menuBar : NSStatusBar.system.thickness
            let barHeight = measured > 0 ? measured : fallbackBarHeight
            return Layout(
                hasNotch: false,
                barHeight: barHeight,
                notchHeight: 0,
                menuBarHeight: measured,
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
