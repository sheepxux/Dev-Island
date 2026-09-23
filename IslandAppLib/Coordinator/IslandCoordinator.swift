import AppKit
import Foundation
import IslandCore
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
/// - Welcome demo active → hover OUT never collapses (`tutorialDemo`)
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

    /// Task the expanded panel should reveal and visually emphasize. This is
    /// set by notification clicks, then cleared when the user leaves the
    /// panel or opens the task.
    public private(set) var highlightedTask: TaskIdentity?

    /// Programmatic opens stay put until the user explicitly engages with
    /// the panel. A synthetic hover-out can arrive when a view first grows
    /// under the pointer; keeping the arming bit here (rather than in view
    /// state) makes that event unable to dismiss notification/onboarding
    /// opens before they are readable.
    public private(set) var automaticCollapseArmed = false

    /// Example sessions the Welcome tutorial shows on the real island instead
    /// of TaskStore content; nil outside the tour. Orthogonal to `mode`:
    /// expand()/collapse() never touch it. `IslandRootView` reads it inside
    /// `body`, so assigning it re-renders the bar and panel like a store
    /// change, and routes answers to demo requests back here.
    private(set) var tutorialDemo: IslandTutorialDemo?

    /// The latest answer the user gave on the island to demo content. The
    /// tour observes it; it is never forwarded to TaskStore or an Agent.
    private(set) var tutorialDemoResponse: IslandTutorialDemo.Response?
    @ObservationIgnored private var tutorialDemoResponseSequence = 0

    /// Called on the main thread whenever `mode` actually changes. Kept for
    /// AppKit-side window plumbing (e.g. installing event monitors). SwiftUI
    /// views can observe `mode` directly via Observation.
    @ObservationIgnored
    public var onModeChange: ((Mode) -> Void)?

    public static let expandDelay: TimeInterval = 0.12
    /// A forgiving exit grace period. 300ms was short enough that moving
    /// diagonally from a card toward the panel edge could collapse the
    /// island before the user corrected their pointer. 450ms still feels
    /// immediate, while making the surface much harder to dismiss by
    /// accident.
    public static let collapseDelay: TimeInterval = 0.60

    /// Animation applied to every mode flip. Used by SwiftUI views
    /// observing `mode` so the bar↔panel morph feels like a single shape
    /// breathing.
    ///
    /// Resolved per access rather than stored, so toggling "Reduce motion"
    /// in System Settings takes effect on the next expand instead of
    /// needing a relaunch. `Motion.islandMorph` is the shared token — the
    /// views that ride along on this morph reach for the same one, and
    /// this used to be a second, slightly different curve of its own.
    public static var modeAnimation: Animation {
        modeAnimation(expanding: true)
    }

    /// Collapse runs on the shorter exit curve; see `Motion.islandCollapse`.
    public static func modeAnimation(expanding: Bool) -> Animation {
        Motion.respectingReducedMotion(
            Motion.systemPrefersReducedMotion,
            preferred: Motion.islandMorph(expanding: expanding)
        )
    }

    @ObservationIgnored private var expandTimer: Timer?
    @ObservationIgnored private var collapseTimer: Timer?

    private init() {}

    // MARK: - Direct control

    public func expand() {
        cancelAllTimers()
        automaticCollapseArmed = false
        setMode(.expanded)
    }

    /// Expand from a direct click on the compact island. The pointer has
    /// already engaged with the surface, so leaving it may auto-collapse.
    public func expandFromPointer() {
        cancelAllTimers()
        automaticCollapseArmed = true
        setMode(.expanded)
    }

    /// Open the panel on a specific task. Reassigning while already expanded
    /// is intentional: it lets two notification clicks retarget the panel.
    /// A real session asking for attention always wins over the Welcome
    /// demo: the island shows the real request at once.
    public func expand(highlighting task: TaskIdentity) {
        cancelAllTimers()
        automaticCollapseArmed = false
        if let tutorialDemo, !tutorialDemo.owns(task) {
            endTutorialDemo()
        }
        highlightedTask = task
        setMode(.expanded)
    }

    public func collapse() {
        cancelAllTimers()
        automaticCollapseArmed = false
        highlightedTask = nil
        setMode(.collapsed)
    }

    public func clearHighlight() {
        highlightedTask = nil
    }

    public func toggle() {
        switch mode {
        case .collapsed: expand()
        case .expanded:  collapse()
        }
    }

    // MARK: - Welcome tutorial demo

    func beginTutorialDemo(_ demo: IslandTutorialDemo) {
        tutorialDemo = demo
    }

    /// Replaces the demo content while a demo is running (the next beat, or
    /// the same beat in another language). A demo that already ended stays
    /// ended so a late beat cannot cover real content.
    func updateTutorialDemo(_ demo: IslandTutorialDemo) {
        guard tutorialDemo != nil else { return }
        tutorialDemo = demo
    }

    public func endTutorialDemo() {
        guard tutorialDemo != nil else { return }
        if let highlightedTask, tutorialDemo?.owns(highlightedTask) == true {
            self.highlightedTask = nil
        }
        tutorialDemo = nil
        tutorialDemoResponse = nil
    }

    /// Records an answer given on the island. Returns true when the demo owned
    /// the request or session, in which case the caller must not forward the
    /// event to TaskStore.
    @discardableResult
    func recordTutorialDemoResponse(_ event: IslandTutorialDemo.Event) -> Bool {
        guard let tutorialDemo, tutorialDemo.owns(event) else { return false }
        tutorialDemoResponseSequence += 1
        tutorialDemoResponse = .init(sequence: tutorialDemoResponseSequence, event: event)
        return true
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
        // While the Welcome demo owns the panel, a hover-out must not fold the
        // island between its beats; the tour decides when it closes.
        guard mode == .expanded, automaticCollapseArmed, tutorialDemo == nil else { return }
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

    public func armAutomaticCollapse() {
        guard mode == .expanded else { return }
        automaticCollapseArmed = true
    }

    // MARK: - Private

    private func setMode(_ newMode: Mode) {
        guard mode != newMode else { return }
        // Wrap the property change in withAnimation so every SwiftUI view
        // observing `mode` (e.g. IslandRootView) interpolates its
        // dependent properties — width, height, corner radius, opacity —
        // with the shared `modeAnimation` spring.
        if Motion.systemPrefersReducedMotion {
            // A shorter curve would still animate the capsule's width and
            // height. Snap geometry instead; IslandRootView keeps a quiet
            // content-opacity transition so the state change remains clear.
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                mode = newMode
            }
        } else {
            withAnimation(Motion.islandMorph(expanding: newMode == .expanded)) {
                mode = newMode
            }
        }
        onModeChange?(mode)
    }

    private func cancelAllTimers() {
        expandTimer?.invalidate(); expandTimer = nil
        collapseTimer?.invalidate(); collapseTimer = nil
    }
}
