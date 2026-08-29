#if DEBUG
import AppKit
import SwiftUI
import IslandCore

/// Host window for `DebugSandboxView` (CLAUDE_CLIENT.md §6 task 10).
///
/// A regular titled NSWindow — NOT borderless / not status-bar level — so
/// it behaves like any other dev tool: draggable, closeable, lives in the
/// app switcher area. Sized once to its content; the sandbox view has a
/// fixed 360pt width and intrinsic height.
///
/// Lifecycle is owned by `AppDelegate`, gated on `#if DEBUG`. Production
/// builds never reference this type.
public final class DebugSandboxWindow: NSWindow {
    private let onDidClose: @MainActor () -> Void
    private var hasReportedClose = false

    public init(
        onReposition: @escaping () -> Void,
        onDidClose: @escaping @MainActor () -> Void = {}
    ) {
        self.onDidClose = onDidClose
        // Initial size is a placeholder — `setContentSize(_:)` after the
        // hosting view computes its intrinsic size below.
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        title = "Island — Debug Sandbox"
        isReleasedWhenClosed = false
        // Float above ordinary windows so you don't lose it behind the
        // editor while iterating, but don't go to .statusBar — that would
        // outrank the IslandWindow we're trying to inspect.
        level = .floating

        let host = NSHostingView(
            rootView: LocalizedAppRoot {
                DebugSandboxView(onReposition: onReposition)
            }
        )
        host.translatesAutoresizingMaskIntoConstraints = true
        contentView = host

        // Snap the window to the SwiftUI content's intrinsic size so the
        // titlebar fits flush around the controls.
        let fittingSize = host.fittingSize
        setContentSize(fittingSize)

        // Park it in the bottom-right of the main screen so it doesn't
        // overlap the island.
        if let screenFrame = NSScreen.main?.visibleFrame {
            let margin: CGFloat = 24
            setFrameOrigin(NSPoint(
                x: screenFrame.maxX - fittingSize.width - margin,
                y: screenFrame.minY + margin
            ))
        }
    }

    public override func close() {
        let shouldReport = !hasReportedClose
        super.close()
        guard shouldReport else { return }
        hasReportedClose = true
        onDidClose()
    }
}
#endif
