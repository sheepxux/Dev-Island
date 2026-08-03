import AppKit
import os

// SkyLight (WindowServer) private connection property that lets a
// NON-ACTIVE app set the mouse cursor.
//
// Why we need it: Dev Island is an `.accessory` app whose island window
// never activates. macOS only honors `NSCursor.set()` from the active
// app — or, briefly, from any app while it is processing a mouse-down —
// which is exactly the symptom we shipped: the pointing hand appeared
// during clicks but never on hover. With this property set, the window
// server accepts our cursor writes while we're in the background, and the
// 25Hz re-assert in `IslandWindow.tickMouseTracking` becomes effective.
//
// Private API, but long-stable and widely shipped (Alt-Tab, Rectangle,
// MiddleClick…). We distribute outside the App Store, so no review
// constraint applies. Failure is graceful: if a future macOS drops the
// property the call returns an error and the cursor simply stays an
// arrow — the pre-fix behavior.
private typealias CGSConnectionID = UInt32

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSSetConnectionProperty")
private func CGSSetConnectionProperty(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ key: CFString,
    _ value: CFTypeRef
) -> CGError

enum BackgroundCursor {
    /// Idempotent; call once at startup before any cursor writes.
    static func enable() {
        let connection = CGSMainConnectionID()
        let result = CGSSetConnectionProperty(
            connection,
            connection,
            "SetsCursorInBackground" as CFString,
            kCFBooleanTrue
        )
        if result != .success {
            Logger(subsystem: "app.devisland.Island", category: "window")
                .warning("SetsCursorInBackground failed (\(result.rawValue)) — hover cursor will stay an arrow")
        }
    }
}
