import IslandCore
import OSLog
import UserNotifications

private let taskNotifierLog = Logger(
    subsystem: "app.devisland.Island",
    category: "notifier"
)
private let taskNotificationSourceKey = "taskSource"
private let taskNotificationIDKey = "taskID"

public extension Notification.Name {
    static let islandNotificationAuthorizationChanged = Notification.Name(
        "island.notificationAuthorizationChanged"
    )
}

/// User-facing notification switches. Attention-required events default on;
/// completion banners default off so Dev Island stays quiet unless a task is
/// blocked or failed.
public enum TaskNotificationPreferences {
    public static let attentionRequiredKey = "island.notifications.attentionRequired"
    public static let completionsKey = "island.notifications.completions"

    public static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            attentionRequiredKey: true,
            completionsKey: false,
        ])
    }
}

/// Pure transition policy, separated from UserNotifications so the product's
/// "notify only when useful" rules are easy to unit test.
enum TaskNotificationKind: Equatable {
    case waiting
    case failed
    case completed

    static func decide(
        for transition: TaskTransition,
        attentionRequired: Bool,
        completions: Bool
    ) -> Self? {
        // A newly discovered task is usually a bootstrap snapshot, not a
        // live transition. Never turn startup state into a banner storm.
        guard let oldStatus = transition.oldStatus else { return nil }

        switch transition.newStatus {
        case .waiting where attentionRequired:
            return .waiting
        case .failed where attentionRequired:
            return .failed
        case .completed where completions && oldStatus != .completed:
            return .completed
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .waiting:   return "Task Needs Input"
        case .failed:    return "Task Failed"
        case .completed: return "Task Completed"
        }
    }

    var identifierComponent: String {
        switch self {
        case .waiting:   return "waiting"
        case .failed:    return "failed"
        case .completed: return "completed"
        }
    }
}

/// Turns `TaskStore.onTaskTransition` events into macOS notifications and
/// routes notification clicks back into the in-app task list.
@MainActor
public final class TaskNotifier: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = TaskNotifier()

    private var started = false
    public private(set) var authorizationIssue: String?

    private override init() {
        super.init()
    }

    /// Bare `swift run` executables have no app bundle identity and crash on
    /// first access to `UNUserNotificationCenter.current()`. Packaged `.app`
    /// builds have full support.
    public static var hasNotificationSupport: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Attach once to the transition callback. Authorization is opt-in at a
    /// deliberate UI moment (Welcome Tour completion or a Settings toggle)
    /// so the system sheet never competes with first launch.
    public func start(requestAuthorization: Bool = false) {
        guard !started else { return }
        started = true

        TaskNotificationPreferences.registerDefaults()
        TaskStore.shared.onTaskTransition = { [weak self] transition in
            self?.handle(transition)
        }

        guard Self.hasNotificationSupport else {
            taskNotifierLog.info("Skipping notification setup because the host is not an app bundle")
            return
        }

        UNUserNotificationCenter.current().delegate = self
        if requestAuthorization {
            refreshAuthorizationIfNeeded()
        } else {
            refreshAuthorizationState()
        }
    }

    /// Fire-and-forget entry point used by Settings. Welcome Tour awaits the
    /// async variant after its window has fully disappeared so the system
    /// permission sheet never competes with our own transition.
    public func refreshAuthorizationIfNeeded() {
        Task { await requestAuthorizationIfNeeded() }
    }

    /// Request authorization only when at least one notification category is
    /// enabled. Returning after the system response lets callers sequence the
    /// surrounding UI without guessing how long the sheet will remain open.
    public func requestAuthorizationIfNeeded() async {
        guard Self.hasNotificationSupport else { return }
        let defaults = UserDefaults.standard
        let isEnabled = defaults.bool(forKey: TaskNotificationPreferences.attentionRequiredKey)
            || defaults.bool(forKey: TaskNotificationPreferences.completionsKey)
        guard isEnabled else { return }

        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            taskNotifierLog.info("Notification authorization granted=\(granted)")
            publishAuthorizationIssue(
                granted ? nil : "Notifications are disabled in System Settings."
            )
        } catch {
            let nsError = error as NSError
            taskNotifierLog.error("Notification authorization failed: domain=\(nsError.domain, privacy: .public) code=\(nsError.code) description=\(nsError.localizedDescription, privacy: .public)")
            publishAuthorizationIssue(nsError.localizedDescription)
        }
    }

    /// Refresh the Settings warning after the user returns from System
    /// Settings. A request-time error is retained while status is still
    /// undetermined so local ad-hoc builds remain diagnosable.
    public func refreshAuthorizationState() {
        guard Self.hasNotificationSupport else { return }
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                publishAuthorizationIssue(nil)
            case .denied:
                publishAuthorizationIssue("Notifications are disabled in System Settings.")
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }

    private func publishAuthorizationIssue(_ issue: String?) {
        authorizationIssue = issue
        NotificationCenter.default.post(
            name: .islandNotificationAuthorizationChanged,
            object: self
        )
    }

    private func handle(_ transition: TaskTransition) {
        let defaults = UserDefaults.standard
        guard let kind = TaskNotificationKind.decide(
            for: transition,
            attentionRequired: defaults.bool(forKey: TaskNotificationPreferences.attentionRequiredKey),
            completions: defaults.bool(forKey: TaskNotificationPreferences.completionsKey)
        ) else { return }

        post(kind, for: transition.task)
    }

    private func post(_ kind: TaskNotificationKind, for task: AgentTask) {
        guard Self.hasNotificationSupport else {
            taskNotifierLog.debug("Skipping \(kind.identifierComponent) notification for \(task.source)/\(task.id)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = kind.title
        content.subtitle = sourceDisplayName(task.source)
        content.body = body(for: kind, task: task)
        content.sound = .default
        content.userInfo = [
            taskNotificationSourceKey: task.source,
            taskNotificationIDKey: task.id,
        ]

        // Include source as well as session ID so two agents with the same ID
        // never replace or route each other's banner.
        let requestID = "task-\(kind.identifierComponent)-\(task.source):\(task.id)"
        let request = UNNotificationRequest(identifier: requestID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                let nsError = error as NSError
                taskNotifierLog.error("Adding notification failed: domain=\(nsError.domain, privacy: .public) code=\(nsError.code) description=\(nsError.localizedDescription, privacy: .public)")
            }
        }
    }

    private func body(for kind: TaskNotificationKind, task: AgentTask) -> String {
        switch kind {
        case .waiting:
            return task.waitingMessage ?? task.currentPhase ?? task.title
        case .failed:
            return task.currentPhase ?? task.title
        case .completed:
            return task.title
        }
    }

    private func sourceDisplayName(_ source: String) -> String {
        if source == "manus" { return "Manus" }
        return LocalAgentRegistry.descriptor(for: source)?.displayName ?? source
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Clicking a banner opens the island, scrolls the referenced task into
    /// view, and highlights it. The user can then inspect the state before a
    /// deliberate card click jumps back to the source session.
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let source = userInfo[taskNotificationSourceKey] as? String,
           let id = userInfo[taskNotificationIDKey] as? String {
            let identity = TaskIdentity(source: source, id: id)
            Task { @MainActor in
                IslandCoordinator.shared.expand(highlighting: identity)
            }
        }
        completionHandler()
    }
}
