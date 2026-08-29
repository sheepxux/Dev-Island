import AppKit
import SwiftUI
import XCTest
@testable import IslandAppLib
import IslandCore

/// Window-level keyboard contracts for the borderless island surface.
///
/// These tests do not stop at checking presentation policy. They host the
/// real SwiftUI decision surface in an AppKit window, inject key-equivalent
/// events, and verify which callback actually fires. That catches duplicate,
/// disabled, or accidentally destructive shortcuts before a release.
@MainActor
final class ActionRequestKeyboardContractTests: XCTestCase {
    func testPrimaryPermissionCommandReturnAllowsOnce() {
        var decisions: [AgentActionDecision] = []
        let request = permissionRequest(session: "primary-allow")
        let host = host(
            ActionRequestSurface(
                request: request,
                now: request.createdAt,
                isKeyboardPrimary: true,
                onDecision: { decisions.append($0) }
            )
        )

        XCTAssertTrue(host.perform(commandReturn(in: host.window)))
        XCTAssertEqual(decisions, [.allow])
    }

    func testPrimaryPermissionCommandDDeniesButEscapeNeverDecides() {
        var decisions: [AgentActionDecision] = []
        let request = permissionRequest(session: "primary-deny")
        let host = host(
            ActionRequestSurface(
                request: request,
                now: request.createdAt,
                isKeyboardPrimary: true,
                onDecision: { decisions.append($0) }
            )
        )

        XCTAssertTrue(host.perform(commandD(in: host.window)))
        XCTAssertEqual(decisions, [.deny])

        decisions.removeAll()
        XCTAssertFalse(host.perform(escape(in: host.window)))
        XCTAssertTrue(decisions.isEmpty)
    }

    func testSecondaryPermissionDoesNotOwnPanelShortcuts() {
        var decisions: [AgentActionDecision] = []
        let request = permissionRequest(session: "secondary")
        let host = host(
            ActionRequestSurface(
                request: request,
                now: request.createdAt,
                isKeyboardPrimary: false,
                onDecision: { decisions.append($0) }
            )
        )

        XCTAssertFalse(host.perform(commandReturn(in: host.window)))
        XCTAssertFalse(host.perform(commandD(in: host.window)))
        XCTAssertTrue(decisions.isEmpty)
    }

    func testPlanReviewRoutesApproveRejectAndContinueToDistinctCallbacks() throws {
        var decisions: [AgentActionDecision] = []
        var deferredCount = 0
        let request = try planReviewRequest()
        let host = host(
            ActionRequestSurface(
                request: request,
                now: request.createdAt,
                isKeyboardPrimary: true,
                initialPlanDocument: .render(
                    try XCTUnwrap(request.planReview).markdown
                ),
                onDecision: { decisions.append($0) },
                onDeferToAgent: { deferredCount += 1 }
            )
        )

        XCTAssertTrue(host.perform(commandO(in: host.window)))
        XCTAssertEqual(deferredCount, 1)
        XCTAssertTrue(decisions.isEmpty)

        XCTAssertTrue(host.perform(commandD(in: host.window)))
        XCTAssertEqual(decisions, [.deny])
        XCTAssertEqual(deferredCount, 1)

        XCTAssertTrue(host.perform(commandReturn(in: host.window)))
        XCTAssertEqual(decisions, [.deny, .allow])
        XCTAssertEqual(deferredCount, 1)
    }

    func testPlanReviewCannotDecideBeforeRenderingFinishes() throws {
        var decisions: [AgentActionDecision] = []
        var deferredCount = 0
        let request = try planReviewRequest()
        let host = host(
            ActionRequestSurface(
                request: request,
                now: request.createdAt,
                isKeyboardPrimary: true,
                onDecision: { decisions.append($0) },
                onDeferToAgent: { deferredCount += 1 }
            )
        )

        XCTAssertFalse(host.perform(commandD(in: host.window)))
        XCTAssertFalse(host.perform(commandReturn(in: host.window)))
        XCTAssertTrue(decisions.isEmpty)
        XCTAssertTrue(host.perform(commandO(in: host.window)))
        XCTAssertEqual(deferredCount, 1)
    }

    func testQuestionCannotCommandReturnWithoutSelectionAndCanContinueInClaude() {
        var answers: [[AgentQuestionAnswer]] = []
        var deferredCount = 0
        let request = questionRequest()
        let host = host(
            ActionRequestSurface(
                request: request,
                now: request.createdAt,
                isKeyboardPrimary: true,
                onDecision: { _ in XCTFail("Question must not emit a permission decision") },
                onAnswer: { answers.append($0) },
                onDeferToAgent: { deferredCount += 1 }
            )
        )

        // The primary button is disabled until the visible question has a
        // selection. The key equivalent must remain unhandled and cannot
        // submit an empty answer object.
        XCTAssertFalse(host.perform(commandReturn(in: host.window)))
        XCTAssertTrue(answers.isEmpty)

        XCTAssertTrue(host.perform(commandO(in: host.window)))
        XCTAssertEqual(deferredCount, 1)
        XCTAssertTrue(answers.isEmpty)
    }

    private func permissionRequest(session: String) -> AgentActionRequest {
        AgentActionRequest(
            source: "codex",
            sessionId: session,
            kind: .permission,
            title: "Allow shell command?",
            message: "Codex wants to verify the app bundle.",
            detail: "codesign --verify --deep --strict 'Dev Island.app'",
            createdAt: fixedNow,
            timeout: 90
        )
    }

    private func planReviewRequest() throws -> AgentActionRequest {
        let review = try XCTUnwrap(AgentPlanReview(
            markdown: "# Release plan\n\n1. Test\n2. Build",
            originalInputJSON: Data(#"{"plan":"Release plan"}"#.utf8)
        ))
        return AgentActionRequest(
            source: "claude-code",
            sessionId: "plan-review",
            kind: .planReview,
            title: "Review Claude Code plan",
            message: "Claude Code is ready to begin implementation.",
            planReview: review,
            createdAt: fixedNow,
            timeout: 90
        )
    }

    private func questionRequest() -> AgentActionRequest {
        AgentActionRequest(
            source: "claude-code",
            sessionId: "question",
            kind: .question,
            title: "Claude Code needs input",
            message: "Choose one option to continue.",
            questions: [
                AgentQuestion(
                    question: "Which verification should run?",
                    header: "Checks",
                    options: [
                        AgentQuestionOption(label: "Unit tests"),
                        AgentQuestionOption(label: "Visual review"),
                    ]
                ),
            ],
            createdAt: fixedNow,
            timeout: 90
        )
    }

    private var fixedNow: Date {
        Date(timeIntervalSince1970: 1_787_700_000)
    }

    @MainActor
    private final class HostedSurface<Content: View> {
        let window: NSWindow
        let hostingView: NSHostingView<Content>

        init(content: Content, size: NSSize) {
            _ = NSApplication.shared
            hostingView = NSHostingView(rootView: content)
            hostingView.frame = NSRect(origin: .zero, size: size)

            window = NSWindow(
                contentRect: NSRect(
                    x: -10_000,
                    y: -10_000,
                    width: size.width,
                    height: size.height
                ),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.makeFirstResponder(hostingView)
            hostingView.layoutSubtreeIfNeeded()
        }

        func perform(_ event: NSEvent) -> Bool {
            window.performKeyEquivalent(with: event)
        }
    }

    private func host<Content: View>(
        _ content: Content,
        size: NSSize = NSSize(width: 420, height: 360)
    ) -> HostedSurface<Content> {
        HostedSurface(content: content, size: size)
    }

    private func commandReturn(in window: NSWindow) -> NSEvent {
        keyEvent(
            characters: "\r",
            modifiers: [.command],
            keyCode: 36,
            window: window
        )
    }

    private func commandD(in window: NSWindow) -> NSEvent {
        keyEvent(
            characters: "d",
            modifiers: [.command],
            keyCode: 2,
            window: window
        )
    }

    private func commandO(in window: NSWindow) -> NSEvent {
        keyEvent(
            characters: "o",
            modifiers: [.command],
            keyCode: 31,
            window: window
        )
    }

    private func escape(in window: NSWindow) -> NSEvent {
        keyEvent(
            characters: "\u{1B}",
            modifiers: [],
            keyCode: 53,
            window: window
        )
    }

    private func keyEvent(
        characters: String,
        modifiers: NSEvent.ModifierFlags,
        keyCode: UInt16,
        window: NSWindow
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
