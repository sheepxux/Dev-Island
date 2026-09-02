# Codex-Plan — Dev Island 当前目标与验收计划

> 当前快照：2026-08-31 · 产品版本：v0.3.0 · 当前分支基线：`97e579e`
>
> 本文取代 2026-08-05 的 v0.2.2 旧快照。旧文档中的通知、跳回、审批、历史、
> Sparkle、License、CI、状态音和新连接器等缺口已经完成，不再作为当前待办。

## 一、长期目标

把 Dev Island 打造成安全、可靠、可扩展、具备商业发布基础的高品质 macOS
Agent Island。产品价值不是“再多一个 Agent 列表”，而是用最小摩擦把真正阻塞
用户的事情带到前台：

1. 人工介入（审批、问题、Plan Review）
2. 任务结果（完成、失败）
3. 活跃工作
4. 空闲

所有阶段都必须有可复现测试、构建与真实体验证据。未经用户明确授权，不 commit、
push、tag、发布 Release、部署官网或修改真实 Agent 配置。

## 二、当前已完成的产品底座

- Manus Webhook fail-closed 安全链路、隐私与发布门禁
- Claude Code / Codex 岛内审批；Claude 问答与 Plan Review
- 历史记录、状态音、精确终端与 tmux 跳回
- Sparkle 更新底座与离线商业 License 验证
- 断开式 device-only License Keychain 存储底座与 provider-neutral 商业链路威胁模型
- Provider-neutral 激活码客户端闭环：可信配置预检、低基数 transport、验签后保存、
  latest-operation-wins 与取消晚到保护；仍未接生产 provider/key/UI
- 商业政策机器门禁：价格、试用、设备、退款、离线宽限、销售地区、Seller/Provider
  等 36 项决策保持显式未批准；未知字段、不安全 Origin、硬件指纹、矛盾策略与伪完整
  审批均 fail closed，当前免费版行为不变
- 商业政策记录建立 descriptor-backed 输入边界：当前用户 owner、单硬链接、安全
  mode、128 KiB 上限、file/path/parent metadata 再绑定和打开后替换拒绝；JSON 根层/嵌套
  重复 key 不再被 last-key-wins 吞掉。该加固不填写或批准任何商业决策
- Claude Code、Codex、Cursor、Gemini CLI、Qwen Code、GitHub Copilot CLI、
  Kimi Code、OpenCode 连接器（Preview 项保持明确标记）
- Codex 只读 Hook 信任验证：仅调用 OpenAI 签名 App 内的 `app-server`，精确校验
  bundle、Team ID、来源路径、事件、命令、启用状态与 `trusted/managed`，任何漂移均
  保守保持“已配置”而不是误报连接
- 注意力优先排序、九宫格状态点阵、Running 环绕动效、Dock 显示协调
- 跟随系统 / English / 简体中文的应用级语言切换；Welcome、Settings、历史记录、
  状态菜单、系统通知、审批/问答与主岛状态已完成双语资源、无障碍摘要、格式化计数
  与最终 App Bundle 打包
- 当前自动化基线：**745 tests，0 failures**；最近一次核心运行时稳定性基线另有
  20 轮 / 240 个真实子进程版本探针、20 轮 tmux descendant cleanup 与 5 轮 Codex Hook
  trust 完整进程边界压力回归、20 轮 sleep/wake 生命周期回归，以及 10 轮零 Agent route 的
  hermetic listener CLI 回归；
  Mac16,10 已建立四场景解锁 CPU/RSS、3 分钟展开态、60 秒 Time Profiler、连续开合
  Animation Hitches、Activity Monitor、Leaks 对象归因与 30 分钟展开态 RSS 实机基线

### Claude 审计画布对齐

`dev-island-audit.canvas.tsx` 使用的是早于当前工作树的快照，不能直接把其中全部
“缺失项”重复列为目标。有效对齐如下：

- [x] P0 岛内审批、AskUserQuestion 与 Plan Review
- [x] P1 8 个本地连接器 + Manus 云端底座、Sparkle、PR CI；线上崩溃上传刻意不接入，
  当前采用不读取 `.ips` 的本地启动健康与用户主动导出诊断
- [x] P2 用量基础、状态音、精确 tmux 跳回
- [x] P3 Session History
- [x] P0 商业客户端安全链路：离线验签、device-only Keychain、激活协调核心
- [x] 商业政策决策记录与攻击夹具；在 owner/legal 真正审批前拒绝 `--require-approved`
- [ ] 商业 provider、seller、试用/退款/设备/离线政策与 sandbox 闭环
- [x] App 内 English / 简体中文本地化底座与核心体验
- [x] GitHub 仓库控制只读审计器、离线安全/攻击夹具与 SwiftPM/Actions
  Dependabot 更新策略
- [ ] 远端 `main` 强制 PR review + `Tests, security, universal build`，限制
  Actions allowlist/全 SHA pin，并开启 Dependabot security updates
- [x] Privacy / Terms 仓库文档与线上路由已建立
- [ ] Homebrew 公开 tap、官网定价/试用转化与官网多语言
- [ ] Apple Watch / iPhone companion 通知
- [ ] 解锁后的真实交互、性能、VoiceOver 与系统集成验收

## 三、当前主线：产品体验与高级感

### 已完成的第一批

- [x] Welcome Tour 从偏网页/AI 模板的衬线语言改为 SF Pro + SF Mono
- [x] 中性色收敛为冷灰；饱和色只用于真实状态
- [x] 修复连接页固定高度内的严重裁切，改为稳定双栏 Agent 矩阵
- [x] Welcome 页头加入稳定的三步进度轨；Live 示例使用真实点阵动效
- [x] Welcome 长 Agent 名称使用受控紧排，避免 `GitHub Copilot CLI` 被硬截断
- [x] Welcome 左侧编辑栏收口为 `32 + 264 + 28 + 404 + 32 = 760pt`的固定几何；
  English 第 2 页从突兀的三行标题回归两行，中英文三页和右侧功能标本保持无裁切
- [x] 点阵加入点级微光，不恢复大面积彩色光晕
- [x] 空闲岛隐藏冗余 `0 sessions`；活动岛保留 `x sessions`
- [x] 主岛会话文案统一为英文 `session/sessions` 与 `No sessions`，移除英文界面中的孤立中文并统一 task/session 术语
- [x] 移除“胶囊套胶囊”的计数徽章，改为细分隔线 + 纯文字
- [x] 无刘海屏合成岛扩至 260pt，`Approval required · 20 sessions` 等边界状态仍完整呈现且轮廓不随内容跳动
- [x] 展开面板按 `Attention / Review / Results / Working` 呈现最高优先级
- [x] 任务行补充完整 VoiceOver 状态与返回目的地
- [x] Settings 从长网页式滚动流改为编号侧栏 + 单任务域详情
- [x] Settings 切换栏目自动回顶，并尊重 Reduce Motion
- [x] Settings 的五个 switch 行收敛为统一左文案/右控件双列节奏；English 四页与简中
  六页均保持同一尾部基线，DEBUG 截图不再泄漏 Swift 测试宿主的 `16.0` 版本
- [x] Session History 移除孤立的衬线标题与普通状态圆点，统一为 SF Pro + 静态九宫格语义
- [x] Support 启动健康升级为 v2 ready milestone：岛与菜单栏跨过 2 秒稳定窗口后
  即记录健康，稳定运行后的 Force Quit/系统重启不再误报；连续未达 ready 计数上限为 3，
  旧 `cleanExit=false` 迁移为静默不确定状态，不读取或上传崩溃报告
- [x] 对本机历史 `.ips` 做一次性开发诊断并确认两类闪退根因：v0.3.0 包缺
  `Sparkle.framework` 可达 rpath，v0.2.2 根岛动画 `Task.sleep` 在 task teardown
  触发 Swift Concurrency fatal error；当前构建边界强制 Framework/rpath/双架构/签名，
  `IslandRootView` 已完全移除 `Task.sleep` 且 CI 禁止回归。原始报告未进入 App/仓库/证据包
- [x] 将 Sparkle 单点检查升级为完整 App 依赖闭包门禁：扫描主程序、Framework、XPC、
  helper 与 dylib 的全部 Mach-O，精确要求 arm64+x86_64，非系统依赖必须在 Bundle 内可达，
  拒绝开发机绝对路径、未知/逃逸 rpath、伪系统路径、非 Mach-O 替换与逃逸/悬空符号链接；
  8 类攻击夹具、PR CI、tag Release 和签名前构建边界共同固定
- [x] 新增显式 opt-in 离屏视觉快照门禁，不在普通测试中写文件
- [x] 本地 Hook 监听器在重试耗尽后可由系统唤醒重新拉起；健康监听时 wake check 保持幂等
- [x] 生产日志收敛为低基数状态；移除 key/ID/URL/路径/外部进程输出/原始错误，Manus 非 HTTP 响应不再触发强制转换崩溃
- [x] Manus realtime 把 cloudflared + 已注册 webhook 作为原子健康状态；启动、wake、heartbeat 与并发 stop 失败均事务清理并显式降级 polling-only
- [x] Manus 真实账号验收 CLI 改为显式命令 + TTY 隐藏输入；signed registration probe 与同运行任务分离，取消/超时/失败进入未取消清理，无法证明远端删除时要求人工复核；cloudflared 使用最小子进程环境
- [x] Manus 真实验收补齐可审计证据链：T7 append-never 私有运行目录、固定 transcript
  allowlist/no-follow 64 KiB 验证器、构建前后源码哈希、CLI binary SHA-256、exit/result 与顶层
  `SHA256SUMS`；11 类成功/注入/链接/权限夹具固定，只有真实 CLI exit 0 + accepted validator
  才能生成 `ACCEPTED`。当前仍没有真实账号成功证据，Release gate 继续关闭
- [x] Manus 验收源码绑定从少量关键文件升级为实际编译输入闭包：自动枚举 83 个
  IslandCore/CLI Swift 源与 7 个固定 Package/tooling 输入，逐项验证 27 个
  `Package.resolved` checkout 的 HEAD/clean/untracked/ignored/submodule 状态；构建前后 JSON 与
  Swift/Xcode/SDK manifest 必须逐字节一致。新增源可发现及链接/权限/未知文件/dirty/ignored/
  revision/workspace 攻击夹具固定，真实账号 gate 仍不因此自动打开
- [x] Manus polling 改为 actor + 生命周期代际；断开/重启/换 key 后晚到结果被双层拦截，401 会失效 key 并关闭同代 realtime
- [x] Manus Connect/Disconnect 使用独立配置代际与 latest-operation-wins；换 key 先清理旧服务，Keychain 删除失败不再谎报已移除
- [x] 按 Manus 当前官方 v2 文档重写 Webhook：`api.manus.ai` 注册/删除/鉴权公钥、双 Header、时间戳+完整 URL+raw-body hash 验签、300 秒重放窗、event ID 去重与真实事件结构；旧猜测协议被拒绝
- [x] Manus 出站请求改为固定源站的专用 ephemeral transport：不保存 Cookie/缓存、拒绝
  redirect、15/30 秒 timeout、响应 origin 二次绑定；App/验收 CLI 共用 16–512 字节凭据
  边界，task/webhook ID 与 Cloudflare callback 均在网络前验证，异常 Retry-After 上限 300 秒
- [x] Manus 返回内容在进入 SwiftUI / SQLite 前建立第二层边界：响应体上限 1 MiB、列表
  上限 1000 项，task/event/attachment 元数据与标题/消息按 UTF-8 字节限长；任务 URL 必须
  精确对应 `https://manus.im/app/<task-id>`。用户点击或跳回时再次验证，拒绝 file/custom
  scheme、跨源、userinfo、端口、query/fragment 与 ID 不匹配；本地 Agent 只允许 Finder
  打开真实存在的普通目录，文件、App/Bundle、远程 file URL 与失效路径均不调用 Launch Services
- [x] Welcome 连接器矩阵补齐 Manus cloud 入口，移除像未完成占位的空白格
- [x] Approval / Question / Plan Review 使用稳定的 `Session XXXX` 本地指纹，不泄露或截断原始 vendor session ID
- [x] Plan Review 按标题、段落、有序/无序列表与代码块保留 Markdown 块级结构
- [x] Completed 只在并发 Running 前保留 15 秒结果窗口，之后活跃工作回到前台；完成记录仍留在面板与历史
- [x] Session History 使用稳定的英文紧凑相对时间，避免英文界面随中文区域设置混入“分钟/秒”
- [x] Required tertiary metadata token 提升到 `#7F7D78`，在 `#111111` 表面为 4.59:1
- [x] 本地 Hook 增加统一只读健康诊断；Welcome 区分已连接/需更新/未连接，Support 与 CLI 复用同一低敏状态且不改配置
- [x] Production、Performance QA 与 Debug 使用三个独立 SwiftPM scratch；构建脚本在 lipo
  后检查实际可执行文件的闭合 marker 矩阵，21 个逐标记负向夹具固定全部泄漏/缺失路径；
  三套真实 Universal App 的 Bundle/plist、6 个 Mach-O、依赖闭包和深层签名均已复验
- [x] 3×3 点阵连续动效保持 Core Animation 合成；相同语义状态共享上限 16 项的关键帧缓存，同尺寸重复布局不再重建 9 个 shadow path
- [x] 根岛每次 SwiftUI 刷新建立单一 presentation snapshot：20 会话注意力排序从最多 5 次收敛为 1 次，面板/紧凑岛共享 primary state、标题与计数；状态计数由 4 次扫描收敛为单次 switch pass，3 项语义回归与性能 CI 固定
- [x] 面板内容 reveal 与持续动效分相：静态层级 40ms 开始淡入，最多 189 个点阵 keyframe 与 1 秒时钟延后到 300ms 轮廓 morph 完成后启动；collapse 立即停止，快速开关共享 generation token 取消旧回调，Reduce Motion 无空间等待；2 项时序回归与性能 CI 固定
- [x] 展开面板审批队列建立单次线性 presentation snapshot：每秒 duration tick 不再为每个会话重复扫描整条请求队列，复杂度从 O(sessions × requests) 收敛为 O(sessions + requests)；面板标题与 VoiceOver 摘要复用根岛单遍状态计数，2 项到达顺序/孤立请求/键盘所有权回归与性能 CI 固定
- [x] 岛内同步动作队列建立硬资源边界：请求默认 90 秒、绝对上限 120 秒，全局最多
  32 项、单一 `(source,sessionId)` 最多 4 项；溢出立即返回中立结果并让 Agent 使用原生
  提示，不保留 continuation。标题、消息、详情、问题、header、选项与描述同时按可见字符
  和 UTF-8 字节限长，单个超大 combining-grapheme 也不能绕过；4 项边界回归与 CI 门禁固定
- [x] 本地 Hook 会话与历史存储建立硬资源边界：session/generation ID、cwd、phase、message
  同时校验控制字符、路径形态、字符数与 UTF-8 字节；每个连接器最多保留 128 个实时会话，
  容量压力依次淘汰终态、最旧 Running，并在全 Waiting 时拒绝最新到达者以保留更早人工阻塞。
  SQLite 在打开及每次写入时确定性保留最新 5,000 个任务与 20,000 条进度，并清理被淘汰
  任务的孤立进度；活跃岛仍只使用内存状态，不因历史修剪中断
- [x] SQLite 历史行增加独立磁盘重读信任边界：新任务/进度在写入前按 source、ID、标题、
  phase、URL、waiting message、进度类型/消息和时间校验类型与 UTF-8 字节，批量中任一非法则
  整个事务回滚；打开旧库时只做一次 SQL 侧类型/字节清理，日常写入保持 O(1) 字段验证。
  **View History** 查询再次在 SQLite 侧过滤，超大外部修改行不会先被 materialize 进 Swift；
  3 项外部篡改/打开维护/事务回滚回归与 CI 门禁固定
- [x] SQLite 文件生命周期独立为 `SQLiteFileBoundary`：App 私有数据库目录固定 `0700`，
  主库与既有 `-wal/-shm/-journal` 固定 `0600`；最终目录、数据库、sidecar 的符号链接、
  非普通文件、非当前用户所有权和多硬链接全部在 SQLite 访问前拒绝。因 SQLite.swift 尚未
  暴露 `SQLITE_OPEN_NOFOLLOW`，App 先以 `O_NOFOLLOW|O_CLOEXEC` 打开锚定描述符，再在
  SQLite 连接前后核对 device+inode，schema/修剪/Clear History 不会被重定向到无关文件；
  6 项链接/文件类型/权限回归与 CI 门禁固定
- [x] Welcome 通知开关统一右侧基线；岛内问答与 Plan Review 的模糊 “Use Claude” 改为明确 “Continue in Claude”
- [x] Welcome Tour 三步统一为近黑 studio canvas 与单一功能舞台；标题尺度、18/14pt 层级圆角、
  240ms 短行程页切换和 10pt 操作圆角完成收敛，Codex 配置状态不再在中英文连接矩阵中截断
- [x] 面板连接点阵、连接 Agent 与 Settings 控件补齐明确 VoiceOver label / value / hint
- [x] 审批、问题与 Plan Review 有待处理请求时改为单一聚焦决策面，不再重复堆叠可点击会话卡；安全 Session 指纹与会话标题仍保留
- [x] 展开面板总数统一为 `session/sessions`；Settings 侧栏长标题保持单行，重复 Agent 更新说明收敛为低噪音状态
- [x] Approval / Question / Plan Review 补齐分组语义、选中状态、队列说明与动作提示
- [x] 只有最早人工请求持有快捷键：`⌘↩` 主要动作、`⌘D` 拒绝、`⌘O` 回到 Claude；`Esc` 继续只收起岛，避免误授权
- [x] 使用真实 `NSWindow.performKeyEquivalent` 建立窗口级键盘契约：主请求、次级请求、禁用提交、审批/拒绝/回到 Agent 与 Escape 安全边界均有回归测试
- [x] borderless 岛窗口自动展开不抢焦点；初始展示完成后只允许直接点击真实轮廓进入 key
  window，透明区域/hover/scroll/右键不激活，收起时释放；AX 窗口名固定为 `Dev Island`
- [x] AskUserQuestion 草稿抽成可测试纯状态模型：单选替换、多选 toggle、Next/Back 保留、
  完整 Submit 与缺答案拒绝均固定，最终答案按界面选项顺序 canonicalize
- [x] 决策面补齐 Increase Contrast 明确分支；问题前进/返回、任务自动定位与 Settings 回顶
  尊重 Reduce Motion，避免空间滚动与 scale
- [x] v6.38.0 将 Increase Contrast 从决策面扩展为产品级角色系统：统一增强 Welcome、Settings、
  History、安静文字、hairline、展开岛边界与 idle 点阵；39 组标准/增强同尺寸快照无裁切或几何
  漂移，4 项策略回归、652 项全量与 65 轮稳定性通过。DEBUG 强制分支不进入 Release，也不冒充
  系统开关或 VoiceOver 真实验收
- [x] v6.39.0 将 Production / Performance QA / Debug 编译图、Bundle 标记与最终可执行 marker
  矩阵完整隔离；18 类逐标记泄漏/缺失夹具、三套 Universal App、652 项全量与 65 轮稳定性通过
- [x] v6.40.0 把双语 Privacy / Terms 原文严格绑定到 App Bundle，并在 **Privacy & Support**
  顶部提供离线阅读；descriptor/UTF-8/双语日期与逐字节边界、10 类攻击夹具、运行时双语
  fail-closed 解析、出站链接 allowlist、4 张英中视觉快照、659 项全量与 65 轮稳定性通过。
  文档继续明确为 owner/legal review draft，不冒充律师审批或网站发布
- [x] v6.41.0 重新捕获当前 Welcome 三步并收敛最终决策页：前两页继续允许 Skip，最后一页
  移除与 Start 重复的低权重出口，只保留标准关闭、Back 与唯一主动作；改前/改后三页同尺寸
  对比证明前两页像素零漂移，纯导航策略、660 项全量、65 轮稳定性与 Universal QA App 通过
- [x] v6.42.0 将 App 内法律资源从 `resourceValues` 后另行 `Data(contentsOf:)` 改为单次
  no-follow descriptor 有界读取；固定普通单链接文件、安全 mode、1–512 KiB 与读取前后
  descriptor/path 全 metadata，正常、symlink、hardlink、危险权限、上下界和路径替换 6 类
  回归由 CI 固定。666 项全量与 65 轮稳定性通过；最新 Universal App 启动证据见本轮 T7 证据包
- [x] v6.43.0 将 hermetic Performance QA App 的真实启动纳入 PR CI：私有
  `CFFIXED_USER_HOME`、5 秒 readiness、8 个一秒 idle 存活样本、精确 launch PID 的 AppKit
  terminate、5 秒退出上限与真实 status 0 同时通过才算成功；锁屏 override 只证明 loader/
  readiness/存活/退出，不支持性能结论。分析器的命令路径已安全引用，并在包含空格的
  `/Volumes/T7 Shield/...` 源码/App/证据路径下完成真实复验
- [x] v6.44.0 将 Performance CSV/App log/summary 从 check-then-create 普通重定向升级为
  `umask 077` + 单次 noclobber descriptor 所有权：三文件固定当前用户 `0600`、单硬链接和
  device/inode token，后续写入不重开路径；分析器只接收与 writer token 绑定的 no-follow
  bounded `pread` 私有快照。含空格路径、预存在、symlink、双并发 claimant 和 reserve 后替换
  5 类夹具连续 10 轮通过；fresh Universal Performance QA App 的 8 样本 smoke 通过 readiness、
  私有 HOME、精确 PID 采样、AppKit 正常退出和 status 0，666 项全量、65 轮稳定性与完整安全门禁
  同时通过。锁屏数字仅为整合 smoke，不作为性能或视觉结论
- [x] v6.45.0 将 readiness 从反复 `awk` 公共 App-log 路径改为与 writer descriptor 8 token
  绑定的 1 MiB `RDONLY|NOFOLLOW|NONBLOCK` 单次 `pread` 私有快照；FIFO/替换在文本解析前失败，
  marker 必须唯一、十进制且位于 launch uptime 后 5.5 秒内。6 类文件/解析/时间夹具连续 10 轮、
  真实 8 样本整合 smoke、666 项全量、65 轮稳定性与完整安全门禁通过；锁屏 smoke 不冒充性能
  或视觉验收
- [x] v6.46.0 将所选 Performance QA App 从可替换的公共 launch path 降为只读输入：主
  executable/plist 通过 no-follow/nonblocking descriptor 有界稳定哈希与 strict deep 签名，
  `ditto` 冻结到随机私有 `0700` sampler root 后只有私有 Bundle 可验证和启动；来源与副本在
  启动前、正常退出后都重新绑定。7 类夹具连续 10 轮，最终来源 Plist 替换攻击精确 exit 3 且
  summary 为 0 byte；fresh Universal App 8 样本 smoke 固定相等的 selected/private SHA-256、
  `isolated_app_snapshot=true`、正常退出与 status 0，666 项全量、65 轮稳定性及完整安全门禁通过。
  锁屏数字仍不作为性能或视觉结论
- [x] v6.47.0 将 PR CI 的 Performance summary acceptance 从 sampler 退出后的公共路径
  `grep`/`sed` 改为带引号 command substitution 捕获的 producer stdout；所有 survival、8 samples
  和 selected/private SHA-256 断言只读进程内 shell 变量，残留 QA descendant 替换 runner 临时
  summary 不再影响 gate。最终 Universal App 的真实 post-exit replacement 攻击保留恶意 public
  bytes 而进程内 8-sample 验收全绿；666 项全量与 65 轮稳定性通过。锁屏 smoke 不作为性能结论，
  远端 6 个仓库策略 finding 未经授权保持不变
- [x] v6.48.0 新增无副作用 listener transport 夹具：随机 loopback 端口、进程内 256-bit
  授权、空 Agent descriptor 集合与零 `/hooks/<source>` route；启动、challenge-response、stop
  后不可达共同通过才返回 verified。CLI 固定五行低基数 stdout、零 stderr，权威入口连续 10 轮；
  真实本机预检前后生产 Header、Claude/Codex Hook、SQLite 与 Keychain 粗粒度指纹保持不变
- [x] v6.49.0 将 App SwiftPM graph 从 File Provider-backed checkout 解耦：新增显式
  `DEV_ISLAND_SWIFT_SCRATCH_ROOT`，最终 flavor 仍固定 production/debug/performance-qa；共享
  `prepare-scratch` 在 SwiftPM 前验证 owner、真实目录、安全 mode、位置与已存在直接父目录，
  拒绝仓库/祖先、`.build` 根、源码、symlink、可写目录和缺失多级父目录。默认 CI/tag 路径不变，
  T7 QA 可避开旧 `.build` 中 `hidden,compressed,dataless` 文件造成的永久读取等待
- [x] v6.50.0 把真实 Production-shaped App 从静态 Bundle 检查提升为 hermetic 启动门禁：精确
  参数与环境双重 opt-in 让冻结私有副本以 inert TaskStore 构造 shipping 岛与状态栏，同时跳过
  SQLite、Keychain、本地 Hook、Manus、LaunchHealth、通知、Welcome 与 Sparkle；readiness 后及
  8 个一秒样本逐次证明精确 PID 无网络 socket、私有 HOME 无产品状态，再经 AppKit 正常退出并
  要求 status 0。PR 在 Universal Production build 后运行，tag Release 在 App 公证后、DMG 前
  重复。671 项全量、65 轮进程/生命周期稳定性、10 轮 listener、完整 security/release/static
  门禁与 T7 fresh App 真实 smoke 通过；锁屏样本不作为性能、丝滑度或视觉结论
- [x] v6.51.0 将 Settings 的单 Agent 配置扫描、全局 managed-Hook 汇总和
  Enable/Update/Disable 从 MainActor 移到统一 detached executor；首次 checking、refresh
  latest-wins、mutation 独占、页面离开失效、旧 Codex trust token 失效与写后实际状态复验共同
  避免界面停顿和假 Connected。6 项聚焦回归含真实 MainActor→非主线程断言，中英文忙碌与 AX
  文案已固定。677 项全量、20+20+5+20 共 65 轮进程/生命周期回归、10 轮无副作用 listener、
  完整 static/security/release 门禁和 T7 fresh Universal Production App 真实 smoke 均通过；
  显示会话 locked，因此不把 8 秒启动样本冒充 Settings 帧节奏或真实大配置交互验收
- [x] v6.52.0 将 Plan Review 最多 65,536 字符的块级与 inline Markdown 解析移出每秒
  TimelineView 重绘，按 request+operation generation 在 detached worker 单次生成 immutable
  document；新增 262,144 UTF-8 bytes 与 512 完整块上限，加载/空白/过度复杂时禁用
  Approve/Reject 及快捷键，同时始终保留 Continue in Claude，避免主线程停顿和截断误批准。
  19 项计划/决策回归、684 项全量、20+20+5+20 共 65 轮进程/生命周期稳定性与 10 轮
  无副作用 listener 均通过；T7 fresh Universal Production App 通过依赖闭包、strict deep
  ad-hoc 与 8/8 hermetic 启动隔离。显示会话 locked，未把启动采样冒充滚动丝滑度或 VoiceOver
- [x] v6.53.0 移除包住 `ScrollViewReader`、`LazyVStack`、所有 TaskCard 与决策面的面板级
  `TimelineView`；Running/Waiting duration 改由单行本地一秒时钟更新，Completed/Failed 完全
  静止，Action countdown 只刷新请求 header，面板未 live 时全部暂停。5 项纯策略回归固定
  hour boundary、终态冻结、负时钟偏差、ceil countdown 与零下限；689 项全量、65 轮稳定性、
  10 轮 listener、T7 fresh Universal Production App 和 8/8 hermetic 启动隔离均通过。显示会话
  locked，因此只声明结构性重绘隔离，不宣称 unlocked 滚动、Animation Hitches 或 VoiceOver
- [x] Support 诊断增加用户主动选择位置的 **Save…**：仅写入已脱敏聚合摘要，128 KiB 上限、`0600`、同目录临时文件、`fsync`、原子替换并拒绝符号链接/目录；不上传
- [x] Release 在导入证书前使用可独立回归的无泄露凭据预检；Developer ID Team ID 必须与 Apple 公证 Team 一致，公证后的 App 与 DMG 必须通过硬 Gatekeeper acceptance 才能发布
- [x] Sparkle 运行时只接受唯一生产 GitHub Feed 与完整安全配置：签名失败永久关闭、每日默认检查、禁止静默安装、关闭系统画像；任一字段缺失或弱化均保持 inert
- [x] macOS 状态菜单去除中英混杂与 7-Agent 超长静态列表，并在 v6.31.0 将菜单首行、
  tooltip 与 VoiceOver value 收敛到同一注意力优先快照；优先状态后明确追加全部会话数，
  TaskStore 变化事件驱动刷新，最近完成仅安排一次到期边沿，标题/Session ID/路径/URL/
  原始 degraded reason 均不进入菜单或 AX value
- [x] Release 在发布前原子生成并自验 `SHA256SUMS`，覆盖 DMG/ZIP 双别名、签名 appcast 与 Cask；别名字节不一致、符号链接或缺失输入均失败，并为全部发布产物生成 GitHub Sigstore build provenance
- [x] 建立下载者视角的独立 Release 验证器：离线核对精确 8 资产、双别名、manifest、Cask/Appcast/SPDX 与 tag commit；线上包装器只读下载，并把全部 SLSA provenance 固定到仓库、`release.yml`、tag ref/source digest，DMG/ZIP 另验 SPDX predicate。新增打包品牌哈希替换攻击后共 19 类攻击夹具通过；公开 v0.3.0 因缺 4 个新资产被明确判定为 legacy incomplete，而非伪通过
- [x] 建立远端 GitHub 控制验收：离线夹具固定 required CI/review、管理员保护、对话解决、线性历史、Actions 精确 allowlist + 全 SHA pin、只读默认 token、Secret Scanning 与 Dependabot 安全更新；线上脚本只做 GET。当前远端精确报告 6 个未满足项，修复前不把 PR CI 称为强制边界
- [x] PR CI 增加 always-run 低敏诊断摘要：固定 11 道门禁 outcome（含品牌资产）、首个
  失败与复现命令、测试总数/失败用例名和安全子门禁；原始日志/环境/Secret/App 数据不进入
  包，仅失败时用全 SHA 固定的 GitHub upload-artifact 上传，14 天自动删除
- [x] PR CI / tag Release 增加内嵌 Bash 静态语法边界：safe-YAML 逐项提取全部 `run`，
  GitHub expression 仅替换为固定占位符后以最小环境 `/bin/bash -n` 解析；两条路径都在
  依赖解析前验证两个 workflow，tag 另早于凭据加载；v6.25.0 再在 safe-load 前加入有界
  Psych AST 单文档/标量 key 预检，拒绝重复/quoted key、`on`/`true` resolved collision、
  多文档、非标量 key、20,000-node/128-level 结构洪泛；descriptor 稳定性补齐 mtime/ctime，
  v6.26.0 再按 step > job defaults > workflow defaults 解析有效 shell，只允许精确 `bash` 或
  `/bin/bash`，拒绝参数/template、畸形 defaults 与非字符串 shell；攻击夹具从 8 类扩展为 20 类
- [x] PR CI / tag Release 增加仓库脚本无执行语法闭包：真实证明 Bash 会在后置 syntax error
  前执行前置副作用后，改为依赖解析/凭据加载前 descriptor-backed 枚举全部 49 Bash + 21 Ruby，
  以最小环境 stdin-only `bash -n` / `ruby -c` 完整解析；目录/文件 owner、type、mode、nlink、
  execute、size、UTF-8/NUL、mtime/ctime 与 symlink 边界固定；v6.28.0 再纳入 5 个 Swift，
  用 `/usr/bin/swiftc -parse -` 检查冻结 stdin 且不执行顶层副作用，Swift 无 shebang/精确
  env-swift、后置语法和错误 shebang 由夹具固定，负向攻击从 11 类扩展为 13 类；v6.69 的
  CryptoKit 发布验证器自动进入闭包，当前为 49 Bash + 21 Ruby + 6 Swift
- [x] 修复本地 CLI 版本探针的子进程完成竞态：移除依赖 Foundation callback/helper-thread 调度的成功路径，改为 `posix_spawn` 独立进程组 + 当前线程 nonblocking drain/`waitpid` + monotonic deadline，超时 TERM→KILL 整组清理；快速退出、非零退出、超限输出、挂起与忽略 TERM 回归覆盖
- [x] Performance 采样证据升级为 CSV/日志/摘要整组 append-never；未知锁屏状态也 fail closed，摘要绑定 App 哈希与机器环境，并提供 CPU/RSS p50/p95、RSS 首尾增长及长时线性斜率
- [x] PR CI 与 Release 从 `Package.resolved`、实际 App 许可目录、编译用 toml++ header、
  9 个 Agent 源 SVG 与打包 PNG 生成确定性 SPDX 2.3；当前 38 个组件逐字节复验，SBOM
  同时进入 SHA256SUMS、build provenance 与独立 GitHub Sigstore SBOM attestation
- [x] 9 个 Agent 品牌源 SVG 与 App 实际打包的 18 个 1×/2× PNG 进入同一确定性清单；
  本地构建、PR CI、SBOM 与下载者 Release 验证器逐字节核对，缺失/额外/符号链接/哈希
  漂移均失败。当前 SPDX 扩为 38 组件/38 关系；tag Release 在加载凭据前对所有来源与
  商标人工复核状态 fail closed，未审批前不能误发商业版本
- [x] 商业激活码固定 16–128 字节受控 ASCII 且 normal/debug 全脱敏；无 trust anchor 时 transport 零调用，避免 keyless build 消耗一次性 code
- [x] 商业激活 actor 使用 latest-operation-wins 与显式取消；取消不敏感的 transport 晚到也不能写入 Keychain，所有文档只经 verify-before-save 入口
- [x] 商业 transport、License 与 Keychain 原始错误统一为低基数结果；篡改/超大响应保留旧有效文档，成功链路通过 device-only Keychain round-trip
- [x] 商业激活码从可复制且不主动清零的 `Data` 收敛为值拷贝共享的专用秘密缓冲区；最后引用释放时通过 `memset_s` 防优化清零，scoped bytes API 与零生产接线边界保持不变
- [x] 商业政策从散落的 TODO 收敛为 schema v1 决策记录；36 项未决字段不以竞品默认值
  或占位数字冒充已批准政策。独立 verifier 与攻击夹具拒绝未知字段、符号链接、HTTP /
  带凭据 Origin、硬件指纹、非法价格、矛盾试用策略和不完整 approval；安全门禁同时证明
  当前记录仍不能通过 `--require-approved`
- [x] IslandWindow 常驻安全轮询从 4 Hz 降至 1 Hz；全局/本地移动事件与轮廓变化继续即时处理边界，25 Hz 光标重申进一步严格限定到紧凑岛内，展开面板阅读态回到 1 Hz，每分钟减少 1,440 次无意义主线程唤醒；三分支纯策略测试与性能 CI 固定能耗/延迟契约
- [x] GitHub GET-only 仓库控制审计不再把 connection reset 误报为管理员权限问题；network、
  authentication、administration read、rate limit 与 unexpected 使用固定低基数分类，raw stderr
  仅在 owner-only 临时目录内有界读取且永不回显；fake-gh success/reset/401/403/404/rate/unknown
  夹具同时进入 PR CI 与 tag Release 安全门禁
- [x] PR CI、tag Release 与失败诊断统一通过 `run-authoritative-tests.sh` 使用
  `.build/tests-authoritative`；668 项全量测试和 20+20+5+20 轮 `--skip-build` 稳定性回归
  共享同一测试二进制，不再接触开发者默认或 App/Performance scratch。fake Swift 精确固定
  66 次调用、filter 分布与路径；另以同一图中已构建 CLI 运行 10 轮 hermetic listener，
  workflow 直接 `swift test` 由安全门禁拒绝
- [x] 固定权威测试图增加完整运行期单写者边界：零字节 `0600` 单硬链接 lockfile 与非等待
  BSD descriptor lock 覆盖 full suite + 65 轮复用；并发第二入口在 Swift 前只输出固定错误。
  真实暂停 fake full suite 的夹具证明竞争路径一秒内失败、零 Swift 调用，首运行释放后仍为
  66 次；独立 checkout 再拒绝 symlink、目录、多硬链接、错误 mode 与非空 lockfile
- [x] 建立应用级本地化边界：默认跟随系统，可在 Settings → General 即时切换
  English / 简体中文，不修改 macOS 全局 `AppleLanguages`，所有打开窗口同步刷新
- [x] Welcome 三步、Agent 连接状态、主岛总会话/注意力摘要、Settings 全六页、
  Session History、状态菜单、系统通知标题及岛内审批/问答完成双语；Agent 生成的任务名、
  命令、路径、问题与选项保持原文，避免改变技术语义
- [x] 中英文 catalog 键集合强制一致、缺失翻译回退英文源文案；SwiftPM 测试资源与
  最终 App `Contents/Resources/*.lproj` 共用同一来源，CI 与构建脚本双层拒绝漏包
- [x] 本地化源码覆盖门禁：所有 literal `L10n` key 必须进入 catalog，未经审核的裸
  SwiftUI 产品文案直接失败；AppKit 菜单与通知也必须显式遵循 App 语言
- [x] Settings 语言选择器改为高对比度深色 Menu，修复原生 Picker 在暗色界面里文字
  接近黑色以及重复箭头的问题
- [x] 新增显式只读 `local-live-readiness`：固定 Claude Code `2.1.197` 与 OpenAI 签名
  Codex `0.149.0-alpha.4.3` 当前实测版本，统一报告 CLI、managed Hook、Codex trust 与
  App loopback listener；版本漂移只要求复核，命令不写配置、不启动 Agent 会话
- [x] 本地监听器增加 CLI-only 一次性 challenge-response；拒绝浏览器 `Origin`，响应不含
  任务、配置或路径。14 项聚焦回归覆盖快/挂起版本进程、版本漂移、启动/停止和 Origin
  拒绝；当前本机实测为两个 CLI 版本已验证、两个 Hook 需更新；最新 QA App 运行时
  listener=`listening`，退出后按设计为 unavailable
- [x] 所有本地 Agent 写入/审批路由增加统一 `X-Dev-Island-Hook: v1` 非 simple-request
  Header；curl 与 OpenCode 插件同源生成，旧 managed 定义自动显示需更新。服务端同时拒绝
  Origin、缺失/错误 Header，且不返回 CORS 授权；真实 HTTP 回归证明被拒请求不会交付
  lifecycle 或 action。该 Header 只关闭浏览器 localhost CSRF，不冒充 same-user 身份 Secret
- [x] 本地 Hook 再增加跨 macOS 用户授权边界：每个 listener epoch 轮换 256-bit 随机凭据，
  owner-only `0600`/128-byte Header 文件使用 descriptor-backed 原子替换；curl 只通过
  `-H @file` 读取，OpenCode 只保存路径并有界解析，Agent 配置、插件源码、argv、日志与诊断
  均不含值。服务端常量时间校验，缺失/旧值/错误值在 body 解码前返回 `{}`；随机源或文件
  边界失败时 listener 保持 unavailable，不降级为无认证模式
- [x] SwiftPM 依赖解析与最终产物闭合到同一 `Package.resolved`：PR/Release 先拒绝未跟踪、
  缺失或链接锁文件，完整测试与 Universal 两个架构全部使用 force-resolved 模式；App 构建
  限制锁文件为普通 1 byte–1 MiB，并在双架构结束后复核 SHA-256 未漂移。离线双 tag 夹具
  证明过期锁文件在强制模式下保持原字节失败，而普通 resolve 会自动改写；另覆盖缺失、
  symlink、空文件与超限攻击路径
- [x] 产品版本闭合到共享 fail-closed 验证器：移除 `VERSION` 缺失时静默回退 `0.1.0`，
  App、CI/tag、Cask、发布清单、SBOM 与下载者校验统一使用单行数字三段式；文件固定 owner、
  type、mode、nlink、1–64 byte 与读取前后 descriptor 稳定性，拒绝链接、空/多行、前导零、
  suffix、超限和 sed/path 注入。当前 prerelease 在单独冻结 Apple/Sparkle build-number 策略前
  保持关闭，避免“文件名是 beta、Bundle 却不可比较”的伪支持
- [x] App 构建输出改为私有暂存后原子发布：`BUILD_DIR` 先固定 owner/mode/location，禁止
  根目录、仓库/祖先、仓库内非 `build/`、最终 symlink 与不安全父目录；完整 App 在 sibling
  `0700` stage 内通过依赖与签名检查后才进入最终名。既有普通文件、symlink、冒名/未签名
  App 和 bundle-ID 漂移均不得覆盖，已验证旧代际通过同目录 backup 保留恢复路径。攻击夹具、
  两次 T7 Universal 构建/真实替换、634 项全量回归、完整门禁和 8 秒启动烟测均通过
- [x] Codex Hook trust stdio 生命周期改为 POSIX 独立进程组：移除 `Process`、reader thread
  与 semaphore，同一线程以 nonblocking stdin/stdout、`poll` 和 monotonic deadline 完成
  `hooks/list`；App Server 提前退出不再固定白等 3 秒，response/超时/2 MiB 超量/I/O 失败
  均按 TERM→KILL 清理完整 descendant group 并回收直接子进程。5 项真实子进程攻击回归
  固定立即退出、有效响应后的后台 descendant、静默超时、无限输出与关闭 stdin；对端
  关闭通过 `F_SETNOSIGPIPE` 退化为局部 I/O 失败，不能把整个 App 以 SIGPIPE 终止。新增
  5 轮独立稳定性脚本并接入 PR CI，成功路径不追加 XCTest 汇总，也不打印 App Server 输出
- [x] 系统 sleep/wake 的 Manus 恢复增加显式顺序 barrier：sleep 不再把 suspend 丢进无所有权
  detached task，TaskStore 保留并在 wake 前 await；power/service 双代际让新 sleep、Disconnect
  和 shutdown 后的旧 wake 静默失效，重复 wake 不再二次重启 public tunnel 或消耗 restart
  budget。阻塞 suspend、重复 wake、断开服务与在途 wake 失败 4 项确定性竞态回归通过，
  完整 TaskStore Manus 生命周期另接入 20 轮 PR CI 稳定性门禁；真实合盖/网络切换仍待解锁实测
- [x] Tag Release checkout 凭据隔离：Release 虽保留最终发布所需的 job 级写权限，但 checkout
  固定 `persist-credentials: false` 且禁止 token override；safe-YAML 验证器作为首个仓库命令，
  在依赖解析/manifest 求值前固定 checkout、步骤顺序与唯一 token 暴露。`GITHUB_TOKEN` 只允许
  进入最终 pinned GitHub Release action；缺失/启用 persistence、checkout token override、提前
  token env、伪装 PAT env、最终 token 缺失与 workflow symlink 七类回归由 Release foundation
  固定。该结果不替代远端 branch/tag/release 权限与 Actions allowlist，当前远端控制仍是
  商业发布 blocker
- [x] Settings → Agents 增加低噪音的 `Live connection check`：只在用户点击后于后台运行
  同一只读 probe，不写 Agent 配置；结果聚合为剩余设置数量与单一下一步，Hook 或监听器
  状态变化后立即失效，避免把陈旧结果当作已连接；中英文、Reduce Motion、无障碍提示
  与九宫格状态语义保持一致
- [x] Settings readiness 使用 latest-valid check token：Hook 安装状态或 listener 生命周期在
  检查期间变化时，同时清除旧快照并作废在途请求；旧 probe 即使晚到也不能覆盖新状态，
  新一轮检查仍可正常完成
- [x] `check-failed` 从“还需完成设置”的琥珀告警中独立出来：不计入 setup action，标题改为
  `Live check incomplete / 实时检查未完成`，详情只陈述暂时无法验证，邻接的
  `Check again / 再次检查` 保持唯一 CTA；静态 cyan 九宫格与更弱边框区分真实配置阻塞和
  仍在运行的检查。listener、安装、版本复核、Hook 更新/启用与 Codex trust 继续优先呈现
- [x] OpenCode Preview 固定 `1.18.23` / commit `13c2759…` 插件与 Event union；七类
  低频事件使用隐私最小 envelope，`retry` 保持 Running、只有 permission request 进入
  人工注意力；发送不 await 且 1 秒 fail-open abort，明确不修改 `permission.ask` output。
  完整插件文件使用 marker ownership、256 KiB 上限、`0600`、symlink/目录/碰撞拒绝，
  并进入 Disconnect All 删除/权限恢复/外部重建冲突回滚。真实 OpenCode 目录未修改，
  登录 CLI 验收前保持 observe-only Preview
- [x] OpenCode 固定同一 upstream commit 的官方 dark-square 标识与 SHA-256，原始几何保持
  不变，生成阶段只把官方双色转换为可随 Dev Island 明暗上下文着色的透明度层；MIT
  notice 随 App 打包。新增真实临时 `127.0.0.1` → `/hooks/opencode` HTTP 往返，验证
  200/`{}`、隐私最小解码、Waiting 与 observe-only 边界，不触碰真实 OpenCode 配置
- [x] 九个 Agent 品牌资产统一进入 schema v3 来源链：固定 revision/path、上游 SHA-256、
  受限 transform、本地 SVG、实际 1×/2× PNG 与随包 notice 哈希；Lobe Icons、Primer、
  OpenCode MIT 及 Kimi/Qwen Apache-2.0 证据均固定，攻击夹具会拒绝上游、transform 或
  notice 漂移。九个来源与资产版权许可均已工程复核，但全部商标展示仍保持 Release 阻断
- [x] 新增独立商标审批记录 schema v1：每个决定绑定展示用途/位置、源 SVG、18 个打包
  PNG、上游版本与许可 notice 的组合指纹；只翻 manifest、篡改指纹、不完整审批、仅单一
  地区批准和 review 符号链接均被攻击夹具拒绝。商业 Release 必须获得未过期的
  `WORLDWIDE` + direct download/GitHub Release/Homebrew 完整授权，当前 9 项仍全部阻断
- [x] Owner/legal 审查包改为仓库生成器原子产出：同输入逐字节确定、输出已存在时拒绝
  覆盖，缺失/伪 PNG/符号链接截图与符号链接输出父目录均失败；包内 machine manifest
  固定记录、四个展示面和九项指纹，`SHA256SUMS` 可发现生成后篡改。攻击夹具进入
  Release foundation，当前真实 v12 截图已生成 T7 v2 包
- [x] Welcome 固定 7 个本地连接器的选择从注册表简单截断改为 Stable 优先；新增
  OpenCode Preview 不再把已稳定支持的 Cursor 挤出首次引导。OpenCode 仍在完整 Settings
  列表中可发现；静态修复后截图保持 4×2 对齐，真实窗口交互仍待解锁验收
- [x] Welcome 连接页在多个 managed Hook 需修复时增加低噪音 `Update all / 全部更新`；
  仅顺序处理当前显示且状态为 `.updateRequired` 的 Agent，保留逐项结果与单独操作，不静默
  修改其他配置；每完成一项即落状态且只让当前项显示进度，剩余计数实时递减，英文单复数
  已校正。v11 中英文截图无裁切，2 张目标画面变化、31 张非目标画面逐字节不变
- [x] Homebrew 分发契约进入 PR/tag 门禁：Cask 先在隔离临时 tap 中确定性渲染，再通过
  真实 `brew style --cask` 与 `brew readall`；版本、ZIP URL/SHA、Bundle ID、
  macOS 下限、zap/Keychain 边界与禁止 latest/`:no_check`/安装脚本均 fail closed

### 当前验收状态

- [x] Welcome 三步离屏截图
- [x] Idle / Running / Waiting / Completed / Failed 五态截图
- [x] 注意力排序面板截图
- [x] 岛内审批截图
- [x] 岛内 AskUserQuestion 截图
- [x] 岛内 Plan Review 截图与修复后 Markdown 复验
- [x] Settings Agents 截图
- [x] Session History 截图
- [x] Launch Health 截图
- [x] 当前接受版产品审计报告与全部 PNG SHA-256 清单
- [x] Settings 真实连接检查的改前/初始/需处理三态离屏审计：卡片首屏不遮挡 Claude/Codex，
  需处理态仅使用细琥珀描边与九宫格点阵；8 项文案/聚合/晚到结果回归和 CI 只读契约门禁通过
- [x] English + 简体中文核心体验离屏审计：最终 24 张截图，中文 Welcome 三步、
  20 会话紧凑态、Settings Agents 与 Settings General 均无裁切或中英操作文案混排
- [x] 全应用简中离屏审计：Welcome、主岛、Settings 六页、Session History、审批、
  问答与空状态共 14 张当前源码截图，无产品文案混排、裁切或明显错位
- [x] Settings 控件节奏复审：37 张当前源码最终截图通过；English General / Notifications /
  Usage / Updates 与简中六页的 switch 固定在同一右边线，更新页显示 `0.3.0`。静态证据不
  替代真实 hover、键盘焦点、VoiceOver、Reduce Motion 与窗口滚动验收
- [x] 本轮 v7 静态体验审计与修复后截图；Welcome 开关对齐和岛内回退文案复验通过
- [x] 20 会话确定性排序压力门禁；人工请求按到达队列置顶，Waiting/Running 时间戳刷新不再引发行跳动
- [x] v8 无障碍/键盘静态回归：16 张最终截图通过，15 个既有场景与 v7 逐字节一致，新增 20 会话场景稳定
- [x] v9 主注意力流审计：17 张当前源码截图通过；修复中英混排、task/session 术语漂移及英文计数引发的标题截断，五态与 20 会话边界均完整
- [x] v10 静态精修审计：17 张当前源码截图通过；6 张目标画面变化、11 张非目标画面逐字节不变，人工介入去重、展开面板 session 语言与 Settings 对齐复验通过
- [x] v11 Welcome 连接恢复审计：33 张最终当前源码截图通过；中英文增加克制的批量更新入口，
  逐项完成反馈与单复数修复不改变静态接受画面；相对改前 2 张目标画面变化、31 张非目标
  画面逐字节不变，真实点击、焦点、VoiceOver 与动效仍待解锁验收
- [x] v13 Welcome 标题节奏审计：当前源码双语快照确认 English 第 2 页三行是唯一
  明显的局部层级问题；修复后标题稳定为两行，其余 Welcome 页与右侧矩阵无裁切。
  静态证据不替代真实翻页动效、键盘焦点、VoiceOver 或 Reduce Motion 验收
- [x] OpenCode 官方 Logo 与全部 Agent 徽章静态对齐图通过；官方原图与 Dev Island 模板
  输出保持同一几何，OpenCode 双色层在产品深色画布中清晰可辨。锁屏证据仅证明静态
  资源、缩放和裁切，不替代真实 Settings/hover/VoiceOver 验收
- [x] 5 项 AppKit 窗口级键盘事件契约通过；PR CI 安全门禁要求这些测试存在且全量测试执行
- [x] 诊断文件导出 5 项安全回归通过；CI 固定大小、权限、`O_NOFOLLOW`、`fsync`、`lstat`、原子 `rename` 与无上传边界
- [x] 发布门禁使用公开 RFC 8032 fixture 验证真实 Sparkle keypair：完整组合会通过 pinned
  `sign_update` 真签 + CryptoKit 验签；缺失凭据、错误 Team ID、公钥长度、公私钥错配和非法证书
  base64 均失败；无生产密钥进入本地测试
- [x] 更新契约 6 项聚焦回归与假公钥打包检查通过；其他 HTTPS 目的地、字段缺失、非每日调度、静默安装与画像均被拒绝，安全 keyless QA 包保持无更新元数据
- [x] 状态菜单 8 项聚焦回归与 648 项全量回归通过：注意力优先、总会话数、中英文单复数、
  旧完成态让位与精确到期边沿、监听器全状态、Manus 原始 reason 隔离及 AX 聚合值隐私；
  最终二进制无旧中文菜单文案
- [x] Release 完整性伪产物回归通过：7 个显式产物（含 SPDX）可复验，stable/versioned 字节不一致会拒绝且不覆盖上次有效清单；provenance action、OIDC 权限、发布前顺序与完整 subject 集合均由门禁固定
- [x] SPDX 生成器内建正/负向自测通过，并用真实 Universal QA App 复验 38 组件/38 关系：重复包、错误 revision、缺失许可、残缺 toml++ 宏、品牌源 SVG/打包 PNG 缺失或哈希漂移、覆盖既有输出或 SPDX 字节漂移均失败
- [x] 商业激活 8 项秘密内存/攻击/并发回归、IslandWindow 3 项能耗/延迟节奏回归、根岛 snapshot 3 项排序/状态回归、审批队列 projection 2 项到达顺序/孤立请求/键盘所有权回归与 Manus 真实验收工具 9 项凭据/关联/取消/清理回归通过；本地化语言解析/catalog/回退/格式化、历史/菜单/通知/Manus 展示、本地真实准备度、OpenCode Preview 19 项、官方品牌资源、Welcome Stable-first、批量更新候选与连接计数文案回归通过；全量 **539 tests，0 failures**，安全、法律/数据流、GitHub controls、CI 诊断、Release、性能、声音、日志隐私与本地化门禁通过
- [x] Manus 出站信任 5 项聚焦回归通过：生产 session 无 redirect/Cookie/cache，危险凭据、
  ID 与 callback transport 零调用，合法 task ID 不换路由，跨源 value/void 响应均拒绝，
  超大 Retry-After 固定为 300 秒；原 37 项 Manus 聚焦回归与安全门禁通过
- [x] Manus 入站内容与任务目的地新增 11 项攻击回归：API/Webhook 的 file/custom scheme、
  跨源、userinfo、端口、query/fragment、ID 不匹配、超长标题/消息与超大响应均拒绝；本地
  目录允许，但普通文件、App Bundle、remote file URL、失效路径及歧义裸 ID 对 opener 保持
  零调用。全量 **531 tests，0 failures** 与完整安全门禁通过
- [x] 多 Agent 状态合并彻底使用 `TaskIdentity(source,id)`：Manus Webhook 与轮询不再把
  裸 session ID 当全局身份，同 ID 的 Codex/Claude/Cursor 会话不会被 Manus 创建事件
  吞掉或被停止事件误改；所有 connector snapshot 只能提交自身 source，重复身份按稳定
  首见顺序保留最新值，错误来源与重复行不能注入其他 Agent 或触发 Dictionary 崩溃。
  新增 8 项回归后全量 **539 tests，0 failures**，完整安全门禁通过
- [x] 岛内动作队列资源边界新增 4 项直接回归：恶意 Unicode 字素、非有限/超长 timeout、
  全局 32 项和单会话 4 项容量、释放后恢复与零悬挂 continuation 均通过；全量
  **543 tests，0 failures**，完整安全门禁通过
- [x] 本地会话与历史容量新增 6 项直接回归：超长/控制字符 ID、cwd/generation/phase/message、
  128 会话注意力保留与确定性淘汰、5,000/20,000 SQLite 修剪、孤立进度清理及旧数据库
  打开即维护均通过；全量 **549 tests，0 failures**，完整安全门禁通过
- [x] SQLite 行内容信任边界新增 3 项直接回归：超限任务/进度写入整批回滚，当前 schema
  旧库打开时清除异常任务、异常进度及孤立内容，运行中被外部放大的行在 Swift 分配前由
  SQL 查询过滤；全量 **552 tests，0 failures**，完整安全门禁通过
- [x] SQLite 文件生命周期新增 8 项直接回归：既有 `0755/0644` 权限收敛为 `0700/0600`，
  数据库符号链接、最终目录链接、目录型数据库入口、多硬链接与 WAL sidecar 链接均失败
  关闭，目标/peer 字节保持不变且 sidecar 在 schema 前被拒绝；目录与主库双 descriptor
  anchor 还能拒绝“目录被替换后原数据库 inode 回到原路径”的重定向，并确保 sidecar
  收敛不接触替换目录中的入口；全量 **560 tests，0 failures**，完整安全门禁通过
- [x] SQLite 运行期文件边界新增 4 项直接回归：目录与主库 descriptor 随 Connection
  全生命周期保留；每次读取、写入和 Clear History 都在 SQLite 接触 sidecar 前以及操作
  返回/提交前后复验。运行中目录替换、恢复原数据库 inode 或新增 journal symlink 均失败
  关闭，写入/清空回滚、历史不返回，后续调用持续报告 unavailable；全量 **564 tests，
  0 failures**，完整安全门禁通过
- [x] 对照 Claude 画布完成当前源码 v13 审计：画布中“只能看、4 连接器、无历史/CI/
  Sparkle/本地化/商业底座”等判断已过时，不再按旧差距重复造功能。基于 33 张本轮新截图
  完成 Settings 本地主路径与微交互精修：Local Agents 固定领先可选 Manus，Claude/Codex
  更新回到首屏；八个连接器副标题补齐简中；Welcome、决策面和 Settings 统一 hover/press、
  Reduce Motion 与禁用 cursor；Quit 回归中性命令。新增 2 项顺序/本地化回归后全量
  **566 tests，0 failures**，完整安全门禁通过。锁屏状态下不宣称真实 hover、帧节奏或
  VoiceOver 已验收
- [x] Managed Hook 配置文件边界从 JSON/TOML 的高层路径读写收敛为统一 descriptor-backed
  事务：结构化配置限 4 MiB、OpenCode 插件限 256 KiB；目标 symlink/hard link、目录/
  device、错误 owner、group/other 可写或 dangling 父目录、超限和提交前字节漂移全部失败
  关闭。安全的配置目录 symlink 会解析一次并锚定具体目录，兼容 dotfiles 且后续链接变化
  不能重定向当前操作。新文件 `0600`、已有权限保留，同目录私有 staging、file+directory
  `fsync`、原子 rename、缺失目标 `RENAME_EXCL` 与 snapshot-aware Disconnect All 回滚共用
  同一边界；11 项直接攻击回归后全量 **577 tests，0 failures**，完整安全门禁通过
- [x] 关闭 Managed Hook 已有配置在“最终复验 → rename/unlink”之间的最后竞态：替换改为
  `RENAME_SWAP` 后验证 displaced snapshot，删除先移入私有 quarantine 再验证；若外部编辑器
  在最终窗口替换目标，原文件会无覆盖恢复，无法证明安全恢复时保留隔离字节并失败关闭。
  新增 2 项确定性攻击回归后全量 **579 tests，0 failures**，安全、法律/数据流与本地化门禁通过
- [x] Cloudflared Quick Tunnel 子进程建立硬启动/停止边界：stderr 改为独立 reader 持续排空，
  URL 前最多 1 MiB，timeout/cancel 不再等待取消不敏感的 AsyncStream；分片 URL 精确限制为
  安全的 `https://<label>.trycloudflare.com`，成功后仍只排空不保留。PATH 改为进程内解析，
  不再执行 `which` 且拒绝错误 owner/group-writable executable；静默、超量、提前退出和忽略
  TERM 均进入有界 SIGTERM→SIGKILL 清理。5 项进程边界回归（其中 3 项启动真实子进程）
  后全量 **584 tests，0 failures**，TunnelManager/Manus 验收清理回归与完整安全门禁通过
- [x] 精确 tmux 跳回移除 `Process.waitUntilExit` 与退出后读取 stdout 的管道死锁路径，和
  CLI version probe 共用 `BoundedChildProcess`：运行中 nonblocking drain、4 KiB 输出上限、
  monotonic deadline、独立进程组与 TERM→KILL，正常退出也清理遗留后台 descendant；tmux
  concrete executable 必须由 root/当前用户拥有且 group/other 不可写，最小环境不含 HOME。
  挂起并忽略 TERM、无限输出、可写 executable 与后台子进程 4 项攻击回归后全量
  **588 tests，0 failures**，完整安全门禁通过
- [x] Codex Local Usage 文件读取建立独立资源与信任边界：每次最多枚举 8,192 个目录项，
  扫描时只保留排序后的 top-N 候选（默认 24、硬上限 128），避免先累计完整目录；rollout
  通过 `O_NOFOLLOW` descriptor 校验普通文件、当前用户 owner 与不可被 group/other 写入，
  再以首次 `fstat` 固定的 offset/length 执行 exact `pread`，并发增长不能扩大本次尾部读取。
  默认 512 KiB、配置硬范围 4 KiB–2 MiB；枚举溢出、文件替换/缩短、读取失败与不安全候选
  全部仅让默认关闭的可选 insight 失败关闭。增长、枚举压力与可写文件 3 项攻击回归后全量
  **591 tests，0 failures**，v6.0.0 契约与完整安全门禁通过
- [x] Manus WebhookServer 在任何公网 tunnel/注册前增加本地监听器所有权证明：随机私有
  challenge 必须在 2 秒内由 7823 精确返回；共享 loopback probe 关闭 redirect、代理、
  Cookie 与缓存，按精确 Content-Length 流式比较最多 256 字节，不再累计无界 readiness
  响应。TunnelManager 在注册前后和 heartbeat 都复验服务；端口冲突、启动失败、注册中
  失效或运行中死亡都会删除已接受的 Webhook、停止进程并降级 polling-only。真实端口占用、
  验收工具启动失败、远端接受后回滚与 heartbeat 丢失共 6 项新回归后全量
  **597 tests，0 failures**，v6.1.0 契约与完整安全门禁通过
- [x] PR CI 诊断补齐品牌资产稳定 ID 与首失败定位，checkout 不再持久化 GitHub token，
  artifact 改用随机私有根和动态精确路径；security/test 日志改为 `NOFOLLOW|NONBLOCK`
  descriptor 校验 owner/type/mode/nlink、按初始尺寸 exact `pread` 并复验 metadata，禁止
  路径二次读取。symlink、17 MiB 超限与 hard-link 攻击只产生 schema-v2 低基数
  `sourceStatus`，不再让 always-run 诊断消失；品牌失败、链接/超限/硬链接与非泄漏夹具通过，
  全量 **597 tests，0 failures**，v6.2.0 契约、隐私/数据流和完整安全门禁通过
- [x] 本地双向 Hook 消除同一请求的 Waiting/决策竞态：actionable payload 必须先 await
  lifecycle snapshot，再进入人工请求队列，Allow/Deny 后不再被晚到 Waiting 覆盖；action
  source/session 与 endpoint/paired lifecycle 精确绑定，错身份时两边都不交付。passive
  lifecycle 仍立即返回 `{}`，不等待 MainActor/SQLite，守住 2 秒 fail-open 预算。真实
  loopback→TaskStore→Codex JSON、暂停式顺序、错身份和 passive 慢持久化回归通过；交互聚焦
  **40 tests，0 failures**，全量 **600 tests，0 failures**，v6.3.0 契约与完整安全门禁通过
- [x] lifecycle 跨请求交付从“每请求一个后台 Task”收敛为按 Agent source 独立的单 drain：
  同 source 严格串行、不同 source 可并行，同 session 尚未处理的 passive 状态合并为最新值；
  每 source 固定 256 项队列上限，passive flood 丢弃新项，action 优先淘汰最早 passive，
  全 action 满载时中立回退。真实 HTTP 证明早到 SessionStart 被暂停时后到审批不能越过，
  listener epoch 失效后排队状态/动作均不交付；18 项聚焦回归连续 20 轮通过，最终全量
  **606 tests，0 failures** 连续 5 轮通过，v6.4.0 契约与完整安全门禁通过
- [x] 自动更新运行期从 Sparkle 隐式自启动改为可观察的显式 throwing start：固定
  `startingUpdater: false`，在 KVO 就绪后调用 `updater.start()`；五态低基数状态机统一
  Settings 与状态菜单，启动失败释放 runtime、关闭 Check Now/自动检查写入并丢弃原始
  Sparkle Error，generation 拒绝晚到 callback。手动检查先原子进入 checking，重复点击
  不会发起第二次检查；keyless QA 构建保持零 runtime 构造。15 项聚焦回归、全量
  **610 tests，0 failures**、v6.5.0 契约与完整安全/本地化/数据流门禁通过
- [x] Sparkle 发布私钥从“stdin 但仍继承 secret environment”收敛为独立进程边界：tag
  workflow 只调用仓库自有包装器，私钥转入非导出 shell 缓冲后清空 Apple/P12/Keychain/
  Sparkle 全部已知凭据变量，再用 `env -i` 最小环境启动 pinned generator；私钥只经
  `--ed-key-file -` stdin 交付。真实 fake-generator 同时检查 child/parent env、完整 argv、
  log 与原始 stdin，缺 key、危险 tag、symlink generator 均失败关闭；全量
  **610 tests，0 failures**、v6.6.0 契约与完整 Release/安全/数据流门禁通过
- [x] Settings 五个 switch 的跨语言布局不再由 label intrinsic width 决定，统一为全宽
  双列行；English 四页视觉快照补齐，DEBUG 更新页显式使用产品版本而不触碰生产 updater。
  首轮全量测试出现一次未复现瞬时失败，随后同一二进制连续四轮 **611 tests，0 failures**；
  v6.7.0 契约、完整安全门禁和 Universal QA App 复验见本轮证据
- [x] 本地 CLI 版本探针把“真实版本漂移”与“本次检查未能完成”拆成不同产品状态：精确
  版本仍为 `verified`，缺失为 `unavailable`，漂移/已完成但格式异常为 `review-required`，
  spawn、timeout、超限与非零退出统一为 `check-failed`。Production 2 秒与 4 KiB 边界不变，
  Settings 中英文只提示重新检查，CLI 输出低基数 retry action，不再把瞬时调度压力误报为
  兼容性复核。24 项聚焦、20 轮 / 240 子进程压力回归、连续十轮 **616 tests，0 failures**、
  v6.8.0 契约、完整安全门禁与 Universal QA App 独立复验均通过
- [x] Settings readiness retry 完成第二层语义与视觉收口：`check-failed` 不再伪装成配置
  待办，也不覆盖已知真实阻塞；英文/简中改前与最终截图均通过 720×520 静态复核，25 项
  聚焦回归通过。v6.9.0 契约冻结双语文案、单一 CTA、静态 cyan 点阵与呈现优先级
- [x] tmux descendant cleanup 测试移除对 2 秒生产 deadline 内 fixture 调度速度的隐式依赖：
  Production 仍精确保持 2 秒，cleanup-only 测试使用隔离的 5 秒调度预算，忽略 TERM 的
  100 ms 硬边界不变；新增独立 20 轮 CI 稳定性 runner。连续十轮 **619 tests，0 failures**
  （累计 6,190 次）与 20 轮 cleanup stress 均通过，v6.10.0 契约和完整门禁复验通过
- [x] 首次完成解锁实机性能闭环，并修复采样门禁自身的 omitted-key 误判：独立显示会话探针
  只有在 current session 同时证明 active console + login done 时，才把缺失
  `CGSSessionScreenIsLocked` 判为 unlocked；warmup、每秒样本与结束持续复核。四个 60 秒
  场景平均 CPU 为 0.087%–0.952%，idle 0.303% 通过 1.0% 门禁；3 分钟 Expanded Running ×20
  平均 0.544%、RSS 斜率为负，60 秒 Time Profiler 无 hang rows 或 Dev Island busy loop。
  v6.11.0 契约、确定性 probe fixtures、真实截图与 T7 原始证据均已固定
- [x] v6.12.0 连续开合与长时性能闭环：20 个 Running 会话以 800 ms 最小延迟反复展开/收起，
  marker I/O 移出主线程后 122 个保存间隔稳定在 0.802–0.843 秒；Animation Hitches 稳态
  render 最大值从 600.504 ms 降至 14.810 ms，render >16.667 ms 从 11 次降为 0，App update
  最大 28.765 ms、GPU 最大 9.757 ms，唯一 69.445 ms all-layer 行无 App/render/GPU expensive
  narrative，按 compositor-only 留证。两个 Potential Hangs 行缺少对应 narrative/time-sample
  业务栈，且窗口内主队列 marker 仍有界，因此登记为 trace/model data gap，不伪称已定位卡死
- [x] 同机 60 秒 Activity Monitor 对比完成：20 行展开态相对 idle 的稳定 CPU 增量约 0.24 个
  百分点，idle wakeups 几乎无增量、preventing sleep 为 No、磁盘写入为 0；Xcode 26
  `Power Profiler` 明确不支持 macOS，因此该证据只称 CPU/wakeup 基线，不冒充电池续航
- [x] 30 分钟 Expanded Running ×20 共保留 1,800 个 unlocked 样本：平均 CPU 0.337%、p95
  1.600%，RSS 78,096 → 42,176 KiB，斜率 -661.745 KiB/min；v4 Leaks 61.056 秒为
  287 个系统框架责任对象 / 14,336 bytes，Dev Island 责任帧 0。QA `get-task-allow` 已从
  v3 的深签传播收紧为仅主 App，旧 v3 被负向门禁拒绝，v4/production 全闭包正向通过；
  v3/v4 六个去签名 Mach-O payload SHA-256 逐项一致。全量 **619 tests，0 failures**、
  完整安全/隐私/Release 基础门禁、240 子进程与 20 轮 tmux 压力复验通过
- [x] 商标审批门禁最终回归：发布基础与安全不变量通过，9 sources / 18 PNGs / 9 Release
  blockers 与 worldwide 正向夹具均符合预期；T7 Universal QA App 完成 6 个 Mach-O
  arm64+x86_64 依赖闭包、34 notices 和 strict deep ad-hoc 签名复验，并生成逐品牌
  owner/legal 审查包。该结果证明门禁有效，不代表任何商标已获准
- [x] Performance 合成样本门禁通过：精确统计 10 个线性样本，平均/p50/p95/峰值、RSS 增长与 6000 KiB/min 斜率均可复现；CPU、斜率、增长超阈值及畸形/符号链接 CSV 均 fail closed
- [x] 点阵渲染 2 项回归通过：并发同签名只生成一份关键帧且缓存有界；颜色/状态/重复布局不重建相同几何。20 会话三场景锁屏短烟雾均未闪退，但不作为 CPU、帧节奏或丝滑度结论
- [x] 面板动效分相最终 QA：静态内容与持续点阵/时钟分阶段启动，两个延迟回调均拒绝旧 generation 与已收起状态；490 项全量回归、完整安全/性能门禁、6 个 Universal Mach-O 依赖闭包、strict deep 签名及 Launch Services 3 秒冷启动通过。锁屏状态下不宣称真实丝滑度
- [x] Debug 与 Release 编译
- [x] Universal QA App（App + Sparkle 均为 arm64 / x86_64）
- [x] ad-hoc 严格签名校验
- [x] Launch Health v2 Universal QA App 真实冷启动超过稳定窗口、正常退出；App 与
  Sparkle 均为 arm64/x86_64，strict deep 签名通过，生产更新 key 与 Performance marker
  均不存在，最终启动状态 `ready=true / consecutive=0`
- [x] 先构建 Performance QA、再构建生产 App 的反向顺序隔离验收；两套 Universal 二进制与 plist 交叉门禁通过
- [x] 性能脚本锁屏默认拒绝验收（exit 5）；四场景锁屏短烟雾仅用于排除启动崩溃，不作为性能结论
- [x] 端口冲突耗尽 → 释放端口 → 模拟 wake → 恢复监听的确定性自动化测试
- [x] Manus 注册失败、wake 失败、heartbeat replacement 失败与 late registration 竞态的确定性自动化测试
- [x] Manus replay trust generation 绑定 exact callback URL + canonical ≥2,048-bit RSA identity；
  等价 PKCS#1/SPKI 不清窗口，URL/真实 key 轮换重置，旧代已认证请求交错返回 401 且不污染新窗口
- [x] 所有 accepted Webhook ID 立即持久化为集合；stop 先停止 attached process，并只在 bounded
  grace 内等待 cancellation-unaware registration；仍未知则保留 credential、launch owner 与 durable
  ambiguity marker 后 fail closed，晚到 accepted ID 先持久化再补偿删除。遗留/重叠 ID 在 provider
  `ok:true` 前不清除、不允许 replacement；polling-only cleanup owner 继续恢复 ledger，cleanup 失败
  保留旧 credential，并同时阻止 Disconnect 释放 credential 和 replacement key 覆盖
- [x] Manus polling stop/restart 晚到 fetch、网络边沿合并与 401 停止的确定性自动化测试
- [x] Manus 并发 Connect、验证中 Disconnect、换 key 晚到 snapshot、运行期 401、远端 cleanup
  失败保留 Keychain 与 Keychain 删除失败不假报成功的 TaskStore 级测试
- [ ] 用真实 Manus 账户完成 v2 公钥、signed test delivery、task_created、task_stopped(finish/ask)、删除和失败清理验收；通过前 Release gate 固定关闭
- [x] 解锁后的真实窗口连续开合夹具与 Animation Hitches 分层验收
- [x] 解锁后的真实审批/问答窗口验收：DEBUG-only Sandbox 通过生产
  `AgentActionRequest` 队列驱动 Codex Allow Once 与 Claude 两题问答；单选、第二题双多选、
  Back 草稿保持、两次 `⌘↩` 前进/提交及 waiting → running 恢复均通过。Debug Universal
  App 改用独立 `.build/app-debug`，不再与生产 bundle graph 共用 scratch
- [ ] 解锁后的真实 sleep/wake、锁屏与网络切换恢复验收
- [ ] VoiceOver 实机朗读顺序与完整键盘流程；当前已在真实 VoiceOver 进程运行时确认审批 AX
  顺序，并实测 `⌘D` 与 `⌘↩` 后回到 Working；但 spoken-output/focus 逐项记录、问答、Plan
  Review、Save Panel 与全键盘漫游仍未完成，因此不把本轮 AX/操作员观察冒充完整朗读验收
- [x] 解锁后实测 Save Panel 的 Escape 取消、同名覆盖确认后取消、T7 成功写入、只读目录
  失败反馈与零残留；导出文件保持 `0600`、单硬链接且仅含聚合状态
- [ ] VoiceOver 下完成 Save Panel 取消、覆盖确认、成功/错误反馈与键盘流程
- [x] Reduce Motion 代码契约补漏：bar↔panel 不再以短空间动画冒充淡入，收起岛 hover 不扩大
  capsule，复用任务/图标按钮及 Welcome 连接动作不再 press-scale；3 项策略回归与 645 项
  全量测试通过。当前屏幕锁定，因此仍不替代下一项系统开关实机目视验收
- [ ] macOS Reduce Motion / Increase Contrast 实机视觉验收；本轮已从系统设置真实开启 Reduce
  Motion，并在同一 Working 面板捕获相隔 250 ms 的逐字节相同帧；Increase Contrast 的 App 内
  对照、VoiceOver spoken output 与更多交互状态仍未完成。三项系统设置和测试进程已恢复并进入门禁
- [x] Settings 打开时真实进程切为 regular activation policy，关闭后回到 accessory；证明
  Dashboard/Settings 场景进入 Dock 且主岛独处时退出 Dock；v6.32.0 再将 16/32/64 ms
  生产重试抽成可注入 scheduler，测试不再 sleep 猜时序，租约回到已应用状态时立即废弃旧回调
- [x] 捕获并修复全量测试首次运行的两类调度型偶发红：Dock policy 13 项回归改为确定性排空，
  50 轮共 650 次通过；Codex process-group fixture 把独立 5 秒调度预算与 production 3 秒
  默认分开，仍强制读取 PID 并验证 descendant 退出，完整进程边界连续 5 轮通过
- [ ] 状态菜单、实际可闻声音、通知投递与 Focus Mode 实机验收；当前只证明试听动作不闪退，
  且系统通知关闭时设置页能给出明确入口
- [ ] 真实 CLI 验收中，Codex Allow Once 与 Deny 已闭环；Claude 审批/问答/Plan Review、Codex
  neutral timeout/native fallback，以及失败、中断和配置 reload 仍需逐项完成
- [x] 解锁后完成重复 launch readiness、四场景 CPU/RSS、60 秒 Time Profiler、3 分钟
  Expanded Running ×20 泄漏趋势与真实场景截图；全部样本初末均为 unlocked
- [ ] 当前机 Animation Hitches、30 分钟 RSS 与 Leaks 已完成；补充跨机器基线和 macOS 可用的
  直接能耗/电池证据后，再制定非 idle 场景 Release 阈值
- [ ] 新真实 tag 后运行 `scripts/release/verify-published-release.sh` 验证精确资产、GitHub build provenance + 全部 DMG/ZIP SBOM attestation，再完成旧版到新版的 Sparkle 端到端更新

当前真实环境预检（2026-08-30）：Claude Code `2.1.197` 与 Codex
`0.149.0-alpha.4.3` 均为 verified，本地 listener 为 listening；Claude managed Hook 为
update-required，Codex Hook 为 configured 且 activation 为 review-required，结果仍是
`ready-agents=0/2`；未自动修改真实 Agent 配置。远端 GitHub 只读审计确认当前 `main` 仍缺
required CI、PR review、conversation resolution、Actions allowlist、SHA pin policy 与
Dependabot security updates 六项控制；未经明确授权未修改远端设置。

## 四、下一批优化顺序

1. 在 Settings 更新 Claude managed Hook，并在 Codex `/hooks` 完成人工信任确认，然后重跑
   `local-live-readiness`；当前 listener/CLI 已验证，但这两项用户确认不能由自动化代替
2. Codex 已真实完成 Allow Once 与 Deny 的 running → waiting → 岛内决策 →
   resumed/completed；下一步用真实 Claude 会话覆盖审批、AskUserQuestion、Plan Review，并补
   Codex neutral timeout/native fallback、失败、中断和配置 reload
3. 有授权的真实 Manus 账户后，跑 v2 Webhook 端到端验收并决定是否打开 Release gate
4. 已完成 Welcome、空闲主岛、Settings readiness、20 会话静态/连续开合、30 分钟、
   Leaks，以及隔离审批/问答/Plan Review 的截图、AX 与部分真实键盘路由；下一步补充
   VoiceOver 实际朗读、第二题完整多选提交、系统 Reduce Motion/Increase Contrast 切换和
   sleep/wake 交互回归
5. 用真实多会话压力场景检查 5–20 会话排序稳定性、滚动和快速状态切换
6. 完成 VoiceOver、键盘、Reduce Motion 与 Increase Contrast 验收
7. 在通过实机门禁后再继续微调间距、文字密度、声音与 hover/press 节奏
8. 真实 CLI Preview 验收通过后再决定是否提升连接器发布等级
9. Owner/legal 使用 T7 `trademark-review-pack-v2` 对九个 Agent 标识逐项作出批准、拒绝或
   继续待审决定；只有带权限依据、UTC 时间、不可变证据 SHA、`WORLDWIDE` 与全部三种
   发布渠道的批准，才可同步回 manifest 与 review record
10. Owner/legal 填完并批准 `scripts/commerce/commercial-policy.json` 后，再按商业链路威胁模型
    完成 provider-specific sandbox 验收；通过前保持 activation service、生产 trust anchor 与
    UI 断开

## 五、证据位置

- Tag Release checkout 不持久化写权限 Git 凭据、首命令 safe-YAML 自检、唯一最终 publication
  token 暴露、七类攻击夹具与 Release/security/legal 门禁证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/security/release-checkout-credential-isolation-v1-20260829/RELEASE_CHECKOUT_CREDENTIAL_ISOLATION_EVIDENCE.md`

- 系统 sleep/wake 顺序 barrier、power/service 双代际、4 项确定性竞态回归、20 轮稳定性、
  全量回归与同源 QA App 证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/sleep-wake-ordering-v1-20260829/SLEEP_WAKE_ORDERING_EVIDENCE.md`
- 对应 keyless production-shaped QA App（Universal、strict deep ad-hoc、无生产更新 key/
  Performance marker；真实合盖/网络切换仍须在解锁环境验收）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/sleep-wake-ordering-v1-20260829/Dev Island.app`

- Codex App Server `hooks/list` nonblocking stdio、完整进程组回收、5 项真实进程攻击回归、
  5 轮专项稳定性、638 项全量回归、完整静态门禁与最终同源 QA App 证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/codex-stdio-process-v1-20260829/CODEX_STDIO_PROCESS_EVIDENCE.md`
- 对应 keyless production-shaped QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep
  ad-hoc、全闭包无 `get-task-allow`/Performance marker/生产更新 key，8 秒启动存活且仅
  loopback listener；仍非 Developer ID/公证 Release）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/codex-stdio-process-v1-20260829/Dev Island.app`

- 解锁 Welcome 三步、Settings 真实检查、主岛展开/收起与 12 次快速开合、20 会话紧凑/展开
  截图；四场景 60 秒 CPU/RSS、3 分钟长样本、60 秒 Time Profiler、显示会话探针修复、
  v6.11.0 契约与逐文件 SHA-256：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/unlocked-baseline-v1-20260828/AUDIT_REPORT.md`
- 对应隔离 Performance QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc、
  34 notices、无生产 Sparkle key/feed，不能发布）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/performance-unlocked-v1-20260828/Dev Island.app`

- Settings live-readiness retry 的中英文改前/改后截图、编号审计、v6.9.0/v6.10.0 契约、
  25 项 readiness 聚焦、15 项 tmux 聚焦、240 子进程与 20 轮 cleanup 压力回归、
  十轮 619 项全量测试及独立 QA App 复验：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/readiness-retry-flow-v1-20260828/AUDIT_REPORT.md`
- 当前最新 Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc、
  34 notices，生产 Sparkle Feed/key 与 Performance fixture 关闭，禁止扩展属性关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/builds/readiness-retry-flow-v1-20260828/Dev Island.app`

- CLI 版本探针调度压力复现、`check-failed` 产品语义、24 项聚焦、240 子进程压力回归、
  十轮 616 项全量测试、v6.8.0 契约与 QA App 独立复验：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/full-suite-stability-v1-20260828/LOCAL_VERSION_PROBE_STABILITY_EVIDENCE.md`
- 对应 v6.8.0 Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc、
  34 notices，生产 Sparkle Feed/Performance fixture 与禁止扩展属性关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/builds/local-version-probe-stability-v1-20260828/Dev Island.app`

- Settings 五个 switch 的跨语言固定尾部基线、English 四页补充、简中六页复验、
  37 张当前源码最终截图、v6.7.0 契约、611 项连续回归与 QA 独立校验：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/product-audit-v13-current-20260828/AUDIT_REPORT.md`
- 对应最新 Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc、
  34 notices，生产 Sparkle Feed/Performance fixture 与禁止扩展属性关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/builds/settings-control-rhythm-v1-20260828/Dev Island.app`

- Sparkle 私钥非导出缓冲、发布凭据环境清除、`env -i` 最小 generator、stdin-only key、
  真实子进程 child/parent/argv/log 夹具、三类失败关闭及 v6.6.0 契约：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/security/sparkle-secret-isolation-v1/SPARKLE_SECRET_ISOLATION_EVIDENCE.md`
- 对应最新 Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc、
  34 notices，生产 Sparkle Feed/Performance fixture 关闭，无 Finder/FileProvider/
  quarantine/resource-fork 污染）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/builds/sparkle-secret-isolation-v1-20260828/Dev Island.app`

- Sparkle 显式启动、五态低基数状态机、启动失败关闭、generation 晚到拒绝、手动检查
  去重、keyless 零构造、15 项聚焦及 610 项全量验证、v6.5.0 契约：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/update-runtime-lifecycle-v1/UPDATE_RUNTIME_LIFECYCLE_EVIDENCE.md`
- 对应最新 Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc、
  34 notices，生产 Sparkle Feed/Performance fixture 关闭，无 Finder/FileProvider/
  quarantine/resource-fork 污染）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/builds/update-runtime-lifecycle-v1-20260828/Dev Island.app`

- lifecycle 按 source 单 drain、同 session passive 合并、256 项容量、action 优先与全 action
  中立回退、listener epoch 拒绝、18 项聚焦/20 轮压力及 606 项全量验证、v6.4.0 契约：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/local-lifecycle-delivery-v1/LOCAL_LIFECYCLE_DELIVERY_EVIDENCE.md`
- 对应最新 Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc、
  34 notices，生产 Sparkle Feed/Performance fixture 关闭，无 Finder/FileProvider/
  quarantine 污染）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/builds/local-lifecycle-delivery-v1-20260828/Dev Island.app`

- 本地 Agent 同请求 lifecycle-before-action 顺序、错 source/session 双侧拒绝、passive
  2 秒 fail-open、40 项交互聚焦回归、600 项全量验证、v6.3.0 契约与 SHA-256：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/local-action-ordering-v1/LOCAL_ACTION_ORDERING_EVIDENCE.md`
- 对应最新 Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc、
  34 notices，生产 Sparkle Feed/Performance fixture 关闭，无 Finder/FileProvider/
  quarantine 污染）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/builds/local-action-ordering-v1-20260828/Dev Island.app`

- PR CI 11 道门禁、品牌首失败、descriptor-backed 有界日志读取、三类文件攻击安全降级、
  schema v2、597 项全量验证、v6.2.0 契约与 SHA-256：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/ci-diagnostics-file-boundary-v1/CI_DIAGNOSTICS_FILE_BOUNDARY_EVIDENCE.md`
- 对应最新 Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc、
  34 notices，生产 Sparkle Feed/Performance fixture 关闭，无 Finder/FileProvider 污染）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/builds/ci-diagnostics-file-boundary-v1-20260827/Dev Island.app`

- Manus WebhookServer 私有 ownership challenge、有界无重定向 loopback probe、注册前后与
  heartbeat 健康复验、6 项攻击/竞态回归、597 项全量验证、v6.1.0 契约与 SHA-256：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/manus-webhook-readiness-v1/MANUS_WEBHOOK_READINESS_EVIDENCE.md`
- 对应最新 Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc、
  34 notices，生产 Sparkle Feed/Performance fixture 关闭，无 Finder/FileProvider 污染）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/builds/manus-webhook-readiness-v1-20260827/Dev Island.app`

- Codex Local Usage 有限枚举、top-N、descriptor 校验、固定长度 `pread`、3 项攻击回归、
  591 项全量验证、v6.0.0 契约与 SHA-256：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/local-usage-file-boundary-v1/LOCAL_USAGE_FILE_BOUNDARY_EVIDENCE.md`
- 对应最新 Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc、
  34 notices，生产 Sparkle Feed/Performance fixture 关闭，无 Finder/FileProvider 污染）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/builds/local-usage-file-boundary-v1-20260827/Dev Island.app`

- tmux 跳回 nonblocking drain、4 KiB stdout、monotonic deadline、可信 executable、
  进程组 TERM→KILL/descendant 清理、4 项真实进程攻击回归与 588 项全量验证证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/tmux-process-boundary-v1/TMUX_PROCESS_BOUNDARY_EVIDENCE.md`
- 最新 tmux 进程边界 QA App（6 个 Mach-O 全部 Universal、strict deep ad-hoc、
  34 notices、生产更新/Performance fixture 关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/builds/tmux-process-boundary-v1-20260827/Dev Island.app`

- Managed Hook 已有配置最终替换/删除竞态闭合、2 项确定性攻击回归、579 项全量验证、
  v5.7.0 契约与 SHA-256：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/security/managed-config-final-race-v1/MANAGED_CONFIG_FINAL_RACE_EVIDENCE.md`
- 当前最新 Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc、
  34 notices，生产 Sparkle Feed/Performance fixture 关闭，无 Finder/FileProvider 污染）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/builds/managed-config-final-race-v1-20260827/Dev Island.app`

- Managed Hook JSON/TOML/plugin descriptor 边界、11 项攻击回归、577 项全量验证与
  Universal QA App 证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/security/managed-config-boundary-v1/MANAGED_CONFIG_BOUNDARY_EVIDENCE.md`
- 对应 Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc、34 notices，
  生产 Sparkle Feed/Performance fixture 关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/builds/managed-config-boundary-v1-20260827/Dev Island.app`

- 当前源码产品审计、33 张接受截图、交互精修说明与 SHA-256：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/design/interaction-polish-v2-final-20260827/INTERACTION_POLISH_EVIDENCE.md`
- 对应最新 Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc、
  生产 Sparkle Feed/Performance fixture 关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/builds/interaction-polish-v1-20260827/Dev Island.app`

- SQLite descriptor 保留到 Connection 全生命周期、运行中路径/sidecar 替换失败关闭、4 项
  直接回归与 564 项全量验证证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/sqlite-runtime-boundary-v1/SQLITE_RUNTIME_BOUNDARY_EVIDENCE.md`
- 对应 Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc、
  生产 Sparkle Feed/Performance fixture 关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/builds/sqlite-runtime-boundary-v1-20260827/Dev Island.app`

- SQLite 目录/主库/sidecar 类型、所有权、链接数、权限与目录+主库双 inode 锚定，8 项
  直接回归及 560 项全量验证证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/sqlite-file-boundary-v1/SQLITE_FILE_BOUNDARY_EVIDENCE.md`
- 对应 Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc、
  生产 Sparkle Feed/Performance fixture 关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/builds/sqlite-file-boundary-v1-20260827/Dev Island.app`
- SQLite 新写入、旧库打开维护与历史读取三层行内容限界、3 项直接回归及 552 项全量验证证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/sqlite-row-trust-v1/SQLITE_ROW_TRUST_EVIDENCE.md`
- 对应 Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc、
  生产 Sparkle Feed/Performance fixture 关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/builds/sqlite-row-trust-v1-20260827/Dev Island.app`
- 本地 Hook 字段、每连接器 128 会话、SQLite 5,000/20,000 自动保留、6 项直接回归与
  549 项全量验证证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/local-session-retention-v1/LOCAL_SESSION_RETENTION_EVIDENCE.md`
- 对应 Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc、
  生产 Sparkle Feed/Performance fixture 关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/builds/local-session-retention-v1-20260827/Dev Island.app`
- 岛内动作队列 90/120 秒生命周期、32/4 容量、字符+UTF-8 限界、4 项直接回归、
  543 项全量验证及 Universal QA App 证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/action-queue-bounds-v1/ACTION_QUEUE_BOUNDS_EVIDENCE.md`
- 对应 Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc、
  生产 Sparkle Feed/Performance fixture 关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/builds/action-queue-bounds-v1-20260827/Dev Island.app`
- 多 Agent `(source,id)` 状态隔离、snapshot 来源所有权、重复身份稳定合并、8 项攻击
  回归与 539 项全量验证证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/multi-agent-identity-v1/MULTI_AGENT_IDENTITY_EVIDENCE.md`
- 对应 Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc、
  生产 Sparkle Feed/Performance fixture 关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/builds/multi-agent-identity-v1-20260827/Dev Island.app`
- Manus 入站内容限界、官方任务页绑定、本地目录 Launch Services 边界、11 项攻击回归与
  531 项全量验证证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/security/task-destination-trust-v1/TASK_DESTINATION_TRUST_EVIDENCE.md`
- 对应 Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc、
  生产 Sparkle Feed/Performance fixture 关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/builds/task-destination-trust-v1-20260827/Dev Island.app`
- 产品体验证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/product-experience/`
- English + 简体中文核心体验最终截图与本地化证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/localization-final/`
- 全应用双语最终截图与源码覆盖门禁证据（31 张 PNG + SHA-256）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/localization-v10/LOCALIZATION_EVIDENCE.md`
- 最新双语 QA App（Universal、ad-hoc 签名、生产 Sparkle Feed 关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/localization-v2/Dev Island.app`
- 当前接受版产品审计（15 张 PNG + 报告 + SHA-256）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/product-audit-v5-accepted/`
- 本轮 v7 静态体验审计（锁屏离屏渲染，不能替代真实动效/可访问性验收）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/product-audit-v7-after/AUDIT_REPORT.md`
- 本轮 v8 无障碍/键盘静态审计（16 张最终截图；不能替代 VoiceOver 与键盘实机验收）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/product-audit-v8-accessibility-keyboard-final/AUDIT_REPORT.md`
- 本轮 v9 主注意力流与会话语言审计（17 张最终截图；真实动效、焦点与 VoiceOver 仍待解锁验收）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/product-audit-v9-session-language-accepted/AUDIT_REPORT.md`
- 本轮 v10 静态精修审计（17 张最终截图 + SHA-256；真实动效、滚动、焦点与 VoiceOver 仍待解锁验收）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/product-audit-v10-after/AUDIT_REPORT.md`
- 本轮 v11 Welcome 连接恢复最终审计（33 张最终截图 + SHA-256；真实点击、动效、焦点与 VoiceOver 仍待解锁验收）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/product-audit-v11-final/AUDIT_REPORT.md`
- 本轮 v12 当前源码复核（33 张新生成截图 + SHA-256；确认 Claude 画布已过时，真实交互与性能仍待解锁验收）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/product-audit-v12-current/AUDIT_REPORT.md`
- 本轮 v13 Welcome 标题节奏审计（同状态改前/改后截图、几何回归与 SHA-256；
  真实动效、焦点、VoiceOver 与系统开关仍待解锁验收）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/product-audit-v13-20260829/AUDIT_REPORT.md`
- 本轮真实决策窗口与辅助结构审计（Approval/Question/Plan/空态/紧凑态截图、4 份 AX 树、
  真实点击后 key-window 快捷键、629 项全量测试、双构建形态与 SHA-256；最终 v5 App 因
  锁屏尚待同二进制运行复抓，VoiceOver/系统辅助开关仍未宣称完成）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/interaction-audit-v9-20260829/AUDIT_REPORT.md`
- 最终源码 Performance QA App（6 个 Mach-O Universal、strict deep ad-hoc，仅主程序带
  `get-task-allow`，无生产更新 key，禁止分发）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/interaction-audit-v5-20260829/Dev Island.app`
- 最终源码 keyless production-shaped App（6 个 Mach-O Universal、strict deep ad-hoc、
  全闭包无 `get-task-allow`/Performance marker/生产更新 key；非 Developer ID/公证 Release）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/interaction-audit-v9-production-20260829/Dev Island.app`
- 真实 Git 工作树完整回归与同源 production-shaped 复验（629 tests / 0 failures、
  构建前 checksum 无差异、6 个 Mach-O Universal、全闭包无 `get-task-allow`、
  8 秒启动存活、343 项源码与 151 项 App 文件哈希；仍非 Developer ID/公证 Release）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/verification/real-worktree-release-v1-20260829/VERIFICATION_REPORT.md`
- 对应真实工作树同源 keyless production-shaped App：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/real-worktree-production-v1-20260829/Dev Island.app`
- 本地 Hook 浏览器 localhost CSRF 边界、113 项聚焦回归、629 项全量回归与最新同源
  production-shaped 构建证据（精确 `X-Dev-Island-Hook: v1`、拒绝 Origin/缺失或错误
  Header、无 CORS 授权；该 Header 不冒充 same-user Secret）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/security/local-hook-browser-boundary-v1-20260829/LOCAL_HOOK_BROWSER_BOUNDARY_EVIDENCE.md`
- 对应最新真实工作树同源 keyless production-shaped App（6 个 Mach-O Universal、
  strict deep ad-hoc、全闭包无 `get-task-allow`/Performance marker/生产更新 key，
  8 秒启动存活；仍非 Developer ID/公证 Release）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/real-worktree-browser-boundary-v1-20260829/Dev Island.app`
- 本地 Hook 跨 macOS 用户授权边界、148 项聚焦回归、634 项全量回归与最新同源
  production-shaped 构建证据（每 listener epoch 256-bit 随机凭据、私有 `0600`
  Header 文件、常量时间比较、旧 epoch/缺失/错误凭据 fail closed）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/security/local-hook-cross-user-auth-v1-20260829/LOCAL_HOOK_CROSS_USER_AUTH_EVIDENCE.md`
- 对应最新真实工作树同源 keyless production-shaped App（6 个 Mach-O Universal、
  strict deep ad-hoc、全闭包无 `get-task-allow`/Performance marker/生产更新 key，
  授权文件边界与 8 秒启动存活复验；仍非 Developer ID/公证 Release）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/real-worktree-cross-user-auth-v1-20260829/Dev Island.app`
- SwiftPM 锁文件产物边界、离线双 tag 自动漂移/强制拒绝夹具、634 项 force-resolved
  全量回归与同源 production-shaped 构建证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/resolved-dependency-boundary-v1-20260829/RESOLVED_DEPENDENCY_BOUNDARY_EVIDENCE.md`
- 对应 force-resolved keyless production-shaped App（构建前后锁文件 SHA-256 相同、
  6 个 Mach-O Universal、strict deep ad-hoc、全闭包无 `get-task-allow`/Performance
  marker/生产更新 key；仍非 Developer ID/公证 Release）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/real-worktree-resolved-dependency-v1-20260829/Dev Island.app`
- `VERSION` 到 App/Cask/Appcast/SBOM/归档/下载者校验的共享 fail-closed 边界、文件与注入
  攻击夹具、634 项全量回归及同源 production-shaped 构建证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/product-version-boundary-v1-20260829/PRODUCT_VERSION_BOUNDARY_EVIDENCE.md`
- 对应版本绑定的 keyless production-shaped App（两个 Apple bundle version 字段精确
  `0.3.0`、6 个 Mach-O Universal、strict deep ad-hoc、无生产更新 key；仍非 Developer ID/
  公证 Release）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/real-worktree-product-version-v1-20260829/Dev Island.app`
- App 构建输出目录、私有暂存、签名后原子发布、既有目标拒绝/替换、失败前保全与 634 项
  全量回归证据（v6.18.0；真实同目录二次替换无 staging/backup 残留）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/app-build-output-boundary-v1-20260829/APP_BUILD_OUTPUT_BOUNDARY_EVIDENCE.md`
- 对应最终 keyless production-shaped App（从校验一致 T7 源码快照构建，6 个 Mach-O 全部
  arm64+x86_64、strict deep ad-hoc、8 秒启动存活；仍非 Developer ID/公证 Release）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/app-build-output-boundary-v1-20260829/Dev Island.app`
- 窗口级键盘事件契约证据（真实 key-equivalent 分发；不替代 VoiceOver 实机验收）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/keyboard-contract-v1/KEYBOARD_CONTRACT_EVIDENCE.md`
- Reduce Motion 产品级空间静止契约、645 项全量回归与 Universal Debug QA 证据（屏幕锁定，
  不替代系统开关目视或 VoiceOver）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/reduced-motion-contract-v1-20260829/REDUCED_MOTION_CONTRACT_EVIDENCE.md`
- 解锁后的 Codex 审批、Claude 两题单选/多选/Back/键盘提交与 Debug graph 隔离证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/unlocked-action-surfaces-v1-20260829/UNLOCKED_ACTION_SURFACES_EVIDENCE.md`
- 安全诊断文件导出证据（文件系统与构建门禁）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/diagnostics-export-v1/DIAGNOSTICS_EXPORT_EVIDENCE.md`
- 解锁后的 Welcome、Settings/Dock、历史确认与 Save Panel 取消/覆盖/成功/失败证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/unlocked-system-interaction-v1-20260829/UNLOCKED_SYSTEM_INTERACTION_EVIDENCE.md`
- Release 凭据、Team ID 与最终 Gatekeeper 硬门禁证据（不替代真实签名、公证和跨版本更新）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/release-gate-hardening-v1/RELEASE_GATE_EVIDENCE.md`
- Sparkle 唯一 Feed 与完整运行时信任契约证据（假公钥包禁止运行/分发）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/updates/update-trust-contract-v1/AUTHENTICATED_UPDATE_CONTRACT_EVIDENCE.md`
- macOS 状态菜单语言、优先级与隐私边界证据（真实菜单仍待解锁验收）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/status-menu-v1/STATUS_MENU_EVIDENCE.md`
- v6.31.0 状态菜单实时快照、总会话数、事件驱动刷新、AX 隐私、648 项全量回归与 Universal
  Debug QA App 证据（显示会话锁定，不替代真实菜单或 VoiceOver）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/status-menu-live-v1-20260829/STATUS_MENU_LIVE_EVIDENCE.md`
- v6.32.0 Dock 确定性重试、旧 generation 失效、Codex fixture 调度隔离、Dock 50 轮/
  650 次、Codex 5 轮、648 项全量回归与 Universal Debug QA App 证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/dock-retry-scheduler-v1-20260829/DOCK_RETRY_SCHEDULER_EVIDENCE.md`
- Release 完整性清单与 GitHub build provenance 静态门禁证据（真实 tag 仍待验收）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/release-provenance-v1/RELEASE_PROVENANCE_EVIDENCE.md`
- Homebrew Cask 真实 style/readall、确定性渲染、危险 stanza 拒绝与公开 v0.3.0 ZIP 哈希证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/homebrew-distribution-v1/HOMEBREW_DISTRIBUTION_EVIDENCE.md`
- 确定性 SPDX 30 组件/30 关系、OpenCode 官方资产、下载者负向夹具与官方 Schema
  证据（真实 tag / GitHub attestation 仍待验收）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/sbom-brand-assets-v2/SBOM_BRAND_ASSETS_EVIDENCE.md`
- 9 个 Agent 源 SVG、18 个实际打包 PNG、38 组件 SPDX、官方 Schema、商业品牌复核硬门禁与
  攻击夹具证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/sbom-all-agent-brands-v3/ALL_AGENT_BRAND_SUPPLY_CHAIN_EVIDENCE.md`
- 9 个 Agent 不可变 revision/path/上游 SHA-256、受限 transform 与 notice 哈希的 schema v3 来源链、
  Lobe Icons / Primer notices、38 组件 SPDX 与商标审批 fail-closed 证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/sbom-all-agent-brands-v4/ALL_AGENT_BRAND_SUPPLY_CHAIN_EVIDENCE.md`
- Kimi/Qwen Apache-2.0 许可结论、schema v3 notice 内容哈希、notice 篡改夹具、38 组件 SPDX
  与九项商标审批继续 fail-closed 的最新证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/sbom-all-agent-brands-v5/ALL_AGENT_BRAND_SUPPLY_CHAIN_EVIDENCE.md`
- 独立离线/线上 Release 验证器、19 类攻击夹具与公开 v0.3.0 legacy-failure 证据（新真实 tag 仍待验收）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/published-release-verifier-v1/PUBLISHED_RELEASE_VERIFIER_EVIDENCE.md`
- GitHub required CI/review、Actions allowlist/SHA pin、Secret Scanning/Dependabot 策略夹具与当前远端 6 项缺口证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/security/github-repository-controls-v1/GITHUB_REPOSITORY_CONTROLS_EVIDENCE.md`
- v6.33.0 GitHub 在线审计 network/authentication/administration/rate-limit/unexpected 低基数分类、
  fake-gh 零回显夹具、648 项全量回归、完整安全门禁与 Universal Debug QA App 证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/github-audit-classification-v1-20260829/GITHUB_AUDIT_CLASSIFICATION_EVIDENCE.md`
- v6.34.0 权威测试 `.build/tests-authoritative` 图隔离、648 项全量回归、20+20+5+20 轮
  `--skip-build` 稳定性、66 次 fake-swift 调用、完整门禁与 Universal Debug QA App 证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/authoritative-test-graph-v1-20260829/AUTHORITATIVE_TEST_GRAPH_EVIDENCE.md`
- v6.35.0 权威测试图单写者锁、真实并发竞争、五类恶意 lockfile、648 项全量回归、
  65 轮复用、完整门禁及并行 Universal Debug QA App 构建证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/authoritative-test-lock-v1-20260829/AUTHORITATIVE_TEST_LOCK_EVIDENCE.md`
- v6.36.0 Welcome 编辑栏节奏修复、同状态双语改前/改后快照、几何回归、649 项全量回归、
  65 轮稳定性、完整安全门禁与 Universal Debug QA App 证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/product-audit-v13-20260829/AUDIT_REPORT.md`
- 对应 Universal Debug QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc，
  生产 Sparkle Feed/Performance fixture 关闭，禁止分发）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/welcome-editorial-rhythm-v1-20260829/Dev Island.app`
- v6.37.0 商业政策审批记录 descriptor/path/parent 输入边界、根层/嵌套重复 JSON key
  拒绝、18 类攻击夹具、`required / missing=36` 与 `--require-approved` 反向证据、649 项
  全量回归、65 轮复用、完整门禁与 Universal Debug QA App 证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/security/commercial-policy-input-boundary-v1-20260829/COMMERCIAL_POLICY_INPUT_BOUNDARY_EVIDENCE.md`
- 对应 Universal Debug QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc，
  生产 Sparkle Feed/Performance fixture 关闭；主程序与 v6.36 QA 逐字节一致，禁止分发）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/commercial-policy-input-boundary-v1-20260829/Dev Island.app`
- v6.38.0 产品级 Increase Contrast 角色系统、39 组标准/增强同尺寸快照、三张人工复核拼图、
  像素差异表、4 项策略回归、652 项全量、65 轮稳定性与 Release-shaped Universal QA App 证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/product-contrast-v1-20260829/PRODUCT_CONTRAST_EVIDENCE.md`
- 对应 Release-shaped Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc，
  生产 Sparkle Feed、Performance fixture 与 DEBUG contrast override 关闭，禁止分发）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/product-contrast-v1-20260829/output/Dev Island.app`
- v6.39.0 三种构建风味实际可执行文件矩阵、18 个逐标记负向夹具、652 项权威测试、
  65 轮稳定性、三套 Universal App 与完整发布门禁证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/build-flavor-isolation-v1-20260829/BUILD_FLAVOR_ISOLATION_EVIDENCE.md`
- 对应 Production / Performance QA / Debug App（全部 6 个 Mach-O、arm64+x86_64、strict
  deep ad-hoc；Performance 与 Debug 禁止分发，三者均非 Developer ID / notarized Release）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/build-flavor-isolation-v1-20260829/`
- v6.40.0 双语法律原文 descriptor/结构/日期/Bundle 字节绑定、10 类攻击夹具、4 张英中离屏
  快照、659 项权威测试、65 轮稳定性与 Release-shaped Universal QA App 证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/bundled-legal-documents-v1-20260829/BUNDLED_LEGAL_DOCUMENTS_EVIDENCE.md`
- 对应 Release-shaped Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc，
  生产 Sparkle Feed、Performance 与 DEBUG marker 关闭；仍非 Developer ID / notarized Release）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/bundled-legal-documents-v1-20260829/output/Dev Island.app`
- v6.41.0 Welcome 三步当前源码审计、最终决策页出口收敛、改前/改后像素对比、660 项权威
  测试、65 轮稳定性与 Release-shaped Universal QA App 证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/product-audit-v14-20260829/AUDIT_REPORT.md`
- 对应 Release-shaped Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc，
  Production marker 干净、生产 Sparkle Feed 关闭；仍非 Developer ID / notarized Release）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/welcome-final-step-v1-20260829/output/Dev Island.app`
- v6.42.0 App 内法律资源单 descriptor 原子读取、6 类运行时边界回归、666 项权威测试、
  65 轮稳定性、Universal 产物复验与隔离 HOME 真实启动/干净退出证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/security/legal-resource-reader-v1-20260829/LEGAL_RESOURCE_READER_EVIDENCE.md`
- 对应 Release-shaped Universal QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc，
  Production marker 干净、生产 Sparkle Feed 关闭；仍非 Developer ID / notarized Release）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/legal-resource-reader-v1-20260829/output/Dev Island.app`
- v6.43.0 PR CI hermetic App 真实启动、私有 CFFIXED home、readiness、8 秒存活、精确 PID
  AppKit terminate、status 0 与 T7 含空格路径回归证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/hermetic-launch-smoke-v1-20260829/HERMITIC_LAUNCH_SMOKE_EVIDENCE.md`
- 对应 Universal Performance QA App（6 个 Mach-O 全部 arm64+x86_64、strict deep ad-hoc，
  编译期隔离且禁止分发）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/hermetic-launch-smoke-v1-20260829/performance/Dev Island.app`
- v6.44.0 Performance 三文件原子 descriptor 所有权、token-bound 私有分析快照、5 类夹具连续
  10 轮、fresh Universal App 8 样本启动/正常退出、666 项权威测试、65 轮稳定性与完整门禁证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/performance-evidence-boundary-v1-20260829/PERFORMANCE_EVIDENCE_BOUNDARY_EVIDENCE.md`
- 对应 fresh Universal Performance QA App（主 executable SHA-256
  `0512d567d28e8feae1f917413d1ce2dd9f9d039734c38c8283c9e519a7a17486`；6 个 Mach-O 全部
  arm64+x86_64、strict deep ad-hoc、编译期隔离且禁止分发）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/performance-evidence-boundary-v1-20260829/build-v6.44/Dev Island.app`
- v6.45.0 readiness App-log token-bound 私有快照、FIFO/替换 nonblocking 拒绝、唯一 marker 与
  5.5 秒 launch window、6 类夹具连续 10 轮、真实 8 样本整合 smoke、666 项权威测试、65 轮
  稳定性及完整门禁证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/readiness-log-snapshot-v1-20260829/READINESS_LOG_SNAPSHOT_EVIDENCE.md`
- 对应 fresh Universal Performance QA App（主 executable SHA-256
  `d2eeeecad5d7a542a2e521bccb736a23cb17fd6233e8eb879a2c0f0d8eaab41f`；6 个 Mach-O 全部
  arm64+x86_64、strict deep ad-hoc、编译期隔离且禁止分发）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/readiness-log-snapshot-v1-20260829/build-v6.45/Dev Island.app`
- v6.46.0 Performance 输入 App 私有快照、来源/副本身份回绑、最终替换攻击、10×7 夹具、
  8 样本整合 smoke、666 项权威测试、65 轮稳定性与完整门禁证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/performance-app-snapshot-v1-20260829/PERFORMANCE_APP_SNAPSHOT_EVIDENCE.md`
- 对应 fresh Universal Performance QA App（主 executable SHA-256
  `3fc307e8ab4bb8ac2691373238f6ca98469b2d9f916f7d3961b0fd2d0e340d8d`；6 个 Mach-O 全部
  arm64+x86_64、strict deep ad-hoc、编译期隔离且禁止分发）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/performance-app-snapshot-v1-20260829/build-v6.46/Dev Island.app`
- v6.47.0 PR CI summary 进程内交付、真实 post-exit public-path replacement、8 样本整合 smoke、
  666 项权威测试、65 轮稳定性与完整门禁证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/ci-performance-summary-memory-v1-20260829/CI_PERFORMANCE_SUMMARY_MEMORY_EVIDENCE.md`
- 对应 fresh Universal Performance QA App（主 executable SHA-256
  `2a3961d26a1efc978cdb61bf4ef6fea095a79090878c368607544cd462ac68fe`；6 个 Mach-O 全部
  arm64+x86_64、strict deep ad-hoc、编译期隔离且禁止分发）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/ci-performance-summary-memory-v1-20260829/build-v6.47/Dev Island.app`
- v6.48.0 无副作用 listener transport 与 v6.49.0 外置 SwiftPM scratch 边界、668 项权威测试、
  10 轮 listener、完整门禁及 Production Universal App 独立复验：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/hermetic-local-readiness-and-external-scratch-v1-20260829/HERMETIC_LOCAL_READINESS_AND_EXTERNAL_SCRATCH_EVIDENCE.md`
- 对应 v6.49 Production-shaped Universal App（主 executable SHA-256
  `cff223d103b5ee2acbd29f34683b8353596d40b7a08c4a78ef6ea58e4c2e755d`；6 个 Mach-O 全部
  arm64+x86_64、strict deep ad-hoc、无生产 Sparkle key，仍非 Developer ID/公证 Release）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/hermetic-local-listener-v1-20260829/build-v6.49/Dev Island.app`
- v6.50.0 真实 Production App hermetic 启动、逐秒服务隔离、671 项权威测试、65 轮稳定性、
  10 轮 listener 与完整 security/release/static 门禁只读证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/production-app-hermetic-launch-v1-20260829/PRODUCTION_APP_HERMETIC_LAUNCH_EVIDENCE.md`
- 对应 v6.50 Production-shaped Universal App（主 executable SHA-256
  `acca055e72285d0f41ac39da56e1eca9efc7cd8f00d822513720cc0ec2eeaa98`；6 个 Mach-O 全部
  arm64+x86_64、strict deep ad-hoc、无生产 Sparkle key；真实 smoke 的 selected/private 哈希
  相等、8/8 样本、正常 status 0，仍非 Developer ID/公证 Release）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/hermetic-local-listener-v1-20260829/build-v6.50/Dev Island.app`
- v6.50 原始 append-never CSV/App log/summary（显示会话 locked，禁止用于性能宣称）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/production-app-hermetic-launch-v1-20260829/`
- v6.51.0 Settings Agent 配置 I/O 主线程隔离、6 项聚焦、677 项权威测试、65 轮稳定性、
  10 轮 listener、完整 static/security/release 门禁、fresh Production App 与只读证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/settings-agent-config-io-v1-20260829/SETTINGS_AGENT_CONFIG_IO_EVIDENCE.md`
- 对应 v6.51 Production-shaped Universal App（主 executable SHA-256
  `2d64f7493ef3edaf9164d7981172c36cb34f35b1779eee6b387fa139e20831ab`；6 个 Mach-O 全部
  arm64+x86_64、strict deep ad-hoc、无生产 Sparkle key；真实 hermetic smoke 的 selected/private
  哈希相等、8/8 样本、readiness 1,542 ms、正常 status 0，仍非 Developer ID/公证 Release）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/hermetic-local-listener-v1-20260829/build-v6.51/Dev Island.app`
- v6.51 原始 append-never CSV/App log/summary（显示会话 locked，禁止用于性能或丝滑度宣称）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/settings-agent-config-io-v1-20260829/`
- v6.52.0 Plan Review Markdown 单次后台渲染、19 项计划/决策回归、684 项权威测试、65 轮
  稳定性、10 轮 listener、fresh Production App 与只读证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/plan-review-render-isolation-v1-20260829/PLAN_REVIEW_RENDER_ISOLATION_EVIDENCE.md`
- 对应 v6.52 Production-shaped Universal App（主 executable SHA-256
  `80936a5f4d7e38e8345f50a43cc7759c4cbf101b51b37c42153c6a9745c543a3`；6 个 Mach-O 全部
  arm64+x86_64、strict deep ad-hoc、无生产 Sparkle key；真实 hermetic smoke 的 selected/private
  哈希相等、8/8 样本、readiness 1,118.7 ms、正常 status 0，仍非 Developer ID/公证 Release）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/hermetic-local-listener-v1-20260829/build-v6.52-final/Dev Island.app`
- v6.52 原始 append-never CSV/App log/summary（显示会话 locked，禁止用于性能或丝滑度宣称）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/plan-review-render-isolation-v1-20260829/`
- v6.53.0 展开面板叶子时钟隔离、5 项纯策略回归、689 项权威测试、65 轮稳定性、10 轮
  listener、fresh Production App 与只读证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/panel-clock-leaf-isolation-v1-20260829/PANEL_CLOCK_LEAF_ISOLATION_EVIDENCE.md`
- 对应 v6.53 Production-shaped Universal App（主 executable SHA-256
  `7ebe81010c05294e49b49872675f67caccb2ac6cf93e0ae703b9c0d9f79ab598`；6 个 Mach-O 全部
  arm64+x86_64、strict deep ad-hoc、无生产 Sparkle key；真实 hermetic smoke 的 selected/private
  哈希相等、8/8 样本、readiness 1,515.2 ms、正常 status 0，仍非 Developer ID/公证 Release）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/hermetic-local-listener-v1-20260829/build-v6.53-final/Dev Island.app`
- v6.53 原始 append-never CSV/App log/summary（显示会话 locked，禁止用于性能或丝滑度宣称）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/panel-clock-leaf-isolation-v1-20260829/`
- GitHub Workflow `run:` Bash 静态语法、最小环境无执行解析、descriptor 边界与 8 类攻击夹具证据（不替代真实 GitHub runner/tag 验收）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/workflow-run-shell-boundary-v1-20260829/WORKFLOW_RUN_SHELL_BOUNDARY_EVIDENCE.md`
- GitHub Workflow safe-load 前的单文档/重复 key/结构资源边界、15 类攻击夹具与 mtime/ctime 稳定性证据（不替代 GitHub workflow schema 或真实 runner/tag 验收）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/workflow-yaml-ambiguity-boundary-v1-20260829/WORKFLOW_YAML_AMBIGUITY_BOUNDARY_EVIDENCE.md`
- GitHub Workflow step/job/workflow 有效 shell 继承、精确 Bash allowlist 与 20 类攻击夹具证据（不替代 runner 命令执行或远端策略验收）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/workflow-effective-shell-boundary-v1-20260829/WORKFLOW_EFFECTIVE_SHELL_BOUNDARY_EVIDENCE.md`
- 41 Bash + 14 Ruby 仓库脚本无执行语法闭包、Bash 前置副作用真实复现与 11 类攻击夹具证据（不替代脚本业务命令或真实 runner 成功）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/repository-script-syntax-closure-v1-20260829/REPOSITORY_SCRIPT_SYNTAX_CLOSURE_EVIDENCE.md`
- 41 Bash + 14 Ruby + 5 Swift 三语言仓库脚本闭包、Swift 顶层副作用零执行与 13 类攻击夹具证据（parse-only 不替代 type-check 或脚本业务输出）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/repository-script-swift-parse-closure-v1-20260829/REPOSITORY_SCRIPT_SWIFT_PARSE_CLOSURE_EVIDENCE.md`
- PR CI always-run 脱敏摘要、失败 artifact、Secret 非泄漏夹具与本地真实日志样本证据（远端失败/成功 PR 仍待验收）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/ci-diagnostics-v1/CI_DIAGNOSTICS_EVIDENCE.md`
- Performance 统计、证据完整性与泄漏趋势门禁（锁屏集成烟雾不构成产品性能结论）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/performance-analysis-v1/PERFORMANCE_ANALYSIS_EVIDENCE.md`
- 连续开合 Animation Hitches、Activity Monitor、v3/v4 Leaks、30 分钟展开态、最小权限签名、
  全量回归与限制说明的最终审计（原始 trace/XML/CSV/log 与 `SHA256SUMS` 同目录）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/transition-hitches-v2-20260829/AUDIT_REPORT.md`
- 最终最小权限 Performance QA App（仅主 App 带 `get-task-allow`；6 个 Mach-O Universal、
  strict deep ad-hoc、无生产 Sparkle key，禁止分发）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/instrumented-v4-20260829/Dev Island.app`
- 最终 keyless production-shaped App（6 个 Mach-O Universal、全闭包无 `get-task-allow`、
  strict deep ad-hoc；仍不是 Developer ID / notarized Release）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/production-v4-20260829/Dev Island.app`
- v6.12.0 全量测试、安全门禁、240 子进程、tmux 20 轮与最终 Bundle 复验日志：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/verification/v6.12.0-20260829/`
- 点阵关键帧缓存、几何去重、构建隔离与早期 20 会话锁屏烟雾证据（后续解锁帧节奏见上方最终审计）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/dot-matrix-rendering-v1/DOT_MATRIX_RENDERING_EVIDENCE.md`
- IslandWindow 空闲轮询节奏证据（事件驱动边界、1 Hz watchdog、25 Hz 岛内光标；直接能耗证据仍待补充）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/idle-window-cadence-v1/IDLE_WINDOW_CADENCE_EVIDENCE.md`
- IslandWindow 展开阅读态节奏证据（25 Hz 严格限于紧凑岛，展开面板 1 Hz，每分钟减少 1,440 次主线程唤醒；直接能耗证据仍待补充）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/interaction-cadence-v1/INTERACTION_CADENCE_EVIDENCE.md`
- 最新交互节奏 QA App（Universal、ad-hoc、生产更新/Performance fixture 关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/interaction-cadence-v1/Dev Island.app`
- 根岛单次 presentation snapshot、单遍状态计数与展开阅读态 1 Hz watchdog 综合证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/render-hot-path-v1/RENDER_HOT_PATH_EVIDENCE.md`
- 最新渲染热路径 QA App（Universal、ad-hoc、生产更新/Performance fixture 关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/render-hot-path-v1/Dev Island.app`
- 面板动效分相、快速开关 generation guard、490 项回归与最终 Bundle 证据（锁屏下不构成真实帧节奏结论）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/panel-activity-staging-v1/PANEL_ACTIVITY_STAGING_EVIDENCE.md`
- 最新面板动效分相 QA App（6 个 Mach-O 全部 Universal、ad-hoc、生产更新/Performance fixture 关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/panel-activity-staging-v1/Dev Island.app`
- 展开面板审批队列单次线性 projection、根岛状态计数复用、13 轮 492 项 soak 与最终 Bundle 证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/panel-queue-projection-v1/PANEL_QUEUE_PROJECTION_EVIDENCE.md`
- 最新综合性能 QA App（动效分相 + 队列 projection；6 个 Mach-O 全部 Universal、ad-hoc、生产更新/Performance fixture 关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/panel-queue-projection-v1/Dev Island.app`
- OpenCode Preview 隐私 envelope、插件 ownership、官方品牌资产、真实 loopback route 与
  Universal QA 证据（真实 CLI/目录未触碰，锁屏下不构成完整视觉验收）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/connectors/opencode-preview-v2/OPENCODE_PREVIEW_EVIDENCE.md`
- 最新 OpenCode Preview 综合 QA App（6 个 Mach-O 全部 Universal、ad-hoc、官方 Logo 与
  MIT notice 已打包、生产更新/Performance fixture 关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/opencode-preview-v2/Dev Island.app`
- 20 会话稳定排序与静态压力证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/multi-session-stress-v1/STABLE_ORDER_EVIDENCE.md`
- 商业 License 存储证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/commercial-license/COMMERCIAL_LICENSE_STORAGE_EVIDENCE.md`
- 商业激活核心与并发/取消证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/commercial-activation-v1/COMMERCIAL_ACTIVATION_EVIDENCE.md`
- 商业激活码秘密内存生命周期证据（专用共享分配、`memset_s`、双架构产物）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/security/commercial-secret-memory-v1/COMMERCIAL_SECRET_MEMORY_EVIDENCE.md`
- 商业政策 schema v1、36 项显式未决字段、严格审批门禁与攻击夹具证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/commercial-policy-gate-v1/COMMERCIAL_POLICY_GATE_EVIDENCE.md`
- 逐品牌商标审批 schema v1、九项组合指纹、四个产品展示面、完整资产/notice 与
  owner/legal 审查表、确定性 machine manifest 与 SHA256SUMS（当前九项仍为 required）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/trademark-review-pack-v2/`
- 审查包原子生成器、确定性复现、九类完整性/覆盖/符号链接攻击夹具与锁屏证据限制：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/trademark-review-packet-generator-v1/TRADEMARK_REVIEW_PACKET_EVIDENCE.md`
- 商业激活 QA App（Universal、ad-hoc 签名、无生产更新 key / License trust anchor）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/commercial-activation-v1/Dev Island.app`
- Launch Health v2、历史闪退根因、5 轮全量回归与真实冷启动证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/launch-health-v2/LAUNCH_HEALTH_V2_EVIDENCE.md`
- 最新启动可靠性 QA App（Universal、ad-hoc、生产更新/Performance fixture 关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/launch-health-v2/Dev Island.app`
- 全 App 依赖闭包、8 类攻击夹具、CI/Release 签名前门禁与最终冷启动证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/bundle-dependency-closure-v1/APP_BUNDLE_DEPENDENCY_CLOSURE_EVIDENCE.md`
- 最新依赖闭包 QA App（6 个 Mach-O 全部 Universal、ad-hoc、生产更新/Performance fixture 关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/bundle-dependency-closure-v1/Dev Island.app`
- Wake Recovery 可靠性证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/wake-recovery-v1/WAKE_RECOVERY_EVIDENCE.md`
- Claude/Codex 真实链路准备度、子进程时序加固与当前本机缺口证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/local-live-readiness-v1/LOCAL_LIVE_READINESS_EVIDENCE.md`
- CLI 版本子进程完成竞态、连续快速退出回归与完整门禁证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/cli-version-process-v1/CLI_VERSION_PROCESS_EVIDENCE.md`
- 最新 CI 诊断 + POSIX CLI readiness QA App（Universal、ad-hoc、生产更新/性能夹具关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/ci-diagnostics-posix-readiness-v1/Dev Island.app`
- 最新本地准备度 QA App（Universal、ad-hoc、生产更新关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/local-readiness-v1/Dev Island.app`
- Settings 真实连接检查三态审计（改前/初始/需处理截图、发现、限制与 SHA-256）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/agent-readiness-settings-v1/AUDIT_REPORT.md`
- 最新 Settings 真实连接检查 QA App（Universal、ad-hoc、生产更新关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/agent-readiness-settings-v1/Dev Island.app`
- 对应 QA 架构、签名、Bundle、本地化、更新与性能夹具隔离证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/agent-readiness-settings-v1/QA_EVIDENCE.md`
- Settings readiness 晚到结果竞态、锁屏实机阻塞与完整回归证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/settings-readiness-late-result-v1/SETTINGS_READINESS_RELIABILITY_EVIDENCE.md`
- 最新 readiness 竞态修复 QA App（Universal、ad-hoc、生产更新关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/settings-readiness-late-result-v1/Dev Island.app`
- Runtime Privacy 证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/security/runtime-log-privacy-v1/RUNTIME_LOG_PRIVACY_EVIDENCE.md`
- Performance QA 构建隔离证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/performance-v6-build-isolation/PERFORMANCE_BUILD_ISOLATION_EVIDENCE.md`
- Performance QA 锁屏烟雾原始样本（禁止用于产品性能结论）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/performance-v6-locked-smoke/`
- Manus Realtime Lifecycle 证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/manus-realtime-lifecycle-v1/MANUS_REALTIME_LIFECYCLE_EVIDENCE.md`
- Manus Polling Lifecycle 证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/manus-polling-lifecycle-v1/MANUS_POLLING_LIFECYCLE_EVIDENCE.md`
- Manus Account Lifecycle 证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/manus-account-lifecycle-v1/MANUS_ACCOUNT_LIFECYCLE_EVIDENCE.md`
- Manus 真实验收工具安全与取消清理证据（不含真实账号调用，Release gate 仍关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/security/manus-live-acceptance-harness-v1/MANUS_LIVE_ACCEPTANCE_HARNESS_EVIDENCE.md`
- Manus 真实验收 transcript/源码/二进制证据边界、11 类攻击夹具、T7 包装器中断留证与
  642 项全量回归（仍不含真实账号成功，Release gate 继续关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/security/manus-live-acceptance-evidence-v1-20260829/MANUS_LIVE_ACCEPTANCE_EVIDENCE.md`
- Manus 真实验收编译输入闭包 v2：90 个本地输入、27 个锁定依赖 checkout、构建前后
  源码与 Swift/Xcode/macOS/SDK 工具链稳定性、空凭据 fail-closed 包装器实测、642 项
  T7 同源全量回归与完整安全门禁证据（仍不含真实账号成功，`ACCEPTED` 不存在）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/security/manus-live-build-input-closure-v1-20260829/MANUS_LIVE_BUILD_INPUT_CLOSURE_EVIDENCE.md`
- Cloudflared Quick Tunnel 独立 stderr drain、1 MiB 启动边界、可信 executable、
  有界 SIGTERM→SIGKILL 与 5 项进程边界回归（3 项真实子进程）证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/security/cloudflared-process-boundary-v1/CLOUDFLARED_PROCESS_BOUNDARY_EVIDENCE.md`
- 最新 Cloudflared 进程边界 QA App（6 个 Mach-O 全部 Universal、strict deep ad-hoc、
  34 notices、生产更新/Performance fixture 关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/builds/cloudflared-process-boundary-v1-20260827/Dev Island.app`
- Manus 出站凭据/ID/callback 构造、无重定向 ephemeral transport、响应 origin 与退避上限证据
  （不含真实账号调用，Release gate 仍关闭）：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/security/manus-outbound-trust-v1/MANUS_OUTBOUND_TRUST_EVIDENCE.md`
- 最新 production-equivalent QA App：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/builds/manus-outbound-trust-v1-20260827/Dev Island.app`
- 最新隔离 Performance QA App：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/dot-matrix-rendering-v1/Dev Island.app`

## v6.54 Welcome 连接配置事务收口

- [x] 初始/重复 Hook 扫描增加 latest-wins refresh ownership；晚到旧 snapshot 不再覆盖较新的
  安装结果。
- [x] Add、Update 与 Update all 共用 surface 级 mutation 独占；操作期间所有竞争按钮禁用，
  批量目标共同显示 working，并以单次最终 UI snapshot 收口状态变化。
- [x] Welcome 与 Settings 共用 `LocalAgentConfigurationExecutor`；View 内不再直接创建 detached
  配置任务或调用 installer，文件解析、原子写入、fsync 与 Codex trust 解析保持在后台。
- [x] 每次 mutation 后重新读取完整 Hook 健康状态；只有实际 Connected 或明确等待 vendor trust
  的 Configured 才成功，写入失败、缺项、Disconnected/Update Required 不再伪造 Connected。
- [x] 关闭/离开 Tour 会废弃在途 UI delivery，但不取消已经进入 managed-config 原子事务的写入；
  重新打开后从磁盘重扫。
- [x] 最终源码 693 tests / 0 failures、完整静态/安全/发布门禁通过；fresh Production App 的
  6 个 Mach-O 全为 arm64+x86_64，strict deep ad-hoc、依赖闭包与 8/8 hermetic 正常退出通过。
- [x] v6.54 App：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/onboarding-operation-ownership-v1-20260829/build-v6.54-final/Dev Island.app`
- [x] v6.54 只读证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/onboarding-operation-ownership-v1-20260829/WELCOME_CONNECTION_OPERATION_EVIDENCE.md`
- [ ] 解锁后用真实大配置和 Codex trust 场景复验按钮禁用、批量进度、失败重试、关闭后重开、
  VoiceOver 与 Animation Hitches；锁屏编译/回归不得替代此项。

## v6.55 商业 License 单调代际与提交时有效期

- [x] 签名 payload 增加严格正整数 `generation`；相同 License ID 的低代际回滚被拒绝，
  同代只允许完整 envelope 字节一致，高代际的签名 `issuedAt` 不得倒退。
- [x] replacement 比较通过不授予权益的 authenticated claims 读取旧文档；旧文档即使已经
  过期，也不会丢掉跨启动回滚下界。无法由当前 trust set 认证的旧文档保持 fail closed，
  只能进入显式删除/恢复边界。
- [x] Keychain load/authenticate/compare/save 与 delete 在一个进程内串行，12 轮并发旧/新
  代际导入最终始终保留新代际；未来若 helper/CLI 写同一 account，仍需跨进程所有权协议。
- [x] 激活请求不再复用 transport 开始前的时间；still-current operation 在 commit 前重新
  取时钟，公开 API 移除 caller-controlled `now`，在途过期响应不能写入 Keychain。
- [x] rollback/conflict 在激活边界归一化为 `licenseRejected` 并保留现有文档；商业政策继续
  `decisionState: required`，App 仍零生产 trust anchor、零 store/service 实例化、零收费 UI。
- [x] 最终源码 700 tests / 0 failures，39 项商业定向回归和完整静态/安全/发布门禁通过；
  fresh Production App 的 6 个 Mach-O 全为 arm64+x86_64，strict deep ad-hoc、依赖闭包与
  8/8 hermetic 服务隔离正常退出通过。
- [x] v6.55 App：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/commercial-license-monotonicity-v1-20260829/build-v6.55-final/Dev Island.app`
- [x] v6.55 只读证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/security/commercial-license-monotonicity-v1-20260829/COMMERCIAL_LICENSE_MONOTONICITY_EVIDENCE.md`
- [ ] 系统管理员级时钟回拨仍需 owner/legal 批准 offline grace、refresh、refund/revoke 与
  trusted-time 策略后处理；当前锁屏 smoke 的 CPU/RSS/readiness 不能作为丝滑度或性能结论。

## v6.56 Support 诊断导出操作所有权与主线程隔离

- [x] Settings 的 Save Panel 完成回调不再直接执行 descriptor open/write、`fsync`、close 与
  atomic rename；Hook 诊断读取和确认后的完整文件事务统一通过
  `SupportDiagnosticsIOExecutor` 进入后台 worker。
- [x] Copy/Save 共用 surface 级 operation ID，覆盖报告生成、Save Panel 取消/确认和后台写入
  完成；离开 Support 后废弃 UI delivery，但不破坏已经进入安全原子边界的写入。
- [x] Copy 与 Saved/失败提示改用独立 feedback ID；旧两秒/四秒延迟无法再清除较新的相同文案，
  离开页面也会废弃全部晚到反馈。
- [x] Performance/Security 静态门禁禁止 `SettingsView` 重新直接调用同步 exporter，并固定 executor、
  operation invalidation、feedback identity 与 bounded outcome 四项新回归。
- [x] Support 定向 11 tests / 0 failures；最终源码 704 tests / 0 failures。Localization、Performance、
  Legal/Data Flow、Workflow Shell、Repository Script、Release Foundation 与 Security 门禁全部通过。
- [x] fresh Production-shaped App 的 6 个 Mach-O 全为 arm64+x86_64，strict deep ad-hoc、依赖闭包、
  Production marker、零 Sparkle production key 通过；8/8 hermetic smoke 保持服务隔离并正常
  AppKit status 0 退出。
- [x] v6.56 App：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/settings-diagnostics-ownership-v1-20260829/build-v6.56-final/Dev Island.app`
- [x] v6.56 只读证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/support-diagnostics-operation-ownership-v1-20260829/SUPPORT_DIAGNOSTICS_OPERATION_EVIDENCE.md`
- [ ] 屏幕仍锁定；必须解锁后在慢本地卷/网络卷复验 Save Panel 取消、成功、失败、页面切换、
  动画响应与 VoiceOver。锁屏 smoke 的 CPU/RSS/readiness 数字不得作为丝滑度或性能结论。

## v6.57 Settings Agent 配置跨页面全局操作所有权

- [x] 复现真实产品竞态：**Disconnect All…** 原先只锁住当前 Agent pane；切到 General/Support
  再返回后，新建 row 会忘记仍在执行的跨文件移除，允许 Enable/Update/Disable 与其并发。
- [x] 将唯一 `LocalAgentConnectionsOperationState` 提升到 `SettingsView` 顶层并通过 Binding 下发；
  单 Agent mutation 与 Disconnect All 共用 operation slot，pane 重建不再恢复成错误的 idle。
- [x] operation completion 同时校验 ID 与 mutation kind；晚到/错类结果不能释放另一项写入。
  每次合法完成增加 generation，当前或重新创建的 Agent pane 统一重扫 rows、managed-Hook 汇总并
  废弃旧 readiness，而不是依赖已经离开的 row 收尾。
- [x] mutation 期间统一禁用全部 Agent Enable/Update/Disable、Codex trust **Check again**、
  readiness **Check this Mac** 与 Disconnect All；维护行使用低噪音双语进度与固定错误提示。
- [x] Disconnect All 不再由 View 直接创建 detached task，统一进入
  `LocalAgentConfigurationExecutor`；worker 只返回 no changes、断开数量或 failed，路径、原始错误
  与用户拥有的 Hook 内容不进入主线程呈现。
- [x] 4 项新 surface 状态机 + 6 项既有 installation 状态机定向回归通过；最终源码
  708 tests / 0 failures。Localization、Legal/Data Flow、Performance、Workflow Shell、Repository
  Script、Release Foundation 与 Security 门禁全部通过。
- [x] fresh Production App 的 6 个 Mach-O 全为 arm64+x86_64，strict deep ad-hoc、依赖闭包、
  Production marker 与零 Sparkle production key 通过；8 个 hermetic survival samples 后由 AppKit
  status 0 正常退出，产品服务保持隔离。
- [x] v6.57 App：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/settings-agent-mutation-ownership-v1-20260829/build-v6.57-final/Dev Island.app`
- [x] 主程序 SHA-256：
  `7223537d7ccfac861cd49b5a0fbc3ea7e172cb3cb90beeafb8febc5ec2bd04f2`
- [x] v6.57 只读证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/settings-agent-mutation-ownership-v1-20260829/SETTINGS_AGENT_MUTATION_OWNERSHIP_EVIDENCE.md`
- [ ] 屏幕仍锁定；解锁后必须真实复验“Disconnect All → 切页 → 返回”、大配置失败恢复、按钮节奏、
  VoiceOver 与 Animation Hitches。锁屏 smoke 的 1430.7 ms readiness、CPU/RSS 数字均不得作为
  丝滑度或性能结论。

## v6.58 Manus 签名重放窗口与终态单调性

- [x] 复现容量攻击：旧 1,024 项 FIFO 会在第 1,025 个仍处于五分钟签名窗口的事件到达时驱逐
  live ID，使捕获的旧 `task_stopped(ask)` 可以再次 delivery，并把终态重新推回 Waiting。
- [x] replay retention 改为每个事件的 authenticated `signedAt + 300s`；同 ID 的较新有效签名 retry
  会延长 expiry，恰在边界仍保留，过期后才清理。
- [x] 1,024 个 live ID 饱和时不再驱逐，新的 ID 返回 HTTP 503 让 provider 稍后重试；重复 ID
  继续幂等 200 且不进入 StateReconciler。
- [x] Manus Completed/Failed 成为单调终态；后来的 stopped/ask/finish 不再回退，Running/Waiting
  仍可正常前进，漏掉 created 的 stopped 仍可恢复新任务。
- [x] 36 项 Webhook/StateReconciler 定向测试通过，包含更新签名延长、饱和 fail-closed、终态不回退
  与 Waiting→Completed。
- [x] 最终源码 712 tests / 0 failures；20 轮版本探针、10 轮 hermetic listener、20 轮 tmux、
  5 轮 Codex trust、20 轮 sleep/wake 全部通过。Localization、Legal/Data Flow、Performance、
  Workflow Shell、Repository Script、Release Foundation、Security 与 `git diff --check` 全通过。
- [x] T7 fresh Production App 的 6 个 Mach-O 全为 arm64+x86_64，strict deep ad-hoc、依赖闭包、
  Production marker、双语法律资源回绑与零 Sparkle production key 通过；8 个 hermetic survival
  samples 后由 AppKit status 0 正常退出，产品服务保持隔离。
- [x] v6.58 App：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/manus-replay-window-v1-20260829/build-v6.58-final/Dev Island.app`
- [x] 主程序 SHA-256：
  `33cbcd1937195a7df1b35e044f9441f3f0584938ef420aa82f4d8e26779c18a9`
- [x] v6.58 只读证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/security/manus-replay-window-v1-20260829/MANUS_REPLAY_WINDOW_EVIDENCE.md`
- [x] 证据 SHA-256：
  `abb5f73a065f15ddd35323f3a17467a4967c4185aece1bb03193c09ab564e8eb`
- [ ] 当前屏幕仍锁定；本轮只能证明安全/可靠性代码与产物门禁，不能把启动 harness 数据当作
  丝滑度、动画、VoiceOver 或真实 Manus 商用验收。

## v6.59 Manus replay 真实 HTTP transport 回归

- [x] 审计 v6.58 证据强度：纯 `WebhookReplayWindow` 状态机已证明 expiry/饱和语义，静态门禁固定
  503，但尚未通过真实 Hummingbird route 证明 HTTP status 与 `onEvent` delivery 边界一致。
- [x] Production 公开构造继续固定 1,024 capacity；新增仅 IslandCore module-internal 的正整数
  capacity 测试构造，Security gate 禁止任何 IslandCore/CLI 生产 call site 覆盖该值。
- [x] 使用随机 loopback 端口、真实 RSA-2048 签名和官方 v2 JSON 实际 POST `/webhook`：首次 200
  且一次 delivery、duplicate 200 且零新增 delivery、两个 live ID 后第三个 ID 503 且不 delivery、
  随后最早 ID 仍为幂等 200，证明饱和没有驱逐。
- [x] transport 定向测试 1 passed / 0 failed；测试不访问 Manus、Cloudflare、用户 Key、配置或任务。
- [x] WebhookAuthenticationTests 15 passed / 0 failed，最终源码 713 tests / 0 failures；20 轮版本
  探针、10 轮 hermetic listener、20 轮 tmux、5 轮 Codex trust、20 轮 sleep/wake 全部通过。
  Localization、Legal/Data Flow、Performance、Workflow Shell、Repository Script、Release
  Foundation、Security 与 `git diff --check` 全通过。
- [x] T7 fresh Production App 的 6 个 Mach-O 全为 arm64+x86_64，strict deep ad-hoc、完整依赖
  闭包、Production marker、双语法律资源回绑与零 Sparkle production key 通过；固定 0 秒 warmup / 8
  samples 的 hermetic smoke 捕获 Production readiness，产品服务保持隔离并由 AppKit status 0 正常退出。
- [x] v6.59 App：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/manus-webhook-http-replay-v1-20260829/build-v6.59-final/Dev Island.app`
- [x] 主程序 SHA-256：
  `d67692dadb26c2408131f072c26a3d69f282a14ca827b3197840d5c7dee97922`
- [x] v6.59 只读证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/security/manus-webhook-http-replay-v1-20260829/MANUS_WEBHOOK_HTTP_REPLAY_EVIDENCE.md`
- [x] 证据 SHA-256：
  `288f8de692108bef16e535a04ab71d79405086ae0572c890c30dfef1e586f248`
- [ ] smoke 的 display probe 本次完整记录为 unlocked，但它仍是隔离进程 harness，不是交互式视觉
  审计；transport 回归也不等于真实 Manus provider/Cloudflare 公网投递，不能作为丝滑度、动画、
  VoiceOver 或商用验收。`ManusRealtimeTrust.liveV2AcceptanceComplete` 必须继续保持 `false`。

## v6.60 解锁视觉精修与空闲态品牌焦点

- [x] 以真实 v6.59 Production App 的 compact empty、expanded empty、Settings Agent 与 Welcome
  三步解锁截图为依据复核 Claude 画布；画布所列审批、问答、Plan Review、历史、PR CI、Sparkle、
  连接器“缺失”均已过时，没有重复重做已存在能力。
- [x] 空闲九宫格在保持固定 3×3 几何和状态语义的前提下提升中性色与 idle intensity；Running 仍沿
  周边旋转、Waiting/Completed/Failed 继续保持各自点亮模式，不退回普通圆点。
- [x] expanded empty 增加 18pt 九宫格品牌焦点，强化标题/说明层级，并将“连接 Agent”改成克制的
  描边操作入口；新增 `IslandQuietActionButtonStyle`，复用现有色彩、动效与 Reduce Motion 规则。
- [x] Welcome 外窗/舞台/主次按钮圆角从 12/8/6 调整为 16/10/8，建立外层 > 舞台 > 控件的连续
  圆角层级；新增 Welcome 圆角层级与 idle 九点最低可见度回归。
- [x] 22 项视觉/布局定向测试与最终源码 715 tests / 0 failures；Localization、Legal/Data Flow、
  Performance、Workflow Shell、Repository Script、Release Foundation 与 Security 门禁全部通过。
- [x] 内部 Desktop checkout 的 `.git/HEAD` 等文件被 macOS 标记为 dataless；未 reset、clean、覆盖或
  强读。T7 安全镜像同步 456 个 materialized 文件，并对 77 个 dataless 文件验证 baseline 存在、
  size 相同且 placeholder 不晚于 baseline。
- [x] T7 fresh Production App 的 6 个 Mach-O 全为 arm64+x86_64，strict deep ad-hoc、完整依赖闭包、
  Production marker、双语法律资源回绑与零 Performance fixture 通过；固定 0 秒 warmup / 8 samples
  的 hermetic smoke 保持产品服务隔离，并以 AppKit status 0 正常退出。
- [x] v6.60 App：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/visual-polish-v1-20260829/build-v6.60-final/Dev Island.app`
- [x] 主程序 SHA-256：
  `6c5fd657058167cc29927fa0b1936a1e13770b9085313270b6aac371a6e6ebde`
- [x] v6.60 审计与发布证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/unlocked-visual-audit-v1-20260829/UNLOCKED_VISUAL_AUDIT_EVIDENCE.md`
- [ ] 构建后 macOS 自动锁屏，尚不能正常退出旧 v6.59、打开 v6.60 并捕获六张 matching-state after
  截图。当前 8-sample harness 也记录 locked；其 readiness、CPU/RSS 不能作为丝滑度、视觉、能耗或
  完整交互结论。解锁后还需完成新旧同尺寸对照，并单独实测 VoiceOver、键盘焦点、Reduce Motion、
  Increase Contrast 与 Animation Hitches。

## v6.61 Codex 任务卡 Logo 与状态点阵解耦

- [x] 复现用户截图中的异常组合：任务卡使用 bottom-trailing `ZStack` 把九宫格状态点阵压在
  Agent Logo 右下角；Codex 的高密度轮廓、模板底色和状态点阵因此被读成一个畸形图标。
- [x] 改为固定的“状态点阵 → 7pt 间距 → Agent Logo”前导结构，Logo 不再使用任务卡小方形
  badge；保留既有 3×3 状态语义、卡片层级、标题/元数据和点击行为。
- [x] 新增 `TaskCardLeadingIdentityMetrics` 与几何回归，保证状态槽和 Logo 槽永不重叠；新增覆盖
  全部已注册 Agent 的视觉快照，防止只修 Codex 却破坏其他品牌标记。
- [x] 用户提供的 `codex.svg` 与仓库来源一致；未把 ChatGPT App 内的官方彩色资源直接复制进
  商业包，现有 Codex 商标/再分发审核门禁继续保持 required。
- [x] 静态多 Agent 快照与真实 Debug App 均通过；真实流程由 Debug Sandbox 创建 Codex 审批，
  经生产审批面拒绝后检查恢复为 Running 的普通任务卡，状态点阵和 Codex Logo 清晰分离。
- [x] 2 项定向测试 / 0 failures；最终源码 717 tests / 0 failures。20 轮版本探针、10 轮 hermetic
  listener、20 轮 tmux、5 轮 Codex Hook trust、20 轮 sleep/wake，以及 Localization、Legal/Data
  Flow、Performance、Workflow Shell、Repository Script、Release Foundation、Security 与
  `git diff --check` 全部通过。
- [x] Production 与 Debug App 均为 arm64+x86_64 Universal，并通过 strict deep 签名验证；Production
  固定 8-sample hermetic smoke 保持产品服务隔离、屏幕解锁并以 AppKit status 0 正常退出。
- [x] v6.61 Production App：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/task-card-logo-separation-v1-20260830/build-v6.61-final/Dev Island.app`
- [x] v6.61 Debug App：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/task-card-logo-separation-v1-20260830/build-v6.61-debug/Dev Island.app`
- [x] 主程序 SHA-256：
  `84568374f5b87a26121428489d3a95af510edc359732c5f92a6ae67e43d4ba7f`
- [x] v6.61 视觉与构建证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/task-card-logo-separation-v1-20260830/TASK_CARD_LOGO_SEPARATION_EVIDENCE.md`
- [ ] 以后若切换成官方多色 Codex 资源，必须先完成 OpenAI 品牌/商标与再分发许可确认；本轮只修复
  现有已审计资源的布局呈现，不以视觉偏好绕过商业发布门禁。

## v6.62 岛顶连接语义与真实 Codex 闭环证据

- [x] 真实 Codex 审批链路暴露出岛顶连接状态误导：`TaskStore.connectionStatus` 只描述 Manus，旧
  面板却把它标成全部 `Agent connections`，因此本地 Codex 正在工作时 VoiceOver 仍宣告“已断开”。
- [x] 新增纯 `AgentConnectionIndicatorPresentation`，组合本地 Hook listener、Manus API key 与 Manus
  transport 三类低基数状态；复用 Status Menu 的隐私安全文案，provider 原始 degraded reason 不进入
  Help 或辅助功能树。
- [x] 连接标记纳入统一 3×3 点阵语义：可用为绿色 plus、恢复中为蓝色周边旋转、需处理为琥珀色
  呼吸 ring、完全未启用才显示灰色 field；Reduce Motion 下持续动效停用。
- [x] 7 项新连接语义回归覆盖本地 listener、Manus-only、恢复、错误、未配置、中英文与私密 reason；
  16 项定向测试 / 0 failures，最终源码 724 tests / 0 failures。
- [x] 20 轮版本探针（240 子进程）、10 轮 hermetic listener、20 轮 tmux、5 轮 Codex Hook trust、
  20 轮 sleep/wake，以及 Localization、Legal/Data Flow、Performance、Workflow Shell、Repository
  Script、Release Foundation、Security 和 `git diff --check` 全部通过。
- [x] 通过真实 macOS 界面启动 fresh v6.62.1 Production App；辅助功能树读为“本地 Agent：已就绪，
  Manus：未连接”，旧的全局“Agent 已断开”消失。随后真实、ephemeral、read-only Codex 会话进入岛内
  并显示“1 个运行中”，返回 `DEV_ISLAND_CONNECTION_PRESENTATION_FINAL_OK` 后正常退出且未修改文件。
- [x] 另已完成真实 Codex `PermissionRequest` → 岛内“仅允许一次” → Running → Completed 闭环，CLI
  返回 `APPROVAL_ROUND_TRIP_COMPLETE`、status 0，并以 proof 文件及三张状态截图固化证据；持久 Codex
  Hook trust 未被 Dev Island 修改。
- [x] Production 与 Debug App 均为 6 个 Mach-O、arm64+x86_64 Universal、完整依赖闭包与 strict deep
  ad-hoc 签名；内部 v6.62.1 仍对应 shipping product version `0.3.0`，不冒充正式商业版本。
- [x] v6.62.1 Production App：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/connection-semantics-v1-20260830/build-v6.62.1-final/Dev Island.app`
- [x] v6.62.1 Debug App：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/connection-semantics-v1-20260830/build-v6.62.1-debug/Dev Island.app`
- [x] Production 主程序 SHA-256：
  `3800c4b823016b3a1515a7444b54d8260ecb8072e25f31ff49481cbcc57cdc16`
- [x] 连接语义体验与构建证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/experience/connection-semantics-v1-20260830/CONNECTION_SEMANTICS_EVIDENCE.md`
- [x] 真实 Codex 审批闭环证据：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/real-codex-approval-v1-20260830/REAL_CODEX_APPROVAL_EVIDENCE.md`
- [ ] Manus 真实账号验收、GitHub 仓库管理员控制、Developer ID/公证、生产 Sparkle、商业 owner 决策与
  品牌/商标 review 仍是商业发布外部门禁；本节不把 ad-hoc QA 构建称为可直接商用 Release。

## v6.63 Codex 真实审批机器可验证证据门禁

- [x] 将 v6.62 的真实 Codex `Allow once` 闭环从 Markdown 叙述升级为 append-never 私有证据包；原始
  Codex session JSONL 与 Dev Island SQLite 仅通过 no-follow、owner/mode/nlink/size 稳定 descriptor
  读取，均不复制进包。
- [x] session 提取器证明同一 session ID 的精确外部 proof prompt、唯一 `require_escalated` 请求、
  pending cell、同 cell 有界 wait、68 秒后 exit 0、精确 `APPROVAL_ROUND_TRIP_COMPLETE` 与
  task-complete 顺序；SQLite 同时证明该 session 的 `codex/completed` 记录与 UTC 边界一致。
- [x] 包内只保留固定 11 行低基数 transcript、一条脱敏 task record、精确 proof、三张人工复核状态
  JPEG、App/CLI/session/SQLite/artifact SHA-256、metadata、public receipt、`ACCEPTED` 和完整
  `SHA256SUMS`；App 版本、Bundle ID 与 strict deep 签名也在生成前复核。
- [x] T7 wrapper 强制在
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/codex-live-approval/`
  下创建随机 `0700` 目录，并要求维护者逐字确认
  `waiting,allow_once,running,completed`；该视觉确认保持显式人工断言，不冒充像素/VoiceOver 自动证明。
- [x] 新增独立 packager/validator 与 Security gate：真实合成正向包以及 receipt/package/session 的
  symlink、hard-link、unsafe mode、错误 final、proof、transcript、task、JPEG、checksum、extra file、
  private-directory 和版本漂移攻击夹具全部通过；tag Release 通过既有 Security gate 强制执行。
- [x] 脱敏可签入 receipt：`docs/CODEX_LIVE_APPROVAL_RECEIPT.txt`；它绑定 shipping `0.3.0`、baseline
  commit、dirty 状态、session/app/CLI/database/transcript/task/proof/三图哈希和 accepted 结果，不含
  原始消息、reasoning、无关数据库行、本机路径或凭据。
- [x] packager、validator 与 T7 wrapper 自身也进入 metadata/receipt SHA-256；正式私有证据包：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/codex-live-approval/run-20260830T055749Z-99ZRth`
- [x] Repository Script Syntax、Legal/Data Flow 与完整 Security 全部通过；最终权威图执行
  724 tests / 0 failures，并完成 20 轮版本探针、10 轮 hermetic listener、20 轮 tmux、5 轮
  Codex Hook trust 与 20 轮 sleep/wake 稳定性。
- [x] 首次权威图在系统负载下暴露
  `testImmediateExitFailsWithoutWaitingForTheFullTimeout` 误用产品 3 秒 timeout：测试子进程未及
  获得首次调度即被读为 `.timedOut`。该 fixture 现统一使用独立 5 秒调度预算，产品默认
  3 秒与 50 ms timeout 回归均未改；修复后定向测试、5 轮 Codex trust 及完整权威图通过。
- [x] fresh Universal Production App 的 6 个 Mach-O 全部为 `arm64+x86_64`，strict deep
  ad-hoc 签名、依赖闭包、法律资源回绑与品牌 inventory 通过；解锁 hermetic Production
  smoke 在产品服务隔离、App 私有快照下采样 8 次，4,027.9 ms ready，并以 AppKit status 0
  正常终止。
- [x] v6.63 Production App：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/codex-live-evidence-gate-v1-20260830/build-v6.63-final/Dev Island.app`
- [x] Production 主程序 SHA-256：
  `435f46857e2e29efa3c494ddc5853ddb7bcba2c13c7718f256c93a3935148f37`
- [x] 最终机器证据报告：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/codex-live-approval-machine-gate-v1-20260830/CODEX_LIVE_APPROVAL_MACHINE_GATE_EVIDENCE.md`
- [ ] 该包只证明一个真实 Codex Allow Once session；Deny、timeout、native fallback、其他 Agent、
  Manus 真实账号、VoiceOver/Reduce Motion 系统验收，以及 clean tag/Developer ID/公证/生产 Sparkle
  仍是独立门禁。receipt 如实保留 `worktree_state=dirty`，不冒充 clean Release 可重现证据。

## v6.64 系统辅助功能证据与环境恢复门禁

- [x] 使用真实 macOS VoiceOver 进程复核 Codex 审批决策面：窗口摘要先读最高注意力与总会话数，
  再读连接状态、连接/设置动作、最早待批请求、请求正文、拒绝与仅允许一次；任务卡保持在决策面后。
- [x] 在真实 key window 分别执行 `⌘D` 与 `⌘↩`，两次都从 Waiting 返回 Working；本轮证据只记录
  操作员确认与前后 AX/截图，不把它改写成 spoken-output 的机器证明。
- [x] 从系统设置真实开启 Reduce Motion；同一 Working 面板相隔 250 ms 的两帧 SHA-256 均为
  `c8cb85ae0736e7d9a27bbe977f52de10aa6eeaec43d25fd7d6f1d3199ee43694`，且逐字节相同。
- [x] 修复验收流程本身的安全缺口：新 wrapper **只读**检查偏好与进程，绝不执行 `defaults write`、
  `killall`、`pkill`、`launchctl` 或 AppleScript；Reduce Motion、Increase Contrast、Reduce
  Transparency 未全部恢复 off，VoiceOver/Debug 未退出，或不是恰好一个指定 Production 进程时，
  均不得生成 `ACCEPTED`。
- [x] 原始 AX/截图以 no-follow、owner/mode/nlink/size 稳定描述符读取；私有 T7 包固定 18 个文件、
  `0700` 目录、只读产物、完整 `SHA256SUMS`，并把实际 JPEG 字节规范化为 `.jpeg`，不继续沿用原始
  捕获器误写的 `.png` 扩展名。
- [x] checked-in receipt 只保留版本、commit、dirty 状态、有限时间、范围声明与哈希；真实任务正文、
  AX 内容、截图、本机路径和进程命令不进入仓库。Security/Release gate 固定 receipt/package 的
  symlink、hard-link、unsafe mode、字段伪造、CRLF、缺 LF、extra file、帧篡改、AX 缺动作及未恢复设置。
- [x] 当前系统恢复状态已机器复核：Reduce Motion / Increase Contrast / Reduce Transparency 均为 off，
  VoiceOver 与 v6.62.1 Debug 进程均为 0，且只运行 v6.63 Production。私有 accepted 包：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/system-accessibility/run-20260830T065649Z-7gNNo7`
- [x] 脱敏 receipt：`docs/SYSTEM_ACCESSIBILITY_RECEIPT.txt`；独立 package validator 与 15 类正/负向
  夹具通过。前两次失败包保留且没有 `ACCEPTED`，分别真实暴露 JPEG 扩展名误标与 Unicode AX 顺序
  解析的 byte/character offset 错误，没有把失败改写成成功。
- [x] 最终权威图执行 724 tests / 0 failures，并完成 20 轮版本探针、10 轮 hermetic listener、
  20 轮 tmux、5 轮 Codex Hook trust 与 20 轮 sleep/wake；49 Bash + 21 Ruby + 5 Swift parse-only、
  Legal/Data Flow 与完整 Security 全部通过。
- [x] v6.64 不改变 App executable source，因此没有伪造新版本产物；重新验证 v6.63 Production
  主程序 SHA-256 `435f46857e2e29efa3c494ddc5853ddb7bcba2c13c7718f256c93a3935148f37`，
  strict deep ad-hoc 签名、6 个 `arm64+x86_64` Mach-O 与完整依赖闭包均通过。最终报告：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/system-accessibility-gate-v1-20260830/SYSTEM_ACCESSIBILITY_GATE_EVIDENCE.md`
- [ ] 本轮范围仍不包含逐项 VoiceOver spoken-output/focus 记录、AskUserQuestion、Plan Review、
  Save Panel、Increase Contrast App 内对照、通知/声音/Focus Mode 或跨 macOS 版本；以后只能在隔离
  macOS 测试账户/VM 中切换系统辅助设置，日常用户会话只允许运行只读恢复门禁。

## v6.65 Codex Deny / timeout 真实分类与证据门禁

- [x] 新增独立 `package/validate/run-codex-live-decision-evidence` 与 Security 攻击门禁；既有
  `Allow once` receipt/包格式保持不变，approval packager 仅增加可安全复用的 CLI main guard。
- [x] session 结果严格分为 `explicit_island_deny`、`neutral_timeout_fallback`、
  `sandbox_rejection` 与 `interrupted_attempt`；只有第一类且 1–89 秒内明确返回 Deny 才可能生成
  `ACCEPTED`，后三类只能被识别和拒绝。
- [x] 分类器同时支持 Codex 真实出现的 strict JSON 与受限 JavaScript object 参数记录；后者不执行
  源码，只接受六个审核字段及 JSON string/规范整数。executable expression、重复字段、未知值类型
  由负向夹具拒绝并证明无副作用。
- [x] proof 必须位于 workspace 外、绝对且规范，父目录 device/inode 稳定，并在分类、打包及写入
  accepted marker 前三次保持不存在；包内只保存路径 SHA-256 与 `result=absent`，不复制本机路径。
- [x] 合成 package/receipt 正例与四分类、已有 proof、session symlink、artifact symlink/hardlink、
  unsafe mode、extra file、classification/absence/JPEG/checksum/receipt 篡改攻击均通过；raw JSONL 与
  SQLite 永不复制进包。
- [x] 三条真实失败样本已由新分类器复核：非交互 session
  `01a0517c-ff58-7a73-9876-2c5726861da8` 为 `sandbox_rejection`；被提前停止的非交互 session
  `01a0517d-c574-74d1-83d1-0c51c33bb0c5` 与 TUI session
  `01a0517e-5680-7643-b877-7573789c74d0` 均为 `interrupted_attempt`。三条 proof 全部不存在，但这
  只证明失败安全，不能冒充岛内 Deny 或 neutral timeout 成功证据。
- [x] 分类/打包脚本已进入总 Security gate；仓库脚本闭包同步为 49 Bash + 21 Ruby + 5 Swift，
  Interface Contract、Data Flow、GitHub Controls 与 Legal verifier 的当前数字保持一致。
- [x] Mac 解锁后新建真实 TUI session；在 90 秒前显示 Dev Island Waiting 决策面并从岛内点击
  **拒绝**，40 秒后 Codex 正常返回 `DENIAL_ROUND_TRIP_COMPLETE` 与 task-complete。SQLite 同
  session 行为 `codex/completed`，proof 在分类、打包和 accepted 前后始终不存在。
- [x] 私有 append-never 包已经 accepted，脱敏 `docs/CODEX_LIVE_DECISION_RECEIPT.txt` 已签入；
  receipt 如实绑定 shipping `0.3.0`、baseline、dirty worktree、真实 App/CLI/session/SQLite、两张
  人工复核图和 proof absence，不把本轮 QA 证据冒充 clean 商业 Release。

## v6.66 macOS 日常用户环境隔离门禁

- [x] 将 v6.64 只覆盖 system-accessibility wrapper 的只读检查扩展到整个仓库可执行源码面；
  `.sh`、`.rb`、`.swift`、workflow YAML 在 Security/Release gate 中以本地、有界 UTF-8 文本
  静态扫描，不执行源码，也不读取已安装 App 或用户内容。
- [x] 明确拒绝 `defaults` 写入/删除、`killall`/`pkill`、`launchctl` 状态修改、AppleScript、
  `CFPreferencesSetAppValue` 与直接 universal-access preference 文件访问；避免 QA、CI、Release
  或 App 源码再次把系统级验收副作用带进维护者的日常登录会话。
- [x] 五类独立攻击夹具覆盖偏好写入、进程级终止、launch-service mutation、AppleScript 与全局
  CFPreferences API；当前真实源码闭包及全部攻击夹具通过。该门禁是仓库防护，不冒充对外部
  Computer Use 或人工操作的运行时沙箱。
- [x] EXPERIENCE_QA、Data Flow 与中英文 Privacy 已同步边界；系统 Reduce Motion、Increase
  Contrast、Reduce Transparency、grayscale 均保持 off，VoiceOver 未运行，本轮没有修改系统设置。
- [x] 当前源码状态下 Repository Script Syntax、Legal/Data Flow、完整 Security、`git diff --check`
  全部通过；权威图执行 724 tests / 0 failures，并完成 20 轮版本探针、10 轮 hermetic listener、
  20 轮 tmux、5 轮 Codex Hook trust 与 20 轮 sleep/wake。
- [x] 此后在已解锁日常会话完成真实 Codex 岛内 Deny；全过程没有切换系统辅助功能、修改 Hook
  trust 或持久系统设置。以后需要切换系统辅助功能的验收仍只能在隔离 macOS 测试账户或 VM 中进行。

## v6.67 Codex 岛内真实拒绝闭环与当前客户端证据兼容

- [x] 真实 session `01a051ae-f825-7f03-9ec8-e9308d266362` 来自 Codex Desktop
  `source=cli`；唯一外部写请求进入 pending cell，Dev Island 决策面真实显示 Waiting，岛内点击
  **拒绝** 后回到 Running，Codex 最终只输出 `DENIAL_ROUND_TRIP_COMPLETE` 并正常 task-complete。
- [x] 当前 Codex `0.149.0-alpha.4.3` 会省略 `workdir`，由工具语义继承 session workspace；分类器只
  接受该省略形式或显式 realpath 等于 workspace 的非空绝对路径。空路径、其他目录继续失败关闭。
- [x] 当前客户端的审核后参数固定为精确 T7 justification、`require_escalated`、10,000 ms yield 与
  2,000 output token；历史已审核夹具的 1,000 token/旧 justification 仍兼容，其他值全部拒绝。
- [x] 当前拒绝结果是数组型 tool output：失败正文必须逐字绑定同一 reviewed command、
  `/bin/zsh -lc` 与 `CreateProcess { message: "Rejected(\"Denied in Dev Island.\")" }`；不再依赖宽泛
  denied/rejected 关键词。篡改回执中的 command 即使保留同一拒绝文案也不能通过。
- [x] 真实 decision wait 为 40 秒；SQLite 同 session 行状态为 completed，proof 三阶段不存在。
  两张人工复核图固定 `waiting,deny,running`，原始 JSONL、SQLite、prompt、command、path 与 reasoning
  均未复制入证据包。
- [x] 私有只读 accepted 包：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/codex-live-decision/run-20260830T081420Z-X5ords`
- [x] 脱敏公开回执：`docs/CODEX_LIVE_DECISION_RECEIPT.txt`。package validator、receipt validator 与
  完整 `SHA256SUMS` 已独立复验；focused 正/负向分类、package 与攻击夹具全部通过。
- [x] 聚合 Security/tag Release 路径现强制要求并验证上述真实 receipt；缺失、symlink、hard-link、
  unsafe mode、timeout/rejected 伪装、版本/哈希漂移、CRLF 与缺末尾 LF 均由独立夹具失败关闭，
  不再只验证合成 decision package。
- [x] 当前源码已重新完成 49 Bash + 21 Ruby + 5 Swift Repository Script Syntax、Legal/Data Flow、
  完整 Security 与 724 tests / 0 failures；同一权威测试图随后完成 20 轮版本探针、10 轮无副作用
  listener、20 轮 tmux、5 轮 Codex Hook trust 与 20 轮 sleep/wake。全过程没有切换系统辅助功能或
  改变全局 macOS 外观。
- [x] 最终只读机器证据报告：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/reliability/codex-live-deny-machine-gate-v1-20260830/CODEX_LIVE_DENY_MACHINE_GATE_EVIDENCE.md`
- [x] 报告 SHA-256：
  `6b9f44530907129fa860ad8e1722d6ed9f521963b5e5cdcbeafbd2dfda1f5e13`

## v6.68 商业发布缺口实证审计与真实 Deny receipt 强制门

- [x] 重新运行只读 `local-live-readiness`：listener 为 listening，Claude/Codex CLI 版本均 verified；
  Claude Hook 为 update-required，Codex Hook 为 configured 且 activation review-required，当前
  `ready-agents=0/2`。未自动更新 Hook 或改变 Codex trust。
- [x] 商业政策 descriptor/语义检查安全通过，但 `state=required, missing=36`；
  `--require-approved` 按预期失败。9 个 Agent 资源的来源、license、notice 与哈希通过，9 个商标审批
  全部仍是 Release blocker，没有把待审状态改成批准。
- [x] 远端 GitHub GET-only 审计仍有 B01/B04/B09/A02/A06/S04 六项 finding；没有管理员授权时未修改
  branch protection、Actions 或 Dependabot。Manus accepted 真实包为 0，
  `liveV2AcceptanceComplete=false` 继续保持 Release-disabled。
- [x] 本机存在有效 Developer ID Application identity，但本轮未签名/公证；GitHub 最新 `v0.3.0`
  被仓库 verifier 正确拒绝为 legacy/incomplete，缺 SBOM、`SHA256SUMS`、`appcast.xml` 与 Homebrew
  cask。当前 v6.63 QA App 刻意无 `SUPublicEDKey/SUFeedURL`，不能冒充生产更新证据。
- [x] 审计中发现真实 Deny receipt 尚未进入聚合 gate；现已修复为 CI/tag Security 必须直接验证
  `docs/CODEX_LIVE_DECISION_RECEIPT.txt`，并新增缺失与九类链接/权限/语义/编码篡改拒绝夹具。
  修复后 Repository Script Syntax、Legal/Data Flow、focused decision gate、完整 Security 与
  `git diff --check` 全部重跑通过；Swift 产品源码未在此后变化，权威 724 tests 与
  20/10/20/5/20 结果继续绑定同一当前产品图。
- [x] 最终只读商业缺口审计：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/commercial-release-gap-audit-v1-20260830/COMMERCIAL_RELEASE_GAP_AUDIT.md`
- [x] 审计 SHA-256：
  `c829869df95a26732a3e6dd7209bcc7260a64c1f666c38eee9b0fc153bcf7da7`
- [ ] 下一步需要用户/owner/legal/管理员提供明确外部授权：先更新 Claude Hook 与 Codex `/hooks`
  trust；再用真实 Manus 账号完成 v2 accepted 包；批准 36 项商业政策和 9 项商标记录；修复 6 项远端
  GitHub 控制；最后创建 clean tag，完成 Developer ID/公证、生产 Sparkle 与旧版到新版更新验收。

## v6.69 Sparkle Ed25519 密码学发布闭环

- [x] 复现并修复发布链严重缺口：旧 `verify-release-assets.sh` 只要求 archive/feed 签名 Base64
  解码为 64 bytes，旧正向夹具使用 64 个零字节仍能通过；credential preflight 也只验证 32-byte
  公钥形态，没有证明配置的公私钥属于同一 keypair。
- [x] 新增 `verify-sparkle-ed25519-signatures.swift`，使用
  `CryptoKit.Curve25519.Signing.PublicKey.isValidSignature`；输入通过 owner/single-link/safe-mode
  `O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC` descriptor、1 GiB 上限、exact read 与前后 metadata 复验，
  不把长度或 Base64 形态冒充密码学成功。
- [x] tag 凭证门在导入证书和构建产物前，先让 `SPARKLE_PRIVATE_ED_KEY` 经 pinned
  `sign_update --ed-key-file -` stdin-only 通道签固定 `VERSION`，再由配置公钥真验签；私钥转入
  非导出 shell buffer 后清除 inherited env，两个子进程均由 `env -i` 启动，错配 keypair 失败关闭。
- [x] 完整 8 资产门从 versioned ZIP 的精确
  `Dev Island.app/Contents/Info.plist` 有界提取交付 App 自己的 `SUPublicEDKey`，对 versioned ZIP
  全部字节和 Sparkle terminal block 声明的精确 feed prefix 分别验签；不再信任 workflow 中另一份
  公钥声明。
- [x] RFC 8032 正向 fixture 通过；malformed signature、unrelated 64-byte archive/feed signature、
  signed prefix 同长度篡改、App 内合法但错配公钥与 credential 公私钥错配全部失败，原有资产/
  checksum/Cask/Appcast/SBOM/品牌/source-revision 攻击回归继续通过。
- [x] 仓库脚本闭包同步为 49 Bash + 21 Ruby + 6 Swift；Interface Contract、Automatic Updates、
  Data Flow、GitHub Controls、Legal verifier、Release Foundation 与 Security 静态断言全部更新。
- [x] 当前源码重新完成 724 tests / 0 failures，以及 20 轮版本探针（240 子进程）、10 轮
  hermetic listener、20 轮 tmux、5 轮 Codex trust、20 轮 sleep/wake；Repository Script Syntax、
  Legal/Data Flow、Release Foundation、完整 Security 与 `git diff --check` 全部 PASS。
- [x] 只读证据报告：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/sparkle-ed25519-cryptographic-gate-v1-20260830/SPARKLE_ED25519_CRYPTOGRAPHIC_GATE_EVIDENCE.md`
- [x] 报告 SHA-256：
  `64cced9f9995dfaf61f651c7e870b5a66807994ff66e8a34c0c565718034ada5`
- [x] 前一轮遗留的 QA Debug Sandbox 已精确关闭；最终 Increase Contrast / Reduce Transparency /
  Reduce Motion / grayscale 均为 off，VoiceOver 与 QA Debug 进程均为 0，本轮未写 macOS 外观设置。
- [ ] 该门只闭合密码学一致性，不冒充 clean tag、Developer ID/公证、完整 GitHub Release 或
  old-to-new updater 安装证据；Manus 真实账号、Hook trust、36 项商业政策、9 项商标审批和 6 项
  远端 GitHub 控制仍保持原 blocker。

## v6.70 Sparkle disposable old-to-new 真实更新闭环

- [x] 不调用会在线解析开发依赖的 Sparkle Xcode 工程；直接从 `Package.resolved` 锁定的
  `2.9.6 @ ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a` checkout 取官方
  `sparkle-cli` 三个 Objective-C 源，并链接已解析、签名有效的 Universal XCFramework，离线构建
  当前 runner 架构 CLI App。
- [x] 使用 RFC 8032 非生产 Ed25519 fixture key、随机 `127.0.0.1:0` server 与一次性 v1/v2
  `Dev Island.app`，真实完成 signed feed 下载、signed ZIP 下载、pre-extraction Ed25519 验签、
  解压、App code-sign validity、原 bundle 替换，并复验 version `1 → 2`、新 executable marker、
  strict code-sign 与 Sparkle `Installation Finished`。
- [x] 四条独立负向链均保持旧 version/executable hash/signature 不变：wrong feed key 在 archive
  下载前失败、wrong archive key 在解压前失败、old App embedded key 错配在 archive 下载前失败、
  正确签名 archive 内的 App executable 在 codesign 后被改写则在安装前失败；pinned
  `sign_update --verify` 交叉证明每份 feed/archive 的预期 key 归属。
- [x] 取消“先写真实账号再清理”的方案：固定哈希覆盖层把 pinned Sparkle 源码复制到 macOS
  私有临时根，移除无关远程 package 引用，把 cache 与 launch-job 环境硬路由至一次性 runtime
  HOME；Xcode 构建使用另一私有 HOME，两个环境均设置 `__CFPREFERENCES_AVOID_DAEMON=1`，完全
  不调用 `defaults write/delete`。保留 Sparkle 原生 ad-hoc helper identity；失败清理只对当前随机
  临时根下精确匹配的 helper PID 做 TERM→KILL。loopback server 仍限 64 MiB/16 KiB headers/
  allowlisted 文件，CLI 由 90 秒 bounded process group 执行。
- [x] 按 Sparkle 2.9.6 源码与实际行为确认：旧 Ed25519 key 已认证 archive 时，Apple code-sign
  identity rotation 是明确支持的安全策略，不能把“不同 signer 应失败”写成伪门禁；本轮测试
  code-sign validity/corruption，生产 signer/Team 连续性仍由 Release 证书与最终真实更新验收负责。
- [x] 新 gate 已加入 PR CI 独立 step、低基数 diagnostics 与 tag Release credential 前置门；Security、
  Release Foundation、Automatic Updates、Data Flow、Legal、GitHub Controls 和 Interface Contract
  同步更新，仓库脚本闭包为 50 Bash + 23 Ruby + 6 Swift。
- [ ] 该 disposable gate 不冒充 clean tag、Developer ID/公证/Gatekeeper 或真实已安装旧 Release →
  新 Release；仍需生产 Sparkle key custody、完整八资产 GitHub Release、真实旧版升级证据，以及
  Manus 账号、Hook trust、商业政策、商标与远端 GitHub 控制闭合。

## v6.71 普通测试图 Keychain 零副作用边界

- [x] 独立 evaluator 在 T7 隔离 `HOME/CFFIXED_USER_HOME` 执行精确 `swift test` 时，真实捕获
  `CommercialLicenseActivationTests.testLatestConcurrentActivationIsTheOnlyDocumentSaved`
  从 `SecItemAdd` 进入登录 Keychain `AuthorizationCopyRights` 并等待；安全停止该精确 evaluator，
  保留失败 run、evaluator 与 process sample，没有清理或修改真实 Keychain/登录状态。
- [x] 明确修正旧假设：随机 service/account 只能避免 namespace 冲突，不能让 Keychain 测试
  hermetic。`CommercialLicenseDocumentStore` 新增 module-internal storage backend，shipping
  initializer 仍只装配 `CommercialLicenseKeychainBackend`；激活与文档存储测试统一注入线程安全的
  进程内存 backend，生产 verify-before-save、generation/issuedAt 回滚边界与错误语义不变。
- [x] `KeychainStore` 同样拆分 `KeychainStoreClient`、注入式 backend 与 shipping
  `KeychainStoreSecurityBackend`；生产 service/account 不变，并显式固定
  `WhenUnlockedThisDeviceOnly` 与 `synchronizable = false`。普通测试改用内存 backend，另以纯
  query/attribute 断言固定 shipping 策略，不调用真实 `SecItem*`。
- [x] Security gate 拒绝商业 License 普通测试直接使用 `SecItem*` 或旧 service/account test
  initializer，并拒绝整个 `IslandCoreTests` / `IslandAppLibTests` Swift 图调用 Keychain
  `SecItemAdd/Update/CopyMatching/Delete`；API-key 测试也不得直连生产静态 store。
- [x] Interface Contract、CI Diagnostics、Data Flow Inventory 与中英文 Privacy 已同步：普通
  `swift test` 只使用进程内存存储；真实 Keychain 验收只能是独立、显式、可处置 macOS 测试
  账户或 VM 门禁，不能在维护者日常登录会话中运行。
- [x] 修复后的完整权威测试、安全/法律/诊断门禁、当前源码 Universal Production App、严格签名、
  依赖闭包与 8-sample hermetic launch smoke 已在全新 evidence root 中通过；权威图为
  732 tests / 0 failures，20/10/20/5/20 稳定性全部通过，Production 主程序 SHA-256 为
  `c6352f27e1b62b1ba5b2e9fc33279883819f3093e30b21ab58fe1d2abec92b79`。

## v6.72 岛内决策面一体化与响应回执

- [x] 以当前 Debug Universal App 真实捕获 Codex approval → Allow once → Running 流程；旧决策面
  的内层圆角卡、整条琥珀竖线和常驻灰底次级按钮是最主要的模板感来源。
- [x] 决策内容改为直接落在岛体上，仅用低对比底部分隔保持多会话层级；命令/计划仍保留唯一必要的
  内嵌内容面。Deny/Reject 等次级动作静止时退为纯文字，hover 才出现轻底；主动作继续保持清晰、
  足够大的安全点击目标和既有键盘契约。
- [x] Allow/Deny、Plan approve/reject 与回答提交成功后增加 0.9 秒非阻塞响应回执；真实 Hook response
  先同步送达 Agent，UI 才呈现“已允许一次 / 已拒绝请求 / 回答已送达”和“Agent 正在继续处理”，
  然后以 opacity + smooth layout 自然回到 Running 行。第二个同会话请求仍优先显示，不会被回执遮挡。
- [x] 回执文案完成 English / 简体中文与 VoiceOver 聚合标签；不包含原始 session ID。2 项新纯展示测试
  固定 permission、plan、question 的不同语义与双语结果。
- [x] Debug App 实际点击确认 AX 从审批按钮切换为“已允许一次，Codex 正在继续处理”，随后回到
  Running；同尺寸 before/after、回执与最终 Running 截图保存在：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/current-interaction-audit-v1-20260830/screenshots/`
- [x] 当前源码 **734 tests / 0 failures**；Localization、Performance analysis、18 项 build-flavor
  isolation、完整 Security 与 `git diff --check` 全部通过。
- [x] fresh Production App 的 6 个 Mach-O 全为 arm64+x86_64，依赖闭包、Production marker、
  strict deep ad-hoc 签名通过；隔离 HOME/CFFIXED_USER_HOME 的 8-sample hermetic smoke 为
  `normal_termination=true / app_exit_status=0 / product state absent`，主程序 SHA-256：
  `f48febd028115602e4b3747b8b010d6c1f69a370901ac1dacc45d0771536d6c3`。
- [x] 以同一份当前源码 Debug Universal App 完成决策节奏补验：Codex Deny 分别由 `⌘D` 与直接点击
  触发，均保持展开并呈现“已拒绝请求 / Codex 正在继续处理”，随后切换为 Running；
  AskUserQuestion 覆盖单选、第二题多选、Back/Next 双向草稿保留、Submit 回执与 Running；Plan Review
  覆盖 Markdown 标题/列表/代码内容、Approve 与 Reject 两条独立回执。截图和审计报告保存在：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/decision-cadence-v1-20260830/`。
- [x] 明确排除该 evidence root 的 `screenshots/01-deny-receipt.png`：它是在测试窗口菜单被 `Esc`
  收起后，再由紧凑栏进入指针自动收起分支所得，只能证明 collapsed Running，不能作为 Deny 回执证据；
  有效 Deny 证据从 `02-deny-keyboard-receipt.jpeg` 开始。
- [ ] 下一轮补齐 Deny、AskUserQuestion 与 Plan Review 的真实视频/Animation Hitches，并在隔离 macOS
  测试账户或 VM 完成完整 VoiceOver spoken-output；当前合成请求、截图与 AX 树不冒充真实 Claude CLI
  round trip、完整朗读合规或帧级性能证据。

## v6.73 Codex Hook 信任旁路实证与激活指引

- [x] 收束上一条真实 timeout 尝试：session
  `01a05346-e435-7f70-821a-439356fe4485` 在约 90 秒后真实回到 Codex 原生审批面，但操作员直接按
  `Esc` 中断了整轮 turn；机器分类固定为 `interrupted_attempt`，`deny-v4-proof.txt` 不存在。该样本
  只证明 native UI 接管与失败安全，不冒充 `neutral_timeout_fallback` 的正常拒绝回执。
- [x] 以当前 Codex `0.151.0-alpha.7.2` 新建 session
  `01a056d6-b417-7612-aa65-7725d14dd9cb`；CLI 明确提示 `[features].codex_hooks` 已废弃，并在 Hook
  review 选择 **Continue without trusting (hooks won't run)** 后继续。该选择没有写入或信任 Dev Island
  Hook，Production App 也未收到审批请求。
- [x] 同一受控请求随后直接执行并创建 `deny-v5-proof.txt`，内容 SHA-256 为
  `19371eb676d748e5afeeded5ff411a552bd0f58edf8f690a4a0583cc901f1135`。该 proof 故意保留为失败证据；
  packager 因 proof 已存在而失败关闭，不能把 `DENIAL_UNEXPECTED_SUCCESS` 包装成岛内 Deny 或 timeout
  通过。
- [x] 启动新版 Codex TUI 后，vendor-owned `~/.codex/config.toml` 从既有基线哈希发生变化，当前为
  `7f66e684a9d552294270f9d5d46390b0dee2adc3b21ebb63aa183cd3e0807ac8`；Dev Island 源码和本轮脚本没有
  写该文件，也未尝试回滚未知的用户/CLI 配置。真实 Hook/CLI 验收以后必须把 vendor 配置漂移纳入前后
  证据，而不能继续假设启动 TUI 完全只读。
- [x] Settings 与 Live connection check 的中英文指引已改为：在 Codex `/hooks` 中审阅并仅信任
  Dev Island 条目，并明确说明 **Continue without trusting** 会让审批留在 Codex、不会进入灵动岛；
  避免把“configured”误读成双向审批已可用。
- [x] 新增简体中文旁路风险回归，`LocalLiveReadinessPresentationTests` 当前 12 tests / 0 failures。
- [x] 完整当前图为 735 tests / 0 failures；Localization、Legal/Data Flow、CI diagnostics、Manus
  acceptance fixtures、Codex approval/decision evidence、system-accessibility isolation、GitHub controls、
  Release Foundation、Performance、Sound、Log Privacy、完整 Security 与 `git diff --check` 全部通过。
- [x] fresh Production App 为 `arm64+x86_64`，6 个 Mach-O 依赖闭包与 strict deep ad-hoc 签名通过；
  主程序 SHA-256 为 `80ae7550675ea5759a6e5cf315d35d01083741ffdd4d9bf4de17386127e435f1`。
  8-sample hermetic smoke 在 1,411.4 ms ready，正常 status 0 退出且 RSS 只增长 16 KiB。
- [x] 审计报告：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/codex-hook-activation-guidance-v1-20260831/CODEX_HOOK_ACTIVATION_GUIDANCE_AUDIT.md`
  （SHA-256 `03f7d05c1fc61ce743d42f7f35478ef2e5357ee78123d8d66f610cb61b742872`）。
- [ ] 真正的 `neutral_timeout_fallback` 正常拒绝仍需用户在 Codex 中完成当前 Dev Island Hook 信任后
  重跑；在此之前保持 readiness 未就绪，不自动修改 trust、`config.toml` 或 Hook feature flag。

## v6.74 决策响应卡顿定位、修复与分段 Instruments 门禁

- [x] 新增 `summarize-animation-hitches.rb`：严格解析 Animation Hitches、SwiftUI update 与
  Potential Hangs 导出，分开统计 App-attributed frame、render/GPU-only frame、App update 与 hang；
  startup/resolved/steady/recording-tail 独立输出，trace duration 外记录只计数不纳入结论。
- [x] Performance action marker 同时记录 monotonic `uptime=` 与 `wallUnix=`；当前录制以 1 ms 声明
  不确定度对齐，旧日志仍可用 250 ms fallback 复算但只能保留为诊断基线。分析器的 no-follow、
  DTD/entity、missing-ref、symlink、重复 marker 与安全输出攻击夹具全部通过。
- [x] 调用栈定位 Permission Deny 慢帧：`TaskStore` 请求先移除、回执后写入，导致 SwiftUI 在两者间
  短暂构造并销毁完整 `TaskCard`，把品牌图、系统 glyph 与 AX tree 懒加载带到交互帧。现改为先无
  动画预留回执、再调用 production response；stale response 无动画回滚，成功继续 0.9 秒回执。
  Permission、Question、Plan 共用同一 sequencing。
- [x] 修复前 Permission resolved App update 最大 132.257 ms，`>33/50/100 ms = 2/2/1`，并有
  54.802 ms Potential Interaction Delay；修复后分别为 21.238 ms、`0/0/0` 与 0 hang。
  App-attributed frame 最大仍为 34.722 ms，明确不宣称全部帧低于 33 ms。
- [x] 样本分类固定：`traces-v7/approval-deny.trace` 为当前源码 accepted；`traces-v4` 三场景为
  pre-fix partial diagnostic；v5 点击发生在 trace 外、v6 命中 idle 实例、v7 Question 锁屏未完成，
  均 rejected/incomplete。修复后 Question Submit 与 Plan Review 继续待解锁补录。
- [x] 当前源码权威图 735 tests / 0 failures，全部稳定性轮次通过；Performance、Localization、
  Legal/Data Flow、CI diagnostics、Release Foundation、Sound、Log Privacy、完整 Security、
  `git diff --check` 与 21 项 build-flavor 反例全部通过。Sparkle disposable old-to-new 四条负向链
  同时通过。
- [x] fresh Production App 的 6 个 Mach-O 全为 arm64+x86_64，依赖闭包、法律字节、品牌资源与
  strict deep ad-hoc 通过；8-sample hermetic launch 正常 status 0 退出、服务与用户状态隔离。
  主 executable SHA-256：`5d42723d904ac5b00c0caede9240bfc69decfd9aa6c6fc174b8d5acc900e5b9b`。
  该 smoke 记录 `screen_locked=true`，不作为视觉、丝滑度、CPU/RSS 或能耗证据。
- [x] 审计报告：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/decision-motion-v1-20260831/DECISION_MOTION_AUDIT.md`
  （SHA-256 `7a7e1c67f88a16d076d50c4a60b846a435d4be3d2f91fb075eeb1d8bb628d9a3`）；
  同目录 `SHA256SUMS` 与 `TRACE_TREE_SHA256.txt` 绑定关键产物和 accepted raw trace tree。
- [ ] Mac 解锁后串行补录固定源码的 Question Submit 与 Plan Review，避免在 resolved window 频繁
  AX 轮询；VoiceOver spoken-output 与系统辅助开关仍只允许在隔离测试账户或 VM 完成。

## v6.75 商业激活 pre-provider 真实 loopback sandbox

- [x] 在 `IslandCoreTests` 内新增测试专属 Hummingbird server 与 transport；每轮使用合成 Ed25519
  key、合成隐私最小 License、随机 numeric `127.0.0.1` 端口和进程内存 document backend，通过
  真实 TCP/HTTP `POST /v1/activate` 驱动 production `CommercialLicenseActivationService`、验签与
  verify-before-save 路径，不访问维护者登录 Keychain。
- [x] 正向闭环证明 bounded activation-code body 到达精确 path，签名文档激活并存入内存；未签名
  response 固定为 `.licenseRejected` 且零存储。HTTPS、`localhost`、外部地址、userinfo、错误
  path、query 与 fragment 全部在连接前拒绝；URLSession 禁用 proxy/cookie/cache/redirect。
- [x] `CommercialActivationSandboxTests` 3 tests / 0 failures，随后以同一已构建测试目标重复 20 轮
  全部通过；Security gate 已静态固定 test-only、内存存储、精确 loopback endpoint 与 shipping
  source 零 sandbox 类型/ready route 边界。
- [x] Interface Contract v6.75、Data Flow Inventory、Activation Threat Model、Legal Release
  Checklist、CI Diagnostics 与法律/安全文档门禁同步，明确该闭环只证明 provider-neutral 客户端
  wiring，不冒充 TLS、provider/checkout、一次性 code、重放/枚举/速率限制、退款/撤销、设备/恢复、
  production key custody、真实 Keychain 或商业发布验收。
- [x] 当前源码权威图为 738 tests / 0 failures，全部版本/listener/tmux/Codex trust/sleep-wake
  稳定性轮次通过；完整 Security、Legal/Data Flow 与 `git diff --check` 通过。fresh Production App
  的 6 个 Mach-O 均为 Universal，依赖闭包、production marker、test-only sandbox symbol/string
  隔离、法律/品牌资源与 strict deep ad-hoc 签名通过；主 executable SHA-256 为
  `07ac2b74f85ea63152f3b50eef4249c1e8f76bece4a5a5c7231b262cd99b04c2`。
- [x] 8-sample hermetic Production launch 正常 status 0 退出、App/user home 与产品服务隔离；因
  `screen_locked=true`，只作为存活证据，不用于视觉、丝滑度或性能结论。只读审计报告：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/commercial-activation-sandbox-v1-20260831/COMMERCIAL_ACTIVATION_SANDBOX_AUDIT.md`
  （SHA-256 `93892fbeed18b68dcbb2cb562868647cb1e4b949888fa274a43be84b63f93c27`）；
  `SHA256SUMS` 与 `SOURCE_SHA256.txt` 已逐项通过。商业 provider、36 项政策、9 项商标、Developer ID/
  公证与远端 GitHub controls 继续保持独立 blocker。

## v6.76 商业激活 transport 失败关闭矩阵

- [x] 将 pre-provider sandbox 从签名/未签名两条链扩展到真实 HTTP 状态矩阵：400/401/404
  统一为 `codeRejected`，429 为 `rateLimited`，500/503 为 `serviceUnavailable`；provider-private
  fixture body 不进入 outcome 且所有拒绝路径零存储。
- [x] 302 携带同 server numeric-loopback `Location` 时 delegate 明确不跟随，redirect target
  计数保持 0；未知 418 与 32 KiB+1 的 200 body 均归一化为 `transportUnavailable` 且零存储。
  endpoint 同时新增缺失显式端口与 port 0 反例。
- [x] 明确不把测试 transport 当 production 模板：当前 synthetic local response 由便利 API 完整
  缓冲后检查大小；未来 HTTPS provider transport 必须在读取期间限制 bytes，并独立完成 TLS/server
  identity、timeout、retry、one-time code 与 abuse controls 评审。
- [x] 5 项 focused tests 连续 20 轮、共 100 次全部通过；当前权威图 **740 tests / 0 failures**，
  全部版本/listener/tmux/Codex trust/sleep-wake 稳定性轮次、完整 Security、Legal/Data Flow 与
  `git diff --check` 通过。
- [x] fresh Production App 的 6 个 Mach-O 均为 Universal；依赖闭包、production marker、test-only
  type/route/body/code/test-name string 与 symbol 隔离、法律/品牌资源及 strict deep ad-hoc 通过。
  主 executable SHA-256：`4d40902d86fe2cb6fb1acce1b8fa1f5ba04ab4dac3e2e1553bb7125421149efe`。
- [x] 8-sample hermetic launch 正常 status 0 退出、产品服务与用户状态隔离；
  `screen_locked=true`，不作为视觉/丝滑度/性能结论。只读报告：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/commercial-activation-failure-matrix-v1-20260831/COMMERCIAL_ACTIVATION_FAILURE_MATRIX_AUDIT.md`
  （SHA-256 `1127e1f923610a007a7fdc9fec2d286007bf59a1fade50ed511b7014e8bca011`）；
  `SHA256SUMS` 与 `SOURCE_SHA256.txt` 已逐项通过。
- [ ] provider/seller、36 项商业政策、真实 sandbox/TLS/streaming transport、Developer ID/公证、
  9 项商标、Manus 账号与远端 GitHub controls 仍保持独立 blocker；本阶段不改变免费 App 行为。

## v6.77 商业激活真实 HTTP operation ownership

- [x] 新增 cancellation-insensitive 攻击模式：test-only transport 将真实 URLSession 请求放入
  detached task，但继续受 2 秒 request/resource timeout 约束；外层 activation task 被取消或
  supersede 后，loopback server 的签名 response 仍真实返回，避免用合作式网络取消掩盖 actor
  operation ownership 缺陷。该 detached 模式禁止进入 shipping source，也不作为生产网络模板。
- [x] 显式 Cancel 在 server 已收到请求后发生；response recorder 证明晚到 response 确实返回，
  activation 固定为 `.cancelled` 且 document storage 保持 empty。latest-operation-wins 同时证明旧、
  新两个 request 与两个 response 都完成，旧 operation 为 `.superseded`，只有最新 operation 能
  验签并写入唯一有效 document。
- [x] 测试时序使用 actor-isolated request/response 计数与最长 1 秒 bounded wait，不依赖任意 client
  sleep；合成 server delay 限制为 0...2,000 ms。7 项 focused suite 连续 20 轮、共 140 次全部通过。
- [x] Interface Contract v6.77、Data Flow Inventory、Activation Threat Model、Legal Release
  Checklist、CI Diagnostics 与法律/安全静态门禁同步；完整 Security、Legal/Data Flow、
  `git diff --check` 通过，`Package.resolved` 未变化。
- [x] 当前源码权威图 **742 tests / 0 failures**；版本探针 20 轮 / 240 子进程、hermetic listener
  10 轮、tmux 20 轮、Codex trust 5 轮、sleep/wake 20 轮全部通过。
- [x] fresh Production App 的 6 个 Mach-O 均为 arm64+x86_64；依赖闭包、Production marker、
  strict deep ad-hoc、法律/品牌资源和 keyless Sparkle 隔离通过。sandbox 类型、取消不敏感 transport
  标记、delay/route/code/test-name string 与 symbol 均未进入出货二进制。主 executable SHA-256：
  `5f0988593bdf40478a51d056afc98e54d0a676ff758f34242bbb27a66fa26176`。
- [x] 8-sample hermetic launch 正常 status 0 退出、产品网络服务与用户状态隔离；
  `screen_locked=true`，不作为视觉、丝滑度、能耗或 Release 性能结论。只读报告：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/commercial-activation-operation-ownership-v1-20260831/COMMERCIAL_ACTIVATION_OPERATION_OWNERSHIP_AUDIT.md`
  （SHA-256 `a57a12b6cd58de2b77c9fa593665e32fe1bdfe1ee73650a59185ead097e2a3f5`）；
  `SHA256SUMS` 与 `SOURCE_SHA256.txt` 已逐项通过。
- [ ] provider/seller、真实 provider sandbox/TLS/streaming/cancellation、36 项商业政策、9 项商标、
  Developer ID/公证、production Sparkle、clean tag/Release、Manus 账号和 6 项远端 GitHub controls
  仍保持独立 blocker；Codex timeout fallback 等用户 Hook trust，Question/Plan motion 等 Mac 解锁。

## v6.78 商业激活 pre-cancelled zero ownership

- [x] 审计发现已在进入 `activate` 前取消的 caller 仍可能先 supersede 有效 pending activation，
  并创建 transport task；对于未来的一次性 activation code，这会让一个已经失效的 UI/调用方
  消耗 code，且无故终止真正仍在进行的 owner。
- [x] trusted-mode preflight 后新增 caller cancellation guard；pre-cancelled 调用直接返回
  `.cancelled`，不得 invalidate 当前 operation、创建 transport task 或发送请求。显式 Cancel、
  late-response 拒绝、latest-operation-wins 与 commit-time verify-before-save 语义保持不变。
- [x] 受控 transport 回归证明第二个 pre-cancelled caller 的 request count 不增加，原 operation
  后续仍可激活并成为唯一存储文档；真实 Hummingbird loopback 回归证明原 request 已到 server 后，
  第二调用仍带来零新增 HTTP request，最终精确为 1 request / 1 response 且原签名 response 激活。
- [x] 两个新 ownership 测试连续 20 轮、共 40 次全部通过；两个 focused suite 共 19 tests / 0
  failures。Interface Contract v6.78、Data Flow、License Security、Activation Threat Model、Legal、
  CI Diagnostics 与静态门禁同步。
- [x] 完整 Security 通过；当前源码权威图 **744 tests / 0 failures**，版本探针 20 轮 / 240 子进程、
  hermetic listener 10 轮、tmux 20 轮、Codex trust 5 轮与 sleep/wake 20 轮全部通过。
- [x] fresh Production App 的 6 个 Mach-O 均为 arm64+x86_64；依赖闭包、Production marker、
  strict deep ad-hoc、法律/品牌资源与 keyless Sparkle 通过。test server/transport、delay/route/code 和
  两个新测试名均未进入出货二进制。主 executable SHA-256：
  `c6a18a54b9a732d92e8680fa47784909a804cbe85fda4fd149ec438a6ecba5bc`。
- [x] 8-sample hermetic launch 正常 status 0 退出、产品网络服务与用户状态隔离；
  `screen_locked=true`，不作为视觉、丝滑度、能耗或 Release 性能结论。只读报告：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/commercial-activation-pre-cancelled-ownership-v1-20260831/COMMERCIAL_ACTIVATION_PRE_CANCELLED_OWNERSHIP_AUDIT.md`
  （SHA-256 `d9a11695baeed7bc7c662fcbd1702e4882c5f5e2d67ff44e0175778d1e84dcad`）；
  `SHA256SUMS` 与 `SOURCE_SHA256.txt` 已逐项通过。
- [ ] provider/seller、真实 provider sandbox/TLS/streaming/cancellation、36 项商业政策、9 项商标、
  Developer ID/公证、production Sparkle、clean tag/Release、Manus 账号和 6 项远端 GitHub controls
  仍保持独立 blocker；Codex timeout fallback 等用户 Hook trust，Question/Plan motion 等 Mac 解锁。

## v6.79 Welcome Tour studio polish

- [x] 以本轮当前源码的 opt-in 离屏快照审计 Welcome 英文/简中三步；旧版主要缺口是 canvas、
  stage 与 divider 值域过近导致层级偏平，以及连接矩阵中 Codex `Configured · review…` 可见截断。
- [x] 保留近黑、低饱和产品语言，用极弱黑灰 canvas、统一 gradient-backed stage shell、方向性 rim
  与克制阴影建立深度；window/stage 连续圆角提升为 18/14pt，主/次操作统一 10pt 圆角，标题由
  34pt 收至 32pt，不增加装饰卡片、插画或状态色光晕。
- [x] Welcome 页切换由 280ms、10/6pt 行程收至 240ms、6/3pt；Reduce Motion 继续 opacity-only。
  该代码契约降低横向 carousel 感，但锁屏离屏证据不能代替解锁后的帧节奏验收。
- [x] Codex 可见状态收敛为本地化 `Configured` / `已配置`，详细 Hook review 继续留在既有 AX 描述
  与 Settings。新增纯 presentation 回归；focused onboarding 为 10 tests / 0 failures。
- [x] English/简中六张 after 快照与三张同 viewport before/after 合图逐张检查，固定 760×500pt
  几何无裁切、无异常换行、无截断；VisualSnapshotTests 17/17 通过。
- [x] 当前源码权威图 **745 tests / 0 failures**；版本探针 20 轮 / 240 子进程、hermetic listener
  10 轮、tmux 20 轮、Codex trust 5 轮与 sleep/wake 20 轮全部通过；完整 Security、Legal/Data
  Flow、Localization、CI Diagnostics、Brand、Release Foundation 与 Performance Analysis 门禁通过。
- [x] fresh Production App 的 6 个 Mach-O 均为 arm64+x86_64；依赖闭包、Production marker、
  strict deep ad-hoc、双语法律/品牌资源与 keyless Sparkle 通过。主 executable SHA-256：
  `6c91c6431723f5318b33f0baa31662b13d15dc03a73b1e53456344563fd51b79`。
- [x] 8-sample hermetic launch 正常 status 0 退出、产品网络服务与用户状态隔离；
  `screen_locked=true`，不作为视觉、丝滑度、VoiceOver、能耗或 Release 性能结论。只读报告：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/current-visual-audit-v1-20260831/CURRENT_VISUAL_AUDIT.md`
  （SHA-256 `131b83dddc4705371c8d4ef1358310fe3235c8dfc5a241bcf385d9940f2ad22a`）；
  before/after、同 viewport comparison、
  `SOURCE_SHA256.txt` 与 Production smoke 均留在同一 T7 evidence root。
- [ ] Welcome 真实窗口页切换、hover/press、键盘焦点与 VoiceOver 仍待 Mac 解锁验收；Developer ID/
  公证、production Sparkle、商业 provider/36 项政策、9 项商标、Manus 账号和远端 GitHub controls
  继续保持独立 blocker。本轮未 commit、push、tag 或创建 Release。

## v6.80 Question 九宫格选择语言

- [x] 以本轮当前源码重新捕获 compact island、priority panel、permission/question/plan decision、
  20-session stress 与英文/简中核心界面；审计确认 Question 仍使用系统 `circle` / square selection
  symbol，是“九宫格点阵替代普通圆形”产品语言中最直接的遗留缺口。
- [x] Question 选项统一改为固定 15pt 的 3×3 点阵：未选是灰色 `.field`，单选已选是等待色
  `.ring`，多选已选是等待色 `.plus`；两层固定几何只用 opacity cross-fade，Reduce Motion 下即时
  切换，不发生 symbol geometry 跳变。选项连续圆角由 6pt 收敛到 9pt。
- [x] 点阵保持 `accessibilityHidden`；现有 Button label/hint、Selected/Not selected value 与
  `.isSelected` trait 全部保留，选择同时通过 pattern 与颜色表达。新增 pure presentation mapping
  回归和单选/多选 selected-state 视觉证据。
- [x] 同 viewport 英文/简中 Question before/after 合图逐张检查，无裁切、错位或异常换行。44 张
  baseline 均有 after：42 张 byte-identical，仅两张预期 Question surface 变化；另新增 selection
  gallery，VisualSnapshotTests 18 tests / 0 failures。
- [x] 当前源码权威图 **747 tests / 0 failures**；版本探针 20 轮 / 240 子进程、hermetic listener
  10 轮、tmux 20 轮、Codex trust 5 轮与 sleep/wake 20 轮全部通过；完整 Security、Localization、
  Legal/Data Flow、CI Diagnostics、Brand、Homebrew、Release Foundation、Performance Analysis、
  signal sound 与 runtime-log privacy 门禁通过。
- [x] fresh Production App 的 6 个 Mach-O 均为 arm64+x86_64；依赖闭包、Production marker、
  strict deep ad-hoc、双语法律/品牌资源与 keyless Sparkle 通过。主 executable SHA-256：
  `2fa6e4a6c4a55f34c40be5b98328b37c01aad9bdaa05941831d7972ac9e4d257`。
- [x] 8-sample hermetic launch 正常 status 0 退出、产品网络服务与用户状态隔离；
  `screen_locked=true`，不作为视觉、丝滑度、VoiceOver、能耗或 Release 性能结论。只读报告：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/current-island-panel-audit-v1-20260831/CURRENT_ISLAND_PANEL_AUDIT.md`；
  before/after、同 viewport comparison、selected-state gallery、`SOURCE_SHA256.txt` 与 smoke 证据
  留在同一 T7 audit root。
- [ ] Question hover/press、真实选择 transition、Reduce Motion、键盘焦点与 VoiceOver 仍待 Mac 解锁；
  Developer ID/公证、production Sparkle、商业 provider/政策、商标、Manus、远端 GitHub controls 与
  clean tagged Release 继续保持独立 blocker。本轮未 commit、push、tag 或创建 Release。

## v6.81 商业激活 hardened HTTPS transport foundation

- [x] 新增默认关闭、provider-neutral 的 `CommercialActivationHTTPSTransport`；只接受 public-DNS
  HTTPS、精确 `/v1/activate`、默认或 443 端口，拒绝 userinfo/query/fragment、IP、single-label、
  reserved/local suffix、非法 label 与 percent-encoded path 绕过。未来 provider 必须在 App 内硬编码
  经评审 endpoint；当前 `IslandApp` / `IslandAppLib` 零实例化，免费产品行为不变。
- [x] 默认 session 为 ephemeral，关闭 proxy/cookie/cache/ambient credentials/connectivity waiting，
  request/resource timeout 固定 10 秒、每 host 单连接且 redirect 固定拒绝。bounded activation code
  只进入 octet-stream POST body，不进入 URL/header；临时 body buffer 在请求交接后清零。
- [x] 成功 response 必须为相同 final URL、HTTP 200 与
  `application/vnd.devisland.license`；declared/unknown-length 都在读取期间限制为 32 KiB，空 body
  失败关闭。400/401/404、429、5xx 只映射既有低基数状态，provider body、raw network error、
  endpoint 与 activation code 不进入公开错误；caller cancellation 保持 `CancellationError`。
- [x] 10 项 focused regression 覆盖 endpoint、session、redirect、精确 request、streaming、状态映射、
  declared/unknown oversize、边界长度、错误脱敏与 cancellation，全部通过；完整 Legal/Data Flow 与
  Security gate 通过。shipping source 静态禁止 URLProtocol/XCTest/private signing key/logging，App
  接线门禁保持零 production activation transport 实例。
- [x] 当前源码权威图 **757 tests / 0 failures**；版本探针 20 轮 / 240 子进程、hermetic listener
  10 轮、tmux 20 轮、Codex trust 5 轮与 sleep/wake 20 轮全部通过；`git diff --check` 通过。
- [x] fresh Production App 的 6 个 Mach-O 均为 arm64+x86_64；依赖闭包、Production marker、
  strict deep ad-hoc、法律/品牌资源与 keyless Sparkle 通过。主 executable 不含 HTTPS test
  URLProtocol/fixture、测试 host/code/body/test-name，SHA-256：
  `d5fa4be7ee359534fffef8fc72239949a9f64c458923e5051a3412cf6da3e4b4`。
- [x] 8-sample hermetic launch 正常 status 0 退出、产品网络服务与用户状态隔离；
  `screen_locked=true`，不作为视觉、丝滑度、VoiceOver、能耗或 Release 性能结论。只读报告：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/commercial-activation-https-transport-v1-20260831/COMMERCIAL_ACTIVATION_HTTPS_TRANSPORT_AUDIT.md`
  （SHA-256 `7698c14b30d895c05184be3a79f9c4bdebb948275749f7d35317fdc3a9ae427e`）。
- [ ] provider/seller、固定 production endpoint 与真实 sandbox/TLS/cancellation、一次性 code/abuse
  controls、36 项商业政策、9 项商标、Developer ID/公证、production Sparkle、Manus 账号、远端
  GitHub controls 与 clean tagged Release 继续保持独立 blocker。本轮未 commit、push、tag 或发布。

## v6.82 商业激活 endpoint capability seal

- [x] `CommercialActivationHTTPSTransport` 的 endpoint initializer 从公开 API 收回为
  `IslandCore` module-internal；未来 provider 接入只能新增经源码评审、无 URL 参数的 factory，
  并把唯一 endpoint 固定在源码中，不允许从 UI、preferences、environment、remote config 或其他
  runtime input 构造。`IslandApp` / `IslandAppLib` 仍禁止实例化该 transport，免费产品行为不变。
- [x] Security gate 同时禁止 transport 暴露 public initializer/public static factory，并禁止 shipping
  App 模块构造它；从 fresh arm64 Release module 提取的 Swift Symbol Graph 机器检查确认该类型
  **0 个 public initializer、0 个 public type factory**，而协议的 public
  `exchange(activationCode:)` requirement 保持 **1 个**。
- [x] URLProtocol 测试夹具新增实例绑定的 `stopHandler`；caller cancellation 回归在确认 request 已
  进入底层 loader 后取消 task，并等待 `URLProtocol.stopLoading()` 的真实证据，再断言外层保持
  `CancellationError`。因此本轮不仅证明结果被丢弃，也证明 in-flight URLSession request 被停止。
- [x] Focused HTTPS suite **10 tests / 0 failures**；完整 Legal/Data Flow 与 Security gate 通过。
  当前源码权威图 **757 tests / 0 failures**；版本探针 20 轮 / 240 子进程、hermetic listener
  10 轮、tmux cleanup 20 轮、Codex trust 5 轮与 sleep/wake 20 轮全部通过。
- [x] fresh Production App 的 6 个 Mach-O 均为 arm64+x86_64；依赖闭包、Production marker、
  双语法律/品牌资源、keyless Sparkle 与 strict deep ad-hoc 通过。测试 URLProtocol/fixture、测试
  host/code/body/test-name 均未进入 Production executable。冻结副本与 fresh build 主 executable
  SHA-256 一致：`fcd3ba6a9334f6683112eab734786020c1a6110848b5380ba6e8d51f7393a7fd`。
- [x] 8-sample hermetic launch 在隔离 App/user state 与关闭产品服务的条件下正常 status 0 退出；
  launch-ready 约 1.049 秒，平均 CPU 2.05%，RSS 增长 128 KB。采样时屏幕虽已解锁，但没有执行
  真实视觉交互，因此该 smoke 只作为启动存活与隔离证据，不作为丝滑度、VoiceOver、能耗或
  Release 性能结论。审计根目录：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/commercial-activation-endpoint-seal-v1-20260831/`。
- [ ] provider/seller、经评审的唯一 production endpoint、真实 provider sandbox/TLS/certificate/
  cancellation、一次性 code 与 abuse controls、36 项商业政策、9 项商标、Developer ID/公证、
  production Sparkle、Manus 账号、远端 GitHub controls 与 clean tagged Release 继续保持独立
  blocker。本轮未 commit、push、tag 或发布。

## v6.83 同 Bundle 单实例接管与解锁 Welcome 实证

- [x] 解锁真实验收确认 Welcome Tour 简中三页无裁切、异常换行或状态跳变；01→02→03 切换完成，
  右上关闭能回到同一 Settings owner。系统 Reduce Motion、Increase Contrast、Reduce
  Transparency 与 grayscale 均保持关闭。`AppleKeyboardUIMode=0` 时 Tab 不遍历全部按钮属于当前
  macOS 键盘导航设置，本轮未擅自更改系统设置或触发最终通知授权。
- [x] 验收同时发现 T7 当前副本与 `/Applications` 旧副本可因相同 Bundle ID 并行运行，造成两个
  Island、两个 status owner 与窗口路由混淆。新增 `AppSingleInstanceGate`：普通启动在任何窗口、
  TaskStore/service 与 LaunchHealth 写入前按同 Bundle ID 的最低正 live PID 选出唯一 owner。
- [x] newcomer 只有在 AppKit 成功激活精确 winner 后才 status 0 退出；winner 竞态消失时 fail open，
  当前实例继续启动。yield 实例的 termination callback 保持 no-op。精确双 opt-in 的 hermetic
  Production smoke 明确绕过 gate，不会激活或退出用户已安装实例。
- [x] 5 项纯策略回归覆盖唯一实例、旧实例胜出、当前实例最老、terminated/非法候选与非法 current
  PID；Performance 静态门禁固定 `NSWorkspace` 最小读取、最低 PID、activation-before-exit、
  LaunchHealth/IslandWindow 前置顺序、yield cleanup 与 hermetic bypass。
- [x] 两个 byte-identical Production 副本真实运行：第一个 PID 64999 唯一监听 `127.0.0.1:7824`；
  第二副本两次分别以 PID 68011/68456 启动，341/365 ms 内正常 status 0 退出。之后仍精确一个
  PID、一个 listener，第一副本的 `Dev Island / 暂无会话` AX surface 前后可交互。
- [x] 在第一普通实例仍运行时，额外 Production hermetic PID 69078 成功绕过 gate，8-sample
  隔离 smoke 正常 status 0 退出；第一 PID 与唯一 listener 随后保持不变。一次并行 fingerprint
  比较中第一实例 SQLite 正常变化，不能归因于 newcomer，因此明确排除，不作为验收证据。
- [x] 当前源码权威图 **762 tests / 0 failures**；版本探针 20 轮 / 240 子进程、hermetic listener
  10 轮、tmux cleanup 20 轮、Codex trust 5 轮与 sleep/wake 20 轮全部通过；完整 Security、
  Legal/Data Flow、Performance、Localization、Release Foundation 等聚合门禁通过。
- [x] fresh warning-free Production App 的 6 个 Mach-O 均为 arm64+x86_64；依赖闭包、Production
  marker、双语法律/品牌资源、keyless Sparkle 与 strict deep ad-hoc 通过。冻结副本主 executable
  SHA-256：`f8c143debec73a87206d4703c65a9fc20616c5f1a11042a037f670d4a6a2d6f4`。
  审计根目录：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/single-instance-v1-20260831/`。
- [ ] 旧版本自身不包含本 gate，用户在新版运行时主动再次启动一个旧副本仍需由旧进程升级/退出
  解决；同 Bundle ID 也不是安全身份。本轮未替换 `/Applications` 安装版，未 commit、push、
  tag、notarize 或发布 Release；外部商业、签名、商标、GitHub 管理与真实 Agent blocker 保持开放。

## v6.84 可信代码身份单实例仲裁与 Security bridge 实证

- [x] 将 v6.83 仅按 Bundle ID 的可靠性 gate 收紧为代码身份仲裁：同 Bundle ID 只用于筛出至多
  32 个候选；当前进程与动态 PID 都必须由 Security.framework 解析出精确 code identifier。非
  ad-hoc 身份必须通过 Apple-generic anchor、精确 identifier 与证书 OU/Team ID 要求；只有签名
  flags 明确标记为 ad-hoc 时才允许使用非空且完全相同的 CDHash。Team/hash 混合、无 Team 的非
  ad-hoc、字段缺失或身份不一致全部忽略，不读取候选 path、argv、environment、window、preference、
  task/session、credential 或 IPC。
- [x] 只选择最低的旧可信 live PID；激活前立即重新解析其完整身份，并要求首次与二次结果连
  CDHash 都一致，以发现退出、PID reuse 或身份漂移。只有该精确 PID 的 AppKit activation 成功，
  newcomer 才 yield；候选过多、签名/生命周期异常或激活失败均 fail open，避免误激活伪 App 或让
  两个实例同时退出。Repository 的精确双 opt-in hermetic Production smoke 继续显式绕过本 gate。
- [x] 首个 v2 Production artifact 在 gate 源码仍调整且 SwiftUI 根 `Settings` Scene 可能先构造
  `SettingsView` / `TaskStore.shared` 的情况下生成，已整体标记 **rejected / non-authoritative**，
  不用于完成结论。v3 将根 Scene 收敛为 inert placeholder，真实 Settings 仍由通过 gate 后的
  AppDelegate 惰性拥有；因此 yielding newcomer 在 Island、status item、listener、SQLite、Hook
  authorization 与其他产品服务创建前退出。v3 是本节唯一 authoritative artifact。
- [x] 代码身份 focused suite **23 tests / 0 failures**；当前源码权威图 **780 tests / 0 failures**，
  完整 Security、Legal/Data Flow、Performance Analysis 与 `git diff --check` 通过。v3 Production
  App 的 6 个 Mach-O 均为 arm64+x86_64，依赖闭包、Production marker 与 strict deep ad-hoc
  签名通过；主 executable SHA-256：
  `0605763b23990ffe2094435fac895bbf104151e8661823c96a9ca409145ef1f3`。本机 native arm64 解析的
  App CDHash 为 `70b870d790f6ccd809df3ce54144982a57177b3e`。
- [x] 两个 App tree manifest 完全相同且 native CDHash 一致的 ad-hoc 副本完成 **20/20** 真实
  LaunchServices 仲裁；每轮 duplicate PID 均在 gate 后消失，始终只保留一个 App owner 与一个
  `127.0.0.1:7824` listener，逐轮检查 owner 没有其他 network socket，duplicate private user root
  没有 `tasks.sqlite`、`local-hook-authorization.header` 或其他产品状态。进程级耗时
  min / median / p95 / max 为 **231 / 235.5 / 302 / 1155 ms**；首轮冷路径离群值保留在统计中，
  未用平均值掩盖。
- [x] 同 Bundle ID、显式 ad-hoc 但不同 CDHash 的最小 AppKit impostor 先运行后，真实 v3 App 仍
  启动并成为唯一 `127.0.0.1:7824` owner；impostor 全程存活、零 network socket，activation 回调
  保持 **0→0**，且真实 App 启动没有向它发送 termination。该结果证明本机 native Security bridge
  不把 Bundle ID 冒充者当可信 owner；它不等同于跨 Team、Developer ID 或恶意同用户进程的完整
  平台安全认证。
- [x] authoritative 只读证据位于
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/single-instance-identity-v3-20260831/live-identity-matrix-v6/`；
  `SINGLE_INSTANCE_IDENTITY_AUDIT.txt`、20 轮 CSV 与 App tree manifest 的 SHA-256 均复验通过。
  屏幕从 initial 到 final 均为 locked，因此本轮只证明进程/签名/listener/state 边界，不证明真实
  Island、焦点、Dock、AX、丝滑度或视觉交互。普通 owner 的 `CFFIXED_USER_HOME` 不隔离 login
  Keychain；harness 没有读取 key 内容且每次网络检查只看到 loopback listener，但该矩阵仍不能称为
  hermetic。LaunchServices 启动的 App 真 exit code 不可观测，故结论严格写为 PID disappeared，
  不把 launcher status 或进程消失虚构成 App `status 0`。
- [ ] 当前实证是 owner 已 ready 后再启动 duplicate，不覆盖两个副本同时 cold launch 时的真实
  LaunchServices 注册竞态；首轮 1155 ms 也只作为锁屏进程级样本。Universal 闭包虽已通过，本机
  只实测 native arm64 CDHash，尚未在 Rosetta/x86_64 下复验同副本身份。相同 Team 跨版本仍必须用
  两个真实 Developer ID artifact 验收，并继续等待公证/Gatekeeper。旧版本自身没有 gate，无法由
  新版本安全强退；若它在新版后主动启动仍需升级或手动退出。本轮未替换 `/Applications`，未
  commit、push、tag、notarize 或发布 Release；商业 provider、政策、商标、production Sparkle、
  Manus、远端 GitHub controls 与 clean tagged Release 继续保持独立 blocker。

## v6.85 Manus Webhook trust generation 与 cleanup transaction

- [x] replay window 不再跨 callback/key 代际污染：trust tuple 固定为 exact external URL 与
  Security.framework canonical RSA bytes 的 SHA-256。RSA key 必须至少 2,048-bit；同一 key 的
  PKCS#1/SPKI PEM 等价表示保持窗口，URL 或真实 key 变化才以原 capacity 原子 reset。非法 URL、
  非法/弱 key 全部在提交前失败，旧 authenticator、URL、generation 与 replay state 不变。
- [x] 每次验签结果携带当时的 private generation UUID。真实 HTTP 请求若在 authentication 后暂停、
  期间发生 trust rotation，恢复时返回 `staleTrustGeneration` / 401，零 delivery 且不把旧代
  `event_id` 写入新窗口；随后相同 ID 经新 tuple 验证仍能首次 delivery。
- [x] Webhook ID 从单值升级为 cleanup 集合：接受 registration 后立即持久化 authoritative
  `webhookIds`，同时兼容 legacy `webhookId`；初始化恢复、去重，多个交错 accepted ID 均保留。
  start/wake/replacement 必须先删除全部遗留 ID，失败时禁止建立新的公网 callback。
- [x] 每个 ID 的 stop/wake/heartbeat/late-registration 删除共享一个 operation；process 先停止，
  provider delete 只有 HTTP 2xx 且 JSON `ok == true` 才确认。`ok:false`、缺失/非法 JSON、HTTP 或
  transport 失败保留 ID 并返回 `webhookCleanupFailed`；heartbeat 不重建，转为 polling-only。
- [x] credential-releasing stop 先停止每个 launch 已附着的 process，并只在 bounded
  `launchCancellationGrace` 内等待 in-flight registration；若 cancellation-unaware 请求仍无结果，则
  保留 credential、retained launch owner 与 durable ambiguity marker 并返回 cleanup failure。晚到 ID
  先持久化再 rollback；cleanup failure 优先于 lifecycle superseded 返回，单次 stop 不做无界重试，
  后续 start/stop 可恢复。只有 credential release 成功时，registration/deletion cleanup operations、
  authoritative ledger 与 ambiguity markers 才必须全部清空。
  stop 在首个 await 前快照 entry-time deletion operations/attempt sequence，按 active transport →
  入口删除 → registration → late deletion → 本轮未尝试 persisted sibling ID 的顺序 drain；
  一个 joined ID 失败不会压制其他 ID，也不会跳过入口时已在进行的删除而提前
  释放 credential。即使并发路径丢失具体 error，authoritative ledger 只要非空，stop 就必须
  fail closed，绝不能成功释放 credential。
- [x] `TaskStore.clearAPIKey()` 改为 delete-before-credential-release：先 detach/停 poller/移除 Manus
  snapshot，在 Keychain credential 仍存在时 await tunnel cleanup。失败则 reattach cleanup owner、
  保留 key 与原 API 状态，进入固定 `Remote callback cleanup pending; retry disconnect`；下一次
  Disconnect 重试成功后才删除 Keychain 并显示 Not Configured。
- [x] `configureAPIKey()` 会先 join 正在进行的 Disconnect removal；替换已有 key 时，candidate 只能
  先验证，必须用旧 manager / credential 完成旧 Webhook cleanup 后才可 Keychain save。失败保留旧
  key，candidate 零持久写入。realtime gate 关闭的 polling-only 生命周期也持有不开放 listener 的
  cleanup-only manager，从 shipping preferences 恢复 ledger，供 Disconnect 或换 key 清理。
- [x] 旧 callback cleanup 成功后，替换流程会先 detach 旧 tunnel/poller/connectors、移除 Manus
  snapshot 并发布 disconnected，再保存 candidate。Keychain save 失败时 read back 真实持久
  状态，不启动 candidate，也不 resurrect 旧服务；有 key/无 key/read-back 失败分别收敛到
  valid/notConfigured/保守旧状态，后续 Configure/Disconnect 可确定性恢复。
- [x] 正常 Quit 不再 fire-and-forget：`TaskStore.shutdown()` 先同步设 terminal flag、cancel/resume
  action continuations、detach ingress/observers/services，再由一个 memoized task 按序 join existing
  Disconnect、sleep suspension、poller、tunnel、local start/serve stop 与 retained bootstrap。每个
  bootstrap/storage/provider await 后都有 terminal guard，Quit 后 Configure/Disconnect/Wake/retry/观察器不得
  重启服务。并发调用及调用者 cancellation 均不会拆分/取消该 single-flight，结果只有
  `completed` / `cleanupPending`。
- [x] shutdown 也覆盖“Disconnect operation 已登记但 cleanup body 尚未运行”与“local retry
  已入队但尚未执行”两个窗口：前者被 terminal generation supersede/join 且不得在 Quit 后
  删 Keychain；后者被保留并先 join，再 stop 具体 local server，不得在 stop 后 restart。
- [x] `PollingFallback.stop()` 现在 cancel 后 join cancellation-unaware poll；LocalHookServer 会 join
  readiness + serve tasks，WebhookServer 会 join serve task。回归后原 loopback 端口可立即重绑，
  晚到 poll snapshot 不能再发布。PollingFallback 对 current/retiring poll operations 使用 token 所有权，
  LocalHookServer 对 current/retiring serve + readiness operations 使用同样边界；start/restart/
  auto-retry 只能 retire 旧句柄，stop 必须 snapshot/cancel/await 全部当前与已退役 operations，
  不再只 join 最新 generation。
- [x] AppKit 普通 owner 使用 `.terminateLater` 和独立两秒 hard timeout；cleanup/timeout 竞争
  同一 private token 并 finish-once，不会等待未响应的 task-group child。remote cleanup 失败或
  超时都允许退出，但 credential + authoritative `webhookIds` ledger 继续保留供下次启动恢复。
  yielded duplicate、Performance QA、hermetic Production smoke 直接 `.terminateNow`，不调度 cleanup/
  timeout/reply，不因退出路径构造 `TaskStore.shared`；`applicationWillTerminate` 不二次 shutdown。
- [x] 定向回归源码覆盖 canonical generation、弱 key、invalid candidate 原子性、旧代请求交错、
  遗留/重叠多 ID、cleanup-only ledger、late registration、heartbeat failure、`ok:false`、credential
  保留/重试、replacement key 零提前覆盖/save-failure read-back，sibling-ID 删除与 entry-time
  deletion join，以及 shutdown single-flight/caller cancellation/Disconnect/sleep/bootstrap 顺序、joinable stop/端口
  重绑、AppKit finish-once/三 bypass。所有 fixture 仅使用 loopback、合成 RSA、隔离 UserDefaults 与
  进程内 Keychain backend。
- [x] 本轮两次 focused 验证共 **146 checks PASS**：Quit/Manus/listener/poller/AppTermination 等
  8 suites 为 118/118，ManusAPIClient + connection presentation 补充为 28/28；
  `swift build --product IslandApp` 同时 PASS。这只是定向回归与开发构建证据，不等于
  authoritative full suite、Universal Production artifact 或 Release 验收。
- [x] v6.85 当时的 authoritative full suite **822 tests / 0 failures**；Security、Legal/Data Flow、
  Performance Analysis 与 `git diff --check` 全部通过。版本探针 20 轮 / 240 子进程、hermetic
  listener 10 轮、tmux cleanup 20 轮、Codex Hook trust 5 轮与 sleep/wake 20 轮均通过。
- [x] fresh warning-free Universal Production App 的 6 个 Mach-O 均为 arm64+x86_64；依赖闭包、
  Production marker、双语法律/品牌资源、keyless Sparkle、全闭包无 `get-task-allow` 与 strict deep
  ad-hoc 签名通过。主 executable SHA-256：
  `081a1c123897f167327e0d1a6cf33ae5d28cf9f40d56dd75ccd4cc517f30cca9`。
- [x] 8-sample hermetic Production launch 在隔离 App/user state、关闭产品服务的条件下正常
  status 0 退出；冻结副本与所选 executable SHA-256 一致，launch-ready 约 1.446 秒。全程
  `locked → locked`，因此仅作为启动、隔离与正常退出证据，不作为视觉、焦点、VoiceOver、动画
  丝滑度、能耗或真实性能结论。审计根目录：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/v6.85-quit-20260831/`。
- [x] 上述 v6.85 的 **822 tests / 0 failures**、Universal Production artifact、主 executable
  SHA-256 与审计根只对应当时的源码快照；后续 strict-join 源码改动已经 supersede 这些证据，
  不得把它们当作当前 working tree 的 full-suite、artifact 或 build-hash 验收。

## 2026-08-31 Tunnel / Local Hook strict-join follow-up

- [x] Tunnel heartbeat 改为 tokenized current/retiring ownership；stop、suspend、wake 与 successor
  start 都先 retire current heartbeat、cancel/stop launch，再 strict join retiring heartbeat，之后才
  drain 可能由 heartbeat 晚到发布的 retained lifecycle callbacks。successor 在这些 callback 完成前
  不得启动或提升新 transport。
- [x] lifecycle callback 自身也成为 retained operation。TaskLocal callback token 只切断 callback
  调用 `stop()` 时的自等待边；外部 `stop()` 无论 cleanup 成功或抛错，都必须先 strict join callback
  才返回，因此 callback ↔ stop single-flight 不形成环，也不会把 error path 变成提前返回路径。
- [x] retained launch operation 在 `process.start()` 前持有局部 cloudflared process。registration
  阻塞时 stop 可立即停止该 process，仅在 bounded `launchCancellationGrace` 内等待；超时则保留
  credential、launch owner 与 ambiguity marker，fail closed 返回 cleanup failure。若晚到 accepted
  ID，则先持久化 authoritative ID，再执行 compensating delete，绝不把 obsolete transport 提升为
  active；只有成功 credential release 才要求 registration/deletion cleanup operations、ledger 与
  marker 全部清空。
- [x] registration 请求跨网络前先持久化 ambiguity marker。409 Conflict 与 429/rate-limit 均按
  outcome unknown 保守处理；marker 跨重启保留，阻止 credential release 与重叠 registration，直到
  结果可被证明并完成补偿清理。
- [x] Local Hook delivery 对每个 source 使用 tokenized current/retiring drain ownership。stop 先停止
  接收，清空队列并让 queued action barrier 返回 `false`，再 cancel/join 所有 cancellation-unaware
  drains；superseded generation 也不能被遗忘或在 stop 后发布事件。
- [x] delivery callback 内部 stop 通过 TaskLocal identity 精确 self-exclude；真实 Hummingbird listener
  使用 graceful shutdown，让当前 action HTTP 请求仍可返回 `{}` 并释放端口。被 self-exclude 的
  callback、delivery 与 server generation 继续 retained，后续外部 stop 必须全部 strict join。
  TaskStore 的生产 App-Quit listener cleanup 来自 callback 之外的独立清理任务，因此走 external
  strict-join 路径。
- [x] 该 strict-join 阶段的初始验证证据仅为：`TunnelManagerTests` **32/32 PASS**；同一 suite 的 `--skip-build`
  **连续 10/10 轮 PASS（每轮 32/32）**；`TaskStoreManusLifecycleTests` **24/24 PASS**；Local Hook
  scoped suites **69 tests / 0 failures**；5 条 ownership/self-stop 竞态测试 **连续 20 轮 PASS**；
  Tunnel 与 Local Hook 两边 scoped `git diff --check` 均 PASS。
- [x] 该 strict-join 阶段当时的 working tree 已完成新的 authoritative wrapper：**836 tests / 0 failures**；
  local version probe 20 轮 / 240 子进程、hermetic listener 10 轮、tmux cleanup 20 轮、Codex Hook
  trust 5 轮与 sleep/wake 20 轮全部 PASS。Security、Legal/Data Flow、Performance Analysis、
  Localization、Release Foundation、Repository Script Syntax 与全仓 `git diff --check` 也全部通过。
- [x] 以独立 T7 SwiftPM scratch 重新构建 fresh warning-free Universal Production App。6 个 Mach-O
  均精确为 arm64+x86_64；依赖闭包、Production marker、双语法律/本地化/品牌资源、34 份 license、
  keyless Sparkle、全闭包无 `get-task-allow` 与 strict deep ad-hoc 签名通过。主 executable SHA-256：
  `1f94620c17c9387c09711bc9c4681a1971094e4c48daf671a195da81a263c609`。
- [x] 精确 `production-launch-smoke` 完成 8 样本：冻结副本与所选 executable hash 一致，产品服务、
  App snapshot 与 user home 隔离，AppKit 正常 `status 0` 退出；launch-ready 约 1.550 秒。屏幕全程
  `locked → locked`，因此该结果只证明启动、隔离与正常退出，不作为视觉、焦点、VoiceOver、动画
  丝滑度、能耗或真实性能结论。当前审计根目录：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/v6.85-strict-join-20260831/`。
- [ ] `ManusRealtimeTrust.liveV2AcceptanceComplete` 继续固定为 `false`。官方
  `GET /v2/webhook.list` 已接入恢复路径：只有 active、精确 callback digest、
  `startedAt ± 300s` 且本地 marker 唯一可归属时才绑定 ID，并在首次删除前
  原子持久化。空 inventory、枚举失败、多 marker 歧义、inactive/越界条目或损坏状态
  都保留 durable marker 并 fail closed。由于尚无真实账号的 create → signed delivery →
  list/delete 以及 read-after-create/read-after-delete 一致性证据，公网 realtime 仍不得
  宣称商用或生成 `ACCEPTED` 证据。Developer ID/公证、production Sparkle、商业/商标与
  clean tagged Release 仍是独立 blocker。本轮未替换 `/Applications`，未 commit、push、tag、
  notarize 或发布。

## 2026-08-31 webhook.list shared-waiter terminal-race follow-up

- [x] 重复 Tunnel soak 在第 21 次独立进程重现了真实竞态：`start()` 与 credential-releasing
  `stop()` 共享同一次 account-level list task，但不共享 list 返回后的“绑定 ID → 删除”
  调用栈。当 start waiter 先恢复时，它会持久化 recovered ID 并创建 delete task；stop 的旧
  unbound snapshot 正确拒绝重复归属，却在未 join 该 late delete 时进入 terminal gate，偶发
  `persistedWebhookIDsRemain`。
- [x] `performStop` 现在会在 reconciliation 后、server teardown 与 credential-release terminal gate 前，
  动态 final-drain 并 join 当前仍保留的每个 `webhookDeletionOperations` token。它不再按旧
  `attemptedWebhookIDs` 排除同 ID 的替代 token；同时只等待已经发布的 provider operation，
  不遍历 `knownWebhookIDs` 发起第二次删除，因此不破坏“同一次 stop 不重试已失败 provider
  call”的边界。
- [x] 新回归用 inert test hook 精确编排：stop 已 join list → list 同时返回但暂停 stop
  → start 先 bind 并创建 blocked delete → stop 跳过 stale unbound row → final drain 成为第二个
  delete waiter → provider delete 仅执行一次。另一条独立回归先让 stop 删除 seeded known ID，
  再让 stale list waiter 为相同 ID 发布替代 token；waiter token 精确为 `token1, token2, token2`，
  provider delete 精确两次而不是三次，证明 final drain 是 join 新 ownership 而不是重试 ledger。
- [x] 定向 Tunnel suite **49/49 PASS**；首次-ID race 与同-ID替代-token race 均完成独立 Swift
  测试进程 **100/100 PASS**。Security gate 另固定 reconciliation → token drain → server teardown
  顺序，并拒绝 final drain 出现 stale ID 过滤或 `deleteKnownWebhook` ledger 重试。
- [x] 修复后的 authoritative wrapper 已重跑为 **885 tests / 0 failures**；
  local version probe 20 轮 / 240 子进程、hermetic listener 10 轮、tmux cleanup 20 轮、
  Codex Hook trust 5 轮与 sleep/wake 20 轮全部 PASS。
- [x] 从最终源码使用独立 T7 SwiftPM scratch 全新构建 keyless Universal Production App；6 个
  Mach-O 均为 arm64+x86_64，依赖闭包、Production marker、双语法律/品牌资源、34 份 license、
  全闭包无 `get-task-allow` 与 strict deep ad-hoc 通过。主 executable SHA-256：
  `aff6003ea8e14935144a9d69935e5dd8168b922b3e0240881c4352902ab0781f`。
- [x] 锁屏 `production-launch-smoke` 完成 8/8 样本、产品服务与用户状态隔离、AppKit 正常
  status 0 退出，冻结副本与所选 executable hash 一致；`locked → locked` 只证明 loader、存活、
  隔离与正常退出，不作为视觉、焦点、VoiceOver、动效丝滑度、能耗或真实性能结论。最终证据根：
  `/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/v6.86-final-20260831/`。
- [ ] `ManusRealtimeTrust.liveV2AcceptanceComplete=false` 继续保持。真实 Manus 账号 create →
  signed delivery → list/delete 及 read-after-create/read-after-delete 一致性、当前 Codex Allow Once /
  Deny 精确候选、Developer ID/公证/stapling、production Sparkle、商业/商标审批、远端 GitHub
  controls 与 clean tagged Release 仍是独立 blocker；锁屏也未完成视觉、焦点、VoiceOver 和动效
  实机验收。本轮未替换 `/Applications`，未 commit、push、tag、notarize 或发布。

## 2026-09-02 Pinned create-dmg 发布边界收口

- [x] 接续 2026-09-01 02:46 中断的工作区：`release.yml` 改为 `Prepare pinned create-dmg`
  精确 commit 下载 + 描述符校验、`Package DMG` 无 Secret 独立 step、两次 keychain
  setup/即时 teardown；四个新脚本（`prepare-pinned-create-dmg.sh`、`run-pinned-create-dmg.rb`、
  `verify-pinned-create-dmg-tool.rb`、`verify-pinned-create-dmg-execution-boundary.sh`）与
  两份文档已就位，但门禁当时未在本地跑过。
- [x] 本地复跑发现 `release.yml` 与文档/门禁不一致的两处 step 顺序：`Tear down App signing
  keychain` 被放在 `Notarize` 之前，`Build .app` / `Verify app dependency closure` 被放在
  `Setup App signing keychain` 之前。`INTERFACE_CONTRACT.md`、`GITHUB_REPOSITORY_CONTROLS.md`、
  `verify-workflow-checkout-isolation.rb`、`verify-release-foundation.sh` 与
  `verify-performance-analysis.sh` 五处口径一致，且门禁锚定的各 step run body 哈希与当前
  文件完全吻合，故只把两步挪回文档规定位置，未改任何 run body。
- [x] 本机补装 ripgrep 15.2.0 后，`verify-workflow-run-shells.rb`（23 steps）、
  `verify-repository-script-syntax.rb`（54 Bash / 27 Ruby / 9 Swift）、
  `verify-release-checkout-isolation.sh`、`verify-release-foundation.sh`、
  `verify-performance-analysis.sh`、`verify-pinned-create-dmg-execution-boundary.sh`、
  `verify-legal-data-flows.sh`、`verify-security-invariants.sh` 与 `git diff --check` 全部 PASS。
  未运行真实网络下载与真实 tag，Swift 源码未改动，未重跑 885 项 XCTest。
- [ ] 可选的更紧边界（keychain 只覆盖 codesign，Build/Notarize/smoke 全部在 keychain 之外）
  需要同时改两份文档与三个门禁，本轮未采用，留待 owner 决定。
- [ ] 本轮未 commit、push、tag、notarize 或发布；本地分支仍比 `origin/codex/v6.60-visual-polish`
  多 4 个未推送提交（`992966a`…`d51ce7c`）。

## 2026-09-02 Vibe Island 方向：先发版、岛内动手、按项目思考

- [x] Owner 授权后，`codex/v6.60-visual-polish` 已 commit 并推送到 PR #19：create-dmg 收口
  （`8d9c9f0`）、启动器阶段诊断（`d585cf8`）、全局决策快捷键（`fb43818`）、roadmap 校准
  （`8f3c2f9`）、夹具 chmod 修复（`eb5a59a`）、项目分支标签（`d1da997`）、今日活动汇总
  （`c7666d7`）与 Welcome 第四步。ROADMAP「当前优化目标」改为 Vibe Island 方向：先发版再打磨、
  只真实验收 Claude Code / Codex / Cursor、冻结五个 Preview 连接器与商业底座。
- [x] PR CI 两次失败均由新 create-dmg 执行边界夹具引起：runner 上 `File.rename` 一个 0500 目录
  返回 EACCES（本地 Darwin 27 允许，runner Darwin 24 拒绝）。启动器 `SystemCallError` 诊断现在
  带阶段标记但不带路径；夹具在原子替换前先 `chmod 0700`，verifier 已返回，证明面不变。
- [x] 全局决策快捷键 `⌃⌥⌘Y` / `⌃⌥⌘N`：Carbon `RegisterEventHotKey`，无需辅助功能授权；只对
  `pendingActionRequests.first` 的 `.permission` 直接 Allow/Deny，问题与 Plan Review 只展开岛；
  成功后发布 `islandGlobalDecisionApplied` 复用岛内回执；Settings › General 默认开启开关；
  契约 v6.87.0。
- [x] TaskCard 显示项目 git 分支：`ProjectBranchReader` 是 App 内唯一打开用户项目文件的路径
  （≤8 层向上、O_NOFOLLOW、当前用户、≤4 KiB `HEAD`），`ProjectBranchCache` 30 秒内存刷新；
  PRIVACY / DATA_FLOW / 契约同步。按项目分组列表因与注意力优先排序契约冲突未采用。
- [x] 今日活动汇总：`TaskStore.todayActivity` / `refreshTodayActivity(now:)`，SQLite 只投影两列
  时间戳；Allow 次数按本地日分桶存偏好、上限 100,000，Clear History 重置；状态菜单与空闲岛各一行，
  只有数字与固定文案；契约 v6.88.0。
- [x] Welcome 第四步「点亮你的岛」：监听器就绪门、按已连接 Agent 分支给出 verbatim 命令与复制按钮、
  `OnboardingLiveSignalState` 前向锁存（会话被 SessionEnd 删除后仍保持）、真实点阵从 idle 交叉淡入
  running/completed；`LocalAgentConfigurationExecutor.run(` 仍精确两处、无 `Task.detached`；契约 v6.89.0。
- [x] 本机补装 ripgrep；Homebrew Ruby 4 一度抢占 PATH 导致商业政策 duplicate-root 夹具误判，已
  unlink，门禁一律用系统 Ruby 2.6。当前源码 **915 tests / 0 failures**；Localization、Legal/Data
  Flow、Performance、Release Foundation、Checkout Isolation、Pinned create-dmg 与 Security 门禁全部 PASS。
- [ ] Owner 决定：合入 PR #19 并切 v0.4.0；Dev Island → Vibe Island 改名（域名、bundle id、Sparkle
  appcast、Homebrew cask、品牌资产）需先定域名与 bundle id 策略。
- [ ] Claude Code 用量洞察未做：Claude Code 本地只写 token 计数，不写服务商额度窗口；按「不把推测值
  包装成官方额度」原则，暂不实现。
- [ ] 快捷键真机按键、分支标签与今日汇总的真实视觉、VoiceOver 及 Welcome 第四步真实命令验收仍待解锁。
