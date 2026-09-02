import AppKit
import IslandCore
import Observation

/// Standard menu-bar (`NSStatusItem`) presence for Dev Island.
///
/// The island capsule floats near the notch, which is glanceable but
/// doesn't read as "this app is running" the way a status-bar icon does —
/// and on Macs where the capsule is hidden behind a busy menu bar (or the
/// user just doesn't know where to look), there was no affordance at all.
/// This item is the conventional signal: icon present = backend running.
///
/// The menu is rebuilt each time it opens (`menuNeedsUpdate`). The status
/// button also tracks the same low-cardinality snapshot continuously, so its
/// tooltip and VoiceOver value remain useful before the menu is opened.
@MainActor
public final class StatusItemController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var languageObserver: NSObjectProtocol?
    private var expiryRefreshWorkItem: DispatchWorkItem?

    public override init() {
        super.init()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        if let button = item.button {
            button.image = Self.menuBarImage()
        }

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        refreshStatusButton()
        observeStore()
        languageObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStatusButton()
            }
        }
    }

    // No deinit/removeStatusItem: the controller is created once in
    // applicationDidFinishLaunching and lives for the app's lifetime.

    // MARK: - NSMenuDelegate

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let store = TaskStore.shared
        let language = DevIslandLanguage.current
        let snapshot = StatusMenuPresentation.snapshot(
            tasks: store.tasks,
            localAgentStatus: store.localHookServiceStatus,
            apiKeyStatus: store.apiKeyStatus,
            connectionStatus: store.connectionStatus,
            language: language
        )
        apply(snapshot, tasks: store.tasks)

        // Status lines: disabled items, purely informational.
        menu.addItem(disabledItem(snapshot.overview))
        if let today = DailyActivityPresentation.summaryLine(
            store.todayActivity,
            language: language
        ) {
            menu.addItem(disabledItem(today))
        }
        menu.addItem(disabledItem(snapshot.localAgents))
        menu.addItem(disabledItem(snapshot.manus))
        // Numbers shown above come from the last refresh; start the next one
        // so the following open is current without ever polling.
        Task { await store.refreshTodayActivity() }

        menu.addItem(.separator())

        menu.addItem(actionItem(
            L10n.string("Open Island", language: language),
            #selector(openPanel),
            key: "p"
        ))
        menu.addItem(actionItem(
            L10n.string("Settings…", language: language),
            #selector(openSettings),
            key: ","
        ))
        menu.addItem(actionItem(
            L10n.string("Welcome Tour…", language: language),
            #selector(openWelcomeTour),
            key: ""
        ))

        let updates = AppUpdateController.shared
        let updateItem = actionItem(
            L10n.string("Check for Updates…", language: language),
            #selector(checkForUpdates),
            key: ""
        )
        updateItem.isEnabled = updates.canCheckForUpdates
        updateItem.toolTip = StatusMenuPresentation.updateHelp(
            status: updates.status,
            canCheckForUpdates: updates.canCheckForUpdates,
            language: language
        )
        menu.addItem(updateItem)

        menu.addItem(.separator())

        menu.addItem(actionItem(
            L10n.string("Quit Dev Island", language: language),
            #selector(quit),
            key: "q"
        ))
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

    @objc private func checkForUpdates() {
        AppUpdateController.shared.checkForUpdates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Live status

    /// Observation tracking is one-shot. Reinstall it after each mutation so
    /// status updates stay event-driven rather than introducing a permanent
    /// menu-bar polling timer.
    private func observeStore() {
        withObservationTracking {
            refreshStatusButton()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeStore()
            }
        }
    }

    private func refreshStatusButton() {
        let store = TaskStore.shared
        let now = Date.now
        let snapshot = StatusMenuPresentation.snapshot(
            tasks: store.tasks,
            localAgentStatus: store.localHookServiceStatus,
            apiKeyStatus: store.apiKeyStatus,
            connectionStatus: store.connectionStatus,
            now: now,
            language: .current
        )
        apply(snapshot, tasks: store.tasks, now: now)
    }

    private func apply(
        _ snapshot: StatusMenuSnapshot,
        tasks: [AgentTask],
        now: Date = .now
    ) {
        if let button = statusItem?.button {
            button.toolTip = snapshot.overview
            button.setAccessibilityLabel(
                L10n.string("Dev Island", language: snapshot.language)
            )
            button.setAccessibilityValue(snapshot.accessibilityValue)
            button.setAccessibilityHelp(
                L10n.string(
                    "Opens the Dev Island status menu",
                    language: snapshot.language
                )
            )
        }
        scheduleExpiryRefresh(tasks: tasks, now: now)
    }

    /// A recent completion temporarily owns the attention-first headline.
    /// Schedule only the exact expiry edge so the status button returns to
    /// active work on time without a repeating clock.
    private func scheduleExpiryRefresh(tasks: [AgentTask], now: Date) {
        expiryRefreshWorkItem?.cancel()
        expiryRefreshWorkItem = nil

        let nextExpiry = StatusMenuPresentation.nextRefreshDate(
            tasks: tasks,
            now: now
        )
        guard let nextExpiry else { return }

        let workItem = DispatchWorkItem { [weak self] in
            self?.refreshStatusButton()
        }
        expiryRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0, nextExpiry.timeIntervalSince(now)),
            execute: workItem
        )
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
