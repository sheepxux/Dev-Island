import AppKit
import Foundation
import Observation
import SwiftUI

/// Orchestrates the bar ⇄ panel transition.
///
/// Owns hover-dwell timers and the current display mode; the AppDelegate
/// listens to `onModeChange` and toggles which NSWindow is visible.
///
/// Trigger semantics (current — deviates from CLAUDE_CLIENT.md §2):
/// - Bar **click**       → `expand()`           (hover only widens the bar)
/// - Panel hover OUT     → `scheduleCollapse()` (fires after `collapseDelay`)
/// - Panel hover IN      → `cancelCollapse()`
/// - Esc / click outside → `collapse()` (installed by AppDelegate)
///
/// `scheduleExpand` / `cancelExpand` are retained for symmetry / future
/// hover-dwell experiments but are not called from production paths.
@Observable @MainActor
public final class IslandCoordinator {
    public static let shared = IslandCoordinator()

    public enum Mode: Equatable {
        case collapsed
        case expanded
    }

    public private(set) var mode: Mode = .collapsed

    /// Called on the main thread whenever `mode` actually changes. Kept for
    /// AppKit-side window plumbing (e.g. installing event monitors). SwiftUI
    /// views can observe `mode` directly via Observation.
    @ObservationIgnored
    public var onModeChange: ((Mode) -> Void)?

    public static let expandDelay: TimeInterval = 0.12
    public static let collapseDelay: TimeInterval = 0.30

    /// Animation applied to every mode flip. Used by SwiftUI views
    /// observing `mode` so the bar↔panel morph feels like a single shape
    /// breathing.
    ///
    /// `.smooth` (critically-damped, zero overshoot) is deliberate here:
    /// the morph spans ~7× in height (≈43→360pt), and any spring overshoot
    /// at that scale reads as the whole panel "wobbling" rather than as
    /// playful bounce. The Dynamic-Island feel comes from the bar's hover-
    /// widen (small delta, where bounce sits well); the bar↔panel morph
    /// itself is too big for bounce to look intentional. `.smooth` also
    /// gives a continuous velocity profile (no abrupt acceleration at
    /// t=0), which keeps the silhouette's edge crisp through the first
    /// few frames where sub-pixel reflow would otherwise show as a seam.
    @ObservationIgnored
    public static let modeAnimation: Animation = .smooth(duration: 0.42, extraBounce: 0.0)

    @ObservationIgnored private var expandTimer: Timer?
    @ObservationIgnored private var collapseTimer: Timer?

    private init() {}

    // MARK: - Direct control

    public func expand() {
        cancelAllTimers()
        setMode(.expanded)
    }

    public func collapse() {
        cancelAllTimers()
        setMode(.collapsed)
    }

    public func toggle() {
        switch mode {
        case .collapsed: expand()
        case .expanded:  collapse()
        }
    }

    // MARK: - Hover-driven scheduling

    public func scheduleExpand() {
        guard mode == .collapsed else { return }
        collapseTimer?.invalidate(); collapseTimer = nil
        expandTimer?.invalidate()
        expandTimer = Timer.scheduledTimer(
            withTimeInterval: Self.expandDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in self?.expand() }
        }
    }

    public func cancelExpand() {
        expandTimer?.invalidate()
        expandTimer = nil
    }

    public func scheduleCollapse() {
        guard mode == .expanded else { return }
        expandTimer?.invalidate(); expandTimer = nil
        collapseTimer?.invalidate()
        collapseTimer = Timer.scheduledTimer(
            withTimeInterval: Self.collapseDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in self?.collapse() }
        }
    }

    public func cancelCollapse() {
        collapseTimer?.invalidate()
        collapseTimer = nil
    }

    // MARK: - Private

    private func setMode(_ newMode: Mode) {
        guard mode != newMode else { return }
        // Wrap the property change in withAnimation so every SwiftUI view
        // observing `mode` (e.g. IslandRootView) interpolates its
        // dependent properties — width, height, corner radius, opacity —
        // with the shared `modeAnimation` spring.
        withAnimation(Self.modeAnimation) {
            mode = newMode
        }
        onModeChange?(mode)
    }

    private func cancelAllTimers() {
        expandTimer?.invalidate(); expandTimer = nil
        collapseTimer?.invalidate(); collapseTimer = nil
    }
}
