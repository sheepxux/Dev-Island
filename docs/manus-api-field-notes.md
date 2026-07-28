# Manus API Field Notes

> 实测日期: 2026-04-25 | 以本文件为准，优先于官方文档。

---

## 认证（已验证 ✅）

- **Header 名**: `API_KEY: <key>`（不是 `Authorization`）
- **Base URL**: `https://api.manus.im`
- **Key 格式**: `sk-` 开头（非文档示例的 `mk_live_` 格式）

---

## GET /v1/tasks（已验证 ✅）

### 响应结构

```json
{
  "object": "list",
  "data": [ ... ],
  "first_id": "rpsI7KMI6hB4ftaldI4t4d",
  "last_id": "8WIKpC9kCyPz2FSbm1uZwD"
}
```

> ⚠️ 顶层键是 `data`，**不是** `tasks`。

### 任务对象结构

```json
{
  "id": "rpsI7KMI6hB4ftaldI4t4d",
  "object": "task",
  "created_at": "1777072176",
  "updated_at": "1777072212",
  "status": "completed",
  "model": "manus-1.6-lite-adaptive",
  "metadata": {
    "task_title": "查看我的ManusAPI",
    "task_url": "https://manus.im/app/rpsI7KMI6hB4ftaldI4t4d"
  },
  "output": [ ... ],
  "credit_usage": 33
}
```

### 关键字段说明

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | String | 任务 ID |
| `created_at` | String | **Unix 时间戳字符串**（非 ISO 8601！）|
| `updated_at` | String | 同上 |
| `status` | String | 见下方状态表 |
| `metadata.task_title` | String | 任务标题 |
| `metadata.task_url` | String | Manus 网页任务链接 |
| `output` | Array | 消息历史（v1 忽略）|
| `model` | String | 模型名（v1 忽略）|
| `credit_usage` | Int | 积分消耗（v1 忽略）|

### Status 值 → 我们的枚举映射

| Manus API status | AgentTask.TaskStatus |
|---|---|
| `pending` | `.running`（排队中）|
| `running` | `.running` |
| `completed` | `.completed` |
| `failed` | `.failed` |
| `paused` | `.waiting`（需要用户输入）|
| `stopped` | `.waiting`（被 ask 停止）|

---

## POST /v1/webhooks（待确认 ⚠️）

- 测试 URL 返回 400 Bad Request（body 为空）
- 可能原因：Manus 对 webhook URL 做可达性验证，测试 URL 无效
- **字段格式待实测**：使用真实 cloudflared URL 后验证
- 我们当前发送：`{ "url": "https://xxx.trycloudflare.com/webhook" }`

---

## DELETE /v1/webhooks/{id}（待确认 ⚠️）

- 尚未实测，待 webhook 注册成功后测试

---

## Webhook 事件（待确认 ⚠️）

- Header 名：`X-Manus-Signature`（猜测，待实测）
- 签名算法：RSA-SHA256（待实测）
- 事件 JSON 结构：待实测
  - 当前假设：`{ "event": "task_created", "data": { ... } }`
  - 实测后更新

---

## 已知问题

- `created_at` / `updated_at` 为字符串格式的 Unix 时间戳，JSONDecoder 的 `.iso8601` 策略不适用，需要手动 `Double(str)` 转换
- `task_title` / `task_url` 在 `metadata` 嵌套对象里，不在顶层
- 顶层列表键为 `data` 不是 `tasks`
