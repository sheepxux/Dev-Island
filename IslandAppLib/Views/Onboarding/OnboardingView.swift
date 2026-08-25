import IslandCore
import AppKit
import SwiftUI

enum OnboardingMetrics {
    static let width: CGFloat = 760
    static let height: CGFloat = 500
    static let windowRadius: CGFloat = 12
    static let stageWidth: CGFloat = 404
    static let stageHeight: CGFloat = 253
    static let stageRadius: CGFloat = 8
}

/// A three-step introduction built like a small editorial object rather than
/// a SaaS landing page: one typographic idea, one functional specimen, and no
/// decorative feature-card grid. Every page shares the same stable geometry
/// so moving through the tour feels like turning a page, not loading a screen.
struct OnboardingView: View {
    let onFinish: (_ requestsNotificationAuthorization: Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var direction = 1
    @State private var installedSources: Set<String> = []
    @State private var workingSources: Set<String> = []
    @State private var connectionErrors: [String: String] = [:]

    @AppStorage(TaskNotificationPreferences.attentionRequiredKey)
    private var attentionRequired = true
    @AppStorage(TaskNotificationPreferences.completionsKey)
    private var completions = false

    private let stepCount = 3

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                stepContent
                    .id(step)
                    .transition(stepTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            footer
        }
        .frame(width: OnboardingMetrics.width, height: OnboardingMetrics.height)
        .background(Palette.tourCanvas)
        .clipShape(
            RoundedRectangle(
                cornerRadius: OnboardingMetrics.windowRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: OnboardingMetrics.windowRadius,
                style: .continuous
            )
            .stroke(Palette.hairline, lineWidth: 0.75)
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: loadInstalledSources)
    }

    // MARK: - Window chrome

    private var header: some View {
        HStack(spacing: 11) {
            brandMark

            Text("Dev Island")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.warmWhite.opacity(0.88))

            Spacer()

            Text("Welcome")
                .font(Typo.tourLabel)
                .foregroundStyle(Palette.textTertiary)

            Rectangle()
                .fill(Palette.hairline)
                .frame(width: 1, height: 16)
                .padding(.horizontal, 3)

            Button {
                onFinish(false)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(pressedScale: 0.98))
            .keyboardShortcut(.cancelAction)
            .help("Close welcome tour")
            .accessibilityLabel("Close welcome tour")
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
        }
    }

    private var brandMark: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
    }

    // MARK: - Pages

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: overviewPage
        case 1: connectionsPage
        default: notificationsPage
        }
    }

    private var overviewPage: some View {
        editorialPage(
            number: "01 / 03",
            label: "Overview",
            title: "Know when\nyou’re needed.",
            detail: "Dev Island keeps agent work in sight, then gets out of the way until a session needs you.",
            note: "One quiet signal in the menu bar."
        ) {
            overviewStage
        }
    }

    private var connectionsPage: some View {
        editorialPage(
            number: "02 / 03",
            label: "Connections",
            title: "Bring your\nagents together.",
            detail: "Choose the local tools you use. Dev Island adds only the hooks it needs and leaves the rest of your setup intact.",
            note: "Local, inspectable, and reversible."
        ) {
            connectionsStage
        }
    }

    private var notificationsPage: some View {
        editorialPage(
            number: "03 / 03",
            label: "Attention",
            title: "Protect your\nfocus.",
            detail: "Choose what deserves an interruption. Dev Island stays quiet while work is moving and signals only at the moments you choose.",
            note: "Permission is requested only after you finish."
        ) {
            notificationsStage
        }
    }

    private func editorialPage<Stage: View>(
        number: String,
        label: String,
        title: String,
        detail: String,
        note: String,
        @ViewBuilder stage: () -> Stage
    ) -> some View {
        HStack(alignment: .top, spacing: 36) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Text(number)
                        .foregroundStyle(Palette.tourAccent)

                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(width: 22, height: 1)

                    Text(label)
                        .foregroundStyle(Palette.textSecondary)
                }
                .font(Typo.tourLabel)
                .padding(.bottom, 22)

                Text(title)
                    .font(Typo.tourDisplay)
                    .tracking(-0.7)
                    .foregroundStyle(Palette.warmWhite)
                    .lineSpacing(-2)

                Text(detail)
                    .font(Typo.tourBody)
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)

                Spacer(minLength: 18)

                HStack(alignment: .top, spacing: 9) {
                    Rectangle()
                        .fill(Palette.tourAccent)
                        .frame(width: 18, height: 1)
                        .padding(.top, 6)

                    Text(note)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.textTertiary)
                        .lineSpacing(2)
                }
            }
            .frame(width: 232)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            stage()
                .frame(
                    width: OnboardingMetrics.stageWidth,
                    height: OnboardingMetrics.stageHeight
                )
                .frame(maxHeight: .infinity, alignment: .center)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
    }

    // MARK: Overview specimen

    private var overviewStage: some View {
        VStack(spacing: 0) {
            stageHeader(title: "Current signal", trailing: "Live")

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)

            compactIslandPreview
                .padding(.horizontal, 18)
                .padding(.vertical, 17)

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)

            signalRow(title: "Running", detail: "3 sessions", state: .running)
            rowDivider
            signalRow(title: "Needs attention", detail: "None", state: .waiting)
            rowDivider
            signalRow(title: "Completed", detail: "2 today", state: .completed)
        }
        .background(stageSurface)
        .accessibilityElement(children: .contain)
    }

    private var compactIslandPreview: some View {
        HStack(spacing: 11) {
            staticSignal(.running, size: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text("Prepare release build")
                    .font(Typo.tourStageTitle)
                    .foregroundStyle(Palette.warmWhite.opacity(0.9))
                Text("Codex · Running tests")
                    .font(Typo.tourLabel)
                    .foregroundStyle(Palette.textTertiary)
            }

            Spacer()

            Text("04:12")
                .font(Typo.tourLabel)
                .foregroundStyle(Palette.textSecondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 17)
        .frame(height: 58)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 3,
                bottomLeadingRadius: 14,
                bottomTrailingRadius: 14,
                topTrailingRadius: 3,
                style: .continuous
            )
                .fill(Palette.notchBlack)
                .overlay {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 3,
                        bottomLeadingRadius: 14,
                        bottomTrailingRadius: 14,
                        topTrailingRadius: 3,
                        style: .continuous
                    )
                        .stroke(Palette.warmWhite.opacity(0.10), lineWidth: 0.75)
                }
        )
    }

    private func signalRow(title: String, detail: String, state: BarState) -> some View {
        HStack(spacing: 10) {
            staticSignal(state, size: 8)

            Text(title)
                .font(Typo.tourStageBody.weight(.medium))
                .foregroundStyle(Palette.warmWhite.opacity(0.78))

            Spacer()

            Text(detail)
                .font(Typo.tourLabel)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, 18)
        .frame(height: 37)
    }

    // MARK: Connection specimen

    private var connectionsStage: some View {
        VStack(spacing: 0) {
            stageHeader(
                title: "Local agents",
                trailing: "\(installedSources.count) connected"
            )

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)

            ForEach(Array(LocalAgentRegistry.all.enumerated()), id: \.element.source) { item in
                OnboardingAgentRow(
                    descriptor: item.element,
                    installed: installedSources.contains(item.element.source),
                    isWorking: workingSources.contains(item.element.source),
                    errorMessage: connectionErrors[item.element.source],
                    onEnable: { enable(item.element) }
                )

                if item.offset < LocalAgentRegistry.all.count - 1 {
                    rowDivider
                        .padding(.leading, 53)
                }
            }
        }
        .background(stageSurface)
    }

    // MARK: Notification specimen

    private var notificationsStage: some View {
        VStack(spacing: 0) {
            stageHeader(title: "Notifications", trailing: "Your choice")

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)

            notificationRow(
                title: "Needs input or failed",
                detail: "Recommended",
                state: .waiting,
                isOn: $attentionRequired
            )

            rowDivider
                .padding(.leading, 45)

            notificationRow(
                title: "Task completed",
                detail: "Off by default",
                state: .completed,
                isOn: $completions
            )

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)

            HStack(spacing: 9) {
                staticSignal(.waiting, size: 8)
                Text("Codex · Waiting for approval")
                    .font(Typo.tourStageBody)

                Spacer()

                Text("Needs input")
                    .font(Typo.tourLabel)
                    .foregroundStyle(Palette.stateWaiting)
            }
            .foregroundStyle(Palette.textTertiary)
            .padding(.horizontal, 16)
            .frame(height: 52, alignment: .leading)
        }
        .background(stageSurface)
    }

    private func notificationRow(
        title: String,
        detail: String,
        state: BarState,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                staticSignal(state, size: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Typo.tourStageTitle)
                        .foregroundStyle(Palette.warmWhite.opacity(0.82))
                    Text(detail)
                        .font(Typo.tourStageBody)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(Palette.warmWhite)
        .padding(.horizontal, 18)
        .frame(height: 76)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }

    private func staticSignal(_ state: BarState, size: CGFloat) -> some View {
        DotMatrixMark(
            color: state.color,
            size: size,
            pattern: state.matrixPattern,
            intensity: state.matrixIntensity
        )
    }

    private func stageHeader(title: String, trailing: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(Typo.tourStageTitle)
                .foregroundStyle(Palette.warmWhite.opacity(0.84))

            Spacer()

            Text(trailing)
                .font(Typo.tourLabel)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
    }

    private var stageSurface: some View {
        RoundedRectangle(cornerRadius: OnboardingMetrics.stageRadius, style: .continuous)
            .fill(Palette.tourPanel)
            .overlay {
                RoundedRectangle(cornerRadius: OnboardingMetrics.stageRadius, style: .continuous)
                    .stroke(Palette.hairline, lineWidth: 0.75)
            }
    }

    // MARK: - Navigation

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Set up later") {
                onFinish(false)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.textTertiary)

            Spacer()

            Button("Back") { move(to: step - 1) }
                .buttonStyle(TourSecondaryButtonStyle())
                .opacity(step > 0 ? 1 : 0)
                .allowsHitTesting(step > 0)
                .accessibilityHidden(step == 0)

            Button {
                if step == stepCount - 1 {
                    finishTour()
                } else {
                    move(to: step + 1)
                }
            } label: {
                Text(actionTitle)
            }
            .buttonStyle(TourPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
        }
    }

    private var actionTitle: String {
        step == stepCount - 1 ? "Start Dev Island" : "Continue"
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: CGFloat(direction * 10))),
            removal: .opacity.combined(with: .offset(x: CGFloat(direction * -6)))
        )
    }

    private func move(to newStep: Int) {
        guard (0..<stepCount).contains(newStep) else { return }
        direction = newStep > step ? 1 : -1
        withAnimation(
            Motion.respectingReducedMotion(reduceMotion, preferred: Motion.tourStep)
        ) {
            step = newStep
        }
    }

    private func finishTour() {
        // Authorization is requested by the window owner only after its exit
        // animation completes, so the system sheet never overlaps the tour.
        onFinish(true)
    }

    // MARK: - Local connections

    private func loadInstalledSources() {
        let descriptors = LocalAgentRegistry.all
        Task { @MainActor in
            let sources = await Task.detached(priority: .userInitiated) {
                Set(descriptors.compactMap { descriptor in
                    LocalHooksInstaller(descriptor).isInstalled() ? descriptor.source : nil
                })
            }.value
            installedSources = sources
        }
    }

    private func enable(_ descriptor: LocalAgentDescriptor) {
        guard !workingSources.contains(descriptor.source) else { return }
        let source = descriptor.source
        workingSources.insert(source)
        connectionErrors[source] = nil

        Task { @MainActor in
            let succeeded = await Task.detached(priority: .userInitiated) {
                do {
                    try LocalHooksInstaller(descriptor).install()
                    return true
                } catch {
                    return false
                }
            }.value

            workingSources.remove(source)
            withAnimation(
                Motion.respectingReducedMotion(reduceMotion, preferred: Motion.contentReveal)
            ) {
                if succeeded {
                    installedSources.insert(source)
                    connectionErrors[source] = nil
                } else {
                    connectionErrors[source] = "Could not update this agent’s configuration."
                }
            }
        }
    }
}

// MARK: - Agent connection row

private struct OnboardingAgentRow: View {
    let descriptor: LocalAgentDescriptor
    let installed: Bool
    let isWorking: Bool
    let errorMessage: String?
    let onEnable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 11) {
                AgentLogoBadge(source: descriptor.source, size: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text(descriptor.displayName)
                        .font(Typo.tourStageTitle)
                        .foregroundStyle(Palette.warmWhite.opacity(0.84))
                    Text(installed ? "Connected" : "Not connected")
                        .font(Typo.tourStageBody)
                        .foregroundStyle(
                            installed ? Palette.stateCompleted : Palette.textTertiary
                        )
                }

                Spacer()

                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 70)
                } else if installed {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("Ready")
                            .font(Typo.tourLabel)
                    }
                    .foregroundStyle(Palette.stateCompleted)
                    .frame(width: 70, height: 28)
                    .accessibilityLabel("Connected")
                } else {
                    Button("Connect", action: onEnable)
                        .buttonStyle(AgentConnectButtonStyle())
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.stateFailed)
                    .padding(.leading, 37)
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, errorMessage == nil ? 9 : 7)
        .frame(height: 68, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AgentConnectButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Palette.warmWhite.opacity(configuration.isPressed ? 0.5 : 0.72))
            .frame(width: 70, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Palette.warmWhite.opacity(configuration.isPressed ? 0.035 : 0.02))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 0.75)
                    }
            )
            .scaleEffect(configuration.isPressed ? 0.995 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

#if PREVIEWS
#Preview("Welcome Tour") {
    OnboardingView(onFinish: { _ in })
}
#endif
