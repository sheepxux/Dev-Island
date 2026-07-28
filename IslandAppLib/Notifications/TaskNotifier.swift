import AppKit
import IslandCore
import Observation
import OSLog
import UserNotifications

/// Posts macOS banner notifications when `TaskStore.shared.tasks`
/// transitions through specific status changes (CLAUDE_CLIENT.md §6
/// task 5):
///
/// - `running → completed` → "Task Completed" banner
/// - any state `→ waiting` → "Task Needs Input" banner
///
/// Tap a banner to open the task's URL in the default browser via
/// `NSWorkspace.shared.open`. The URL is stashed in
/// `UNNotificationContent.userInfo["taskURL"]` and recovered in the
/// `UNUserNotificationCenterDelegate` callback.
///
/// Observation: TaskStore is `@Observable` (Swift 5.9 macro). We use
/// `withObservationTracking` and re-arm after each fire — the
/// non-SwiftUI canonical pattern. First observation pass establishes
/// a baseline so existing tasks at launch don't spam notifications.
@MainActor
public final class TaskNotifier: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = TaskNotifier()

    private static let log = Logger(subsystem: "app.devisland.Island", category: "notifier")

    /// Last seen task list, keyed by ID. We diff this against each new
    /// snapshot to find status transitions.
    private var previousTasksById: [String: AgentTask] = [:]

    /// First observation pass loads `previousTasksById` without firing
    /// any notifications — otherwise every existing task would trigger
    /// on launch (`running` already running, `waiting` already waiting,
    /// etc).
    private var hasBaseline = false

    private override init() { super.init() }

    /// True when the host bundle is a real `.app` (i.e., the kind of
    /// thing `xcodebuild` / `Xcode` Run produces). False when launched
    /// directly from SPM's `.build/debug/IslandApp` — that path has no
    /// `Info.plist` / bundle identifier, and `UNUserNotificationCenter.current()`
    /// throws an NSInternalInconsistencyException ("bundleProxyForCurrentProcess
    /// is nil") on first access. We use this as a graceful-degradation
    /// gate so dev builds via `swift run` don't crash on launch — they
    /// just silently skip banner posting. Real .app builds (and the
    /// eventual Homebrew Cask / Xcode-built artifact) get full
    /// notification support.
    public static var hasNotificationSupport: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Become the system notification delegate, request authorization,
    /// and start observing `TaskStore.shared.tasks` for transitions.
    /// Idempotent — safe to call once at app launch.
    public func start() {
        guard Self.hasNotificationSupport else {
            Self.log.info("Skipping UN setup — host is not a .app bundle (\(Bundle.main.bundleURL.path)). Run via Xcode/built .app to test banner notifications.")
            // Still observe so the diff machinery runs and we'd catch any
            // transition-detection bugs in dev. Just don't post banners.
            observeTaskStore()
            return
        }

        UNUserNotificationCenter.current().delegate = self

        Task {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound])
                Self.log.info("Notification authorization granted=\(granted)")
            } catch {
                Self.log.error("Notification auth failed: \(String(describing: error))")
            }
        }

        observeTaskStore()
    }

    // MARK: - Observation

    /// Re-arming `withObservationTracking` loop. The closure body reads
    /// every property we want to track for changes; `onChange` fires
    /// ONCE when any of them changes, after which we have to re-register.
    private func observeTaskStore() {
        withObservationTracking {
            _ = TaskStore.shared.tasks
        } onChange: {
            // onChange runs synchronously off the observed property's
            // setter — hop back to MainActor before touching anything
            // and re-arm observation.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleUpdate(TaskStore.shared.tasks)
                self.observeTaskStore()
            }
        }

        // Establish baseline on first call, no notifications.
        if !hasBaseline {
            handleUpdate(TaskStore.shared.tasks)
        }
    }

    private func handleUpdate(_ newTasks: [AgentTask]) {
        let newById = Dictionary(uniqueKeysWithValues: newTasks.map { ($0.id, $0) })

        if !hasBaseline {
            previousTasksById = newById
            hasBaseline = true
            Self.log.debug("Baseline set with \(newById.count) tasks")
            return
        }

        for (id, newTask) in newById {
            guard let oldTask = previousTasksById[id] else {
                // Brand-new task this update — no transition to fire on.
                // (If it arrived already in `.waiting`, we deliberately
                // skip it to avoid spamming on initial bootstrap of a
                // fresh API key configuration.)
                continue
            }
            guard oldTask.status != newTask.status else { continue }

            switch (oldTask.status, newTask.status) {
            case (.running, .completed):
                postCompletedNotification(task: newTask)
            case (_, .waiting):
                postWaitingNotification(task: newTask)
            default:
                break
            }
        }

        previousTasksById = newById
    }

    // MARK: - Posting

    private func postCompletedNotification(task: AgentTask) {
        guard Self.hasNotificationSupport else {
            Self.log.debug("(skip) running→completed for \(task.id) — no .app bundle")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Task Completed"
        content.body = task.title
        content.userInfo = ["taskURL": task.taskURL]
        content.sound = .default

        // Per-task identifier so a re-fire (e.g. status flapping under
        // a flaky network) replaces the previous banner instead of
        // stacking duplicates.
        let id = "task-completed-\(task.id)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.log.error("Add completed notification failed: \(String(describing: error))")
            }
        }
    }

    private func postWaitingNotification(task: AgentTask) {
        guard Self.hasNotificationSupport else {
            Self.log.debug("(skip) →waiting for \(task.id) — no .app bundle")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Task Needs Input"
        // Manus puts the prompt text in `waitingMessage`; fall back to
        // the title if the connector hasn't surfaced one.
        content.body = task.waitingMessage ?? task.title
        content.userInfo = ["taskURL": task.taskURL]
        content.sound = .default

        let id = "task-waiting-\(task.id)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.log.error("Add waiting notification failed: \(String(describing: error))")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show the banner even when our app is foreground — though as an
    /// `.accessory` policy app we virtually never are.
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// User clicked the banner → open the task's URL in the default
    /// browser. Banners with no URL (shouldn't happen, defensive) are
    /// silently dismissed.
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo["taskURL"] as? String,
           let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }
}
