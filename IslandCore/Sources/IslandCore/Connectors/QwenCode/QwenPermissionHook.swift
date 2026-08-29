import Foundation

/// Qwen Code 0.22.0 `PermissionRequest` wire contract.
///
/// The response shape is intentionally shared only because Qwen's pinned
/// source documents the same structured `hookSpecificOutput.decision`
/// object. Promotion from Preview still requires a real CLI round trip.
enum QwenPermissionHook {
    private static let codec = PermissionRequestHookCodec(
        source: "qwen-code",
        displayName: "Qwen Code"
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
