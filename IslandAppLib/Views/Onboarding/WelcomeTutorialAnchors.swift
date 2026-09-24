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
    /// Height of that screen's menu bar. The macOS 26 menu bar is transparent
    /// and shows whatever a window paints under it (2026-09-24: a light wash
    /// there erased the white menu-bar icons), so the tour window stops at
    /// the band's lower edge and never paints inside it.
    public var menuBarHeight: CGFloat
    public var islandRect: CGRect?
    public var statusItemRect: CGRect?

    /// The screen minus its menu-bar band: the frame the tour window fills
    /// and the space the canvas converts targets into.
    public var stageFrame: CGRect {
        WelcomeTutorialLayout.stageFrame(screenFrame: screenFrame, menuBarHeight: menuBarHeight)
    }

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
