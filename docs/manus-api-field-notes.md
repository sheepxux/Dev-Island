# Manus API Field Notes

> v1 账户实测：2026-04-25 · v2 官方契约复核：2026-08-26
>
> v1 章节记录旧版真实账户行为；Webhook 章节以 Manus 当前 v2 官方文档为准。
> 当前 Release 仍只启用已实测的 v1 轮询，v2 公网实时链路待同一真实账户完成端到端验收。

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

## 当前官方 Webhook API v2（文档契约已核对，真实账户待验收 ⚠️）

官方来源：

- <https://open.manus.im/docs/v2/webhook.create>
- <https://open.manus.im/docs/v2/webhook.list>
- <https://open.manus.im/docs/v2/webhook.delete>
- <https://open.manus.im/docs/v2/webhook.publicKey>
- <https://open.manus.im/docs/v2/webhooks-overview>
- <https://open.manus.im/docs/v2/webhooks-security>

### 注册、枚举、删除与公钥

| 操作 | 方法与 URL | 请求 |
|---|---|---|
| 注册 | `POST https://api.manus.ai/v2/webhook.create` | Header `x-manus-api-key`; body `{ "url": "https://…/webhook" }` |
| 枚举 | `GET https://api.manus.ai/v2/webhook.list` | Header `x-manus-api-key`; response `data[]` 每项含 `id`、`url`、`status`、`created_at` |
| 删除 | `POST https://api.manus.ai/v2/webhook.delete` | Header `x-manus-api-key`; body `{ "webhook_id": "…" }` |
| 验签公钥 | `GET https://api.manus.ai/v2/webhook.publicKey` | Header `x-manus-api-key`; response `public_key` + `algorithm: "RSA-SHA256"` |

- 注册前 Manus 会向回调地址发送测试请求；端点必须接收 JSON POST、10 秒内返回 200。
- 注册响应的 ID 位于 `webhook.id`，不是旧代码猜测的顶层 `id`；返回的 URL 必须与请求值逐字
  相同且状态必须为 `active`，否则不能接受 cleanup capability。
- `webhook.list` 是按账号鉴权的完整 Webhook inventory。客户端最多接收 1,024 项；每项 ID、
  canonical HTTPS URL、`active`/`inactive` 状态与非负 Int64 `created_at` 都要严格验证，重复 ID、
  缺字段、错类型、不安全 URL、超限正文或超限列表全部失败关闭。
- 删除响应必须是可解码 JSON 且 `ok == true`。HTTP 2xx 本身不确认删除；`ok:false`、缺失/
  错类型 `ok`、空正文或非法 JSON 都必须保留本地 webhook ID，供 credential-backed cleanup 重试。
  唯一例外是来自精确官方 origin、body 严格为 `ok:false` 且 `error.code == "not_found"` 的 404；
  它证明目标已不存在，可完成 crash-safe at-least-once delete。普通/畸形 404 仍失败关闭。
- 公钥通过固定官方 HTTPS 源按账号鉴权获取，仅在内存缓存一小时；不允许从环境变量或
  `UserDefaults` 注入。

### 签名协议

- Headers：`X-Webhook-Signature`、`X-Webhook-Timestamp`
- 算法：2048-bit RSA-SHA256，PKCS#1 v1.5
- 签名正文：`{timestamp}.{full_webhook_url}.{sha256_hex(raw_body)}`
- URL 必须是注册时的完整 HTTPS URL（包含 query）；不能用不可信 Host Header 重建。
- 时间戳与本机时间差超过 300 秒时拒绝。已验签 `event_id` 保留到该签名的精确
  `timestamp + 300s`；同 ID 的较新已认证 retry 会延长 expiry。1,024 个仍有效 ID 占满内存窗口
  时，新 ID 返回 503 失败关闭，不驱逐仍可重放的旧 ID；重复 ID 幂等返回 200。
- 缺失 Header、非法 Base64、过期时间戳、URL/正文被篡改或验签失败均 fail closed。
- 每个 replay trust generation 由 exact external URL 与 canonical RSA public-key identity 组成。
  RSA key 先由 Security.framework 导入，必须至少 2,048-bit，再从 canonical external bytes 计算
  SHA-256；同一 key 的 PKCS#1/SPKI PEM 表示不会清空 replay window。URL 或真实 key 改变才以
  原 capacity 原子 reset；非法 URL/key 不改变旧 verifier、URL、generation 或 replay state。
- 已在旧 generation 验签、但在 replay 登记前遇到 trust rotation 的请求返回 401 且零 delivery；
  旧 `event_id` 不进入新窗口，相同 ID 经新 tuple 签名后仍按首次 delivery 处理。
- 本机 transport 回归会启动真实 Hummingbird listener，并用 RSA-2048 签名的官方 v2 JSON 经
  loopback `/webhook` POST，证明首次 200/一次 delivery、重复 200/零新增 delivery、live capacity
  饱和时新 ID 503、饱和后最早 ID 仍未被驱逐。该测试不访问 Manus 或 Cloudflare，不能替代真实
  账号注册与公网投递验收。

### 事件结构

官方只登记两个生命周期事件，外层为：

```json
{
  "event_id": "task_stopped_task_abc123",
  "event_type": "task_stopped",
  "task_detail": {
    "task_id": "task_abc123",
    "task_title": "Example",
    "task_url": "https://manus.im/app/task_abc123",
    "message": "…",
    "attachments": [],
    "stop_reason": "finish"
  }
}
```

- `task_created`：`task_detail` 含 `task_id`、`task_title`、`task_url`。
- `task_stopped`：额外含 `message`、可选 `attachments`，以及 `stop_reason`：
  `finish`（完成）或 `ask`（等待用户输入）。
- 旧实现猜测的 `event/data` 外层与 `task_progress` 事件不属于当前官方契约，已移除。

### 当前安全门禁

- `ManusRealtimeTrust.liveV2AcceptanceComplete` 固定为 `false`。
- 正式 App 与真实验收 CLI 共用同一 API key 边界：16–512 字节可打印 ASCII，不固定
  provider prefix；换行、空白、控制字符、过短或超长值在网络调用前拒绝。
- `ManusAPIClient` 使用专用 ephemeral `URLSession`，不持久化 Cookie/缓存，15 秒请求与
  30 秒资源 timeout，不跟随任何 HTTP redirect；响应 scheme/host/effective port 必须与
  原请求一致，否则在解析前失败。
- v1 task ID 与 v2 webhook ID 只接受 1–256 字节 ASCII 字母/数字/`_`/`-`，防止 `/`、
  `..` 或 percent escape 改写已审查路由。注册回调只接受小写
  `https://<id>.trycloudflare.com/webhook`，且不得带凭据、端口、query 或 fragment。
- `Retry-After` 只接受有限数值并上限为 300 秒，服务端异常值不能让当前客户端无限暂停。
- v1 响应在 JSON decode 前固定为最多 1 MiB，单页最多 1000 个任务；task ID、Unix 时间戳、
  标题与 URL 都要通过独立入站策略，`GET task` 返回的 ID 必须与请求 ID 一致。task URL
  只能是无 userinfo/端口/query/fragment 且 ID 精确匹配的
  `https://manus.im/app/<task-id>`，否则不会进入 TaskStore 或 SQLite。
- v2 已验签事件仍不是可信 UI 数据：event ID、task ID、title、message、attachment 数量/
  名称/URL/size 都有明确 UTF-8 字节或数量边界，越界事件在 delivery 前拒绝。
- 用户点击任务时会重复执行目的地策略；Manus 不可打开 `file:`、自定义 scheme 或跨源 URL，
  本地 CLI 只能打开真实存在的普通目录，不能借任务 URL 启动文件或 App Bundle。
- 当前 Release 不绑定 WebhookServer、不启动 Cloudflare Quick Tunnel、不注册公网端点；
  Manus 继续使用每 60 秒一次的已验证 v1 API 轮询。已验证 credential 仍会装配一个内部
  `CleanupOnlyWebhookServer` + `TunnelManager` owner，读取 production preferences ledger；它不能开放
  listener、cloudflared 或 registration，只为 Disconnect/换 key 恢复历史 ID 删除能力。
- cleanup-only manager 还会恢复权威 `webhookRecoveryStateV1` envelope。它把 `webhookIds`、
  unresolved token、每次注册的 callback URL SHA-256、`startedAt` 与 `discoveredWebhookIDs` 放在同一
  versioned 单元内，并在每次修改后按 `set → synchronize → decode/readback → mirrors` 顺序确认精确
  字节；旧 `webhookId`、`webhookIds`、
  token 与 attempt 键仅为迁移/诊断镜像。损坏、超限、重复或交叉引用不一致会让 credential release
  继续失败关闭。
- start 与 credential-releasing stop 会共用一个账号级 `webhook.list` single-flight，只处理没有 live
  launch owner、尚未绑定 ID 的 attempt。归属必须同时满足：listed 状态为 `active`、完整 URL 的
  SHA-256 与持久 digest 精确相同、`created_at` 位于 `startedAt ± 300s`，并且同一 digest 只对应一个
  unresolved attempt。多个本机 marker 同 digest 时删除零项；inactive、窗外、无关或非法条目也永不
  删除。唯一 attempt 对应多个 exact provider matches 时全部绑定并清理。空 list 不能证明 create
  未发生，因此 marker 保留；list 失败同样保留。
- exact matches 的全部 ID 必须先与 attempt、authoritative ID ledger 一起写入同一 envelope 并
  readback，之后才能发出首个 delete。首次删除失败后，`discoveredWebhookIDs` 跨重启保留，后续
  start/stop 直接重试这些 ID，不再依赖 list；2xx + `ok:true` 或严格 official 404 `not_found` 成功后
  才逐项移除，最后一个 ID 清除时才解除对应 token/attempt。
- Manus 接受 registration 后，ID 会在任何后续 readiness/generation 检查前立即加入权威 envelope
  的 known-ID ledger；旧 `webhookId` / `webhookIds` 只做兼容镜像。初始化恢复并验证全部 ID；交错接受的
  多个 ID 不得彼此覆盖。所有遗留 ID 删除成功前，start/wake/heartbeat 都禁止 replacement。
- stop 会 join 已登记的 in-flight registration；晚到 accepted ID 先持久化、停止 process，再共享
  per-ID deletion operation。只有 2xx + `ok:true` 或严格 official 404 `not_found` 才清本地 ID；失败
  保留 ID 并可由后续 stop/start 重试。heartbeat cleanup 失败不启动 replacement，只降级
  polling-only。
- credential-releasing stop 在首次 await 前快照 entry-time deletion operations 与 attempt
  sequence，先让 transport 不可达，再 join 入口删除、registration 和晚到删除，最后处理
  本轮尚未真正尝试的 persisted sibling IDs。某个 joined ID 失败不能跳过其他 ID；
  入口时已在进行的删除结果未知时，不能提前释放 credential。即使并发路径没有
  传回具体 error，stop 仍必须执行 terminal gate：known ID、unresolved token、attempt、launch、
  deletion 与 listing ownership 全部为空，且 envelope 未标记 corrupt，才能成功。任一状态残留都
  fail closed 并保留 credential。
- Disconnect 先 detach 服务、移除 Manus live snapshots，在 credential 仍位于 device-only Keychain
  时 await 完整 remote cleanup。失败不调用 Keychain delete，保留 APIKeyStatus、credential 与
  cleanup owner；Core 只记录固定 `Remote callback cleanup pending; retry disconnect` reason，Settings
  将其本地化为 `Remote callback cleanup pending — retry Disconnect`，不暴露其他 raw reason。重试
  cleanup 成功后才允许删除 credential。Keychain 删除自身失败也不得显示 Not Configured。
- 新 Connect 必须先 join 已在进行的 Disconnect removal。替换已有 key 时，candidate 可以先完成
  list 验证，但旧 manager 必须用旧 credential 删除所有遗留 callback 后，candidate 才能写入
  Keychain；cleanup 失败时旧 key 与 cleanup owner 保留，candidate 不得产生任何持久覆盖。
- 旧 callback cleanup 成功后，必须先 detach 旧 tunnel/poller/connectors、移除 Manus
  snapshots 并收敛为 disconnected，再写 candidate。如果 Keychain save 失败，必须 read back
  真实持久状态：有 credential 为 Valid，无 credential 为 Not Configured，read-back 也失败时
  才保守保留旧 API state。candidate/旧服务都不得重启，后续 Configure/Disconnect 必须可恢复。
- 正常 Quit 使用可 await、memoized 的 `TaskStore.shutdown()`：首次 suspension 前 detach 所有
  ingress、中立恢复 action continuations 并标记 store terminal，然后 join 已有 Disconnect、sleep
  suspension、poller、tunnel、local listener start/retry/stop 和 bootstrap。已登记但尚未进入 body 的
  Disconnect 也必须被 terminal generation supersede/join，不得在 Quit 后删 Keychain；已入队
  local retry 必须先 join、再 stop server。任一 bootstrap/storage/provider await
  后都必须复查 terminal，不得在 Quit 后晚到恢复服务。结果只有 completed/cleanupPending；
  cleanup pending 不删 Keychain，并保留权威 `webhookRecoveryStateV1` envelope。
- `PollingFallback` 的 start/stop 必须保留 tokenized current + retiring poll operations，
  `LocalHookServer` 的 start/restart/retry/stop 必须保留 tokenized current + retiring serve/readiness
  operations。stop 必须 join 全部已 supersede 句柄，不能只等待最新 generation。
- AppKit 普通 owner 以 `.terminateLater` 等待上述事务，但 cleanup 与独立两秒 hard timeout
  竞争同一 finish-once token；失败/超时仍允许退出，credential + ledger 保留供下次启动。
  yielded duplicate、Performance QA 与 hermetic launch smoke 直接 `.terminateNow`，不构造
  `TaskStore.shared`。
- Settings 不再直接显示 `ConnectionStatus.degraded(reason:)` 的任意字符串。有效凭据的 degraded
  reason 只有三种固定、双语、低基数映射：polling-only、cleanup-pending 与未知失败；分别显示
  `Polling only — checking every minute`、`Remote callback cleanup pending — retry Disconnect`、
  `Connection unavailable — reconnect to retry`。connected/reconnecting/disconnected 也使用固定文案；
  菜单继续使用更紧凑的 `Manus: Connected / Polling only / Disconnected`，未知 reason、路径、
  credential 或 provider 错误不得进入 UI、辅助功能 value 或支持诊断。
- 真实 Hummingbird `/webhook` transport 回归除成功、幂等 retry 与 capacity 饱和外，还直接证明
  缺失签名、非法 Base64 签名及“用原正文签名后篡改 body”三种请求均返回 401，且 delivery count
  保持为零。TaskStore 回归另证明 Release gate 关闭时，成功轮询仍保持 polling-only degraded，
  同时保留既有 Codex 等本地 Agent 会话，不能用一次成功 poll 冒充 realtime connected。
- `IslandCoreCLI` 默认不触网；只有 `manus-live-acceptance` 子命令是显式真实账号验收入口。
  Key 使用交互式 TTY 隐藏输入，不从环境变量、参数、pipe 或重定向读取；默认 timeout 为
  600 秒，可选范围固定为 60–1800 秒。
- 验收必须依次证明公钥可用、注册期间的已验签 delivery、同一次运行的 `task_created`、
  `task_stopped(finish/ask)`、远端删除与本地 server/tunnel 停止。注册 probe 不计为真实任务；
  `finish/ask` 也不能由本轮未见过 created 的旧任务补齐。
- CLI 只输出低基数 checkpoint，不打印公共 URL、Webhook/Task/Event ID、payload 或 raw error。
  `Ctrl+C`、`SIGTERM`、timeout 与任意异常都会进入独立未取消 cleanup；注册结果不确定、拿不到
  ID 或删除失败时输出 `manual_webhook_review_required`，禁止声称清理成功。
- `scripts/qa/run-manus-live-acceptance.sh` 会在 T7 Shield 固定私有目录构建并复制本轮 CLI，
  记录构建前后完整输入闭包、binary SHA-256、commit/dirty 状态、CLI exit 与顶层 `SHA256SUMS`。
  Key 仍只经交互式 TTY 进入 CLI，不进入 wrapper、argv、环境、transcript 或证据元数据。
- build-input manifest 自动枚举全部 IslandCore/CLI Swift 源与 evidence tooling，不再依赖手写文件
  列表；同时把 `Package.resolved` 的每个 pin 绑定到 T7 SwiftPM workspace 中同 revision、clean、
  无 untracked/ignored file/submodule 的 checkout。构建前后两份 JSON 及 Swift/Xcode/SDK manifest
  必须逐字节一致，任何新增/删除/修改、缓存污染或工具链漂移都不能进入 CLI 运行。
- transcript 只接受四行固定前言、11 个唯一 checkpoint 与一个末行低基数 result；成功还要求
  signed probe 在 registration started/accepted 之间、同运行 created 早于 finish/ask、删除早于
  transport stop。验证器通过 no-follow descriptor 拒绝 64 KiB 以上、链接、多硬链接、可写权限、
  CRLF、重复/乱序、URL/ID/raw error 注入。只有 CLI exit 0 且 `--require-accepted` 通过才生成
  `ACCEPTED`；中断、失败和 manual review 证据不得冒充真实成功。
- cloudflared 只收到 `PATH`、`TMPDIR` 与可选 locale，不继承父进程 API keys、tokens、HOME
  或 DYLD 配置。
- 官方 `webhook.list` reconciliation 已实现不等于真实服务已验收；仍缺真实账号
  create → signed delivery → list/delete，以及 read-after-create/read-after-delete 一致性证据。
  未取得这些证据前不得宣称 realtime 可商用。
- 2026-08-30 对 T7 既有真实验收目录重新计数：5 个 run 目录中没有 `ACCEPTED`；2 次 build
  interrupted、2 次凭据被拒，另 1 个为空的预创建目录。因此当前唯一允许的 Release 声明仍是
  **polling-only fallback**，`ManusRealtimeTrust.liveV2AcceptanceComplete` 必须继续为 `false`。

---

## 已知问题

- `created_at` / `updated_at` 为字符串格式的 Unix 时间戳，JSONDecoder 的 `.iso8601` 策略不适用，需要手动 `Double(str)` 转换
- `task_title` / `task_url` 在 `metadata` 嵌套对象里，不在顶层
- 顶层列表键为 `data` 不是 `tasks`
- v1 任务 API 与当前 v2 Webhook API 使用不同 origin/header/响应结构；不得混用。
- v2 `task.list` 已有官方文档，但尚未用现有真实账号核验，因此本轮没有替换已工作的 v1 轮询。
