import SwiftUI

/// Animation tokens. See CLAUDE_CLIENT.md §5.
enum Motion {
    /// Panel expand/collapse spring.
    static let expand = Animation.spring(response: 0.6, dampingFraction: 0.72)
    /// Color cross-fade between states.
    static let colorTransition = Animation.easeInOut(duration: 0.25)
    /// Running breathing loop (2s).
    static let runningBreath = Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)
    /// Waiting pulse loop (1s).
    static let waitingPulse = Animation.easeInOut(duration: 1).repeatForever(autoreverses: true)
    /// Waiting ripple expansion (1.5s).
    static let waitingRipple = Animation.easeOut(duration: 1.5).repeatForever(autoreverses: false)
}
