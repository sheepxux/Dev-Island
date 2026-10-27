# Windows 协作者计划

> 协作者：[@Liu-Chen787](https://github.com/Liu-Chen787)（仓库 write 权限）
> Owner：[@sheepxux](https://github.com/sheepxux)
> 起草：2026-10-27

Dev Island 是 macOS 刘海应用（SwiftUI / AppKit），在 Windows 上不能编译也不能运行。
这份计划只安排不需要 Mac 的工作，并说清楚每一项交付后由谁接手。

## 一、为什么需要你

产品目前有五个 **Preview** 连接器卡在同一个地方：Owner 的 Mac 上没有装好并登录的真实 CLI，
所以代码只能用“想象出来的”事件数据测试。这五个 CLI 在 Windows 上都能装：

| 连接器 | 固定版本 | 调研笔记 |
| --- | --- | --- |
| Gemini CLI | `@google/gemini-cli@0.57.0` | [`gemini-cli-hooks-notes.md`](gemini-cli-hooks-notes.md) |
| Qwen Code | `@qwen-code/qwen-code@0.22.0` | [`qwen-code-hooks-notes.md`](qwen-code-hooks-notes.md) |
| GitHub Copilot CLI | `@github/copilot@1.0.80` | [`copilot-cli-hooks-notes.md`](copilot-cli-hooks-notes.md) |
| Kimi Code CLI | `@moonshot-ai/kimi-code@0.38.0`（Node ≥ 22.19） | [`kimi-code-hooks-notes.md`](kimi-code-hooks-notes.md) |
| OpenCode | `opencode@1.18.23` | [`opencode-plugin-notes.md`](opencode-plugin-notes.md) |

你抓回来的**真实事件数据**能直接回答“我们的假设对不对”。这件事优先级最高。

> [`ROADMAP.md`](ROADMAP.md) 曾把这五个连接器冻结，原因是 Owner 一个人顾不过来。
> 现在由你推进证据采集，冻结只针对 Owner 的投入。

## 二、分工

| 你（Windows） | Owner（Mac） |
| --- | --- |
| 装真实 CLI、登录、按清单跑场景 | 把你的时间线变成 `IslandCoreTests` 里的测试夹具 |
| 用捕获脚本记录事件的形状与时机 | 修正连接器的解码与状态映射 |
| 写证据报告，指出和调研笔记不一致的地方 | 在 Mac 上接着岛做最终真机验收、改 Preview 标签 |
| App 图标按 macOS 规范重制 | 生成 `.icns`、在 Dock / 菜单栏核对 |
| 中英文界面文案审校 | 合并、构建、签名、公证、发版 |

你的证据证明的是 **CLI 发出了什么、什么时候发**；
它不证明 Dev Island 在 Mac 上的安装、岛的显示或跳回终端。后者仍由 Owner 验收。

## 三、上手

1. 克隆：`git clone https://github.com/sheepxux/Dev-Island.git`
2. 从最新 `main` 开分支，命名 `feat/…`、`fix/…`、`chore/…`、`docs/…`。
3. 提 PR 到 `main`，Owner 审核后 squash 合并。`main` 有分支保护，不能直接 push。
4. 提交信息前缀沿用仓库约定：连接器证据和测试写 `[S]`，图标、文案、文档写 `[C]`。
   例：`[S] docs(evidence): capture Gemini CLI 0.57.0 hook timeline on Windows`
5. CI 跑在 GitHub 的 macOS 机器上，你的 PR 会自动编译和测试。
   CI 失败时把链接发给 Owner，不需要你在本地复现。
6. 不改 `IslandCore/`、`IslandAppLib/` 的 Swift 代码，除非事先和 Owner 说好。
   你的产出基本都在 `docs/` 和素材目录里。

## 四、任务 1：五个 CLI 的真实事件采集（优先）

### 4.1 捕获脚本

仓库里的 [`scripts/collab/capture-hook.mjs`](../scripts/collab/capture-hook.mjs) 代替 Dev Island 接收 Hook。
把它复制到 `C:\devisland-capture\capture-hook.mjs`，下面所有配置都指向这个路径。

- 原始数据存到 `%USERPROFILE%\devisland-capture\<agent>\raw\`。**这个目录绝不提交**，
  里面可能有提示词、代码和路径。
- `timeline.jsonl` 只保留**形状**：字段名、类型、字符串长度、少数枚举值（事件名、通知类型、状态等），
  ID 只留 8 位哈希（能看出“是不是同一个会话”，看不出原值）。这个文件可以提交。
- 脚本不输出任何内容、总是退出 0，所以 CLI 会照常弹出它自己的审批界面。

### 4.2 每个 CLI 的配置

**先备份你原来的配置文件**，测完再恢复。用一个没有敏感内容的空目录做测试项目，
提示词用 `say hi`、`run pwd` 这类无害内容。

下面每家只给一个事件的写法，其余事件照抄，只改事件名（命令里的事件名和配置里的键保持一致）。

**Gemini CLI**：`%USERPROFILE%\.gemini\settings.json`

```json
{
  "hooks": {
    "SessionStart": [
      { "matcher": "", "hooks": [
        { "type": "command", "command": "node C:/devisland-capture/capture-hook.mjs gemini SessionStart" }
      ] }
    ]
  }
}
```

事件：`SessionStart`、`BeforeAgent`、`Notification`、`AfterAgent`、`SessionEnd`。

**Qwen Code**：`%USERPROFILE%\.qwen\settings.json`，形状同 Gemini，每条命令加 `"timeout": 5000`（毫秒）。

事件：`SessionStart`、`UserPromptSubmit`、`PermissionRequest`、`Notification`、`Stop`、`StopFailure`、`SessionEnd`。

**GitHub Copilot CLI**：新建 `%USERPROFILE%\.copilot\hooks\devisland-capture.json`

```json
{
  "version": 1,
  "hooks": {
    "SessionStart": [ { "command": "node C:/devisland-capture/capture-hook.mjs copilot SessionStart" } ]
  }
}
```

事件：`SessionStart`、`UserPromptSubmit`、`Notification`、`Stop`、`ErrorOccurred`、`SessionEnd`，
外加 `PermissionRequest` 和 `permissionRequest` 各挂一条（见 4.3，这是 Copilot 最重要的问题）。
如果 Windows 上 `command` 字段不执行，查官方 Hooks reference 里 Windows 用的字段（例如 `powershell`），
这本身就是要写进报告的发现。

**Kimi Code CLI**：`%USERPROFILE%\.kimi-code\config.toml` 末尾追加

```toml
[[hooks]]
event = "SessionStart"
command = "node C:/devisland-capture/capture-hook.mjs kimi SessionStart"
timeout = 5
```

事件：`SessionStart`、`TurnStarted`、`PermissionRequest`、`PermissionResult`、`Stop`、`StopFailure`、`Interrupt`、`SessionEnd`。
使用默认引擎，不要设置 `KIMI_CODE_LEGACY_FLAG`。

**OpenCode**：新建 `%USERPROFILE%\.config\opencode\plugins\devisland-capture.js`

```js
import { record } from "file:///C:/devisland-capture/capture-hook.mjs";

export const DevIslandCapture = async () => ({
  event: async ({ event }) => record("opencode", event.type, event),
  "permission.ask": async (input, output) => record("opencode", "permission.ask", { input, output }),
});
```

只记录，不修改 `output`。

### 4.3 每家要回答的问题

所有 CLI 都跑这一组通用场景：

1. 新会话 → 一轮对话 → 正常结束 → 退出；
2. 恢复（resume）上一个会话；
3. 触发一次工具审批（例如让它执行 `pwd`），分别 **允许**、**拒绝**、**不理它等超时**；
4. 中途按 Ctrl+C 打断一轮；
5. 制造一次失败（断网、用错的 API key 或触发限流）；
6. 两个项目目录同时各开一个会话，确认会话 ID 不同；
7. 删除捕获配置后再跑一轮，确认 CLI 没有残留错误。

再额外回答每家的关键问题：

| CLI | 必须回答 |
| --- | --- |
| Gemini | `Notification` 的 `notification_type` 实际有哪些值？`ToolPermission` 是在原生审批弹出**之前**还是之后到？`AfterAgent` 最大有多少字节（我们的上限是 1 MiB）？`/hooks panel` 有没有解析警告？ |
| Qwen | `PermissionRequest` 是否包含 `session_id`、`tool_name`、`tool_input`？脚本什么都不返回时，是否回落到原生审批？`StopFailure` 带哪些字段？`permission_prompt` / `idle_prompt` 各在什么时候出现？ |
| Copilot | **`permissionRequest` 的完整输入长什么样**。官方文档没公布，这是岛内能不能做 Allow/Deny 的前提。另外：`ErrorOccurred` 的 `recoverable` 何时为 false？`Notification` 有哪些类别？ |
| Kimi | `PermissionRequest` 是否在原生审批界面**之前**到？允许、拒绝、取消三种情况都有 `PermissionResult` 吗？`StopFailure` 的错误类别有哪些？`TurnStarted` 有没有让输入变慢？ |
| OpenCode | 插件能否从全局目录被发现？`session.status` 的 busy / idle / retry 实际顺序？`permission.updated` / `permission.replied` 的时机？**`permission.ask` 的 input 和 output 形状**？ |

如果固定版本已经装不到，先测能装到的最接近版本，在报告里写清楚实际版本。
有余力时再用最新版跑一遍，标出字段变化。

### 4.4 交付格式

每个 CLI 一个 PR，目录 `docs/field-evidence/<agent>/`：

```text
docs/field-evidence/gemini-cli/
├── REPORT.md        报告
└── timeline.jsonl   从 %USERPROFILE%\devisland-capture\gemini\ 复制，只含形状
```

`REPORT.md` 模板：

```markdown
# <CLI> <实际版本> — Windows 事件证据

- 日期 / 系统：2026-xx-xx · Windows 11 xx · Node xx
- 登录方式：个人账号 / API key（不要写 key）

## 场景结果
| 场景 | 收到的事件（按顺序） | 备注 |
| --- | --- | --- |
| 新会话 → 一轮 → 结束 | SessionStart → BeforeAgent → AfterAgent | |

## 关键问题答案
（逐条回答 4.3 表格中这家的问题）

## 和调研笔记不一致的地方
（字段名、事件名、时机、Windows 特有行为）

## 没测到的
（以及原因）
```

提交前自查：`timeline.jsonl` 里不应出现任何真实文字内容，只有 `<string N>` 和 `<id xxxxxxxx>`。

建议顺序：**Copilot → Qwen → Gemini → Kimi → OpenCode**。
Copilot 和 Qwen 的答案能直接决定岛内能否做审批，价值最高。

## 五、任务 2：App 图标重制

Owner 已选定新图标的方向：米色机身、黑色屏幕、绿色像素字 `Dev_`。
直接使用前要按 macOS 规范重做：

- 画布 1024 × 1024，透明背景；机身居中、约 824 × 824，四周各留约 100 px；
- 拆成三层导出无损 PNG：机身、屏幕、`Dev_` 字形；
- **不要**自带高光、玻璃反光、斜面和投影，系统会自己加；
- 交付源文件（Figma / Sketch / SVG 任一）和分层 PNG，放到 `scripts/assets/app-icon/`；
- 附一张 16 px、32 px 缩略图对比，确认缩小后仍能认出“黑屏 + 一点绿”。

绿色只用在图标和品牌素材上。产品界面里的绿色表示“任务完成”，不作品牌色。
生成 `.icns` 和放进 App 由 Owner 在 Mac 上完成。

## 六、任务 3：文案审校

- 文件：`IslandAppLib/Resources/zh-Hans.lproj/Localizable.strings` 和 `en.lproj/Localizable.strings`；
- 规则见 [`LOCALIZATION.md`](LOCALIZATION.md)：只改等号右边的译文，不改键；产品名和厂商名不翻译；
- 重点看：生硬的直译、中英文含义不一致、过长导致岛上放不下的句子；
- 一次 PR 只改一类问题，PR 描述里列出改了哪几条、为什么。

## 七、以后可以接的

公开发布阶段（ROADMAP 的 M4）需要官网、演示视频和 Product Hunt / Hacker News 文案，都可以在 Windows 上做。
到那一步再单独排期。

## 八、不要做的事

- 不提交 `raw/` 目录、截图里的提示词、API key、token 或真实路径；
- 不索要、不保存签名证书、Sparkle 私钥和发布凭证，这些只在 Owner 的 Mac 上；
- 不用捕获脚本返回审批决定，它只观察；
- 不直接改 README / ROADMAP 里的“已支持”状态，转正由 Owner 在 Mac 验收后决定。

## 九、节奏

- 每完成一个 CLI 开一个 PR，不要攒着一次提交；
- 每周同步一次（30 分钟以内），对一下本文件的进度表；
- 卡住超过一天就在 PR 或聊天里说，附上卡住的那一步。

| 项目 | 状态 | PR |
| --- | --- | --- |
| Copilot CLI 证据 | 待开始 | |
| Qwen Code 证据 | 待开始 | |
| Gemini CLI 证据 | 待开始 | |
| Kimi Code 证据 | 待开始 | |
| OpenCode 证据 | 待开始 | |
| App 图标重制 | 待开始 | |
| 文案审校 | 待开始 | |
