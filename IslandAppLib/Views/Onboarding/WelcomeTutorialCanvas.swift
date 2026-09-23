import AppKit
import SwiftUI

/// The full-screen Welcome (2026-09-23): a light wash over the user's desktop
/// with the real island and menu bar left untouched above it. The tour
/// coaches the real island — three example sessions, then an approval and a
/// question the user answers on the island itself, supplied through
/// `IslandCoordinator.tutorialDemo` and rendered by the same views a real
/// request uses — and the setup steps follow as cards on the same stage, so
/// the first live signal lights up the island the user was just shown.
/// Nothing here writes configuration or reaches an Agent.
///
/// The tour window sits below the menu bar and the island, so nothing drawn
/// inside the menu-bar band is visible: pointers end at its lower edge, and
/// the ring appears only once the panel reaches below it.
struct WelcomeTutorialCanvas: View {
    let anchors: WelcomeTutorialAnchors
    let onFinish: (_ requestsNotificationAuthorization: Bool) -> Void

    enum Step: Int, CaseIterable, Equatable {
        case island
        case panel
        case request
        case menuBar
        case connect
        case reminders
        case firstSignal

        var setupStep: OnboardingView.Step? {
            switch self {
            case .connect: return .connect
            case .reminders: return .reminders
            case .firstSignal: return .firstSignal
            case .island, .panel, .request, .menuBar: return nil
            }
        }

        /// The steps that show the example on the island.
        var showsExample: Bool {
            switch self {
            case .island, .panel, .request: return true
            case .menuBar, .connect, .reminders, .firstSignal: return false
            }
        }
    }

    static let totalStepCount = Step.allCases.count

    /// How long the island's own "Allowed once" / "Answers sent" receipt
    /// plays before the next example beat arrives.
    static let beatHandoffDelay: Duration = .milliseconds(1_300)

    @State private var step: Step = .island
    @State private var cardSize: CGSize = .zero
    @State private var coordinator = IslandCoordinator.shared
    @State private var revealed = false
    @State private var beatHandoffID = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.devIslandLanguage) private var language

    private var demoBeat: IslandTutorialDemo.Beat? { coordinator.tutorialDemo?.beat }

    var body: some View {
        GeometryReader { proxy in
            let canvas = CGRect(origin: .zero, size: proxy.size)
            let target = targetRect(in: canvas)
            let placement = WelcomeTutorialLayout.placement(
                target: target,
                cardSize: cardSize,
                canvas: canvas
            )

            ZStack(alignment: .topLeading) {
                stage(bloom: WelcomeTutorialLayout.bloomCenter(of: placement), canvas: canvas)

                guidance(placement, showsRing: (target?.height ?? 0) > 1)

                card
                    .background(
                        GeometryReader { cardProxy in
                            Color.clear.preference(key: CardSizeKey.self, value: cardProxy.size)
                        }
                    )
                    .offset(x: placement.card.minX, y: placement.card.minY)
                    .animation(reduceMotion ? nil : Motion.tourStep, value: placement.card)
            }
            .onPreferenceChange(CardSizeKey.self) { size in
                guard size != cardSize else { return }
                cardSize = size
            }
        }
        .foregroundStyle(Palette.Window.ink)
        .tint(Palette.Window.ink)
        .preferredColorScheme(.light)
        .onAppear {
            coordinator.beginTutorialDemo(WelcomeDemoContent.demo(beat: .working, language: language))
            reveal()
        }
        .onDisappear {
            coordinator.endTutorialDemo()
        }
        .onChange(of: coordinator.mode) { _, mode in
            // Opening the island by hand is the first step's own action.
            if step == .island, mode == .expanded {
                move(to: .panel)
            }
        }
        .onChange(of: coordinator.tutorialDemoResponse) { _, response in
            advanceExample(after: response)
        }
        .onChange(of: language) { _, _ in
            guard let demo = coordinator.tutorialDemo else { return }
            coordinator.updateTutorialDemo(WelcomeDemoContent.demo(beat: demo.beat, language: language))
        }
    }

    // MARK: - Targets

    private func targetRect(in canvas: CGRect) -> CGRect? {
        let screenRect: CGRect?
        switch step {
        case .island, .panel, .request, .firstSignal:
            screenRect = anchors.islandRect
        case .menuBar:
            screenRect = anchors.statusItemRect
        case .connect, .reminders:
            screenRect = nil
        }
        guard let screenRect, !screenRect.isEmpty else { return nil }
        let rect = WelcomeTutorialLayout.canvasRect(
            fromScreenRect: screenRect,
            screenFrame: anchors.screenFrame
        )
        // Nothing below the menu bar can point higher than its lower edge.
        let visibleTop = anchors.menuBarHeight
        guard rect.maxY > visibleTop else {
            return CGRect(x: rect.minX, y: visibleTop, width: rect.width, height: 0)
        }
        return rect.intersection(
            CGRect(x: canvas.minX, y: visibleTop, width: canvas.width, height: canvas.height)
        )
    }

    // MARK: - Stage

    /// The wash and its one bloom, which follows whatever the tour points at.
    private func stage(bloom: CGPoint, canvas: CGRect) -> some View {
        ZStack {
            LinearGradient(
                colors: [Palette.Window.stage, Palette.Window.stageDeep],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [
                    Palette.Window.stageBloom.opacity(0.95),
                    Palette.Window.stageBloom.opacity(0),
                ],
                center: UnitPoint(
                    x: bloom.x / max(canvas.width, 1),
                    y: bloom.y / max(canvas.height, 1)
                ),
                startRadius: 0,
                endRadius: 560
            )
            .animation(reduceMotion ? nil : Motion.tourStep, value: bloom)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// The breathing ring around the target and the point travelling the
    /// connector toward the card. One small mark moves; under Reduce Motion
    /// both rest.
    @ViewBuilder
    private func guidance(_ placement: WelcomeTutorialLayout.Placement, showsRing: Bool) -> some View {
        if let connector = placement.connector {
            TimelineView(.animation(paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let travel = reduceMotion
                    ? 0
                    : Double(StatusPhase.cyclePhase(t, period: Motion.guideTravelPeriod))
                let breath = reduceMotion
                    ? 1
                    : WelcomeTutorialLayout.breathOpacity(
                        phase: Double(StatusPhase.cyclePhase(t, period: Motion.guideBreathPeriod))
                    )
                let point = WelcomeTutorialLayout.travelPoint(on: connector, phase: travel)

                ZStack(alignment: .topLeading) {
                    Path { path in
                        path.move(to: connector.start)
                        path.addLine(to: connector.end)
                    }
                    .stroke(
                        Palette.Window.guide.opacity(0.45),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )

                    Circle()
                        .fill(Palette.Window.guide)
                        .frame(width: 7, height: 7)
                        .offset(x: point.x - 3.5, y: point.y - 3.5)

                    if showsRing, let spotlight = placement.spotlight {
                        RoundedRectangle(
                            cornerRadius: WelcomeTutorialLayout.spotlightCornerRadius,
                            style: .continuous
                        )
                        .strokeBorder(Palette.Window.guide, lineWidth: 1.5)
                        .frame(width: spotlight.width, height: spotlight.height)
                        .offset(x: spotlight.minX, y: spotlight.minY)
                        .opacity(breath)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        .frame(width: OnboardingMetrics.width)
        .background(WindowCanvas())
        .clipShape(
            RoundedRectangle(cornerRadius: OnboardingMetrics.windowRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: OnboardingMetrics.windowRadius, style: .continuous)
                .strokeBorder(Palette.Window.hairlineStrong, lineWidth: 0.75)
        }
        .shadow(color: Palette.Window.shadow.opacity(0.05), radius: 2, y: 1)
        .shadow(color: Palette.Window.shadow.opacity(0.10), radius: 28, y: 14)
    }

    @ViewBuilder
    private var content: some View {
        if let setupStep = step.setupStep {
            // One OnboardingView across the three setup steps so its
            // connection state survives; only its content changes.
            OnboardingView(
                step: setupStep,
                onContinue: { advance() },
                onFinish: onFinish
            )
            .padding(.top, 8)
            .padding(.bottom, 26)
        } else {
            coachContent
                .id(step)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
        }
    }

    private var coachContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                if step.showsExample {
                    revealing(0) {
                        Text(L10n.string("Example · showing on your island", language: language))
                            .font(Typo.caption.weight(.medium))
                            .foregroundStyle(Palette.Window.textTertiary)
                    }
                }

                revealing(1) {
                    Text(L10n.string(title, language: language))
                        .font(Typo.display)
                        .tracking(Typo.displayTracking)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }

                revealing(2) {
                    Text(L10n.string(detail, language: language))
                        .font(Typo.lead)
                        .foregroundStyle(Palette.Window.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 430)
                }
            }
            .frame(maxWidth: .infinity)

            revealing(3) {
                coachAction
            }
        }
        .frame(width: OnboardingMetrics.columnWidth)
        .padding(.top, 18)
        .padding(.bottom, 30)
    }

    /// Lines of the card follow it in, one after the other.
    private func revealing<Content: View>(_ index: Int, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed || reduceMotion ? 0 : 6)
            .animation(
                reduceMotion ? nil : Motion.stagedReveal.delay(Double(index) * Motion.stagedRevealStep),
                value: revealed
            )
    }

    @ViewBuilder
    private var coachAction: some View {
        switch step {
        case .island:
            primaryAction("Open it for me") { openIsland() }
        case .panel:
            primaryAction("Show me a request") { advance() }
        case .request:
            switch demoBeat {
            case .resumed:
                primaryAction("Next") { advance() }
            case .askingPermission, .askingQuestion, .working, nil:
                if coordinator.mode == .expanded {
                    Text(L10n.string(
                        demoBeat == .askingQuestion
                            ? "Choose an option on the island and submit."
                            : "Answer on the island: Allow once, or Deny.",
                        language: language
                    ))
                    .font(Typo.callout)
                    .foregroundStyle(Palette.Window.textSecondary)
                    .multilineTextAlignment(.center)
                } else {
                    // The island was folded (Esc, or a click outside); bring
                    // the example back rather than leaving the step stuck.
                    primaryAction("Open it for me") { openIsland() }
                }
            }
        case .menuBar:
            primaryAction("Next") { advance() }
        case .connect, .reminders, .firstSignal:
            EmptyView()
        }
    }

    private func primaryAction(_ key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(L10n.string(key, language: language))
        }
        .buttonStyle(.window(.primary, size: .large))
        .keyboardShortcut(.defaultAction)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)

            Text("Dev Island")
                .font(Typo.bodyStrong)
                .foregroundStyle(Palette.Window.ink)

            Spacer()

            Button {
                onFinish(false)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.Window.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle(pressedScale: 0.96))
            .pointingHandCursor()
            .keyboardShortcut(.cancelAction)
            .help(L10n.string("Close welcome tour", language: language))
            .accessibilityLabel(L10n.string("Close welcome tour", language: language))
        }
        .padding(.horizontal, OnboardingMetrics.contentHorizontalPadding - 8)
        .padding(.leading, 8)
        .frame(height: 56)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0..<Self.totalStepCount, id: \.self) { index in
                    Capsule()
                        .fill(index == step.rawValue ? Palette.Window.ink : Palette.Window.hairlineStrong)
                        .frame(width: index == step.rawValue ? 18 : 5, height: 5)
                }
            }
            .animation(reduceMotion ? nil : Motion.tourStep, value: step)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                L10n.format(
                    "Step %lld of %lld",
                    language: language,
                    Int64(step.rawValue + 1),
                    Int64(Self.totalStepCount)
                )
            )

            Text(L10n.string(stepName, language: language))
                .font(Typo.callout)
                .foregroundStyle(Palette.Window.textSecondary)
                .padding(.leading, 4)

            Spacer()

            if step.setupStep == nil {
                Button(L10n.string("Skip to setup", language: language)) {
                    move(to: .connect)
                }
                .buttonStyle(.window(.quiet))
            } else if let previous = Step(rawValue: step.rawValue - 1), previous.setupStep != nil {
                Button(L10n.string("Back", language: language)) {
                    move(to: previous)
                }
                .buttonStyle(.window(.quiet))
            }
        }
        .padding(.horizontal, OnboardingMetrics.contentHorizontalPadding)
        .frame(height: 56)
    }

    // MARK: - Copy

    private var stepName: String {
        switch step {
        case .island: return "Your island"
        case .panel: return "The panel"
        case .request: return "Your turn"
        case .menuBar: return "The menu bar"
        case .connect: return "Connect"
        case .reminders: return "Reminders"
        case .firstSignal: return "First signal"
        }
    }

    private var title: String {
        switch step {
        case .island: return "This is your island."
        case .panel: return "Every session, in one place."
        case .request:
            switch demoBeat {
            case .askingQuestion: return "Options show up there too."
            case .resumed: return "One answer, and it keeps going."
            case .askingPermission, .working, nil: return "When it needs you, it asks."
            }
        case .menuBar: return "Always one click away."
        case .connect, .reminders, .firstSignal: return ""
        }
    }

    private var detail: String {
        switch step {
        case .island:
            return "It stays at the top of your screen. While an Agent works, its progress lives here; when it needs you, it speaks up. Click it to open."
        case .panel:
            return "Each row is a session. The clock opens your history, the gear opens Settings, and Esc or a click outside closes the panel."
        case .request:
            switch demoBeat {
            case .askingQuestion: return "Pick one and submit; the session carries on."
            case .resumed: return "The island folds back and stays quiet until the next time you are needed."
            case .askingPermission, .working, nil: return "Answer it right on the island. No hunting through terminal windows."
            }
        case .menuBar:
            return "The menu-bar item opens the island, Settings and this tour, and quits Dev Island."
        case .connect, .reminders, .firstSignal:
            return ""
        }
    }

    // MARK: - Navigation

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        move(to: next)
    }

    private func move(to next: Step) {
        prepareIsland(for: next)
        withAnimation(reduceMotion ? nil : Motion.tourStep) {
            step = next
        }
        reveal()
    }

    /// Puts the real island in the state the step talks about.
    private func prepareIsland(for next: Step) {
        switch next {
        case .island:
            break
        case .panel:
            if coordinator.mode != .expanded {
                openIsland()
            }
        case .request:
            coordinator.updateTutorialDemo(WelcomeDemoContent.demo(beat: .askingPermission, language: language))
            openIsland()
        case .menuBar:
            coordinator.collapse()
        case .connect, .reminders, .firstSignal:
            // From here on the island shows only real sessions.
            coordinator.endTutorialDemo()
            if coordinator.mode == .expanded {
                coordinator.collapse()
            }
        }
    }

    /// A passive open on the example session: no focus is taken from the
    /// user's editor.
    private func openIsland() {
        coordinator.expand(highlighting: IslandTutorialDemo.primaryIdentity)
    }

    /// The island answered an example request. Take the request down at once
    /// so the island plays its own receipt, then bring the next beat.
    private func advanceExample(after response: IslandTutorialDemo.Response?) {
        guard step == .request,
              let response,
              let demo = coordinator.tutorialDemo,
              let next = demo.beat(after: response.event) else { return }

        let handoffID = UUID()
        beatHandoffID = handoffID
        coordinator.updateTutorialDemo(WelcomeDemoContent.demo(
            beat: next == .resumed ? .resumed : .working,
            language: language
        ))
        reveal()
        guard next != .resumed else {
            // Answering on the island keyed the island; give Return back to
            // the card's "Next".
            NSApp.windows.first { $0 is OnboardingWindow && $0.isVisible }?.makeKey()
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: Self.beatHandoffDelay)
            guard beatHandoffID == handoffID, step == .request,
                  coordinator.tutorialDemo != nil else { return }
            coordinator.updateTutorialDemo(WelcomeDemoContent.demo(beat: next, language: language))
            openIsland()
            reveal()
        }
    }

    private func reveal() {
        revealed = false
        DispatchQueue.main.async {
            withAnimation(reduceMotion ? nil : Motion.stagedReveal) {
                revealed = true
            }
        }
    }
}

/// Only the card reports a size; siblings contribute the zero default in
/// whatever order the stack reduces them, so keep the largest.
private struct CardSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: max(value.width, next.width), height: max(value.height, next.height))
    }
}
