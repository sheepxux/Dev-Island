import XCTest
@testable import IslandAppLib
import IslandCore

final class IslandTutorialDemoTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Strings the release flavor verifier rejects in a shipping binary. The
    /// demo is production code, so none of its copy may borrow them.
    private let releaseForbiddenMarkers = [
        "DEV_ISLAND_FORCE_INCREASED_CONTRAST",
        "Seed 3 (preview set)",
        "Sandbox-injected waiting prompt",
    ]

    func testEveryBeatShowsThreeSessionsLedByTheAskingOne() {
        for beat in IslandTutorialDemo.Beat.allCases {
            let demo = WelcomeDemoContent.demo(beat: beat, language: .english, now: now)
            XCTAssertEqual(demo.beat, beat)
            XCTAssertEqual(demo.tasks.count, 3, "\(beat)")
            XCTAssertEqual(demo.tasks.first?.identity, IslandTutorialDemo.primaryIdentity, "\(beat)")
            XCTAssertEqual(demo.tasks.map(\.createdAt), demo.tasks.map(\.createdAt).sorted(), "\(beat)")
            XCTAssertTrue(demo.tasks.allSatisfy { !$0.taskURL.hasPrefix("file:") }, "\(beat)")
            XCTAssertTrue(demo.tasks.allSatisfy { $0.currentPhase == nil }, "\(beat)")
        }
    }

    func testRequestsBelongToThePrimarySessionSoTheyRenderInline() {
        let permission = WelcomeDemoContent.demo(beat: .askingPermission, language: .english, now: now)
        let question = WelcomeDemoContent.demo(beat: .askingQuestion, language: .english, now: now)

        XCTAssertEqual(permission.requests.map(\.kind), [.permission])
        XCTAssertEqual(permission.requests.first?.taskIdentity, IslandTutorialDemo.primaryIdentity)
        XCTAssertEqual(permission.requests.first?.detail, WelcomeDemoContent.permissionCommand)
        XCTAssertEqual(permission.tasks.first?.status, .waiting)

        XCTAssertEqual(question.requests.map(\.kind), [.question])
        XCTAssertEqual(question.requests.first?.taskIdentity, IslandTutorialDemo.primaryIdentity)
        XCTAssertEqual(
            question.requests.first?.questions.first?.options.map(\.label),
            WelcomeDemoContent.questionOptionLabels
        )
        XCTAssertEqual(question.requests.first?.questions.first?.allowsMultipleSelection, false)

        for beat in [IslandTutorialDemo.Beat.working, .resumed] {
            XCTAssertTrue(WelcomeDemoContent.demo(beat: beat, language: .english, now: now).requests.isEmpty)
        }
    }

    func testRequestIdsAreStableAcrossRebuildsAndLanguages() {
        let english = WelcomeDemoContent.demo(beat: .askingPermission, language: .english, now: now)
        let chinese = WelcomeDemoContent.demo(beat: .askingPermission, language: .simplifiedChinese, now: now)

        XCTAssertEqual(english.requests.first?.id, chinese.requests.first?.id)
        XCTAssertNotEqual(english.requests.first?.title, chinese.requests.first?.title)
        XCTAssertNotEqual(WelcomeDemoContent.permissionRequestID, WelcomeDemoContent.questionRequestID)
    }

    func testDemoCopyNeverBorrowsReleaseForbiddenMarkers() {
        for language in [DevIslandLanguage.english, .simplifiedChinese] {
            for beat in IslandTutorialDemo.Beat.allCases {
                let demo = WelcomeDemoContent.demo(beat: beat, language: language, now: now)
                var strings: [String] = []
                for task in demo.tasks {
                    strings.append(task.title)
                    strings.append(task.waitingMessage ?? "")
                }
                for request in demo.requests {
                    strings.append(request.title)
                    strings.append(request.message)
                    strings.append(request.detail ?? "")
                    for question in request.questions {
                        strings.append(question.question)
                        strings.append(question.header)
                        strings.append(contentsOf: question.options.map(\.label))
                    }
                }
                for marker in releaseForbiddenMarkers {
                    XCTAssertFalse(strings.contains { $0.contains(marker) }, "\(beat) \(language) contains \(marker)")
                }
            }
        }
    }

    func testOwnershipCoversOnlyDemoRequestsAndSessions() {
        let demo = WelcomeDemoContent.demo(beat: .askingPermission, language: .english, now: now)
        let request = demo.requests[0]

        XCTAssertTrue(demo.owns(requestID: request.id))
        XCTAssertFalse(demo.owns(requestID: UUID()))
        XCTAssertTrue(demo.owns(IslandTutorialDemo.primaryIdentity))
        XCTAssertFalse(demo.owns(TaskIdentity(source: "codex", id: "real")))
        XCTAssertTrue(demo.owns(.decision(requestID: request.id, .allow)))
        XCTAssertFalse(demo.owns(.answers(requestID: UUID(), [])))
        XCTAssertTrue(demo.owns(.taskTapped(IslandTutorialDemo.primaryIdentity)))
    }

    func testAnswersAdvanceTheBeatOnlyForTheCurrentRequest() {
        let permission = WelcomeDemoContent.demo(beat: .askingPermission, language: .english, now: now)
        let question = WelcomeDemoContent.demo(beat: .askingQuestion, language: .english, now: now)
        let permissionID = permission.requests[0].id
        let questionID = question.requests[0].id

        XCTAssertEqual(permission.beat(after: .decision(requestID: permissionID, .deny)), .askingQuestion)
        XCTAssertEqual(permission.beat(after: .decision(requestID: permissionID, .allow)), .askingQuestion)
        XCTAssertEqual(permission.beat(after: .deferred(requestID: permissionID)), .askingQuestion)
        XCTAssertNil(permission.beat(after: .decision(requestID: questionID, .allow)))
        XCTAssertNil(permission.beat(after: .taskTapped(IslandTutorialDemo.primaryIdentity)))

        let answer = AgentQuestionAnswer(
            question: question.requests[0].questions[0].question,
            selectedLabels: ["npm"]
        )
        XCTAssertEqual(question.beat(after: .answers(requestID: questionID, [answer])), .resumed)
        XCTAssertNil(question.beat(after: .answers(requestID: permissionID, [answer])))

        let working = WelcomeDemoContent.demo(beat: .working, language: .english, now: now)
        XCTAssertNil(working.beat(after: .decision(requestID: permissionID, .allow)))
    }
}
