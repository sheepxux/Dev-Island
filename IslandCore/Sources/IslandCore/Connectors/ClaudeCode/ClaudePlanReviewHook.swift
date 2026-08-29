import Foundation

/// Claude Code `ExitPlanMode` review over a matcher-scoped `PreToolUse` hook.
///
/// Source of truth (verified 2026-08-26):
/// https://code.claude.com/docs/en/hooks#exitplanmode
/// https://code.claude.com/docs/en/hooks#allow-with-updatedinput
enum ClaudePlanReviewHook {
    static func decodeRequest(_ data: Data) -> AgentActionRequest? {
        guard data.count <= AgentPlanReview.maximumInputBytes,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["hook_event_name"] as? String == "PreToolUse",
              root["tool_name"] as? String == "ExitPlanMode",
              let rawSessionID = root["session_id"] as? String,
              let sessionID = LocalAgentEvent.validSessionId(rawSessionID),
              let input = root["tool_input"] as? [String: Any],
              let markdown = input["plan"] as? String,
              input["planFilePath"].map({ $0 is String }) != false,
              JSONSerialization.isValidJSONObject(input),
              let inputJSON = try? JSONSerialization.data(
                withJSONObject: input,
                options: [.sortedKeys, .withoutEscapingSlashes]
              ),
              let review = AgentPlanReview(
                markdown: markdown,
                originalInputJSON: inputJSON
              ) else {
            return nil
        }

        return AgentActionRequest(
            source: "claude-code",
            sessionId: sessionID,
            kind: .planReview,
            title: "Review Claude Code plan",
            message: "Claude Code is ready to begin implementation.",
            planReview: review
        )
    }

    static func response(for response: AgentActionResponse?) -> String {
        guard case .planReview(let decision, let review) = response else {
            return "{}"
        }

        var output: [String: Any] = [
            "hookEventName": "PreToolUse",
            "permissionDecision": decision.rawValue,
        ]
        switch decision {
        case .allow:
            guard let originalInput = try? JSONSerialization.jsonObject(
                with: review.originalInputJSON
            ) as? [String: Any],
                  originalInput["plan"] as? String == review.markdown else {
                return "{}"
            }
            output["updatedInput"] = originalInput
        case .deny:
            output["permissionDecisionReason"] = "Plan rejected in Dev Island."
        }

        let body: [String: Any] = ["hookSpecificOutput": output]
        guard let data = try? JSONSerialization.data(
            withJSONObject: body,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
