import SwiftUI
import IslandCore

/// A read-only view over persisted snapshots. It intentionally consumes
/// `storedTaskHistory`, never `tasks`, so opening the sheet cannot change the
/// island's attention queue or emit a notification.
struct TaskHistoryView: View {
    let store: TaskStore
    private let automaticallyRefresh: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.devIslandLanguage) private var language
    @State private var query = ""
    @State private var filter: TaskHistoryFilter = .all

    init(store: TaskStore, automaticallyRefresh: Bool = true) {
        self.store = store
        self.automaticallyRefresh = automaticallyRefresh
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.Window.hairline)
            controls
            Divider().overlay(Palette.Window.hairline)
            content
            Divider().overlay(Palette.Window.hairline)
            footer
        }
        .frame(minWidth: 640, idealWidth: 680, minHeight: 500, idealHeight: 560)
        .background(Palette.Window.canvas)
        .foregroundStyle(Palette.Window.ink)
        .tint(Palette.Window.ink)
        .preferredColorScheme(.light)
        .task {
            guard automaticallyRefresh else { return }
            await store.refreshStoredTaskHistory()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("Session History", language: language))
                    .font(Typo.title)
                    .tracking(Typo.titleTracking)
                Text(L10n.string(
                    "A private, read-only record stored on this Mac.",
                    language: language
                ))
                    .font(Typo.caption)
                    .foregroundStyle(Palette.Window.textSecondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Palette.Window.ink.opacity(0.055))
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .foregroundStyle(Palette.Window.textSecondary)
            .accessibilityLabel(
                L10n.string("Close session history", language: language)
            )
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.Window.textTertiary)
                TextField(
                    L10n.string("Search title or agent", language: language),
                    text: $query
                )
                    .textFieldStyle(.plain)
                    .font(Typo.callout)
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(
                Capsule()
                    .fill(Palette.Window.field)
                    .overlay {
                        Capsule()
                            .strokeBorder(Palette.Window.hairlineStrong, lineWidth: 0.75)
                    }
            )

            Picker(L10n.string("Status", language: language), selection: $filter) {
                ForEach(TaskHistoryFilter.allCases) { value in
                    Text(value.label(language: language)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 332)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        switch store.storedTaskHistoryStatus {
        case .loading:
            historyPlaceholder(
                icon: nil,
                title: L10n.string("Loading local history…", language: language),
                detail: L10n.string("Reading the private database on this Mac.", language: language)
            )

        case .unavailable:
            historyPlaceholder(
                icon: "exclamationmark.triangle",
                title: L10n.string("History is unavailable", language: language),
                detail: L10n.string(
                    "Your live sessions are unaffected. Retry after the local database becomes available.",
                    language: language
                )
            ) {
                Task { await store.refreshStoredTaskHistory() }
            }

        case .available:
            if visibleTasks.isEmpty {
                historyPlaceholder(
                    icon: "clock",
                    title: emptyTitle,
                    detail: emptyDetail
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(visibleTasks.enumerated()), id: \.element.identity) { index, task in
                            TaskHistoryRow(
                                task: task,
                                isLive: liveIdentities.contains(task.identity),
                                onOpen: { store.jumpToTask(task) }
                            )
                            if index < visibleTasks.count - 1 {
                                WindowDivider()
                                    .padding(.leading, 54)
                            }
                        }
                    }
                    .windowSurface(radius: Palette.Window.Radius.group, tone: .raised)
                    .padding(22)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(historyCountCopy)
                .font(Typo.caption)
                .monospacedDigit()
                .foregroundStyle(Palette.Window.textTertiary)

            Spacer()

            Button {
                Task { await store.refreshStoredTaskHistory() }
            } label: {
                Label {
                    Text(L10n.string("Refresh", language: language))
                } icon: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.window(.secondary))
            .disabled(store.storedTaskHistoryStatus == .loading)
            .accessibilityHint(
                L10n.string(
                    "Reloads private session history from this Mac",
                    language: language
                )
            )
        }
        .padding(.horizontal, 22)
        .frame(height: 50)
    }

    private var visibleTasks: [AgentTask] {
        TaskHistoryPresentation.filtered(
            store.storedTaskHistory,
            query: query,
            filter: filter
        )
    }

    private var liveIdentities: Set<TaskIdentity> {
        Set(store.tasks.compactMap { task in
            task.status == .running || task.status == .waiting ? task.identity : nil
        })
    }

    private var historyCountCopy: String {
        let total = store.storedTaskHistoryTotalCount
        let loaded = store.storedTaskHistory.count
        if total > loaded {
            return L10n.format(
                "Showing the %lld most recent of %lld",
                language: language,
                Int64(loaded),
                Int64(total)
            )
        }
        return L10n.format(
            total == 1 ? "%lld stored session" : "%lld stored sessions",
            language: language,
            Int64(total)
        )
    }

    private var emptyTitle: String {
        L10n.string(
            store.storedTaskHistory.isEmpty ? "No stored sessions yet" : "No matching sessions",
            language: language
        )
    }

    private var emptyDetail: String {
        L10n.string(
            store.storedTaskHistory.isEmpty
            ? "Completed and in-progress Agent snapshots will appear here without changing the live island."
            : "Try another search or status filter.",
            language: language
        )
    }

    private func historyPlaceholder(
        icon: String?,
        title: String,
        detail: String,
        retry: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Palette.Window.textTertiary)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(title)
                .font(Typo.bodyStrong)
            Text(detail)
                .font(Typo.caption)
                .foregroundStyle(Palette.Window.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let retry {
                Button(L10n.string("Retry", language: language), action: retry)
                    .buttonStyle(.window(.secondary))
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(36)
    }
}

private struct TaskHistoryRow: View {
    let task: AgentTask
    let isLive: Bool
    let onOpen: () -> Void

    @Environment(\.devIslandLanguage) private var language
    @State private var isHovering = false

    /// The whole row opens the session. VoiceOver hears the title as the
    /// label and source, status and age as the value, the same facts the
    /// row shows.
    var body: some View {
        Button(action: onOpen) { rowContent }
            .buttonStyle(HistoryRowButtonStyle(isHovering: isHovering))
            .onHover { isHovering = $0 }
            .pointingHandCursor()
            .accessibilityLabel(titleText)
            .accessibilityValue(accessibilityDetails)
            .accessibilityHint(
                L10n.string(
                    "Returns to the Agent or its host app",
                    language: language
                )
            )
    }

    private var titleText: String {
        task.title.isEmpty
            ? L10n.string("Untitled session", language: language)
            : task.title
    }

    private var accessibilityDetails: String {
        [
            TaskHistoryPresentation.sourceName(task.source),
            TaskHistoryPresentation.statusLabel(for: task, isLive: isLive, language: language),
            TaskHistoryPresentation.relativeAgeLabel(for: task.updatedAt, relativeTo: .now, language: language),
        ].joined(separator: L10n.string(", ", language: language))
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            AgentLogoBadge(
                source: task.source,
                size: 28,
                ink: Palette.Window.ink,
                badge: Palette.Window.canvasDeep
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(titleText)
                    .font(Typo.calloutStrong)
                    .foregroundStyle(Palette.Window.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    Text(TaskHistoryPresentation.sourceName(task.source))
                    Text(verbatim: "·")
                    DotMatrixMark(
                        color: task.status.windowColor,
                        size: 9,
                        pattern: task.status.matrixPattern,
                        intensity: task.status.matrixIntensity
                    )
                        .accessibilityHidden(true)
                    Text(TaskHistoryPresentation.statusLabel(
                        for: task,
                        isLive: isLive,
                        language: language
                    ))
                    Text(verbatim: "·")
                    Text(TaskHistoryPresentation.relativeAgeLabel(
                        for: task.updatedAt,
                        relativeTo: .now,
                        language: language
                    ))
                }
                .font(Typo.caption)
                .foregroundStyle(Palette.Window.textSecondary)
            }

            Spacer(minLength: 12)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.Window.textTertiary)
                .opacity(isHovering ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }

}

/// Hover and press washes for whole-row History buttons.
private struct HistoryRowButtonStyle: ButtonStyle {
    let isHovering: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Rectangle().fill(
                    configuration.isPressed
                        ? Palette.Window.pressed
                        : (isHovering ? Palette.Window.hover : .clear)
                )
            }
            .animation(
                Motion.respectingReducedMotion(reduceMotion, preferred: Motion.hoverHighlight),
                value: isHovering
            )
            .animation(Motion.press, value: configuration.isPressed)
    }
}
