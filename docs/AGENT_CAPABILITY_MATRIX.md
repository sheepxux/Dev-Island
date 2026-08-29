# Agent capability matrix / Agent 能力矩阵

> Verified against the implementation and vendor evidence on 2026-08-27.
> “Observe” means Dev Island can surface a state; “Act” means it can return a
> documented decision to the agent from inside the island.

| Agent | Lifecycle | Permission / input | Act inside island | Usage / limits | Current transport |
| --- | --- | --- | --- | --- | --- |
| **Manus** | Task status and progress | Not exposed by the verified API integration | No | No verified source | HTTPS API, secure 60-second polling |
| **Claude Code** | Start, prompt, permission, question, plan review, notification, stop, failure, end | Full `PermissionRequest`, `AskUserQuestion` choices, and injected `ExitPlanMode` Markdown | **Yes — Allow/Deny + answers + Approve/Reject plan** | No verified content-free source | Matcher-scoped synchronous local hook → `127.0.0.1` |
| **Codex** | Start, prompt, permission, stop, end | Observe the complete `PermissionRequest` payload | **Yes — Allow once / Deny** | **Opt-in local provider windows + reset times** | Synchronous local hook → `127.0.0.1`; bounded official App Server check verifies exact Hook activation |
| **Gemini CLI — Preview** | Start, before-agent, notification, after-agent, end | Observe `Notification(ToolPermission)` | **No — return to Gemini CLI** | No verified source | Bounded passive local hook → `127.0.0.1`; real CLI acceptance pending |
| **Qwen Code — Preview** | Start, prompt, permission, attention notification, stop, failure, end | Full documented `PermissionRequest` payload | **Preview — Allow/Deny implemented** | No verified source | Synchronous local command hook → `127.0.0.1`; real CLI acceptance pending |
| **GitHub Copilot CLI — Preview** | Start, prompt, attention notification, stop, non-recoverable error, end | Observe permission prompts and elicitation dialogs with fixed private copy | **No — return to Copilot CLI** | No verified source | Dedicated personal Hook file → `127.0.0.1`; real CLI acceptance pending |
| **Kimi Code CLI — Preview** | Start, turn start, permission request/result, stop, failure, interrupt, end | Observe the real approval boundary with fixed private copy | **No — return to Kimi Code** | No verified source | Passive command Hooks in losslessly maintained TOML → `127.0.0.1`; real CLI acceptance pending |
| **OpenCode — Preview** | Created, busy/retry/idle, failure, delete | Observe permission requested/replied with fixed private copy | **No — return to OpenCode** | No verified source | Dependency-free global plugin → `127.0.0.1`; isolated fixture verified, real CLI acceptance pending |
| **Cursor** | Start, prompt, completed, aborted, failed, end | Not subscribed | No | No verified source | Local hook → `127.0.0.1` |

## Evidence and implementation depth

### Shared managed-configuration safety

- Every JSON, TOML, and complete-file plugin update uses the same
  descriptor-backed transaction boundary. Structured files are capped at
  4 MiB and the OpenCode plugin at 256 KiB. A safe symlinked config directory
  is resolved once and anchored for dotfiles compatibility; target symlinks,
  hard links, non-regular files, wrong ownership, dangling/unsafe parents,
  oversized input, and content drift detected before commit all fail closed.
- A write stages private bytes in the anchored directory, preserves an
  existing file's permissions (or creates a new file as `0600`), synchronizes
  the file, atomically renames it, and synchronizes the directory. Individual
  updates and Disconnect All use the same exact snapshot comparison and do
  not overwrite an external edit during rollback.

### Manus

- Evidence: [`manus-api-field-notes.md`](manus-api-field-notes.md), based on
  real API responses recorded by the project.
- Implementation: API key in Keychain, task list/progress reconciliation, and
  remote stop. Public webhook/tunnel startup is fail-closed until Manus'
  signing protocol and public-key trust anchor are verified end to end.
- Limit: no verified interactive approval response contract is implemented.

### Claude Code

- Vendor evidence: [Claude Code hooks](https://code.claude.com/docs/en/hooks).
- Implementation: the documented synchronous `PermissionRequest` is decoded
  into the same stable island queue as Codex and returns Claude Code's
  documented `decision.behavior` object. A matcher-scoped
  `PreToolUse(AskUserQuestion)` hook presents one to four documented choice
  questions inside the island and returns `permissionDecision: allow` with
  the original questions plus `updatedInput.answers`. The same scoped hook
  handles `ExitPlanMode`: it renders the injected Markdown, preserves the
  complete original `tool_input`, and returns that exact input with the
  documented allow decision only after **Approve plan**.
- Safety and fallback: duplicate question keys/options, unknown selections,
  over-limit forms, oversized/malformed plans, and mismatched responses fail
  neutral. “Continue in Claude” and timeout return `{}` immediately so Claude Code's
  native prompt remains the fallback. Plan contents remain in memory while
  pending and are not persisted. Other notification/elicitation forms remain
  observe-only.

### Codex

- Vendor evidence: [Codex hooks — PermissionRequest](https://learn.chatgpt.com/docs/hooks#permissionrequest),
  [Hook review and trust](https://learn.chatgpt.com/docs/hooks#review-and-trust-hooks),
  and [official Hook locations](https://learn.chatgpt.com/docs/config-file/config-advanced#hooks).
- Activation boundary: Dev Island first proves that its exact managed
  definition exists in `~/.codex/hooks.json`. It then starts only the
  OpenAI-signed Codex App Server executable for a bounded, read-only
  `hooks/list` check. **Connected** requires every exact Dev Island path,
  event, and command to be enabled and `trusted` or `managed`; every failure
  remains **Configured — review or confirm in Codex `/hooks`**. The probe does
  not inspect undocumented trust storage, change trust, start a thread, use a
  PATH shim, retain output, or take over an existing Codex runtime.
- Implementation: the hook remains synchronous for up to 95 seconds while
  Dev Island queues the request. The island shows the tool, reason, and
  command/input, then returns the documented `allow` or `deny` JSON. Timeout,
  cancellation, sleep, shutdown, and session end return `{}` so Codex keeps
  its native approval path.
- Verification: exact response-shape tests plus a real loopback HTTP round
  trip cover Allow, neutral fallback, required `X-Dev-Island-Hook: v1`,
  browser-Origin rejection, missing/wrong protocol or authorization Header
  rejection, listener-epoch credential rotation, and an OPTIONS preflight that
  receives no CORS authorization. Managed commands read the private credential
  through curl `-H @file`; the value is absent from config and argv.
- Usage insight: Settings can opt in to an on-demand, bounded read of recent
  local Codex rollout suffixes. Only provider-authored percentages, window
  lengths, reset timestamps, and event time cross into the UI. Missing or
  invalid data remains unavailable instead of being estimated. This path was
  verified against a real local Codex `token_count/rate_limits` event and has
  no network, Keychain, SQLite, logging, or background-polling dependency.

### Cursor

- Vendor evidence: [Cursor hooks](https://cursor.com/docs/hooks).
- Implementation: lifecycle-only observation with generation guards for
  asynchronously delivered events. `error` maps to failed and `aborted` maps
  to a quiet completed state.
- Limit: Dev Island does not subscribe to or answer gating hooks.

### Gemini CLI — Preview

- Vendor evidence: Gemini CLI v0.57.0
  [Hooks reference](https://github.com/google-gemini/gemini-cli/blob/6b0ae9a6c37aa117cc8b070d8b41c5bb4fa6d253/docs/hooks/reference.md),
  whose SHA-256 is unchanged from the prior v0.53.1 integration baseline.
- Implementation: five low-frequency lifecycle hooks map to Running, Waiting,
  Completed, and removal. Other notification types are ignored. The command
  uses explicit loopback/no-proxy routing, a two-second timeout, discarded
  output, and fail-open termination.
- Safety: the capability is code-gated as `observeOnly`; no synchronous action
  event or response codec exists, so the island cannot present a false
  Allow/Deny control. Install is merge-based and refuses malformed or
  incompatible existing settings without changing their bytes.
- Verification limit: implementation and simulated receiver/installer tests
  pass, but this Mac has no installed, signed-in Gemini CLI. A real v0.57.0
  lifecycle and `/hooks panel` acceptance remains required before promotion
  from Preview. See [`gemini-cli-hooks-notes.md`](gemini-cli-hooks-notes.md).

### Qwen Code — Preview

- Vendor evidence: `@qwen-code/qwen-code@0.22.0` at pinned commit
  [`e38665674e2978f98cd35e7c6f6eac057741647f`](https://github.com/QwenLM/qwen-code/tree/e38665674e2978f98cd35e7c6f6eac057741647f),
  including its Hook reference and TypeScript `PermissionRequest` types.
- Implementation: seven low-frequency lifecycle/attention events plus the
  documented synchronous structured Allow/Deny response. Qwen's millisecond
  command timeout is rendered independently from the second-based connectors.
- Safety: raw forward-extensible bodies are not retained or logged. Unknown
  fields are ignored; high-frequency assistant/tool-result events are not
  subscribed. Timeout, malformed content and app unavailability return `{}`.
  JSON installation is merge-based and surgical.
- Verification limit: fixture, installer and real loopback simulation tests
  pass, but no installed/signed-in Qwen CLI was available. It remains Preview
  until the recorded real acceptance checklist passes. See
  [`qwen-code-hooks-notes.md`](qwen-code-hooks-notes.md).

### GitHub Copilot CLI — Preview

- Vendor evidence: `@github/copilot@1.0.80` / `v1.0.80` at commit
  `ef627e1baad937d3c8da45f8a5541c6fc3c97b6a`, plus the official GitHub Docs
  Hook reference pinned at commit
  `be8d08aa6e3a95d7f531c6a00cbeff883e4e9814`.
- Implementation: six low-frequency PascalCase events map to Running,
  attention, Completed, categorical Failed, and removal. PascalCase selects
  the documented compatible payload carrying `hook_event_name`. Permission
  and elicitation notification text is replaced with fixed private copy;
  informational notifications and recoverable errors remain quiet.
- Config safety: Dev Island owns
  `~/.copilot/hooks/dev-island.json`, a version-1 personal Hook file. Install,
  update and uninstall preserve unrelated fields/commands; malformed,
  incompatible or wrong-version files remain byte-for-byte unchanged.
- Interaction limit: the official reference documents the
  `permissionRequest` response but not a complete input schema. Capability is
  therefore code-gated observe-only; the island cannot show a false
  Allow/Deny control. `preToolUse` is not used as a substitute because it
  would intercept ordinary tool execution.
- Verification limit: decoding, lifecycle, installer and real managed-command
  loopback tests pass, but no installed or signed-in Copilot CLI was available.
  See [`copilot-cli-hooks-notes.md`](copilot-cli-hooks-notes.md).

### Kimi Code CLI — Preview

- Vendor evidence: npm `@moonshot-ai/kimi-code@0.38.0`, Node `>=22.19.0`, at
  pinned release commit
  [`0999454bdcb5ddd98f39bffee434dcf0a810f394`](https://github.com/MoonshotAI/kimi-code/tree/0999454bdcb5ddd98f39bffee434dcf0a810f394).
  The default agent-core-v2 engine and its 20-event source contract are
  distinguished from the opt-in legacy engine.
- Implementation: Dev Island subscribes only to eight low-frequency events:
  `SessionStart`, observation-only `TurnStarted`, `PermissionRequest`,
  `PermissionResult`, `Stop`, `StopFailure`, `Interrupt`, and `SessionEnd`.
  Permission requests enter Waiting immediately and results restore Running;
  Kimi remains the only approval surface.
- Privacy: payloads may carry titles, prompts, tool input, permission display,
  error messages and future fields. The decoder retains only event, session ID,
  cwd and an allowlisted error category; all user/vendor text is replaced by
  fixed product copy before normalized task persistence.
- Config safety: `~/.kimi-code/config.toml` is syntax-validated with exactly
  pinned `swift-toml` 2.0.0. Dev Island never reserializes the document; it
  edits only explicit managed blocks. Comments, ordering, whitespace, unknown
  non-Hook fields and user Hooks survive byte-for-byte. Malformed TOML,
  incomplete markers, unwrapped legacy entries and unknown managed fields fail
  closed. JSON and TOML participate in the same prepare-first Disconnect All
  rollback transaction.
- Verification limit: decoding, lifecycle, privacy, lossless config fixtures,
  multi-source identity, terminal/tmux headers and a real managed-command
  loopback test pass. Kimi Code was not installed or authenticated on this Mac,
  so native UI timing, default-engine configuration reload and fallback still
  require a real `0.38.0` session. The opt-in `KIMI_CODE_LEGACY_FLAG` engine is
  outside this Preview contract. See
  [`kimi-code-hooks-notes.md`](kimi-code-hooks-notes.md).

### OpenCode — Preview

- Vendor evidence: OpenCode / `@opencode-ai/plugin` `1.18.23` at commit
  [`13c27598d35f6f91fa4763a0b61a220ab7fcb263`](https://github.com/anomalyco/opencode/tree/13c27598d35f6f91fa4763a0b61a220ab7fcb263),
  including the plugin interface and generated SDK Event union.
- Implementation: a dependency-free global plugin allowlists only
  `session.created/status/idle/deleted/error` and
  `permission.updated/replied`. It posts schema version, session ID, cwd and
  an allowlisted `busy/idle/retry` status to loopback. Retry remains Running;
  it never creates false human attention.
- Privacy and fallback: prompt/title/message/tool/permission metadata and raw
  errors never enter the envelope. Delivery is unawaited, aborts after one
  second and ignores failure, so an unavailable island cannot delay a turn.
  The upstream mutable `permission.ask` output is deliberately untouched.
- Config safety: Dev Island owns only the complete marked
  `~/.config/opencode/plugins/dev-island.js`. Unowned collisions, symlinks,
  directories, devices and files over 256 KiB fail closed; managed files use
  mode `0600`. Disconnect All can delete and rollback this file without
  overwriting an external recreation or dangling symlink.
- Brand and route evidence: the official square mark is pinned to the same
  upstream commit and SHA-256, then adapted only into an alpha template for
  Dev Island's theme; the MIT notice ships in the App. An ephemeral real
  Hummingbird listener verifies the registry-derived `/hooks/opencode` HTTP
  path, neutral `{}` response and privacy-minimal Waiting delivery.
- Verification limit: lifecycle/privacy/installer/rollback fixtures pass, but
  OpenCode was not installed or authenticated and the real global plugin
  directory was not changed. Discovery, reload, timing and native fallback
  remain unverified, so approval stays in OpenCode. See
  [`opencode-plugin-notes.md`](opencode-plugin-notes.md).

---

## 中文说明

- **观察（Observe）**：Dev Island 能知道 Agent 进入了什么状态，并在灵动岛里呈现。
- **操作（Act）**：用户可以直接在 Dev Island 里处理请求，而且程序会按照厂商公开的
  协议把结果返回给 Agent。
- 当前 **Codex 与 Claude Code PermissionRequest** 已达到双向操作深度；Claude Code
  的 `AskUserQuestion` 单选/多选可以直接回答，`ExitPlanMode` Markdown 计划也能在岛内
  审阅并批准或拒绝。其他 Elicitation 表单仍只观察，
  Gemini CLI 预览版只观察生命周期与权限等待、审批仍回原生 CLI 完成；Qwen Code
  预览版已按固定官方协议实现岛内审批，但尚未经过真实登录 CLI 验收；GitHub Copilot
  CLI 预览版只显示权限/输入注意力，所有操作仍回 Copilot 完成；Kimi Code CLI
  预览版观察真实权限请求/结果，但审批仍回 Kimi 完成；OpenCode 预览版通过隔离插件
  观察生命周期和权限注意力，但审批仍回 OpenCode 完成；Cursor 只观察生命周期，
  Manus 使用安全轮询同步远程任务。
- 能力矩阵只描述已经有官方或实测证据、并有测试覆盖的功能；不会因为某个 Agent
  “看起来可能支持”就提前标记为可用。
