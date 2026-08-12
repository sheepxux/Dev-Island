import SwiftUI

/// Product-wide motion tokens.
///
/// Keep spatial changes on the `smooth` / `snappy` family so velocity is
/// continuous when several pieces move together. Opacity changes are kept
/// shorter: the island should feel responsive first, expressive second.
enum Motion {
    /// Large bar ↔ panel geometry change. No overshoot: the silhouette
    /// grows almost an order of magnitude in height, where bounce reads as
    /// window wobble rather than tactility.
    static let islandMorph = Animation.smooth(duration: 0.38, extraBounce: 0)
    /// Small hover and press geometry changes can carry a hint of energy.
    static let hover = Animation.snappy(duration: 0.22, extraBounce: 0.08)
    /// Content enters after its containing surface has begun to settle.
    static let contentReveal = Animation.smooth(duration: 0.26, extraBounce: 0)
    /// Task-list and empty-state height changes.
    static let layout = Animation.smooth(duration: 0.32, extraBounce: 0)
    /// Welcome Tour page choreography.
    static let tourStep = Animation.smooth(duration: 0.42, extraBounce: 0)
    /// Welcome Tour's persistent island illustration changing state.
    static let tourHero = Animation.spring(response: 0.48, dampingFraction: 0.86)
    /// Tiny controls should acknowledge immediately.
    static let press = Animation.easeOut(duration: 0.09)
    /// Color cross-fade between states.
    static let colorTransition = Animation.easeInOut(duration: 0.22)
    /// Running breathing loop (2s).
    static let runningBreath = Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)
    /// Waiting pulse loop (1s).
    static let waitingPulse = Animation.easeInOut(duration: 1).repeatForever(autoreverses: true)
    /// Waiting ripple expansion (1.5s).
    static let waitingRipple = Animation.easeOut(duration: 1.5).repeatForever(autoreverses: false)

    /// Accessibility helper for one-shot transitions. Call sites retain the
    /// same state changes while users who request reduced motion get a short
    /// dissolve instead of spatial travel.
    static func respectingReducedMotion(
        _ reduceMotion: Bool,
        preferred: Animation,
        fallbackDuration: Double = 0.14
    ) -> Animation {
        reduceMotion ? .easeOut(duration: fallbackDuration) : preferred
    }
}
