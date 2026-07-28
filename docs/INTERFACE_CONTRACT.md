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

## 变更记录

| 日期 | 版本 | 描述 | Commit |
|---|---|---|---|
| 2026-04-24 | v1.0.0 | 初始版本 | `[S][contract] feat(store): initial TaskStore API` |
