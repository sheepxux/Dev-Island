import AppKit
import SwiftUI

/// The full-screen Welcome (2026-09-23; stage redesigned 2026-09-24): a
/// see-through wash over the user's desktop, from the menu bar's lower edge
/// down, with the real island and the native menu bar untouched above it.
/// Whatever the tour talks about sits on one charcoal plate that hangs from
/// the band; a stem in the plate's own colour drops to a paper caption card,
/// and one light pulse travels it on the island's own clock. The tour coaches
/// the real island — three example sessions, then an approval and a question
/// the user answers on the island itself, supplied through
/// `IslandCoordinator.tutorialDemo` and rendered by the same views a real
/// request uses — and the setup steps follow as the same card on the same
/// stage, so the first live signal lights up the island the user was just
/// shown. Nothing here writes configuration or reaches an Agent.
///
/// The tour window stops at the menu bar's lower edge (macOS 26 shows what
/// a window paints under its transparent menu bar, and a light wash there
/// erased the menu-bar icons), so nothing is ever painted inside the band:
/// the collapsed island and the menu-bar item are pointed at from below by
/// a shelf, and the plate wraps the panel only once it reaches below.
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

        /// The steps that point at something on screen.
        var hasTarget: Bool {
            switch self {
            case .island, .panel, .request, .menuBar, .firstSignal: return true
            case .connect, .reminders: return false
            }
        }
    }

    static let totalStepCount = Step.allCases.count

    /// How long the island's own "Allowed once" / "Answers sent" receipt
    /// plays before the next example beat arrives.
    static let beatHandoffDelay: Duration = .milliseconds(1_300)
    /// The entrance: the plate drops shortly after the window fades in, the
    /// stem draws and the words land once the plate has settled.
    static let plateDropDelay: Duration = .milliseconds(60)
    static let stemDrawDelay: Duration = .milliseconds(300)

    /// The card's vertical rhythm, on a 4pt grid.
    private enum CardRhythm {
        static let topToEyebrow: CGFloat = 32
        static let eyebrowToContent: CGFloat = 14
        static let contentToFooter: CGFloat = 28
        static let footerHeight: CGFloat = 20
        static let footerToBottom: CGFloat = 24
        static let closeInset: CGFloat = 14
        /// A one- or two-line lead makes the same card on the coaching
        /// steps: title, gap, two lines, gap, action.
        static let coachMinHeight: CGFloat = 152
        static let actionSlotHeight: CGFloat = 40
    }

    @State private var step: Step = .island
    @State private var cardSize: CGSize = .zero
    @State private var coordinator = IslandCoordinator.shared
    @State private var revealed = false
    @State private var beatHandoffID = UUID()
    /// The curve the plate moves on, chosen by what caused the change: the
    /// island's own morph, a step change, or a retreat into the band.
    @State private var plateAnimation: Animation = Motion.tourStep
    @State private var plateDropped = false
    @State private var stemDrawn = false
    @State private var loopsSettled = false
    @State private var settleID = UUID()
    @State private var entranceID = UUID()
    /// The plate the tour last showed, so it can retreat in place.
    @State private var lastPlate: WelcomeTutorialLayout.Plate?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.devIslandLanguage) private var language

    private var demoBeat: IslandTutorialDemo.Beat? { coordinator.tutorialDemo?.beat }

    private var isLive: Bool { loopsSettled && !reduceMotion }

    var body: some View {
        GeometryReader { proxy in
            let canvas = CGRect(origin: .zero, size: proxy.size)
            let target = targetRect(in: canvas)
            let placement = WelcomeTutorialLayout.placement(
                target: target,
                cardSize: cardSize,
                canvas: canvas
            )
            let presented = presentedPlate(placement.plate, canvas: canvas)

            ZStack(alignment: .topLeading) {
                stage

                plate(presented.plate, visible: presented.visible)

                stem(placement.connector)

                card
                    .background(
                        GeometryReader { cardProxy in
                            Color.clear.preference(key: CardSizeKey.self, value: cardProxy.size)
                        }
                    )
                    .offset(x: placement.card.minX, y: placement.card.minY)
                    // One composition, one curve: the card moves on whatever
                    // the plate and stem move on (the step curve, the
                    // retreat, or the island's own morph).
                    .animation(reduceMotion ? nil : plateAnimation, value: placement.card)
            }
            .onPreferenceChange(CardSizeKey.self) { size in
                guard size != cardSize else { return }
                cardSize = size
            }
            .onChange(of: placement.plate) { _, plate in
                if let plate { lastPlate = plate }
            }
        }
        .foregroundStyle(Palette.Window.ink)
        .tint(Palette.Window.ink)
        .preferredColorScheme(.light)
        .onAppear {
            coordinator.beginTutorialDemo(WelcomeDemoContent.demo(beat: .working, language: language))
            enter()
        }
        .onDisappear {
            loopsSettled = false
            coordinator.endTutorialDemo()
        }
        .onChange(of: coordinator.mode) { _, mode in
            // The plate follows the island on the island's own curve.
            plateAnimation = Motion.islandMorph(expanding: mode == .expanded)
            settleLoops()
            // Opening the island by hand is the first step's own action.
            if step == .island, mode == .expanded {
                move(to: .panel, plateAnimation: Motion.islandMorph)
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
            screenRect = WelcomeTutorialLayout.usableTarget(anchors.islandRect, within: anchors.screenFrame)
        case .menuBar:
            // An item the menu bar moved into its overflow is not pointed at.
            let band = CGRect(
                x: anchors.screenFrame.minX,
                y: anchors.screenFrame.maxY - anchors.menuBarHeight,
                width: anchors.screenFrame.width,
                height: anchors.menuBarHeight
            )
            screenRect = WelcomeTutorialLayout.usableTarget(anchors.statusItemRect, within: band)
        case .connect, .reminders:
            screenRect = nil
        }
        guard let screenRect else { return nil }
        // The canvas starts at the menu bar's lower edge; a target that sits
        // inside the band (the collapsed island, the menu-bar item) becomes a
        // zero-height mark on the top edge that the shelf hangs from. The
        // collapsed island peeks a hover boost below the band while the
        // pointer is on it; that is still the band.
        let rect = WelcomeTutorialLayout.canvasRect(
            fromScreenRect: screenRect,
            screenFrame: anchors.stageFrame
        )
        guard rect.maxY > canvas.minY + WelcomeTutorialLayout.inBandTolerance else {
            return CGRect(x: rect.minX, y: canvas.minY, width: rect.width, height: 0)
        }
        return rect.intersection(canvas)
    }

    // MARK: - Stage

    /// The see-through wash: the one thing painted over the desktop.
    private var stage: some View {
        LinearGradient(
            colors: [Palette.Window.stage, Palette.Window.stageDeep],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The plate to draw right now: the placement's own once it has dropped,
    /// otherwise the same plate retracted to the band's lower edge, where it
    /// waits to drop from or retreats to.
    private func presentedPlate(
        _ plate: WelcomeTutorialLayout.Plate?,
        canvas: CGRect
    ) -> (plate: WelcomeTutorialLayout.Plate, visible: Bool) {
        if let plate, plateDropped {
            return (plate, true)
        }
        let basis = plate ?? lastPlate ?? WelcomeTutorialLayout.Plate(
            rect: CGRect(
                x: canvas.midX - WelcomeTutorialLayout.shelfHeight,
                y: canvas.minY,
                width: WelcomeTutorialLayout.shelfHeight * 2,
                height: 0
            ),
            cornerRadius: WelcomeTutorialLayout.shelfCornerRadius
        )
        let retracted = WelcomeTutorialLayout.Plate(
            rect: CGRect(x: basis.rect.minX, y: canvas.minY, width: basis.rect.width, height: 0),
            cornerRadius: basis.cornerRadius
        )
        return (retracted, false)
    }

    /// The dark ground behind what the tour points at. Square top corners on
    /// the band's lower edge, so it reads as sliding out from under the menu
    /// bar; flat, with no ring or shadow.
    private func plate(_ plate: WelcomeTutorialLayout.Plate, visible: Bool) -> some View {
        // Geometry and opacity are keyed separately, opacity outermost: the
        // geometry's `nil` under Reduce Motion (nothing moves) must not
        // swallow the dissolve the plate still owes when it appears or
        // leaves.
        ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: plate.cornerRadius,
                bottomTrailingRadius: plate.cornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Palette.Window.stagePlate)
            .frame(width: max(plate.rect.width, 0), height: max(plate.rect.height, 0))
            .offset(x: plate.rect.minX, y: plate.rect.minY)
            // Geometry never moves under Reduce Motion, and a plate that is
            // still waiting to drop jumps to its new place unseen.
            .animation(reduceMotion || !plateDropped ? nil : plateAnimation, value: plate)
        }
        .opacity(visible ? 1 : 0)
        .animation(Motion.respectingReducedMotion(reduceMotion, preferred: plateAnimation), value: visible)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The stem from the plate to the card, in the plate's own colour, and
    /// the one pulse travelling it. Only the pulse's offset and opacity live
    /// inside the timeline.
    @ViewBuilder
    private func stem(_ connector: WelcomeTutorialLayout.Connector?) -> some View {
        if let connector {
            let length = max(connector.end.y - connector.start.y, 0)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Palette.Window.stagePlate)
                    .frame(
                        width: WelcomeTutorialLayout.stemWidth,
                        height: stemDrawn || reduceMotion ? length : 0
                    )
                    .offset(
                        x: connector.start.x - WelcomeTutorialLayout.stemWidth / 2,
                        y: connector.start.y
                    )
                    .animation(reduceMotion ? nil : Motion.guideDraw, value: stemDrawn)
                    .animation(reduceMotion ? nil : plateAnimation, value: connector)

                TimelineView(.animation(paused: !isLive)) { context in
                    let pulse = pulseState(at: context.date)
                    let point = WelcomeTutorialLayout.travelPoint(on: connector, phase: pulse.progress)

                    Capsule()
                        .fill(Palette.Window.stageSignal)
                        .frame(
                            width: WelcomeTutorialLayout.pulseWidth,
                            height: WelcomeTutorialLayout.pulseLength
                        )
                        .offset(
                            x: point.x - WelcomeTutorialLayout.pulseWidth / 2,
                            y: point.y - WelcomeTutorialLayout.pulseLength / 2
                        )
                        .opacity(pulse.opacity)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Where the pulse is on the island's clock: travelling while the stage
    /// is live, hidden while geometry settles, and a still pointer arrived
    /// at the card under Reduce Motion.
    private func pulseState(at date: Date) -> WelcomeTutorialLayout.Pulse {
        if reduceMotion {
            return WelcomeTutorialLayout.Pulse(progress: 1, opacity: 1)
        }
        guard isLive else {
            return WelcomeTutorialLayout.Pulse(progress: 0, opacity: 0)
        }
        let phase = Double(StatusPhase.cyclePhase(
            date.timeIntervalSinceReferenceDate,
            period: Motion.runningOrbitPeriod
        ))
        return WelcomeTutorialLayout.pulse(phase: phase)
    }

    // MARK: - Card

    /// A caption on paper: eyebrow, content, footer; a corner close. No
    /// header, no step name, no page-control pill.
    private var card: some View {
        VStack(spacing: 0) {
            eyebrow
                .padding(.top, CardRhythm.topToEyebrow)
                .padding(.bottom, CardRhythm.eyebrowToContent)
            content
            footer
                .padding(.top, CardRhythm.contentToFooter)
                .padding(.bottom, CardRhythm.footerToBottom)
        }
        .frame(width: OnboardingMetrics.width)
        .background(WindowCanvas())
        .clipShape(
            RoundedRectangle(cornerRadius: OnboardingMetrics.windowRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: OnboardingMetrics.windowRadius, style: .continuous)
                .strokeBorder(Palette.Window.ring, lineWidth: 0.75)
        }
        .overlay(alignment: .topTrailing) {
            closeButton
                .padding(CardRhythm.closeInset)
        }
        .shadow(color: Palette.Window.shadow.opacity(0.06), radius: 2, y: 1)
        .shadow(color: Palette.Window.shadow.opacity(0.14), radius: 32, y: 16)
    }

    private var eyebrow: some View {
        Text(L10n.string(step.showsExample ? "Example · showing on your island" : stepName, language: language))
            .font(Typo.calloutStrong)
            .foregroundStyle(Palette.Window.textTertiary)
            .frame(height: 16)
            .frame(maxWidth: .infinity)
            .animation(
                Motion.respectingReducedMotion(reduceMotion, preferred: Motion.colorTransition),
                value: step
            )
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
            .padding(.top, 6)
        } else {
            coachContent
                .id(step)
                .transition(.asymmetric(
                    insertion: .identity,
                    removal: .opacity.animation(Motion.tourExit)
                ))
        }
    }

    private var coachContent: some View {
        VStack(spacing: 0) {
            revealing(0) {
                Text(L10n.string(title, language: language))
                    .font(Typo.display)
                    .tracking(Typo.displayTracking)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }

            revealing(1) {
                Text(L10n.string(detail, language: language))
                    .font(Typo.lead)
                    .foregroundStyle(Palette.Window.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 430)
            }
            .padding(.top, 10)

            revealing(2) {
                coachAction
                    .frame(height: CardRhythm.actionSlotHeight)
            }
            .padding(.top, 28)
        }
        .frame(width: OnboardingMetrics.columnWidth, alignment: .top)
        .frame(minHeight: CardRhythm.coachMinHeight, alignment: .top)
        .padding(.horizontal, OnboardingMetrics.contentHorizontalPadding)
    }

    /// Lines of the card follow it in, one after the other.
    private func revealing<Content: View>(_ index: Int, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed || reduceMotion ? 0 : 6)
            .animation(
                Motion.respectingReducedMotion(
                    reduceMotion,
                    preferred: Motion.stagedReveal.delay(Double(index) * Motion.stagedRevealStep)
                ),
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
                primaryAction("Continue") { advance() }
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
            primaryAction("Start setup") { advance() }
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

    private var closeButton: some View {
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

    private var footer: some View {
        HStack(spacing: 10) {
            ledger

            Spacer()

            if step.showsExample {
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
        .frame(height: CardRhythm.footerHeight)
    }

    /// Seven equal marks reading progress: done, current, still to come.
    private var ledger: some View {
        HStack(spacing: 6) {
            ForEach(0..<Self.totalStepCount, id: \.self) { index in
                ledgerMark(for: index)
            }
        }
        .animation(
            Motion.respectingReducedMotion(reduceMotion, preferred: Motion.colorTransition),
            value: step
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.format(
                "Step %lld of %lld",
                language: language,
                Int64(step.rawValue + 1),
                Int64(Self.totalStepCount)
            ) + " " + L10n.string(stepName, language: language)
        )
    }

    @ViewBuilder
    private func ledgerMark(for index: Int) -> some View {
        if index < step.rawValue {
            Circle().fill(Palette.Window.textTertiary).frame(width: 5, height: 5)
        } else if index == step.rawValue {
            Circle().fill(Palette.Window.ink).frame(width: 5, height: 5)
        } else {
            Circle().strokeBorder(Palette.Window.hairlineStrong, lineWidth: 1).frame(width: 5, height: 5)
        }
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

    /// Moves the tour to `next`. The plate retreats into the band when the
    /// step has nothing to point at, drops again when a target returns, and
    /// otherwise moves on the step curve unless the island's own morph is
    /// the cause.
    private func move(to next: Step, plateAnimation cause: Animation? = nil) {
        let plateReturns = !step.hasTarget && next.hasTarget
        prepareIsland(for: next)
        plateAnimation = cause ?? (next.hasTarget ? Motion.tourStep : Motion.tourRetract)
        if plateReturns {
            plateDropped = false
            stemDrawn = false
        }
        // The step change moves the card and reflows its content: geometry,
        // so it snaps under Reduce Motion; the words still fade in through
        // `revealing`, and the eyebrow and ledger carry their own dissolve.
        withAnimation(reduceMotion ? nil : Motion.tourStep) {
            step = next
        }
        settleLoops()
        reveal()
        guard plateReturns else { return }
        // The plate has moved to its new place unseen; now let it drop, and
        // once it has, draw the stem toward the card.
        let id = UUID()
        entranceID = id
        Task { @MainActor in
            await Task.yield()
            guard entranceID == id else { return }
            withAnimation(reduceMotion ? nil : Motion.tourStep) { plateDropped = true }
            try? await Task.sleep(for: .seconds(Motion.tourStepDuration))
            guard entranceID == id else { return }
            withAnimation(reduceMotion ? nil : Motion.guideDraw) { stemDrawn = true }
        }
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
            // the card's "Continue".
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

    // MARK: - Choreography

    /// First appearance: the window fades in with the wash and the empty
    /// card; the plate drops from the band; the stem draws toward the card
    /// as the words land; the pulse joins the island's clock once everything
    /// has settled. Under Reduce Motion everything is simply there.
    private func enter() {
        guard !reduceMotion else {
            plateDropped = true
            stemDrawn = true
            revealed = true
            loopsSettled = true
            return
        }
        let id = UUID()
        entranceID = id
        Task { @MainActor in
            try? await Task.sleep(for: Self.plateDropDelay)
            guard entranceID == id else { return }
            withAnimation(Motion.tourStep) { plateDropped = true }
            try? await Task.sleep(for: Self.stemDrawDelay - Self.plateDropDelay)
            guard entranceID == id else { return }
            withAnimation(Motion.guideDraw) { stemDrawn = true }
            reveal()
            settleLoops()
        }
    }

    /// Loops wait for the plate and card to settle after any geometry change.
    private func settleLoops() {
        loopsSettled = false
        let id = UUID()
        settleID = id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Motion.guideLoopDelay))
            guard settleID == id else { return }
            loopsSettled = true
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
