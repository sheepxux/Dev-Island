import Foundation
import XCTest
@testable import IslandCore

final class ClaudeQuestionHookTests: XCTestCase {
    func testDecodesDocumentedAskUserQuestionPayload() throws {
        let request = try XCTUnwrap(ClaudeQuestionHook.decodeRequest(samplePayload()))

        XCTAssertEqual(request.source, "claude-code")
        XCTAssertEqual(request.sessionId, "session-question")
        XCTAssertEqual(request.kind, .question)
        XCTAssertEqual(request.questions.count, 2)
        XCTAssertEqual(request.questions[0].header, "Framework")
        XCTAssertEqual(request.questions[0].options.map(\.label), ["SwiftUI", "AppKit"])
        XCTAssertFalse(request.questions[0].allowsMultipleSelection)
        XCTAssertEqual(request.questions[1].header, "Checks")
        XCTAssertTrue(request.questions[1].allowsMultipleSelection)
    }

    func testEncodesAllowWithOriginalQuestionsAndAnswers() throws {
        let request = try XCTUnwrap(ClaudeQuestionHook.decodeRequest(samplePayload()))
        let response = AgentActionResponse.question(AgentQuestionSubmission(
            questions: request.questions,
            answers: [
                AgentQuestionAnswer(
                    question: "Which UI framework?",
                    selectedLabels: ["SwiftUI"]
                ),
                AgentQuestionAnswer(
                    question: "Which checks should run?",
                    selectedLabels: ["Unit tests", "Launch smoke"]
                ),
            ]
        ))

        let encoded = ClaudeQuestionHook.response(for: response)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: Data(encoded.utf8)
        ) as? [String: Any])
        let output = try XCTUnwrap(root["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(output["hookEventName"] as? String, "PreToolUse")
        XCTAssertEqual(output["permissionDecision"] as? String, "allow")

        let updatedInput = try XCTUnwrap(output["updatedInput"] as? [String: Any])
        let questions = try XCTUnwrap(updatedInput["questions"] as? [[String: Any]])
        let answers = try XCTUnwrap(updatedInput["answers"] as? [String: String])
        XCTAssertEqual(questions.count, 2)
        XCTAssertEqual(questions[0]["question"] as? String, "Which UI framework?")
        XCTAssertEqual(questions[1]["multiSelect"] as? Bool, true)
        XCTAssertEqual(answers["Which UI framework?"], "SwiftUI")
        XCTAssertEqual(answers["Which checks should run?"], "Unit tests, Launch smoke")
    }

    func testRejectsWrongEventToolAnsweredAndAmbiguousPayloads() {
        let invalidPayloads = [
            #"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":[]}}"#,
            #"{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"questions":[]}}"#,
            #"{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Q?","header":"H","options":[{"label":"A"}]}],"answers":{"Q?":"A"}}}"#,
            #"{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Q?","header":"H","options":[{"label":"A"}]},{"question":"Q?","header":"H2","options":[{"label":"B"}]}]}}"#,
            #"{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Q?","header":"H","options":[{"label":"A"},{"label":"A"}]}]}}"#,
        ]

        for json in invalidPayloads {
            XCTAssertNil(ClaudeQuestionHook.decodeRequest(Data(json.utf8)), json)
        }
    }

    func testBoundsQuestionHeaderOptionAndDescriptionByUTF8Bytes() throws {
        let pathologicalCluster = "a" + String(repeating: "\u{0301}", count: 8_192)
        let root: [String: Any] = [
            "session_id": "session-unicode",
            "hook_event_name": "PreToolUse",
            "tool_name": "AskUserQuestion",
            "tool_input": [
                "questions": [[
                    "question": "Question " + pathologicalCluster,
                    "header": "Header " + pathologicalCluster,
                    "options": [[
                        "label": "Label " + pathologicalCluster,
                        "description": "Description " + pathologicalCluster,
                    ]],
                ]],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: root)

        let request = try XCTUnwrap(ClaudeQuestionHook.decodeRequest(data))
        let question = try XCTUnwrap(request.questions.first)
        let option = try XCTUnwrap(question.options.first)
        let description = try XCTUnwrap(option.description)

        XCTAssertLessThanOrEqual(
            question.question.utf8.count,
            AgentQuestion.maximumQuestionBytes
        )
        XCTAssertLessThanOrEqual(
            question.header.utf8.count,
            AgentQuestion.maximumHeaderBytes
        )
        XCTAssertLessThanOrEqual(
            option.label.utf8.count,
            AgentQuestionOption.maximumLabelBytes
        )
        XCTAssertLessThanOrEqual(
            description.utf8.count,
            AgentQuestionOption.maximumDescriptionBytes
        )
        XCTAssertLessThan(question.question.utf8.count, ("Question " + pathologicalCluster).utf8.count)
        XCTAssertLessThan(question.header.utf8.count, ("Header " + pathologicalCluster).utf8.count)
        XCTAssertLessThan(option.label.utf8.count, ("Label " + pathologicalCluster).utf8.count)
        XCTAssertLessThan(description.utf8.count, ("Description " + pathologicalCluster).utf8.count)
    }

    func testInvalidOrMismatchedResponsesFailNeutral() throws {
        let request = try XCTUnwrap(ClaudeQuestionHook.decodeRequest(samplePayload()))
        XCTAssertEqual(ClaudeQuestionHook.response(for: nil), "{}")
        XCTAssertEqual(
            ClaudeQuestionHook.response(for: .permission(.allow)),
            "{}"
        )
        XCTAssertEqual(
            ClaudeQuestionHook.response(for: .question(AgentQuestionSubmission(
                questions: request.questions,
                answers: [AgentQuestionAnswer(
                    question: request.questions[0].question,
                    selectedLabels: ["Not an option"]
                )]
            ))),
            "{}"
        )
    }

    private func samplePayload() -> Data {
        Data(#"""
        {
          "session_id": "session-question",
          "cwd": "/Users/dev/Project",
          "hook_event_name": "PreToolUse",
          "tool_name": "AskUserQuestion",
          "tool_input": {
            "questions": [
              {
                "question": "Which UI framework?",
                "header": "Framework",
                "options": [
                  {"label": "SwiftUI", "description": "Use native declarative UI"},
                  {"label": "AppKit", "description": "Use imperative views"}
                ],
                "multiSelect": false
              },
              {
                "question": "Which checks should run?",
                "header": "Checks",
                "options": [
                  {"label": "Unit tests"},
                  {"label": "Launch smoke"}
                ],
                "multiSelect": true
              }
            ]
          },
          "tool_use_id": "toolu_question"
        }
        """#.utf8)
    }
}
