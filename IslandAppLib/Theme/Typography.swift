import SwiftUI

/// Typography tokens. Product UI uses SF Pro for reading and reserves SF Mono
/// for counts, terminal content, and compact technical labels. The
/// Welcome Tour deliberately avoids the oversized serif treatment common to
/// generated landing pages; hierarchy comes from spacing, weight and scale.
enum Typo {
    // Welcome Tour
    static let tourDisplay = Font.system(size: 32, weight: .semibold)
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
    /// Agent + phase metadata. Durations opt into monospaced digits at the
    /// call site so the full row does not read like terminal output.
    static let cardMeta = Font.system(size: 11, weight: .regular)
    /// Section headers ("Tasks (N)").
    static let sectionHeader = Font.system(size: 13, weight: .semibold)
}
