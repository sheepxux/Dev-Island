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
    @State private var questionPageOpacity = 1.0
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
        let card = RoundedRectangle(cornerRadius: NotchMetrics.panelRowRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            header
                .opacity(request.kind == .question ? questionPageOpacity : 1)

            switch request.kind {
            case .permission:
                permissionContent
            case .question:
                questionContent
                    .opacity(questionPageOpacity)
            case .planReview:
                planReviewContent
            }
        }
        .padding(.horizontal, TaskCardMetrics.horizontalPadding)
        .padding(.top, 11)
        .padding(.bottom, 12)
        // The one thing in the panel that asks for something is raised off
        // it: a lighter step plus a ring, since shadows vanish on black.
        .background { card.fill(Palette.islandRaised) }
        .overlay {
            card.strokeBorder(
                Palette.hairline,
                lineWidth: InterfaceContrastPolicy.borderWidth(
                    increased: usesIncreasedContrast,
                    standard: 0.75
                )
            )
        }
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilitySortPriority(isKeyboardPrimary ? 100 : 0)
        .onChange(of: request.id) { _, _ in
            questionDraft = QuestionAnswerDraft(questions: request.questions)
            questionPageOpacity = 1
            planRenderingState.invalidate()
        }
        .task(id: request.id) { await renderPlanIfNeeded() }
        .onDisappear { planRenderingState.invalidate() }
    }

    @ViewBuilder
    private var planReviewContent: some View {
        if request.planReview != nil {
            VStack(alignment: .leading, spacing: 3) {
                Text(request.title)
                    .font(Typo.islandHeadline)
                    .foregroundStyle(Palette.warmWhite)

                Text(request.message)
                    .font(Typo.islandBody)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                if let document = planRenderingState.document {
                    if document.blocks.isEmpty {
                        Text(L10n.string(
                            "This plan cannot be rendered safely.",
                            language: language
                        ))
                            .font(Typo.islandMeta)
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
                            .font(Typo.islandMeta)
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
            .modifier(IslandWell(increasedContrast: usesIncreasedContrast))
            .accessibilityLabel(
                L10n.string("Claude Code plan", language: language)
            )

            queuedLabel

            HStack(spacing: 7) {
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

                Button { onDecision(.deny) } label: {
                    ActionDecisionLabel(
                        title: L10n.string("Reject", language: language),
                        shortcut: isKeyboardPrimary ? "⌘D" : nil
                    )
                }
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

                Button { onDecision(.allow) } label: {
                    ActionDecisionLabel(
                        title: L10n.string("Approve plan", language: language),
                        shortcut: isKeyboardPrimary ? "⌘↩" : nil,
                        isPrimary: true
                    )
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
                .font(Typo.islandMeta)
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
        VStack(alignment: .leading, spacing: 3) {
            Text(request.title)
                .font(Typo.islandHeadline)
                .foregroundStyle(Palette.warmWhite)
                .lineLimit(2)

            Text(request.message)
                .font(Typo.islandBody)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        // The command is what is being approved, so it is set at full
        // strength rather than as muted decoration.
        if let detail = request.detail, !detail.isEmpty {
            Text(detail)
                .font(Typo.islandCode)
                .foregroundStyle(Palette.warmWhite)
                .lineLimit(4)
                .truncationMode(.tail)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .modifier(IslandWell(increasedContrast: usesIncreasedContrast))
        }

        queuedLabel

        HStack(spacing: 8) {
            Spacer(minLength: 8)

            Button { onDecision(.deny) } label: {
                ActionDecisionLabel(
                    title: L10n.string("Deny", language: language),
                    shortcut: isKeyboardPrimary ? "⌘D" : nil
                )
            }
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

            Button { onDecision(.allow) } label: {
                ActionDecisionLabel(
                    title: L10n.string("Allow once", language: language),
                    shortcut: isKeyboardPrimary ? "⌘↩" : nil,
                    isPrimary: true
                )
            }
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
            VStack(alignment: .leading, spacing: 3) {
                // Amber already marks the card once, in its header.
                Text(question.header)
                    .font(Typo.islandLabel)
                    .foregroundStyle(Palette.textSecondary)

                Text(question.question)
                    .font(Typo.islandHeadline)
                    .foregroundStyle(Palette.warmWhite)
                    .fixedSize(horizontal: false, vertical: true)

                if question.allowsMultipleSelection {
                    Text(L10n.string("Select one or more", language: language))
                        .font(Typo.islandMeta)
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            VStack(spacing: 5) {
                ForEach(question.options) { option in
                    Button {
                        toggle(option: option, in: question)
                    } label: {
                        HStack(alignment: .top, spacing: 9) {
                            QuestionSelectionMark(
                                selected: isSelected(option, in: question),
                                allowsMultipleSelection: question.allowsMultipleSelection
                            )
                            .frame(width: 15, height: 16)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label)
                                    .font(Typo.islandBody.weight(.medium))
                                    .foregroundStyle(Palette.warmWhite)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if let description = option.description {
                                    Text(description)
                                        .font(Typo.islandMeta)
                                        .foregroundStyle(Palette.textSecondary)
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

            queuedLabel

            HStack(spacing: 7) {
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
                        goBackOneQuestion()
                    }
                    .buttonStyle(ActionDecisionButtonStyle(role: .secondary))
                    .accessibilityHint(
                        L10n.string("Returns to the previous question", language: language)
                    )
                }

                Button {
                    advanceOrSubmit()
                } label: {
                    ActionDecisionLabel(
                        title: L10n.string(
                            isLastQuestion ? "Submit" : "Next",
                            language: language
                        ),
                        shortcut: isKeyboardPrimary ? "⌘↩" : nil,
                        isPrimary: true
                    )
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
                .font(Typo.islandMeta)
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
                .font(Typo.islandNumeric)
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
        // One line when the whole context fits; otherwise the session title
        // takes its own line rather than shrinking to a few characters, so
        // two sessions of the same Agent stay distinguishable.
        return ViewThatFits(in: .horizontal) {
            headerLine(context: agentAndSession, expiresIn: expiresIn)
            VStack(alignment: .leading, spacing: 4) {
                headerLine(context: agentName, expiresIn: expiresIn)
                Text(sessionContext)
                    .font(Typo.islandMeta)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, TaskCardLeadingIdentityMetrics.statusSize + 9)
            }
        }
        .help(sessionContext)
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
        L10n.format(
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

    private func headerLine(context: String, expiresIn: String) -> some View {
        HStack(spacing: 6) {
            // Drawn at rest, at full strength: a frozen frame of the ripple
            // would show the waiting mark at its dimmest.
            DotMatrixMark(
                color: Palette.stateWaiting,
                size: TaskCardLeadingIdentityMetrics.statusSize,
                motion: .still,
                pattern: .ring,
                intensity: 1
            )
            .padding(.trailing, 3)

            Text(headerLabel)
                .font(Typo.islandLabel)
                .foregroundStyle(Palette.stateWaiting)
                .fixedSize()

            Text(verbatim: "·")
                .font(Typo.islandMeta)
                .foregroundStyle(Palette.textTertiary)

            Text(context)
                .font(Typo.islandMeta)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            Text(expiresIn)
                .font(Typo.islandNumeric)
                .foregroundStyle(Palette.textTertiary)
                .monospacedDigit()
                .fixedSize()
                .accessibilityLabel(
                    L10n.format("Expires in %@", language: language, expiresIn)
                )
        }
    }

    private func actionHelp(_ message: String, shortcut: String) -> String {
        let localizedMessage = L10n.string(message, language: language)
        return isKeyboardPrimary ? "\(localizedMessage) (\(shortcut))" : localizedMessage
    }

    private var headerLabel: String {
        switch request.kind {
        case .permission:
            return L10n.string("Approval", language: language)
        case .planReview:
            return L10n.string("Plan review", language: language)
        case .question:
            guard request.questions.count > 1 else {
                return L10n.string("Question", language: language)
            }
            return L10n.format(
                "Question %lld of %lld",
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

    private func advanceOrSubmit() {
        let outcome: QuestionAnswerDraft.Outcome
        if reduceMotion || isLastQuestion {
            outcome = questionDraft.advanceOrSubmit()
        } else {
            var nextOutcome: QuestionAnswerDraft.Outcome = .blocked
            var replacement = Transaction(animation: nil)
            replacement.disablesAnimations = true
            withTransaction(replacement) {
                questionPageOpacity = 0
                nextOutcome = questionDraft.advanceOrSubmit()
            }
            if nextOutcome == .advanced {
                withAnimation(Motion.questionPageReveal) {
                    questionPageOpacity = 1
                }
            } else {
                questionPageOpacity = 1
            }
            outcome = nextOutcome
        }

        if case let .submit(answers) = outcome {
            onAnswer(answers)
        }
    }

    private func goBackOneQuestion() {
        guard !reduceMotion else {
            _ = questionDraft.goBack()
            return
        }

        var didMove = false
        var replacement = Transaction(animation: nil)
        replacement.disablesAnimations = true
        withTransaction(replacement) {
            questionPageOpacity = 0
            didMove = questionDraft.goBack()
        }
        if didMove {
            withAnimation(Motion.questionPageReveal) {
                questionPageOpacity = 1
            }
        } else {
            questionPageOpacity = 1
        }
    }

    private var agentName: String {
        LocalAgentRegistry.descriptor(for: request.source)?.displayName
            ?? request.source.capitalized
    }

    /// The session in words the user already knows: its own title. A short
    /// fingerprint stands in only when the request's session row is not in
    /// the panel to borrow a title from.
    private var sessionContext: String {
        if let contextTitle, !contextTitle.isEmpty {
            return contextTitle
        }
        return ActionRequestPresentationPolicy.sessionReference(
            for: request.sessionId,
            language: language
        )
    }

    /// Who is asking: the Agent, then the session.
    private var agentAndSession: String {
        "\(agentName) · \(sessionContext)"
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
                .foregroundStyle(Palette.warmWhite)
                .fixedSize(horizontal: false, vertical: true)

        case .paragraph(let text):
            Text(text)
                .font(Typo.islandBody)
                .foregroundStyle(Palette.warmWhite)
                .fixedSize(horizontal: false, vertical: true)

        case .unorderedListItem(let text):
            listRow(marker: "•", text: text)

        case .orderedListItem(let marker, let text):
            listRow(marker: marker, text: text)

        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(Typo.islandCode)
                    .foregroundStyle(Palette.warmWhite)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
            }
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Palette.warmWhite.opacity(usesIncreasedContrast ? 0.075 : 0.035))
            }
        }
    }

    private func listRow(marker: String, text: AttributedString) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(marker)
                .font(Typo.islandNumeric)
                .foregroundStyle(Palette.stateWaiting)
                .frame(width: 19, alignment: .trailing)

            Text(text)
                .font(Typo.islandBody)
                .foregroundStyle(Palette.warmWhite)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func headingFont(level: Int) -> Font {
        level <= 2 ? Typo.islandHeadline : Typo.islandControl
    }

    private var usesIncreasedContrast: Bool {
        InterfaceContrastPolicy.usesIncreasedContrast(accessibilityContrast)
    }
}

/// A decision's title with its key equivalent printed beside it, so the
/// shortcut is discoverable without hovering for a tooltip. Only the oldest
/// pending request owns shortcuts, so only it shows them.
private struct ActionDecisionLabel: View {
    let title: String
    let shortcut: String?
    var isPrimary = false

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if let shortcut {
                Text(verbatim: shortcut)
                    .font(Typo.islandNumeric)
                    .foregroundStyle(isPrimary ? Palette.islandActionShortcut : Palette.textTertiary)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Sunken wells for commands and plan text inside a request card.
private struct IslandWell: ViewModifier {
    let increasedContrast: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: NotchMetrics.panelWellRadius, style: .continuous)
        content
            .background { shape.fill(Palette.islandWell) }
            .overlay {
                shape.strokeBorder(
                    Palette.hairline,
                    lineWidth: InterfaceContrastPolicy.borderWidth(
                        increased: increasedContrast,
                        standard: 0.75
                    )
                )
            }
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
        let capsule = Capsule()
        configuration.label
            .font(Typo.islandControl)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 13)
            .frame(height: 28)
            .background { capsule.fill(background) }
            .overlay { capsule.strokeBorder(border, lineWidth: increasedContrast ? 1 : 0.75) }
            .scaleEffect(
                InteractionFeedbackPolicy.pressScale(
                    isPressed: configuration.isPressed,
                    pressedScale: 0.96,
                    reduceMotion: reduceMotion
                )
            )
            .animation(Motion.press, value: configuration.isPressed)
            .animation(
                Motion.respectingReducedMotion(
                    reduceMotion,
                    preferred: Motion.hoverHighlight
                ),
                value: isHovering
            )
            .contentShape(capsule)
            .onHover { isHovering = isEnabled && $0 }
            .pointingHandCursor(enabled: isEnabled)
    }

    private var foreground: Color {
        guard isEnabled else { return Palette.textTertiary }
        switch role {
        case .primary:
            return Palette.islandTop
        case .secondary:
            return isHovering || configuration.isPressed || increasedContrast
                ? Palette.warmWhite
                : Palette.textSecondary
        }
    }

    private var background: Color {
        switch role {
        case .primary:
            guard isEnabled else { return Palette.warmWhite.opacity(0.10) }
            if configuration.isPressed { return Palette.islandActionPressed }
            return isHovering ? Palette.islandActionHover : Palette.warmWhite
        case .secondary:
            if configuration.isPressed { return Palette.warmWhite.opacity(0.12) }
            return Palette.warmWhite.opacity(isHovering ? 0.08 : (increasedContrast ? 0.06 : 0))
        }
    }

    private var border: Color {
        switch role {
        case .primary: return .clear
        case .secondary:
            return increasedContrast || isHovering ? Palette.hairline : .clear
        }
    }
}

/// One stable nine-point selection language for every question answer.
///
/// The geometry never changes when selection changes: two equal-sized grids
/// cross-fade in place. Single selection focuses inward; multiple selection
/// lights the centre and cardinals, keeping the two interaction models
/// distinguishable without falling back to generic radio/checkmark symbols.
enum QuestionSelectionPresentation {
    enum Tone: Equatable {
        case quiet
        case attention
    }

    struct Style: Equatable {
        let pattern: DotMatrixMark.Pattern
        let tone: Tone
        let intensity: Double
    }

    static func style(
        selected: Bool,
        allowsMultipleSelection: Bool
    ) -> Style {
        guard selected else {
            return Style(pattern: .field, tone: .quiet, intensity: 1)
        }
        return Style(
            pattern: allowsMultipleSelection ? .plus : .ring,
            tone: .attention,
            intensity: 1
        )
    }
}

struct QuestionSelectionMark: View {
    let selected: Bool
    let allowsMultipleSelection: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var accessibilityContrast

    var body: some View {
        let quiet = QuestionSelectionPresentation.style(
            selected: false,
            allowsMultipleSelection: allowsMultipleSelection
        )
        let active = QuestionSelectionPresentation.style(
            selected: true,
            allowsMultipleSelection: allowsMultipleSelection
        )

        ZStack {
            mark(for: quiet)
                .opacity(selected ? 0 : 1)
            mark(for: active)
                .opacity(selected ? 1 : 0)
        }
        .frame(width: 15, height: 15)
        .animation(reduceMotion ? nil : Motion.colorTransition, value: selected)
        .accessibilityHidden(true)
    }

    private func mark(
        for style: QuestionSelectionPresentation.Style
    ) -> some View {
        DotMatrixMark(
            color: color(for: style.tone),
            size: 15,
            pattern: style.pattern,
            intensity: style.intensity
        )
    }

    private func color(
        for tone: QuestionSelectionPresentation.Tone
    ) -> Color {
        switch tone {
        case .quiet:
            return InterfaceContrastPolicy.usesIncreasedContrast(accessibilityContrast)
                ? Palette.textSecondary
                : Palette.textTertiary
        case .attention:
            return Palette.stateWaiting
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
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? Palette.stateWaiting.opacity(
                                increasedContrast
                                    ? (configuration.isPressed ? 0.22 : (isHovering ? 0.19 : 0.16))
                                    : (configuration.isPressed ? 0.14 : (isHovering ? 0.12 : 0.085))
                            )
                            : Palette.warmWhite.opacity(
                                increasedContrast
                                    ? (configuration.isPressed ? 0.12 : (isHovering ? 0.1 : 0.07))
                                    : (configuration.isPressed ? 0.065 : (isHovering ? 0.055 : 0.032))
                            )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected
                            ? Palette.stateWaiting.opacity(
                                increasedContrast ? (isHovering ? 0.72 : 0.62) : (isHovering ? 0.48 : 0.34)
                            )
                            : Palette.warmWhite.opacity(
                                increasedContrast ? (isHovering ? 0.3 : 0.22) : (isHovering ? 0.13 : 0.065)
                            ),
                        lineWidth: increasedContrast ? 1 : 0.6
                    )
            }
            .scaleEffect(
                InteractionFeedbackPolicy.pressScale(
                    isPressed: configuration.isPressed,
                    pressedScale: 0.98,
                    reduceMotion: reduceMotion
                )
            )
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
