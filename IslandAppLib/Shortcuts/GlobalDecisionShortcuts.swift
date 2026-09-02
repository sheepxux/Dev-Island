import AppKit
import Carbon.HIToolbox
import IslandCore

/// User switch for the system-wide decision shortcuts. Defaults on: the whole
/// point of the island is that a blocked agent never makes you leave the app
/// you are working in, and the three-modifier chords do not collide with
/// anything a text editor binds by default.
public enum GlobalDecisionShortcutPreferences {
    public static let enabledKey = "island.shortcuts.globalDecisions"

    public static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [enabledKey: true])
    }

    public static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }
}

/// The two fixed chords. They are registered through Carbon
/// `RegisterEventHotKey`, which delivers the key press to this background app
/// no matter which app is frontmost and, unlike an `NSEvent` global monitor,
/// needs no Accessibility authorization.
public enum GlobalDecisionShortcut: UInt32, CaseIterable, Sendable {
    case allow = 1
    case deny = 2

    /// Control + Option + Command, expressed in Carbon modifier bits.
    static let carbonModifiers = UInt32(controlKey | optionKey | cmdKey)

    var carbonKeyCode: UInt32 {
        switch self {
        case .allow: UInt32(kVK_ANSI_Y)
        case .deny: UInt32(kVK_ANSI_N)
        }
    }

    public var decision: AgentActionDecision {
        switch self {
        case .allow: .allow
        case .deny: .deny
        }
    }

    /// Glyph form used in Settings and Help copy.
    public var displayString: String {
        switch self {
        case .allow: "⌃⌥⌘Y"
        case .deny: "⌃⌥⌘N"
        }
    }
}

/// What a shortcut press does given the current queue.
public enum GlobalDecisionShortcutAction: Equatable, Sendable {
    /// Hand the decision to the agent without opening the island.
    case respond(requestID: UUID, decision: AgentActionDecision)
    /// Open the island (highlighting the owning session when there is one)
    /// because the front request needs the user to read or type something.
    case revealIsland(TaskIdentity?)
}

/// Pure decision rule, kept separate from Carbon so it is unit-testable.
///
/// Only the oldest unresolved request owns the shortcuts — the same request
/// that owns ⌘↩ / ⌘D inside the panel (`ActionRequestPresentationPolicy`).
/// A chord may decide a plain permission request. It never approves a plan
/// or answers a question blindly: those reveal the island instead so the user
/// actually sees what they are agreeing to.
public enum GlobalDecisionShortcutPolicy {
    public static func action(
        for shortcut: GlobalDecisionShortcut,
        in requests: [AgentActionRequest]
    ) -> GlobalDecisionShortcutAction {
        guard let front = requests.first else {
            return .revealIsland(nil)
        }
        switch front.kind {
        case .permission:
            return .respond(requestID: front.id, decision: shortcut.decision)
        case .question, .planReview:
            return .revealIsland(front.taskIdentity)
        }
    }
}

public extension Notification.Name {
    /// Posted on the main queue after a shortcut has successfully handed a
    /// decision to the agent, so the panel can show the same receipt it shows
    /// for an in-island click. `userInfo` carries
    /// `GlobalDecisionShortcutService.requestUserInfoKey` and
    /// `GlobalDecisionShortcutService.decisionUserInfoKey`.
    static let islandGlobalDecisionApplied = Notification.Name(
        "island.globalDecisionApplied"
    )
}

/// Registers the chords for the lifetime of the app and routes presses to
/// `TaskStore`. Registration follows the Settings switch live.
@MainActor
public final class GlobalDecisionShortcutService {
    public static let shared = GlobalDecisionShortcutService()

    public static let requestUserInfoKey = "request"
    public static let decisionUserInfoKey = "decision"

    private static let signature: OSType = 0x4476_4973 // 'DvIs'

    private let defaults: UserDefaults
    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [GlobalDecisionShortcut: EventHotKeyRef] = [:]
    private var defaultsObserver: NSObjectProtocol?
    private var isStarted = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether the chords are currently registered with the system.
    public var isRegistered: Bool { !hotKeyRefs.isEmpty }

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        GlobalDecisionShortcutPreferences.registerDefaults(in: defaults)
        installHandlerIfNeeded()
        synchronizeRegistration()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.synchronizeRegistration()
            }
        }
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }
        unregisterAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    // MARK: - Registration

    private func synchronizeRegistration() {
        if GlobalDecisionShortcutPreferences.isEnabled(in: defaults) {
            registerAll()
        } else {
            unregisterAll()
        }
    }

    private func registerAll() {
        for shortcut in GlobalDecisionShortcut.allCases where hotKeyRefs[shortcut] == nil {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: shortcut.rawValue)
            let status = RegisterEventHotKey(
                shortcut.carbonKeyCode,
                GlobalDecisionShortcut.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                hotKeyRefs[shortcut] = ref
            }
        }
    }

    private func unregisterAll() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr,
                      hotKeyID.signature == GlobalDecisionShortcutService.signature,
                      let shortcut = GlobalDecisionShortcut(rawValue: hotKeyID.id) else {
                    return OSStatus(eventNotHandledErr)
                }
                let service = Unmanaged<GlobalDecisionShortcutService>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                MainActor.assumeIsolated {
                    service.handle(shortcut)
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )
    }

    // MARK: - Dispatch

    func handle(_ shortcut: GlobalDecisionShortcut) {
        let store = TaskStore.shared
        switch GlobalDecisionShortcutPolicy.action(for: shortcut, in: store.pendingActionRequests) {
        case let .respond(requestID, decision):
            guard let request = store.pendingActionRequests.first(where: { $0.id == requestID }),
                  store.respond(to: requestID, decision: decision) else { return }
            NotificationCenter.default.post(
                name: .islandGlobalDecisionApplied,
                object: nil,
                userInfo: [
                    Self.requestUserInfoKey: request,
                    Self.decisionUserInfoKey: decision,
                ]
            )
        case let .revealIsland(identity):
            if let identity {
                IslandCoordinator.shared.expand(highlighting: identity)
            } else {
                IslandCoordinator.shared.expand()
            }
        }
    }
}
