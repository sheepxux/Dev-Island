# Dev Island Experience QA

体验结论必须来自当前源码和当前运行实例。旧截图、离屏 SwiftUI snapshot 或单元测试可以
作为回归证据，但不能单独证明真实窗口焦点、系统辅助功能、动画帧节奏或 Agent 端到端链路。

## 决策面验收顺序

1. 使用 `DEV_ISLAND_PERFORMANCE_QA=1` 的隔离 App 注入 Approval、AskUserQuestion 与
   Plan Review；不得触碰真实 Hook、SQLite、Keychain、Manus、通知和更新网络。
2. 记录原生窗口截图，并保存同一时刻的 AX 树。AX 至少应包含 `Dev Island` 窗口名、
   Agent/本地会话指纹、请求正文、选项状态、可用动作和倒计时。
3. 验证自动展开不改变前台编辑器；用户点击岛后，真实 key window 路由必须允许最早请求
   接收 `⌘↩`、`⌘D` 或 `⌘O`。Escape 只收起岛。
4. AskUserQuestion 逐项验证：未选时 Next disabled；单选替换；多选 toggle；Back 保留；
   缺任一答案不能提交；最终输出顺序与界面顺序一致。
5. 分别在系统 Reduce Motion 和 Increase Contrast 下人工检查。Reduce Motion 不得出现
   hover scale、空间滚动或持续点阵循环；Increase Contrast 应明显增强边界、正文和控件。

## 证据分级

- **代码/单测**：证明纯规则和回归边界，不证明真实窗口路由。
- **AX 树**：证明元素已暴露给辅助技术，不证明 VoiceOver 的实际朗读体验。
- **真实窗口键盘**：证明当前运行实例的焦点和快捷键路由，不证明所有键盘布局或系统版本。
- **截图/录屏**：证明视觉状态，不证明可访问名称、焦点、输入或动画帧率。
- **VoiceOver 与系统开关人工验收**：完成后才能声明对应 macOS 辅助功能体验已验收。

当前证据仍不得改写为 WCAG、VoiceOver 或“已完全商用合规”。

## 当前真实工作树复验

2026-08-29 的真实工作树复验已完成 629 项全量测试、checksum-identical T7 源码
快照构建、6 个 Universal Mach-O 依赖闭包、最小权限签名检查和 8 秒启动存活。
完整证据位于：

`/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/verification/real-worktree-release-v1-20260829/VERIFICATION_REPORT.md`

对应 App 仍为 keyless、ad-hoc 签名的 production-shaped 本地验证包，不能替代
Developer ID、公证、Staple、Gatekeeper、真实更新链路或真实 Agent 账户验收。
本次最终复验时屏幕处于锁定状态，因此同二进制视觉复抓、VoiceOver 以及系统
Reduce Motion / Increase Contrast 人工验收继续保留为明确未完成项。

## Reduce Motion 代码契约补漏（v6.30.0）

2026-08-29 发现“短 fallback 动画”仍会插值宽高、圆角与 scale，和只保留 opacity 的产品
契约不一致。当前源码已将 Reduce Motion 下的 bar↔panel 轮廓改为无动画几何切换，收起岛
hover 不再扩大占位，通用任务/图标按钮与 Welcome 连接动作不再 press-scale；普通模式的
300ms 无回弹 morph 保持不变。3 项纯策略回归、645 项全量测试与 Universal Debug QA 构建
均通过。由于显示会话仍为 locked，这只能证明实现和回归边界，不能改写为系统开关目视、
动画帧节奏、Increase Contrast 或 VoiceOver 实机验收已完成。

## 状态菜单实时摘要（v6.31.0）

状态菜单、状态按钮 tooltip 与 VoiceOver value 现在共用同一低基数快照：先呈现最需要用户
介入的状态，再明确追加全部会话数；本地监听器与 Manus 只显示稳定健康状态。TaskStore
变化通过 Observation 事件驱动刷新，不使用永久轮询 timer；最近完成状态只在最早到期边沿
安排一次可取消刷新。任务标题、Session ID、路径、URL 与原始错误不会进入这些表面。

8 项聚焦回归、648 项全量回归、完整安全/法律/发布门禁与 Universal Debug QA App 已通过。
由于当前显示会话为 locked，以下仍必须在同一 QA App 解锁后人工完成：

1. Waiting、Failed、Running、recent Completed 与 Idle 之间切换时，tooltip 和菜单首行同步，
   最近完成到期后只刷新一次且让位给仍在运行的会话。
2. 英文与简中切换后无需重启即可同步更新菜单、tooltip、AX value 与 AX help。
3. VoiceOver 实际朗读稳定名称、聚合 value 和“打开状态菜单”帮助；不得读出任务标题、路径、
   Session ID、URL 或 provider 错误。
4. Instruments/Activity Monitor 确认 idle 状态没有周期性菜单栏 polling wakeup。

## Dock 重试与测试调度隔离（v6.32.0）

Settings、Welcome 与 Debug Sandbox 的 Dock lease 语义没有改变：第一个常规窗口把 App 提升
为 regular，最后一个窗口关闭后恢复 accessory。生产 AppKit 写入失败仍只按 16/32/64 ms
重试三次；当租约变化使目标已经满足时，旧 generation 现在立即失效，不再留下无意义唤醒。

13 项 Dock 回归已移除 250 ms 墙钟等待，通过注入 scheduler 确定性排空；50 轮共 650 次通过。
同轮捕获的 Codex 进程 fixture 首次调度问题也已与 production 三秒边界分离，并连续五轮通过。
这些结果不能替代解锁后再次观察 Settings/Welcome 打开关闭、Dock 图标、Command-Tab 和焦点
交接；它们证明测试不会再因主线程或新子进程未及时获得调度而把正确行为误报为失败。

## GitHub 在线审计结果可信度（v6.33.0）

仓库控制在线审计现在把连接中断、认证失败、管理读取权限、限流与未知 API 故障明确分开；
失败只显示受控 endpoint 名称与一条低基数分类，`gh` 的原始 URL、账户信息和响应正文不会进入
终端或证据。fake-`gh` fixture 已覆盖 success、connection reset、401、403、404、rate limit
和 unknown，并用每类唯一 sentinel 验证零回显。

真实 GET-only 复核仍稳定返回六项远端设置缺口：required CI、PR review、conversation
resolution、Actions allowlist、full-SHA pinning 与 Dependabot security updates。这个结果证明
当前 snapshot 可读且离线 validator 工作正常；它没有修改 GitHub 设置，也不能替代管理员完成
设置后的复验。网络/认证/权限/限流分类本身不代表任何远端控制已通过或失败。

## 权威测试构建图隔离（v6.34.0）

PR CI、tag Release 与失败诊断现在通过同一入口使用 `.build/tests-authoritative`，不再让完整
测试与开发者默认 `.build`、Debug/Release App 或 Performance QA 共用 SwiftPM 数据库。全量
测试完成后，四组进程/生命周期压力回归都以 `--skip-build` 复用同一个测试二进制，因此最终
诊断仍只有一个权威 XCTest 总数。

fake Swift 已固定 66 次调用及其完整 scratch、filter 与轮数分布；真实验收仍必须运行 648 项
测试和全部 65 轮重复回归。该改动提升的是构建/测试可复现性，不改变 App UI，也不能替代真实
Agent、VoiceOver、sleep/wake、通知、声音或跨机器性能体验证据。

## 权威测试图并发所有权（v6.35.0）

同一 checkout 的权威测试运行现在覆盖 full suite 到最后一轮稳定性回归持有单一 BSD descriptor
lock。第二个入口不排队、不调用 Swift、不复用半构建产物，只返回固定错误；已有运行不被终止。
并发夹具真实暂停首个 fake full suite 并证明竞争路径在一秒内失败，释放后首运行仍完整产生
1+20+20+5+20 次调用。该工程证据避免把 `build.db` 卡顿误判为产品或测试失败，但不构成 App
视觉、交互、VoiceOver 或真实 Agent 链路验收。

## Welcome Tour 标题节奏（v6.36.0）

2026-08-29 用同一离屏状态对比发现：English 第 2 页的编辑栏仅 `232pt`，使
`Bring your agents together.` 被挤成三行，而第 1、3 页都是两行，翻页时视觉重心会上下跳动。
当前源码将编辑栏放宽到 `264pt`、栏间距收至 `28pt`，与左右 `32pt` 和右侧 `404pt`
精确组成 `760pt` 固定窗口。修复后第 2 页为 `Bring your` / `agents together.`，第 1、3 页
与简中三页仍无裁切，右侧 Agent 矩阵保持完整。

几何回归和 CI 静态门禁固定了全部常量、布局用法与总宽等式。离屏快照仍不能证明真实翻页
动效的帧节奏、hover/press、键盘焦点、VoiceOver 朗读或 Reduce Motion 切换；这些仍必须在解锁的
同一 QA App 上手工复验。

## 产品级 Increase Contrast 回归（v6.38.0）

此前只有岛内决策面显式处理 Increase Contrast，Welcome、Settings、History、展开岛边界、
安静文本和 idle 点阵仍使用固定灰阶。当前源码已将这些表面收敛到同一个
`InterfaceContrastPolicy`：标准外观继续保持近黑、低噪音层级，增强外观提高次级/三级文字、
分隔线、卡片边界和 idle 点阵的可辨识度；展开岛边界由 0.5pt 提升到至少 1pt。Running、
Waiting、Completed 与 Failed 的状态色保持克制，避免“高对比”退化成所有状态都发光。

本轮使用 DEBUG-only 强制入口从当前源码生成 39 组标准/增强同状态快照，全部尺寸一致，无裁切、
换行或几何漂移；三张人工复核拼图覆盖 Welcome/主岛、决策面/History 与简中 Settings。4 项
纯策略回归、652 项权威测试、20+20+5+20 轮稳定性与完整安全/法律/发布门禁均通过。证据位于：

`/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/product-contrast-v1-20260829/PRODUCT_CONTRAST_EVIDENCE.md`

强制 DEBUG 快照只证明同一渲染代码的两种视觉分支，不证明 macOS 系统设置通知、真实窗口重绘、
VoiceOver 朗读或用户主观可读性已经验收；显示会话仍为 locked，因此这些人工项继续保持未完成。

## 三种构建风味产物隔离（v6.39.0）

Production、Performance QA 与 Debug 现在不仅使用三个独立 SwiftPM scratch；构建脚本会在
lipo 后扫描实际 `IslandApp` 可执行文件。Production 同时拒绝 Performance 与 DEBUG-only
标记，Performance QA 精确要求三个性能标记且拒绝三个 Debug 标记，Debug 则反向要求三个
Debug 标记并拒绝全部性能标记。共享验证器的 18 个负向夹具逐个证明每项泄漏或缺失都会失败。

本轮从同一份 T7 源码分别生成三套真实 Universal App，并在最终输出目录再次独立验证：每套
均有 6 个 arm64+x86_64 Mach-O、完整依赖闭包、strict deep ad-hoc 签名和关闭的生产 Sparkle
通道；Performance QA 另使用隔离 Bundle ID 与 plist fixture 标记。首轮 Production 构建发现
APFS 克隆的 Swift module cache 仍引用旧绝对路径，构建正确失败；无效缓存和原始日志均保留，
随后用全新 private scratch 成功复现，未把缓存失败误写成产品或编译器缺陷。

652 项权威测试、20+20+5+20 轮稳定性、18 个负向 marker 夹具、完整安全/法律/发布门禁均通过。
证据位于：

`/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/build-flavor-isolation-v1-20260829/BUILD_FLAVOR_ISOLATION_EVIDENCE.md`

这组证据证明构建风味不会静默串线，不证明 Debug/Performance App 可分发，也不替代 Developer
ID、公证、Gatekeeper、真实 Agent、VoiceOver、系统辅助开关、通知、声音或动效实机验收。

## 离线法律文件体验（v6.40.0）

**Privacy & Support** 现在先呈现 Legal Documents，再进入诊断与历史动作。Privacy Notice 与
Terms of Use 都从签名 App 的 `Contents/Resources/Legal` 本地读取；不需要浏览器或网络，也不把
构建机路径、解析错误或法律正文写入日志。运行时会同时验证英文和简中两半，即使当前只展示一种
语言，另一半损坏也会整体 fail closed。Markdown 只允许两个已审阅 `mailto:` 与产品 HTTPS
origin 离开页面，其余相对路径、`file:` 或外部站点保留可读文字但不可点击。

本轮从当前源码生成并人工检查英文/简中 Support 页、英文 Privacy 与简中 Terms 共 4 张固定尺寸
快照；按钮基线、标题、正文层级、分隔线和页脚均无裁切或错位。首轮法律页快照暴露 XCTest 宿主
版本 `16.0` 污染证据，预览接口随后固定注入产品版本 `0.3.0` 并重新生成；首轮图不计入通过证据。
659 项权威测试、20+20+5+20 轮稳定性、10 类法律文件攻击夹具、完整安全/法律/本地化门禁和
T7 Release-shaped Universal App 构建均通过。证据位于：

`/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/bundled-legal-documents-v1-20260829/BUNDLED_LEGAL_DOCUMENTS_EVIDENCE.md`

这些离屏图不证明真实 sheet 点击、滚动、键盘焦点或 VoiceOver 朗读；ad-hoc QA App 也不是可分发
版本。两份法律文本仍是 owner/legal review draft，不代表律师批准、网站同步、购买同意或商业
政策已经完成。

## Welcome 最终决策页（v6.41.0）

本轮重新从当前源码捕获 English Welcome 三步，而不是复用旧画布或历史截图。Overview 与
Connections 的层级、几何和主要动作健康；Attention 最终页同时出现窗口关闭、Skip、Back 与
Start 四条离开路径，其中 Skip 与已进入完成决策的 Start 语义重复，让收尾显得没有定稿。

当前最终页只保留标准关闭、Back 与唯一 **Start Dev Island** 主动作；前两页继续保留低权重
Skip。改前/改后三页保持同一 `1520×1000` 2×尺寸，Overview 与 Connections SHA-256 逐字节
相同，只有 Attention 页变化。纯导航策略另固定负页码、单页流程与最终页均不显示 Skip。
660 项权威测试、20+20+5+20 轮稳定性与 T7 Release-shaped Universal App 构建通过。证据位于：

`/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/product-audit-v14-20260829/AUDIT_REPORT.md`

静态截图不能证明 280 ms 翻页过渡、真实点击、键盘焦点或 VoiceOver；这些仍保留为解锁实机项。

## App 内法律文件读取可靠性（v6.42.0）

本轮不改 Privacy / Terms 的排版、文字、入口或出站链接规则，只关闭运行时先检查 URL metadata、
再从路径另行读取的替换窗口。Settings 现在从一次 no-follow descriptor 完成 1–512 KiB 有界读取，
并在结束后同时复验 descriptor 与原路径的身份、权限、链接数、大小和时间戳；任何漂移继续只显示
固定重装提示，不暴露文件路径、errno 或法律正文。

正常单链接文件和 symlink、hardlink、group/other 可写 mode、大小上下界、打开后路径原子替换均有
确定性回归。666 项权威测试与 20+20+5+20 轮稳定性通过。该边界不改变可见几何，因此沿用 v6.40
已人工检查的法律页视觉基线；本轮重点证据是同源 Universal QA App 的真实启动、8 秒存活和干净退出，
而不是再生成一组像素相同的截图。证据位于：

`/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/security/legal-resource-reader-v1-20260829/LEGAL_RESOURCE_READER_EVIDENCE.md`

这仍是 ad-hoc 本地 QA，不替代 Developer ID、公证、Gatekeeper、律师审批、网站同步或购买同意。

## PR CI hermetic App 真实启动门禁（v6.43.0）

此前 PR CI 会构建并静态检查隔离 Performance QA App，但 loader、主运行循环 readiness 与普通
退出仍只存在于阶段性人工证据。当前 performance-build gate 会从本轮最终 App 建立私有
`CFFIXED_USER_HOME`，在 5 秒内等待 readiness，零 warmup 后连续保留 8 个一秒 idle 样本，
随后只对精确 launch PID 发出 AppKit terminate，并要求 5 秒内返回真实 exit status 0。
cleanup signal 只能回收失败运行，不能产生 `normal_termination=true`。

本轮真实 smoke 从包含空格的 `/Volumes/T7 Shield/...` 源码、App 与证据路径执行。首次运行暴露
分析器变量在命令位置未引用，导致 App 已正常启动/退出后分析阶段把 `T7 Shield` 拆成两个参数；
该失败作为 superseded 证据保留，没有改写成产品失败。当前脚本使用 `"$QA_ANALYZER"`，静态门禁
固定该引用形式，fresh App 的 readiness、8 个样本、正常退出与 summary 已全部通过。

锁屏状态仍被如实保留，因此这组证据只证明编译期 hermetic App 的依赖加载、readiness、8 秒
存活与正常退出；不能冒充 CPU/RSS 产品基线、首帧、动效、真实 Agent、VoiceOver、Developer ID、
公证或 Gatekeeper 验收。

## Performance 证据文件原子所有权（v6.44.0）

v6.43 的真实启动门禁暴露了第二个证据完整性问题：三条输出路径虽然先检查“不存在”，实际写入
仍通过后续普通重定向重新打开 final path，无法把“append-never”解释为并发安全保证。当前 sampler
在 App 启动前通过单次 noclobber `exec` 固定 CSV/App log/summary 三个 descriptor；文件必须为
当前用户 `0600` 单硬链接，path 与 descriptor 的 device/inode token 在 readiness、分析和 summary
结束后持续回绑。App、CSV 与 summary 后续都不再按路径重开写入。

统计分析另从公共 CSV 建立 `RDONLY|NOFOLLOW|NONBLOCK` reader，并要求与 writer token、owner、
mode、nlink、size、mtime、ctime 全部一致；单次有界 `pread` 的私有快照才进入多遍统计。含空格
路径、任一预存在目标、symlink、两个并发 claimant 只有一个 winner、reserve 后替换连同快照拒绝
共 5 类夹具连续 10 轮通过。随后从 v6.44 T7 源码快照全新构建 Universal Performance QA App：
6 个 Mach-O 均为 arm64+x86_64，依赖闭包、法律字节绑定、Performance marker、Plist 隔离与
strict deep ad-hoc 均通过。最终 8 样本 smoke 记录 readiness 1,517.2 ms、私有 HOME、正常
AppKit 退出和 status 0；666 项权威测试、20+20+5+20 共 65 轮稳定性及完整安全门禁同时通过。

该 smoke 仍发生在锁屏会话，只证明工具和 hermetic App 整合；CPU/RSS、首帧、动效与真实产品
体验结论继续使用既有解锁基线，不能由本轮锁屏数字替代。

只读证据：
`/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/performance-evidence-boundary-v1-20260829/PERFORMANCE_EVIDENCE_BOUNDARY_EVIDENCE.md`

## Performance readiness 私有快照（v6.45.0）

后续审计发现 readiness 轮询虽在公共 App-log 路径读取前后复验 writer token，`awk` 本身仍位于
两个校验之间：路径若在窗口中被替换为 FIFO 或超大文件，最终结果会失败，但文本读取可能先阻塞
或越过 1 MiB 边界。当前每轮改为 `RDONLY|NOFOLLOW|NONBLOCK` reader，绑定仍打开的 descriptor 8
device/inode 与稳定 metadata 后，单次有界 `pread` 到私有 sampler 目录；parser 只读取该快照。

Marker 现在必须尚未出现或恰好出现一次，并使用纯十进制 uptime；重复、malformed、反向时间和
超过 5.5 秒 launch window 全部失败关闭。含原有路径竞态以及 App-log FIFO、marker、时间窗口的
6 类夹具连续 10 轮通过。相同 fresh Universal Performance QA App 的真实 8 样本整合 smoke
先完成 preliminary 复验；随后从 v6.45 T7 源码快照重新构建最终 Universal App，6 个 Mach-O、
依赖闭包、marker/Plist 隔离、法律字节绑定与 strict deep ad-hoc 均通过。最终 smoke 记录
readiness 1,400.4 ms、私有 HOME、正常 AppKit 退出和 status 0；666 项权威测试、65 轮稳定性与
完整安全门禁通过。

本轮仍为锁屏整合证据，不支持 CPU/RSS、首帧、动效或真实产品体验宣称。只读证据：
`/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/readiness-log-snapshot-v1-20260829/READINESS_LOG_SNAPSHOT_EVIDENCE.md`

## Performance 输入 App 私有快照（v6.46.0）

继续审计发现，v6.45 虽把输出证据和 readiness 全部绑定到 descriptor，所选 Performance QA
App 仍先从公共路径完成检查/哈希、稍后再从同一路径 launch；路径在这两个动作之间被替换时，
summary 可能描述旧 executable，而实际启动另一个 Bundle。当前 sampler 将所选 App 降为纯输入：
主 executable 与 `Info.plist` 均通过 `RDONLY|NOFOLLOW|NONBLOCK` descriptor 做有界稳定 SHA-256，
strict deep 校验后以 `ditto` 冻结到随机私有 `0700` sampler root。只有私有 Bundle 会进入依赖
闭包、Performance marker、metadata 与 launch；来源和副本在启动前及正常退出后都重新绑定。

最终 7 类文件/App-input 夹具连续 10 轮通过。使用最终 App 的真实替换攻击在 readiness 后原子
替换来源 `Info.plist`：私有 App 仍安全完成，但 sampler 精确 exit 3、只输出固定错误，0-byte
summary 未发布。370 文件只读源码快照的 manifest SHA-256 为
`2aa50293ab6bba6c07035466a591ea6e80b9c025f712435e00b17a1df27bd006`；由独立 build workspace
全新构建的主 executable SHA-256 为
`3fc307e8ab4bb8ac2691373238f6ca98469b2d9f916f7d3961b0fd2d0e340d8d`。6 个 Mach-O、Universal
架构、依赖闭包、marker/Plist 隔离、法律字节绑定与 strict deep ad-hoc 全部通过。最终 8 样本
smoke 同时记录相等的 selected/private 哈希、`isolated_app_snapshot=true`、readiness 1,347.0 ms、
私有 HOME、正常 AppKit 退出和 status 0；666 项权威测试、20+20+5+20 共 65 轮稳定性与完整
安全门禁通过。

显示会话仍为 locked，因此 CPU/RSS 数字只验证 harness 整合，不能支持首帧、动效、VoiceOver、
能耗或真实产品丝滑度结论。只读证据：
`/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/performance-app-snapshot-v1-20260829/PERFORMANCE_APP_SNAPSHOT_EVIDENCE.md`

## PR CI Performance summary 进程内交付（v6.47.0）

v6.46 的 sampler 已保证 summary 写入期间 path/descriptor 一致，但 PR workflow 在 producer
退出后仍以 `grep`/`sed` 重开 runner 临时 summary。PR 中被测试的 App 本身属于不可信输入；若
错误或恶意 descendant 等待 sampler 退出后替换该文件，后续 CI 就可能验证另一组字节。当前
workflow 在 `set -euo pipefail` 下用带引号 command substitution 一次性捕获 sampler stdout，
全部 survival/sample/hash 断言只读 `performance_summary` shell 变量。App stdout/stderr 已固定
进入 descriptor 8，launch 时关闭 7/9，因此被测进程不能向 acceptance stream 注入输出。

静态门禁新增可替换 public summary 与独立 producer output 夹具，并拒绝 workflow 恢复任何
post-exit public-summary `grep`/`sed`。真实整合攻击使用最终 v6.47 Universal Performance QA App：
sampler 正常完成 8 samples 后，将已验证 summary 移走并在原路径写入
`normal_termination=false`、status 99、0 samples 和不相等哈希；已捕获变量仍精确保留正常退出、
status 0、8 samples、`isolated_app_snapshot=true` 与相等的 selected/private SHA-256，全部验收
通过。最终 App 主 executable SHA-256 为
`2a3961d26a1efc978cdb61bf4ef6fea095a79090878c368607544cd462ac68fe`，6 个 Mach-O、依赖闭包、
fixture/Plist 隔离、法律字节与 strict deep ad-hoc 全部通过；readiness 为 988.0 ms。666 项
权威测试与 20+20+5+20 共 65 轮稳定性通过。

本轮仍在 locked 显示会话中，只证明 CI acceptance byte-flow、loader、readiness 与正常退出，
不支持 CPU/RSS 或视觉体验结论；远端 `main` 的 6 个 CI/review/Actions/Dependabot 设置 finding
也仍未获修改授权。只读证据：
`/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/ci-performance-summary-memory-v1-20260829/CI_PERFORMANCE_SUMMARY_MEMORY_EVIDENCE.md`

## Production App hermetic 真实启动门禁（v6.50.0）

此前真实启动门禁只运行编译期隔离的 Performance QA App；Production-shaped App 虽已通过
Universal 架构、依赖闭包、build-flavor marker、法律资源与 strict deep 签名检查，仍可能在真实
loader、shipping SwiftUI/AppKit 初始化或退出路径中失败。当前新增双重 opt-in：只有精确参数
`--dev-island-hermetic-launch-smoke-v1` 与精确环境值
`DEV_ISLAND_HERMETIC_LAUNCH_SMOKE=v1` 同时存在，真实 Production UI 才以 inert TaskStore 启动；
普通 Finder/LaunchServices 行为完全不变。

该模式仍构造并布局可见岛与状态栏，但不启动 SQLite、Keychain、本地 Hook listener、Manus、
LaunchHealth、通知、Welcome 或 Sparkle。readiness 之后及 8 个一秒存活样本的每一秒都会检查
精确 PID 没有网络 socket、私有 HOME 没有数据库或 Hook 授权文件；最后只用
`NSRunningApplication.terminate()` 请求同一 PID 正常退出并要求 status 0。PR 的 `app-build` 在
Universal 构建后执行；tag Release 在 App 公证/staple/Gatekeeper 校验后、DMG 打包前再次执行。

锁屏/unknown override 只允许证明真实 Production artifact 的 loader、岛/状态栏构造、8 秒存活、
服务隔离与正常退出。采集的 CPU/RSS 数字不能代表丝滑度、首帧、动效、能耗或 Release 性能，
也不替代真实 Agent、用户状态迁移、Developer ID 分发、解锁视觉与 VoiceOver 验收。最终 T7 App、
测试数量、哈希和只读证据路径已经补入 Codex-Plan。

## Settings Agent 配置操作响应性（v6.51.0）

此前 **Agent Connections** 的单 Agent 状态扫描、全部 managed Hook 汇总及
Enable/Update/Disable 会在 SwiftUI MainActor 内直接读取和解析配置；最大 4 MiB JSON/TOML 与
写入后的 file/directory `fsync` 都可能让 Settings 在最需要反馈时停住。当前这些路径统一进入
可测试的后台 executor，主线程只接收低基数状态和固定产品文案。

每一行首次出现时保持真实 Checking，不再先猜测 Enable；后台 refresh 采用 latest-wins，写操作
独占同一行并显示 Enabling/Updating/Disabling 进度。写入结束后会重新读取实际配置，只有磁盘状态
与动作目标一致才显示成功；外部工具立即改回配置、旧 refresh 晚到或旧 Codex trust 探针晚到时，
都不能产生假的 Connected。离开页面只废弃晚到 UI 结果，不会中断已经进入原子边界的安全写入。

6 项聚焦回归已经覆盖初始 checking、refresh 取代、mutation 独占、离开失效、动作语义和真实
MainActor→非主线程断言；中英文进度与无障碍标签同时通过本地化门禁。最终 677 项权威测试、
20+20+5+20 共 65 轮进程/生命周期回归、10 轮无副作用 listener 及完整静态、安全与发布门禁
通过。T7 fresh Production App 的 6 个 Mach-O 全为 arm64+x86_64，strict deep ad-hoc 通过；
hermetic 启动 8/8 样本、readiness 1,542 ms、服务隔离、AppKit 正常退出和 status 0 均通过。

该改动提升的是操作期间的可响应性和状态可信度，不改变 Settings 的几何，也不代表当前真实
Claude/Codex Hook 已更新或 Codex `/hooks` 已由用户信任。显示会话仍为 locked，因此不能把代码
契约或启动 smoke 当作真实帧节奏、VoiceOver 或大配置文件下的人工体验验收。只读证据：
`/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/settings-agent-config-io-v1-20260829/SETTINGS_AGENT_CONFIG_IO_EVIDENCE.md`

## Plan Review 后台单次渲染（v6.52.0）

此前 Plan Review 虽保留了标题、列表、段落和代码块，但展开面板每秒更新时间/倒计时时，
`PlanMarkdownView` 会再次执行块级和 inline Markdown 解析。面对最大 65,536 字符的计划，这会把
静态阅读内容重新带入主线程高频路径，也可能在极端多段落输入下生成过大的 SwiftUI 树。

当前每个 request ID 只在后台生成一次不可变 document；任何局部秒级更新只做现成文字布局。新请求、
旧 operation 晚到和视图离开都有明确 generation 拒绝。正文同时增加 262,144 UTF-8 bytes 上限，
最多 512 个完整块可以进入界面。Preparing 状态使用固定双语进度与 AX 文案，在完整非空 document
准备好前 Approve/Reject 与 `⌘↩`/`⌘D` 都不可用；`⌘O` / Continue in Claude 始终保留。空白或
过度复杂的内容不会截断后继续允许批准。

最终 19 项计划/决策回归与 684 项权威测试均通过，覆盖真实 MainActor→非主线程、latest-wins、
离开失效、inline 预渲染、512 块上限、准备阶段键盘拒绝和单一 combining-grapheme byte 攻击；
20+20+5+20 共 65 轮进程/生命周期稳定性及 10 轮无副作用 listener 同时通过。T7 fresh
Production App 的 6 个 Mach-O 全为 arm64+x86_64，依赖闭包和 strict deep ad-hoc 通过；真实
hermetic 启动完成 8/8 样本、服务隔离、AppKit 正常退出与 status 0。显示会话 locked，因此不把
启动 CPU/RSS/readiness 或代码回归冒充大计划滚动、Animation Hitches 或 VoiceOver 实机结论。
只读证据：
`/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/plan-review-render-isolation-v1-20260829/PLAN_REVIEW_RENDER_ISOLATION_EVIDENCE.md`

## 展开面板叶子时钟隔离（v6.53.0）

此前一个面板级 `TimelineView` 每秒包裹并重新求值 `ScrollViewReader`、`LazyVStack`、全部任务行与
决策面；即使只有一个 9.5pt countdown 在变化，Plan Review 滚动区、问答选项、按钮和 hover
结构仍处于同一周期性失效边界。当前面板容器完全不含时钟：Running/Waiting 只重绘对应
TaskCard，Completed/Failed 不安装 tick；Action Request 只重绘 header，正文和操作区保持稳定。
面板尚未 live 或开始收起时，所有局部时钟继续暂停，静态 QA 可注入固定 Date。

5 项纯策略回归覆盖 live/terminal 调度、小时格式、终态冻结、负时钟偏差、ceil countdown 与
零下限；键盘与 Plan Review 聚焦回归同时证明结构改造未改变决策路由。最终 689 项权威测试、
20+20+5+20 共 65 轮进程/生命周期稳定性、10 轮无副作用 listener、完整性能/安全/发布门禁和
T7 fresh Universal Production App 均通过；8/8 hermetic 启动证明服务隔离与正常 status 0。
显示会话 locked，因此以上不能代替真实 5–20 会话滚动、hover 保持、Animation Hitches、能耗
或 VoiceOver 实机验收。只读证据：
`/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/panel-clock-leaf-isolation-v1-20260829/PANEL_CLOCK_LEAF_ISOLATION_EVIDENCE.md`

## Welcome 连接操作状态（v6.54.0）

Welcome 的连接页现在把“正在检查”和“正在修改”视为明确的 surface 状态。任何 Add、Update 或
Update all 开始后，其他连接按钮统一禁用；批量目标同时显示进度，结束时只提交一份完整磁盘复验
snapshot，避免逐行完成造成摘要、按钮和颜色连续跳动。失败仍按目标显示固定 Try again，Codex 的
vendor trust 未验证时继续显示 Configured，不会因为安装调用返回就瞬间伪装成 Connected。

关闭 Tour 后，晚到扫描/安装结果不再修改已经离开的界面；重新打开会重新检查真实配置。4 项新增
回归固定旧扫描拒绝、mutation 独占、离开失效和写后状态分类。此轮没有改变 Welcome 的窗口几何、
字体、色彩或 280 ms 翻页动效；显示会话仍为 locked，因此这里只能确认交互状态契约，不能声称
真实点击反馈、进度动画、VoiceOver 或整体“丝滑感”已经完成实机验收。

最终源码 693 项测试、完整性能/法律/安全/发布门禁、fresh Universal Production App 与 8/8
hermetic 启动均通过。只读证据：

`/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/onboarding-operation-ownership-v1-20260829/WELCOME_CONNECTION_OPERATION_EVIDENCE.md`
