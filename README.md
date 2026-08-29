<div align="center">

<img src="docs/media/logo-256.png" width="116" alt="Dev Island app icon">

# Dev Island

**Your agents. One quiet island.**

A calm, native macOS surface for every AI agent working in the background.<br>
把所有后台运行的 AI Agent，收进 MacBook 顶部的一座安静小岛。

<p><a href="#english">English</a> · <a href="#简体中文">简体中文</a></p>

<p>
  <a href="https://devisland.app"><img alt="Official website" src="https://img.shields.io/badge/Official_Website-devisland.app-111111?style=flat-square"></a>
  <a href="https://github.com/sheepxux/Dev-Island/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/sheepxux/Dev-Island?style=flat-square&label=Release&color=111111"></a>
  <img alt="macOS 14 or later" src="https://img.shields.io/badge/macOS-14%2B-111111?style=flat-square&logo=apple&logoColor=white">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/License-MIT-111111?style=flat-square"></a>
</p>

<a href="https://devisland.app">
  <img src="docs/media/dev-island-hero.png" width="960" alt="Dev Island monitoring Manus, Claude Code, Codex and Cursor sessions from the MacBook notch">
</a>

<p>
  <strong><a href="https://devisland.app">Download from devisland.app →</a></strong>
  &nbsp;&nbsp;·&nbsp;&nbsp;
  <a href="https://github.com/sheepxux/Dev-Island/releases/latest">GitHub Releases</a>
</p>

</div>

---

<a id="english"></a>

## English

AI agents keep working after you leave their window. That is useful—until one
needs approval, finishes quietly, or disappears inside a pile of terminals.

Dev Island keeps those sessions visible in one small surface around the
MacBook notch. It stays compact while work is moving, asks for attention only
when necessary, and lets you jump back to the exact app or project with one
click.

### The whole experience in six seconds

<div align="center">
  <img src="docs/media/status-priority-demo.gif" width="800" alt="Dev Island moving from a running task to an attention request and an expanded multi-session panel">
</div>

### Made to stay out of the way

| | Experience |
| --- | --- |
| **Glance** | See running, waiting, failed and completed work without opening another dashboard. |
| **Notice** | Receive a native notification with a short semantic signal when a session needs input or fails. Completion alerts and all signal sounds are optional. |
| **Return** | Open the island on the exact task, then jump back to its source app, captured terminal, tmux pane or browser. |
| **Understand** | Optionally view provider-authored Codex rate-limit windows and reset times from local activity—never an estimated quota. |
| **Focus** | Collapse to a quiet status surface. Reduced Motion is respected throughout the interface. |

The panel adapts to the number of sessions instead of reserving a large fixed
window. On Macs without a notch—or while using an external display—the
menu-bar item keeps the same controls within reach.

### Supported agents

| Agent | Interaction depth | Where data flows |
| --- | --- | --- |
| **Manus** | Remote status, progress and stop | Manus API; secure 60-second polling, key in Keychain |
| **Claude Code** | Lifecycle + **Allow/Deny, question answers, and Markdown plan review inside the island** | Matcher-scoped synchronous loopback hook (`127.0.0.1`) |
| **Codex** | Lifecycle + **Allow/Deny inside the island** | Synchronous loopback hook (`127.0.0.1`); a bounded, read-only official App Server check distinguishes configured Hooks from Hooks Codex has enabled and trusted |
| **Gemini CLI — Preview** | Lifecycle + permission attention; approval stays in Gemini CLI | Passive loopback hook (`127.0.0.1`); implementation and simulation verified, real CLI acceptance pending |
| **Qwen Code — Preview** | Lifecycle + documented **Allow/Deny inside the island** | Synchronous loopback hook (`127.0.0.1`); fixture and loopback verification complete, real CLI acceptance pending |
| **GitHub Copilot CLI — Preview** | Lifecycle + permission/input attention; actions stay in Copilot CLI | Privacy-minimal personal Hook (`127.0.0.1`); implementation and loopback verified, real CLI acceptance pending |
| **Kimi Code CLI — Preview** | Lifecycle + approval attention; approval stays in Kimi Code | Privacy-minimal passive loopback Hook with lossless TOML maintenance; pinned `0.38.0` default engine, real CLI acceptance pending |
| **OpenCode — Preview** | Lifecycle + permission attention; approval stays in OpenCode | Dependency-free global plugin posts a privacy-minimal allowlist to `127.0.0.1`; pinned `1.18.23`, real CLI acceptance pending |
| **Cursor** | Lifecycle observation | Loopback only (`127.0.0.1`) |

Local integrations need no Dev Island account and no API key. Enable one from
the Welcome Tour or **Settings → Connected Services**. Dev Island adds only
its own hook entries and preserves the rest of each tool's configuration.
Codex separately trusts each non-managed Hook definition by its current hash.
After setup, Dev Island briefly asks the OpenAI-signed Codex App Server for
Hook metadata on-device. It reports **Connected** only when every exact Dev
Island definition is enabled and `trusted` or `managed`; unavailable,
untrusted, modified, disabled, mismatched, or malformed results stay
**Configured** with a prompt to review `/hooks`. The check never changes trust,
starts a thread, uses a PATH shim, sends data over the network, or retains the
App Server response.
The loopback listener verifies that it owns the local port, retries bind
failures, and surfaces an explicit recovery control instead of failing
silently.
Managed terminal Hooks retain a bounded host/tmux hint only while a session is
live. Task clicks prefer the terminal that emitted the event and can select the
original tmux window and pane without shell interpolation or Accessibility
permission. The local tmux command has a strict output/deadline/process-group
boundary and does not inherit HOME. Ordinary non-tmux tab selection remains an
explicit future opt-in.
The evidence-backed implementation depth for every connector is documented in
the [Agent capability matrix](docs/AGENT_CAPABILITY_MATRIX.md).
Gemini CLI, Qwen Code, GitHub Copilot CLI, Kimi Code CLI and OpenCode remain
explicitly labeled Preview until real signed-in sessions pass their pinned
acceptance checklists. No Preview connector is counted as stable support based
on simulation alone. OpenCode's mutable permission decision hook is
deliberately unused; Preview approval remains in OpenCode.

**Local Usage Insights** in Settings is opt-in and currently supports Codex.
It scans a bounded number of entries, retains only the newest candidates, and
reads each exact initial suffix through a validated no-follow descriptor.
Concurrent growth cannot expand the read. It exposes numeric provider limits
and timestamps, and never uploads or persists the snapshot. Missing data stays
missing—Dev Island does not infer quota from token or task counts.

### Install

#### Official website — recommended

Visit **[devisland.app](https://devisland.app)**, download the latest DMG, open
it, and drag **Dev Island.app** onto **Applications**.

The public build is a Universal Binary for Apple Silicon and Intel. The app
and DMG are Developer ID signed, notarized by Apple, and stapled for offline
verification.

#### Direct download

- [Download the latest DMG](https://github.com/sheepxux/Dev-Island/releases/latest/download/Dev-Island.dmg)
- [Browse every release](https://github.com/sheepxux/Dev-Island/releases)

The Homebrew Cask is prepared in `dist/homebrew-island/`, but the public tap is
not live yet.

#### Build from source

Requires macOS 14 or later and a Swift 6 toolchain (Xcode 16 or later).

```sh
git clone https://github.com/sheepxux/Dev-Island.git
cd Dev-Island
swift test
./scripts/build-app.sh
open "build/Dev Island.app"
```

Local builds are ad-hoc signed for development. Public releases are signed and
notarized in GitHub Actions.

### First run

The three-step Welcome Tour explains the island, connects the local tools you
choose, and asks which events deserve notifications. Waiting, failure and
completion use distinct, restrained signal sounds delivered through macOS
Notification Center, so system Focus rules still apply. Sounds can be previewed
or muted in Settings.

The interface follows the Mac language by default. Choose **Settings → General
→ Language** to switch Dev Island itself between English and Simplified Chinese
without changing the system language or restarting the app.

Dev Island normally behaves like a lightweight menu-bar utility. Its Dock icon
appears only while a conventional window such as Welcome or Settings is open.

### Privacy by design

- Manus API keys are stored in macOS Keychain, not plain-text preferences.
- Local hooks send session and approval events only to a server bound to
  `127.0.0.1`; commands shown for approval never leave the Mac.
- The OpenCode Preview plugin forwards only schema version, event category,
  session ID, cwd and an allowlisted status. It excludes prompts, titles,
  messages, tool arguments, permission metadata and raw errors.
- Claude Code plans are rendered and decided locally. Plan Markdown and its
  injected tool input stay in memory only while the review is pending.
- Dev Island does not include an advertising or product-analytics SDK.
- Signed release builds use an authenticated Sparkle feed. Update checks send no
  system profile, can be disabled in Settings, and every feed and archive is
  verified with Ed25519 before installation.
- **Settings → Privacy & Support → Privacy Notice / Terms of Use** opens the
  exact bilingual review copies bundled with this app version, entirely
  offline. Only reviewed support-email and `devisland.app` links can leave the
  sheet.
- **Settings → Privacy & Support → Copy Diagnostics** exports aggregate status only;
  task content, paths, URLs, session IDs and API keys are excluded.
- **Settings → Privacy & Support → View History** opens a private, searchable list of
  recent Agent snapshots. Historical rows are read-only and never enter the
  live island's attention queue.
- **Settings → Privacy & Support → Clear History** removes persisted task and progress
  records after confirmation without interrupting active sessions.
- Manus currently uses periodic API polling. Public webhook delivery and the
  Cloudflare quick tunnel remain disabled until Manus' signing protocol and
  public-key trust anchor have been verified end to end. The implemented path
  cannot open a tunnel or register a callback until a private, bounded
  loopback challenge proves that this Dev Island process owns the listener.
- A local Agent can be disconnected individually, or all at once through
  **Settings → Agent Connections → Disconnect All…**. Only Dev Island command
  handlers are removed; user-owned settings and Hooks are preserved, and a
  cross-file failure rolls back without overwriting concurrent edits.

Read the canonical [Privacy Notice](PRIVACY.md), [Terms of Use](TERMS.md), and
[source-backed data-flow inventory](docs/DATA_FLOW_INVENTORY.md). These local
documents are engineering-reviewed drafts; the live website copy must be
updated separately before the next commercial release.

### Architecture

Dev Island is a Swift Package Manager project with a small AppKit shell around
native SwiftUI surfaces.

| Target | Responsibility |
| --- | --- |
| `IslandApp` | App lifecycle, menu-bar presence and window coordination |
| `IslandAppLib` | Island, panel, Welcome Tour, Settings, motion and notifications |
| `IslandCore` | Connectors, local hooks, persistence, Keychain and Manus sync |
| `IslandCoreCLI` | Headless integration and connector diagnostics |

Before a real Claude Code or Codex acceptance session, run
`swift run IslandCoreCLI local-live-readiness`. The read-only preflight checks
the reviewed CLI version, managed Hook state, Codex trust, and the running
App's loopback listener; it never repairs config or starts a session.

The shared UI/core contract lives in
[`docs/INTERFACE_CONTRACT.md`](docs/INTERFACE_CONTRACT.md). Connector work is
organized under `IslandCore/Sources/IslandCore/Connectors/`.
Performance claims follow the reproducible fixture and evidence rules in
[`docs/PERFORMANCE_QA.md`](docs/PERFORMANCE_QA.md).
The future commercial license boundary is documented in
[`docs/COMMERCIAL_LICENSE_SECURITY.md`](docs/COMMERCIAL_LICENSE_SECURITY.md);
it remains disabled and contains no production trust key.

### Contributing

Bug reports, focused improvements and new connector proposals are welcome.
Please open an issue before a large architectural change. Changes to
`TaskStore`'s public surface should update the interface contract in the same
pull request. Please report vulnerabilities through the private process in the
[Security Policy](SECURITY.md), not a public issue.

<p align="right"><a href="#dev-island">Back to top ↑</a></p>

---

<a id="简体中文"></a>

## 简体中文

AI Agent 的价值，在于你切走窗口后它仍然可以继续工作。但也正因如此，审批请求、
失败状态和已经完成的结果，很容易被埋在一堆终端与应用窗口里。

Dev Island 把这些会话集中到 MacBook 顶部的一块小界面中。任务正常运行时，它
保持安静；需要输入或操作时，它才提醒你；点击任务即可回到对应的应用、终端、
项目或浏览器页面。

### 六秒看懂 Dev Island

<div align="center">
  <img src="docs/media/status-priority-demo.gif" width="800" alt="Dev Island 从任务运行、需要输入到展开多会话面板的完整过程">
</div>

### 用完就安静地让开

| | 使用体验 |
| --- | --- |
| **一眼查看** | 不打开额外仪表盘，也能看到运行中、等待、失败和已完成的任务。 |
| **必要时提醒** | 会话需要输入或执行失败时发送系统通知与简短状态音；完成通知和全部状态音都可以单独关闭。 |
| **一键返回** | 通知会定位到准确任务，点击后可返回来源应用、实际终端、原 tmux pane 或浏览器。 |
| **了解额度** | 可选查看 Codex 在本机记录的厂商额度窗口与重置时间，不用任务数伪造“剩余额度”。 |
| **保持专注** | 平时收起为安静的状态条，并完整支持 macOS「减弱动态效果」。 |

展开面板会根据任务数量自动调整高度，不会长期占据一大块屏幕。在没有刘海的 Mac
或外接显示器上，也可以通过菜单栏图标使用相同功能。

### 已支持的 Agent

| Agent | 交互深度 | 数据流向 |
| --- | --- | --- |
| **Manus** | 远程状态、进度与停止 | Manus API；安全的 60 秒轮询，密钥存入钥匙串 |
| **Claude Code** | 生命周期 + **岛内审批、单选/多选问答与 Markdown 计划审阅** | 精确匹配的同步本机 Hook（`127.0.0.1`） |
| **Codex** | 生命周期 + **直接在岛内 Allow/Deny** | 同步本机 Hook（`127.0.0.1`）；通过有界、只读的官方 App Server 检查区分“已配置”与“Codex 已启用并信任” |
| **Gemini CLI — 预览** | 生命周期 + 权限等待提醒；审批仍回 Gemini CLI 完成 | 被动本机 Hook（`127.0.0.1`）；实现与模拟验证已完成，真实 CLI 验收待完成 |
| **Qwen Code — 预览** | 生命周期 + 按官方协议**直接在岛内 Allow/Deny** | 同步本机 Hook（`127.0.0.1`）；fixture 与回环链路验证完成，真实 CLI 验收待完成 |
| **GitHub Copilot CLI — 预览** | 生命周期 + 权限/输入提醒；操作仍回 Copilot CLI 完成 | 隐私最小化的个人 Hook（`127.0.0.1`）；实现与回环链路已验证，真实 CLI 验收待完成 |
| **Kimi Code CLI — 预览** | 生命周期 + 权限等待提醒；审批仍回 Kimi Code 完成 | 隐私最小化的被动本机 Hook + 无损 TOML 维护；固定 `0.38.0` 默认引擎，真实 CLI 验收待完成 |
| **OpenCode — 预览** | 生命周期 + 权限注意力；审批仍回 OpenCode 完成 | 无依赖全局插件只向 `127.0.0.1` 发送隐私最小化白名单；固定 `1.18.23`，真实 CLI 验收待完成 |
| **Cursor** | 生命周期观察 | 仅本机回环地址（`127.0.0.1`） |

本地连接器不需要注册 Dev Island 账号，也不需要 API Key。可以在首次欢迎引导，
或 **设置 → Connected Services** 中启用。Dev Island 只写入自己的 Hook 条目，
不会覆盖工具原有的其他配置。本机监听器会验证端口确由当前进程持有；发生端口冲突
时自动重试，并在设置中明确提示和提供恢复按钮，不会静默失效。
Codex 会按当前 Hook 定义的哈希单独记录非托管 Hook 的信任状态。配置后，Dev Island
只会在本机短暂调用 OpenAI 签名的 Codex App Server 读取 Hook 元数据；只有每个精确的
Dev Island 定义都已启用且状态为 `trusted` 或 `managed`，才显示**已连接**。不可用、
未信任、已修改、已停用、定义不匹配或响应异常时仍显示**已配置**，并提示前往
Codex `/hooks` 审阅。该检查不会修改信任、创建线程、执行 PATH 中的同名程序、联网，
也不会保留 App Server 原始响应。
受管终端 Hook 只在活跃会话期间保留有限的宿主与 tmux 跳回提示；点击任务会优先激活
真正发出事件的终端，并可在不调用 shell、不申请辅助功能权限的前提下选择原 tmux
window 与 pane。本机 tmux 命令具有严格的输出、截止时间和进程组边界，也不会继承 HOME。
普通非 tmux 标签页的精确选择仍保留为未来的显式授权能力。
每个连接器已经验证到什么深度、依据是什么，详见
[Agent 能力矩阵](docs/AGENT_CAPABILITY_MATRIX.md)。
Gemini CLI、Qwen Code、GitHub Copilot CLI、Kimi Code CLI 与 OpenCode 会一直
保留“预览”标记，直到真实登录会话通过各自固定版本的完整验收清单；不会因为模拟测试
通过就提前计入稳定支持。OpenCode 的可变权限决策 Hook 在预览阶段明确不使用，审批仍
回 OpenCode 完成。

设置中的 **Local Usage Insights** 默认关闭，当前仅支持 Codex。开启后只会按需读取
有限数量的最近本地 rollout 候选，并通过 no-follow descriptor 精确读取首次测量的有限
尾部；文件并发增长不会扩大读取。界面只显示厂商写入的数字额度与时间，不会上传、写入
Dev Island 数据库，也不会在数据缺失时根据 token 或任务数量猜测额度。

### 安装

#### 官网下载——推荐

访问 **[devisland.app](https://devisland.app)**，下载最新版 DMG，打开后将
**Dev Island.app** 拖入 **Applications（应用程序）** 文件夹。

正式版本同时支持 Apple Silicon 与 Intel。App 和 DMG 均使用 Developer ID
签名，已经通过 Apple 公证并附加离线验证票据。

#### 直接下载

- [下载最新版 DMG](https://github.com/sheepxux/Dev-Island/releases/latest/download/Dev-Island.dmg)
- [查看所有历史版本](https://github.com/sheepxux/Dev-Island/releases)

Homebrew Cask 已在 `dist/homebrew-island/` 中准备完成，但公开 Tap 尚未上线。

#### 从源码构建

需要 macOS 14 或更高版本，以及 Swift 6 工具链（Xcode 16 或更高版本）。

```sh
git clone https://github.com/sheepxux/Dev-Island.git
cd Dev-Island
swift test
./scripts/build-app.sh
open "build/Dev Island.app"
```

本地构建使用 ad-hoc 签名，仅供开发调试。GitHub 发布的正式版本会完成
Developer ID 签名和 Apple 公证。

### 首次使用

三步欢迎引导会介绍核心交互、连接你选择的本地工具，并让你决定哪些事件需要
通知。等待、失败和完成分别使用克制且可区分的状态音，并通过 macOS 通知中心
投递，因此仍遵循系统的专注模式；可以在设置中试听或一键静音。

界面默认跟随 Mac 的语言。可以在 **设置 → 通用 → 语言** 中单独切换 English / 简体中文，
无需修改系统语言，也无需重启应用。

Dev Island 平时是一款轻量的菜单栏工具。只有打开欢迎引导或设置等常规窗口时，
Dock 中才会显示应用图标。

### 隐私设计

- Manus API Key 保存在 macOS 钥匙串中，不会写入明文偏好设置。
- 本地 Agent Hook 只向绑定在 `127.0.0.1` 的本机服务发送会话与审批事件；
  审批界面展示的命令不会离开这台 Mac。
- OpenCode 预览插件只转发 schema 版本、事件类别、会话 ID、cwd 与白名单状态；
  prompt、标题、消息、工具参数、权限 metadata 和原始错误都不会进入该数据包。
- Dev Island 不包含广告或产品分析 SDK。
- 正式签名版本的自动更新使用经过认证的 Sparkle Feed，不发送系统画像，可在设置中关闭；Feed
  与安装包都必须通过 Ed25519 验签后才会安装。
- **设置 → Support → Copy Diagnostics** 只会复制聚合状态，不包含任务内容、
  路径、URL、会话 ID 或 API Key。
- **设置 → Support → View History** 会打开只保存在本机、可搜索的最近 Agent
  会话快照；历史记录只读，不会进入灵动岛的实时注意力排序。
- **设置 → Support → Clear History** 会在再次确认后删除持久化任务与进度记录，
  但不会打断或隐藏当前活跃会话。
- Manus 当前使用定时 API 轮询。只有完成签名协议与公钥信任锚的端到端验证后，
  才会启用公网 Webhook 与 Cloudflare Quick Tunnel。现有实现只有在随机、有界的
  loopback challenge 证明本 Dev Island 进程确实拥有监听器后，才允许启动 tunnel
  或注册回调。
- 本地 Agent 可以逐个断开，也可以通过 **设置 → Agent Connections → Disconnect
  All…** 一次清理。操作只移除 Dev Island 的 command handler，保留用户自己的设置
  与 Hook；跨文件失败会安全回滚，也不会覆盖操作期间出现的外部修改。

完整内容见 [隐私说明](PRIVACY.md)、[使用条款](TERMS.md) 与
[数据流清单](docs/DATA_FLOW_INVENTORY.md)。这些本地文件已完成工程事实核对；官网
页面仍需在下一次商业发布前单独同步。

### 项目架构

Dev Island 使用 Swift Package Manager 管理，由轻量 AppKit 外壳协调原生 SwiftUI
界面。

| Target | 职责 |
| --- | --- |
| `IslandApp` | App 生命周期、菜单栏与窗口协调 |
| `IslandAppLib` | 灵动岛、任务面板、欢迎引导、设置、动画与通知 |
| `IslandCore` | 连接器、本地 Hook、持久化、钥匙串和 Manus 同步 |
| `IslandCoreCLI` | 无界面集成测试与连接器诊断 |

开始真实 Claude Code 或 Codex 验收会话前，可运行
`swift run IslandCoreCLI local-live-readiness`。该只读预检会核对已审阅的 CLI 版本、
受管 Hook、Codex 信任和运行中 App 的本机监听器；它不会修复配置或创建会话。

UI 与核心层的公共约定记录在
[`docs/INTERFACE_CONTRACT.md`](docs/INTERFACE_CONTRACT.md)，连接器代码位于
`IslandCore/Sources/IslandCore/Connectors/`。
性能宣传必须遵循 [`docs/PERFORMANCE_QA.md`](docs/PERFORMANCE_QA.md)中的隔离环境与
原始证据要求。
未来商业授权的安全边界记录在
[`docs/COMMERCIAL_LICENSE_SECURITY.md`](docs/COMMERCIAL_LICENSE_SECURITY.md)；
当前仍为默认禁用状态，仓库中没有生产信任公钥。

### 参与贡献

欢迎提交 Bug、聚焦的小型改进，以及新连接器提案。大规模架构调整前请先创建
Issue。任何修改 `TaskStore` 公共接口的 PR，都应同步更新接口约定文档。
安全漏洞请按[安全政策](SECURITY.md)私下报告，不要先创建公开 Issue。

<p align="right"><a href="#dev-island">返回顶部 ↑</a></p>

---

## License / 许可证

Dev Island is released under the [MIT License](LICENSE).<br>
Dev Island 使用 [MIT 许可证](LICENSE)发布。

<div align="center">
  <sub>
    Native SwiftUI · Local-first connectors · Signed and notarized for macOS<br>
    <a href="https://devisland.app">devisland.app</a> ·
    <a href="https://github.com/sheepxux/Dev-Island/issues">Issues</a> ·
    <a href="https://github.com/sheepxux/Dev-Island/releases">Releases</a>
  </sub>
</div>
