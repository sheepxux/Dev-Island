# Codex-Plan — Dev Island 当前目标与验收计划

> 当前快照：2026-08-29 · 产品版本：v0.3.0 · 主分支基线：`42f8895`
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
- 当前自动化基线：**677 tests，0 failures**；此前同一二进制完整套件连续十轮通过，另有
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
  后检查实际可执行文件的闭合 marker 矩阵，18 个逐标记负向夹具固定全部泄漏/缺失路径；
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
  前执行前置副作用后，改为依赖解析/凭据加载前 descriptor-backed 枚举全部 43 Bash + 15 Ruby，
  以最小环境 stdin-only `bash -n` / `ruby -c` 完整解析；目录/文件 owner、type、mode、nlink、
  execute、size、UTF-8/NUL、mtime/ctime 与 symlink 边界固定；v6.28.0 再纳入 5 个 Swift，
  用 `/usr/bin/swiftc -parse -` 检查冻结 stdin 且不执行顶层副作用，Swift 无 shebang/精确
  env-swift、后置语法和错误 shebang 由夹具固定，负向攻击从 11 类扩展为 13 类
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
- [x] 发布门禁用虚构凭据验证：完整组合通过，缺失凭据、错误 Team ID、错误 Sparkle 公钥长度和非法证书 base64 均失败；无生产密钥进入本地测试
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
- [x] Manus polling stop/restart 晚到 fetch、网络边沿合并与 401 停止的确定性自动化测试
- [x] Manus 并发 Connect、验证中 Disconnect、换 key 晚到 snapshot、运行期 401 与 Keychain 删除失败的 TaskStore 级测试
- [ ] 用真实 Manus 账户完成 v2 公钥、signed test delivery、task_created、task_stopped(finish/ask)、删除和失败清理验收；通过前 Release gate 固定关闭
- [x] 解锁后的真实窗口连续开合夹具与 Animation Hitches 分层验收
- [x] 解锁后的真实审批/问答窗口验收：DEBUG-only Sandbox 通过生产
  `AgentActionRequest` 队列驱动 Codex Allow Once 与 Claude 两题问答；单选、第二题双多选、
  Back 草稿保持、两次 `⌘↩` 前进/提交及 waiting → running 恢复均通过。Debug Universal
  App 改用独立 `.build/app-debug`，不再与生产 bundle graph 共用 scratch
- [ ] 解锁后的真实 sleep/wake、锁屏与网络切换恢复验收
- [ ] VoiceOver 实机朗读顺序与完整键盘流程；当前已证明 AX 结构、点击后 key window、审批
  `⌘↩`、问答第二题多选/返回保持/最终提交，尚未实际开启 VoiceOver
- [x] 解锁后实测 Save Panel 的 Escape 取消、同名覆盖确认后取消、T7 成功写入、只读目录
  失败反馈与零残留；导出文件保持 `0600`、单硬链接且仅含聚合状态
- [ ] VoiceOver 下完成 Save Panel 取消、覆盖确认、成功/错误反馈与键盘流程
- [x] Reduce Motion 代码契约补漏：bar↔panel 不再以短空间动画冒充淡入，收起岛 hover 不扩大
  capsule，复用任务/图标按钮及 Welcome 连接动作不再 press-scale；3 项策略回归与 645 项
  全量测试通过。当前屏幕锁定，因此仍不替代下一项系统开关实机目视验收
- [ ] macOS Reduce Motion / Increase Contrast 实机视觉验收；v6.38.0 已完成产品级 Increase
  Contrast 代码、自动化和 39 组离屏成对视觉回归，但当前显示会话锁定，尚未从系统设置切换后
  观察真实窗口重绘、动画节奏与 VoiceOver
- [x] Settings 打开时真实进程切为 regular activation policy，关闭后回到 accessory；证明
  Dashboard/Settings 场景进入 Dock 且主岛独处时退出 Dock；v6.32.0 再将 16/32/64 ms
  生产重试抽成可注入 scheduler，测试不再 sleep 猜时序，租约回到已应用状态时立即废弃旧回调
- [x] 捕获并修复全量测试首次运行的两类调度型偶发红：Dock policy 13 项回归改为确定性排空，
  50 轮共 650 次通过；Codex process-group fixture 把独立 5 秒调度预算与 production 3 秒
  默认分开，仍强制读取 PID 并验证 descendant 退出，完整进程边界连续 5 轮通过
- [ ] 状态菜单、实际可闻声音、通知投递与 Focus Mode 实机验收；当前只证明试听动作不闪退，
  且系统通知关闭时设置页能给出明确入口
- [ ] 真实 CLI 的审批、问答、失败、中断和配置 reload 验收
- [x] 解锁后完成重复 launch readiness、四场景 CPU/RSS、60 秒 Time Profiler、3 分钟
  Expanded Running ×20 泄漏趋势与真实场景截图；全部样本初末均为 unlocked
- [ ] 当前机 Animation Hitches、30 分钟 RSS 与 Leaks 已完成；补充跨机器基线和 macOS 可用的
  直接能耗/电池证据后，再制定非 idle 场景 Release 阈值
- [ ] 新真实 tag 后运行 `scripts/release/verify-published-release.sh` 验证精确资产、GitHub build provenance + 全部 DMG/ZIP SBOM attestation，再完成旧版到新版的 Sparkle 端到端更新

当前真实环境预检（2026-08-29）：Claude Code `2.1.197` 与 Codex
`0.149.0-alpha.4.3` 均为 verified，但本地 listener 未运行，两个 managed Hook 均为
update-required，Codex activation 为 review-required，结果为 `ready-agents=0/2`；未自动修改
真实 Agent 配置。远端 GitHub 只读审计确认当前 `main` 仍缺
required CI、PR review、conversation resolution、Actions allowlist、SHA pin policy 与
Dependabot security updates 六项控制；未经明确授权未修改远端设置。

## 四、下一批优化顺序

1. 用户解锁并打开 Dev Island 后，在 Settings 更新 Claude/Codex managed Hook；Codex 再于
   `/hooks` 完成人工信任确认，然后重跑 `local-live-readiness`
2. 用真实 Claude/Codex 会话逐项完成 running → waiting → 岛内决策 → resumed/completed，
   同时覆盖拒绝、超时与回原生 Agent 的中立回退
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
