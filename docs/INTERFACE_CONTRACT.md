# IslandCore Interface Contract

> 最后更新: 2026-08-09 | 版本: v1.6.0
> 变更流程: 改 TaskStore 公开 API 前更新此文档,commit 用 `[S][contract]` tag。

---

## TaskStore 公开 API

```swift
@MainActor
@Observable
public final class TaskStore {

    // MARK: - Observed state (C 的 View 只读)

    public private(set) var tasks: [AgentTask]
    public private(set) var connectionStatus: ConnectionStatus
    public private(set) var apiKeyStatus: APIKeyStatus

    // MARK: - Actions

    /// 验证并保存 API key,启动所有服务。
    /// 抛出 ManusError.unauthorized 若 key 无效。
    public func configureAPIKey(_ key: String) async throws

    /// 清除 API key,停止所有服务,清空 tasks。
    public func clearAPIKey()

    /// 在浏览器中打开指定任务。
    /// 裸 id 兼容入口仅在匹配唯一时执行;新代码应传 source 或 AgentTask。
    public func openTaskInBrowser(id: String)
    public func openTaskInBrowser(source: String, id: String)
    public func openTask(_ task: AgentTask)

    /// 按全局身份解析任务。
    public func task(with identity: TaskIdentity) -> AgentTask?

    /// 跳回任务所在的会话(v1.4.0 新增,J2 交付)。
    /// 能解析出来源 app 时做 app 级激活(cursor → Cursor.app);
    /// 解析不出或激活失败时回退到 openTaskInBrowser 的行为
    /// (本地任务 → Finder 打开项目目录,Manus → 浏览器)。
    public func jumpToTask(id: String)
    public func jumpToTask(source: String, id: String)
    public func jumpToTask(_ task: AgentTask)

    /// 通过 Manus API 停止任务。
    public func stopTask(id: String) async throws

    // MARK: - Events (v1.4.0 新增,J1 交付)

    /// 任务状态跃迁回调。B 侧(通知投递)在 app 启动时赋值一次。
    /// - 主线程(MainActor)回调,`tasks` 已更新完毕后触发
    /// - 每个状态发生变化的任务触发一次;新出现的任务也触发
    ///   (oldStatus == nil);任务移除不触发
    /// - 同一批快照里多个任务变化 → 逐个回调,顺序不保证
    /// - Debug Sandbox 的 debug 系列 mutator 同样触发,便于 B 测通知
    public var onTaskTransition: ((TaskTransition) -> Void)?
}

/// 一次任务状态跃迁(v1.4.0 新增)。
public struct TaskTransition: Sendable {
    public let task: AgentTask          // 跃迁之后的任务状态
    public let oldStatus: TaskStatus?   // nil = 该任务首次出现
    public let newStatus: TaskStatus    // 与 task.status 相同,便于 switch
}
```

**B 侧通知建议映射**(契约不强制,B 自行决定打扰度):

| 跃迁 | 建议动作 |
|---|---|
| 任意 → `.waiting` | 通知「需要你的审批/输入」+ `waitingMessage` |
| 任意 → `.failed` | 通知「任务失败」 |
| `.running` → `.completed` | 通知「任务完成」(可选,默认关,减少噪音) |
| 首次出现(oldStatus == nil) | 不通知(避免 app 启动时快照轰炸) |

---

## 数据模型

```swift
public struct AgentTask: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let source: String          // "manus"
    public var title: String
    public var status: TaskStatus
    public var currentPhase: String?
    public let createdAt: Date
    public var updatedAt: Date
    public let taskURL: String
    public var waitingMessage: String?
    public var identity: TaskIdentity  // (source, id),跨 agent 全局唯一
}

public struct TaskIdentity: Hashable, Codable, Sendable {
    public let source: String
    public let id: String
}

public enum TaskStatus: String, Codable, Sendable {
    case running, waiting, completed, failed
}

public enum ConnectionStatus: Equatable, Sendable {
    case connected
    case disconnected
    case reconnecting
    case degraded(reason: String)
}

public enum APIKeyStatus: Equatable, Sendable {
    case notConfigured
    case valid
    case invalid
}
```

---

## v1 限制

- `TaskStore` 没有 `reply` 方法 — v2 再加
- 没有附件下载
- 只支持单 Manus 账户
- session id 只在单个 source 内唯一。UI 列表、通知、高亮、跳回必须使用
  `TaskIdentity` / `AgentTask`,不得把裸 `id` 当全局 key
- `openTaskInBrowser` 由 C 调用 `TaskStore.openTask(_:)`,不是通过 AgentConnector

---

## Claude Code 本地连接器(v1.1.0 新增)

`TaskStore` 公开 API 不变。新增 C 侧可用的 IslandCore 公开类型:

```swift
/// hooks 安装器 — SettingsView 的 Claude Code 行直接调用
public enum ClaudeHooksInstaller {
    public static func isInstalled(settingsURL: URL? = nil) -> Bool
    public static func install(settingsURL: URL? = nil, port: Int = defaultPort) throws
    public static func uninstall(settingsURL: URL? = nil) throws
}
```

行为约定:

- `tasks` 里现在会出现 `source == "claude-code"` 的任务(TaskCard 已有 "C" logo 分支)
- claude-code 任务的 `taskURL` 是项目目录的 `file://` URL,`openTaskInBrowser` 会打开 Finder
- `stopTask` 对 claude-code 任务是 no-op(本地会话无法远程停止)
- `clearAPIKey` 只清 Manus 任务,不影响本地会话
- 本地管线(`LocalHookServer`,127.0.0.1:7824)随 app 启动,与 Manus key 无关

---

## Codex / Cursor 本地连接器(v1.2.0 / v1.3.0 新增)

API 形态与 Claude Code 完全一致,仅安装器与 source 不同:

```swift
public enum CodexHooksInstaller {   // 写 ~/.codex/hooks.json
    public static func isInstalled(hooksURL: URL? = nil) -> Bool
    public static func install(hooksURL: URL? = nil, port: Int = ClaudeHooksInstaller.defaultPort) throws
    public static func uninstall(hooksURL: URL? = nil) throws
}

public enum CursorHooksInstaller {  // 写 ~/.cursor/hooks.json(扁平 entry + 顶层 version: 1)
    public static func isInstalled(hooksURL: URL? = nil) -> Bool
    public static func install(hooksURL: URL? = nil, port: Int = ClaudeHooksInstaller.defaultPort) throws
    public static func uninstall(hooksURL: URL? = nil) throws
}
```

行为约定(在 claude-code 约定基础上):

- `source == "codex"`(TaskCard "Cx" logo)/ `source == "cursor"`(TaskCard "Cu" logo)
- Cursor 只订阅 fire-and-forget 事件,没有 waiting 态;`stop.status == "error"` → failed,`"aborted"` → completed(phase "Aborted")
- Cursor 的会话键是 `conversation_id`(sessionStart/sessionEnd 上的 `session_id` 值相同)

---

## 声明式连接器框架(v1.5.0 新增,J3 冻结)

> 本地 agent 的唯一事实来源是注册表。B 侧(设置页列表改版)对接以下 API,
> 不再逐家 import 安装器;三个旧安装器 enum 保留为兼容壳,行为不变。

```swift
/// 所有本地 agent 的注册表 — 设置页按此渲染行(顺序即显示顺序)。
public enum LocalAgentRegistry {
    public static let all: [LocalAgentDescriptor]          // 当前: claudeCode, codex, cursor, geminiCLI
    public static func descriptor(for source: String) -> LocalAgentDescriptor?
}

/// 一个本地 agent 的全部元数据(一行表数据)。
public struct LocalAgentDescriptor: Sendable {
    public let source: String            // task.source / logo 资产键(AgentLogo-<source>)
    public let displayName: String       // "Claude Code"
    public let settingsSubtitle: String  // 设置行未启用时的副标题
    public let configPath: String        // "~/.claude/settings.json"(展示用,~ 未展开)
    public var configURL: URL            // configPath 展开 ~ 后的实际路径
    // 其余字段(hookEvents / hookEntryStyle / appCandidates / decodeEvent)
    // 为核心侧内部驱动用,B 侧无需触碰
}

/// 通用 hooks 安装器 — 设置页行的 Enable/Disable 直接调用。
public struct LocalHooksInstaller: Sendable {
    public static let defaultPort: Int   // 7824(原 ClaudeHooksInstaller.defaultPort 仍可用)
    public init(_ descriptor: LocalAgentDescriptor)
    public func isInstalled(configURL: URL? = nil) -> Bool
    public func install(configURL: URL? = nil, port: Int = Self.defaultPort) throws
    public func uninstall(configURL: URL? = nil) throws
}
```

行为约定:

- **B 侧设置页渲染循环**:`ForEach(LocalAgentRegistry.all, id: \.source)` → 每行用
  `LocalHooksInstaller(descriptor)` 做开关;当前 `SettingsView` 已按此实现,可直接参考
- 核心侧新增 agent 只改注册表,不会破坏 B 侧代码;设置页自动多一行
- Gemini CLI 注册项:`source == "gemini-cli"`,写 `~/.gemini/settings.json`,订阅
  `SessionStart / BeforeAgent / Notification / AfterAgent / SessionEnd`;
  `ToolPermission` 通知映射 waiting,`AfterAgent` 映射 completed。官方当前没有可靠的
  failed 事件,因此不推断失败态
- 三个旧安装器(`ClaudeHooksInstaller` / `CodexHooksInstaller` / `CursorHooksInstaller`)
  是注册表的薄兼容壳,API 与行为不变,新代码不要再用
- `LocalAgentConnector` 是唯一的本地连接器实现(表驱动);`ClaudeCodeConnector` /
  `CodexConnector` / `CursorConnector` 三个类型已删除(它们从未进入契约)

---

## 变更记录

| 日期 | 版本 | 描述 | Commit |
|---|---|---|---|
| 2026-04-24 | v1.0.0 | 初始版本 | `[S][contract] feat(store): initial TaskStore API` |
| 2026-07-28 | v1.1.0 | Claude Code 本地连接器(TaskStore API 不变) | `[S] feat(claude-code): local hooks connector` |
| 2026-07-28 | v1.2.0 | Codex 本地连接器:`CodexHooksInstaller`(API 形态同 `ClaudeHooksInstaller`,写 `~/.codex/hooks.json`),tasks 新增 `source == "codex"`,其余约定同 claude-code | `[S] feat(codex): local hooks connector` |
| 2026-07-29 | v1.3.0 | Cursor 本地连接器:`CursorHooksInstaller`(写 `~/.cursor/hooks.json`,扁平 entry + 顶层 `version: 1`),tasks 新增 `source == "cursor"`;仅订阅 fire-and-forget 事件(sessionStart / beforeSubmitPrompt / stop / sessionEnd),无 waiting 态;`stop.status == "error"` 映射为 failed | `[S] feat(cursor): local hooks connector` |
| 2026-07-29 | v1.4.0 | **契约冻结(J1/J2)**:新增 `TaskTransition` 结构与 `TaskStore.onTaskTransition` 回调(状态跃迁事件,通知投递用);新增 `TaskStore.jumpToTask(id:)`(app 级激活,失败回退 openTaskInBrowser 行为)。`openTaskInBrowser` 保持不变 | `[S][contract] feat: task transitions + jump-to-task` |
| 2026-08-03 | v1.5.0 | **契约冻结(J3)**:声明式连接器框架 — 新增 `LocalAgentRegistry` / `LocalAgentDescriptor` / `LocalHooksInstaller`(表驱动:设置行、hook 安装、服务器路由、跳回目标全部由注册表生成);三个旧安装器 enum 降级为兼容壳;三个旧连接器 actor 删除,统一为 `LocalAgentConnector`。`TaskStore` 公开 API 不变 | `[S][contract] feat: declarative local-agent framework` |
| 2026-08-05 | v1.5.1 | **加法式注册表扩展**:新增 Gemini CLI (`source == "gemini-cli"`,用户配置 `~/.gemini/settings.json`);复用 v1.5.0 描述符/安装器契约,`TaskStore` 公开 API 不变 | `[S][contract] feat(gemini): local hooks connector` |
| 2026-08-09 | v1.6.0 | **跨 agent 任务身份**:新增 `TaskIdentity(source,id)`、`AgentTask.identity`、source-aware open/jump API 与直接接收 `AgentTask` 的入口;旧裸 id API 保留兼容,遇到歧义拒绝执行;通知/列表/跳回统一使用复合身份 | `[S][contract] fix: source-aware task routing` |
