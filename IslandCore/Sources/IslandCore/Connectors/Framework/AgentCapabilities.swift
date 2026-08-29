import Foundation

/// How deeply one connector can participate in an interaction category.
public enum AgentInteractionSupport: String, Codable, Sendable {
    /// The integration neither observes nor answers this interaction.
    case unavailable
    /// Dev Island can surface the state, but the user must answer elsewhere.
    case observeOnly
    /// Dev Island can surface the request and return the user's decision.
    case bidirectional
}

/// Code-level capability matrix used by Settings, UI gating, and tests.
///
/// A connector must not claim `bidirectional` until its exact response wire
/// format is backed by vendor documentation and a round-trip test.
public struct AgentCapabilities: Codable, Equatable, Sendable {
    public let lifecycleEvents: Bool
    public let permissionRequests: AgentInteractionSupport
    public let questionRequests: AgentInteractionSupport
    public let planReviews: AgentInteractionSupport

    public init(
        lifecycleEvents: Bool = true,
        permissionRequests: AgentInteractionSupport = .unavailable,
        questionRequests: AgentInteractionSupport = .unavailable,
        planReviews: AgentInteractionSupport = .unavailable
    ) {
        self.lifecycleEvents = lifecycleEvents
        self.permissionRequests = permissionRequests
        self.questionRequests = questionRequests
        self.planReviews = planReviews
    }

    public static let lifecycleOnly = AgentCapabilities()
}
