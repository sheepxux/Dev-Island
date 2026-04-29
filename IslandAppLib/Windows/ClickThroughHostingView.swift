import AppKit
import SwiftUI

/// `NSHostingView` subclass that filters mouse events through a
/// `visibleRegion` rect. Anything outside the region returns nil from
/// `hitTest`, so AppKit forwards the click to the window below.
///
/// Why we need this: `IslandWindow` is sized to the LARGEST visible
/// state (panel + shadow padding, ~536×408). When the bar is collapsed,
/// only a small capsule at the top is visible — but the rest of the
/// 408pt-tall window is still a fully transparent NSWindow that
/// intercepts all clicks in the upper-middle of the screen. That
/// silently blocks the user from clicking apps under our window's
/// transparent area.
///
/// Setting `visibleRegion` to the silhouette's bounding rect on every
/// SwiftUI re-render keeps the click-through region in lockstep with
/// the actual visible silhouette. nil = pass-through-disabled (default
/// AppKit hit-testing).
final class ClickThroughHostingView<RootView: View>: NSHostingView<RootView> {

    /// Visible region in this view's local (top-left, flipped)
    /// coordinate space. Set externally — typically from a SwiftUI
    /// `.onChange` callback inside the root view that fires whenever
    /// the silhouette dimensions change.
    var visibleRegion: CGRect?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let region = visibleRegion else {
            // No region set yet — fall back to default behavior so we
            // don't accidentally swallow events during init.
            return super.hitTest(point)
        }
        // `point` arrives in the SUPERVIEW's coord system; convert into
        // ours. NSHostingView is flipped (top-left origin) to match
        // SwiftUI, so this stays in the same space as `region`.
        let local = convert(point, from: superview)
        guard region.contains(local) else {
            return nil  // outside silhouette → click passes through
        }
        return super.hitTest(point)
    }
}
