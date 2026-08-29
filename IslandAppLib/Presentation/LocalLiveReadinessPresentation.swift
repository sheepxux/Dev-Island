import Foundation
import IslandCore

/// Owns the lifetime of the explicit Settings readiness check. A Hook or
/// listener change invalidates both the visible snapshot and the in-flight
/// token, so a detached probe that finishes late cannot restore stale status.
struct LocalLiveReadinessCheckState: Equatable {
    private(set) var snapshot: LocalLiveReadinessSnapshot?
    private(set) var activeCheckID: UUID?

    init(snapshot: LocalLiveReadinessSnapshot? = nil) {
        self.snapshot = snapshot
    }

    var isChecking: Bool { activeCheckID != nil }

    mutating func begin() -> UUID? {
        guard activeCheckID == nil else { return nil }
        let checkID = UUID()
        activeCheckID = checkID
        return checkID
    }

    @discardableResult
    mutating func accept(
        _ snapshot: LocalLiveReadinessSnapshot,
        for checkID: UUID
    ) -> Bool {
        guard activeCheckID == checkID else { return false }
        self.snapshot = snapshot
        activeCheckID = nil
        return true
    }

    mutating func invalidate() {
        snapshot = nil
        activeCheckID = nil
    }
}

/// Low-noise copy for the explicit Agent Connections readiness check. The
/// Settings surface shows one next step rather than exposing diagnostic
/// internals or repeating every failed predicate as a dashboard.
enum LocalLiveReadinessPresentation {
    enum Tone: Equatable {
        case neutral
        case checking
        case retry
        case ready
        case attention
    }

    struct Content: Equatable {
        let title: String
        let detail: String
        let tone: Tone
        let actionCount: Int
    }

    static func content(
        snapshot: LocalLiveReadinessSnapshot?,
        isChecking: Bool,
        language: DevIslandLanguage
    ) -> Content {
        if isChecking {
            return Content(
                title: L10n.string("Checking local setup…", language: language),
                detail: L10n.string(
                    "Checking this Mac without changing Agent configuration.",
                    language: language
                ),
                tone: .checking,
                actionCount: 0
            )
        }

        guard let snapshot else {
            return Content(
                title: L10n.string("Live connection check", language: language),
                detail: L10n.string(
                    "Verify Claude Code and Codex before your first real approval.",
                    language: language
                ),
                tone: .neutral,
                actionCount: 0
            )
        }

        if snapshot.isReady {
            return Content(
                title: L10n.string("Ready for live Agent sessions", language: language),
                detail: L10n.string(
                    "Claude Code and Codex passed local setup checks.",
                    language: language
                ),
                tone: .ready,
                actionCount: 0
            )
        }

        let knownSetupActionCount = outstandingActionCount(in: snapshot)
        let failedChecks = names(
            in: snapshot,
            where: { $0.cli == .checkFailed },
            language: language
        )
        if knownSetupActionCount == 0, !failedChecks.isEmpty {
            return Content(
                title: L10n.string("Live check incomplete", language: language),
                detail: L10n.format(
                    "Couldn't verify %@ right now.",
                    language: language,
                    failedChecks
                ),
                tone: .retry,
                actionCount: 0
            )
        }

        let count = max(1, knownSetupActionCount)
        return Content(
            title: L10n.format(
                count == 1
                    ? "%lld setup action remains"
                    : "%lld setup actions remain",
                language: language,
                Int64(count)
            ),
            detail: nextAction(in: snapshot, language: language),
            tone: .attention,
            actionCount: count
        )
    }

    static func outstandingActionCount(in snapshot: LocalLiveReadinessSnapshot) -> Int {
        var count = snapshot.listener == .listening ? 0 : 1
        for agent in snapshot.agents {
            switch agent.cli {
            case .unavailable, .reviewRequired:
                count += 1
            case .verified, .checkFailed:
                break
            }
            switch agent.hook {
            case .connected:
                if agent.activation == .reviewRequired { count += 1 }
            case .configured, .updateRequired, .disconnected:
                count += 1
            }
        }
        return count
    }

    private static func nextAction(
        in snapshot: LocalLiveReadinessSnapshot,
        language: DevIslandLanguage
    ) -> String {
        if snapshot.listener != .listening {
            return L10n.string("The local Agent listener is offline.", language: language)
        }

        let unavailable = names(
            in: snapshot,
            where: { $0.cli == .unavailable },
            language: language
        )
        if !unavailable.isEmpty {
            return L10n.format("Install %@ to continue.", language: language, unavailable)
        }

        let versionReview = names(
            in: snapshot,
            where: { $0.cli == .reviewRequired },
            language: language
        )
        if !versionReview.isEmpty {
            return L10n.format(
                "The installed %@ version needs a compatibility review.",
                language: language,
                versionReview
            )
        }

        let updates = names(
            in: snapshot,
            where: { $0.hook == .updateRequired },
            language: language
        )
        if !updates.isEmpty {
            return L10n.format("Update %@ below.", language: language, updates)
        }

        let disconnected = names(
            in: snapshot,
            where: { $0.hook == .disconnected },
            language: language
        )
        if !disconnected.isEmpty {
            return L10n.format("Enable %@ below.", language: language, disconnected)
        }

        if snapshot.agents.contains(where: {
            $0.source == "codex"
                && ($0.hook == .configured || $0.activation == .reviewRequired)
        }) {
            return L10n.format(
                "Review Dev Island Hooks in Codex %@.",
                language: language,
                "/hooks"
            )
        }

        let failedChecks = names(
            in: snapshot,
            where: { $0.cli == .checkFailed },
            language: language
        )
        if !failedChecks.isEmpty {
            return L10n.format(
                "Couldn't verify %@ right now.",
                language: language,
                failedChecks
            )
        }

        return L10n.string("Local setup still needs attention.", language: language)
    }

    private static func names(
        in snapshot: LocalLiveReadinessSnapshot,
        where predicate: (LocalAgentLiveReadiness) -> Bool,
        language: DevIslandLanguage
    ) -> String {
        let names = snapshot.agents.filter(predicate).map { agent in
            LocalAgentRegistry.descriptor(for: agent.source)?.displayName ?? agent.source
        }
        guard let first = names.first else { return "" }
        guard names.count > 1 else { return first }
        return L10n.format("%@ and %@", language: language, first, names[1])
    }
}
