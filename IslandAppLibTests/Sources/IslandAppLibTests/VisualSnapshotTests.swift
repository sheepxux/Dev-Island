import AppKit
import SwiftUI
import XCTest
@testable import IslandAppLib
import IslandCore

/// Opt-in visual evidence for the fixed-size Welcome Tour.
///
/// Normal test runs stay side-effect free. Set
/// `DEV_ISLAND_VISUAL_SNAPSHOT_DIR` to an existing or creatable directory
/// when a design pass needs exact before/after PNGs, including on a locked
/// QA machine where interactive window capture is unavailable.
@MainActor
final class VisualSnapshotTests: XCTestCase {
    func testCaptureAgentBrandBadges() throws {
        guard let outputDirectory = try snapshotDirectory() else { return }
        configureApplicationIconForPackageTests()

        let gallery = HStack(spacing: 14) {
            ForEach(LocalAgentRegistry.all, id: \.source) { descriptor in
                VStack(spacing: 8) {
                    AgentLogoBadge(
                        source: descriptor.source,
                        size: 36,
                        ink: Palette.warmWhite.opacity(0.9),
                        badge: Color.white.opacity(0.055)
                    )
                    Text(descriptor.displayName)
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(height: 23, alignment: .top)
                }
                .frame(width: 78)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.tourCanvas)
        .preferredColorScheme(.dark)

        try render(
            gallery,
            size: NSSize(width: 800, height: 122),
            to: outputDirectory.appendingPathComponent("61-agent-brand-badges.png")
        )
    }

    func testCaptureTaskCardLeadingIdentity() throws {
        guard let outputDirectory = try snapshotDirectory() else { return }
        configureApplicationIconForPackageTests()

        let now = Date(timeIntervalSince1970: 1_788_060_000)
        let statuses: [TaskStatus] = [.running, .waiting, .completed, .failed]
        let rows = VStack(spacing: 4) {
            ForEach(Array(LocalAgentRegistry.all.enumerated()), id: \.element.source) {
                index, descriptor in
                TaskCard(
                    task: AgentTask(
                        id: "brand-row-\(descriptor.source)",
                        source: descriptor.source,
                        title: "\(descriptor.displayName) session",
                        status: statuses[index % statuses.count],
                        currentPhase: "Checking visual identity",
                        createdAt: now.addingTimeInterval(-180),
                        updatedAt: now.addingTimeInterval(-30),
                        taskURL: "file:///tmp/brand-row"
                    ),
                    now: now,
                    isLive: false,
                    onTap: {}
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.notchBlack)
        .preferredColorScheme(.dark)

        try render(
            rows,
            size: NSSize(width: 430, height: 526),
            to: outputDirectory.appendingPathComponent(
                "62-task-card-leading-identity.png"
            )
        )
    }

    func testCaptureWelcomeTour() throws {
        guard let outputPath = ProcessInfo.processInfo.environment[
            "DEV_ISLAND_VISUAL_SNAPSHOT_DIR"
        ], !outputPath.isEmpty else {
            return
        }

        configureApplicationIconForPackageTests()

        let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let hookSnapshot = LocalAgentHookDiagnostics.snapshot()

        for step in 0..<3 {
            let view = OnboardingView(
                onFinish: { _ in },
                initialStep: step,
                initialHookSnapshot: hookSnapshot
            )

            let destination = outputDirectory.appendingPathComponent(
                String(format: "%02d-welcome-step.png", step + 1)
            )
            try render(
                view,
                size: NSSize(
                    width: OnboardingMetrics.width,
                    height: OnboardingMetrics.height
                ),
                to: destination
            )
        }
    }

    func testCaptureSimplifiedChineseCoreExperience() throws {
        guard let outputDirectory = try snapshotDirectory() else { return }
        configureApplicationIconForPackageTests()

        let hookSnapshot = LocalAgentHookDiagnostics.snapshot()
        for step in 0..<3 {
            let view = OnboardingView(
                onFinish: { _ in },
                initialStep: step,
                initialHookSnapshot: hookSnapshot
            )
            try render(
                view,
                language: .simplifiedChinese,
                size: NSSize(
                    width: OnboardingMetrics.width,
                    height: OnboardingMetrics.height
                ),
                to: outputDirectory.appendingPathComponent(
                    String(format: "40-zh-hans-welcome-step-%02d.png", step + 1)
                )
            )
        }

        let layout = NotchMetrics.Layout(
            hasNotch: false,
            barHeight: 28,
            notchHeight: 0,
            menuBarHeight: 28,
            notchWidth: NotchMetrics.defaultNotchWidth,
            topMargin: 0
        )
        let compact = NotchBarView(
            state: .waiting,
            summary: .init(running: 19, waiting: 1),
            title: "需要批准部署权限",
            layout: layout
        )
        .padding(.horizontal, 30)
        .padding(.vertical, 22)
        .background(Color(white: 0.16))
        .preferredColorScheme(.dark)
        try render(
            compact,
            language: .simplifiedChinese,
            size: NSSize(width: 276, height: 72),
            to: outputDirectory.appendingPathComponent("43-zh-hans-island-waiting-20.png")
        )

        let settings = SettingsView(
            previewStore: TaskStore.presentationFixture()
        )
        try render(
            settings,
            language: .simplifiedChinese,
            size: NSSize(width: 720, height: 520),
            to: outputDirectory.appendingPathComponent("44-zh-hans-settings-agents.png")
        )

        let generalSettings = SettingsView(
            previewStore: TaskStore.presentationFixture(),
            initialPane: .general
        )
        try render(
            generalSettings,
            language: .simplifiedChinese,
            size: NSSize(width: 720, height: 520),
            to: outputDirectory.appendingPathComponent("45-zh-hans-settings-general.png")
        )

        let now = Date.now
        let runningHistory = AgentTask(
            id: "zh-running-history",
            source: "codex",
            title: "优化会话历史的视觉层级",
            status: .running,
            currentPhase: "正在检查状态语义",
            createdAt: now.addingTimeInterval(-190),
            updatedAt: now.addingTimeInterval(-12),
            taskURL: "file:///tmp/zh-running-history"
        )
        let history = [
            runningHistory,
            AgentTask(
                id: "zh-waiting-history",
                source: "claude-code",
                title: "批准生产签名命令",
                status: .waiting,
                currentPhase: "正在等待批准",
                createdAt: now.addingTimeInterval(-420),
                updatedAt: now.addingTimeInterval(-65),
                taskURL: "file:///tmp/zh-waiting-history"
            ),
            AgentTask(
                id: "zh-completed-history",
                source: "gemini-cli",
                title: "验证发布资源",
                status: .completed,
                currentPhase: "已完成",
                createdAt: now.addingTimeInterval(-980),
                updatedAt: now.addingTimeInterval(-310),
                taskURL: "file:///tmp/zh-completed-history"
            ),
            AgentTask(
                id: "zh-failed-history",
                source: "qwen-code",
                title: "运行连接器兼容性检查",
                status: .failed,
                currentPhase: "命令失败",
                createdAt: now.addingTimeInterval(-1_500),
                updatedAt: now.addingTimeInterval(-820),
                taskURL: "file:///tmp/zh-failed-history"
            ),
        ]
        let historyStore = TaskStore.presentationFixture(
            tasks: [runningHistory],
            storedTaskHistory: history
        )
        try render(
            TaskHistoryView(store: historyStore, automaticallyRefresh: false),
            language: .simplifiedChinese,
            size: NSSize(width: 680, height: 560),
            to: outputDirectory.appendingPathComponent("46-zh-hans-session-history.png")
        )

        let approvalTask = AgentTask(
            id: "zh-permission-session",
            source: "codex",
            title: "准备签名发布版本",
            status: .waiting,
            currentPhase: "正在等待批准",
            createdAt: now.addingTimeInterval(-38),
            updatedAt: now,
            taskURL: "file:///tmp/zh-permission-session"
        )
        let approvalRequest = AgentActionRequest(
            source: "codex",
            sessionId: approvalTask.id,
            kind: .permission,
            title: "允许执行签名验证命令？",
            message: "Codex 希望验证已签名的 App 包。",
            detail: "codesign --verify --deep --strict 'Dev Island.app'",
            createdAt: now,
            timeout: 90
        )
        try render(
            actionPanel(task: approvalTask, request: approvalRequest),
            language: .simplifiedChinese,
            size: NSSize(width: 464, height: 330),
            to: outputDirectory.appendingPathComponent("47-zh-hans-approval-surface.png")
        )

        let questionTask = AgentTask(
            id: "zh-question-session",
            source: "claude-code",
            title: "确定审批交互方式",
            status: .waiting,
            currentPhase: "正在等待输入",
            createdAt: now.addingTimeInterval(-41),
            updatedAt: now,
            taskURL: "file:///tmp/zh-question-session"
        )
        let questionRequest = AgentActionRequest(
            source: "claude-code",
            sessionId: questionTask.id,
            kind: .question,
            title: "Claude Code 需要输入",
            message: "回答问题后继续。",
            questions: [
                AgentQuestion(
                    question: "由哪个界面处理审批？",
                    header: "交互界面",
                    options: [
                        AgentQuestionOption(
                            label: "Dev Island",
                            description: "留在紧凑的灵动岛工作流中"
                        ),
                        AgentQuestionOption(
                            label: "终端",
                            description: "每次提问都返回 Claude Code"
                        ),
                    ]
                ),
            ],
            createdAt: now,
            timeout: 90
        )
        try render(
            actionPanel(task: questionTask, request: questionRequest),
            language: .simplifiedChinese,
            size: NSSize(width: 464, height: 390),
            to: outputDirectory.appendingPathComponent("48-zh-hans-question-surface.png")
        )

        let remainingSettingsPanes: [(SettingsPane, String)] = [
            (.notifications, "49-zh-hans-settings-notifications.png"),
            (.usage, "50-zh-hans-settings-usage.png"),
            (.updates, "51-zh-hans-settings-updates.png"),
            (.support, "52-zh-hans-settings-support.png"),
        ]
        for (pane, filename) in remainingSettingsPanes {
            try render(
                SettingsView(
                    previewStore: TaskStore.presentationFixture(),
                    initialPane: pane
                ),
                language: .simplifiedChinese,
                size: NSSize(width: 720, height: 520),
                to: outputDirectory.appendingPathComponent(filename)
            )
        }

        let emptyPanel = NotchPanelView(
            tasks: [],
            manusConnectionStatus: .connected,
            localAgentStatus: .listening,
            apiKeyStatus: .valid,
            layout: layout,
            highlightedTask: nil,
            onTaskTap: { _ in },
            onSettingsTap: {},
            onConnectTap: {},
            isLive: false
        )
        .padding(22)
        .background(Color(white: 0.16))
        .preferredColorScheme(.dark)
        try render(
            emptyPanel,
            language: .simplifiedChinese,
            size: NSSize(width: 464, height: 250),
            to: outputDirectory.appendingPathComponent("53-zh-hans-empty-panel.png")
        )
    }

    func testCaptureCompactIslandStates() throws {
        guard let outputDirectory = try snapshotDirectory() else { return }
        configureApplicationIconForPackageTests()

        let layout = NotchMetrics.Layout(
            hasNotch: false,
            barHeight: 28,
            notchHeight: 0,
            menuBarHeight: 28,
            notchWidth: NotchMetrics.defaultNotchWidth,
            topMargin: 0
        )
        let cases: [(String, BarState, TaskStatusSummary, String)] = [
            ("idle", .idle, .init(), "No sessions"),
            ("running", .running, .init(running: 3), "Running tests"),
            ("waiting", .waiting, .init(running: 2, waiting: 1), "Approval required"),
            ("completed", .completed, .init(running: 2, completed: 1), "Build complete"),
            ("failed", .failed, .init(running: 2, failed: 1), "Command failed"),
            ("waiting-20", .waiting, .init(running: 19, waiting: 1), "Approval required"),
        ]

        for (index, item) in cases.enumerated() {
            let view = NotchBarView(
                state: item.1,
                summary: item.2,
                title: item.3,
                layout: layout
            )
            .padding(.horizontal, 30)
            .padding(.vertical, 22)
            .background(Color(white: 0.16))
            .preferredColorScheme(.dark)

            try render(
                view,
                size: NSSize(width: 276, height: 72),
                to: outputDirectory.appendingPathComponent(
                    String(format: "%02d-island-%@.png", index + 10, item.0)
                )
            )
        }
    }

    func testCapturePriorityPanel() throws {
        guard let outputDirectory = try snapshotDirectory() else { return }
        configureApplicationIconForPackageTests()

        let now = Date.now
        let tasks = [
            AgentTask(
                id: "approval",
                source: "claude-code",
                title: "Review deployment permissions",
                status: .waiting,
                currentPhase: "Waiting for approval",
                createdAt: now.addingTimeInterval(-82),
                updatedAt: now,
                taskURL: "file:///tmp/approval"
            ),
            AgentTask(
                id: "result",
                source: "codex",
                title: "Refine Welcome Tour",
                status: .completed,
                currentPhase: "Changes ready",
                createdAt: now.addingTimeInterval(-245),
                updatedAt: now,
                taskURL: "file:///tmp/result"
            ),
            AgentTask(
                id: "running",
                source: "gemini-cli",
                title: "Validate release assets",
                status: .running,
                currentPhase: "Running tests",
                createdAt: now.addingTimeInterval(-114),
                updatedAt: now,
                taskURL: "file:///tmp/running"
            ),
        ]
        let layout = NotchMetrics.Layout(
            hasNotch: false,
            barHeight: 28,
            notchHeight: 0,
            menuBarHeight: 28,
            notchWidth: NotchMetrics.defaultNotchWidth,
            topMargin: 0
        )

        let view = NotchPanelView(
            tasks: TaskPresentationPolicy.ordered(tasks),
            manusConnectionStatus: .connected,
            localAgentStatus: .listening,
            apiKeyStatus: .valid,
            layout: layout,
            highlightedTask: tasks[0].identity,
            onTaskTap: { _ in },
            onSettingsTap: {},
            onConnectTap: {},
            isLive: false
        )
        .padding(22)
        .background(Color(white: 0.16))
        .preferredColorScheme(.dark)

        try render(
            view,
            size: NSSize(width: 464, height: 286),
            to: outputDirectory.appendingPathComponent("20-priority-panel.png")
        )
    }

    func testCaptureTwentySessionStressPanel() throws {
        guard let outputDirectory = try snapshotDirectory() else { return }
        configureApplicationIconForPackageTests()

        let now = Date.now
        let sources = [
            "claude-code", "codex", "gemini-cli", "qwen-code",
            "copilot-cli", "kimi-code", "cursor",
        ]
        let phases = [
            "Waiting for approval", "Waiting for input", "Review requested",
            "Permission required", "Needs a decision", "Command failed",
            "Tests failed", "Build needs review", "Completed", "Changes ready",
            "Validation complete", "Review complete", "Running tests",
            "Indexing project", "Writing changes", "Calling tool",
            "Reviewing output", "Preparing build", "Checking assets",
            "Updating documentation",
        ]
        let tasks = (0..<20).map { index -> AgentTask in
            let status: TaskStatus
            switch index {
            case 0..<5: status = .waiting
            case 5..<8: status = .failed
            case 8..<12: status = .completed
            default: status = .running
            }
            return AgentTask(
                id: "stress-session-\(index)",
                source: sources[index % sources.count],
                title: "Session \(index + 1) · \(phases[index])",
                status: status,
                currentPhase: phases[index],
                createdAt: now.addingTimeInterval(TimeInterval(index - 240)),
                updatedAt: now.addingTimeInterval(TimeInterval(-index)),
                taskURL: "file:///tmp/stress-session-\(index)"
            )
        }
        let orderedTasks = TaskPresentationPolicy.ordered(tasks, now: now)
        let layout = NotchMetrics.Layout(
            hasNotch: false,
            barHeight: 28,
            notchHeight: 0,
            menuBarHeight: 28,
            notchWidth: NotchMetrics.defaultNotchWidth,
            topMargin: 0
        )
        let view = NotchPanelView(
            tasks: orderedTasks,
            manusConnectionStatus: .connected,
            localAgentStatus: .listening,
            apiKeyStatus: .valid,
            layout: layout,
            highlightedTask: orderedTasks.first?.identity,
            onTaskTap: { _ in },
            onSettingsTap: {},
            onConnectTap: {},
            isLive: false
        )
        .padding(22)
        .background(Color(white: 0.16))
        .preferredColorScheme(.dark)

        try render(
            view,
            size: NSSize(width: 464, height: 420),
            to: outputDirectory.appendingPathComponent(
                "24-twenty-session-stress.png"
            )
        )
    }

    func testCaptureSettingsAgents() throws {
        guard let outputDirectory = try snapshotDirectory() else { return }
        configureApplicationIconForPackageTests()

        let view = SettingsView(
            previewStore: TaskStore.presentationFixture()
        )

        try render(
            view,
            size: NSSize(width: 720, height: 520),
            to: outputDirectory.appendingPathComponent("30-settings-agents.png")
        )
    }

    func testCaptureEnglishSettingsControlRhythm() throws {
        guard let outputDirectory = try snapshotDirectory() else { return }
        configureApplicationIconForPackageTests()

        let panes: [(SettingsPane, String)] = [
            (.general, "33-settings-general.png"),
            (.notifications, "34-settings-notifications.png"),
            (.usage, "35-settings-usage.png"),
            (.updates, "36-settings-updates.png"),
        ]

        for (pane, filename) in panes {
            let view = SettingsView(
                previewStore: TaskStore.presentationFixture(),
                initialPane: pane
            )
            try render(
                view,
                size: NSSize(width: 720, height: 520),
                to: outputDirectory.appendingPathComponent(filename)
            )
        }
    }

    func testCaptureBundledLegalDocuments() throws {
        guard let outputDirectory = try snapshotDirectory() else { return }
        configureApplicationIconForPackageTests()

        try render(
            SettingsView(
                previewStore: TaskStore.presentationFixture(),
                initialPane: .support
            ),
            size: NSSize(width: 720, height: 520),
            to: outputDirectory.appendingPathComponent("56-settings-support-en.png")
        )

        try render(
            SettingsView(
                previewStore: TaskStore.presentationFixture(),
                initialPane: .support
            ),
            language: .simplifiedChinese,
            size: NSSize(width: 720, height: 520),
            to: outputDirectory.appendingPathComponent("57-settings-support-zh-hans.png")
        )

        let english = LegalDocumentPresentation(
            kind: .privacy,
            title: "Dev Island Privacy Notice",
            lastUpdated: "Last updated: August 29, 2026",
            blocks: [
                .callout("Engineering-verified draft for owner and legal review. This copy is bundled with the app and available offline."),
                .heading(level: 2, text: "1. Data processed on your Mac"),
                .paragraph("Dev Island is local-first. It processes bounded Agent and session state needed to present work and requests that need your attention."),
                .bullet("Local hooks deliver events only to the loopback listener on this Mac."),
                .bullet("Prompts, credentials, raw errors, and file-system paths are excluded from support diagnostics."),
                .heading(level: 2, text: "2. Your choices"),
                .paragraph("You choose which connectors, notifications, updates, and local history features to enable."),
            ]
        )
        try render(
            LegalDocumentSheet(
                kind: .privacy,
                previewPresentation: english,
                previewAppVersion: "0.3.0"
            ),
            size: NSSize(width: 640, height: 540),
            to: outputDirectory.appendingPathComponent("54-legal-privacy-en.png")
        )

        let chinese = LegalDocumentPresentation(
            kind: .terms,
            title: "Dev Island 使用条款",
            lastUpdated: "最后更新：2026 年 8 月 26 日",
            blocks: [
                .callout("这是供产品负责人和法律专业人士审阅的工程草案。当前副本随 App 离线提供。"),
                .heading(level: 2, text: "1. 当前 Beta"),
                .paragraph("当前版本尚未启用应用内购买、订阅、生产激活或付费服务。"),
                .heading(level: 2, text: "2. Agent 操作与审批"),
                .paragraph("Agent 可能犯错。影响不清晰时应回到来源会话核对，再决定是否允许操作。"),
                .bullet("不得把非官方构建冒充官方签名版本。"),
                .bullet("第三方 Agent 的条款与账号规则由对应服务商负责。"),
            ]
        )
        try render(
            LegalDocumentSheet(
                kind: .terms,
                previewPresentation: chinese,
                previewAppVersion: "0.3.0"
            ),
            language: .simplifiedChinese,
            size: NSSize(width: 640, height: 540),
            to: outputDirectory.appendingPathComponent("55-legal-terms-zh-hans.png")
        )
    }

    func testCaptureSettingsLiveReadinessAttention() throws {
        guard let outputDirectory = try snapshotDirectory() else { return }
        configureApplicationIconForPackageTests()

        let readiness = LocalLiveReadinessSnapshot(
            listener: .listening,
            agents: [
                .init(
                    source: "claude-code",
                    cli: .verified,
                    hook: .updateRequired,
                    activation: .notRequired
                ),
                .init(
                    source: "codex",
                    cli: .verified,
                    hook: .updateRequired,
                    activation: .reviewRequired
                ),
            ]
        )
        let view = SettingsView(
            previewStore: TaskStore.presentationFixture(),
            initialLiveReadinessSnapshot: readiness
        )

        try render(
            view,
            size: NSSize(width: 720, height: 520),
            to: outputDirectory.appendingPathComponent(
                "31-settings-live-readiness-attention.png"
            )
        )
    }

    func testCaptureSettingsLiveReadinessCheckFailed() throws {
        guard let outputDirectory = try snapshotDirectory() else { return }
        configureApplicationIconForPackageTests()

        let readiness = LocalLiveReadinessSnapshot(
            listener: .listening,
            agents: [
                .init(
                    source: "claude-code",
                    cli: .checkFailed,
                    hook: .connected,
                    activation: .notRequired
                ),
                .init(
                    source: "codex",
                    cli: .verified,
                    hook: .connected,
                    activation: .verified
                ),
            ]
        )
        let view = SettingsView(
            previewStore: TaskStore.presentationFixture(),
            initialLiveReadinessSnapshot: readiness
        )

        try render(
            view,
            size: NSSize(width: 720, height: 520),
            to: outputDirectory.appendingPathComponent(
                "01-settings-readiness-check-failed-en.png"
            )
        )
        try render(
            view,
            language: .simplifiedChinese,
            size: NSSize(width: 720, height: 520),
            to: outputDirectory.appendingPathComponent(
                "02-settings-readiness-check-failed-zh-hans.png"
            )
        )
    }

    func testCaptureSessionHistory() throws {
        guard let outputDirectory = try snapshotDirectory() else { return }
        configureApplicationIconForPackageTests()

        let now = Date.now
        let running = AgentTask(
            id: "running-history",
            source: "codex",
            title: "Refine the session history visual language",
            status: .running,
            currentPhase: "Reviewing status semantics",
            createdAt: now.addingTimeInterval(-190),
            updatedAt: now.addingTimeInterval(-12),
            taskURL: "file:///tmp/running-history"
        )
        let history = [
            running,
            AgentTask(
                id: "waiting-history",
                source: "claude-code",
                title: "Approve the production signing command",
                status: .waiting,
                currentPhase: "Waiting for approval",
                createdAt: now.addingTimeInterval(-420),
                updatedAt: now.addingTimeInterval(-65),
                taskURL: "file:///tmp/waiting-history"
            ),
            AgentTask(
                id: "completed-history",
                source: "gemini-cli",
                title: "Validate release assets",
                status: .completed,
                currentPhase: "Completed",
                createdAt: now.addingTimeInterval(-980),
                updatedAt: now.addingTimeInterval(-310),
                taskURL: "file:///tmp/completed-history"
            ),
            AgentTask(
                id: "failed-history",
                source: "qwen-code",
                title: "Run connector compatibility checks",
                status: .failed,
                currentPhase: "Command failed",
                createdAt: now.addingTimeInterval(-1_500),
                updatedAt: now.addingTimeInterval(-820),
                taskURL: "file:///tmp/failed-history"
            ),
        ]
        let store = TaskStore.presentationFixture(
            tasks: [running],
            storedTaskHistory: history
        )
        let view = TaskHistoryView(
            store: store,
            automaticallyRefresh: false
        )

        try render(
            view,
            size: NSSize(width: 680, height: 560),
            to: outputDirectory.appendingPathComponent("31-session-history.png")
        )
    }

    func testCaptureLaunchHealthNotice() throws {
        guard let outputDirectory = try snapshotDirectory() else { return }

        let view = LaunchHealthNotice(consecutiveStartupInterruptions: 2)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.tourCanvas)
            .preferredColorScheme(.dark)

        try render(
            view,
            size: NSSize(width: 560, height: 160),
            to: outputDirectory.appendingPathComponent("32-launch-health-notice.png")
        )
    }

    func testCaptureApprovalSurface() throws {
        guard let outputDirectory = try snapshotDirectory() else { return }
        configureApplicationIconForPackageTests()

        let now = Date.now
        let task = AgentTask(
            id: "permission-session",
            source: "codex",
            title: "Prepare signed release",
            status: .waiting,
            currentPhase: "Waiting for approval",
            createdAt: now.addingTimeInterval(-38),
            updatedAt: now,
            taskURL: "file:///tmp/permission-session"
        )
        let request = AgentActionRequest(
            source: "codex",
            sessionId: task.id,
            kind: .permission,
            title: "Allow shell command?",
            message: "Codex wants to verify the signed app bundle.",
            detail: "codesign --verify --deep --strict 'Dev Island.app'",
            createdAt: now,
            timeout: 90
        )
        let layout = NotchMetrics.Layout(
            hasNotch: false,
            barHeight: 28,
            notchHeight: 0,
            menuBarHeight: 28,
            notchWidth: NotchMetrics.defaultNotchWidth,
            topMargin: 0
        )

        let view = NotchPanelView(
            tasks: [task],
            manusConnectionStatus: .connected,
            localAgentStatus: .listening,
            apiKeyStatus: .valid,
            layout: layout,
            highlightedTask: task.identity,
            pendingActionRequests: [request],
            onTaskTap: { _ in },
            onSettingsTap: {},
            onConnectTap: {},
            initialPlanDocuments: request.planReview.map {
                [request.id: PlanMarkdownDocument.render($0.markdown)]
            } ?? [:],
            isLive: false
        )
        .padding(22)
        .background(Color(white: 0.16))
        .preferredColorScheme(.dark)

        try render(
            view,
            size: NSSize(width: 464, height: 330),
            to: outputDirectory.appendingPathComponent("21-approval-surface.png")
        )
    }

    func testCaptureQuestionSurface() throws {
        guard let outputDirectory = try snapshotDirectory() else { return }
        configureApplicationIconForPackageTests()

        let now = Date.now
        let task = AgentTask(
            id: "question-session",
            source: "claude-code",
            title: "Refine the attention flow",
            status: .waiting,
            currentPhase: "Waiting for input",
            createdAt: now.addingTimeInterval(-41),
            updatedAt: now,
            taskURL: "file:///tmp/question-session"
        )
        let request = AgentActionRequest(
            source: "claude-code",
            sessionId: task.id,
            kind: .question,
            title: "Claude Code needs input",
            message: "Answer two questions to continue.",
            questions: [
                AgentQuestion(
                    question: "Which surface should own approvals?",
                    header: "Surface",
                    options: [
                        AgentQuestionOption(
                            label: "Dev Island",
                            description: "Stay in the compact island workflow"
                        ),
                        AgentQuestionOption(
                            label: "Terminal",
                            description: "Return to Claude Code for every prompt"
                        ),
                    ]
                ),
                AgentQuestion(
                    question: "Which verification should run?",
                    header: "Checks",
                    options: [
                        AgentQuestionOption(label: "Unit tests"),
                        AgentQuestionOption(label: "Visual review"),
                    ],
                    allowsMultipleSelection: true
                ),
            ],
            createdAt: now,
            timeout: 90
        )

        try render(
            actionPanel(task: task, request: request),
            size: NSSize(width: 464, height: 420),
            to: outputDirectory.appendingPathComponent("22-question-surface.png")
        )
    }

    func testCaptureQuestionSelectionMarks() throws {
        guard let outputDirectory = try snapshotDirectory() else { return }

        let gallery = VStack(alignment: .leading, spacing: 14) {
            questionSelectionRow(
                title: "Single selection",
                allowsMultipleSelection: false
            )
            questionSelectionRow(
                title: "Multiple selection",
                allowsMultipleSelection: true
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.notchBlack)
        .preferredColorScheme(.dark)

        try render(
            gallery,
            size: NSSize(width: 320, height: 136),
            to: outputDirectory.appendingPathComponent(
                "25-question-selection-marks.png"
            )
        )
    }

    func testCapturePlanReviewSurface() throws {
        guard let outputDirectory = try snapshotDirectory() else { return }
        configureApplicationIconForPackageTests()

        let now = Date.now
        let task = AgentTask(
            id: "plan-session",
            source: "claude-code",
            title: "Review implementation plan",
            status: .waiting,
            currentPhase: "Waiting for plan review",
            createdAt: now.addingTimeInterval(-54),
            updatedAt: now,
            taskURL: "file:///tmp/plan-session"
        )
        let markdown = """
        ## Refine the attention flow

        1. Keep approval requests ahead of completed and running sessions.
        2. Preserve stable ordering inside the same priority tier.
        3. Verify keyboard focus, VoiceOver order, and Reduce Motion.
        """
        let input = try JSONSerialization.data(
            withJSONObject: ["plan": markdown, "futureField": 7],
            options: [.sortedKeys]
        )
        let review = try XCTUnwrap(AgentPlanReview(
            markdown: markdown,
            originalInputJSON: input
        ))
        let request = AgentActionRequest(
            source: "claude-code",
            sessionId: task.id,
            kind: .planReview,
            title: "Review Claude Code plan",
            message: "Claude Code is ready to begin implementation.",
            planReview: review,
            createdAt: now,
            timeout: 90
        )

        try render(
            actionPanel(task: task, request: request),
            size: NSSize(width: 464, height: 430),
            to: outputDirectory.appendingPathComponent("23-plan-review-surface.png")
        )
    }

    private func actionPanel(
        task: AgentTask,
        request: AgentActionRequest
    ) -> some View {
        let layout = NotchMetrics.Layout(
            hasNotch: false,
            barHeight: 28,
            notchHeight: 0,
            menuBarHeight: 28,
            notchWidth: NotchMetrics.defaultNotchWidth,
            topMargin: 0
        )
        return NotchPanelView(
            tasks: [task],
            manusConnectionStatus: .connected,
            localAgentStatus: .listening,
            apiKeyStatus: .valid,
            layout: layout,
            highlightedTask: task.identity,
            pendingActionRequests: [request],
            onTaskTap: { _ in },
            onSettingsTap: {},
            onConnectTap: {},
            isLive: false
        )
        .padding(22)
        .background(Color(white: 0.16))
        .preferredColorScheme(.dark)
    }

    private func questionSelectionRow(
        title: String,
        allowsMultipleSelection: Bool
    ) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 112, alignment: .leading)

            ForEach([false, true], id: \.self) { selected in
                HStack(spacing: 7) {
                    QuestionSelectionMark(
                        selected: selected,
                        allowsMultipleSelection: allowsMultipleSelection
                    )
                    Text(selected ? "Selected" : "Resting")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(
                            selected ? Palette.warmWhite : Palette.textTertiary
                        )
                }
                .frame(width: 76, alignment: .leading)
            }
        }
    }

    private func snapshotDirectory() throws -> URL? {
        guard let outputPath = ProcessInfo.processInfo.environment[
            "DEV_ISLAND_VISUAL_SNAPSHOT_DIR"
        ], !outputPath.isEmpty else {
            return nil
        }
        let directory = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func configureApplicationIconForPackageTests() {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        AgentBrand.resourceDirectoryOverride = repositoryRoot
            .appendingPathComponent("IslandApp/Resources", isDirectory: true)
        let iconURL = repositoryRoot
            .appendingPathComponent("IslandApp/Resources/AppIcon.icns")
        if let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    private func render<Content: View>(
        _ content: Content,
        language: DevIslandLanguage = .english,
        size: NSSize,
        to destination: URL
    ) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            XCTFail("Refusing to overwrite visual evidence at \(destination.path)")
            return
        }
        _ = NSApplication.shared

        let hostingView = NSHostingView(
            rootView: LocalizedAppRoot(language: language) {
                content
            }
        )
        hostingView.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hostingView

        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(
            in: hostingView.bounds
        ) else {
            XCTFail("Could not allocate a visual snapshot bitmap")
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Could not encode the visual snapshot as PNG")
            return
        }
        try png.write(to: destination, options: .atomic)
    }
}
