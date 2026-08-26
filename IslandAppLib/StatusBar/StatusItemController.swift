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
        let headline = statusHeadline(for: TaskStatusSummary(tasks: store.tasks))
        menu.addItem(disabledItem(headline))
        let localAgents = LocalAgentRegistry.all.map(\.displayName).joined(separator: " / ")
        menu.addItem(disabledItem("本地管线:\(localAgents)"))
        menu.addItem(disabledItem("Manus:\(manusStatusText(store))"))

        menu.addItem(.separator())

        menu.addItem(actionItem("打开面板", #selector(openPanel), key: "p"))
        menu.addItem(actionItem("设置…", #selector(openSettings), key: ","))
        menu.addItem(actionItem("欢迎导览…", #selector(openWelcomeTour), key: ""))

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

    @objc private func openWelcomeTour() {
        NotificationCenter.default.post(name: .islandOpenOnboardingRequested, object: nil)
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

    private func statusHeadline(for summary: TaskStatusSummary) -> String {
        guard let segment = summary.foregroundSegment else { return "后台运行中" }

        switch segment.status {
        case .waiting:   return "\(segment.count) 个会话等待你处理"
        case .failed:    return "\(segment.count) 个任务需要检查"
        case .completed: return "\(segment.count) 个任务已完成"
        case .running:   return "\(segment.count) 个任务正在运行"
        }
    }

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
