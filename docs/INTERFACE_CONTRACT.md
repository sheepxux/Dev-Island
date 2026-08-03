# IslandCore Interface Contract

> 最后更新: 2026-07-29 | 版本: v1.4.0
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
    public func openTaskInBrowser(id: String)

    /// 跳回任务所在的会话(v1.4.0 新增,J2 交付)。
    /// 能解析出来源 app 时做 app 级激活(cursor → Cursor.app);
    /// 解析不出或激活失败时回退到 openTaskInBrowser 的行为
    /// (本地任务 → Finder 打开项目目录,Manus → 浏览器)。
    public func jumpToTask(id: String)

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
| `.running` → `.completed` | 通知「任务完成」(可选,默认开) |
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
- `openTaskInBrowser` 由 C 调用 `TaskStore.openTaskInBrowser(id:)`,不是通过 AgentConnector

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

## 变更记录

| 日期 | 版本 | 描述 | Commit |
|---|---|---|---|
| 2026-04-24 | v1.0.0 | 初始版本 | `[S][contract] feat(store): initial TaskStore API` |
| 2026-07-28 | v1.1.0 | Claude Code 本地连接器(TaskStore API 不变) | `[S] feat(claude-code): local hooks connector` |
| 2026-07-28 | v1.2.0 | Codex 本地连接器:`CodexHooksInstaller`(API 形态同 `ClaudeHooksInstaller`,写 `~/.codex/hooks.json`),tasks 新增 `source == "codex"`,其余约定同 claude-code | `[S] feat(codex): local hooks connector` |
| 2026-07-29 | v1.3.0 | Cursor 本地连接器:`CursorHooksInstaller`(写 `~/.cursor/hooks.json`,扁平 entry + 顶层 `version: 1`),tasks 新增 `source == "cursor"`;仅订阅 fire-and-forget 事件(sessionStart / beforeSubmitPrompt / stop / sessionEnd),无 waiting 态;`stop.status == "error"` 映射为 failed | `[S] feat(cursor): local hooks connector` |
| 2026-07-29 | v1.4.0 | **契约冻结(J1/J2)**:新增 `TaskTransition` 结构与 `TaskStore.onTaskTransition` 回调(状态跃迁事件,通知投递用);新增 `TaskStore.jumpToTask(id:)`(app 级激活,失败回退 openTaskInBrowser 行为)。`openTaskInBrowser` 保持不变 | `[S][contract] feat: task transitions + jump-to-task` |
