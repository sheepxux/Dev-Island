import Foundation

/// Claude Code AskUserQuestion wire contract over a matcher-scoped
/// `PreToolUse` hook.
///
/// Source of truth (verified 2026-08-26):
/// https://code.claude.com/docs/en/hooks#askuserquestion
/// https://code.claude.com/docs/en/hooks#allow-with-updatedinput
enum ClaudeQuestionHook {
    private struct Payload: Decodable {
        let hookEventName: String
        let sessionId: String
        let toolName: String
        let toolInput: ToolInput
    }

    private struct ToolInput: Decodable {
        let questions: [WireQuestion]
        let answers: [String: String]?
    }

    private struct WireQuestion: Decodable {
        let question: String
        let header: String
        let options: [WireOption]
        let multiSelect: Bool?
    }

    private struct WireOption: Decodable {
        let label: String
        let description: String?
    }

    static func decodeRequest(_ data: Data) -> AgentActionRequest? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(Payload.self, from: data),
              payload.hookEventName == "PreToolUse",
              payload.toolName == "AskUserQuestion",
              let sessionID = LocalAgentEvent.validSessionId(payload.sessionId),
              payload.toolInput.answers?.isEmpty != false,
              (1...AgentActionRequest.maximumQuestions).contains(
                payload.toolInput.questions.count
              ) else {
            return nil
        }

        let questions = payload.toolInput.questions.compactMap(decodeQuestion)
        guard questions.count == payload.toolInput.questions.count,
              Set(questions.map(\.question)).count == questions.count else {
            return nil
        }

        let title = questions.count == 1
            ? questions[0].header
            : "Claude Code needs input"
        let message = questions.count == 1
            ? questions[0].question
            : "Answer \(questions.count) questions to continue this session."

        return AgentActionRequest(
            source: "claude-code",
            sessionId: sessionID,
            kind: .question,
            title: title,
            message: message,
            questions: questions
        )
    }

    static func response(for response: AgentActionResponse?) -> String {
        guard case .question(let submission) = response,
              isValid(submission) else {
            return "{}"
        }

        let questions: [[String: Any]] = submission.questions.map { question in
            let value: [String: Any] = [
                "question": question.question,
                "header": question.header,
                "multiSelect": question.allowsMultipleSelection,
                "options": question.options.map { option in
                    var optionValue: [String: Any] = ["label": option.label]
                    if let description = option.description, !description.isEmpty {
                        optionValue["description"] = description
                    }
                    return optionValue
                },
            ]
            // Keep this mutable shape explicit: if Claude adds another
            // documented question field, it belongs here and in the model.
            return value
        }
        let answers = Dictionary(uniqueKeysWithValues: submission.answers.map {
            ($0.question, $0.wireValue)
        })
        let body: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "updatedInput": [
                    "questions": questions,
                    "answers": answers,
                ],
            ],
        ]

        guard let data = try? JSONSerialization.data(
            withJSONObject: body,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeQuestion(_ value: WireQuestion) -> AgentQuestion? {
        let questionText = boundedNonempty(
            value.question,
            characterLimit: AgentQuestion.maximumQuestionCharacters,
            byteLimit: AgentQuestion.maximumQuestionBytes
        )
        let header = boundedNonempty(
            value.header,
            characterLimit: AgentQuestion.maximumHeaderCharacters,
            byteLimit: AgentQuestion.maximumHeaderBytes
        )
        guard let questionText, let header,
              (1...AgentQuestion.maximumOptions).contains(value.options.count) else {
            return nil
        }

        let options = value.options.compactMap { option -> AgentQuestionOption? in
            guard let label = boundedNonempty(
                option.label,
                characterLimit: AgentQuestionOption.maximumLabelCharacters,
                byteLimit: AgentQuestionOption.maximumLabelBytes
            ) else { return nil }
            let description = option.description.flatMap {
                boundedNonempty(
                    $0,
                    characterLimit: AgentQuestionOption.maximumDescriptionCharacters,
                    byteLimit: AgentQuestionOption.maximumDescriptionBytes
                )
            }
            return AgentQuestionOption(label: label, description: description)
        }
        guard options.count == value.options.count,
              Set(options.map(\.label)).count == options.count else {
            return nil
        }

        return AgentQuestion(
            question: questionText,
            header: header,
            options: options,
            allowsMultipleSelection: value.multiSelect ?? false
        )
    }

    private static func boundedNonempty(
        _ value: String,
        characterLimit: Int,
        byteLimit: Int
    ) -> String? {
        AgentActionTextPolicy.boundedNonempty(
            value,
            maximumCharacters: characterLimit,
            maximumUTF8Bytes: byteLimit
        )
    }

    private static func isValid(_ submission: AgentQuestionSubmission) -> Bool {
        guard !submission.questions.isEmpty,
              submission.questions.count == submission.answers.count else {
            return false
        }

        let answersByQuestion = Dictionary(
            grouping: submission.answers,
            by: \.question
        )
        guard answersByQuestion.count == submission.questions.count else { return false }

        return submission.questions.allSatisfy { question in
            guard let answers = answersByQuestion[question.question],
                  answers.count == 1 else { return false }
            let selected = answers[0].selectedLabels
            guard !selected.isEmpty,
                  question.allowsMultipleSelection || selected.count == 1 else {
                return false
            }
            let optionLabels = Set(question.options.map(\.label))
            return Set(selected).count == selected.count
                && selected.allSatisfy(optionLabels.contains)
        }
    }
}
