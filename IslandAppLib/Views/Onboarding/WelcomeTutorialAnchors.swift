import AppKit
import Observation

/// The real on-screen things the full-screen Welcome coaches toward, in
/// AppKit screen coordinates. AppDelegate feeds the island's silhouette as it
/// morphs and the menu-bar item's frame; the canvas converts them into its
/// own space and follows them live.
@Observable @MainActor
public final class WelcomeTutorialAnchors {
    /// Frame of the screen the tour covers.
    public var screenFrame: CGRect
    /// Height of that screen's menu bar. Anything the tour draws inside the
    /// band sits under the menu bar and the island, so pointers stop there.
    public var menuBarHeight: CGFloat
    public var islandRect: CGRect?
    public var statusItemRect: CGRect?

    public init(
        screen: NSScreen,
        islandRect: CGRect? = nil,
        statusItemRect: CGRect? = nil
    ) {
        screenFrame = screen.frame
        menuBarHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        self.islandRect = islandRect
        self.statusItemRect = statusItemRect
    }
}
