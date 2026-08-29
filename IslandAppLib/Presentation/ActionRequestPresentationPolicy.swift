import Foundation
import IslandCore

/// Stable queue projection shared by the panel and compact-island attention
/// routing. Arrival order is authoritative: resolving the visible request
/// naturally reveals the next request for that session without reshuffling.
enum ActionRequestPresentationPolicy {
    static func attentionTarget(
        in requests: [AgentActionRequest]
    ) -> TaskIdentity? {
        requests.first?.taskIdentity
    }

    static func primary(
        for identity: TaskIdentity,
        in requests: [AgentActionRequest]
    ) -> AgentActionRequest? {
        requests.first(where: { $0.taskIdentity == identity })
    }

    /// Only the oldest unresolved request owns panel-level keyboard
    /// shortcuts. Several request surfaces can be visible at once, and
    /// letting each one register the same key equivalent makes AppKit's
    /// target ambiguous (or, worse, answers the wrong Agent session).
    static func isKeyboardPrimary(
        _ request: AgentActionRequest,
        in requests: [AgentActionRequest]
    ) -> Bool {
        requests.first?.id == request.id
    }

    static func additionalCount(
        for identity: TaskIdentity,
        in requests: [AgentActionRequest]
    ) -> Int {
        max(0, requests.count(where: { $0.taskIdentity == identity }) - 1)
    }

    static func orphaned(
        requests: [AgentActionRequest],
        tasks: [AgentTask]
    ) -> [AgentActionRequest] {
        let identities = Set(tasks.map(\.identity))
        return requests.filter { !identities.contains($0.taskIdentity) }
    }

    /// A short, stable reference keeps simultaneous sessions distinguishable
    /// without printing a raw UUID or chopping a human-readable identifier
    /// into fragments such as "on-session". FNV-1a is used only as a local
    /// display fingerprint; it is not a security primitive.
    static func sessionReference(
        for sessionID: String,
        language: DevIslandLanguage = .current
    ) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in sessionID.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16_777_619
        }
        let fingerprint = String(format: "%04X", hash & 0xFFFF)
        return L10n.format("Session %@", language: language, fingerprint)
    }
}

/// One linear projection of the pending-action queue for the expanded panel.
///
/// Task/request mutations can re-evaluate the panel row builder. Looking up the
/// first request and queued count by rescanning the complete request array for
/// every task turns each real update into O(tasks × requests) work. This
/// immutable index preserves arrival order while making every row lookup O(1);
/// orphan collection and keyboard ownership are derived in the same pass.
struct ActionRequestPresentationSnapshot {
    let orphanedRequests: [AgentActionRequest]

    private let primaryByIdentity: [TaskIdentity: AgentActionRequest]
    private let requestCountByIdentity: [TaskIdentity: Int]
    private let keyboardPrimaryID: UUID?

    init(
        requests: [AgentActionRequest],
        tasks: [AgentTask]
    ) {
        let visibleIdentities = Set(tasks.map(\.identity))
        var primaryByIdentity: [TaskIdentity: AgentActionRequest] = [:]
        var requestCountByIdentity: [TaskIdentity: Int] = [:]
        var orphanedRequests: [AgentActionRequest] = []
        orphanedRequests.reserveCapacity(requests.count)

        for request in requests {
            let identity = request.taskIdentity
            guard visibleIdentities.contains(identity) else {
                orphanedRequests.append(request)
                continue
            }

            if primaryByIdentity[identity] == nil {
                primaryByIdentity[identity] = request
            }
            requestCountByIdentity[identity, default: 0] += 1
        }

        self.primaryByIdentity = primaryByIdentity
        self.requestCountByIdentity = requestCountByIdentity
        self.orphanedRequests = orphanedRequests
        keyboardPrimaryID = requests.first?.id
    }

    func primary(for identity: TaskIdentity) -> AgentActionRequest? {
        primaryByIdentity[identity]
    }

    func additionalCount(for identity: TaskIdentity) -> Int {
        max(0, requestCountByIdentity[identity, default: 0] - 1)
    }

    func isKeyboardPrimary(_ request: AgentActionRequest) -> Bool {
        keyboardPrimaryID == request.id
    }
}
