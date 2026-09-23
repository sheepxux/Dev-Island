import AppKit
import SwiftUI

/// The full-screen Welcome (2026-09-23): a scrim over the user's desktop with
/// the real island and menu bar left untouched above it. Three coaching
/// steps point at the real island, its open panel and the menu-bar item;
/// then the setup card (`OnboardingView`) takes over on the same canvas, so
/// the first live signal lights up the island the user has just been shown.
///
/// The tour window sits below the menu bar and the island, so nothing drawn
/// inside the menu-bar band is visible: pointers end at its lower edge, and
/// the spotlight only matters once the panel reaches below it.
struct WelcomeTutorialCanvas: View {
    let anchors: WelcomeTutorialAnchors
    let onFinish: (_ requestsNotificationAuthorization: Bool) -> Void

    @State private var phase: Phase = .coach(.island)
    @State private var cardSize: CGSize = .zero
    @State private var coordinator = IslandCoordinator.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.devIslandLanguage) private var language

    enum CoachStep: Int, CaseIterable, Equatable {
        case island
        case panel
        case menuBar
    }

    enum Phase: Equatable {
        case coach(CoachStep)
        case setup(initialStep: Int)
    }

    /// Coaching steps precede the setup card's four; both tracks count to
    /// the same total so the tour reads as one.
    static let coachStepCount = CoachStep.allCases.count
    static let totalStepCount = coachStepCount + 4

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
                scrim(spotlight: showsSpotlight ? placement.spotlight : nil)
                    .ignoresSafeArea()

                if let connector = placement.connector {
                    connectorPath(connector)
                }
                if showsSpotlight, let spotlight = placement.spotlight {
                    RoundedRectangle(
                        cornerRadius: WelcomeTutorialLayout.spotlightCornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(Palette.Window.canvas.opacity(0.9), lineWidth: 1.5)
                    .frame(width: spotlight.width, height: spotlight.height)
                    .offset(x: spotlight.minX, y: spotlight.minY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }

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
        .onChange(of: coordinator.mode) { _, mode in
            // Opening the island by hand is the first step's own action.
            if phase == .coach(.island), mode == .expanded {
                move(to: .coach(.panel), islandMode: nil)
            }
        }
    }

    // MARK: - Targets

    private var showsSpotlight: Bool {
        switch phase {
        case .coach(.island), .coach(.panel): return true
        case .coach(.menuBar), .setup: return false
        }
    }

    private func targetRect(in canvas: CGRect) -> CGRect? {
        let screenRect: CGRect?
        switch phase {
        case .coach(.island), .coach(.panel):
            screenRect = anchors.islandRect
        case .coach(.menuBar):
            screenRect = anchors.statusItemRect
        case .setup:
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

    // MARK: - Scrim

    private func scrim(spotlight: CGRect?) -> some View {
        Rectangle()
            .fill(Palette.Window.scrim)
            .overlay {
                if let spotlight {
                    RoundedRectangle(
                        cornerRadius: WelcomeTutorialLayout.spotlightCornerRadius,
                        style: .continuous
                    )
                    .frame(width: spotlight.width, height: spotlight.height)
                    .offset(x: spotlight.minX, y: spotlight.minY)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .blendMode(.destinationOut)
                }
            }
            .compositingGroup()
            .animation(reduceMotion ? nil : Motion.tourStep, value: spotlight)
            .accessibilityHidden(true)
    }

    private func connectorPath(_ connector: WelcomeTutorialLayout.Connector) -> some View {
        Path { path in
            path.move(to: connector.start)
            path.addLine(to: connector.end)
        }
        .stroke(Palette.Window.canvas.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(Palette.Window.canvas)
                .frame(width: 7, height: 7)
                .offset(x: connector.start.x - 3.5, y: connector.start.y - 3.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Card

    @ViewBuilder
    private var card: some View {
        switch phase {
        case .coach(let step):
            coachCard(step)
        case .setup(let initialStep):
            OnboardingView(
                onFinish: onFinish,
                initialStep: initialStep,
                trackOffset: Self.coachStepCount,
                trackTotal: Self.totalStepCount
            )
        }
    }

    private func coachCard(_ step: CoachStep) -> some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Text(L10n.string(title(step), language: language))
                        .font(Typo.display)
                        .tracking(Typo.displayTracking)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(L10n.string(detail(step), language: language))
                        .font(Typo.lead)
                        .foregroundStyle(Palette.Window.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 430)
                }
                .frame(maxWidth: .infinity)

                Button {
                    advance(from: step)
                } label: {
                    Text(L10n.string(action(step), language: language))
                }
                .buttonStyle(.window(.primary, size: .large))
                .keyboardShortcut(.defaultAction)
            }
            .frame(width: OnboardingMetrics.columnWidth)
            .padding(.top, 18)
            .padding(.bottom, 30)

            footer(step)
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
        .id(step)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
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

    private func footer(_ step: CoachStep) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0..<Self.totalStepCount, id: \.self) { index in
                    Capsule()
                        .fill(index == step.rawValue ? Palette.Window.ink : Palette.Window.hairlineStrong)
                        .frame(width: index == step.rawValue ? 18 : 5, height: 5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                L10n.format(
                    "Step %lld of %lld",
                    language: language,
                    Int64(step.rawValue + 1),
                    Int64(Self.totalStepCount)
                )
            )

            Text(L10n.string(name(step), language: language))
                .font(Typo.callout)
                .foregroundStyle(Palette.Window.textSecondary)
                .padding(.leading, 4)

            Spacer()

            Button(L10n.string("Skip to setup", language: language)) {
                move(to: .setup(initialStep: 1), islandMode: .collapsed)
            }
            .buttonStyle(.window(.quiet))
        }
        .padding(.horizontal, OnboardingMetrics.contentHorizontalPadding)
        .frame(height: 56)
    }

    // MARK: - Copy

    private func name(_ step: CoachStep) -> String {
        switch step {
        case .island: return "Your island"
        case .panel: return "The panel"
        case .menuBar: return "The menu bar"
        }
    }

    private func title(_ step: CoachStep) -> String {
        switch step {
        case .island: return "This is your island."
        case .panel: return "Every session, in one place."
        case .menuBar: return "Always one click away."
        }
    }

    private func detail(_ step: CoachStep) -> String {
        switch step {
        case .island:
            return "It stays at the top of your screen. While an Agent works, its progress lives here; when it needs you, it speaks up. Click it to open."
        case .panel:
            return "Each row is a session. The clock opens your history, the gear opens Settings, and Esc or a click outside closes the panel."
        case .menuBar:
            return "The menu-bar item opens the island, Settings and this tour, and quits Dev Island."
        }
    }

    private func action(_ step: CoachStep) -> String {
        switch step {
        case .island: return "Open it for me"
        case .panel, .menuBar: return "Next"
        }
    }

    // MARK: - Navigation

    private func advance(from step: CoachStep) {
        switch step {
        case .island:
            // The mode change advances the tour (see onChange); a panel that
            // is somehow already open moves on at once.
            if coordinator.mode == .expanded {
                move(to: .coach(.panel), islandMode: nil)
            } else {
                coordinator.expand()
            }
        case .panel:
            move(to: .coach(.menuBar), islandMode: .collapsed)
        case .menuBar:
            move(to: .setup(initialStep: 0), islandMode: .collapsed)
        }
    }

    private func move(to next: Phase, islandMode: IslandCoordinator.Mode?) {
        if islandMode == .collapsed, coordinator.mode == .expanded {
            coordinator.collapse()
        }
        withAnimation(reduceMotion ? nil : Motion.tourStep) {
            phase = next
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
