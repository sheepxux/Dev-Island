import AppKit
import IslandCore

/// Standard menu-bar (`NSStatusItem`) presence for Dev Island.
///
/// The island capsule floats near the notch, which is glanceable but
/// doesn't read as "this app is running" the way a status-bar icon does —
/// and on Macs where the capsule is hidden behind a busy menu bar (or the
/// user just doesn't know where to look), there was no affordance at all.
/// This item is the conventional signal: icon present = backend running.
///
/// The menu is rebuilt each time it opens (`menuNeedsUpdate`) so the
/// status lines always reflect the live `TaskStore` state without any
/// observation plumbing.
@MainActor
public final class StatusItemController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?

    public override init() {
        super.init()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        if let button = item.button {
            button.image = Self.menuBarImage()
            button.toolTip = "Dev Island — 后台运行中"
        }

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    // No deinit/removeStatusItem: the controller is created once in
    // applicationDidFinishLaunching and lives for the app's lifetime.

    // MARK: - NSMenuDelegate

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let store = TaskStore.shared

        // Status lines: disabled items, purely informational.
        let running = store.tasks.filter { $0.status == .running }.count
        let waiting = store.tasks.filter { $0.status == .waiting }.count
        var headline = "后台运行中"
        if running > 0 { headline += " — \(running) 个任务进行中" }
        if waiting > 0 { headline += ",\(waiting) 个等待输入" }
        menu.addItem(disabledItem(headline))
        menu.addItem(disabledItem("本地管线:Claude Code / Codex / Cursor"))
        menu.addItem(disabledItem("Manus:\(manusStatusText(store))"))

        menu.addItem(.separator())

        menu.addItem(actionItem("打开面板", #selector(openPanel), key: "p"))
        menu.addItem(actionItem("设置…", #selector(openSettings), key: ","))

        menu.addItem(.separator())

        menu.addItem(actionItem("退出 Dev Island", #selector(quit), key: "q"))
    }

    // MARK: - Actions

    @objc private func openPanel() {
        IslandCoordinator.shared.expand()
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: .islandOpenSettingsRequested, object: nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Icon

    /// Designer-supplied icon first, SF Symbol fallback second.
    ///
    /// Drop `MenuBarIcon.png` (18×18) + `MenuBarIcon@2x.png` (36×36) into
    /// `IslandApp/Resources/` and they're picked up with no code change —
    /// black shapes on transparent background; `isTemplate` lets macOS
    /// tint them for dark/light menu bars automatically.
    private static func menuBarImage() -> NSImage? {
        let image: NSImage?
        if let custom = NSImage(named: "MenuBarIcon") {
            custom.size = NSSize(width: 18, height: 18)
            image = custom
        } else {
            // Interim brand mark: the island capsule shape.
            image = NSImage(
                systemSymbolName: "capsule.fill",
                accessibilityDescription: "Dev Island"
            )
        }
        image?.isTemplate = true
        return image
    }

    // MARK: - Helpers

    private func manusStatusText(_ store: TaskStore) -> String {
        guard store.apiKeyStatus == .valid else { return "未配置" }
        switch store.connectionStatus {
        case .connected:            return "已连接"
        case .reconnecting:         return "重连中…"
        case .degraded(let reason): return "降级(\(reason))"
        case .disconnected:         return "未连接"
        }
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
}
