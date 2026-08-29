import XCTest
@testable import IslandAppLib
import IslandCore

final class QuestionAnswerDraftTests: XCTestCase {
    func testSingleSelectionReplacesThePreviousChoice() throws {
        let questions = fixtures()
        let question = questions[0]
        var draft = QuestionAnswerDraft(questions: questions)

        draft.toggle(question.options[0], in: question)
        draft.toggle(question.options[1], in: question)

        XCTAssertFalse(draft.isSelected(question.options[0], in: question))
        XCTAssertTrue(draft.isSelected(question.options[1], in: question))
        XCTAssertEqual(
            draft.answers,
            nil,
            "A choice for one question must never fabricate a complete submission"
        )
    }

    func testMultiSelectionTogglesAndPreservesVisibleOptionOrder() throws {
        let questions = fixtures()
        let question = questions[1]
        var draft = QuestionAnswerDraft(questions: questions)
        draft.toggle(questions[0].options[0], in: questions[0])
        XCTAssertEqual(draft.advanceOrSubmit(), .advanced)

        // Select out of order. The submission must still follow the visible
        // option order so Claude receives a stable wire value.
        draft.toggle(question.options[2], in: question)
        draft.toggle(question.options[0], in: question)
        XCTAssertEqual(
            draft.advanceOrSubmit(),
            .submit([
                AgentQuestionAnswer(
                    question: questions[0].question,
                    selectedLabels: [questions[0].options[0].label]
                ),
                AgentQuestionAnswer(
                    question: question.question,
                    selectedLabels: [question.options[0].label, question.options[2].label]
                ),
            ])
        )

        draft.toggle(question.options[0], in: question)
        XCTAssertFalse(draft.isSelected(question.options[0], in: question))
        XCTAssertTrue(draft.isSelected(question.options[2], in: question))
    }

    func testNextAndBackPreserveTheDraft() {
        let questions = fixtures()
        var draft = QuestionAnswerDraft(questions: questions)

        XCTAssertEqual(draft.advanceOrSubmit(), .blocked)
        draft.toggle(questions[0].options[0], in: questions[0])
        XCTAssertEqual(draft.advanceOrSubmit(), .advanced)
        XCTAssertEqual(draft.currentIndex, 1)

        XCTAssertTrue(draft.goBack())
        XCTAssertEqual(draft.currentIndex, 0)
        XCTAssertTrue(draft.isSelected(questions[0].options[0], in: questions[0]))
        XCTAssertFalse(draft.goBack())
    }

    func testLastQuestionCannotSubmitWhileAnyAnswerIsMissing() {
        let questions = fixtures()
        var draft = QuestionAnswerDraft(questions: questions)
        draft.toggle(questions[0].options[0], in: questions[0])
        XCTAssertEqual(draft.advanceOrSubmit(), .advanced)

        XCTAssertEqual(draft.advanceOrSubmit(), .blocked)
        XCTAssertNil(draft.answers)
        XCTAssertEqual(draft.currentIndex, 1)
    }

    func testCompleteTwoQuestionFlowSubmitsCanonicalAnswers() {
        let questions = fixtures()
        var draft = QuestionAnswerDraft(questions: questions)

        draft.toggle(questions[0].options[1], in: questions[0])
        XCTAssertEqual(draft.advanceOrSubmit(), .advanced)
        draft.toggle(questions[1].options[1], in: questions[1])
        draft.toggle(questions[1].options[2], in: questions[1])

        XCTAssertEqual(
            draft.advanceOrSubmit(),
            .submit([
                AgentQuestionAnswer(
                    question: questions[0].question,
                    selectedLabels: [questions[0].options[1].label]
                ),
                AgentQuestionAnswer(
                    question: questions[1].question,
                    selectedLabels: [
                        questions[1].options[1].label,
                        questions[1].options[2].label,
                    ]
                ),
            ])
        )
    }

    private func fixtures() -> [AgentQuestion] {
        [
            AgentQuestion(
                question: "Where should approval happen?",
                header: "Surface",
                options: [
                    AgentQuestionOption(label: "Dev Island"),
                    AgentQuestionOption(label: "Claude Code"),
                ]
            ),
            AgentQuestion(
                question: "Which checks should run?",
                header: "Checks",
                options: [
                    AgentQuestionOption(label: "Unit tests"),
                    AgentQuestionOption(label: "Launch smoke"),
                    AgentQuestionOption(label: "Visual review"),
                ],
                allowsMultipleSelection: true
            ),
        ]
    }
}
