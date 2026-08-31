import Foundation
import IslandCore

/// Short-lived confirmation shown after Dev Island has synchronously handed a
/// decision back to the Agent. It deliberately confirms only delivery; a later
/// lifecycle event is the first evidence that the Agent actually resumed.
struct ActionResponseReceiptSnapshot: Equatable {
    let title: String
    let detail: String

    var accessibilityLabel: String {
        "\(title). \(detail)"
    }
}

enum ActionResponseReceiptPresentation {
    static func decision(
        for request: AgentActionRequest,
        decision: AgentActionDecision,
        language: DevIslandLanguage
    ) -> ActionResponseReceiptSnapshot {
        let titleKey: String
        switch (request.kind, decision) {
        case (.permission, .allow):
            titleKey = "Allowed once"
        case (.permission, .deny):
            titleKey = "Request denied"
        case (.planReview, .allow):
            titleKey = "Plan approved"
        case (.planReview, .deny):
            titleKey = "Plan rejected"
        case (.question, _):
            // Question requests are submitted through `answersSent` instead.
            titleKey = "Decision sent"
        }

        return snapshot(
            titleKey: titleKey,
            source: request.source,
            language: language
        )
    }

    static func answersSent(
        for request: AgentActionRequest,
        language: DevIslandLanguage
    ) -> ActionResponseReceiptSnapshot {
        snapshot(
            titleKey: "Answers sent",
            source: request.source,
            language: language
        )
    }

    private static func snapshot(
        titleKey: String,
        source: String,
        language: DevIslandLanguage
    ) -> ActionResponseReceiptSnapshot {
        ActionResponseReceiptSnapshot(
            title: L10n.string(titleKey, language: language),
            detail: L10n.format(
                "Response sent to %@",
                language: language,
                agentDisplayName(for: source)
            )
        )
    }

    private static func agentDisplayName(for source: String) -> String {
        if source == "manus" { return "Manus" }
        return LocalAgentRegistry.descriptor(for: source)?.displayName
            ?? source.replacingOccurrences(of: "-", with: " ").capitalized
    }
}
