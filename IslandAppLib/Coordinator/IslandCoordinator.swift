import AppKit
import Foundation

/// Orchestrates the bar ⇄ panel transition.
///
/// Owns hover-dwell timers and the current display mode; the AppDelegate
/// listens to `onModeChange` and toggles which NSWindow is visible.
///
/// Hover semantics (per CLAUDE_CLIENT.md §6 task 2):
/// - Bar hover IN  → `scheduleExpand()`   (fires after `expandDelay`)
/// - Bar hover OUT → `cancelExpand()`     (cancels pending expand)
/// - Panel hover IN  → `cancelCollapse()` (mouse re-entered, abort collapse)
/// - Panel hover OUT → `scheduleCollapse()` (fires after `collapseDelay`)
@MainActor
public final class IslandCoordinator {
    public static let shared = IslandCoordinator()

    public enum Mode: Equatable {
        case collapsed
        case expanded
    }

    public private(set) var mode: Mode = .collapsed

    /// Called on the main thread whenever `mode` actually changes.
    public var onModeChange: ((Mode) -> Void)?

    public static let expandDelay: TimeInterval = 0.12
    public static let collapseDelay: TimeInterval = 0.30

    private var expandTimer: Timer?
    private var collapseTimer: Timer?

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
        mode = newMode
        onModeChange?(mode)
    }

    private func cancelAllTimers() {
        expandTimer?.invalidate(); expandTimer = nil
        collapseTimer?.invalidate(); collapseTimer = nil
    }
}
