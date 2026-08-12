import IslandCore
import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var step = 0
    @AppStorage(TaskNotificationPreferences.attentionRequiredKey)
    private var attentionRequired = true
    @AppStorage(TaskNotificationPreferences.completionsKey)
    private var completions = false

    private let stepCount = 3

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case 0: welcomeStep.transition(stepTransition)
                case 1: connectionsStep.transition(stepTransition)
                default: notificationsStep.transition(stepTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 42)
            .padding(.top, 36)

            footer
        }
        .frame(width: 620, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black)
                    .frame(width: 286, height: 74)
                    .shadow(color: Color.blue.opacity(0.22), radius: 18)

                HStack(spacing: 14) {
                    Circle()
                        .fill(Palette.stateWaiting)
                        .frame(width: 12, height: 12)
                    Text("1")
                    Image(systemName: "pause.fill")
                        .foregroundStyle(Palette.stateWaiting)
                    Text("2")
                    Image(systemName: "play.fill")
                        .foregroundStyle(Palette.stateRunning)
                }
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
            }

            VStack(spacing: 9) {
                Text("Your AI agents, one island")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("See every active session at a glance—without keeping terminal windows in view.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
            }

            HStack(spacing: 22) {
                valuePoint("Detect blockers", symbol: "exclamationmark.bubble")
                valuePoint("Stay focused", symbol: "eye.slash")
                valuePoint("Jump back", symbol: "arrow.turn.down.right")
            }

            Spacer()
        }
    }

    private var connectionsStep: some View {
        VStack(spacing: 18) {
            VStack(spacing: 7) {
                Text("Connect your local agents")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Enable the tools you use. Dev Island only adds its own local hook entries and preserves the rest of each config file.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(LocalAgentRegistry.all, id: \.source) { descriptor in
                    OnboardingAgentRow(descriptor: descriptor)
                }
            }

            Text("You can change these connections anytime in Settings.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer(minLength: 0)
        }
    }

    private var notificationsStep: some View {
        VStack(spacing: 22) {
            VStack(spacing: 7) {
                Text("Come back only when it matters")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("A notification opens the island on the exact task. Click its card to return to the source app or terminal.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            VStack(spacing: 0) {
                onboardingNotificationToggle(
                    title: "Attention required",
                    subtitle: "Waiting for input and failures",
                    symbol: "bell.badge.fill",
                    tint: .orange,
                    isOn: $attentionRequired
                )

                Divider().padding(.leading, 58)

                onboardingNotificationToggle(
                    title: "Task completed",
                    subtitle: "Optional—off by default to reduce noise",
                    symbol: "checkmark.circle.fill",
                    tint: .green,
                    isOn: $completions
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            VStack(alignment: .leading, spacing: 12) {
                flowRow("1", "Agent needs you", color: Palette.stateWaiting)
                flowRow("2", "Click the notification to inspect it", color: .secondary)
                flowRow("3", "Click the card to jump back", color: Palette.stateRunning)
            }
            .frame(maxWidth: 390, alignment: .leading)

            Spacer(minLength: 0)
        }
        .onChange(of: attentionRequired) { _, enabled in
            if enabled { TaskNotifier.shared.refreshAuthorizationIfNeeded() }
        }
        .onChange(of: completions) { _, enabled in
            if enabled { TaskNotifier.shared.refreshAuthorizationIfNeeded() }
        }
    }

    private var footer: some View {
        VStack(spacing: 16) {
            HStack(spacing: 7) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: index == step ? 20 : 7, height: 7)
                        .animation(.easeOut(duration: 0.2), value: step)
                }
            }

            HStack {
                Button("Skip for now", action: onFinish)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Spacer()

                if step > 0 {
                    Button("Back") { move(to: step - 1) }
                }

                Button(step == stepCount - 1 ? "Start using Dev Island" : "Continue") {
                    if step == stepCount - 1 {
                        onFinish()
                    } else {
                        move(to: step + 1)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
    }

    private func move(to newStep: Int) {
        withAnimation(.easeInOut(duration: 0.28)) {
            step = newStep
        }
    }

    private func valuePoint(_ title: String, symbol: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.system(size: 12, weight: .medium))
        }
        .frame(width: 110)
    }

    private func onboardingNotificationToggle(
        title: String,
        subtitle: String,
        symbol: String,
        tint: Color,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .padding(16)
    }

    private func flowRow(_ number: String, _ text: String, color: Color) -> some View {
        HStack(spacing: 11) {
            Text(number)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(color))
            Text(text)
                .font(.system(size: 12, weight: .medium))
        }
    }
}

private struct OnboardingAgentRow: View {
    let descriptor: LocalAgentDescriptor

    @State private var installed = false
    @State private var errorMessage: String?

    private var installer: LocalHooksInstaller { .init(descriptor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                AgentLogoBadge(
                    source: descriptor.source,
                    size: 30,
                    ink: .primary,
                    badge: Color.primary.opacity(0.06)
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(installed ? "Ready for new sessions" : "Not enabled")
                        .font(.system(size: 10))
                        .foregroundStyle(installed ? Color.green : .secondary)
                }
                Spacer()
                Button(installed ? "Enabled" : "Enable") {
                    enable()
                }
                .disabled(installed)
                .controlSize(.small)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .onAppear { installed = installer.isInstalled() }
    }

    private func enable() {
        do {
            try installer.install()
            installed = true
            errorMessage = nil
        } catch {
            errorMessage = "Couldn’t update \(descriptor.configPath): \(error.localizedDescription)"
        }
    }
}

#if PREVIEWS
#Preview("Onboarding") {
    OnboardingView(onFinish: {})
}
#endif
