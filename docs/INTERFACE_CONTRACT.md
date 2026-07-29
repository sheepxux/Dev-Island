# IslandCore Interface Contract

> 最后更新: 2026-04-24 | 版本: v1.0.0
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

    /// 通过 Manus API 停止任务。
    public func stopTask(id: String) async throws
}
```

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
