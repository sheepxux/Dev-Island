import IslandCore
import SwiftUI

/// The review is read-only until the user clicks the explicit authorization
/// button. Dismissal and loading never change vendor trust.
struct CodexHookAuthorizationSheet: View {
    let onAuthorized: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.devIslandLanguage) private var language
    @State private var review: CodexHookAuthorizationReview?
    @State private var isWorking = true
    @State private var errorMessage: String?
    @State private var copiedLauncher = false
    /// Resolved once off the main thread: locating the CLI validates the whole
    /// signed bundle, which must never run inside a button action.
    @State private var executableURL: URL?
    private let authorization = CodexHookAuthorization()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.string("Authorize Dev Island hooks", language: language))
                .font(Typo.title)
                .tracking(Typo.titleTracking)
                .accessibilityAddTraits(.isHeader)
            Text(L10n.string(
                "Allow Codex to run these Dev Island commands for task updates and approval requests on this Mac. Each tool request still follows your Codex approval settings.",
                language: language
            ))
                .font(Typo.callout)
                .foregroundStyle(Palette.Window.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.string(
                "Authorizing saves trust records for exactly these entries in your Codex configuration (config.toml). Nothing else is changed.",
                language: language
            ))
                .font(Typo.callout)
                .foregroundStyle(Palette.Window.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let review {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(review.entries, id: \.eventName) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: entry.eventName)
                                    .font(Typo.caption.weight(.semibold))
                                Text(verbatim: entry.command)
                                    .font(Typo.mono)
                                    .foregroundStyle(Palette.Window.textSecondary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .frame(maxHeight: 280)
                .background(Palette.Window.field, in: RoundedRectangle(cornerRadius: Palette.Window.Radius.inset, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Palette.Window.Radius.inset, style: .continuous)
                        .strokeBorder(Palette.Window.hairline, lineWidth: 0.75)
                }
            } else if isWorking {
                ProgressView(L10n.string("Reading Dev Island hooks…", language: language))
                    .controlSize(.small)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Typo.callout)
                    .foregroundStyle(Palette.Window.stateWaiting)
                if let executableURL {
                    Text(CodexTrustGuidance.manualInstructions(language: language))
                        .font(Typo.caption)
                        .foregroundStyle(Palette.Window.textSecondary)
                    Button {
                        copiedLauncher = CodexTrustGuidance.copyCLILaunchCommand(executableURL: executableURL)
                    } label: {
                        Text(L10n.string(
                            copiedLauncher ? "Launch command copied" : "Copy Codex CLI launch command",
                            language: language
                        ))
                    }
                    .buttonStyle(.window(.secondary))
                }
            }

            HStack {
                Spacer()
                Button(L10n.string("Cancel", language: language)) { dismiss() }
                    .buttonStyle(.window(.secondary))
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking && review != nil)
                Button(L10n.string(
                    review?.isAlreadyAuthorized == true ? "Done" : "Authorize Dev Island hooks",
                    language: language
                )) {
                    authorizeReviewedHooks()
                }
                .buttonStyle(.window(.primary))
                .disabled(isWorking || review == nil || errorMessage != nil)
            }
        }
        .padding(24)
        .frame(width: 540)
        .background(WindowCanvas())
        .foregroundStyle(Palette.Window.ink)
        .tint(Palette.Window.ink)
        .task {
            let authorization = authorization
            executableURL = await Task.detached(priority: .userInitiated) {
                CodexHookAuthorization.verifiedExecutableURL()
            }.value
            let result = await Task.detached(priority: .userInitiated) {
                Result { try authorization.review() }
            }.value
            switch result {
            case .success(let value): review = value
            case .failure(let error): errorMessage = CodexTrustGuidance.errorMessage(error, language: language)
            }
            isWorking = false
        }
    }

    private func authorizeReviewedHooks() {
        guard let review, !isWorking else { return }
        if review.isAlreadyAuthorized {
            onAuthorized()
            dismiss()
            return
        }
        isWorking = true
        let authorization = authorization
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try authorization.authorize(review) }
            }.value
            isWorking = false
            switch result {
            case .success:
                onAuthorized()
                dismiss()
            case .failure(let error):
                errorMessage = CodexTrustGuidance.errorMessage(error, language: language)
            }
        }
    }
}
