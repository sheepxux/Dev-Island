# Codex-Plan — Dev Island 进度与后续计划

> 写给继续开发的人(A 核心轨 / Codex / 朋友 B)。  
> 对照主文档:`docs/ROADMAP.md`、`docs/INTERFACE_CONTRACT.md`。  
> 快照日期:**2026-08-05** | 发版:**v0.2.2** | 契约:**v1.5.0** | 测试:**118 全绿**

---

## 一、现在在哪

### 产品现状

| 项 | 状态 |
|---|---|
| 最新 Release | [v0.2.2](https://github.com/sheepxux/Dev-Island/releases/tag/v0.2.2)(DMG 主推 + ZIP) |
| 已接入 agent | Manus(云) + Claude Code / Codex / Cursor(本地 hooks) |
| 本地管线 | `LocalHookServer` @ `127.0.0.1:7824`,与 Manus key 无关 |
| 声明式框架 | ✅ 已合入 main(PR #15),注册表驱动 |
| 品牌 logo | ✅ 四家均有模板 PNG(任务卡 + Settings) |
| 菜单栏图标 / 启动体验 / 悬浮手型 | ✅ v0.2.2 |
| 变现 | 后置,不动 |

### 汇合点状态

| 汇合点 | A(核心) | B(产品) | 结论 |
|---|---|---|---|
| **J1** 通知链路 | ✅ `TaskStore.onTaskTransition` 已合入 | ⏳ 系统通知投递 + 设置开关 **未做** | 核心就绪,等 B;未发 v0.3.0 |
| **J2** 跳回链路 | ✅ `jumpToTask` + `SourceAppResolver` 已合入 | ⏳ 任务卡点击接入 jump API **未做**(现多为 open/Finder) | 核心就绪,等 B |
| **J3** 框架 × 列表 | ✅ 契约 v1.5.0 冻结,框架合入 | ⏳ 设置页分组+搜索+徽标改版 **未做**(已能按注册表渲染行) | A 侧 J3 前置完成;完整 J3 等 B 列表改版后联调 → 才发 **v0.4.0** |
| **J4 / J5** | 未开始 | 未开始 | Wave / 公开发布 |

### 已合入的关键 PR(近期)

| PR | 内容 |
|---|---|
| #8 | 契约 v1.4.0:状态跃迁回调 + jump-to-session + 端口重试/唤醒健康检查 + Cursor generation 守卫 |
| #9–10 | DMG 作为主安装产物 |
| #11–13 | 状态栏图标、启动即展开面板/首启 Settings、v0.2.2 |
| #12 | 悬浮手型光标(`SetsCursorInBackground`)+ 按压/悬停反馈 |
| #14 | 每 agent 品牌 logo |
| #15 | **声明式连接器框架**(契约 v1.5.0,J3 冻结) |

开放 PR:仅 [#1](https://github.com/sheepxux/Dev-Island/pull/1) 旧 Notch Bar POC,可忽略/关闭。

---

## 二、A 轨已完成(可勾选复盘)

- [x] TaskTransition + `onTaskTransition`(J1)
- [x] `jumpToTask` / SourceAppResolver(J2)
- [x] LocalHookServer:端口退避重试、epoch、唤醒 `ensureRunning`
- [x] Cursor generation 守卫(乱序 stop/prompt)
- [x] 表驱动框架:`LocalAgentRegistry` / `Descriptor` / `Event` / `Connector` / `HooksInstaller`
- [x] Claude / Codex / Cursor 迁入注册表;旧 connector actor 删除;旧 installer 变兼容壳
- [x] Settings 本地行改为 `ForEach(LocalAgentRegistry.all)`
- [x] 契约文档写到 v1.5.0
- [x] 每家 logo 管道(`scripts/make-agent-logos.swift`)
- [x] DMG 发布流水线 + v0.2.2

**新增一家 agent 的标准动作(框架已就绪):**

1. 调研 hooks 配置路径 / 事件名 / entry 形状  
2. 加 `LocalAgentDescriptor` + payload → `LocalAgentEvent` 映射  
3. `LocalAgentRegistry.all` 登记一行  
4. `scripts/assets/agent-logos/<source>.svg` → 跑 `swift scripts/make-agent-logos.swift`  
5. 单测 + `IslandCoreCLI local-hooks` 端到端  

不必再改 `LocalHookServer` 路由、不必再写新 connector actor、不必手改 Settings 行。

---

## 三、B 轨待办(阻塞发版的部分)

这些不阻塞 A 继续接 Wave,但阻塞 **M1 / v0.3.0** 与完整 **J3 / v0.4.0**:

| 优先级 | 任务 | 依赖契约 |
|---|---|---|
| P0 | 系统通知:`onTaskTransition` → waiting/failed/(可选)completed | v1.4.0 |
| P0 | 通知点击 → 展开面板并高亮任务 | v1.4.0 |
| P0 | 任务卡点击 → `jumpToTask(id:)` | v1.4.0 |
| P1 | Onboarding 三步引导(可独立) | — |
| P1 | 胶囊多会话计数(`2▶ 1⏸`) | — |
| P1 | 设置页列表改版:分组 + 搜索 + 状态徽标(J3) | v1.5.0 `LocalAgentRegistry` |
| P2 | Wave 验收签字 + 新 agent logo 复核 | 每 Wave |

---

## 四、接下来做什么(建议顺序)

### 立即(A 轨,不等人)

**下一刀:Wave 1 — Gemini CLI(+ 同族如 Qwen Code)**

1. 调研 Gemini CLI 官方 hooks(配置文件路径、事件名、是否嵌套/扁平、session id 字段)  
2. 判定家族:`gemini-hooks` 新形状 vs 复用现有 `HookEntryStyle`  
3. 实现描述符 + 映射 + logo + 测试  
4. 真机 `local-hooks` 冒烟 → PR → 标 🧪 待 B 验收(J4)

验收出口(A 侧):注册表出现 `gemini`(或确定的 source key),118+ 测试绿,CLI 能收到 SessionStart→Stop 一类生命周期。

### 并行提醒 B

- 优先做通知 + jump 接入 → 两人约一次 **J1/J2 联调** → 可发 **v0.3.0(M1)**  
- 设置页分组搜索可跟 Wave 1 并行 → 联调后发 **v0.4.0(M2)**  

### 再往后(仍按 ROADMAP)

| 顺序 | A | 出口 |
|---|---|---|
| Wave 2 | Kimi / DeepSeek / CodeBuddy / Qoder / ZCode / MiMoCode… | 每家 J4 |
| Wave 3 | OpenCode / Copilot / Amp / Kiro / Trae…(独立机制先调研) | 每家 J4 |
| 稳健性 | 并发压测、TTL、48h 挂机、卸载一键清 hooks | 支撑 v0.5.0 |
| M3 | ≥12 家 ✅ + Sparkle/Homebrew(B) | **v0.5.0** |
| M4 | 官网 / PH(B) + 发版保障(A) | **v1.0.0-beta** |
| M5 | 变现(后置) | 日活稳定后再开 |

---

## 五、建议下一会话具体清单(A)

```
[ ] 装 Gemini CLI,抓真实 hooks 配置与一次完整会话 payload
[ ] 写调研笔记(可贴进 docs/ 或本文件附录):路径 / 事件 / entry 形状 / 与现有三家差异
[ ] 分支 feat/gemini-cli-connector
[ ] LocalAgentDescriptor.gemini + Event 映射 + Registry
[ ] logo SVG + make-agent-logos
[ ] 测试:decode / lifecycle / installer 形状
[ ] IslandCoreCLI local-hooks 注入验证
[ ] PR [S] feat(gemini): … → 合 main → 通知 B 验收
```

可选顺手(非阻塞):

- 关闭或归档 PR #1  
- ROADMAP 文首「当前状态 v0.2.0」改成 v0.2.2 + 框架已就绪  
- 矩阵表 Gemini 行改为 🔬 / 🛠  

---

## 六、关键代码入口

| 用途 | 路径 |
|---|---|
| 注册表 | `IslandCore/.../Connectors/Framework/LocalAgentRegistry.swift` |
| 描述符 / 安装器 / 通用连接器 | 同目录 `LocalAgent*.swift` / `LocalHooksInstaller.swift` |
| 现有三家映射范本 | `ClaudeCode/ClaudeCodeAgent.swift` 等 `*Agent.swift` |
| 契约 | `docs/INTERFACE_CONTRACT.md`(v1.5.0) |
| 主路线图 | `docs/ROADMAP.md` |
| Logo 生成 | `scripts/make-agent-logos.swift` |
| 本地调试服务器 | `IslandCoreCLI` → `local-hooks` |

---

## 七、风险与已知权衡

1. **J1/J2 产品侧未合**:用户仍可能「看不到通知 / 点卡片不跳回」——核心 API 已在,差 UI 接线。  
2. **Cursor 乱序 prompt**:generation 守卫不保证「两个 prompt 反序」;已文档化接受(人工间隔秒级)。  
3. **sessionEnd 后迟到事件**:无 tombstone,靠 TTL;与「中途启动仍应显示 lone Stop」设计一致。  
4. **商标 logo**:单色模板 PNG 来自 LobeHub 素材管道,仅作识别用途。  
5. **变现**:明确后置,本阶段不做 license / 支付。

---

## 八、一句话给下一个执行者

> 框架和 v0.2.2 体验已落地;**A 下一刀接 Gemini CLI**,**B 下一刀接通知+jump**;两边合上 J1–J3 再发 v0.3.0 / v0.4.0。
