import Foundation

/// Shared wire codec for vendors that document the same synchronous
/// `PermissionRequest` contract. A connector opts in only after its own
/// official documentation has been verified; sharing the parser does not
/// imply support for any unverified agent.
struct PermissionRequestHookCodec: Sendable {
    let source: String
    let displayName: String

    private struct Payload: Decodable {
        let hookEventName: String
        let sessionId: String
        let toolName: String
        let toolInput: HookJSONValue
    }

    func decodeRequest(_ data: Data) -> AgentActionRequest? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(Payload.self, from: data),
              payload.hookEventName == "PermissionRequest",
              let sessionId = LocalAgentEvent.validSessionId(payload.sessionId),
              let object = payload.toolInput.objectValue else {
            return nil
        }

        let reason = object["description"]?.stringValue
        let command = object["command"]?.stringValue
        let fallbackDetail = payload.toolInput.rendered
        let detail = command ?? (fallbackDetail == "{}" ? nil : fallbackDetail)

        return AgentActionRequest(
            source: source,
            sessionId: sessionId,
            kind: .permission,
            title: "Approve \(payload.toolName)",
            message: reason ?? "\(displayName) wants to use \(payload.toolName).",
            detail: detail
        )
    }

    /// Both verified vendors use the same documented output object. `nil`
    /// deliberately declines to decide so the vendor keeps its own prompt.
    static func response(for decision: AgentActionDecision?) -> String {
        response(forActionResponse: decision.map(AgentActionResponse.permission))
    }

    static func response(forActionResponse response: AgentActionResponse?) -> String {
        guard case .permission(let decision) = response else { return "{}" }
        let behavior: [String: Any]
        switch decision {
        case .allow:
            behavior = ["behavior": "allow"]
        case .deny:
            behavior = [
                "behavior": "deny",
                "message": "Denied in Dev Island.",
            ]
        }
        let body: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": behavior,
            ],
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: body,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

private enum HookJSONValue: Decodable, Sendable {
    case object([String: HookJSONValue])
    case array([HookJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: HookJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([HookJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    var objectValue: [String: HookJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var rendered: String {
        guard JSONSerialization.isValidJSONObject(foundationValue),
              let data = try? JSONSerialization.data(
                withJSONObject: foundationValue,
                options: [.sortedKeys, .withoutEscapingSlashes]
              ) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private var foundationValue: Any {
        switch self {
        case .object(let value): return value.mapValues(\.foundationValue)
        case .array(let value): return value.map(\.foundationValue)
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .null: return NSNull()
        }
    }
}
