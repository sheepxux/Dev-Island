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
    static let islandMorphDuration: TimeInterval = 0.30
    static let islandMorph = Animation.smooth(duration: islandMorphDuration, extraBounce: 0)
    /// Small hover and press geometry changes can carry a hint of energy.
    static let hover = Animation.smooth(duration: 0.16, extraBounce: 0)
    /// Content enters after its containing surface has begun to settle.
    static let contentReveal = Animation.easeOut(duration: 0.18)
    /// Task-list and empty-state height changes.
    static let layoutDuration: TimeInterval = 0.24
    static let layout = Animation.smooth(duration: layoutDuration, extraBounce: 0)
    /// Welcome Tour page choreography.
    static let tourStep = Animation.smooth(duration: 0.28, extraBounce: 0)
    /// Tiny controls should acknowledge immediately.
    static let press = Animation.easeOut(duration: 0.08)
    /// Color cross-fade between states.
    static let colorTransition = Animation.easeInOut(duration: 0.18)
    /// Row background following the cursor. Shorter than `colorTransition`
    /// on purpose: skimming down a list shouldn't leave a trail of rows
    /// fading out behind the pointer.
    static let hoverHighlight = Animation.easeOut(duration: 0.10)

    // MARK: - Loop periods

    // The running / waiting loops are driven by a `TimelineView` and a
    // time-derived phase (`StatusPhase`) rather than by `repeatForever`
    // animations: a repeating animation has to retarget awkwardly when the
    // state changes underneath it, whereas the phase formula can just
    // switch. These are the periods that the phase math keys off.

    static let runningOrbitPeriod: TimeInterval = 1.8
    static let waitingBreathPeriod: TimeInterval = 1.4
    /// The delay before the completed acknowledgement settles must match its
    /// rise duration, so both legs use named tokens rather than inline values.
    static let completedFeedbackRise: TimeInterval = 0.18
    static let completedFeedbackSettle: TimeInterval = 0.27

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
