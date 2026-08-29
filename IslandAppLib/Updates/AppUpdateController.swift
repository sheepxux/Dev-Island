import Foundation
import Observation
import Sparkle

/// The release-time fields that make Sparkle an authenticated update channel.
/// A missing or weak field disables the updater instead of silently falling
/// back to an unsigned feed.
public struct AppUpdateConfiguration: Equatable, Sendable {
    public static let productionFeedURLString =
        "https://github.com/sheepxux/Dev-Island/releases/latest/download/appcast.xml"
    public static let scheduledCheckInterval = 86_400

    public let feedURL: URL
    public let publicKey: String

    public init?(infoDictionary: [String: Any]) {
        guard let feed = infoDictionary["SUFeedURL"] as? String,
              feed == Self.productionFeedURLString,
              let feedURL = URL(string: feed),
              feedURL.scheme?.lowercased() == "https",
              feedURL.host?.isEmpty == false,
              feedURL.user == nil,
              feedURL.password == nil,
              let publicKey = infoDictionary["SUPublicEDKey"] as? String,
              let keyData = Data(base64Encoded: publicKey),
              keyData.count == 32,
              infoDictionary["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
              infoDictionary["SURequireSignedFeed"] as? Bool == true,
              infoDictionary["SUSignedFeedFailureExpirationInterval"] as? Int == 0,
              infoDictionary["SUEnableAutomaticChecks"] as? Bool == true,
              infoDictionary["SUScheduledCheckInterval"] as? Int == Self.scheduledCheckInterval,
              infoDictionary["SUAutomaticallyUpdate"] as? Bool == false,
              infoDictionary["SUEnableSystemProfiling"] as? Bool == false else {
            return nil
        }

        self.feedURL = feedURL
        self.publicKey = publicKey
    }
}

/// Low-cardinality runtime state for Settings and the status menu. Sparkle's
/// raw errors, feed responses, paths, and download details never cross this
/// boundary into product UI or support diagnostics.
public enum AppUpdateStatus: Equatable, Sendable {
    case unavailable
    case starting
    case ready
    case checking
    case failed
}

@MainActor
protocol AppUpdateRuntime: AnyObject {
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }

    func start(
        canCheckDidChange: @escaping (Bool) -> Void,
        automaticChecksDidChange: @escaping (Bool) -> Void
    ) throws
    func checkForUpdates()
}

/// The only production adapter allowed to construct Sparkle. Starting is
/// explicit so Dev Island can fail closed on `start()` instead of letting
/// `SPUStandardUpdaterController(startingUpdater: true)` show a delayed
/// developer-facing configuration alert that our state cannot observe.
@MainActor
private final class SparkleAppUpdateRuntime: AppUpdateRuntime {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private var canCheckObservation: NSKeyValueObservation?
    private var automaticChecksObservation: NSKeyValueObservation?

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func start(
        canCheckDidChange: @escaping (Bool) -> Void,
        automaticChecksDidChange: @escaping (Bool) -> Void
    ) throws {
        let updater = controller.updater
        canCheckObservation = updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { _, change in
            let value = change.newValue ?? false
            Task { @MainActor in canCheckDidChange(value) }
        }
        automaticChecksObservation = updater.observe(
            \.automaticallyChecksForUpdates,
            options: [.initial, .new]
        ) { _, change in
            let value = change.newValue ?? false
            Task { @MainActor in automaticChecksDidChange(value) }
        }

        do {
            try updater.start()
        } catch {
            canCheckObservation = nil
            automaticChecksObservation = nil
            throw error
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

/// Owns Sparkle's standard updater UI and exposes only the small state surface
/// Settings and the menu-bar item need. The controller is inert in local QA
/// builds unless build-app.sh receives a valid release public key.
@MainActor
@Observable
public final class AppUpdateController {
    public static let shared = AppUpdateController()

    public private(set) var isAvailable: Bool
    public private(set) var status: AppUpdateStatus
    public private(set) var canCheckForUpdates = false
    public private(set) var automaticallyChecksForUpdates = false
    public private(set) var canChangeAutomaticChecks = false

    public let currentVersion: String

    @ObservationIgnored private let configuration: AppUpdateConfiguration?
    @ObservationIgnored private let makeRuntime: () -> any AppUpdateRuntime
    @ObservationIgnored private var runtime: (any AppUpdateRuntime)?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var runtimeGeneration: UInt64 = 0

    public convenience init(bundle: Bundle = .main) {
        let info = bundle.infoDictionary ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)
            ?? "—"
        self.init(
            infoDictionary: info,
            currentVersion: version,
            makeRuntime: { SparkleAppUpdateRuntime() }
        )
    }

    init(
        infoDictionary: [String: Any],
        currentVersion: String,
        makeRuntime: @escaping () -> any AppUpdateRuntime
    ) {
        let configuration = AppUpdateConfiguration(infoDictionary: infoDictionary)
        self.configuration = configuration
        self.isAvailable = configuration != nil
        self.status = configuration == nil ? .unavailable : .starting
        self.currentVersion = currentVersion
        self.makeRuntime = makeRuntime
    }

    /// Start once at application launch so Sparkle owns its normal 24-hour
    /// scheduler. Weak/missing release metadata keeps this a no-op.
    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        guard configuration != nil else {
            status = .unavailable
            return
        }

        status = .starting
        runtimeGeneration &+= 1
        let generation = runtimeGeneration
        let candidate = makeRuntime()
        runtime = candidate

        do {
            try candidate.start(
                canCheckDidChange: { [weak self] value in
                    self?.applyCanCheck(value, generation: generation)
                },
                automaticChecksDidChange: { [weak self] value in
                    self?.applyAutomaticChecks(value, generation: generation)
                }
            )
            guard generation == runtimeGeneration else { return }
            canChangeAutomaticChecks = true
            applyAutomaticChecks(
                candidate.automaticallyChecksForUpdates,
                generation: generation
            )
            applyCanCheck(
                candidate.canCheckForUpdates,
                generation: generation
            )
        } catch {
            guard generation == runtimeGeneration else { return }
            // Invalidate any observation callbacks already queued by the
            // failed runtime. The raw Sparkle error is deliberately discarded.
            runtimeGeneration &+= 1
            runtime = nil
            canCheckForUpdates = false
            automaticallyChecksForUpdates = false
            canChangeAutomaticChecks = false
            status = .failed
        }
    }

    public func checkForUpdates() {
        guard status == .ready,
              canCheckForUpdates,
              let runtime else { return }
        canCheckForUpdates = false
        status = .checking
        runtime.checkForUpdates()
    }

    public func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard canChangeAutomaticChecks, let runtime else { return }
        runtime.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = runtime.automaticallyChecksForUpdates
    }

    private func applyCanCheck(_ value: Bool, generation: UInt64) {
        guard generation == runtimeGeneration,
              runtime != nil,
              status != .failed else { return }
        canCheckForUpdates = value
        if value {
            status = .ready
        } else if status == .ready {
            status = .checking
        }
    }

    private func applyAutomaticChecks(_ value: Bool, generation: UInt64) {
        guard generation == runtimeGeneration,
              runtime != nil,
              status != .failed else { return }
        automaticallyChecksForUpdates = value
    }
}
