import Foundation

/// Codex PermissionRequest wire contract.
///
/// Source of truth (verified 2026-08-26):
/// https://learn.chatgpt.com/docs/hooks#permissionrequest
enum CodexPermissionHook {
    private static let codec = PermissionRequestHookCodec(
        source: "codex",
        displayName: "Codex"
    )

    static func decodeRequest(_ data: Data) -> AgentActionRequest? {
        codec.decodeRequest(data)
    }

    static func response(for decision: AgentActionDecision?) -> String {
        PermissionRequestHookCodec.response(for: decision)
    }

    static func response(forActionResponse response: AgentActionResponse?) -> String {
        PermissionRequestHookCodec.response(forActionResponse: response)
    }
}
