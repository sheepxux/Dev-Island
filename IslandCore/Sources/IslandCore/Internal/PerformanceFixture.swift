#if DEV_ISLAND_PERFORMANCE_QA
import Foundation

/// Hermetic task fixtures compiled only into dedicated performance-QA builds.
/// They keep measurements away from the user's SQLite database, Keychain,
/// local Hook port, Manus account, and notification preferences.
public enum PerformanceFixture {
    private static let actionMarkerQueue = DispatchQueue(
        label: "app.devisland.performance-action-markers",
        qos: .utility
    )

    public enum Scenario: String, Sendable {
        case idle
        case compactRunning20 = "compact-running-20"
        case expandedRunning20 = "expanded-running-20"
        case expandedMixed20 = "expanded-mixed-20"
        case transitionRunning20 = "transition-running-20"
        case decisionApproval = "decision-approval"
        case decisionQuestion = "decision-question"
        case decisionPlanReview = "decision-plan-review"
    }

    public static let scenario: Scenario = {
        let raw = ProcessInfo.processInfo.environment["DEV_ISLAND_PERFORMANCE_SCENARIO"]
        return raw.flatMap(Scenario.init(rawValue:)) ?? .idle
    }()

    public static var shouldExpand: Bool {
        switch scenario {
        case .idle, .compactRunning20, .transitionRunning20:
            return false
        case .expandedRunning20, .expandedMixed20,
             .decisionApproval, .decisionQuestion, .decisionPlanReview:
            return true
        }
    }

    /// Repeated bar-to-panel morphs are isolated to the dedicated QA binary.
    /// The interval leaves each 300 ms silhouette transition fully settled
    /// before the next edge begins, while still producing enough samples for
    /// a one-minute Animation Hitches recording.
    public static var transitionInterval: TimeInterval? {
        scenario == .transitionRunning20 ? 0.8 : nil
    }

    public static let transitionInitialDelay: TimeInterval = 1.0

    public static func makeTasks(now: Date = .now) -> [AgentTask] {
        switch scenario {
        case .idle:
            return []
        case .compactRunning20, .expandedRunning20, .transitionRunning20:
            return (0..<20).map { makeTask(index: $0, status: .running, now: now) }
        case .expandedMixed20:
            return (0..<20).map { index in
                let status: TaskStatus
                switch index {
                case 0..<3: status = .waiting
                case 3..<5: status = .failed
                case 5..<8: status = .completed
                default: status = .running
                }
                return makeTask(index: index, status: status, now: now)
            }
        case .decisionApproval:
            return [makeDecisionTask(
                sessionID: "perf-decision-approval",
                source: "codex",
                title: "Dev Island release check",
                phase: "Needs approval",
                now: now
            )]
        case .decisionQuestion:
            return [makeDecisionTask(
                sessionID: "perf-decision-question",
                source: "claude-code",
                title: "Dev Island interaction review",
                phase: "Needs input",
                now: now
            )]
        case .decisionPlanReview:
            return [makeDecisionTask(
                sessionID: "perf-decision-plan-review",
                source: "claude-code",
                title: "Dev Island plan review",
                phase: "Review plan",
                now: now
            )]
        }
    }

    /// A single production-path request for unlocked interaction and
    /// Animation Hitches evidence. The performance App remains hermetic: it
    /// never starts local Hooks or provider services, but buttons, keyboard
    /// routing, response receipts, and session restoration all use the same
    /// `TaskStore` queue as the shipping App.
    public static func makeActionRequest(now: Date = .now) -> AgentActionRequest? {
        switch scenario {
        case .decisionApproval:
            return AgentActionRequest(
                source: "codex",
                sessionId: "perf-decision-approval",
                kind: .permission,
                title: "Approve Bash",
                message: "Codex wants to inspect the release working tree.",
                detail: "git status --short && swift test",
                createdAt: now,
                timeout: AgentActionRequest.maximumTimeout
            )
        case .decisionQuestion:
            return AgentActionRequest(
                source: "claude-code",
                sessionId: "perf-decision-question",
                kind: .question,
                title: "Claude Code needs input",
                message: "Answer two questions to continue.",
                questions: [
                    AgentQuestion(
                        question: "Which surface should own approvals?",
                        header: "Surface",
                        options: [
                            AgentQuestionOption(
                                label: "Dev Island",
                                description: "Stay in the compact island workflow"
                            ),
                            AgentQuestionOption(
                                label: "Terminal",
                                description: "Return to Claude Code for every prompt"
                            ),
                        ]
                    ),
                    AgentQuestion(
                        question: "Which verification should run?",
                        header: "Checks",
                        options: [
                            AgentQuestionOption(label: "Unit tests"),
                            AgentQuestionOption(label: "Launch smoke"),
                            AgentQuestionOption(label: "Visual review"),
                        ],
                        allowsMultipleSelection: true
                    ),
                ],
                createdAt: now,
                timeout: AgentActionRequest.maximumTimeout
            )
        case .decisionPlanReview:
            let markdown = """
            ## Refine the attention flow

            1. Keep **approval requests** ahead of completed and running sessions.
            2. Preserve stable ordering inside the same priority tier.
            3. Verify keyboard focus, VoiceOver order, and Reduce Motion.

            ```swift
            priority = attention > completed > running > idle
            ```
            """
            let input: [String: Any] = [
                "plan": markdown,
                "planFilePath": "/Users/dev/.claude/plans/dev-island-attention.md",
            ]
            guard let inputJSON = try? JSONSerialization.data(
                withJSONObject: input,
                options: [.sortedKeys, .withoutEscapingSlashes]
            ),
                  let review = AgentPlanReview(
                    markdown: markdown,
                    originalInputJSON: inputJSON
                  ) else { return nil }
            return AgentActionRequest(
                source: "claude-code",
                sessionId: "perf-decision-plan-review",
                kind: .planReview,
                title: "Review Claude Code plan",
                message: "Claude Code is ready to begin implementation.",
                planReview: review,
                createdAt: now,
                timeout: AgentActionRequest.maximumTimeout
            )
        case .idle, .compactRunning20, .expandedRunning20,
             .expandedMixed20, .transitionRunning20:
            return nil
        }
    }

    static func signalActionQueued(_ request: AgentActionRequest) {
        writeActionMarker(
            phase: "queued",
            kind: request.kind.rawValue,
            result: nil
        )
    }

    static func signalActionFinished(
        _ request: AgentActionRequest,
        response: AgentActionResponse?
    ) {
        let result: String
        switch response {
        case .permission(.allow):
            result = "allow"
        case .permission(.deny):
            result = "deny"
        case .question:
            result = "submitted"
        case .planReview(.allow, _):
            result = "approve"
        case .planReview(.deny, _):
            result = "reject"
        case nil:
            result = "nativeFallback"
        }
        writeActionMarker(
            phase: "resolved",
            kind: request.kind.rawValue,
            result: result
        )
    }

    private static func writeActionMarker(
        phase: String,
        kind: String,
        result: String?
    ) {
        let uptime = ProcessInfo.processInfo.systemUptime
        let wallUnix = Date().timeIntervalSince1970
        let resultField = result.map { " result=\($0)" } ?? ""
        let line = "DEV_ISLAND_PERFORMANCE_ACTION phase=\(phase) kind=\(kind)\(resultField) uptime=\(uptime) wallUnix=\(wallUnix)\n"
        let data = Data(line.utf8)
        actionMarkerQueue.async {
            FileHandle.standardOutput.write(data)
        }
    }

    private static func makeTask(index: Int, status: TaskStatus, now: Date) -> AgentTask {
        let sources = ["claude-code", "codex", "cursor", "manus"]
        let phase: String?
        switch status {
        case .running: phase = "Running deterministic QA workload"
        case .waiting: phase = "Needs input"
        case .completed: phase = nil
        case .failed: phase = "Fixture failure"
        }

        return AgentTask(
            id: String(format: "perf-%02d", index + 1),
            source: sources[index % sources.count],
            title: "Performance session \(index + 1)",
            status: status,
            currentPhase: phase,
            createdAt: now.addingTimeInterval(TimeInterval(-900 - index * 11)),
            updatedAt: now.addingTimeInterval(TimeInterval(-index)),
            taskURL: "https://example.invalid/dev-island-performance/\(index + 1)",
            waitingMessage: status == .waiting ? "Fixture needs a deterministic answer" : nil
        )
    }

    private static func makeDecisionTask(
        sessionID: String,
        source: String,
        title: String,
        phase: String,
        now: Date
    ) -> AgentTask {
        AgentTask(
            id: sessionID,
            source: source,
            title: title,
            status: .waiting,
            currentPhase: phase,
            createdAt: now,
            updatedAt: now,
            taskURL: "https://example.invalid/dev-island-performance/decision",
            waitingMessage: phase
        )
    }
}
#endif
