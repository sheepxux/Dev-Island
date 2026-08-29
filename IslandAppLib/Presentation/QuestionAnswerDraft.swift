import Foundation
import IslandCore

/// Pure, deterministic draft state for a progressive AskUserQuestion flow.
///
/// Keeping selection and navigation rules outside SwiftUI makes the safety
/// boundary testable without relying on view timing or accessibility actions:
/// every question must have an answer, single-select replaces the previous
/// choice, multi-select toggles, and answers preserve visible option order.
struct QuestionAnswerDraft: Equatable {
    enum Outcome: Equatable {
        case blocked
        case advanced
        case submit([AgentQuestionAnswer])
    }

    let questions: [AgentQuestion]
    private(set) var currentIndex: Int
    private var selections: [String: Set<String>]

    init(questions: [AgentQuestion]) {
        self.questions = questions
        currentIndex = 0
        selections = [:]
    }

    var currentQuestion: AgentQuestion? {
        guard questions.indices.contains(currentIndex) else { return nil }
        return questions[currentIndex]
    }

    var isLastQuestion: Bool {
        !questions.isEmpty && currentIndex == questions.count - 1
    }

    func hasSelection(for question: AgentQuestion) -> Bool {
        !(selections[question.id] ?? []).isEmpty
    }

    func isSelected(_ option: AgentQuestionOption, in question: AgentQuestion) -> Bool {
        selections[question.id]?.contains(option.label) == true
    }

    mutating func toggle(_ option: AgentQuestionOption, in question: AgentQuestion) {
        guard questions.contains(question), question.options.contains(option) else { return }

        if question.allowsMultipleSelection {
            var selected = selections[question.id] ?? []
            if selected.contains(option.label) {
                selected.remove(option.label)
            } else {
                selected.insert(option.label)
            }
            selections[question.id] = selected
        } else {
            selections[question.id] = [option.label]
        }
    }

    @discardableResult
    mutating func goBack() -> Bool {
        guard currentIndex > 0 else { return false }
        currentIndex -= 1
        return true
    }

    mutating func advanceOrSubmit() -> Outcome {
        guard let question = currentQuestion, hasSelection(for: question) else {
            return .blocked
        }

        if !isLastQuestion {
            currentIndex += 1
            return .advanced
        }

        guard let answers else { return .blocked }
        return .submit(answers)
    }

    var answers: [AgentQuestionAnswer]? {
        let canonical = questions.compactMap { question -> AgentQuestionAnswer? in
            let selected = selections[question.id] ?? []
            let selectedLabels = question.options.map(\.label).filter(selected.contains)
            guard !selectedLabels.isEmpty else { return nil }

            return AgentQuestionAnswer(
                question: question.question,
                selectedLabels: selectedLabels
            )
        }
        return canonical.count == questions.count ? canonical : nil
    }
}
