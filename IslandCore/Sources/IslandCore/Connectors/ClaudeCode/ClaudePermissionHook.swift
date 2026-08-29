import Foundation

/// Claude Code PermissionRequest wire contract.
/// Source of truth (verified 2026-08-26):
/// https://code.claude.com/docs/en/hooks#permissionrequest
enum ClaudePermissionHook {
    private static let codec = PermissionRequestHookCodec(
        source: "claude-code",
        displayName: "Claude Code"
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
