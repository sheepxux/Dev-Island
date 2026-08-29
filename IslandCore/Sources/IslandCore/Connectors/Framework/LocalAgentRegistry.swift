import Foundation

/// The single source of truth for which local agents Dev Island supports.
///
/// Everything downstream — hook server routes, connectors, Settings rows,
/// jump-back app resolution — iterates or queries this table. Shipping a
/// new agent is: add its descriptor here (+ payload mapping), drop a logo
/// SVG into `scripts/assets/agent-logos/`, re-run the logo script.
public enum LocalAgentRegistry {

    /// All supported local agents, in Settings display order.
    public static let all: [LocalAgentDescriptor] = [
        .claudeCode,
        .codex,
        .geminiCLI,
        .qwenCode,
        .copilotCLI,
        .kimiCode,
        .openCode,
        .cursor,
    ]

    public static func descriptor(for source: String) -> LocalAgentDescriptor? {
        all.first { $0.source == source }
    }
}
