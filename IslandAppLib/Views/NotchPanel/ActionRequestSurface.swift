import SwiftUI
import IslandCore

/// Focused decision surface that replaces the blocked session's ordinary row
/// while a response is required. It stays separate from `TaskCard` so SwiftUI
/// never nests Allow / Deny buttons inside the row's jump-back button.
struct ActionRequestSurface: View {
    let request: AgentActionRequest
    /// Session title carried by the matching live task. Keeping it inside the
    /// decision surface avoids repeating a full clickable TaskCard above the
    /// request while preserving enough context for a safe decision.
    var contextTitle: String? = nil
    var additionalQueuedCount: Int = 0
    /// Deterministic override for previews/tests. Production uses a tiny clock
    /// inside the request header, leaving the form and decision surface stable.
    var now: Date? = nil
    var isLive: Bool = true
    /// The oldest unresolved request alone owns key equivalents. This keeps
    /// shortcuts deterministic when several Agent sessions need attention.
    var isKeyboardPrimary: Bool = false
    let onDecision: (AgentActionDecision) -> Void
    var onAnswer: ([AgentQuestionAnswer]) -> Void = { _ in }
    var onDeferToAgent: () -> Void = {}

    @State private var questionDraft: QuestionAnswerDraft
    @State private var planRenderingState = PlanMarkdownRenderingOperationState()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var accessibilityContrast
    @Environment(\.devIslandLanguage) private var language

    init(
        request: AgentActionRequest,
        contextTitle: String? = nil,
        additionalQueuedCount: Int = 0,
        now: Date? = nil,
        isLive: Bool = true,
        isKeyboardPrimary: Bool = false,
        initialPlanDocument: PlanMarkdownDocument? = nil,
        onDecision: @escaping (AgentActionDecision) -> Void,
        onAnswer: @escaping ([AgentQuestionAnswer]) -> Void = { _ in },
        onDeferToAgent: @escaping () -> Void = {}
    ) {
        self.request = request
        self.contextTitle = contextTitle
        self.additionalQueuedCount = additionalQueuedCount
        self.now = now
        self.isLive = isLive
        self.isKeyboardPrimary = isKeyboardPrimary
        self.onDecision = onDecision
        self.onAnswer = onAnswer
        self.onDeferToAgent = onDeferToAgent
        _questionDraft = State(
            initialValue: QuestionAnswerDraft(questions: request.questions)
        )
        _planRenderingState = State(
            initialValue: PlanMarkdownRenderingOperationState(
                requestID: initialPlanDocument == nil ? nil : request.id,
                document: initialPlanDocument
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            contextLabel

            switch request.kind {
            case .permission:
                permissionContent
            case .question:
                questionContent
            case .planReview:
                planReviewContent
            }
        }
        .padding(.leading, 43)
        .padding(.trailing, 12)
        .padding(.top, 7)
        .padding(.bottom, 12)
        .background(alignment: .leading) {
            Rectangle()
                .fill(Palette.stateWaiting.opacity(usesIncreasedContrast ? 1 : 0.82))
                .frame(width: usesIncreasedContrast ? 1.5 : 1)
                .padding(.leading, 31)
                .padding(.vertical, 8)
        }
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(usesIncreasedContrast ? 0.055 : 0.027))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    Color.white.opacity(usesIncreasedContrast ? 0.18 : 0.065),
                    lineWidth: usesIncreasedContrast ? 1 : 0.5
                )
        }
        .transition(
            reduceMotion
                ? .opacity
                : .opacity.combined(with: .move(edge: .top))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilitySortPriority(isKeyboardPrimary ? 100 : 0)
        .onChange(of: request.id) { _, _ in
            questionDraft = QuestionAnswerDraft(questions: request.questions)
            planRenderingState.invalidate()
        }
        .task(id: request.id) { await renderPlanIfNeeded() }
        .onDisappear { planRenderingState.invalidate() }
    }

    @ViewBuilder
    private var contextLabel: some View {
        if let contextTitle, !contextTitle.isEmpty {
            Text(contextTitle)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(
                    Palette.textSecondary.opacity(usesIncreasedContrast ? 1 : 0.78)
                )
                .lineLimit(1)
                .truncationMode(.tail)
                // The containing decision group already includes this title
                // in its label; suppress a duplicate VoiceOver stop.
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var planReviewContent: some View {
        if request.planReview != nil {
            VStack(alignment: .leading, spacing: 4) {
                Text(request.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.warmWhite.opacity(usesIncreasedContrast ? 1 : 0.94))

                Text(request.message)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Palette.textSecondary.opacity(usesIncreasedContrast ? 1 : 0.9))
            }

            ScrollView {
                if let document = planRenderingState.document {
                    if document.blocks.isEmpty {
                        Text(L10n.string(
                            "This plan cannot be rendered safely.",
                            language: language
                        ))
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 10)
                    } else {
                        PlanMarkdownView(document: document)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 10)
                    }
                } else {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityHidden(true)
                        Text(L10n.string("Preparing plan…", language: language))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        L10n.string("Preparing Claude Code plan", language: language)
                    )
                }
            }
            .scrollIndicators(.visible)
            .frame(minHeight: 96, maxHeight: 210)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(usesIncreasedContrast ? 0.5 : 0.32))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        Color.white.opacity(usesIncreasedContrast ? 0.18 : 0.06),
                        lineWidth: usesIncreasedContrast ? 1 : 0.5
                    )
            }
            .accessibilityLabel(
                L10n.string("Claude Code plan", language: language)
            )

            HStack(spacing: 7) {
                queuedLabel

                Button(L10n.string("Continue in Claude", language: language)) {
                    onDeferToAgent()
                }
                    .buttonStyle(ActionDecisionButtonStyle(role: .secondary))
                    .help(actionHelp(
                        "Continue reviewing this plan in Claude Code",
                        shortcut: "⌘O"
                    ))
                    .accessibilityLabel(
                        L10n.string("Continue plan review in Claude Code", language: language)
                    )
                    .accessibilityHint(
                        L10n.string(
                            "Returns this review to Claude Code without deciding it here",
                            language: language
                        )
                    )
                    .actionRequestKeyboardShortcut(
                        "o",
                        modifiers: [.command],
                        enabled: isKeyboardPrimary
                    )

                Spacer(minLength: 5)

                Button(L10n.string("Reject", language: language)) { onDecision(.deny) }
                    .buttonStyle(ActionDecisionButtonStyle(role: .secondary))
                    .disabled(!isPlanDecisionReady)
                    .help(actionHelp("Reject this plan", shortcut: "⌘D"))
                    .accessibilityHint(
                        L10n.string(
                            "Rejects this plan and lets Claude Code continue",
                            language: language
                        )
                    )
                    .actionRequestKeyboardShortcut(
                        "d",
                        modifiers: [.command],
                        enabled: isKeyboardPrimary && isPlanDecisionReady
                    )

                Button(L10n.string("Approve plan", language: language)) {
                    onDecision(.allow)
                }
                    .buttonStyle(ActionDecisionButtonStyle(role: .primary))
                    .disabled(!isPlanDecisionReady)
                    .help(actionHelp(
                        "Approve this plan and let Claude Code continue",
                        shortcut: "⌘↩"
                    ))
                    .accessibilityHint(
                        L10n.string(
                            "Approves this plan and lets Claude Code continue",
                            language: language
                        )
                    )
                    .actionRequestKeyboardShortcut(
                        .return,
                        modifiers: [.command],
                        enabled: isKeyboardPrimary && isPlanDecisionReady
                    )
            }
        } else {
            Text(L10n.string("This plan cannot be rendered safely.", language: language))
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)
            Button(L10n.string("Continue in Claude", language: language)) {
                onDeferToAgent()
            }
                .buttonStyle(ActionDecisionButtonStyle(role: .secondary))
                .help(actionHelp(
                    "Continue reviewing this plan in Claude Code",
                    shortcut: "⌘O"
                ))
                .accessibilityLabel(
                    L10n.string("Continue plan review in Claude Code", language: language)
                )
                .accessibilityHint(
                    L10n.string(
                        "Returns this review to Claude Code because it cannot be rendered safely here",
                        language: language
                    )
                )
                .actionRequestKeyboardShortcut(
                    "o",
                    modifiers: [.command],
                    enabled: isKeyboardPrimary
                )
        }
    }

    @MainActor
    private func renderPlanIfNeeded() async {
        guard let markdown = request.planReview?.markdown else {
            planRenderingState.invalidate()
            return
        }

        let requestID = request.id
        let operationID = planRenderingState.begin(requestID: requestID)
        let document = await PlanMarkdownRenderingExecutor.render(markdown)
        guard !Task.isCancelled else { return }
        planRenderingState.accept(
            document,
            requestID: requestID,
            operationID: operationID
        )
    }

    private var isPlanDecisionReady: Bool {
        planRenderingState.document?.isReadyForDecision == true
    }

    @ViewBuilder
    private var permissionContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(request.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.warmWhite.opacity(usesIncreasedContrast ? 1 : 0.94))
                .lineLimit(1)

            Text(request.message)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(Palette.textSecondary.opacity(usesIncreasedContrast ? 1 : 0.9))
                .fixedSize(horizontal: false, vertical: true)
        }

        if let detail = request.detail, !detail.isEmpty {
            Text(detail)
                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                .foregroundStyle(Palette.warmWhite.opacity(usesIncreasedContrast ? 0.9 : 0.72))
                .lineLimit(4)
                .truncationMode(.tail)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(usesIncreasedContrast ? 0.5 : 0.32))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            Color.white.opacity(usesIncreasedContrast ? 0.18 : 0.055),
                            lineWidth: usesIncreasedContrast ? 1 : 0.5
                        )
                }
        }

        HStack(spacing: 8) {
            queuedLabel
            Spacer(minLength: 8)

            Button(L10n.string("Deny", language: language)) { onDecision(.deny) }
                .buttonStyle(ActionDecisionButtonStyle(role: .secondary))
                .help(actionHelp("Deny this request", shortcut: "⌘D"))
                .accessibilityHint(
                    L10n.string("Denies this permission request", language: language)
                )
                .actionRequestKeyboardShortcut(
                    "d",
                    modifiers: [.command],
                    enabled: isKeyboardPrimary
                )

            Button(L10n.string("Allow once", language: language)) { onDecision(.allow) }
                .buttonStyle(ActionDecisionButtonStyle(role: .primary))
                .help(actionHelp("Allow this request once", shortcut: "⌘↩"))
                .accessibilityHint(
                    L10n.string(
                        "Allows this permission for this request only",
                        language: language
                    )
                )
                .actionRequestKeyboardShortcut(
                    .return,
                    modifiers: [.command],
                    enabled: isKeyboardPrimary
                )
        }
    }

    @ViewBuilder
    private var questionContent: some View {
        if let question = currentQuestion {
            VStack(alignment: .leading, spacing: 4) {
                Text(question.header)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.45)
                    .foregroundStyle(
                        Palette.stateWaiting.opacity(usesIncreasedContrast ? 1 : 0.9)
                    )
                    .textCase(.uppercase)

                Text(question.question)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.warmWhite.opacity(usesIncreasedContrast ? 1 : 0.94))
                    .fixedSize(horizontal: false, vertical: true)

                if question.allowsMultipleSelection {
                    Text(L10n.string("Select one or more", language: language))
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            VStack(spacing: 5) {
                ForEach(question.options) { option in
                    Button {
                        toggle(option: option, in: question)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: selectionSymbol(
                                selected: isSelected(option, in: question),
                                multiple: question.allowsMultipleSelection
                            ))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(
                                isSelected(option, in: question)
                                    ? Palette.stateWaiting
                                    : (usesIncreasedContrast
                                        ? Palette.textSecondary
                                        : Palette.textTertiary)
                            )
                            .frame(width: 13, height: 15)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(
                                        Palette.warmWhite.opacity(usesIncreasedContrast ? 1 : 0.9)
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if let description = option.description {
                                    Text(description)
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(
                                            usesIncreasedContrast
                                                ? Palette.textSecondary
                                                : Palette.textTertiary
                                        )
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .buttonStyle(QuestionOptionButtonStyle(
                        isSelected: isSelected(option, in: question)
                    ))
                    .accessibilityLabel(option.label)
                    .accessibilityValue(
                        L10n.string(
                            isSelected(option, in: question) ? "Selected" : "Not selected",
                            language: language
                        )
                    )
                    .accessibilityHint(
                        option.description
                            ?? L10n.string("Select this answer", language: language)
                    )
                    .accessibilitySelected(isSelected(option, in: question))
                }
            }

            HStack(spacing: 7) {
                queuedLabel

                Button(L10n.string("Continue in Claude", language: language)) {
                    onDeferToAgent()
                }
                    .buttonStyle(ActionDecisionButtonStyle(role: .secondary))
                    .help(actionHelp(
                        "Continue answering this question in Claude Code",
                        shortcut: "⌘O"
                    ))
                    .accessibilityLabel(
                        L10n.string("Continue answering in Claude Code", language: language)
                    )
                    .accessibilityHint(
                        L10n.string(
                            "Returns this question to Claude Code without answering it here",
                            language: language
                        )
                    )
                    .actionRequestKeyboardShortcut(
                        "o",
                        modifiers: [.command],
                        enabled: isKeyboardPrimary
                    )

                Spacer(minLength: 5)

                if questionDraft.currentIndex > 0 {
                    Button(L10n.string("Back", language: language)) {
                        if reduceMotion {
                            _ = questionDraft.goBack()
                        } else {
                            withAnimation(Motion.contentReveal) {
                                _ = questionDraft.goBack()
                            }
                        }
                    }
                    .buttonStyle(ActionDecisionButtonStyle(role: .secondary))
                    .accessibilityHint(
                        L10n.string("Returns to the previous question", language: language)
                    )
                }

                Button(
                    L10n.string(
                        isLastQuestion ? "Submit" : "Next",
                        language: language
                    )
                ) {
                    advanceOrSubmit()
                }
                .buttonStyle(ActionDecisionButtonStyle(role: .primary))
                .disabled(!hasSelection(for: question))
                .help(actionHelp(
                    isLastQuestion ? "Submit answers" : "Next question",
                    shortcut: "⌘↩"
                ))
                .accessibilityHint(
                    L10n.string(
                        isLastQuestion
                            ? "Submits all selected answers to Claude Code"
                            : "Moves to the next question",
                        language: language
                    )
                )
                .actionRequestKeyboardShortcut(
                    .return,
                    modifiers: [.command],
                    enabled: isKeyboardPrimary
                )
            }
        } else {
            Text(L10n.string(
                "This question cannot be rendered safely.",
                language: language
            ))
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)
            Button(L10n.string("Continue in Claude", language: language)) {
                onDeferToAgent()
            }
                .buttonStyle(ActionDecisionButtonStyle(role: .secondary))
                .help(actionHelp(
                    "Continue answering this question in Claude Code",
                    shortcut: "⌘O"
                ))
                .accessibilityLabel(
                    L10n.string("Continue answering in Claude Code", language: language)
                )
                .accessibilityHint(
                    L10n.string(
                        "Returns this question to Claude Code because it cannot be rendered safely here",
                        language: language
                    )
                )
                .actionRequestKeyboardShortcut(
                    "o",
                    modifiers: [.command],
                    enabled: isKeyboardPrimary
                )
        }
    }

    @ViewBuilder
    private var queuedLabel: some View {
        if additionalQueuedCount > 0 {
            Text(L10n.format(
                "+%lld queued",
                language: language,
                Int64(additionalQueuedCount)
            ))
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.textTertiary)
                .monospacedDigit()
                .accessibilityLabel(
                    L10n.format(
                        "%lld more requests queued for this session",
                        language: language,
                        Int64(additionalQueuedCount)
                    )
                )
        }
    }

    @ViewBuilder
    private var header: some View {
        if let now {
            header(at: now)
        } else {
            TimelineView(
                .animation(minimumInterval: 1.0, paused: !isLive)
            ) { context in
                header(at: context.date)
            }
        }
    }

    private func header(at referenceDate: Date) -> some View {
        let expiresIn = PanelClockPresentation.requestCountdown(
            expiresAt: request.expiresAt,
            at: referenceDate
        )
        return HStack(spacing: 7) {
            DotMatrixMark(
                color: Palette.stateWaiting,
                size: 9,
                phase: 0.7,
                motion: .attention,
                pattern: .ring,
                intensity: 1
            )

            Text(headerLabel)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Palette.stateWaiting.opacity(0.96))

            Text("·")
                .font(.system(size: 9))
                .foregroundStyle(Palette.textTertiary.opacity(0.7))

            Text(agentAndSession)
                .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                .foregroundStyle(
                    usesIncreasedContrast ? Palette.textSecondary : Palette.textTertiary
                )
                .lineLimit(1)

            Spacer(minLength: 6)

            Text(expiresIn)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(
                    usesIncreasedContrast ? Palette.textSecondary : Palette.textTertiary
                )
                .monospacedDigit()
                .accessibilityLabel(
                    L10n.format("Expires in %@", language: language, expiresIn)
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.format(
                "%@, %@, expires in %@",
                language: language,
                headerLabel,
                agentAndSession,
                expiresIn
            )
        )
    }

    private var accessibilityLabel: String {
        if let contextTitle, !contextTitle.isEmpty {
            return L10n.format(
                "%@ for %@, %@",
                language: language,
                headerLabel,
                agentAndSession,
                contextTitle
            )
        }
        return L10n.format(
            "%@ for %@",
            language: language,
            headerLabel,
            agentAndSession
        )
    }

    private var usesIncreasedContrast: Bool {
        InterfaceContrastPolicy.usesIncreasedContrast(accessibilityContrast)
    }

    private var accessibilityHint: String {
        guard isKeyboardPrimary else {
            return L10n.string(
                "Use Tab to move through this request. Keyboard shortcuts are reserved for the oldest pending request.",
                language: language
            )
        }

        let key: String
        switch request.kind {
        case .permission:
            key = "Oldest pending request. Command Return allows once and Command D denies. Escape only closes Dev Island."
        case .planReview:
            key = "Oldest pending request. Command Return approves, Command D rejects, and Command O continues in Claude Code. Escape only closes Dev Island."
        case .question:
            key = "Oldest pending request. Command Return advances or submits after an answer is selected, and Command O continues in Claude Code. Escape only closes Dev Island."
        }
        return L10n.string(key, language: language)
    }

    private func actionHelp(_ message: String, shortcut: String) -> String {
        let localizedMessage = L10n.string(message, language: language)
        return isKeyboardPrimary ? "\(localizedMessage) (\(shortcut))" : localizedMessage
    }

    private var headerLabel: String {
        switch request.kind {
        case .permission:
            return L10n.string("APPROVAL", language: language)
        case .planReview:
            return L10n.string("PLAN REVIEW", language: language)
        case .question:
            guard !request.questions.isEmpty else {
                return L10n.string("QUESTION", language: language)
            }
            return L10n.format(
                "QUESTION %lld/%lld",
                language: language,
                Int64(min(questionDraft.currentIndex + 1, request.questions.count)),
                Int64(request.questions.count)
            )
        }
    }

    private var currentQuestion: AgentQuestion? {
        questionDraft.currentQuestion
    }

    private var isLastQuestion: Bool {
        questionDraft.isLastQuestion
    }

    private func hasSelection(for question: AgentQuestion) -> Bool {
        questionDraft.hasSelection(for: question)
    }

    private func isSelected(
        _ option: AgentQuestionOption,
        in question: AgentQuestion
    ) -> Bool {
        questionDraft.isSelected(option, in: question)
    }

    private func toggle(option: AgentQuestionOption, in question: AgentQuestion) {
        questionDraft.toggle(option, in: question)
    }

    private func selectionSymbol(selected: Bool, multiple: Bool) -> String {
        if multiple {
            return selected ? "checkmark.square.fill" : "square"
        }
        return selected ? "circle.inset.filled" : "circle"
    }

    private func advanceOrSubmit() {
        let outcome: QuestionAnswerDraft.Outcome
        if reduceMotion {
            outcome = questionDraft.advanceOrSubmit()
        } else {
            outcome = withAnimation(Motion.contentReveal) {
                questionDraft.advanceOrSubmit()
            }
        }

        if case let .submit(answers) = outcome {
            onAnswer(answers)
        }
    }

    private var agentAndSession: String {
        let agent = LocalAgentRegistry.descriptor(for: request.source)?.displayName
            ?? request.source.capitalized
        let reference = ActionRequestPresentationPolicy.sessionReference(
            for: request.sessionId,
            language: language
        )
        return "\(agent) · \(reference)"
    }

}

private extension View {
    @ViewBuilder
    func actionRequestKeyboardShortcut(
        _ key: KeyEquivalent,
        modifiers: EventModifiers,
        enabled: Bool
    ) -> some View {
        if enabled {
            keyboardShortcut(key, modifiers: modifiers)
        } else {
            self
        }
    }

    @ViewBuilder
    func accessibilitySelected(_ selected: Bool) -> some View {
        if selected {
            accessibilityAddTraits(.isSelected)
        } else {
            self
        }
    }
}

private struct PlanMarkdownView: View {
    let document: PlanMarkdownDocument

    @Environment(\.colorSchemeContrast) private var accessibilityContrast

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(document.blocks.enumerated()), id: \.offset) { item in
                blockView(item.element)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: PlanMarkdownRenderedBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(headingFont(level: level))
                .foregroundStyle(Palette.warmWhite.opacity(usesIncreasedContrast ? 1 : 0.94))
                .fixedSize(horizontal: false, vertical: true)

        case .paragraph(let text):
            Text(text)
                .font(.system(size: 11.25, weight: .regular))
                .foregroundStyle(Palette.warmWhite.opacity(usesIncreasedContrast ? 0.96 : 0.82))
                .fixedSize(horizontal: false, vertical: true)

        case .unorderedListItem(let text):
            listRow(marker: "•", text: text)

        case .orderedListItem(let marker, let text):
            listRow(marker: marker, text: text)

        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.warmWhite.opacity(usesIncreasedContrast ? 0.94 : 0.76))
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
            }
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(usesIncreasedContrast ? 0.075 : 0.035))
            }
        }
    }

    private func listRow(marker: String, text: AttributedString) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(marker)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.stateWaiting.opacity(usesIncreasedContrast ? 1 : 0.84))
                .frame(width: 19, alignment: .trailing)

            Text(text)
                .font(.system(size: 11.25, weight: .regular))
                .foregroundStyle(Palette.warmWhite.opacity(usesIncreasedContrast ? 0.96 : 0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .system(size: 13.5, weight: .semibold)
        case 2: return .system(size: 13, weight: .semibold)
        default: return .system(size: 12, weight: .semibold)
        }
    }

    private var usesIncreasedContrast: Bool {
        InterfaceContrastPolicy.usesIncreasedContrast(accessibilityContrast)
    }
}

private struct ActionDecisionButtonStyle: ButtonStyle {
    enum Role { case primary, secondary }

    let role: Role

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var accessibilityContrast

    func makeBody(configuration: Configuration) -> some View {
        ActionDecisionButtonBody(
            configuration: configuration,
            role: role,
            isEnabled: isEnabled,
            reduceMotion: reduceMotion,
            increasedContrast: InterfaceContrastPolicy.usesIncreasedContrast(accessibilityContrast)
        )
    }
}

private struct ActionDecisionButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let role: ActionDecisionButtonStyle.Role
    let isEnabled: Bool
    let reduceMotion: Bool
    let increasedContrast: Bool

    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(foreground.opacity(configuration.isPressed ? 0.72 : 1))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(background.opacity(configuration.isPressed ? 0.78 : 1))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(border, lineWidth: increasedContrast ? 1 : 0.6)
            }
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .opacity(isEnabled ? 1 : 0.38)
            .animation(Motion.press, value: configuration.isPressed)
            .animation(
                Motion.respectingReducedMotion(
                    reduceMotion,
                    preferred: Motion.hover
                ),
                value: isHovering
            )
            .contentShape(Rectangle())
            .onHover { isHovering = isEnabled && $0 }
            .pointingHandCursor(enabled: isEnabled)
    }

    private var foreground: Color {
        switch role {
        case .primary:
            return Palette.islandTop
        case .secondary:
            return Palette.warmWhite.opacity(
                increasedContrast ? 1 : (isHovering ? 0.9 : 0.76)
            )
        }
    }

    private var background: Color {
        switch role {
        case .primary:
            return isHovering ? Color.white.opacity(0.98) : Palette.warmWhite.opacity(0.92)
        case .secondary:
            return Color.white.opacity(
                increasedContrast ? (isHovering ? 0.14 : 0.1) : (isHovering ? 0.075 : 0.045)
            )
        }
    }

    private var border: Color {
        switch role {
        case .primary: return Color.clear
        case .secondary:
            return Color.white.opacity(
                increasedContrast ? (isHovering ? 0.34 : 0.24) : (isHovering ? 0.16 : 0.09)
            )
        }
    }
}

private struct QuestionOptionButtonStyle: ButtonStyle {
    let isSelected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var accessibilityContrast

    func makeBody(configuration: Configuration) -> some View {
        QuestionOptionButtonBody(
            configuration: configuration,
            isSelected: isSelected,
            reduceMotion: reduceMotion,
            increasedContrast: InterfaceContrastPolicy.usesIncreasedContrast(accessibilityContrast)
        )
    }
}

private struct QuestionOptionButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let isSelected: Bool
    let reduceMotion: Bool
    let increasedContrast: Bool

    @State private var isHovering = false

    var body: some View {
        configuration.label
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isSelected
                            ? Palette.stateWaiting.opacity(
                                increasedContrast
                                    ? (configuration.isPressed ? 0.22 : (isHovering ? 0.19 : 0.16))
                                    : (configuration.isPressed ? 0.14 : (isHovering ? 0.12 : 0.085))
                            )
                            : Color.white.opacity(
                                increasedContrast
                                    ? (configuration.isPressed ? 0.12 : (isHovering ? 0.1 : 0.07))
                                    : (configuration.isPressed ? 0.065 : (isHovering ? 0.055 : 0.032))
                            )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        isSelected
                            ? Palette.stateWaiting.opacity(
                                increasedContrast ? (isHovering ? 0.72 : 0.62) : (isHovering ? 0.48 : 0.34)
                            )
                            : Color.white.opacity(
                                increasedContrast ? (isHovering ? 0.3 : 0.22) : (isHovering ? 0.13 : 0.065)
                            ),
                        lineWidth: increasedContrast ? 1 : 0.6
                    )
            }
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.992 : 1))
            .animation(Motion.press, value: configuration.isPressed)
            .animation(
                Motion.respectingReducedMotion(
                    reduceMotion,
                    preferred: Motion.hover
                ),
                value: isHovering
            )
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .pointingHandCursor()
    }
}
