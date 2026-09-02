import SwiftUI
import AppKit
import IslandAppLib
import IslandCore

@main
struct IslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Keep this SwiftUI-owned scene deliberately inert. `SettingsView`
        // binds to `TaskStore.shared`; constructing it while SwiftUI evaluates
        // the root Scene could bootstrap SQLite, Keychain and the local
        // listener before AppDelegate's single-instance gate runs. The real
        // Settings surface is created lazily by the AppDelegate-owned
        // `SettingsWindow` after launch arbitration succeeds.
        //
        // Replacing the scene's default Command-, entry keeps the native
        // shortcut useful without letting SwiftUI create a second settings
        // window beside that explicitly-owned surface.
        Settings {
            EmptyView()
        }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button {
                        NotificationCenter.default.post(
                            name: .islandOpenSettingsRequested,
                            object: nil
                        )
                    } label: {
                        Text(L10n.string("Settings…"))
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// A duplicate copy exits before constructing windows, services or launch
    /// health state. Its termination callback must therefore remain a no-op.
    private var yieldedToExistingInstance = false
    private let terminationCoordinator = AppTerminationCoordinator()
    private var islandWindow: IslandWindow?
    private var screenChangeObserver: NSObjectProtocol?
    private var openSettingsObserver: NSObjectProtocol?
    private var openOnboardingObserver: NSObjectProtocol?

    #if DEV_ISLAND_PERFORMANCE_QA
    /// A recursive main-queue work item drives the isolated transition
    /// fixture without bringing a timer or synthetic interaction path into
    /// production. Each edge publishes a stable marker so retained app logs
    /// can be aligned with Animation Hitches traces.
    private var performanceTransitionWorkItem: DispatchWorkItem?
    private var performanceTransitionIteration = 0
    /// `xctrace --target-stdout` owns a pipe whose reader can pause while a
    /// deferred trace is compressed. Never let evidence I/O block the main
    /// actor and become the hitch the fixture is trying to measure.
    private let performanceMarkerQueue = DispatchQueue(
        label: "app.devisland.performance-markers",
        qos: .utility
    )
    #endif

    #if !DEV_ISLAND_PERFORMANCE_QA
    /// Repository-owned CI can launch the real production executable without
    /// touching user state. Normal Finder/LaunchServices starts have neither
    /// half of the exact opt-in pair and therefore keep ordinary behavior.
    private let isHermeticLaunchSmoke =
        HermeticAppLaunchMode.isEnabledForCurrentProcess
    private let hermeticLaunchMarkerQueue = DispatchQueue(
        label: "app.devisland.hermetic-launch-markers",
        qos: .utility
    )
    #endif

    /// `LSUIElement` keeps cold launch out of the Dock. Conventional windows
    /// acquire leases here and temporarily promote the process to `.regular`;
    /// the island panel itself never does, so quick glances stay lightweight.
    private let dockVisibility = DockVisibilityCoordinator()
    private var settingsDockLease: DockVisibilityLease?
    private var onboardingDockLease: DockVisibilityLease?
    private var applicationToRestoreAfterFullWindow: NSRunningApplication?

    /// Lazily-created so we don't pay the SwiftUI view-construction cost
    /// until the user actually opens settings. Re-used across opens —
    /// the second gear tap brings the same window forward instead of
    /// stacking a new one.
    private var settingsWindow: SettingsWindow?
    private var onboardingWindow: OnboardingWindow?

    /// Welcome can outlive its own window while macOS presents the
    /// notification authorization sheet. Keep the eventual destination and
    /// any reopen request as flow state so commands received during that
    /// async gap are handed off without creating two tours or losing Dock
    /// ownership.
    private enum OnboardingExitDestination {
        case island
        case settings
    }

    private var onboardingExitDestination: OnboardingExitDestination = .island
    private var onboardingIsFinishing = false
    private var onboardingAuthorizationInFlight = false
    private var reopenOnboardingAfterCurrentFlow = false

    /// Conventional menu-bar icon (`NSStatusItem`): visible whenever the
    /// app — and therefore the local hook backend — is running. Menu
    /// carries live status lines plus panel/settings/quit shortcuts.
    private var statusItemController: StatusItemController?

    /// NSEvent monitors that are alive only while the panel is expanded.
    /// Global monitors fire for events going to OTHER apps (so clicks on
    /// the desktop / Finder / another app trigger collapse), and the
    /// keyDown global monitor catches Esc regardless of which app is key.
    /// Cleared on every collapse so we don't leak handlers.
    private var panelEventMonitors: [Any] = []

    #if DEBUG
    /// In-app sandbox for driving the island without Manus (CLAUDE_CLIENT.md
    /// §6 task 10). Only ever instantiated in DEBUG builds.
    private var debugSandboxWindow: DebugSandboxWindow?
    private var debugSandboxDockLease: DockVisibilityLease?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if !DEV_ISLAND_PERFORMANCE_QA
        // Finder, a mounted DMG and a development build can otherwise run
        // separate processes with the same bundle ID. Keep hermetic smoke
        // explicitly exempt so repository QA can inspect a Production artifact
        // without disturbing the user's installed App.
        if !isHermeticLaunchSmoke,
           AppSingleInstanceGate.activateExistingInstanceIfNeeded() {
            yieldedToExistingInstance = true
            NSApp.terminate(nil)
            return
        }

        // Arm a local-only startup marker before constructing any UI. It is
        // closed only after the island and menu-bar surfaces survive a short
        // stability window; no crash report is inspected or uploaded, and the
        // hermetic performance build never touches the marker.
        if !isHermeticLaunchSmoke {
            LaunchHealthTracker.shared.beginLaunch()
        }
        #endif

        let window = IslandWindow()
        window.makeKeyAndOrderFront(nil)
        self.islandWindow = window

        // §6 task-1 gotcha: the initial `.accessory` policy must be applied
        // AFTER makeKeyAndOrderFront on the always-on island window,
        // otherwise nothing shows.
        dockVisibility.synchronize()
        // The launch order above remains passive because IslandWindow starts
        // with canBecomeKey=false. Arm keyboard focus only now: an intentional
        // click can enter the approval/question surface, while automatic
        // request expansion never steals focus from the user's editor.
        window.enableKeyboardInteraction()

        #if DEBUG
        // Open the Debug Sandbox alongside the island so every dev launch
        // has live controls without any extra step. Release builds skip
        // this entire block (and don't link the sandbox types at all).
        debugSandboxDockLease = acquireDockLease(.debugSandbox)
        let sandbox = DebugSandboxWindow(
            onReposition: { [weak self] in
                self?.islandWindow?.reposition()
            },
            onDidClose: { [weak self] in
                self?.releaseDebugSandboxDockLease()
            }
        )
        sandbox.orderFront(nil)
        self.debugSandboxWindow = sandbox
        #endif

        // Bridge coordinator mode → AppKit-side concerns (event monitors).
        // The visual morph is driven entirely inside `IslandRootView` via
        // SwiftUI's withAnimation; AppDelegate no longer touches alpha.
        IslandCoordinator.shared.onModeChange = { [weak self] mode in
            guard let self else { return }
            switch mode {
            case .collapsed:
                self.islandWindow?.releaseKeyboardInteraction()
                self.removePanelEventMonitors()
            case .expanded:
                self.installPanelEventMonitors()
            }
        }

        // Re-pin the window when displays change (Task 8 multi-screen).
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.islandWindow?.reposition()
            }
        }

        // Settings window plumbing. Panel's gear button posts this
        // notification (defined in IslandAppLib's SettingsWindow.swift);
        // we lazily create / focus the window here so the SwiftUI side
        // stays free of AppKit window references.
        openSettingsObserver = NotificationCenter.default.addObserver(
            forName: .islandOpenSettingsRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.openSettings()
            }
        }

        openOnboardingObserver = NotificationCenter.default.addObserver(
            forName: .islandOpenOnboardingRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.openOnboarding()
            }
        }

        #if !DEV_ISLAND_PERFORMANCE_QA
        // Banner notifications for task state transitions. This attaches the
        // observer but does not request permission; the Welcome Tour's final
        // action or an explicit Settings toggle owns that decision.
        // (running → completed, * → waiting). Owns its own
        // UNUserNotificationCenter delegate + observation re-arming
        // loop; we just kick it off once.
        if !isHermeticLaunchSmoke {
            TaskNotifier.shared.start()
            // System-wide ⌃⌥⌘Y / ⌃⌥⌘N for the front permission request. Carbon
            // hot keys reach a background app without Accessibility access.
            GlobalDecisionShortcutService.shared.start()
        }
        #endif

        // Conventional status-bar presence: icon visible = backend running.
        statusItemController = StatusItemController()

        #if DEV_ISLAND_PERFORMANCE_QA
        // Emit one low-cardinality readiness timestamp only in the hermetic,
        // never-publish performance bundle. The sampler subtracts the uptime
        // captured immediately before process launch, giving us a reproducible
        // launch-to-first-laid-out-island metric without touching user state.
        signalPerformanceReadiness(afterLayingOut: window)
        #endif

        #if !DEV_ISLAND_PERFORMANCE_QA
        if isHermeticLaunchSmoke {
            signalHermeticLaunchReadiness(afterLayingOut: window)
        }
        #endif

        #if !DEV_ISLAND_PERFORMANCE_QA
        // Sparkle starts only when the signed release bundle contains the
        // complete HTTPS + Ed25519 trust configuration. Local QA builds stay
        // deliberately inert instead of touching an unsigned update feed.
        if !isHermeticLaunchSmoke {
            AppUpdateController.shared.start()
        }
        #endif

        // First launch is one composed experience: the island stays quiet
        // behind the Welcome Tour, then expands after the tour closes. The
        // old ordering expanded the panel first and opened onboarding on
        // top 200ms later, making two windows compete for attention during
        // the product's most important first impression.
        #if DEV_ISLAND_PERFORMANCE_QA
        // Dedicated QA builds are hermetic: no onboarding, notifications,
        // Keychain, SQLite, Hook server, Manus, or update network. The
        // compile-time marker prevents this path from entering production.
        IslandCoordinator.shared.collapse()
        if PerformanceFixture.shouldExpand {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                IslandCoordinator.shared.expand()
            }
        } else if let interval = PerformanceFixture.transitionInterval {
            scheduleNextPerformanceTransition(
                after: PerformanceFixture.transitionInitialDelay,
                interval: interval
            )
        }
        #else
        if isHermeticLaunchSmoke {
            IslandCoordinator.shared.collapse()
        } else {
            let defaults = UserDefaults.standard
            let needsOnboarding = !defaults.bool(forKey: OnboardingWindow.completionKey)
            if needsOnboarding {
                IslandCoordinator.shared.collapse()
                DispatchQueue.main.async { [weak self] in
                    self?.openOnboarding()
                }
            }

            scheduleStartupHealthMilestone(afterLayingOut: window)
        }
        #endif
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        #if DEV_ISLAND_PERFORMANCE_QA
        let mode = AppTerminationMode.performanceQA
        #else
        let mode: AppTerminationMode
        if yieldedToExistingInstance {
            mode = .yieldedDuplicate
        } else if isHermeticLaunchSmoke {
            mode = .hermeticLaunchSmoke
        } else {
            mode = .owner
        }
        #endif

        let decision = terminationCoordinator.requestTermination(
            mode: mode,
            cleanup: {
                _ = await TaskStore.shared.shutdown()
            },
            reply: {
                sender.reply(toApplicationShouldTerminate: true)
            }
        )

        switch decision {
        case .terminateNow:
            return .terminateNow
        case .terminateLater:
            return .terminateLater
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !yieldedToExistingInstance else { return }

        #if DEV_ISLAND_PERFORMANCE_QA
        performanceTransitionWorkItem?.cancel()
        performanceTransitionWorkItem = nil
        #endif

        #if !DEV_ISLAND_PERFORMANCE_QA
        // A deliberate Quit during the short stability window is not a launch
        // loop. Close the marker before tearing down services so it cannot be
        // mistaken for an interrupted startup on the next run.
        if !isHermeticLaunchSmoke {
            LaunchHealthTracker.shared.markStartupReady()
            GlobalDecisionShortcutService.shared.stop()
        }
        #endif
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = openSettingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = openOnboardingObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        removePanelEventMonitors()
    }

    #if DEV_ISLAND_PERFORMANCE_QA
    private func signalPerformanceReadiness(afterLayingOut window: IslandWindow) {
        // One main-runloop turn lets the initial SwiftUI/AppKit transaction
        // settle after the window and status item are both installed.
        DispatchQueue.main.async {
            window.contentView?.layoutSubtreeIfNeeded()
            window.contentView?.displayIfNeeded()
            let uptime = ProcessInfo.processInfo.systemUptime
            self.writePerformanceMarker(
                "DEV_ISLAND_PERFORMANCE_READY uptime=\(uptime)\n"
            )
        }
    }

    private func scheduleNextPerformanceTransition(
        after delay: TimeInterval,
        interval: TimeInterval
    ) {
        performanceTransitionWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }

            self.performanceTransitionIteration += 1
            let target: IslandCoordinator.Mode =
                self.performanceTransitionIteration.isMultiple(of: 2)
                ? .collapsed
                : .expanded

            switch target {
            case .collapsed:
                IslandCoordinator.shared.collapse()
            case .expanded:
                IslandCoordinator.shared.expand()
            }

            let uptime = ProcessInfo.processInfo.systemUptime
            let targetName = target == .expanded ? "expanded" : "collapsed"
            let line = "DEV_ISLAND_PERFORMANCE_TRANSITION iteration=\(self.performanceTransitionIteration) target=\(targetName) uptime=\(uptime)\n"
            self.writePerformanceMarker(line)

            self.scheduleNextPerformanceTransition(after: interval, interval: interval)
        }
        performanceTransitionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func writePerformanceMarker(_ line: String) {
        let data = Data(line.utf8)
        performanceMarkerQueue.async {
            FileHandle.standardOutput.write(data)
        }
    }
    #endif

    #if !DEV_ISLAND_PERFORMANCE_QA
    private func signalHermeticLaunchReadiness(
        afterLayingOut window: IslandWindow
    ) {
        // One main-runloop turn proves the real Production App constructed and
        // laid out both the island and status item. Marker I/O stays off the
        // main actor; the verifier continuously drains its private App log.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self,
                  let window,
                  self.islandWindow === window,
                  window.isVisible,
                  self.statusItemController != nil else { return }
            window.contentView?.layoutSubtreeIfNeeded()
            window.contentView?.displayIfNeeded()
            let uptime = ProcessInfo.processInfo.systemUptime
            let marker = "DEV_ISLAND_PRODUCTION_READY uptime=\(uptime)\n"
            let data = Data(marker.utf8)
            self.hermeticLaunchMarkerQueue.async {
                FileHandle.standardOutput.write(data)
            }
        }
    }

    private func scheduleStartupHealthMilestone(afterLayingOut window: IslandWindow) {
        DispatchQueue.main.asyncAfter(
            deadline: .now() + LaunchHealthTracker.startupStabilityDelay
        ) { [weak self, weak window] in
            guard let self,
                  let window,
                  self.islandWindow === window,
                  window.isVisible,
                  self.statusItemController != nil else { return }

            // Flush the first AppKit/SwiftUI layout before recording ready.
            // If construction, rendering, or the first main-runloop work
            // terminates the process, this closure never writes the marker.
            window.contentView?.layoutSubtreeIfNeeded()
            window.contentView?.displayIfNeeded()
            LaunchHealthTracker.shared.markStartupReady()
        }
    }
    #endif

    /// Dev Island is a menu-bar utility. Closing its only conventional
    /// window (the borderless Welcome Tour) must never terminate the
    /// background agent monitor or remove the island itself.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the temporary Dock icon restores the conventional surface
    /// that owns it. Miniaturized Settings behaves like a normal Mac window;
    /// the always-on island remains excluded from this path.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if onboardingDockLease != nil {
            if let onboardingWindow, !onboardingIsFinishing {
                onboardingWindow.makeKeyAndOrderFront(nil)
                return false
            }

            // While macOS owns the notification sheet, retain AppKit's
            // default Dock reopen behavior so the system surface can become
            // active. During our own short fade/handoff, never fall through
            // to a hidden Settings window. A tour returning to the island is
            // treated as explicitly reopened; a tour already routing to
            // Settings simply completes that transition.
            if onboardingAuthorizationInFlight {
                return true
            }
            switch onboardingExitDestination {
            case .island:
                reopenOnboardingAfterCurrentFlow = true
            case .settings:
                break
            }
            return false
        }

        if let settingsWindow, settingsDockLease != nil {
            if settingsWindow.isMiniaturized {
                settingsWindow.deminiaturize(nil)
            }
            settingsWindow.bringToFront()
            return false
        }

        #if DEBUG
        if let debugSandboxWindow, debugSandboxDockLease != nil {
            if debugSandboxWindow.isMiniaturized {
                debugSandboxWindow.deminiaturize(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
            debugSandboxWindow.makeKeyAndOrderFront(nil)
            return false
        }
        #endif

        // An authorization sheet can temporarily own the Dock lease after
        // the tour window has faded away. Let AppKit perform its default
        // reopen behavior so that system-owned surface can be reactivated.
        return true
    }

    // MARK: - Settings

    private func openSettings() {
        // Keep one visual focal point. If Settings is requested while the
        // Welcome flow is up (including its notification-authorization gap),
        // make Settings the next destination. The finishing flow keeps its
        // Dock lease until Settings has acquired its own, so the icon never
        // flickers between the two surfaces.
        if onboardingDockLease != nil {
            onboardingExitDestination = .settings
            reopenOnboardingAfterCurrentFlow = false
            if !onboardingIsFinishing {
                onboardingWindow?.performClose(nil)
            }
            return
        }

        ensureSettingsDockLease()

        if let existing = settingsWindow {
            existing.bringToFront()
            return
        }
        let window = SettingsWindow { [weak self] in
            self?.releaseSettingsDockLease()
        }
        settingsWindow = window
        window.bringToFront()
    }

    private func openOnboarding() {
        // Once dismissal begins, the window disappears before an optional
        // system authorization sheet completes. Queue a fresh tour instead
        // of reusing the closing flow's lease; completion will acquire the
        // new lease before releasing the old one.
        if onboardingIsFinishing
            || (onboardingDockLease != nil && onboardingWindow == nil) {
            reopenOnboardingAfterCurrentFlow = true
            return
        }

        if let existing = onboardingWindow {
            existing.bringToFront()
            return
        }

        beginOnboarding()
    }

    private func beginOnboarding(
        returningTo destination: OnboardingExitDestination? = nil
    ) {
        // Keep only one visual focal point. When the tour is reopened from
        // the menu-bar item, collapse the island before raising the window.
        IslandCoordinator.shared.collapse()
        ensureOnboardingDockLease()

        let exitDestination = destination
            ?? (settingsWindow?.isVisible == true ? .settings : .island)
        onboardingExitDestination = exitDestination
        onboardingIsFinishing = false
        onboardingAuthorizationInFlight = false
        reopenOnboardingAfterCurrentFlow = false
        if exitDestination == .settings {
            settingsWindow?.orderOut(nil)
        }

        let window = OnboardingWindow(screen: islandWindow?.screen) { [weak self] requestsAuthorization in
            UserDefaults.standard.set(true, forKey: OnboardingWindow.completionKey)
            guard let self else { return }
            self.onboardingIsFinishing = true
            guard let closingWindow = self.onboardingWindow else {
                self.completeOnboardingFlow()
                return
            }
            closingWindow.dismiss { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.onboardingWindow = nil

                    if requestsAuthorization {
                        self.onboardingAuthorizationInFlight = true
                        await TaskNotifier.shared.requestAuthorizationIfNeeded()
                        self.onboardingAuthorizationInFlight = false
                    }

                    try? await Task.sleep(for: .milliseconds(80))
                    self.completeOnboardingFlow()
                }
            }
        }
        onboardingWindow = window
        window.bringToFront()
    }

    /// Finish one Welcome flow with an atomic Dock handoff. The old lease is
    /// deliberately released last: Settings or a queued replacement tour
    /// first establishes its own ownership, preventing an accessory/regular
    /// flash between conventional windows.
    private func completeOnboardingFlow() {
        let finishingLease = onboardingDockLease
        let destination = onboardingExitDestination
        let shouldReopen = reopenOnboardingAfterCurrentFlow

        onboardingWindow = nil
        onboardingDockLease = nil
        onboardingIsFinishing = false
        onboardingAuthorizationInFlight = false
        reopenOnboardingAfterCurrentFlow = false
        onboardingExitDestination = .island

        if shouldReopen {
            beginOnboarding(returningTo: destination)
        } else {
            switch destination {
            case .island:
                IslandCoordinator.shared.expand()
            case .settings:
                openSettings()
            }
        }

        if let finishingLease {
            releaseDockLease(finishingLease)
        }
    }

    // MARK: - Dock presence

    private func ensureSettingsDockLease() {
        guard settingsDockLease == nil else { return }
        settingsDockLease = acquireDockLease(.settings)
    }

    private func releaseSettingsDockLease() {
        guard let lease = settingsDockLease else { return }
        settingsDockLease = nil
        releaseDockLease(lease)
    }

    private func ensureOnboardingDockLease() {
        guard onboardingDockLease == nil else { return }
        onboardingDockLease = acquireDockLease(.onboarding)
    }

    private func acquireDockLease(
        _ reason: DockVisibilityReason
    ) -> DockVisibilityLease {
        if dockVisibility.desiredPolicy == .accessory {
            let frontmost = NSWorkspace.shared.frontmostApplication
            let ownPID = ProcessInfo.processInfo.processIdentifier
            applicationToRestoreAfterFullWindow = frontmost?.processIdentifier == ownPID
                ? nil
                : frontmost
        }
        return dockVisibility.acquire(reason)
    }

    private func releaseDockLease(_ lease: DockVisibilityLease) {
        dockVisibility.release(lease)
        guard dockVisibility.desiredPolicy == .accessory else { return }

        let application = applicationToRestoreAfterFullWindow
        applicationToRestoreAfterFullWindow = nil
        if let application, !application.isTerminated {
            // Cooperative activation is more reliable than a one-sided
            // request on macOS 14+: explicitly yield from Dev Island, then
            // ask the previous foreground app to take activation from us.
            NSApp.yieldActivation(to: application)
            let accepted = application.activate(
                from: NSRunningApplication.current,
                options: []
            )
            if !accepted {
                NSApp.deactivate()
            }
        } else {
            NSApp.deactivate()
        }
    }

    #if DEBUG
    private func releaseDebugSandboxDockLease() {
        guard let lease = debugSandboxDockLease else { return }
        debugSandboxDockLease = nil
        releaseDockLease(lease)
    }
    #endif

    // MARK: - Panel-only event monitors

    /// Install Esc + click-outside monitors. CLAUDE_CLIENT.md §2 trigger
    /// spec: "点外部 / Esc 收起".
    ///
    /// The click monitor is global: before direct engagement the editor stays
    /// key, while clicking the island makes its borderless window key. Global
    /// monitors only fire for events targeted at OTHER apps, so clicks on the
    /// visible shape itself don't trigger a collapse in either phase.
    ///
    /// Esc needs both legs. The global one covers the normal case (the
    /// user's editor is still focused) but is inert until the app is
    /// trusted for Accessibility — see `InputPermissions`. The local one
    /// covers the case where our own app happens to be active, needs no
    /// authorization, and consumes the event so Esc doesn't also reach
    /// whatever view is focused.
    private func installPanelEventMonitors() {
        guard panelEventMonitors.isEmpty else { return }

        // 53 = Escape (kVK_Escape).
        if let escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
            if event.keyCode == 53 {
                Task { @MainActor in IslandCoordinator.shared.collapse() }
            }
        }) {
            panelEventMonitors.append(escMonitor)
        }

        if let localEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            guard event.keyCode == 53 else { return event }
            Task { @MainActor in IslandCoordinator.shared.collapse() }
            return nil
        }) {
            panelEventMonitors.append(localEscMonitor)
        }

        if let clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { _ in
                Task { @MainActor in IslandCoordinator.shared.collapse() }
            }
        ) {
            panelEventMonitors.append(clickMonitor)
        }
    }

    private func removePanelEventMonitors() {
        for monitor in panelEventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        panelEventMonitors.removeAll()
    }
}
