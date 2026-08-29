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
    static let colorTransitionDuration: TimeInterval = 0.18
    static let colorTransition = Animation.easeInOut(duration: colorTransitionDuration)
    /// Row background following the cursor. Shorter than `colorTransition`
    /// on purpose: skimming down a list shouldn't leave a trail of rows
    /// fading out behind the pointer.
    static let hoverHighlight = Animation.easeOut(duration: 0.10)

    // MARK: - Loop periods

    // The running / waiting loops are compositor-owned opacity keyframes.
    // These periods are also used by the pure `StatusPhase` helper so new
    // layers join a shared wall-clock phase rather than visibly restarting.

    static let runningOrbitPeriod: TimeInterval = 1.8
    static let waitingBreathPeriod: TimeInterval = 1.4

    // MARK: - Accessibility

    /// Accessibility helper for one-shot opacity and color transitions.
    /// Geometry-changing call sites must use `allowsSpatialFeedback` instead:
    /// a shorter curve still moves width, offset and scale through space.
    static func respectingReducedMotion(
        _ reduceMotion: Bool,
        preferred: Animation,
        fallbackDuration: Double = 0.14
    ) -> Animation {
        reduceMotion ? .easeOut(duration: fallbackDuration) : preferred
    }

    /// Whether a geometry-changing affordance may move at all. A short
    /// fallback curve is appropriate for opacity, but applying that same
    /// curve to width, offset or scale still creates spatial motion. Keep
    /// this decision explicit at geometry call sites.
    static func allowsSpatialFeedback(_ reduceMotion: Bool) -> Bool {
        !reduceMotion
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

/// Stages expensive panel activity outside the silhouette's critical morph.
/// Content may begin its quiet opacity reveal once the capsule has room, but
/// compositor loops and the row/header-local second clocks wait until geometry
/// animation has fully settled. A 20-session Running panel can otherwise add
/// 189 opacity keyframe animations (header + 20 rows, nine dots each) near the
/// first morph frames.
enum IslandPanelActivityTiming {
    static let contentRevealDelay: TimeInterval = 0.04
    static let liveEffectsDelay: TimeInterval = Motion.islandMorphDuration + 0.04

    static func liveEffectsDelay(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : liveEffectsDelay
    }
}
