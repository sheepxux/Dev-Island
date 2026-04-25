import AppKit
import SwiftUI

/// Notch + bar geometry.
///
/// Hardcoded to MacBook Pro 14"/16" defaults for the static PoC. Task 7
/// (no-notch fallback) will read live values from `NSScreen.safeAreaInsets`
/// and the auxiliary top-area APIs.
enum NotchMetrics {
    /// Hardware notch width in points (14" ≈ 200, 16" ≈ 220). Conservative default.
    static let notchWidth: CGFloat = 200
    /// Bar (and notch) height. Matches the macOS menu bar.
    static let barHeight: CGFloat = 32
    /// How far the bar extends to either side of the notch.
    static let sideExtension: CGFloat = 90
    /// Total bar width = notch + 2× side extension.
    static var totalWidth: CGFloat { notchWidth + 2 * sideExtension }
    /// Inner padding from each end of the side extension.
    static let sideInset: CGFloat = 10
    /// Status dot diameter.
    static let dotSize: CGFloat = 12

    // No-notch fallback (Task 7).
    static let fallbackWidth: CGFloat = 140
    static let fallbackTopMargin: CGFloat = 4

    /// Returns true if the main display has a hardware notch.
    static func hasHardwareNotch() -> Bool {
        guard let screen = NSScreen.main else { return false }
        return screen.safeAreaInsets.top > 20
    }
}
