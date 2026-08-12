import AppKit
import SwiftUI

/// Product-wide motion tokens — the single source of truth for how the
/// island moves. Anything that animates names a token here instead of
/// inlining its own curve, so "the bar and the panel feel like one object"
/// keeps holding as the UI grows.
///
/// Keep spatial changes on the `smooth` / `snappy` family so velocity is
/// continuous when several pieces move together. Opacity changes are kept
/// shorter: the island should feel responsive first, expressive second.
enum Motion {

    // MARK: - One-shot curves

    /// Large bar ↔ panel geometry change. No overshoot: the silhouette
    /// grows almost an order of magnitude in height, where bounce reads as
    /// window wobble rather than tactility. `.smooth` also has no abrupt
    /// acceleration at t=0, which keeps the silhouette's edge crisp through
    /// the first few frames where sub-pixel reflow would show as a seam.
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
    /// Row background following the cursor. Shorter than `colorTransition`
    /// on purpose: skimming down a list shouldn't leave a trail of rows
    /// fading out behind the pointer.
    static let hoverHighlight = Animation.easeOut(duration: 0.12)

    // MARK: - Loop periods

    // The running / waiting loops are driven by a `TimelineView` and a
    // time-derived phase (`StatusPhase`) rather than by `repeatForever`
    // animations: a repeating animation has to retarget awkwardly when the
    // state changes underneath it, whereas the phase formula can just
    // switch. These are the periods that the phase math keys off.

    static let runningBreathPeriod: TimeInterval = 2
    static let waitingPulsePeriod: TimeInterval = 1
    static let waitingRipplePeriod: TimeInterval = 1.5
    /// Sweep of the indeterminate bar under a running task card.
    static let progressShimmerPeriod: TimeInterval = 1.4

    /// One-shot "completed" flash on the status dot. `completedFlashRise`
    /// is both the rise duration and how long the dot is held at full
    /// scale before settling, so it's named rather than repeated at the
    /// animation and the scheduling call site — those two drifting apart
    /// is what makes a flash look like a stutter.
    static let completedFlashRise: TimeInterval = 0.18
    static let completedFlashSettle: TimeInterval = 0.27

    // MARK: - Accessibility

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

    /// System-wide "Reduce motion", readable outside a SwiftUI view.
    /// `IslandCoordinator` drives the bar ⇄ panel morph from AppKit-side
    /// code where `@Environment(\.accessibilityReduceMotion)` isn't
    /// reachable, and both paths must agree or the silhouette and its
    /// contents would animate on different curves.
    static var systemPrefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
