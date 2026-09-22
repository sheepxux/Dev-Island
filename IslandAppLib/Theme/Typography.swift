import SwiftUI

/// One type scale, named by role. SF Pro carries reading; SF Mono appears only
/// where characters must line up — counts, clocks, commands — which is also
/// where the icon's terminal `Dev_` lives. Nothing that carries information is
/// set below 11pt (macOS's small system size); a size outside this list needs
/// a reason written next to it.
enum Typo {
    // MARK: Windows (light ground)

    /// Welcome headlines. Pair with `displayTracking`.
    static let display = Font.system(size: 30, weight: .semibold)
    static let displayTracking: CGFloat = -0.8
    /// The one sentence under a Welcome headline.
    static let lead = Font.system(size: 14)
    /// Pane titles in Settings and sheet titles. Pair with `titleTracking`.
    static let title = Font.system(size: 22, weight: .semibold)
    /// `Font` cannot carry tracking, so the two tightened roles name theirs.
    static let titleTracking: CGFloat = -0.4
    /// Group headings and prominent row titles.
    static let headline = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyStrong = Font.system(size: 13, weight: .semibold)
    static let callout = Font.system(size: 12)
    static let calloutStrong = Font.system(size: 12, weight: .medium)
    /// Hints and footnotes. The floor.
    static let caption = Font.system(size: 11)
    static let control = Font.system(size: 12.5, weight: .medium)
    static let controlStrong = Font.system(size: 12.5, weight: .semibold)
    static let controlLarge = Font.system(size: 14, weight: .semibold)
    static let mono = Font.system(size: 12, design: .monospaced)
    static let numeric = Font.system(size: 12, weight: .medium, design: .monospaced)

    // MARK: Island (dark ground, dense)

    /// Panel header and the question a request asks.
    static let islandHeadline = Font.system(size: 13, weight: .semibold)
    /// Session titles in rows.
    static let islandTitle = Font.system(size: 13, weight: .medium)
    /// Request messages and empty-state copy.
    static let islandBody = Font.system(size: 12)
    /// Agent · branch · phase lines. The floor.
    static let islandMeta = Font.system(size: 11)
    /// The label that names what a request needs.
    static let islandLabel = Font.system(size: 11, weight: .semibold)
    /// Counts and clocks.
    static let islandNumeric = Font.system(size: 11, weight: .medium, design: .monospaced)
    /// Commands and plan code.
    static let islandCode = Font.system(size: 11.5, design: .monospaced)
    static let islandControl = Font.system(size: 12, weight: .semibold)

    /// Current task label in the synthetic-notch compact bar.
    static let barTitle = Font.system(size: 12, weight: .medium)
    /// Session count in the compact bar and notch wings.
    static let barCount = Font.system(size: 11, weight: .medium, design: .monospaced)
}
