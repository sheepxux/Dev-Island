import SwiftUI

/// Typography tokens. Product UI uses SF Pro, numbers use SF Mono, and the
/// Welcome Tour introduces a restrained New York display face for editorial
/// contrast. Keeping those roles explicit prevents a mix of arbitrary sizes.
enum Typo {
    // Welcome Tour
    static let tourDisplay = Font.system(size: 36, weight: .regular, design: .serif)
    static let tourBody = Font.system(size: 13, weight: .regular)
    static let tourLabel = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let tourStageTitle = Font.system(size: 12, weight: .semibold)
    static let tourStageBody = Font.system(size: 11, weight: .regular)
    static let controlLabel = Font.system(size: 12, weight: .semibold)

    /// Task count digits in the notch bar.
    static let barCount = Font.system(size: 11, weight: .medium, design: .monospaced)
    /// Current task label in the synthetic-notch compact bar.
    static let barTitle = Font.system(size: 12, weight: .regular)
    /// Count badge in the synthetic-notch compact bar.
    static let barBadge = Font.system(size: 10, weight: .semibold, design: .monospaced)
    /// Task card title (one line).
    static let cardTitle = Font.system(size: 13, weight: .medium)
    /// Phase + duration row.
    static let cardMeta = Font.system(size: 11, design: .monospaced).weight(.regular)
    /// Section headers ("Tasks (N)").
    static let sectionHeader = Font.system(size: 13, weight: .semibold)
}
