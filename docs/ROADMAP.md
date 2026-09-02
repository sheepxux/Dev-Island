# Dev Island 开发计划

> **产品定位(终局):Every Agent — one notch, one glance。**
> 目标覆盖 26+ 个 agent:Claude Code、Codex、ZCode、Gemini CLI、Antigravity CLI、Cursor、Trae、OpenCode、MiMoCode、Droid、Qoder、Qwen、Grok Build、Kimi Code、DeepSeek、Mistral Vibe、Copilot、CodeBuddy、WorkBuddy、Kiro、Hermes、Amp、Pi Agent、Oh My Pi、Gajae Code…
>
> **当前方向:先把产品做到足够好用、功能足够全面,变现后置。**
> **当前状态:v0.3.0 已发布，下一版本开发中** —— Manus + Claude Code + Codex + Cursor 四个已发布连接器；Gemini CLI、Qwen Code、GitHub Copilot CLI、Kimi Code CLI 与 OpenCode 已完成 Preview 实现和隔离配置安全测试，分别仍待真实 v0.57.0 / v0.22.0 / v1.0.80 / v0.38.0 / v1.18.23 登录会话验收。Kimi 已固定当前 `MoonshotAI/kimi-code` 默认 v2 引擎、真实权限请求/结果边界与无损 TOML 事务；OpenCode 已固定隐私最小事件插件与完整文件 ownership，但明确不修改 `permission.ask` output。PR CI、安全诊断、Codex/Claude 岛内审批、Claude Code `AskUserQuestion` 岛内回答、`ExitPlanMode` Markdown 计划审阅、会话历史、品牌状态音、精确终端/tmux 跳回、English / 简体中文全应用语言切换与源码覆盖门禁、Sparkle 签名更新底座已完成本地实现，仍待真机视觉/听觉验收、真实 tmux 会话验收、生产更新密钥和首个签名 Appcast 的跨版本验证。

### 当前优化目标（2026-09-02 校准：Vibe Island 方向）

> 产品方向转为 **Vibe Island**：面向同时开着三四个 Claude Code / Codex / Cursor 的 vibe coder。
> 他们不盯终端，只要三件事：谁现在需要我、一键回答它、今天替我干了多少活。
> 过去一周的投入几乎全在证据、门禁和商业底座上，而所有“真机验收”与“真实 CLI 验收”一项未勾；
> 评价标准从“门禁通过”改为“真实用户一周内打开岛、批准请求的次数”。

1. **先发版，再打磨：** 合入 PR #19，切 v0.4.0，找 10–20 个真实 vibe coder 用起来；owner 自己先当第一个用户，亲手过掉 Claude Code / Codex 的真机验收项。
2. **只做三家真实验收：** Claude Code、Codex、Cursor。Gemini CLI、Qwen Code、Copilot CLI、Kimi Code、OpenCode 五个 Preview 连接器**冻结**，不再投入模拟验证。
3. **岛是动手的地方：** 全局快捷键在任何 app 里直接 Allow / Deny 排在最前的请求；岛内审批、问答、Plan Review 保持最高优先级。
4. **按项目思考：** 展开面板按项目分组，任务卡显示项目名、分支与已运行时长。
5. **加一点 vibe：** 本地每日汇总（会话数、审批数、agent 运行时长）；用量洞察从 Codex 扩到 Claude Code 本地记录；状态音与点阵动效继续往“有性格”走。
6. **3 分钟点亮岛：** Welcome Tour 末尾给出“现在去终端跑这条命令”，首个真实事件到达时岛立刻变色。
7. **冻结商业化底座：** 商业授权、商业政策决策、商标审阅包全部停在 M5，公开发布前不再投入。
8. **改名在公开发布前一次做完：** Dev Island → Vibe Island 牵动 bundle id、域名、Sparkle appcast、Homebrew cask 与品牌资产，需 owner 决定域名与 bundle id 策略后统一执行。
9. **安全门不放松但不再扩建：** 已有的签名、公证、Sparkle、门禁保持；生产密钥、外部发布与付费政策仍须明确授权。

---

## 一、里程碑总览

| 里程碑 | 内容 | 出口条件(全部满足才算达成) | 对应发版 |
|---|---|---|---|
| **M0 地基** | v0.2.0 真机验收 | 验收清单 A 全绿,发现的 bug 已修复或立项 | — |
| **M1 价值闭环** | 通知 + 跳回会话 + onboarding | "不盯终端"承诺兑现:审批弹通知、点通知/任务卡直达会话;新用户 3 分钟内跑通第一个会话 | v0.3.0 |
| **M2 框架就绪** | 声明式连接器框架 + Wave 1 | 现有 3 连接器迁移为表驱动且回归全绿;Gemini 家族接入并通过 B 验收;设置页新列表上线 | v0.4.0 |
| **M3 矩阵铺开** | Wave 2 + Wave 3 + 分发 | 矩阵表内 ✅ ≥ 12 家;自动更新可用;Homebrew tap 可安装;48h 挂机稳定 | v0.5.0 |
| **M4 公开发布** | 落地页 + PH/HN 发布 | 官网上线、演示视频完成、发布日执行完毕、48h 值班响应 | v1.0.0-beta |
| **M5 变现**(后置) | license + 支付 | 触发条件:日活稳定 + M1 体验被用户反馈验证 | v1.0.0 |

> 表中的 `v1.0.0-beta` 是产品里程碑名称，不是当前流水线可直接发布的字面 tag。
> 当前 `VERSION`、两个 Apple bundle version 字段和 Sparkle 比较值共用数字三段式；真正的
> prerelease tag 必须先冻结独立 build number、升级顺序和 GitHub prerelease 策略，不能直接
> 把 `-beta` suffix 写进 Info.plist。

---

## 二、双轨并行原则与汇合点

两人**始终各自有事做、互不阻塞**,靠三条规则实现:

1. **契约先行**:A 的每个核心功能先出"契约 PR"(只改 `INTERFACE_CONTRACT.md`,冻结 API 形态),B 评审通过即可按契约并行开发 UI,不等 A 的实现落地。
2. **B 永不空转**:等待 A 接口期间,B 手上永远有独立任务(onboarding、视觉、Homebrew、官网)。
3. **汇合点即集成测试**:每个汇合点当天,两边分支都合入 main,当场跑真机联调;发现的问题谁的域谁修,24h 内闭环。

| 汇合点 | 触发时机 | A 交付 | B 交付 | 联调内容 |
|---|---|---|---|---|
| **J1** | 阶段 1 中段 | TaskStore 状态跃迁回调(契约冻结→实现合入) | 通知投递 + 点击唤起面板 | 真实会话触发通知全链路 |
| **J2** | 阶段 1 末 | 跳回会话 API(app 级激活) | 任务卡点击行为接入 | 三个 agent 各跑一次"黄灯→跳回→批准" |
| **J3** | 阶段 2 初 | 声明式框架 API 冻结 | 设置页新列表(分组+搜索)对接 | 现有 4 家在新列表下开关/状态全部正常 |
| **J4** | 每个 Wave 结束 | 该 Wave 连接器合入 | 该 Wave 真机验收 + logo | 验收清单 A 的连接器部分逐家过,B 签字 |
| **J5** | 阶段 3 初 | v0.5.0 发版产物 | 落地页 + 支持矩阵页 | 官网下载链接→安装→跑通全流程走查 |

---

## 三、阶段计划(双轨)

### 阶段 0:地基验收(两人一起,≈2 天)

唯一任务:对照「五、验收清单 A」在两台真机上把 v0.2.0 过一遍。发现的问题按域立 issue,阻塞项当场修。
**出口 = M0。**

### 阶段 1:好用 —— 价值闭环

> 主题:用户装上之后,"不用盯终端"这个承诺真正兑现。

| A(核心)轨 | B(产品)轨 |
|---|---|
| ① 通知回调契约 PR(J1 前置) | ① onboarding 三步引导(独立,先行) |
| ② TaskStore 状态跃迁回调实现:→completed / →waiting / →failed | ② 系统通知投递 + 设置页开关(按契约并行) |
| ③ ✅ 跳回会话:优先激活真实终端；tmux 精确到原 window/pane，失败安全回退(J2 前置) | ③ 通知点击 → 展开面板并高亮任务 |
| ④ ✅ LocalHookServer 端口占用降级、可见提示与手动恢复 | ④ ✅ 胶囊按注意力优先并显示总会话数 |
| ⑤ 休眠唤醒后本地管线健康检查 | ⑤ ✅ 任务卡点击行为接入跳回 API(J2 后) |

**汇合点:J1(通知链路)、J2(跳回链路)。出口 = M1,发 v0.3.0。**

### 阶段 2:全面 —— 连接器矩阵铺开

> 主题:"我用的 agent 它都支持",以及长期挂机不出幺蛾子。铺开策略与状态见「四、连接器矩阵」。

| A(核心)轨 | B(产品)轨 |
|---|---|
| ① 声明式框架:现有 3 连接器迁移为表驱动,API 契约冻结(J3 前置) | ① 设置页连接器列表改版:分组 + 搜索 + 状态徽标(J3 对接) |
| ② Wave 1:Gemini CLI + 衍生系(Qwen Code 等) | ② Wave 1 真机验收 + logo(J4) |
| ③ Wave 2:Claude 衍生系与国产 CLI(Kimi Code、DeepSeek、CodeBuddy、Qoder、ZCode、MiMoCode…) | ③ Wave 2 真机验收 + logo(J4) |
| ④ Wave 3:独立机制调研与接入(OpenCode、Copilot、Amp、Kiro、Trae…) | ④ Wave 3 真机验收 + logo(J4) |
| ⑤ ✅ Codex 集成边界调研：当前本地 Hook；未来可选 App Server client；无公开 Codex Cloud 任务监控 API | ⑤ Sparkle 自动更新接入（实现完成；待生产密钥与跨版本验收） |
| ⑥ 长期挂机稳健性:并发压测、TTL 复核、48h 内存观察 | ⑥ Homebrew tap 发布(独立) |
| ⑦ ✅ 全部本地 Hooks 一键安全清理（跨文件失败回滚） | ⑦ ✅ 本地历史删除控制 + 只读可搜索会话历史视图 |
| ⑧ ✅ Claude Code `ExitPlanMode` Markdown 计划审阅（批准/拒绝/原生回退） | ⑧ 计划审阅面板真机视觉、键盘与 VoiceOver 验收 |
| ⑨ ✅ 等待/失败/完成三种品牌状态音、并发防重叠与全局静音 | ⑨ 解锁后完成真机听感、专注模式与通知设置组合验收 |
| ⑩ ✅ Codex 本地只读用量/额度基础：来源标注、过期状态与失败隔离；其他供应商待验证数据源 | ⑩ ✅ 用量摘要默认关闭、按需刷新，只作低打扰信息且不进入注意力排序 |

**汇合点:J3(框架×列表,达成即发 v0.4.0 = M2)、J4(每 Wave 一次,全部 Wave 验收完发 v0.5.0 = M3)。出口 = M3。**

### 阶段 3:公开发布

| A(核心)轨 | B(产品)轨 |
|---|---|
| ① v0.5.0 → v1.0.0-beta 发版与流水线保障 | ① devisland.app 落地页(hero:15 秒状态流转录屏) |
| ② 发布日 issue 值班(技术侧) | ② 演示视频(60-90 秒)+ 支持矩阵页 |
| ③ 用户反馈的核心侧修复 | ③ Product Hunt / HN / X 发布执行 |

**汇合点:J5。出口 = M4。**

发布构建的本地安全底座继续按真实产物收紧：`BUILD_DIR` 不再直接承载半成品或触发对最终
App 的递归删除；production/Performance QA 都先在私有 sibling 暂存中完成依赖、签名和
Bundle 身份验证，再以同文件系统 rename 发布。路径、链接、冒名/损坏既有 App 与失败恢复
均进入 PR/tag 攻击门禁；这不替代后续 Developer ID、公证、真实 tag 和下载安装验收。

### 后置:变现(M5,时机成熟再启动)

安全底座已落地:默认禁用、仅公钥的 Ed25519 离线校验器、device-only Keychain、
provider-neutral 激活核心与攻击面测试；尚未配置生产公钥，也未改变当前免费版本行为。
Seller/Provider、价格、试用、设备、退款、离线与销售地区已进入机器可验证但仍未批准的
schema v1 决策记录，不能把占位方案直接当作已批准政策。选定方案后仍需完成法律/产品
决策和 provider sandbox 验收。
A:签发服务 + webhook + 激活/撤销/恢复链路;B:激活 UI + 购买跳转 + 定价与条款文案。

---

## 四、双人甘特图

> 起始日期为占位符,只表达**相对排期、并行关系与汇合点**,不承诺日历日期。GitHub 上自动渲染。

```mermaid
gantt
    title Dev Island 双轨开发甘特图(A=核心 / B=产品)
    dateFormat  YYYY-MM-DD
    axisFormat  %m-%d
    excludes    weekends

    section 阶段0 · 两人
    v0.2.0 真机验收(M0)          :m0, 2026-01-01, 2d

    section 阶段1 · A轨
    通知回调契约PR                 :a1, after m0, 1d
    状态跃迁回调实现               :a2, after a1, 2d
    跳回会话调研+实现              :a3, after a2, 3d
    端口降级+唤醒健康检查          :a4, after a3, 2d

    section 阶段1 · B轨
    onboarding 引导               :b1, after m0, 3d
    通知投递+设置开关(按契约)    :b2, after a1, 3d
    通知点击→面板高亮             :b3, after b2, 1d
    胶囊多会话计数                 :b4, after b3, 2d
    任务卡接入跳回API              :b5, after a3, 1d

    section 汇合点
    J1 通知链路联调                :milestone, j1, after a2, 0d
    J2 跳回链路联调·发v0.3.0(M1) :milestone, j2, after a3 b5, 0d

    section 阶段2 · A轨
    声明式框架+迁移3连接器         :a5, after j2, 3d
    Wave1 Gemini家族               :a6, after a5, 3d
    Wave2 Claude衍生+国产CLI       :a7, after a6, 5d
    Wave3 独立机制调研+接入        :a8, after a7, 5d
    云任务调研+48h稳健性           :a9, after a8, 3d

    section 阶段2 · B轨
    设置页列表改版                 :b6, after j2, 3d
    Wave1 验收+logo                :b7, after a6, 2d
    Sparkle 自动更新               :b8, after b7, 3d
    Wave2 验收+logo                :b9, after a7, 2d
    Homebrew tap + 会话历史        :b10, after b9, 3d
    Wave3 验收+logo                :b11, after a8, 2d

    section 汇合点
    J3 框架×列表联调·发v0.4.0(M2):milestone, j3, after a5 b6, 0d
    J4 矩阵验收完成·发v0.5.0(M3) :milestone, j4, after a9 b11, 0d

    section 阶段3 · A轨
    v1.0.0-beta 发版保障           :a10, after j4, 2d
    发布日技术值班                 :a11, after a10, 2d

    section 阶段3 · B轨
    落地页+演示视频                :b12, after j4, 4d
    PH/HN/X 发布执行               :b13, after b12, 1d

    section 汇合点
    J5 官网全流程走查·公开发布(M4):milestone, j5, after a11 b13, 0d
```

阅读要点:

- **B 从不等 A**:J1 契约一冻结,B 的通知 UI 与 A 的回调实现同步推进;A 做框架迁移时 B 改设置页列表。
- **验收窗口错峰**:每个 Wave,A 转入下一波开发的同时 B 验收上一波 —— 流水线式推进。
- 甘特图是**相对排期**,实际以汇合点达成为准;某轨提前完成就从后置事项里拉任务,不空等。

---

## 五、分工与协作规则

沿用仓库既有的 `[S]` / `[C]` 双角色模式,边界是 `docs/INTERFACE_CONTRACT.md`:

| 角色 | 负责范围 | 代码域 |
|---|---|---|
| **A — 核心** `[S]` | 连接器框架与实现、事件管线、数据层、发布流水线 | `IslandCore/`、`IslandCoreCLI/`、`.github/workflows/` |
| **B — 产品** `[C]` | UI/UX、通知、上手引导、连接器实测验收、分发渠道 | `IslandAppLib/`、`IslandApp/`、`dist/` |

**连接器矩阵专项分工:**

| 环节 | 负责人 | 说明 |
|---|---|---|
| 声明式连接器框架 | A | 一个 agent = 一行声明(配置路径 + 格式家族 + 事件词汇表) |
| 每家机制调研 | A | 装真实 CLI 确认家族归属,更新「六、连接器矩阵」 |
| 同族 agent 声明配置 | A 写,B 复核 | PR 附 CLI 端到端记录 |
| 新机制家族攻坚 | A | 先出调研结论再排期 |
| 每家真机实测验收 | **B** | 对照验收清单 A 逐项过,**B 签字后才算"已支持"** |
| 设置页列表改版 / 每家 logo | B | 分组 + 搜索 + 状态徽标;品牌色块替代字母缩写 |
| README / 官网支持矩阵 | B | 对外只宣传 ✅ 的,未验收标 beta |

**协作规则:**

1. A 改动任何 IslandCore 公开 API,必须**同一个 PR 内**更新 `INTERFACE_CONTRACT.md`(版本号 + 变更记录表)。
2. B 只依赖契约文档编程,不直接读 IslandCore 实现细节做假设。
3. 所有变更走 PR → squash 合并 main(分支保护已开启,禁止直接 push main)。
4. 分支命名:`feat/xxx`、`fix/xxx`、`chore/xxx`;提交信息带 `[S]` / `[C]` 前缀标注责任域。
5. 每个汇合点做一次面对面联调;此外每周 30 分钟同步,更新本文档勾选状态。
6. 跨域改动由 A 先出核心 PR,合并后 B 基于 main 出 UI PR,**不搞叠 PR**(v0.2.0 期间叠 PR 被 GitHub 自动关闭过一次,教训)。

---

## 六、连接器矩阵(调研 + 状态总表)

> 状态流转:📋 待调研 → 🔬 调研中 → 🛠 开发中 → 🧪 待 B 验收 → ✅ 已支持 / ❌ 暂不可行(记录原因)
> "家族"指集成机制:`claude-hooks`(~/.xxx/settings.json 嵌套格式)、`gemini-hooks`、`cursor-hooks`(扁平 + version)、`api`(云端轮询/webhook)、`custom`(插件/其他)。

| Agent | 家族(预判) | 状态 | 负责 | 备注 |
|---|---|---|---|---|
| Claude Code | claude-hooks | ✅ | — | v0.2.0 |
| Codex | codex-hooks | ✅ | — | v0.2.0；写 `~/.codex/hooks.json` 后只标“已配置”，用户需在 Codex `/hooks` 审阅或确认当前哈希 |
| Cursor | cursor-hooks | ✅ | — | v0.2.0,含 stop.status→failed |
| Manus | api | ✅ | — | v0.1.x,轮询 + webhook |
| Gemini CLI | gemini-hooks | 🧪 | B | Preview 实现与模拟验证完成；待 v0.57.0 真机登录、Hooks panel 与端到端验收 |
| Qwen(Qwen Code) | qwen-hooks(JSON command/HTTP) | 🧪 | B | Preview 实现、官方 Logo、配置安全与双向回环模拟完成；待真实 v0.22.0 登录、Hooks UI/debug 与端到端验收 |
| Kimi Code | kimi-hooks(TOML command) | 🧪 | B | Preview 固定 `@moonshot-ai/kimi-code@0.38.0` 默认 v2 引擎；八类低频生命周期/权限注意力、官方 Logo、parser 校验的无损 TOML、跨 JSON/TOML 回滚和真实 command→loopback 测试完成；审批保持 observe-only，待真实登录、配置 reload、原生审批/失败/中断与 UI 验收 |
| DeepSeek | 📋 | 📋 | A | CLI 形态待确认 |
| ZCode | 📋 | 📋 | A | |
| MiMoCode | 📋 | 📋 | A | |
| CodeBuddy | claude-hooks? | 📋 | A | |
| Qoder | 📋 | 📋 | A | |
| Trae | custom? | 📋 | A | IDE 形态,可能无 CLI hooks |
| OpenCode | plugin(TypeScript events) | 🧪 | B | Preview 固定 `1.18.23` / commit `13c2759…`；七类隐私最小生命周期/权限注意力、1 秒 fail-open、真实临时 loopback route、`0600` 完整文件 ownership、官方方形 Logo/SHA/许可与 Disconnect All 回滚完成；`permission.ask` output 明确不修改，待真实发现/reload/登录/回退/UI 验收 |
| Copilot CLI | copilot-hooks(versioned JSON command) | 🧪 | B | Preview 固定 v1.0.80；独立个人 Hook 文件、低频生命周期/注意力、官方 Logo 与配置安全/回环测试完成；权限请求输入 schema 未完整公开，保持 observe-only，待真实登录验收 |
| Amp | 📋 | 📋 | A | |
| Droid | 📋 | 📋 | A | |
| Kiro | custom? | 📋 | A | IDE,自有 agent hooks 概念 |
| Grok Build | 📋 | 📋 | A | |
| Mistral Vibe | 📋 | 📋 | A | |
| Antigravity CLI | 📋 | 📋 | A | |
| Hermes | 📋 | 📋 | A | |
| Pi Agent | 📋 | 📋 | A | |
| Oh My Pi | 📋 | 📋 | A | |
| WorkBuddy | 📋 | 📋 | A | |
| Gajae Code | 📋 | 📋 | A | |
| ChatGPT / Codex 云 | api | ❌ | A | 2026-08-26 官方文档复核未发现可列出/监控既有 Codex Cloud 任务的公开 API；Responses background Webhook 不是 Codex Cloud session API，不混称支持 |

> 维护:A 每完成一家调研就更新本表;B 验收通过后把状态改成 ✅ 并注明版本。对外(README/官网)只宣传 ✅ 的。下一波排序、固定上游证据与逐项验收门见 [`NEXT_CONNECTOR_WAVE.md`](NEXT_CONNECTOR_WAVE.md)。

---

## 七、验收清单

### A. v0.2.0 真机验收(M0,阶段 1 开工前必须全过)

**安装与启动:**
- [ ] 从 Releases 下载 `Dev-Island.zip`,解压拖入 /Applications,双击启动**无任何 Gatekeeper 警告**
- [ ] 菜单栏出现胶囊,鼠标悬停展开面板
- [ ] `spctl -a -vv -t exec "/Applications/Dev Island.app"` 输出 accepted / Notarized Developer ID

**三个本地连接器(每个都单独验证):**
- [ ] 设置页打开开关后,对应配置文件里出现我们的 hook 条目,且**用户原有条目原样保留**(`~/.claude/settings.json` / `~/.codex/hooks.json` / `~/.cursor/hooks.json`)
- [ ] Codex 在 `/hooks` 中显示 Dev Island 当前定义；完成审阅/信任后再跑真实链路，Dev Island 配置文件诊断本身只能显示“已配置”
- [ ] 跑一个真实会话:开始 → 岛变蓝(running);结束 → 变绿(completed)
- [ ] Claude Code / Codex:触发一次权限请求 → 变黄(waiting),批准后恢复
- [ ] Cursor:agent 出错中断 → 变红(failed)
- [ ] 关闭开关后,配置文件里我们的条目被干净移除,用户条目仍在
- [ ] Dev Island 完全退出时,跑上述 CLI 会话**不卡顿、不报错**(fire-and-forget 验证)

**共存与恢复:**
- [ ] Manus(有 key 的话)与本地连接器同时显示,互不覆盖
- [ ] 断网状态下本地连接器照常工作
- [ ] 合盖休眠 10 分钟后唤醒,新会话事件仍能进岛
- [x] 自动占用随机回环端口验证不会误报 Ready；释放端口后手动重启立即恢复监听
- [ ] 解锁后目视验收 Settings 的重试/离线提示与 VoiceOver 文案

### B. 每个 PR 合并前(双方自查)

- [ ] `swift build && swift test` 本地全绿
- [ ] `scripts/qa/audit-github-repository-controls.sh` 通过，`main` 强制 PR review + CI，Actions allowlist/全 SHA pin 与 Dependabot security updates 已生效
- [ ] 改了 IslandCore 公开 API → `INTERFACE_CONTRACT.md` 同 PR 更新
- [ ] 新连接器 / 新功能 → 有单测;涉及 hook → CLI (`swift run IslandCoreCLI local-hooks`) 端到端跑过
- [ ] README 的状态表若受影响则同步更新
- [ ] PR 描述含 Test plan(照抄 #3/#5/#6 的格式)

### C. 每次发版(tag 前)

- [ ] `VERSION` 文件与 tag 一致(流水线会强制校验,不一致直接 fail)
- [ ] main 上 `swift test` 全绿
- [ ] `scripts/build-app.sh` 本地跑通,产物能启动
- [ ] tag 推送后盯流水线到 Release 产物出现(公证偶发排队 20+ 分钟属正常;403 协议错误 → developer.apple.com 重签协议)
- [ ] 从 Releases 下载产物做一次冒烟:安装、启动、开一个连接器
- [ ] Homebrew cask 的 sha256 同步更新(tap 发布后)

### D. 每个汇合点(J1-J5,联调当天)

- [ ] 两轨分支均已合入 main,CI 全绿
- [ ] 真机联调按该汇合点的「联调内容」执行并记录结果
- [ ] 发现的问题按域立 issue,24h 内闭环或明确降级方案
- [ ] 若为发版汇合点(J2/J3/J4),执行清单 C

---

*维护约定:本文档随每个汇合点与每周同步更新;阶段与排期调整走 PR 讨论。*
