import Foundation
import IslandCore

/// Example sessions the Welcome tutorial shows on the real island in place of
/// TaskStore content. Plain production value types: nothing here enters
/// TaskStore, persists, notifies, or reaches an Agent, and none of it is a
/// DEBUG fixture. `IslandRootView` substitutes the demo for the store at its
/// presentation seam and routes answers to demo requests back to the tour.
struct IslandTutorialDemo: Equatable {
    /// The moments the tour walks through on the island.
    enum Beat: Equatable, CaseIterable {
        /// Three sessions at work; the compact bar shows the first.
        case working
        /// The first session asks for permission to run a command.
        case askingPermission
        /// The first session asks a question with two options.
        case askingQuestion
        /// Answered; the session is back at work.
        case resumed
    }

    /// An answer the user gave on the island to demo content.
    enum Event: Equatable {
        case decision(requestID: UUID, AgentActionDecision)
        case answers(requestID: UUID, [AgentQuestionAnswer])
        case deferred(requestID: UUID)
        case taskTapped(TaskIdentity)
    }

    /// One recorded answer; `sequence` lets an observer tell two identical
    /// answers apart.
    struct Response: Equatable {
        let sequence: Int
        let event: Event
    }

    var beat: Beat
    var tasks: [AgentTask]
    var requests: [AgentActionRequest]

    static let source = "claude-code"
    /// Identity of the session that asks; it stays the same through every
    /// beat so its row keeps its identity in the panel.
    static let primaryIdentity = TaskIdentity(source: source, id: "welcome-demo-release")

    func owns(requestID: UUID) -> Bool {
        requests.contains { $0.id == requestID }
    }

    func owns(_ identity: TaskIdentity) -> Bool {
        tasks.contains { $0.identity == identity }
    }

    func owns(_ event: Event) -> Bool {
        switch event {
        case .decision(let requestID, _), .answers(let requestID, _), .deferred(let requestID):
            return owns(requestID: requestID)
        case .taskTapped(let identity):
            return owns(identity)
        }
    }

    /// The beat that follows an answer to the current request, or nil when
    /// the event is not an answer to it.
    func beat(after event: Event) -> Beat? {
        switch (beat, event) {
        case (.askingPermission, .decision(let requestID, _)) where owns(requestID: requestID),
             (.askingPermission, .deferred(let requestID)) where owns(requestID: requestID):
            return .askingQuestion
        case (.askingQuestion, .answers(let requestID, _)) where owns(requestID: requestID),
             (.askingQuestion, .deferred(let requestID)) where owns(requestID: requestID):
            return .resumed
        default:
            return nil
        }
    }
}

/// Builds the tour's example content in the app language. Titles are the
/// same strings the retired island specimen used, so the copy stays reviewed.
enum WelcomeDemoContent {
    /// Request ids are fixed per beat so re-rendering a beat (for example
    /// after a language change) keeps the same request on screen.
    static let permissionRequestID = UUID(uuidString: "6D1B3C50-0B1E-4C1F-9A3A-5F1D0C7E0001")!
    static let questionRequestID = UUID(uuidString: "6D1B3C50-0B1E-4C1F-9A3A-5F1D0C7E0002")!
    /// Never a `file://` URL: rows with file URLs look up the project branch
    /// on disk, and the demo must not touch the file system.
    private static let taskURL = "https://devisland.app/welcome/example"
    /// Copied from the retired specimen: the command the example asks about.
    static let permissionCommand = "npm run build"
    static let questionOptionLabels = ["npm", "pnpm"]

    static func demo(
        beat: IslandTutorialDemo.Beat,
        language: DevIslandLanguage,
        now: Date = .now
    ) -> IslandTutorialDemo {
        let primary = IslandTutorialDemo.primaryIdentity
        let primaryTitle: String
        let primaryStatus: TaskStatus
        var waitingMessage: String?
        var requests: [AgentActionRequest] = []

        switch beat {
        case .working:
            primaryTitle = L10n.string("Prepare release build", language: language)
            primaryStatus = .running
        case .askingPermission:
            primaryTitle = L10n.string("Prepare release build", language: language)
            primaryStatus = .waiting
            let request = AgentActionRequest(
                id: permissionRequestID,
                source: primary.source,
                sessionId: primary.id,
                kind: .permission,
                title: L10n.string("Allow shell command?", language: language),
                message: L10n.string("Claude Code wants to run this in your project.", language: language),
                detail: permissionCommand,
                createdAt: now,
                timeout: AgentActionRequest.maximumTimeout
            )
            waitingMessage = request.title
            requests = [request]
        case .askingQuestion:
            primaryTitle = L10n.string("Prepare release build", language: language)
            primaryStatus = .waiting
            let question = L10n.string("Which package manager should the build use?", language: language)
            let request = AgentActionRequest(
                id: questionRequestID,
                source: primary.source,
                sessionId: primary.id,
                kind: .question,
                title: L10n.string("Which package manager?", language: language),
                message: question,
                questions: [
                    AgentQuestion(
                        question: question,
                        header: L10n.string("Build setup", language: language),
                        options: [
                            AgentQuestionOption(
                                label: questionOptionLabels[0],
                                description: L10n.string("Matches the lockfile in this repo", language: language)
                            ),
                            AgentQuestionOption(
                                label: questionOptionLabels[1],
                                description: L10n.string("Faster installs; needs pnpm on this Mac", language: language)
                            ),
                        ]
                    ),
                ],
                createdAt: now,
                timeout: AgentActionRequest.maximumTimeout
            )
            waitingMessage = request.title
            requests = [request]
        case .resumed:
            primaryTitle = L10n.string("Back to work", language: language)
            primaryStatus = .running
        }

        // The asking session was created first so it stays the primary row;
        // the others show the island carrying more than one thing.
        let tasks = [
            AgentTask(
                id: primary.id,
                source: primary.source,
                title: primaryTitle,
                status: primaryStatus,
                createdAt: now.addingTimeInterval(-90),
                updatedAt: now,
                taskURL: taskURL,
                waitingMessage: waitingMessage
            ),
            AgentTask(
                id: "welcome-demo-notes",
                source: primary.source,
                title: L10n.string("Write release notes", language: language),
                status: .running,
                createdAt: now.addingTimeInterval(-60),
                updatedAt: now,
                taskURL: taskURL
            ),
            AgentTask(
                id: "welcome-demo-test",
                source: primary.source,
                title: L10n.string("Fix flaky test", language: language),
                status: .running,
                createdAt: now.addingTimeInterval(-30),
                updatedAt: now,
                taskURL: taskURL
            ),
        ]
        return IslandTutorialDemo(beat: beat, tasks: tasks, requests: requests)
    }
}
