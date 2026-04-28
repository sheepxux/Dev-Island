import SwiftUI

/// Typography tokens. Numbers/timers always use SF Mono. Titles use SF Pro.
enum Typo {
    /// Task count digits in the notch bar.
    static let barCount = Font.system(size: 11, weight: .medium, design: .monospaced)
    /// Current task label in the synthetic-notch compact bar.
    static let barTitle = Font.system(size: 12, weight: .regular, design: .monospaced)
    /// Count badge in the synthetic-notch compact bar.
    static let barBadge = Font.system(size: 10, weight: .semibold, design: .monospaced)
    /// Task card title (one line).
    static let cardTitle = Font.system(size: 13, weight: .medium)
    /// Phase + duration row.
    static let cardMeta = Font.system(size: 11, design: .monospaced).weight(.regular)
    /// Section headers ("Tasks (N)").
    static let sectionHeader = Font.system(size: 13, weight: .semibold)
}
