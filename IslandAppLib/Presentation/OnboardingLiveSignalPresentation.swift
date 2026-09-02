import Foundation
import IslandCore

/// Latches the first real Agent event seen by Welcome's final step.
///
/// The value only ever moves forward: `waiting` → `seen` once any session
/// from a selected source exists → `completed` once a session from that
/// source reports `.completed`. It never falls back when the session is
/// removed (Claude Code's `SessionEnd` deletes the task moments after
/// `Stop`), so the stage keeps showing what the user already achieved.
enum OnboardingLiveSignalState: Hashable, Sendable {
    case waiting
    case seen(source: String)
    case completed(source: String)

    var source: String? {
        switch self {
        case .waiting: return nil
        case .seen(let source), .completed(let source): return source
        }
    }

    var hasSeenEvent: Bool {
        self != .waiting
    }

    /// Pure, order-independent advancement. `sources` is the set of Agent
    /// sources the user connected in Welcome; events from any other source
    /// are ignored so an unrelated session cannot claim the first light.
    func advanced(with tasks: [AgentTask], sources: Set<String>) -> Self {
        switch self {
        case .waiting:
            guard let task = tasks.first(where: { sources.contains($0.source) }) else {
                return .waiting
            }
            if tasks.contains(where: {
                $0.source == task.source && $0.status == .completed
            }) {
                return .completed(source: task.source)
            }
            return .seen(source: task.source)

        case .seen(let source):
            let finished = tasks.contains {
                $0.source == source && $0.status == .completed
            }
            return finished ? .completed(source: source) : self

        case .completed:
            return self
        }
    }
}

/// What Welcome asks the user to run, resolved from the listener health and
/// the connection states already loaded by the Connections step. Commands
/// are verbatim product strings and deliberately not localized.
enum OnboardingLiveSignalRecipe: Equatable, Sendable {
    /// The loopback listener has not proven it owns its port yet; asking the
    /// user to run anything now would produce a silent island.
    case listenerStarting
    /// A single terminal command whose Stop event completes the loop.
    case command(source: String, command: String)
    /// Codex has the managed Hook definition but its own trust gate is still
    /// closed: launch Codex, review `/hooks`, then send any prompt.
    case codexTrust(command: String)
    /// Cursor is driven from its own UI rather than a terminal.
    case cursorChat
    /// Another connected Agent without a scripted one-liner.
    case anySession(source: String)
    /// Nothing is connected; the Back button leads to the Connections step.
    case connectAgent

    static let claudeCodeCommand = "claude -p \"say hi\""
    static let codexCommand = "codex exec \"say hi\""
    static let codexLaunchCommand = "codex"

    static func resolve(
        listener: LocalHookServiceStatus,
        states: [String: LocalAgentHookConnectionState],
        candidateSources: [String]
    ) -> Self {
        guard listener == .listening else { return .listenerStarting }

        if states["claude-code"] == .connected {
            return .command(source: "claude-code", command: claudeCodeCommand)
        }
        switch states["codex"] {
        case .connected?:
            return .command(source: "codex", command: codexCommand)
        case .configured?:
            return .codexTrust(command: codexLaunchCommand)
        default:
            break
        }
        if states["cursor"] == .connected {
            return .cursorChat
        }
        if let source = candidateSources.first(where: {
            states[$0] == .connected || states[$0] == .configured
        }) {
            return .anySession(source: source)
        }
        return .connectAgent
    }

    var command: String? {
        switch self {
        case .command(_, let command), .codexTrust(let command): return command
        case .listenerStarting, .cursorChat, .anySession, .connectAgent: return nil
        }
    }

    /// Sources whose events are allowed to advance the latch.
    static func signalSources(
        states: [String: LocalAgentHookConnectionState]
    ) -> Set<String> {
        Set(states.compactMap { source, state in
            state == .connected || state == .configured ? source : nil
        })
    }
}
