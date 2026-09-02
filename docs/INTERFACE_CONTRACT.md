# IslandCore Interface Contract

> 最后更新: 2026-08-31 | 版本: v6.85.0
> 变更流程: 改 TaskStore 公开 API 前更新此文档,commit 用 `[S][contract]` tag。

---

## 可信代码身份单实例接管（v6.84.0）

- 普通 Finder/LaunchServices 启动必须在创建 IslandWindow、启动本地服务或写入 LaunchHealth 前，
  枚举当前用户会话中同 `Bundle.main.bundleIdentifier` 的 App 进程；除 Bundle ID、PID 与终止状态外，
  只允许 Security.framework 由动态 PID 解析有效代码签名的 identifier、Team ID 或 CDHash。不得读取
  其他进程命令、窗口内容、可执行路径、环境、偏好、IPC 或用户数据，也不得记录代码身份。
- SwiftUI root `Settings` Scene 必须在 gate 前保持 inert。根 `App.body`、Scene builder、AppDelegate
  stored-property initializer 与任何 pre-gate closure 求值都不得构造绑定 `TaskStore.shared` 的
  `SettingsView`，也不得以其他方式触发 TaskStore、SQLite、Keychain、listener、通知或产品窗口。
  Settings 的真实内容只能在当前进程已确定继续作为 owner 后延迟创建；只证明
  `applicationDidFinishLaunching` 回调内部 gate 早于 `IslandWindow()`，不足以证明该边界。
- 当前进程与候选签名 identifier 都必须精确等于自身 Bundle ID。非 ad-hoc 签名必须通过
  `anchor apple generic`、精确 identifier 与证书 OU 要求，双方再以同一非空 Team ID 建立跨版本
  Developer ID 边界；只有 signing flags 明确标记为 ad-hoc 时，才允许用非空且完全相同的 CDHash
  信任同一运行 Mach-O slice 的 byte-identical QA 副本。Team/hash 混合、非 ad-hoc 且无 Team、
  缺失或不一致全部忽略。
  当前自身身份无法证明时 fail open。
- ad-hoc CDHash 是 Security.framework 为当前实际运行的 Mach-O slice 返回的代码身份，不是整个
  Universal executable 的 SHA-256。即使 App tree byte-identical，native arm64 与 Rosetta x86_64
  仍有不同 CDHash，必须互不信任并 fail open；live QA 必须记录进程架构和对应 slice CDHash，不能
  用 Universal executable hash 或另一架构的 CDHash 代替。
- 选择策略必须确定且有界：同 Bundle 候选最多 32 个，超限直接 fail open；可信 live candidate 中
  最低正 PID（最早实例）获胜。只有比当前 PID 更早的可信进程可要求当前实例 yield。选出 winner 后
  必须由同一 PID 再解析一次代码身份，并要求与首次身份逐字一致；进程消失、PID reuse 或身份漂移
  都必须 fail open。
- 当前实例只有在 AppKit 成功激活精确、二次验证后的 winner 后才能退出。当前为最早可信实例、
  winner 消失或激活失败时继续启动，不能让两个实例同时退出，也不能激活不可信的同 Bundle App。
- yield 实例必须在 Island、status item、TaskStore bootstrap、通知、更新器与 launch-health marker
  之前终止；其 `applicationWillTerminate` 不得 shutdown 未启动的共享服务或改写 launch-health。
- `production-launch-smoke` 的精确参数+环境双重 opt-in 必须绕过单实例 gate。这样 CI/维护者可在
  已安装 App 运行时验证冻结 Production artifact，而不会激活、退出或读取用户 App 状态；该绕过
  仍保持 TaskStore、SQLite、Keychain、Hook、Manus、通知、Welcome 与 Sparkle 全部 inert。
- 启动普通 live owner 来验收真实 listener 的测试不具备上述 hermetic 性质。单独设置
  `CFFIXED_USER_HOME` 不隔离当前用户的 login Keychain；普通 `TaskStore.bootstrap()` 仍可能读取
  shipping `manus_api_key` 并启动 Manus 网络生命周期。因此这类 run 必须明确标记为 ordinary-live、
  预先处理真实凭据/网络风险，且不得称为 hermetic 或用来证明 Keychain/网络零访问。
- 本 gate 不授权 IPC、不接收跨进程 payload，也不终止其他进程。未包含 gate 的旧二进制在新版
  已运行后主动启动，仍不能由新版安全强退；本地不同 CDHash 的 ad-hoc 版本也会 fail open。正式
  跨版本唯一 owner 依赖同 Team 的 Developer ID 签名链，不能用 Bundle ID 或产品资源冒充。
- `single-instance-identity-v2-20260831` artifact 因 root Settings Scene 在 gate 前可能构造
  TaskStore-backed SettingsView 的 pre-gate Scene 风险拒绝。其签名、依赖闭包、回调内反汇编和
  进程结果只能保留为诊断材料，不能升级为 v6.84 接受证据，也不能与后续样本合并统计。
- 修复 inert root Scene 后的 `single-instance-identity-v3-20260831` 是当前 authoritative artifact；
  `live-identity-matrix-v6` 在锁屏、arm64、ordinary-live 范围内通过。20/20 个 LaunchServices 副本
  PID 均消失，耗时 min/median/p95/max 为 231/235.5/302/1,155 ms；每轮始终只有一个 App owner
  和一个 `127.0.0.1:7824` listener，owner 的完整观察 socket 集没有其他 INET socket，duplicate
  private home 每轮前后为空。不同 ad-hoc CDHash impostor 的 activation count 保持 `0 → 0`，未被
  激活或终止，真实 App 继续作为唯一 listener owner。该结论只接受同一 arm64 slice 的本地进程级
  仲裁、服务/状态隔离与不同-CDHash 拒绝，不把 ordinary-live run 描述为 hermetic。
- v3 仍不证明同 Team Developer ID 跨版本仲裁，也不覆盖 native arm64 与 Rosetta x86_64 的跨-slice
  互信；后者按契约必须 fail open。显示全程 locked，因此可见 winner 激活、窗口/焦点路由、动效与
  VoiceOver 仍待解锁验收。LaunchServices 启动返回的 PID 可观察消失，但 harness 不拥有可 `wait()`
  的 child process，真实退出码（包括是否为 0）不可观察；不得用 PID 消失或另一次 hermetic smoke
  的 status 0 冒充这 20 轮的退出码证据。

---

## 注意力队列与稳定排序（v3.9.0）

- 跨状态优先级保持 `Waiting > Failed > recent Completed > Running > old Completed`。
- `pendingActionRequests` 的追加顺序是需要人工介入会话的权威队列；同一会话只取
  最早请求的位置，后续排队问题不得让该会话重新跳动。
- 有交互请求的 Waiting 会话排在没有交互请求的 Waiting 会话之前；队列内按请求
  到达顺序，其他 Waiting 与 Running 按创建顺序稳定显示。
- Waiting/Running 的 `updatedAt`、阶段文字或持续时间刷新不得改变行顺序；Failed 与
  Completed 已终止实时进度，仍按状态转换时间展示最新结果。
- 面板级键盘快捷键只属于 `pendingActionRequests` 中最早的未解决请求；解决后下一项
  自然接管。`⌘↩` 执行当前主要动作，`⌘D` 只用于存在拒绝语义的审批/Plan Review，
  `⌘O` 只用于回到 Claude Code 的问题/Plan Review；`Esc` 永远只收起岛，不得作出
  Allow、Deny、Approve、Reject 或 Submit 决策。
- 一个会话存在可处理的 `AgentActionRequest` 时，决策面替代该会话的普通可点击 TaskCard；
  决策面必须保留 Agent、安全的本地 Session 指纹和会话标题。不得同时堆叠两张重复
  会话卡，也不得把决策按钮嵌入跳回会话的 Button。请求解决后恢复普通 TaskCard。
- 展开面板的总数使用 `session/sessions`，不得回退到含义模糊的 `total` 或 task/session
  混用；与收起岛、History 和 VoiceOver 的术语保持一致。
- 这保证 5–20 个并行会话持续更新时，只有优先级变化、新人工请求或请求解决会改变
  列表结构；普通心跳和阶段更新不得导致 reshuffle。
- 同步动作请求默认等待 90 秒，调用方即使传入更长或非有限 timeout，也不得超过
  120 秒；非法非有限创建时间回退当前时间。
- 内存队列全局最多 32 项，同一 `TaskIdentity(source,sessionId)` 最多 4 项。重复 ID、
  过期请求或容量溢出必须立即以 `nil` 恢复调用方，让 Agent 使用原生交互；不得先保存
  continuation，也不得改变已有队列顺序。
- 所有队列内展示文字同时受可见字符和 UTF-8 字节限制。截断必须保留完整 Swift
  `Character`；一个由大量 combining scalar 组成的字素不得绕过字节上限。

---

## 岛内决策面的焦点、键盘与辅助功能（v6.13.0）

- `IslandWindow` 启动和程序化展开时必须保持 non-key，不能因为 Agent 请求自动出现而抢走
  编辑器焦点。只有初始展示完成后、用户直接左键点击真实可见轮廓，窗口才允许成为 key；
  hover、scroll、键盘事件、右键和透明宿主区域都不得触发。收起岛时，若岛自身是 key，
  必须释放键盘交互并退出激活状态；Settings、Welcome 或 DEBUG 窗口为 key 时不得误伤。
- borderless 岛窗口必须暴露稳定 AX 名称 `Dev Island`。该名称只声明辅助技术可识别的窗口
  目的地；不得据此宣称 status-level borderless window 一定出现在标准 Window 菜单。
- 审批、AskUserQuestion 与 Plan Review 仍只有最早未解决请求拥有面板级快捷键。真实窗口
  路由要求先由用户点击岛进入键盘交互，再允许 `⌘↩`、`⌘D`、`⌘O` 到达 SwiftUI 控件；
  自动展开本身不构成用户同意，也不得执行任何决策。
- progressive AskUserQuestion 使用独立的 `QuestionAnswerDraft` 规则：单选替换旧值，多选逐项
  toggle，Back 保留全部草稿；Next 仅在当前题已选择时前进，最后一题只有在每一题均有
  非空答案时才能 Submit。输出必须按问题顺序和可见选项顺序 canonicalize，不能按 Set 的
  非确定顺序发给 Claude Code。
- Reduce Motion 下，决策面只使用短 opacity 过渡，按钮不 scale，问题前进/返回不得使用
  空间移动；任务自动定位与 Settings 回顶必须直接跳转而非动画滚动。Increase Contrast 下，
  决策卡、等待强调线、正文、选项、代码块、边界和主次按钮必须使用明确增强分支。
- Reduce Motion 的约束同时覆盖产品通用交互：岛的 bar↔panel 宽高/圆角不得用“更短动画”
  代替真正的无空间移动，而应无动画切换轮廓并只让内容 opacity 淡入；收起岛 hover 不得扩大
  占位，所有复用 `PressableButtonStyle` 的任务行、图标按钮和 Welcome 连接动作不得 press-scale。
  普通模式继续使用统一的 300ms 无回弹轮廓 morph 与轻微按压反馈。
- AX 树、窗口级 key-equivalent 测试和静态截图只能证明结构、路由与视觉分支，不能替代
  VoiceOver 实际朗读顺序、系统 Reduce Motion / Increase Contrast 开关下的人工验收或
  跨机器可访问性结论。

---

## 产品级 Increase Contrast 角色系统（v6.38.0）

- `InterfaceContrastPolicy` 是自定义深色界面的唯一高对比解释层；它必须同时读取 SwiftUI
  `colorSchemeContrast` 与 `NSWorkspace.accessibilityDisplayShouldIncreaseContrast`，不能再由
  Welcome、Settings、History、岛或决策面各自猜测系统状态、复制灰阶或只增强局部页面。
- 次级正文、三级说明、hairline、展开岛边界和 idle 点阵必须使用统一的 adaptive role。
  标准外观下必需文字在 `#111111` 抬升表面上的对比度不得低于 4.5:1；Increase Contrast
  下每个安静角色都必须比标准态更明亮或更不透明。Running、Waiting、Completed 与 Failed
  的饱和状态色继续表达任务语义，不得仅因高对比设置而全部变成装饰性高亮。
- 展开岛的静态轮廓边界使用 adaptive `islandBorder`；标准态保持 0.5pt 的克制层级，Increase
  Contrast 下至少为 1pt。收起岛继续融入物理 notch，不得因为边界增强产生独立悬浮胶囊。
- `DEV_ISLAND_FORCE_INCREASED_CONTRAST=1` 只允许存在于 `#if DEBUG`，用于离屏标准/高对比
  同状态成对回归；Release 二进制不得包含这个强制入口。DEBUG 快照可以证明像素分支、无裁切
  和几何稳定，不能替代用户从系统设置切换 Increase Contrast 后的真实窗口与 VoiceOver 验收。

---

## macOS 状态菜单实时摘要与隐私边界（v6.31.0）

- 菜单首行、状态按钮 tooltip 与 VoiceOver value 必须来自同一个 `StatusMenuSnapshot`，并由
  同一时刻的 `TaskStore` 任务、本地监听器、Manus 凭据与连接状态计算；不得让三个入口各自
  拼接文案而产生互相矛盾的状态。
- 摘要沿用岛内“需要用户动手优先”的规则：Waiting > Failed > 最近完成 > Running > Idle。
  非空时在优先状态后追加全部任务的总会话数，例如
  `1 session needs attention · 3 sessions total` / `1 个会话需要关注 · 共 3 个会话`；总数
  不能被误解为当前优先状态的数量。
- 状态按钮使用 `withObservationTracking` 响应 `TaskStore` 变化，不得增加永久轮询 timer。
  只有“最近完成”会因时间流逝改变优先级，因此仅为最早完成态到期边沿安排一次可取消刷新；
  新状态到达后必须取消旧回调并重新计算。
- 状态按钮的 AX label 固定为 `Dev Island`，AX value 只包含聚合摘要、本地 Agent 低基数健康
  与 Manus 低基数连接状态，AX help 说明其会打开状态菜单。任务标题、Session ID、路径、
  URL、工具输入和 provider 原始错误不得进入 tooltip、菜单或辅助功能值。
- 打开菜单时仍以当前快照重建信息行和本地化动作；该代码/单测契约不等于 VoiceOver 实际
  朗读、真实菜单视觉、系统语言切换或状态变化时序已完成人工验收。

---

## TaskStore 公开 API

```swift
@MainActor
@Observable
public final class TaskStore {

    // MARK: - Observed state (C 的 View 只读)

    public private(set) var tasks: [AgentTask]
    public private(set) var pendingActionRequests: [AgentActionRequest]
    public private(set) var connectionStatus: ConnectionStatus
    public private(set) var apiKeyStatus: APIKeyStatus
    public private(set) var localHookServiceStatus: LocalHookServiceStatus
    /// SQLite 中最近 200 条只读快照；不得合并回 tasks。
    public private(set) var storedTaskHistory: [AgentTask]
    public private(set) var storedTaskHistoryTotalCount: Int
    public private(set) var storedTaskHistoryStatus: StoredTaskHistoryStatus

    // MARK: - Actions

    /// 验证并保存 API key,启动所有服务。
    /// 若已有 credential，保存 candidate 前必须 join 正在进行的 Disconnect，
    /// 并使用旧 credential 确认旧 tunnel/Webhook ledger 已完整清理；失败时
    /// 保留旧 key 与 cleanup owner。抛出 ManusError.unauthorized 若 candidate 无效。
    public func configureAPIKey(_ key: String) async throws

    /// 清除 API key,停止所有服务,清空 Manus tasks。
    /// 先失效配置代际并 detach 服务，在凭据仍可用时确认远端 Webhook 已删除，
    /// 然后才允许删除 device-only Keychain。远端 cleanup 失败时抛错、保留
    /// credential 与 cleanup owner，并进入可重试的 cleanup-pending degraded 状态；
    /// Keychain 删除失败时也不得声称 key 已移除。
    public func clearAPIKey() async throws

    /// 打开经过策略验证的任务目的地。Manus 只允许与同一 task ID 对应的
    /// `https://manus.im/app/<id>`；本地 Agent 只允许 Finder 打开真实存在的普通目录。
    /// 文件、App/Bundle、远程 file URL、自定义 scheme、跨源或含凭据/端口/query/
    /// fragment 的 URL 均不调用 Launch Services。裸 id 仅在匹配唯一时执行。
    public func openTaskInBrowser(id: String)
    public func openTaskInBrowser(source: String, id: String)
    public func openTask(_ task: AgentTask)

    /// 按全局身份解析任务。
    public func task(with identity: TaskIdentity) -> AgentTask?

    /// 跳回任务所在的会话(v1.4.0 新增,J2 交付；v2.5.0 / v5.9.0 加强)。
    /// 受管本地 Hook 优先激活实际发出事件的终端；若事件来自 tmux，先选择
    /// 原始 window + pane，再激活宿主。无可信上下文时仍做来源 app 级激活；
    /// 解析不出或激活失败时回退到 openTaskInBrowser 的行为
    /// (本地任务 → Finder 打开项目目录,Manus → 浏览器)。
    public func jumpToTask(id: String)
    public func jumpToTask(source: String, id: String)
    public func jumpToTask(_ task: AgentTask)

    /// 通过 Manus API 停止任务。
    public func stopTask(id: String) async throws

    /// 处理一个正在阻塞本地 Agent 的审批或计划审阅。计划批准会自动携带队列中
    /// 保留的完整原始输入；重复点击或超时后调用返回 false。
    @discardableResult
    public func respond(to requestID: UUID, decision: AgentActionDecision) -> Bool

    /// 回答 Claude Code AskUserQuestion；答案必须完整匹配请求中的问题和选项。
    @discardableResult
    public func respond(to requestID: UUID, answers: [AgentQuestionAnswer]) -> Bool

    /// 不替用户作答，立即返回 `{}`，让 Agent 显示自己的原生交互界面。
    @discardableResult
    public func deferActionRequestToAgent(_ requestID: UUID) -> Bool

    /// App 退出时同步 detach ingress/待恢复的 Hook continuation，
    /// 再 await 同一个低基数、single-flight 服务清理结果。
    public func shutdown() async -> TaskStoreShutdownResult

    /// 立即取消当前重试退避并重新启动本机 Agent 监听器。
    public func retryLocalHookService()

    /// 刷新只读历史页面；不得触发 TaskTransition、通知或岛状态变化。
    @discardableResult
    public func refreshStoredTaskHistory() async -> Bool

    /// 原子删除 SQLite 中的任务/进度记录；不移除当前内存中的活跃会话。
    /// 返回 false 表示存储不可用或事务失败。
    @discardableResult
    public func clearStoredTaskHistory() async -> Bool

    // MARK: - Events (v1.4.0 新增,J1 交付)

    /// 任务状态跃迁回调。B 侧(通知投递)在 app 启动时赋值一次。
    /// - 主线程(MainActor)回调,`tasks` 已更新完毕后触发
    /// - 每个状态发生变化的任务触发一次;新出现的任务也触发
    ///   (oldStatus == nil);任务移除不触发
    /// - 同一批快照里多个任务变化 → 逐个回调,顺序不保证
    /// - Debug Sandbox 的 debug 系列 mutator 同样触发,便于 B 测通知
    public var onTaskTransition: ((TaskTransition) -> Void)?
}

/// 一次任务状态跃迁(v1.4.0 新增)。
public struct TaskTransition: Sendable {
    public let task: AgentTask          // 跃迁之后的任务状态
    public let oldStatus: TaskStatus?   // nil = 该任务首次出现
    public let newStatus: TaskStatus    // 与 task.status 相同,便于 switch
}

public struct AgentActionRequest: Identifiable, Hashable, Sendable {
    public static let defaultTimeout: TimeInterval       // 90 seconds
    public static let maximumTimeout: TimeInterval       // 120 seconds
    public static let maximumTitleCharacters: Int        // 256
    public static let maximumTitleBytes: Int             // 1,024
    public static let maximumMessageCharacters: Int      // 1,024
    public static let maximumMessageBytes: Int           // 4,096
    public static let maximumDetailCharacters: Int       // 4,096
    public static let maximumDetailBytes: Int            // 16,384
    public static let maximumQuestions: Int              // 4
    public enum Kind: String, Hashable, Sendable { case permission, question, planReview }
    public let id: UUID
    public let source: String
    public let sessionId: String
    public let kind: Kind
    public let title: String
    public let message: String
    public let detail: String?
    public let questions: [AgentQuestion]
    public let planReview: AgentPlanReview?
    public let createdAt: Date
    public let expiresAt: Date
    public var taskIdentity: TaskIdentity
}

public enum AgentActionDecision: String, Hashable, Sendable {
    case allow, deny
}

public struct AgentQuestion: Identifiable, Hashable, Sendable {
    public static let maximumQuestionCharacters: Int     // 512
    public static let maximumQuestionBytes: Int          // 2,048
    public static let maximumHeaderCharacters: Int       // 64
    public static let maximumHeaderBytes: Int             // 256
    public static let maximumOptions: Int                 // 8
    public let question: String          // Claude answers 对象的 wire key
    public let header: String
    public let options: [AgentQuestionOption]
    public let allowsMultipleSelection: Bool
}

public struct AgentQuestionOption: Identifiable, Hashable, Sendable {
    public static let maximumLabelCharacters: Int        // 128
    public static let maximumLabelBytes: Int             // 512
    public static let maximumDescriptionCharacters: Int  // 512
    public static let maximumDescriptionBytes: Int       // 2,048
    public let label: String
    public let description: String?
}

public struct AgentQuestionAnswer: Hashable, Sendable {
    public let question: String
    public let selectedLabels: [String]
}

public struct AgentQuestionSubmission: Hashable, Sendable {
    public let questions: [AgentQuestion]
    public let answers: [AgentQuestionAnswer]
}

public struct AgentPlanReview: Hashable, Sendable {
    public static let maximumMarkdownCharacters: Int     // 65,536
    public static let maximumMarkdownBytes: Int          // 262,144
    public static let maximumInputBytes: Int              // 262,144
    public let markdown: String
    public let originalInputJSON: Data
}

public enum AgentActionResponse: Hashable, Sendable {
    case permission(AgentActionDecision)
    case question(AgentQuestionSubmission)
    case planReview(AgentActionDecision, AgentPlanReview)
}
```

**B 侧通知建议映射**(契约不强制,B 自行决定打扰度):

| 跃迁 | 建议动作 |
|---|---|
| 任意 → `.waiting` | 通知「需要你的审批/输入」+ `waitingMessage` |
| 任意 → `.failed` | 通知「任务失败」 |
| `.running` → `.completed` | 通知「任务完成」(可选,默认关,减少噪音) |
| 首次出现(oldStatus == nil) | 不通知(避免 app 启动时快照轰炸) |

---

## 数据模型

```swift
public struct AgentTask: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let source: String          // "manus"
    public var title: String
    public var status: TaskStatus
    public var currentPhase: String?
    public let createdAt: Date
    public var updatedAt: Date
    public let taskURL: String
    public var waitingMessage: String?
    public var jumpContext: SessionJumpContext? // 仅活跃会话内存；SQLite 不持久化
    public var identity: TaskIdentity  // (source, id),跨 agent 全局唯一
}

public struct SessionJumpContext: Codable, Hashable, Sendable {
    public let terminalBundleIdentifier: String?
    public let terminalProgram: String?
    public let tty: String?
    public let tmuxSocketPath: String?
    public let tmuxPane: String?
}

public struct TaskIdentity: Hashable, Codable, Sendable {
    public let source: String
    public let id: String
}

public enum TaskStatus: String, Codable, Sendable {
    case running, waiting, completed, failed
}

public enum ConnectionStatus: Equatable, Sendable {
    case connected
    case disconnected
    case reconnecting
    case degraded(reason: String)
}

public enum APIKeyStatus: Equatable, Sendable {
    case notConfigured
    case valid
    case invalid
}

/// 本地 Agent Hook 监听器健康状态；与 Manus connectionStatus 相互独立。
public enum LocalHookServiceStatus: Equatable, Sendable {
    case starting
    case listening
    case retrying(attempt: Int, limit: Int)
    case unavailable
    case stopped
}
```

### Manus 传输错误（v3.2.0 加固）

```swift
public enum ManusError: Error, Sendable {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval)
    case httpError(statusCode: Int, responseBytes: Int)
    case decodingError(underlying: Error)
    case invalidURL
    case invalidResponse
    case networkUnavailable
}
```

- `URLSession` 返回非 `HTTPURLResponse` 时必须失败关闭为 `invalidResponse`，禁止强制转换
  导致 App 崩溃。
- 设置页只把错误映射为固定、可操作的产品文案；不得显示 provider 原始错误、URL、
  路径、响应内容或标识符。
- Unified log 只允许低基数操作名、事件类别、状态码、计数与退避时间；API key、
  Task/Session/Webhook ID、URL、路径、外部进程输出和原始 Error 描述均禁止进入日志。

### Manus 出站信任边界（v4.2.0 加固）

- 正式 App 与真实验收 CLI 共用 `ManusCredentialPolicy`：API key 必须是 16–512 字节的
  可打印 ASCII；不固定 provider prefix，但换行、空白、控制字符和无界输入不得进入 Header。
- v1 task ID 与 v2 webhook ID 只允许 1–256 字节 ASCII 字母/数字/`_`/`-`；路径分隔符、
  dot-segment、percent escape、空白、控制字符与超长输入必须在创建 `URLRequest` 前失败。
- webhook 注册 URL 必须逐字匹配小写 `https://<id>.trycloudflare.com/webhook`，不得携带
  userinfo、非默认端口、query、fragment 或其他 path。
- 生产 `ManusAPIClient` 只能使用无持久 Cookie/缓存的 ephemeral session，request/resource
  timeout 分别为 15/30 秒，并拒绝所有 redirect。HTTP 响应必须保持原请求的 HTTPS
  host 与 effective port；注入测试 session 也不能绕过响应 origin 校验。
- 非有限、负数或过大的 `Retry-After` 不得控制生命周期；单次退避上限固定为 300 秒。
- 以上失败必须发生在响应解析或状态发布之前。请求构造失败不得调用 transport，且 Keychain
  中不再满足策略的旧值启动时标记为 invalid，不得继续启动 Manus 服务。

### Manus realtime 生命周期（v3.3.0 加固）

- `ConnectionStatus.connected` 只表示当前进程的本地 WebhookServer 私有 challenge、
  cloudflared 进程和 Manus webhook 注册同时成功；单独存活的任一层不得作为 realtime
  connected 状态。
- WebhookServer `start` 必须在 2 秒 deadline 内通过随机私有 loopback route 证明 7823
  由当前实例监听，端口冲突不得启动 cloudflared 或远端注册。探针只接受精确
  `Content-Length` 与 challenge bytes，响应最多 256 字节、禁止 redirect/代理/Cookie/
  缓存；不得使用会累计完整响应的 `URLSession.data`。注册前后与 heartbeat 都要重验，
  失效后删除已注册 webhook、停止 tunnel 并降级 polling-only。
- cloudflared 启动后若 URL 获取或 webhook 注册失败，必须立即停止该子进程；首次启动
  失败还要回滚本地 WebhookServer，不得留下未注册的公共 tunnel。
- cloudflared 启动 stderr 必须由独立 reader 持续排空，不依赖主线程/run loop 或取消不敏感
  的 AsyncStream。取得 URL 前最多读取 1 MiB，超量、静默超时、Task 取消、提前 EOF 或非法
  URL 均停止子进程并失败关闭；取得 URL 后继续只排空不保留、不记录，避免长时 pipe 填满
  阻塞 tunnel。只接受完整小写 `https://<safe-label>.trycloudflare.com`，相似后缀、危险 label、
  端口、凭据与其他 scheme 不得进入注册。
- PATH fallback 必须在进程内解析，禁止额外执行 `which`；只接受绝对目录中由 root/当前用户
  拥有、group/other 不可写的 regular executable，并解析到具体目标。停止先发 SIGTERM，固定
  短宽限后对仍运行的子进程发 SIGKILL；不得因外部工具忽略终止而卡住 App 或验收清理。
- wake 恢复必须把失败返回给 `TaskStore`。失败后当前服务代际关闭 WebhookServer、清理
  transport 并进入 `.degraded(reason: ManusRealtimeTrust.pollingOnlyReason)`；一次成功的
  polling 只证明 API 可达，不得把 polling-only 模式提升为 `.connected`。
- heartbeat 发现进程死亡后只在新进程和新 webhook 都成功时恢复 realtime；任一步失败
  只通知一次降级并停止 replacement process，不得靠“进程还活着”掩盖注册缺失。
- heartbeat 必须是 tokenized current/retiring retained operation，而不是可被新代句柄覆盖的裸
  `Task`。start/stop/suspend/wake 在进入后续 transport 生命周期前，必须先 retire 当前 heartbeat、
  cancel 所有 launch 并停止其已附着 process、strict join 全部 retiring heartbeat，然后再快照并
  drain heartbeat 尾部发布的 retained lifecycle callback；callback 恰好在 heartbeat 返回前登记时
  也不能越过 successor promotion 屏障。
- `onRealtimeUnavailable` callback 必须以独立 token 持有到真实结束，并用 TaskLocal 只识别当前
  callback。callback 自己调用 `stop()` 时只排除这个精确 callback，避免 callback ↔ single-flight
  stop 自等待；任一外部 `stop()` 则必须在共享 stop operation 成功或失败后继续 strict join 全部
  retained callbacks，之后才能返回或抛错。新的 start/wake 也不得在 retiring callback 尚未结束时
  提升 replacement transport。
- launch operation 必须在调用 cancellation-unaware 的 `process.start()` **之前**保存具体 process
  ownership。stop/supersession 因而可以立即终止仍阻塞于 URL/readiness/registration 的 process，
  同时保留 launch task 以等待晚到 registration ID 的持久化与补偿删除；不能只依赖
  `activeTransport`，因为 provider 接受前它按契约仍为空。
- Manus 接受注册并返回 ID 后，必须在任何 post-registration readiness / lifecycle 检查前立即
  把该 ID 加入 authoritative recovery envelope 的持久 cleanup ledger；旧 `webhookId` / `webhookIds`
  只做兼容镜像。启动、wake 或 heartbeat replacement 在删除全部遗留 ID 前不得注册新
  callback。多个交错注册都必须保留各自 ID，后到 ID 不得覆盖仍待删除的旧 ID。
- 每次 `webhook.create` 在跨越 provider 网络边界**之前**，必须按
  `set envelope → preferences.synchronize() → decode/readback → compatibility mirrors` 顺序提交单一 versioned
  `webhookRecoveryStateV1` envelope。权威单元同时包含 known ID ledger、unresolved token，以及
  token 对应的 exact callback URL SHA-256、`startedAt` 和空 `discoveredWebhookIDs`；不得持久化完整
  public URL。旧 `webhookId` / `webhookIds` / token / attempt 键仅为兼容镜像，envelope 存在时不得
  参与恢复决策。409 Conflict、429/rate-limit、取消、timeout、transport loss、5xx 与不可解码
  success 都按 outcome unknown 保留；损坏、超限、重复 ID/token 或交叉引用不一致同样 fail closed。
- `GET https://api.manus.ai/v2/webhook.list` 是账号级 recovery inventory，并与 start/stop 共享一个
  retained single-flight。它只为没有 live launch owner、没有已绑定 ID 的 attempt 做归属：listed
  row 必须为 `active`，完整 HTTPS URL 的 SHA-256 必须与持久 digest 精确一致，且 `created_at` 位于
  `startedAt ± 300s`。同一 digest 若对应多个本地 unresolved attempt，则归属有歧义，全部 marker
  保留且删除零项；inactive、窗外、无关 row 也不得删除。唯一 attempt 可以接收多个 exact provider
  matches 并全部清理。provider 未承诺 read-after-create 一致性，因此空 list 不能解除 marker，
  list 失败也必须保留 recovery state。
- 所有 matched IDs 必须先与 attempt binding、known ID ledger 一起按上述 flush/readback 顺序提交到
  同一 envelope，之后才允许第一个 provider delete。若删除失败，`discoveredWebhookIDs` 跨进程保留，
  下次 start/stop 直接重试这些 exact IDs，不再依赖新的 list 归属。只有 2xx + JSON `ok:true`，或
  来自精确官方 origin、`ok:false` 且 `error.code == "not_found"` 的 404，才证明 delete 后置条件；
  每个 ID 成功后原子移除，最后一个 discovered ID 清除时才解除对应 token/attempt。旧版只有 token
  而没有 callback digest 的 marker 无法安全归属，继续 fail closed，绝不做账号级批量删除。
- cleanup 必须先让对应 cloudflared process 不可达，再调用 provider delete；本地 ID 只有在
  provider 返回 2xx 且 JSON 明确 `ok == true`，或上述严格 404 `not_found` 后才可清除。其他
  `ok:false`、缺失/非法确认、transport 或 HTTP 失败都保留 ID 并抛出 `webhookCleanupFailed`，供
  下一次 start/wake/stop 重试。
- stop/suspend 与正在进行的注册允许 actor 重入，但必须使用生命周期代际淘汰旧结果。`stop()`
  先 cancel 已登记 launch、立即停止它在 `process.start()` 前附着的具体 process，并在有界
  `launchCancellationGrace` 内等待 registration operation。若 cancellation-unaware provider call
  仍未结束，stop 必须 fail closed 为 cleanup failure，保留 launch ownership、credential 与持久
  unknown-outcome marker，而不是无界卡住或假装可以释放 credential；若已过期注册随后返回 ID，
  必须先持久化、再停止对应进程并共享同一 per-ID deletion operation 完成补偿删除。cleanup failure
  必须优先于 superseded 结果返回；heartbeat 删除失败不得启动 replacement，并降级 polling-only。
- credential-releasing `stop()` 在首次 suspension 前必须快照 entry-time deletion
  operations 和 deletion-attempt sequence：先让 active/launch process 不可达并 join 入口时删除，
  再在有界 grace 内等待 registrations；已完成的晚到 ID 继续 drain deletion，未完成的 unknown
  outcome 则保留 marker/ownership 并让本次 stop 失败。只有前述步骤闭合后，才对本轮从未真正
  尝试的 persisted sibling IDs 发起删除。一个 joined ID 失败不能把其他 ID 误标为已尝试；一个已在进行的
  deletion 结果未知时，`stop()` 不能提前返回并释放 credential。每个 exact token 只在
  自己的 operation 结束时退役，只有成功才能清除该 ID。不论具体 error 如何
  在并发 join 中传递，credential-releasing stop 必须在 reconciliation 后执行 terminal gate：known
  ID、unresolved token、attempt、launch、deletion 与 listing ownership 全部为空，且 recovery
  envelope 未标记 corrupt，才能成功。任一状态仍存在都必须 fail closed 为可重试 cleanup failure。
- 当前 Release 的 `ManusRealtimeTrust.liveV2AcceptanceComplete` 固定为 `false`，因此公共
  realtime 保持 fail-closed；polling-only 服务仍必须用当前 credential 创建不具备 listener/
  registration 能力的 cleanup-only manager，恢复同一 preferences ledger 并在 Disconnect 或换 key
  时删除遗留 ID。该 owner 只恢复清理能力，不能打开公共数据流。

### Manus 官方 Webhook v2 契约（v3.6.0 加固）

- 注册、枚举、删除、公钥分别固定为 `POST /v2/webhook.create`、`GET /v2/webhook.list`、
  `POST /v2/webhook.delete`、`GET /v2/webhook.publicKey`，origin 为
  `https://api.manus.ai`，鉴权 Header 为 `x-manus-api-key`；不得从偏好或环境覆盖。
- 公钥响应必须声明 `algorithm == "RSA-SHA256"` 并提供可导入且至少 2,048-bit 的 RSA PEM；只在当前
  `ManusAPIClient` 内存中缓存一小时，不落盘，不允许远端配置替换 API origin。
- 每次 tunnel URL 建立后、注册前，WebhookServer 必须先绑定完整外部 HTTPS URL 与当前
  公钥；注册测试请求之前未完成绑定时一律拒绝。
- replay trust generation 必须由 **exact external URL + canonical RSA public-key identity**
  组成。公钥 identity 使用 Security.framework 导入后导出的 canonical RSA bytes 的 SHA-256，
  因此同一密钥的 PKCS#1 与 SubjectPublicKeyInfo PEM 形态属于同一 generation；仅格式变化不得
  清空 live replay IDs。URL 任一字节变化或真实 RSA key 变化才以原 capacity 原子建立新窗口。
  非法 URL / key 必须在提交前失败，旧 authenticator、URL、generation 与 replay window 均保持。
- HTTP 请求认证成功后仍携带当时的私有 generation token；若 actor suspension 期间 trust tuple
  已轮换，`markEventForDelivery` 必须返回 `staleTrustGeneration`、HTTP 401 且零 delivery。旧代
  `event_id` 不得进入或占用新代 replay window；随后由新 tuple 验证的相同 ID 仍是首次 delivery。
- Header 固定为 `X-Webhook-Signature` 与 `X-Webhook-Timestamp`。验签内容固定为
  `{timestamp}.{registered_url}.{sha256_hex(raw_body)}`，使用 RSA PKCS#1 v1.5 + SHA-256。
  时间差大于 300 秒、缺失/非十进制时间戳、非法 Base64、URL/正文不一致均返回 401。
- Payload 固定为 `event_id / event_type / task_detail`；只接受官方登记的
  `task_created`、`task_stopped`。旧猜测 `event / data / task_progress` 必须拒绝。
- `webhook.delete` 的 HTTP 2xx 只表示 RPC 返回；只有可解码 JSON 中 `ok == true` 才确认远端
  callback 已删除。`ok: false`、缺失 `ok`、类型错误或空/非法 JSON 都是 `invalidResponse`，调用方
  必须继续保留 webhook ID 与 credential-backed cleanup 能力。
- 已验签事件按 `event_id` 做有界内存去重。每个 ID 必须保留到该次已认证签名的真实
  `timestamp + 300s` 到期点；同 ID 的更新签名会延长保留期。1,024 个仍有效 ID 占满窗口时，
  新 ID 返回 503 失败关闭，不得 FIFO 驱逐仍可重放的旧 ID；重复 ID 继续幂等返回 200。
- `task_stopped` 只允许 Running/Waiting 向 Waiting/Completed 前进；已有 Completed/Failed 的
  Manus 任务是单调终态，旧 `ask` 或其他重放事件不得把它重新推回注意力队列。
- 官方文档核对不替代真实账号验收。Release gate 只有在 signed test delivery、创建、
  完成、ask、删除和失败清理全部取得可复现证据后才可通过代码评审打开。

### Manus 真实账号验收工具（v4.1.0 加固）

- `IslandCoreCLI` 默认与其他子命令均不得访问 Manus；只有显式
  `manus-live-acceptance` 可以创建临时 Quick Tunnel 和 Webhook。Key 只从
  `readpassphrase(..., RPP_REQUIRE_TTY)` 读取，不接受参数、环境变量、管道或重定向输入。
- timeout 默认为 600 秒，只允许显式设置为 60–1800 秒。CLI 输出只包含固定 checkpoint
  和低基数结果，不得打印 API key、公共 URL、Webhook/Task/Event ID、payload、服务端文案
  或原始 Error。
- 注册请求 in-flight 时由当前 `WebhookServer` 成功验签并解码的首次事件只记录为
  `signed_registration_probe`，不得冒充 `task_created`。`finish/ask` 只有在同一运行先收到
  相同 task 的 `task_created` 才能计入，关联 ID 只保存在进程内且不进入 Snapshot/输出。
- 成功必须同时证明 trust anchor、signed probe、registration accepted、同运行 created、
  stopped(finish)、stopped(ask)、远端 Webhook 删除和两个本地 transport 停止；少一项均不得
  exit 0。
- `SIGINT`、`SIGTERM`、timeout、注册/验收异常都必须进入不继承取消状态的 cleanup task。
  已知 Webhook ID 时尝试删除；注册可能已成功但拿不到 ID，或删除失败时，必须输出固定
  `manual_webhook_review_required` 并失败退出，不能谎报清理完成。
- cloudflared 子进程只继承受控 `PATH`、`TMPDIR` 与可选 `LANG/LC_ALL`；不得继承 HOME、
  API keys、tokens、代理配置或 DYLD 注入变量。
- 以上只是安全的验收工具，不是验收结果。真实账号未授权、未跑完整证据前，
  `ManusRealtimeTrust.liveV2AcceptanceComplete` 继续固定为 `false`。

### Manus polling 生命周期（v3.4.0 加固）

- `PollingFallback` 必须由 actor 隔离任务句柄，不得使用 `nonisolated(unsafe)`；每次
  start/stop 更新生命周期代际并取消旧 Task。
- connector 可能不响应 Swift Task cancellation。fetch 在 stop、restart、断开或换 key
  后晚到时，必须在任何 snapshot、网络状态或授权回调之前校验 polling 代际；旧结果不得
  写入 `TaskStore`、SQLite 或连接状态。
- `TaskStore` 对 polling snapshot、network error/restored、unauthorized 与 realtime event
  再校验 Manus service generation，形成 connector 和 store 两层 stale-callback 防护。
- 连续离线只发送一次 network-error 边沿；恢复只发送一次 restored 边沿并继续 snapshot。
  `401 unauthorized` 必须停止本轮 polling、把 API key 标记为 invalid、连接标记为
  disconnected，并关闭同代 realtime tunnel；不得继续显示旧的 connected 状态。

### Manus 账户配置生命周期（v3.5.0 加固）

- 每次 Connect / Disconnect 都更新独立的 configuration generation。验证请求可忽略
  Task cancellation，但只有最新代际可以保存 Keychain、启动服务或发布账户状态。
- 两个并发 Connect 采用 latest-operation-wins；先发请求晚到时返回取消，不得覆盖后发
  key。Disconnect 在验证期间发生时，晚到验证不得重新写 key 或重启网络。
- `configureAPIKey` 首先 join 已存在的 credential-removal operation；若旧 Disconnect cleanup
  失败，candidate 不得开始拥有配置。candidate 可先完成只读验证，但替换已有 key 前必须使用
  旧 manager / 旧 credential await 所有旧 Webhook 删除；cleanup 失败时不得调用 Keychain save，
  必须保留旧 key、旧 `APIKeyStatus` 与 cleanup-pending 状态。只有 cleanup 成功才可覆盖 credential。
- 每次启动新 key 前必须同步 detach 旧 connector / poller / tunnel、使旧回调失效，并
  await 旧资源清理；旧 key 的晚到 snapshot 不得进入新账户的 live tasks。
- 替换 key 的旧 callback cleanup 成功后，必须先退役旧 tunnel/poller/connectors、清除
  Manus snapshot 并发布 `.disconnected`，再尝试保存 candidate。若 Keychain save 失败，
  candidate 服务不得启动，旧服务也不得 resurrect；必须 read back 持久源：仍有
  credential 时为 `.valid`，无 credential 时为 `.notConfigured`，read-back 也失败时才
  保守保留旧 `APIKeyStatus`。之后 Configure/Disconnect 必须可重试，不得对已退役
  tunnel 二次 stop。
- 即使 realtime gate 关闭，已验证 credential 的 polling-only 生命周期也必须用内部
  `CleanupOnlyWebhookServer` 装配普通 `TunnelManager(client:server:preferences:)`，从 production
  preferences suite 恢复权威 `webhookRecoveryStateV1` envelope；该 server 永远报告 unavailable，manager 不会
  启动 listener、cloudflared 或 registration，只为 Disconnect/换 key 保留删除能力。
- `clearAPIKey()` 是 async throwing、同一时刻单 operation 的边界：先同步 detach、失效旧回调、
  停止 poller、移除 live Manus tasks，再在 credential 仍在 Keychain 时 await tunnel 的完整
  remote cleanup（包括 join late registration）。cleanup 失败时不得调用 Keychain delete；必须
  保留原 `APIKeyStatus`、credential 与 tunnel cleanup owner，并让 `ConnectionStatus` 使用固定
  `Remote callback cleanup pending; retry disconnect` reason。presentation 只把该精确 reason 映射为
  双语 `Remote callback cleanup pending — retry Disconnect`，不得显示其他 provider/raw reason；
  下一次 Disconnect 必须重试。
- 只有 remote cleanup 成功后才允许删除 Keychain。若 device-only Keychain 删除本身失败，网络
  已断开但仍保留之前的 `APIKeyStatus` 并抛错；只有两段都成功才显示 `.notConfigured`。较新的
  Configure generation 永远拥有新 credential，旧的 suspended Disconnect 不得将其删除。
- shipping `TaskStore` 只能使用 live `ManusAPIClient` 与 device-only `KeychainStore`；
  客户端/存储注入边界为 module-internal，仅供 inert `@testable` 生命周期测试，不能成为
  Release 的环境变量、偏好或任意 Keychain namespace 覆盖入口。

### 正常 Quit 的服务清理屏障（v6.85.0）

- `TaskStore.shutdown()` 必须是可 await 的 terminal single-flight 事务，并只返回
  `TaskStoreShutdownResult.completed` / `.cleanupPending` 两种低基数结果。首个调用者
  在首次 suspension 前设置 shutdown generation，取消并中立恢复所有 action-request
  continuations，detach local listener/connector 和 Manus ingress，移除 sleep/wake observers，并发布
  stopped 状态。启动中的 bootstrap 也必须加入同一所有权屏障，不得在 detach 后晚到
  重建 SQLite、listener 或 Manus 服务。
- 完整 shutdown operation 必须被 `TaskStore` 持有并 memoize；并发/后续调用者只 join
  同一 task，调用者 cancellation 不得取消该共享 cleanup。事务按所有权 join 入口时
  in-flight Disconnect removal、sleep suspension、poller、tunnel 与 local listener；同一资源不得
  fire-and-forget 或重复 stop。
- 已登记但尚未进入 cleanup body 的 Disconnect 也必须被 shutdown terminal generation
  supersede 并 join；它不得在 Quit 后开始独立删 Keychain。已入队但未运行的本地
  listener retry/restart task 必须被保留所有权，shutdown 先 join 该 hop、再 stop 具体 server，
  防止 stop 返回后的晚到 restart。
- `PollingFallback.stop()` 必须先推进 generation、cancel 并 await 已持有 poll task，即使
  connector 不响应 cancellation，晚到 snapshot 也必须被拒绝。外部 `LocalHookServer.stop()` 必须
  await readiness 和 serve-loop tasks；callback-owned 内部 stop 只适用下述精确 self-exclusion，
  且后续外部 stop 仍需补齐 strict join。`WebhookServer.stop()` 必须 await serve task。外部 stop
  返回后原 loopback 端口必须可立即重绑，不能依赖进程退出回收。
- start/restart 不得在 cancel 后丢弃旧 task handle。`PollingFallback` 必须用 tokenized
  current operation + retiring operations 持有被替代的 cancellation-unaware polls；
  `LocalHookServer` 必须对 current/retiring serve 与 readiness operations 保持同样所有权。
  外部 stop 必须快照、cancel 并 await **当前与全部已退役 operations**，不能只 join 最新句柄而让
  早先 superseded poll/serve/readiness 在屏障后存活或重占端口。每个 operation 只能由
  自己的 tokenized completion 从 retiring set 移除。
- `LocalHookEventDelivery` 也必须按 source 保留 tokenized current/retiring drain ownership。
  listener stop 先停止接收、清空所有 queued entries，并让每个 queued synchronous action barrier
  以 `false` 中立返回；随后 cancel 且 join 当前和 superseded drains。callback 内部触发 stop 时，
  TaskLocal 只排除拥有该 callback 的精确 drain/server generation，不能把它从 retiring ownership
  中删除。
- 真实 Hummingbird listener 的 callback-owned stop 必须请求 graceful service-group shutdown，
  让当前 HTTP action route 完成并返回 `{}` 后释放端口，不能用直接 task cancellation 撕裂响应。
  这个内部 stop 不是 no-more-side-effects 边界；后续无 TaskLocal 身份的外部 stop（包括生产
  `TaskStore.shutdown()`）仍必须 strict join 被精确排除的 delivery 与 server generation，且重复
  external stop 看到的 current/retiring 集合必须已经归零。
- shutdown 不是 Disconnect，不得删除 device-only Keychain credential。任一 remote callback
  cleanup 失败时返回 `.cleanupPending`，并必须保留 credential 与 authoritative
  `webhookRecoveryStateV1` envelope，供下次启动重试；其他 listener/poller 仍继续停止。
- `AppDelegate.applicationShouldTerminate` 对普通 owner 返回 `.terminateLater`，将上述
  shutdown 与独立两秒 hard timeout 绑定到同一 private token。cleanup completion 与 timeout
  竞争同一 finish-once reply；超时不得等待一个未响应的 task-group child，也不得触发
  credential/ledger 清除。cleanup 返回 pending 或两秒超时都允许 AppKit 退出，只是未完成
  的远端清理保留为下次启动责任。`applicationWillTerminate` 不得再启动第二个 shutdown。
- `yieldedDuplicate`、`performanceQA` 和 `hermeticLaunchSmoke` 三种无产品服务所有权的进程
  必须立即 `.terminateNow`，不得调度 cleanup/timeout/reply，也不得因退出路径构造
  `TaskStore.shared`。

### 本地用量快照（v2.6.0 新增）

```swift
public struct AgentUsageWindow: Equatable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Hashable, Sendable { case primary, secondary }
    public let kind: Kind
    public let usedPercent: Double       // 仅接受 0...100 的有限值
    public let durationMinutes: Int
    public let resetsAt: Date?
}

public struct AgentUsageSnapshot: Equatable, Sendable {
    public enum Provider: String, Codable, Sendable { case codex }
    public let provider: Provider
    public let observedAt: Date
    public let windows: [AgentUsageWindow]
    public func isStale(at: Date, maximumAge: TimeInterval) -> Bool
}

public struct CodexLocalUsageReader: Sendable {
    public init(codexDirectory: URL, maximumTailBytes: Int, maximumCandidateFiles: Int)
    public func latestSnapshot() throws -> AgentUsageSnapshot?
}
```

行为约定：

- Settings 必须默认关闭，只有用户显式打开 **Local Usage Insights** 后才能读取。
- 读取只发生在用户打开或刷新该设置时，不建立后台轮询，也不访问网络或 Keychain。
- Reader 每次最多遍历 8,192 个目录项，过程中只保留按 mtime/path 稳定排序的最近 24 个
  rollout 候选，不得先积累完整文件清单。每个候选必须通过 no-follow descriptor 的普通文件、
  当前用户 owner 与 group/other 不可写校验；使用首次 `fstat` 固定 offset/length 后以 `pread`
  精确读取至多 512 KiB，文件并发增长不得越过该边界。只寻找厂商写入的
  `event_msg/token_count/rate_limits`；解码模型没有任何 prompt/response/path/ID 字段，非用量
  内容不建模、不记录、不返回。遍历超限、文件替换/缩短或读取异常均只让该可选摘要失败关闭。
- 公开模型只允许数值窗口与时间戳，禁止路径、account/session ID、prompt、response、
  credits balance 或凭据穿过该边界。
- 不存在或异常值必须显示 unavailable/stale，不得由任务数或 token 数推算“剩余额度”。
- 该摘要不参与灵动岛注意力排序；当前只支持已在真实本机数据中验证的 Codex 来源。

---

## 商业 License 验证与断开式存储底座（v3.0.0 新增）

这组公开 API 只定义未来商业授权的安全边界，不代表 App 已经开始收费、激活或授予
付费权益。当前 App target 不实例化 `CommercialLicenseVerifier` 或
`CommercialLicenseDocumentStore`，默认 verifier 没有生产 trust anchor，因此商业模式
必须保持关闭。

```swift
public struct TrustedCommercialLicenseKey: Sendable {
    public let id: String
    public init(id: String, rawRepresentation: Data) throws
}

public enum CommercialLicenseTrustError: Error, Equatable, Sendable {
    case invalidKeyIdentifier
    case invalidPublicKey
    case duplicateKeyIdentifier
}

public struct VerifiedCommercialLicense: Equatable, Sendable {
    public let licenseID: UUID
    public let generation: Int64
    public let tier: String
    public let features: [String]
    public let issuedAt: Date
    public let notBefore: Date
    public let expiresAt: Date?
    public let signingKeyID: String
    public func grants(_ feature: String) -> Bool
}

public enum CommercialLicenseEvaluation: Equatable, Sendable {
    case commercialModeDisabled
    case missingDocument
    case valid(VerifiedCommercialLicense)
    case rejected(CommercialLicenseRejection)
}

public struct CommercialLicenseVerifier: Sendable {
    public static let expectedIssuer: String
    public static let expectedProductID: String
    public init()
    public init(trustedKeys: [TrustedCommercialLicenseKey]) throws
    public func evaluate(document: Data?, now: Date = .now)
        -> CommercialLicenseEvaluation
}

public enum CommercialLicenseDocumentStoreError: Error, Equatable, Sendable {
    case invalidDocumentSize
    case storedDocumentTooLarge
    case storedDocumentRejected
    case rollbackRejected
    case conflictingGeneration
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case unexpectedData
}

public struct CommercialLicenseDocumentStore: Sendable {
    public static let maximumDocumentBytes: Int
    public init()

    @discardableResult
    public func importDocument(
        _ document: Data,
        using verifier: CommercialLicenseVerifier,
        now: Date = .now
    ) throws -> CommercialLicenseEvaluation

    public func evaluateStored(
        using verifier: CommercialLicenseVerifier,
        now: Date = .now
    ) throws -> CommercialLicenseEvaluation

    public func delete() throws
}
```

行为约定：

- `CommercialLicenseVerifier()` 没有 trust anchor，必须返回
  `.commercialModeDisabled`；不能从环境变量、偏好、远端或 License 文件注入公钥。
- `importDocument(_:using:now:)` 是唯一公开写入入口。只有 verifier 对同一组原始字节
  返回 `.valid` 才能保存；disabled、missing、rejected、空文档、超限文档以及存储错误
  都不得覆盖上一份有效文档。
- 签名 payload 必须包含严格大于零的 `generation`。相同 `licenseID` 的后继文档只能进入
  更高 generation；相同 generation 只接受完全相同的原始字节；更高 generation 的签名
  `issuedAt` 也不能倒退。旧文档即使已经过期，仍须先完成不授予权益的 authenticated-claims
  比较，不能因为当前失效而丢掉回滚下界。
- store 的 load/authenticate/compare/save 与 `delete()` 在进程内共享一个临界区；当前 App
  只允许一个进程写该 Keychain account。Security.framework 没有 generic-password CAS，未来
  若 helper/CLI 也写入，必须先增加独立的跨进程所有权协议。
- 已存文档若损坏或不能被当前 trust set 认证，导入必须抛出 `.storedDocumentRejected` 且
  保持原字节，不得静默覆盖后绕过 revision 下界。正常 key rotation 必须在旧/新公钥共同
  受信期间先写入新 generation；紧急恢复只能走用户可见的显式 `delete()`/重新激活流程。
- verifier 与 store 共用 32 KiB 文档上限。store 不向调用方暴露 bearer 文档字节；
  `evaluateStored(using:now:)` 只返回语义化 evaluation。
- 默认 Keychain service 为 `app.devisland.Island`、account 为
  `commercial_license_v1`，可访问级别固定为 `WhenUnlockedThisDeviceOnly`，并显式设置
  `synchronizable = false`；shipping API 不开放任意 service/account 覆盖。
- `CommercialLicenseDocumentStore` 通过 module-internal storage backend 隔离平台存储；公开
  initializer 始终装配上述 shipping Keychain adapter。普通 `swift test` 只能注入进程内存
  backend，并仅对 shipping adapter 的纯 query/attribute builder 验证 device-only 与
  non-synchronizing 策略；随机 service/account 仍会访问真实登录 Keychain，不能作为 hermetic
  fixture。任何真实 `SecItem*` 验收都必须是独立、显式、可处置的隔离 macOS 测试账户或 VM
  门禁，不得运行在维护者日常登录会话或普通 PR 测试图中。
- `delete()` 是幂等的显式删除边界；错误只能携带低层状态码，禁止包含 License 字节。
- 在产品所有者确认 Merchant of Record、设备数/离线宽限/退款恢复、MIT 商业关系，且
  完成 production key custody 与 provider sandbox 评审前，App 不得连接此底座。

---

## Provider-neutral 商业激活核心（v4.0.0 新增）

这组 API 只建立 `激活码 → 未可信签名文档 → 离线验签 → Keychain` 的客户端安全
边界。它不包含 URL、支付商、账户、邮箱、设备 ID、生产公钥、激活 UI 或商业政策；
shipping App 仍不得实例化该服务。

```swift
public struct CommercialActivationCode: Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    public static let minimumUTF8Bytes: Int // 16
    public static let maximumUTF8Bytes: Int // 128
    public init(_ value: String) throws
    public func withUnsafeUTF8Bytes<Result>(
        _ body: (UnsafeBufferPointer<UInt8>) throws -> Result
    ) rethrows -> Result
}

public enum CommercialActivationCodeError: Error, Equatable, Sendable {
    case invalidLength
    case invalidCharacters
}

public enum CommercialActivationTransportRejection: Equatable, Sendable {
    case codeRejected
    case rateLimited
    case serviceUnavailable
}

public enum CommercialActivationTransportResponse: Equatable, Sendable {
    case licenseDocument(Data)
    case rejected(CommercialActivationTransportRejection)
}

public protocol CommercialActivationTransport: Sendable {
    func exchange(activationCode: CommercialActivationCode) async throws
        -> CommercialActivationTransportResponse
}

public enum CommercialActivationHTTPSTransportError: Error, Equatable, Sendable {
    case invalidEndpoint
    case unavailable
    case invalidResponse
    case responseTooLarge
}

public struct CommercialActivationHTTPSTransport: CommercialActivationTransport {
    public static let activationPath: String // /v1/activate
    public static let licenseContentType: String
    public static let requestTimeout: TimeInterval // 10 seconds
    // No public initializer or factory until provider approval.
    public func exchange(activationCode: CommercialActivationCode) async throws
        -> CommercialActivationTransportResponse
}

public enum CommercialLicenseActivationFailure: Equatable, Sendable {
    case commercialModeDisabled
    case transportUnavailable
    case licenseRejected
    case secureStorageUnavailable
}

public enum CommercialLicenseActivationOutcome: Equatable, Sendable {
    case activated(VerifiedCommercialLicense)
    case rejected(CommercialActivationTransportRejection)
    case failed(CommercialLicenseActivationFailure)
    case superseded
    case cancelled
}

public actor CommercialLicenseActivationService {
    public init(
        verifier: CommercialLicenseVerifier,
        store: CommercialLicenseDocumentStore,
        transport: any CommercialActivationTransport
    )
    public func activate(code: CommercialActivationCode) async
        -> CommercialLicenseActivationOutcome
    @discardableResult
    public func cancelPendingActivation() -> Bool
}
```

行为约定：

- 激活码按 UTF-8 字节计数，长度必须为 16–128，只允许 ASCII 字母、数字、`-._`；
  backing value 不公开，普通与 debug 描述必须始终脱敏。
- 接受后的字节必须保存在单一专用分配中；`CommercialActivationCode` 的值拷贝只共享
  该分配，不得产生新的 secret-bearing `Data`。最后一个引用释放时必须通过
  `memset_s` 主动清零，transport 仍只能在非逃逸闭包内临时读取字节。
- 该保证只覆盖 `CommercialActivationCode` 自己持有的内部副本，无法清除调用者传入的
  Swift `String`，也不能阻止未来 provider transport 在闭包内主动复制请求体；未来 UI
  必须构造成功后立即清空输入状态，provider-specific 评审必须限制请求体生命周期并禁止
  持久化或记录。
- verifier 无 trust anchor 时必须在调用 transport 前返回
  `.failed(.commercialModeDisabled)`，避免 keyless build 消耗一次性激活码。
- transport 只返回签名文档或 `codeRejected / rateLimited / serviceUnavailable` 三种
  低基数拒绝；具体 endpoint、支付/账户数据、设备绑定和重试策略不属于此契约。
- 同一 service 同时只允许一个 pending operation。新请求使旧请求 `.superseded`；显式
  取消使当前请求 `.cancelled`。即使 transport 不响应取消并晚到，也不得写 Keychain。
- 文档有效期必须在 still-current operation 取得 commit 所有权后，使用当时重新读取的时间
  判断；不得复用网络请求开始前的时间，让长时间在途响应绕过过期边界。用于确定性测试的
  clock 只能通过 module-internal initializer 注入，公开激活 API 不允许调用者覆盖时间。
- 文档只能交给 `CommercialLicenseDocumentStore.importDocument`；验签失败、超限或篡改
  以及签名 generation 回滚/冲突必须归一化为 `.licenseRejected` 并保留旧文档，Keychain 错误归一化为
  `.secureStorageUnavailable`，transport 原始错误不得穿过结果或日志边界。
- App 接入前仍需产品所有者批准 provider、seller、试用/退款、设备/恢复和离线宽限，
  加入 code-reviewed production 公钥，并完成 provider sandbox 与真实 UI 验收。

HTTPS transport 约定（v6.81）：

- 只接受 syntactically public DNS 的 `https://<host>/v1/activate`；端口只能省略或为 443，
  userinfo、其他 path、query、fragment、IP、single-label 和 reserved/local suffix 均拒绝。
- 使用 ephemeral URLSession 与系统 TLS/hostname validation；禁用 proxy、cookie、cache、ambient
  URL credential、connectivity waiting 和 redirect，request/resource timeout 固定 10 秒。
- 激活码只能在 `application/octet-stream` POST body；URL/header 不得出现 code。成功响应必须是
  exact final URL、HTTP 200 和 `application/vnd.devisland.license`。400/401/404、429、5xx 继续
  映射为三种低基数拒绝，其他状态/网络错误不得携带原始细节。
- 200 response 的 declared length 与逐字节 unknown-length stream 必须共享 verifier/store 的
  32 KiB 上限；第 32 KiB+1 字节到达前失败，不得先完整缓冲。caller cancellation 必须取消
  URLSession work 并保持 CancellationError 语义。
- 该类型不 hard-code endpoint，App/AppLib 不得构造。真实 provider DNS/TLS/service、一次性兑换、
  重放/枚举/速率限制、政策、production key 与 UI 验收完成前，商业模式继续关闭。

v6.82 endpoint construction / cancellation 追加约定：

- `CommercialActivationHTTPSTransport` 不得暴露 `public init` 或 `public static func`；当前 endpoint
  initializer 只能是 module-internal，且 `IslandCore` shipping source（定义文件之外）、App、AppLib
  均不得构造。未来 provider 接入必须通过一次单独源码评审添加 no-URL factory，并把唯一 endpoint
  固定在源码；UI、preferences、environment、remote config 或其他 runtime input 不得提供 URL。
- caller cancellation 不得只让外层 Swift Task 返回 `CancellationError`。URLProtocol 攻击夹具必须
  在 response 延迟期间观察其底层 `stopLoading`，证明 URLSession request 已收到取消；actor 的
  late-response commit invalidation 仍是独立的第二层防线，不能被 transport 合作式取消取代。

---

## 商业激活 pre-provider loopback sandbox（v6.75.0）

- `CommercialActivationSandboxTests` 只属于 `IslandCoreTests`；shipping App、`IslandAppLib` 与
  `IslandCore` 生产源码不得包含它的 server、transport、ready route 或 runtime 开关。
- 每次正向闭环使用进程内新生成的 Ed25519 key、合成 License、内存 document backend 与随机
  numeric `127.0.0.1` 端口，通过真实 Hummingbird TCP/HTTP `POST /v1/activate` 驱动生产
  `CommercialLicenseActivationService`、验签与 verify-before-save 逻辑。测试不得访问登录
  Keychain，也不得读取 production trust anchor、provider secret、账号、支付或设备数据。
- 测试 transport 只接受精确 `http://127.0.0.1:<port>/v1/activate`；HTTPS、`localhost`、非
  loopback 地址、userinfo、其他 path、query 与 fragment 均在连接前拒绝。URLSession 必须使用
  ephemeral 配置，禁用 proxy/cookie/cache/redirect，并保持 32 KiB response bound。
- 正向用例必须证明真实 HTTP 请求体只含 bounded activation-code bytes、返回文档通过生产 verifier
  后写入内存 backend；未签名响应必须归一化为 `.licenseRejected` 且零存储。该闭环验证的是
  provider-neutral 客户端 wiring，不验证 TLS、一次性兑换、重放/枚举防护、速率限制、退款/撤销、
  设备限制、恢复、生产 key custody、真实 Keychain 或任何 seller/provider 行为。
- `Package.swift` 对 Hummingbird 的新增直接依赖只服务测试 target。每次 fresh Production build
  仍须复核最终 App 的 Mach-O 依赖闭包与 build-flavor marker，证明 test server/fixture 没有进入
  shipping Bundle；在 provider、商业政策与生产 trust anchor 获批前，商业模式继续关闭。

v6.76 追加失败关闭矩阵：

- endpoint 必须显式包含 `1...65535` 的端口；省略端口或端口 `0` 与其他非精确 endpoint 一样
  在创建 transport 时拒绝。
- 真实 loopback HTTP `400 / 401 / 404` 只映射为 `codeRejected`，`429` 只映射为
  `rateLimited`，`500...599` 只映射为 `serviceUnavailable`；provider response body 不得进入
  outcome、日志或存储。
- `3xx` 即使携带同源 loopback `Location` 也不得跟随；测试必须证明 redirect target 零请求。
  其他未知状态和超过 32 KiB 的 `200` response 均归一化为 `transportUnavailable` 且零存储。
- 这组状态映射仍只是 test-only transport 对 provider-neutral contract 的攻击夹具；它不是未来
  production transport 的实现模板。production transport 必须在读取期间限制 response bytes，
  不能先完整缓冲；真实 provider 接入还必须使用 HTTPS，并完成证书/域名、timeout、重试、一次性
  code 与滥用防护评审。

v6.77 追加真实 HTTP operation ownership 矩阵：

- cancellation 回归不得仅依赖 URLSession 合作式取消。测试 transport 的显式攻击模式必须在
  detached、有 2 秒 request/resource timeout 的任务中继续 loopback 请求，让外层 activation task
  被取消后仍真实收到签名 response；该模式只允许存在于测试 target。
- 显式 `cancelPendingActivation()` 必须在 request 已到达 server、签名 response 确实返回后仍得到
  `.cancelled`，document backend 保持 `.missingDocument`。
- latest-operation-wins 回归必须让旧、新两个 request 与两个签名 response 都真实完成；旧 operation
  固定得到 `.superseded`，只有新 operation 能进入 verify-before-save 并成为唯一存储文档。
- request/response 到达使用 recorder 计数与最长 1 秒 bounded wait 确定，不用任意 sleep 猜测客户端
  时序；server 的合成 response delay 固定受控在 0...2,000 ms。该测试证明 activation actor 的
  commit ownership，不证明未来 provider 的取消协议、退款撤销或跨进程存储仲裁。

v6.78 追加 pre-cancelled zero-ownership 边界：

- 已在进入 `activate` 前取消的 caller 不拥有新的 activation operation。可信配置预检后必须直接
  返回 `.cancelled`，不得先 invalidate/supersede 当前 pending operation，也不得创建 transport task
  或发送请求；避免一个已经失效的 UI/调用方消耗一次性 activation code。
- 受控 transport 回归必须证明 pre-cancelled 调用的 request count 保持不变，原 pending operation
  后续仍能成为 `.activated` 并完成唯一 verify-before-save。
- 真实 loopback 回归必须在原 request 已到达 server 后发起 pre-cancelled 第二调用，最终 recorder
  仍只有 1 个 request / 1 个 response，原签名 response 激活成功。该契约不改变 provider-specific
  timeout/retry/cancellation 协议，也不允许 production transport 使用 detached 请求。

---

## v1 限制

- 岛内双向操作当前对已验证官方返回协议的 Codex / Claude Code
  `PermissionRequest`、Claude Code `AskUserQuestion` 单选/多选，以及 Claude Code
  `ExitPlanMode` Markdown 计划审阅开放
- MCP Elicitation 与自由文本表单仍未开放岛内提交
- 没有附件下载
- 只支持单 Manus 账户
- session id 只在单个 source 内唯一。UI 列表、通知、高亮、跳回必须使用
  `TaskIdentity` / `AgentTask`,不得把裸 `id` 当全局 key
- Manus Webhook create/stop 与所有 snapshot reconcile 必须使用 `TaskIdentity(source,id)`；
  connector snapshot 只接受与声明 source 相同的行，重复复合身份按稳定首见顺序保留
  `updatedAt` 最新值。错误来源、重复行或同 ID 的其他 Agent 不得被注入、删除或改状态
- `openTaskInBrowser` 由 C 调用 `TaskStore.openTask(_:)`,不是通过 AgentConnector；所有入口
  都必须先经过 `TaskDestinationPolicy`，不得直接把 `taskURL` 交给 `NSWorkspace.open`
- 终端型受管 Hook 只增加 bounded host/TTY/tmux headers；Loopback 层重新校验后写入
  `SessionJumpContext`。上下文不会进入 SQLite、日志或诊断。tmux 跳回只执行固定候选中
  解析后的 root/当前用户所有、group/other 不可写普通 executable，不继承 `HOME` 或其他
  无关环境；参数数组不经过 shell。查询 stdout 在运行中持续排空且最多 4 KiB，每个命令
  使用 2 秒 monotonic deadline 和独立进程组，超时、管道超限或异常先 TERM 再 KILL 整组；
  无 tmux 或切换失败时仍退回宿主 App 激活
- 普通非 tmux tab 的精确选择仍未开放：这需要用户明确授权终端 Automation 或
  Accessibility，不应为一次任务点击静默申请

---

## Claude Code 本地连接器(v1.1.0 新增)

`TaskStore` 公开 API 不变。新增 C 侧可用的 IslandCore 公开类型:

```swift
/// hooks 安装器 — SettingsView 的 Claude Code 行直接调用
public enum ClaudeHooksInstaller {
    public static func isInstalled(settingsURL: URL? = nil) -> Bool
    public static func install(settingsURL: URL? = nil, port: Int = defaultPort) throws
    public static func uninstall(settingsURL: URL? = nil) throws
}
```

行为约定:

- `tasks` 里现在会出现 `source == "claude-code"` 的任务(TaskCard 已有 "C" logo 分支)
- claude-code 任务的 `taskURL` 是项目目录的 `file://` URL；只有目标仍是存在的普通目录时
  `openTaskInBrowser` 才会交给 Finder，文件、可启动 Bundle、远程 host 与失效路径均拒绝
- `stopTask` 对 claude-code 任务是 no-op(本地会话无法远程停止)
- `clearAPIKey` 只清 Manus 任务,不影响本地会话
- 本地管线(`LocalHookServer`,127.0.0.1:7824)随 app 启动,与 Manus key 无关
- 监听器每轮最多尝试 5 次；正式退避固定为 5/10/15/20 秒。耗尽后进入
  `unavailable`，系统唤醒调用 `ensureRunning()` 开启新一轮；监听健康时该调用必须幂等，
  不重启端口或重新发布 `starting`

---

## Codex / Cursor 本地连接器(v1.2.0 / v1.3.0 新增)

API 形态与 Claude Code 完全一致,仅安装器与 source 不同:

```swift
public enum CodexHooksInstaller {   // 写 ~/.codex/hooks.json
    public static func isInstalled(hooksURL: URL? = nil) -> Bool
    public static func install(hooksURL: URL? = nil, port: Int = ClaudeHooksInstaller.defaultPort) throws
    public static func uninstall(hooksURL: URL? = nil) throws
}

public enum CursorHooksInstaller {  // 写 ~/.cursor/hooks.json(扁平 entry + 顶层 version: 1)
    public static func isInstalled(hooksURL: URL? = nil) -> Bool
    public static func install(hooksURL: URL? = nil, port: Int = ClaudeHooksInstaller.defaultPort) throws
    public static func uninstall(hooksURL: URL? = nil) throws
}
```

行为约定(在 claude-code 约定基础上):

- `source == "codex"`(TaskCard "Cx" logo)/ `source == "cursor"`(TaskCard "Cu" logo)
- Cursor 只订阅 fire-and-forget 事件,没有 waiting 态;`stop.status == "error"` → failed,`"aborted"` → completed(phase "Aborted")
- Cursor 的会话键是 `conversation_id`(sessionStart/sessionEnd 上的 `session_id` 值相同)
- Codex 与 Claude Code `PermissionRequest` 使用同步 Hook。Dev Island 默认等待 90 秒、绝对
  上限 120 秒，并返回官方
  `hookSpecificOutput.decision.behavior` 的 `allow` / `deny` 结构；超时、取消、睡眠、
  App 退出或会话结束返回 `{}`，保留 Codex 自己的原生审批界面
- 所有岛内同步动作共用全局 32 项、单一 `(source,sessionId)` 4 项队列上限；容量溢出
  立即返回 `{}`，不得保留 continuation。队列内展示文字同时按字符与 UTF-8 字节限长
- Claude Code `PreToolUse` 只用 `AskUserQuestion|ExitPlanMode` matcher 触发，不会拦截
  其他工具调用；岛内完成 1–4 个单选/多选后返回官方 `permissionDecision: allow` 与
  `updatedInput.questions/answers`。`ExitPlanMode` 保留并展示注入的完整 Markdown，批准时
  原样返回完整 `updatedInput`，拒绝时返回 `deny`。非法、重复、不完整、超长或不一致
  内容失败关闭；“Continue in Claude”和超时立即返回 `{}`

---

## 本地会话与历史资源边界(v5.1.0 新增)

- 所有本地 Agent 的标准化事件共用同一入口限界：`sessionId` 与可选 `generationId`
  各最多 256 UTF-8 bytes，必须非空且不含控制字符；可选 `cwd` 必须为绝对路径、不得
  含控制字符且最多 4,096 bytes；phase 最多 256 个完整字符 / 1,024 bytes，message 最多
  1,024 个完整字符 / 4,096 bytes。非法身份必须整项拒绝；展示文字只能在完整 grapheme
  边界截断，不能产生无效 UTF-8。
- 每个本地连接器的实时会话表最多 128 项。容量压力必须先淘汰终态，再淘汰最旧
  Running；Waiting 最后淘汰，且 128 项全为 Waiting 时拒绝最新到达者，保留更早的人工
  阻塞。相同时间戳必须使用稳定 arrival ordinal 和 ID tie-break，确保排序与淘汰可复现；
  淘汰后同步删除 generation bookkeeping。
- 派生标题最多 256 个字符 / 1,024 bytes，派生 task URL 最多 16 KiB。实时会话继续只由
  内存驱动；SQLite 历史不得被恢复进活跃岛。
- SQLite 在打开数据库以及每次任务/进度写入的同一事务中执行确定性修剪：最多保留
  最新 5,000 个任务与 20,000 条进度。任务淘汰必须同步删除对应孤立进度；修剪持久历史
  不得删除或中断当前 Running / Waiting 内存会话。**Clear History** 仍可显式提前删除
  两张历史表。

---

## SQLite 历史行内容信任边界(v5.2.0 新增)

- SQLite 不是可信输入源。所有新任务行在事务写入前再次验证：source 最多 64 bytes 且仅
  小写 ASCII 字母/数字/连字符；task ID 最多 256 bytes、非空且无控制字符；标题最多
  1,024 bytes且非空；phase 最多 1,024 bytes；task URL 最多 16 KiB 且无控制字符；
  waiting message 最多 16 KiB；时间必须为有限值。
- 进度行的 source/ID 使用相同边界，type 最多 256 bytes 且非空，message 最多 16 KiB。
  单项写入超限必须零写入；批量 snapshot 中任一项非法时必须回滚同事务内已经准备的
  合法前缀，不能留下半批历史。
- 打开 current 或迁移后的数据库时，SQLite 必须先以 `typeof` 与
  `length(CAST(... AS BLOB))` 做一次类型/UTF-8 bytes 清理，再执行 5,000/20,000 容量修剪
  与孤立进度清理。正常事件写入只执行 O(1) Swift 字段验证，不得为每个事件重复进行
  全表内容扫描。
- **View History** 查询必须再次在 SQL `WHERE` 层使用同一类型/字节谓词，之后才能让
  SQLite.swift materialize 字符串。这样即使当前进程运行期间数据库被外部修改，超大行也
  不会进入 Swift/UI；`totalCount` 只统计可安全读取的行。读取仍不写数据库或恢复 live 岛。

---

## SQLite 文件生命周期边界(v5.3.0 新增)

- App-owned 最终数据库目录必须为当前有效用户拥有的真实目录，不得是符号链接或其他文件
  类型，并在任何数据库访问前收敛/复验为 `0700`。父级系统目录可以遵循 macOS 自己的
  路径布局；本契约只声明 Dev Island 拥有的最终 `island-app` 目录。
- `tasks.sqlite` 必须为当前有效用户拥有、link count 精确为 1 的普通文件，权限固定
  `0600`。既有符号链接、目录、设备/FIFO/socket、其他用户文件或多硬链接必须在 SQLite
  打开、schema 检查、自动修剪和 **Clear History** 之前失败关闭，不得修改链接目标或 peer。
- SQLite 的 `-wal`、`-shm`、`-journal` sidecar 使用同一普通文件/owner/link-count 边界；
  既有安全文件收敛为 `0600`，任何链接或非普通入口在主库访问前拒绝。
- 当前 SQLite.swift 未暴露 `SQLITE_OPEN_NOFOLLOW`。`SQLiteFileBoundary` 必须用
  `O_DIRECTORY|O_NOFOLLOW` 锚定最终目录，再以目录 descriptor 为根通过 `openat` 打开主库，
  并分别保留目录和主库的 device+inode anchor。SQLite 连接建立后及维护事务后，两条路径的
  identity、owner、类型和 mode 仍须一致，主库 link count 仍须为 1，否则连接不得进入
  `SQLiteStore.db`。
- 既有 sidecar 的检查、打开和权限收敛必须相对目录 anchor 使用 `fstatat/openat/fchmod`，
  禁止在 `lstat` 后通过会跟随替换路径的 `chmod` 操作；目录被替换时不得接触替换目录中的
  同名 sidecar。
- 文件边界错误只能把私有历史标为 unavailable；本地 Hook 监听和实时内存会话仍需继续，
  且日志只能记录低基数存储失败，不得包含路径、owner 或原始系统错误。

---

## SQLite 运行期文件边界(v5.4.0 新增)

- `SQLiteStore` 必须与 `Connection` 同生命周期强持有 prepared directory/database
  descriptors；不得在 `open()` 返回时释放 anchor。
- 每次 history read、task/progress write、retention 与 **Clear History** 均须先复验主路径并
  检查已有 sidecar，SQLite 操作完成后再次复验。写事务的提交前检查失败必须抛错并回滚；
  read 的返回前检查失败不得把已经 materialize 的行交给调用者。
- 运行中出现目录/主库 identity 漂移、链接、非普通 sidecar、错误 owner 或 link count 时，
  该 store 必须关闭 Connection、释放 anchor 并记住 terminal unavailable 状态。后续调用
  继续抛出低基数文件边界错误，不得把 nil connection 误报成空历史或成功清除；App 重启并
  在安全路径重新 open 后才恢复持久化。
- 持久化失败不得移除当前内存会话、停止本地 listener 或中断 Agent；只读历史和清除入口
  必须呈现 unavailable/失败。

---

## Settings 主路径与微交互(v5.5.0 新增)

- Agents 设置页同时出现本地与云端分组时，必须按 **Local Agents → Cloud Agent** 排列；
  readiness 卡片要求更新 Claude Code/Codex 时，对应操作应位于首屏，不得被可选 Manus
  配置挤到折叠线以下。搜索仅命中某一组时仍只显示该组。
- `LocalAgentRegistry` 中全部八个 `settingsSubtitle` 必须在 English 与简体中文 catalog 中
  有审阅文案；简中界面不得回退为英文连接器说明。
- Welcome、审批/问答/Plan 操作、Settings 导航与工具入口使用同一 0.10–0.16 秒低位移
  hover/press 反馈。开启 Reduce Motion 时保留颜色/描边反馈，但不得执行 hover scale。
- 禁用按钮不得显示 pointing-hand cursor；**Quit Dev Island** 保留 `⌘Q`，但因不删除设置、
  历史或凭据，必须作为中性应用命令呈现，不使用破坏性红色。

---

## 声明式连接器框架(v1.5.0 新增,J3 冻结)

> 本地 agent 的唯一事实来源是注册表。B 侧(设置页列表改版)对接以下 API,
> 不再逐家 import 安装器;三个旧安装器 enum 保留为兼容壳,行为不变。

```swift
/// 所有本地 agent 的注册表 — 设置页按此渲染行(顺序即显示顺序)。
public enum LocalAgentRegistry {
    public static let all: [LocalAgentDescriptor]          // 当前含 claudeCode, codex, geminiCLI, qwenCode, copilotCLI, kimiCode, openCode, cursor
    public static func descriptor(for source: String) -> LocalAgentDescriptor?
}

/// 一个本地 agent 的全部元数据(一行表数据)。
public struct LocalAgentDescriptor: Sendable {
    public let source: String            // task.source / logo 资产键(AgentLogo-<source>)
    public let displayName: String       // "Claude Code"
    public let settingsSubtitle: String  // 设置行未启用时的副标题
    public let releaseStage: AgentReleaseStage // stable / preview
    public let hookActivationRequirement: HookActivationRequirement
    public let configPath: String        // "~/.claude/settings.json"(展示用,~ 未展开)
    public let capabilities: AgentCapabilities
    public let actionHookEvents: Set<String>
    public let hookMatchersByEvent: [String: String]
    public let standalonePluginRenderer: (@Sendable (Int) -> Data)?
    public var configURL: URL            // configPath 展开 ~ 后的实际路径
    // 其余字段(hookEvents / hookEntryStyle / appCandidates / decodeEvent)
    // 为核心侧内部驱动用,B 侧无需触碰
}

public enum HookActivationRequirement: Equatable, Sendable {
    case none
    case reviewInAgent(command: String)
    public var reviewCommand: String?
}

public struct AgentCapabilities: Codable, Equatable, Sendable {
    public let lifecycleEvents: Bool
    public let permissionRequests: AgentInteractionSupport
    public let questionRequests: AgentInteractionSupport
    public let planReviews: AgentInteractionSupport
}

/// 通用 hooks 安装器 — 设置页行的 Enable/Disable 直接调用。
public struct LocalHooksInstaller: Sendable {
    public static let defaultPort: Int   // 7824(原 ClaudeHooksInstaller.defaultPort 仍可用)
    public init(_ descriptor: LocalAgentDescriptor)
    public func isInstalled(configURL: URL? = nil) -> Bool
    public func hasManagedEntries(configURL: URL? = nil) -> Bool
    public func install(configURL: URL? = nil, port: Int = Self.defaultPort) throws
    public func uninstall(configURL: URL? = nil) throws
}

/// 跨注册表移除所有 Dev Island Hook。写入前准备全部编辑；中途失败时回滚，
/// 且绝不覆盖操作期间出现的外部配置更改。
public enum LocalAgentHookMaintenance {
    public static func hasManagedHooks() -> Bool
    public static func removeAllManagedHooks() throws -> LocalAgentHookRemovalResult
}

public struct LocalAgentHookRemovalResult: Equatable, Sendable {
    public let removedSources: [String]
    public var removedCount: Int
    public var wasNoOp: Bool
}

/// 只读 Hook 配置健康状态；不包含路径、文件内容或会话数据。
public enum LocalAgentHookConnectionState: String, Equatable, Sendable {
    case connected, configured, updateRequired, disconnected
}

public struct LocalAgentHookConnection: Equatable, Sendable {
    public let source: String
    public let displayName: String
    public let state: LocalAgentHookConnectionState
}

public struct LocalAgentHookHealthSnapshot: Equatable, Sendable {
    public let agents: [LocalAgentHookConnection]
    public var connectedCount: Int
    public var configuredCount: Int
    public var updateRequiredCount: Int
    public var disconnectedCount: Int
}

public enum LocalAgentHookDiagnostics {
    public static func snapshot() -> LocalAgentHookHealthSnapshot
    public static func snapshotResolvingVendorActivation() -> LocalAgentHookHealthSnapshot
}

public enum LocalAgentCLIReadinessState: String, Equatable, Sendable {
    case verified, reviewRequired, checkFailed, unavailable
}

public enum LocalAgentActivationReadinessState: String, Equatable, Sendable {
    case notRequired, verified, reviewRequired
}

public enum LocalHookListenerReadinessState: String, Equatable, Sendable {
    case listening, unavailable
}

public struct LocalLiveReadinessSnapshot: Equatable, Sendable {
    public let listener: LocalHookListenerReadinessState
    public let agents: [LocalAgentLiveReadiness]
    public var readyAgentCount: Int
    public var isReady: Bool
}

public struct LocalLiveReadinessProbe: Sendable {
    public static let verifiedClaudeCodeVersion: String
    public static let verifiedCodexVersion: String
    public func snapshot() async -> LocalLiveReadinessSnapshot
}

public enum HermeticLocalListenerCheckState: String, Equatable, Sendable {
    case verified, unavailable
}

public struct HermeticLocalListenerReadinessHarness: Sendable {
    public init(timeout: TimeInterval = 3)
    public func run() async -> HermeticLocalListenerCheckState
}
```

行为约定:

- **B 侧设置页渲染循环**:`ForEach(LocalAgentRegistry.all, id: \.source)` → 每行用
  `LocalHooksInstaller(descriptor)` 做开关;当前 `SettingsView` 已按此实现,可直接参考
- 核心侧新增 agent 只改注册表,不会破坏 B 侧代码;设置页自动多一行
- 三个旧安装器(`ClaudeHooksInstaller` / `CodexHooksInstaller` / `CursorHooksInstaller`)
  是注册表的薄兼容壳,API 与行为不变,新代码不要再用
- `LocalAgentConnector` 是唯一的本地连接器实现(表驱动);`ClaudeCodeConnector` /
  `CodexConnector` / `CursorConnector` 三个类型已删除(它们从未进入契约)
- Gemini CLI 只订阅五个低频 lifecycle/notification 事件；
  `PermissionRequest` 能力固定为 `.observeOnly`，`actionHookEvents` 为空，B 侧只能展示
  “回 Gemini CLI 处理”的等待状态，不得渲染岛内 Allow/Deny。真实 v0.57.0 验收前
  对外状态为 Preview
- Qwen Code 固定到 `@qwen-code/qwen-code@0.22.0` 与上游 commit
  `e38665674e2978f98cd35e7c6f6eac057741647f`；只订阅七个低频 lifecycle、attention
  与 `PermissionRequest` 事件。其 command Hook 超时单位是毫秒，安装器写 `100000`，
  内层 curl 仍以 95 秒失败中立；Allow/Deny 使用官方结构化 `decision.behavior`。
  真实登录 CLI、Hooks UI/debug 与端到端验收前 `releaseStage == .preview`
- GitHub Copilot CLI 固定到 `@github/copilot@1.0.80`、tag commit
  `ef627e1baad937d3c8da45f8a5541c6fc3c97b6a` 与 GitHub Docs Hook reference
  commit `be8d08aa6e3a95d7f531c6a00cbeff883e4e9814`；使用独立的
  `~/.copilot/hooks/dev-island.json` version-1 文件与六个低频 PascalCase Hook。
  权限/elicitation 只显示固定类别文案；因官方 reference 未公开完整
  `permissionRequest` 输入 schema，能力固定 observe-only，禁止渲染岛内 Allow/Deny。
  真实 v1.0.80 登录会话验收前 `releaseStage == .preview`
- Kimi Code CLI 固定到 `@moonshot-ai/kimi-code@0.38.0`、release commit
  `0999454bdcb5ddd98f39bffee434dcf0a810f394` 与默认 agent-core-v2 引擎；只订阅
  `SessionStart / TurnStarted / PermissionRequest / PermissionResult / Stop / StopFailure /
  Interrupt / SessionEnd` 八类低频 Hook。`PermissionRequest/Result` 均为
  fire-and-forget，能力固定 observe-only，禁止渲染岛内 Allow/Deny；`TurnStarted` 用于
  避免把可阻塞的 `UserPromptSubmit` 放进常规运行路径。配置位置为
  `~/.kimi-code/config.toml`，完整文档在写前/写后用固定 TOML 解析器校验，但不得
  重新序列化；只编辑显式 Dev Island managed block。损坏 TOML、残缺 marker、未包裹
  旧条目或未知受管字段失败关闭。默认 v2 真实登录验收前
  `releaseStage == .preview`；`KIMI_CODE_LEGACY_FLAG` 模式不在本 Preview 契约内
- OpenCode 固定到 OpenCode / `@opencode-ai/plugin` `1.18.23`、commit
  `13c27598d35f6f91fa4763a0b61a220ab7fcb263`；使用完整文件归属的
  `~/.config/opencode/plugins/dev-island.js` 与 `.standaloneJavaScriptPlugin`。
  插件只转发 schema version、七类低频事件、session ID、cwd 和
  `busy/idle/retry` 白名单状态；title、prompt、message、tool args、permission
  metadata 与 raw error 禁止进入 envelope。`retry` 仍为 Running，只有
  `permission.updated` 进入人工注意力。发送不 await、1 秒 abort、错误忽略，App
  离线不得阻塞 Agent。Preview 禁止修改上游 `permission.ask` output，能力固定
  observe-only
- Standalone plugin 安装只允许缺失路径或携带精确 Dev Island marker 的 256 KiB 内
  regular file，最终权限固定 `0600`；未归属冲突、symlink、目录与 device 失败关闭。
  Disconnect All 删除完整受管文件并参与 prepare/compare/rollback；后续失败恢复原字节
  与权限，但外部重建的文件或 dangling symlink 必须保留并报告冲突
- 所有 JSON、TOML 与 standalone plugin 配置写入共用 `ManagedConfigFile` 文件事务边界。
  结构化配置最大 4 MiB；目标必须是当前用户拥有、单链接的 regular file，最终父目录
  必须由当前用户拥有且不可被 group/other 写入。配置目录 symlink 会先解析到具体目录再
  绑定 descriptor，以兼容安全的 dotfiles 布局；dangling/不安全父目录、目标 symlink、
  hard link、目录/device、错误 owner 和超限文件一律失败关闭。只读状态检查可有界跟随
  最终链接来识别遗留 Dev Island marker，但该路径不得被报告为 installed，也不得修改
- 文件读取、提交前复验、临时文件创建与最终 rename 必须绑定同一个 no-follow 父目录
  descriptor。写入先比较最初 snapshot 的 device/inode 与完整字节，再在同目录创建私有
  临时文件、`fsync` 文件并 `fsync` 目录；缺失配置用 `RENAME_EXCL`，已有配置必须用
  `RENAME_SWAP` 将被替换文件保留在私有 staging 名下，验证它仍与最初 snapshot 完全一致后
  才删除。删除必须先原子移动到私有 quarantine、验证 snapshot 后才 unlink；若最终窗口出现
  外部替换，必须无覆盖恢复其原字节，无法安全恢复时保留 quarantine 并失败关闭。缺失配置
  默认 `0600`，已有配置保留原权限。Disconnect All 的提交与回滚使用同一 snapshot，不得在
  compare 与 write 之间回退到无条件路径写入
- 单个与批量卸载都只移除命中本 Agent endpoint marker 的 command；如果用户命令与
  Dev Island command 位于同一个 group，保留用户 handler。包含受管 marker 的损坏
  配置失败关闭并保持原字节，不得静默显示为已断开
- Settings 的 **Disconnect All…** 不影响 Manus；跨文件提交前必须先完成全部解析，
  后续写入失败回滚已写文件。回滚时若文件已被外部修改，必须保留外部内容并要求人工检查
- `LocalAgentHookDiagnostics.snapshot()` 只读注册表中已知配置并区分 current、stale 与 absent；
  不创建/修复文件，不返回路径或内容。Welcome、Settings、Support 与
  `local-hook-status` 使用 `snapshotResolvingVendorActivation()`，但公开结果仍只有四种
  低基数状态，不含路径、命令、Hash 或 Hook 正文
- Codex 的 `hookActivationRequirement == .reviewInAgent(command: "/hooks")`。
  配置文件 current 先映射为 `.configured`；只有只读 Codex App Server `hooks/list`
  探针证明每个精确的 Dev Island source path、event 与 command 均 `enabled == true`，
  且 `trustStatus` 为 `trusted` 或 `managed`，才提升为 `.connected`。不可用、超时、
  schema/解析错误、discovery error、缺失、停用、未信任、已修改或定义不匹配全部保持
  `.configured`
- Codex 信任探针只能执行安装在官方 `com.openai.codex` App 内、Team ID
  `2DC432GLL2` 签名的嵌入式二进制，不搜索 PATH；子进程固定为
  `app-server --stdio`、最小环境、三秒与 2 MiB 上限、stderr 丢弃。原始响应只在内存中
  短暂存在并尽力清零；禁止写配置、修改信任、创建线程或记录输出
- Welcome、Settings、CLI 和 Support 必须使用同一语义；未验证时提示在 Codex
  `/hooks` 审阅或确认，Settings 可显式 **Check again**
- `local-live-readiness` 是显式只读工程验收入口：Claude Code 与 Codex CLI 只有精确
  命中当前真实审阅版本才标记 `verified`，版本漂移只进入 `review-required`，不得据此
  宣称不兼容或自动修改配置。Codex 版本只执行与信任探针相同的 OpenAI 签名 App 内嵌
  二进制；Claude 只解析已知本机安装位置，stdout 4 KiB/2 秒上限、stderr 丢弃、原始
  字节清除。未安装保持 `unavailable`；spawn、timeout、输出超限、非零退出等探测执行
  失败统一进入 `check-failed`，不得误报为版本需要兼容性复核。Settings 使用“暂时无法
  验证，请重新检查”，CLI 只输出 `check-<source>-version-again` 低基数动作
- 外部监听准备度使用 `POST /_dev-island/readiness-v1` + 一次性 UUID challenge；服务端
  拒绝 `Origin`，响应只回显固定前缀与 challenge。它只证明 App 的 loopback Hook 协议
  可达，不替代真实 running → waiting → 决策 → resumed/completed 会话验收
- `local-hermetic-listener-check` 是维护者显式启动的最小 transport 夹具：只在随机空闲
  loopback 端口注入内存随机授权，传入空 Agent descriptor 列表，因此没有任何
  `/hooks/<source>` route，也不读取/轮换生产授权文件、Agent 配置、Keychain、SQLite 或任务。
  只有 listener 自身 readiness、外部 challenge-response 与 stop 后路由消失全部成立才返回
  `verified`；底层 framework 日志被关闭，CLI 只允许固定低基数结果。该结果不能冒充生产 App
  正在监听、managed Hook 已更新、Codex 已信任或真实 Agent 会话已验收

---

## 本地 Agent Loopback 浏览器请求边界(v6.14.0 加固)

- 所有 `/hooks/<source>` POST 必须同时满足：连接命中 numeric `127.0.0.1`、请求不含
  `Origin`，并携带精确 `X-Dev-Island-Hook: v1`。缺失、错误值或 Origin-bearing 请求
  统一返回中立 `{}`，不得解码 body、交付 lifecycle 或调用同步决策闭包。
- 该 Header 不是 same-user 身份认证 Secret；本机同用户进程仍属于既有信任边界。
  它的目的在于把 browser fetch/XHR 从 simple request 提升为必须 CORS preflight 的请求，
  同时让普通 HTML form POST 无法满足路由契约。监听器不得返回
  `Access-Control-Allow-Origin` 或允许该 Header 的 CORS 响应。
- `LocalHooksInstaller` 生成的全部 passive/action curl 命令与 OpenCode 完整插件必须使用
  同一常量。旧 managed command/plugin 因逐字节不匹配显示 update-required；不得为了兼容
  旧 Header-less 定义而在服务端降级接受。
- 真实 HTTP 回归必须覆盖合法 curl/URLSession 往返、携带正确 Header 但含恶意 Origin、
  缺失 Header、错误 Header 以及 OPTIONS preflight 不获授权；拒绝路径的 lifecycle/action
  计数必须保持不变。安装器回归还必须覆盖全部 command-hook descriptor 和 OpenCode
  插件逐字节固定输出。

---

## 本地 Agent Loopback 跨用户授权边界(v6.15.0 加固)

- 固定 `X-Dev-Island-Hook: v1` 只承担浏览器非 simple-request 协议标记；每个 listener
  epoch 还必须用 `SecRandomCopyBytes` 生成新的 256-bit 随机值，并以
  `X-Dev-Island-Authorization: v1.<64 lowercase hex>` 常量时间校验全部
  `/hooks/<source>` POST。缺失、旧值、错误长度/前缀/大小写或不匹配值统一返回 `{}`，
  且不得解码 body、交付 lifecycle 或调用同步动作。
- 随机值只允许写入
  `~/Library/Application Support/island-app/local-hook-authorization.header`。文件必须通过
  descriptor-backed 原子替换边界生成，最终为当前用户所有、单硬链接、regular file、
  `0600` 且不超过 128 bytes；链接、错误 owner/type、超限、父目录可写或并发替换均失败
  关闭。随机源或文件边界失败时 listener 必须保持 `unavailable`，不得退回无授权监听。
- curl managed Hook 只能以 `-H @<private-header-file>` 运行时读取，不得把随机值写入
  Agent 配置或 argv。OpenCode 插件只保存相同相对路径，每次事件通过 Bun Blob slice
  有界读取最多 129 bytes、严格解析单行 Header 后再发请求；文件缺失/异常时静默 fail-open
  到 Agent 原生体验，不得发送无凭据请求。
- 监听重启/自动重试会先轮换文件；旧 listener 仍由 epoch gate 禁止交付，旧凭据不能命中
  新 listener。旧 managed command/plugin 因缺少私有文件读取自动显示 update-required。
- 该凭据隔离同一台 Mac 上的其他 OS 用户，但不声称防御当前登录用户下的恶意进程：后者
  可读取 `0600` 文件，仍处于本地用户信任边界。凭据不得写日志、SQLite、诊断、插件源码、
  Agent 配置、通知或网络目的地。

---

## PR CI 脱敏诊断文件边界(v6.2.0 新增)

- PR/`main` CI 使用 11 个固定顺序且具稳定 ID 的门禁；品牌资产门禁必须进入诊断，失败时
  `firstFailure.id == "brand"`，不得被误报为只有后续步骤 `skipped` 的 `incomplete`。
- Checkout 固定 `persist-credentials: false`。诊断在 `RUNNER_TEMP` 下创建随机 `0700` 父目录，
  只把生成器新建的 `0700` bundle 路径交给 artifact step；bundle 恰有两个 `0600` 文件。
- security/test 原始日志只通过单次 `NOFOLLOW | NONBLOCK` descriptor 读取：必须为当前用户
  所有、单硬链接、group/other 不可写的 regular file；安全日志上限 2 MiB，测试日志上限
  16 MiB。读取以初始 descriptor size 做精确 `pread`，前后复验 device/inode/size/mtime/ctime，
  禁止再按 path `read`/`binread`。
- 缺失、空、symlink、hard link、权限不安全、超限或读取中变化的日志不得使 always-run
  诊断失败；schema v2 以低基数 `sourceStatus` 和 `available: false` 安全降级，仍生成脱敏包。
  原始日志、任意错误/断言正文、环境、Secret 与用户 App 数据不得进入 JSON、Markdown 或
  上传 artifact。
- 失败 artifact 仍只在 `failure()` 上传，Action 固定完整 commit SHA、缺包即失败、保留
  14 天；这份 artifact 是排障证据，不替代远端 required check 和 branch protection。

---

## 本地 Agent 双向 Hook 交付顺序(v6.3.0 加固)

- 同一同步 Hook payload 同时解码出 lifecycle event 与 `AgentActionRequest` 时，
  `LocalHookServer` 必须先 `await` lifecycle 交付与 TaskStore snapshot 提交，再把请求加入
  `pendingActionRequests`。不得恢复为未等待的 MainActor `Task`，否则旧 Waiting snapshot
  可能在用户 Allow/Deny 后晚到并覆盖已恢复的 Running 状态。
- 不产生动作请求的 passive lifecycle Hook 继续保持 fail-open：HTTP `{}` 响应不得等待
  MainActor 或 SQLite，避免 2 秒 curl 预算因历史持久化抖动而耗尽；后台交付前仍需复验
  当前 listener epoch。只有同步决策 payload 才进入上面的严格等待顺序。
- action decoder 返回的 `source` 必须逐字等于当前 descriptor/endpoint source；若同一
  payload 也能解码 lifecycle event，两者的 session ID 必须相同。任一不一致只返回 `{}`，
  不得交付配对 lifecycle、调用决策闭包或把请求排进其他 Agent/会话。
- 用户决策仍只解析一次 continuation；超时、取消、休眠、shutdown、重复 ID、全局/单会话
  容量溢出和会话终止保持中立回退。只有同会话最后一个请求解决后才可乐观恢复 Running。
- 真实 loopback 回归必须覆盖：生命周期 handler 被刻意暂停时 action queue 仍为空；释放后
  Waiting task 先建立；Allow 返回精确 vendor JSON；队列清空且 session 最终为 Running。
  另需用被刻意暂停的 passive handler 证明 HTTP `{}` 不等待持久化，并证明错 source/session
  的 action 连配对 lifecycle 也不会交付。
  该自动化证明本地 HTTP/TaskStore/wire 闭环，不替代真实签名 Agent 与解锁 UI 的人工验收。

---

## 本地 Agent lifecycle 跨请求顺序与容量(v6.4.0 加固)

- passive Hook 不得再为每个 HTTP 请求创建无界 unstructured delivery task；同一 Agent
  source 只允许一个 drain 顺序调用 lifecycle handler，不同 source 使用独立 drain，避免
  一个慢连接器阻塞其他 Agent 的人工请求。
- 同 source、同 session 尚未开始处理的 passive 状态只保留最新事件，并维持该 session
  在跨会话队列中的首次位置。最终 Stop/SessionEnd/Running 等状态因此不会被更旧的排队
  snapshot 回写覆盖；正在处理的事件不被替换。
- 每个 source 最多排队 256 个 lifecycle/barrier 项，外加一个正在处理的事件。容量已满时
  新 passive 事件中立丢弃并使用低基数日志；action barrier 优先淘汰最早 passive 项，若
  队列全部为 action barrier 则本次动作立即返回 `{}`，不得继续占用内存或 continuation。
- actionable payload 的 barrier 必须排在该 source 所有更早 passive 事件之后；只有 paired
  lifecycle（若有）交付完成且 listener epoch 仍有效，才可调用决策闭包。决策返回后仍需
  再验 epoch，旧 listener 不得向 vendor 输出晚到决定。
- 确定性回归必须覆盖：真实 HTTP 的 SessionStart 被暂停时，后到 PermissionRequest 不得
  越过；同 session passive 合并且 handler 最大并发为 1；不同 source 可并行；两项容量下
  passive flood 被限制、最早 passive 让位给 action、全 action 队列中立失败且最终交付
  顺序稳定；listener epoch 失效后排队 lifecycle/action 均不得交付。

---

## 自动更新运行期状态与失败关闭(v6.5.0 加固)

- `AppUpdateConfiguration` 仍是构造 Sparkle 的前置完整信任门；keyless、缺字段、弱化字段、
  非精确 feed 或错误 key 的 App 不得创建 updater runtime，也不得写自动检查偏好。
- 生产 runtime 必须使用 `SPUStandardUpdaterController(startingUpdater: false)`，建立观察后
  显式调用 throwing `SPUUpdater.start()`。不得恢复为 `startingUpdater: true`，否则启动失败
  无法进入 Dev Island 状态机且可能出现延迟的开发者配置 alert。
- 产品状态固定为 `unavailable / starting / ready / checking / failed`，不得携带 raw Error、
  URL、路径、feed body 或下载详情。start 失败时清空 runtime、禁用 Check Now/自动检查开关，
  只显示固定重启建议；错误不写日志、诊断或持久化。
- runtime generation 必须拒绝失败实例已排队的 KVO 回调。`start()` 只执行一次；手动检查在
  调用 Sparkle 前原子切换为 checking 并关闭重复入口，只有 `canCheckForUpdates=true` 才回到
  ready。自动检查偏好只在 runtime 成功启动后才可读写，并以 runtime 返回值为准。
- 回归必须覆盖 keyless 零 runtime、成功启动幂等、手动检查去重、busy→ready、启动失败、
  失败后的晚到 callback、失败状态控件隔离与自动检查偏好同步；菜单/Settings 中英文只使用
  固定低基数状态文案。

---

## 自动更新发布私钥进程边界(v6.6.0 加固)

- tagged Release 不得直接调用 `generate_appcast`。唯一入口是仓库自有
  `run-sparkle-appcast-generator.sh`，且 Sparkle 私钥只能通过
  `--ed-key-file -` 的 stdin 交付；不得进入 argv、文件、日志或生成器环境。
- 包装器读取 GitHub 注入的 `SPARKLE_PRIVATE_ED_KEY` 后，必须先转入新的非导出 shell
  变量，再清除 Sparkle/Apple/P12/临时 Keychain 的全部已知凭据环境变量。不得让第三方
  Sparkle 进程继承未来误加到同一步骤的其他发布凭据。
- 生成器必须由 `env -i` 启动，只允许固定的 `/usr/bin:/bin` PATH 与 `C` locale；不得传递
  `HOME`、GitHub token、runner metadata、签名凭据或任意 workflow 环境。generator 必须是
  非符号链接的普通可执行文件，feed 必须是非符号链接目录，tag 必须通过有界 SemVer 形态校验。
- `env -i` 下的仓库自有 supervisor 必须保留为 generator 的直接父进程并等待其退出，不能
  `exec` 覆盖自身；这样 generator 通过 macOS 直接父进程检查时只能看到清洁 allowlist，不能读到
  最初由 GitHub 注入包装器的私钥环境。supervisor 只通过继承 stdin 转交 key，并转发终止信号。
- 确定性真实子进程夹具必须同时检查生成器自身和父进程环境、完整 argv 与捕获日志，证明
  私钥只按原字节出现在 stdin；缺 key、不安全 tag 与 symlink generator 必须在签名前失败关闭。

---

## 自动更新 Ed25519 密码学闭环（v6.69.0 加固）

- Release 凭证预检不得只接受 32-byte 公钥形态。必须让
  `SPARKLE_PRIVATE_ED_KEY` 经 pinned Sparkle `sign_update --ed-key-file -` 的 stdin-only 通道
  签固定 `VERSION` payload，再由配置的 `SPARKLE_PUBLIC_ED_KEY` 通过 CryptoKit
  `Curve25519.Signing.PublicKey` 验证；错配或不可用私钥必须在证书导入和产物构建前失败关闭。
- 完整资产验证不得信任 workflow 环境中的第二份公钥。必须从 versioned ZIP 的精确
  `Dev Island.app/Contents/Info.plist` 条目有界提取即将交付用户的 `SUPublicEDKey`，并要求其为
  canonical base64 32-byte Ed25519 公钥；缺失、畸形或换成另一把合法公钥均失败。
- `sparkle:edSignature` 必须验证 versioned ZIP 的完整字节；feed 尾部 `edSignature` 必须验证
  `length` 声明的精确 Appcast byte prefix。CryptoKit 输入只允许 owner-owned、单硬链接、不可
  group/other 写的普通文件，通过 `O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC` descriptor 有界读取并比较
  前后 identity/size/time metadata；不得把 Base64 可解码或 64-byte 长度当作密码学成功。
- 确定性 RFC 8032 fixture 必须证明真实公私钥正例，并拒绝 unrelated 64-byte archive/feed
  signature、已签 feed prefix 篡改、App 内公钥错配与 credential 公私钥错配。该闭环证明发布
  资产密码学一致性，仍不替代 Developer ID/公证、GitHub attestation 或旧版到新版安装验收。

---

## 自动更新 disposable old-to-new 真实闭环（v6.70.0 加固）

- PR CI 在依赖解析后、tag Release 在任何凭据加载前，必须离线编译 pinned Sparkle 2.9.6
  checkout 的真实 `sparkle-cli`；不得下载第二份源码、使用未固定 CLI 或读取生产 Sparkle key。
- 一次性 v1/v2 `Dev Island.app`、RFC 8032 测试 key、signed feed/ZIP 只允许进入随机 `0700`
  临时根。HTTP 仅绑定随机 `127.0.0.1:0`，文件名 allowlist、单文件 64 MiB、header 16 KiB；
  updater 使用私有进程 home、无代理环境、90 秒进程组 deadline，超时必须 TERM→KILL。
- 正向链必须真实完成 feed 下载、feed/ZIP Ed25519 验签、解压、App code-sign validity 与原路径
  bundle replacement，并以新 plist version、新 executable marker 和 strict code-sign 复验结果。
- 四条互斥负向链必须保持旧 App version/executable hash/signature 不变：feed 用另一 key、archive
  用另一 key、旧 App 内嵌另一 public key、以及 archive 本身正确签名但其中 App executable 在
  codesign 后被改写。前两类签名归属还必须由 pinned `sign_update --verify` 独立交叉验证。
- pinned Sparkle 源码必须先复制到 macOS 当前用户的随机 `0700` 临时根；只有 SHA-256 与
  `2.9.6 @ ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a` 同时匹配，才允许移除无关远程 package
  引用，并把 cache root、helper launch-job 环境覆盖到一次性 runtime HOME。构建与运行必须使用
  两个不同的私有 HOME、`__CFPREFERENCES_AVOID_DAEMON=1` 和原生 ad-hoc helper 签名；不得读取
  或写入维护者真实 HOME/cache/preferences，也不得调用 `defaults write/delete`。失败清理只允许
  精确匹配当前随机临时根下的 `Autoupdate`/`Updater` 完整命令路径，禁止名称级进程终止。
- Sparkle 在旧 Ed25519 key 已认证 archive 时明确允许 Apple code-sign identity rotation；因此
  本门只证明代码签名有效性/破坏拒绝，不得声称 signer equality。生产完成仍要求同一受控
  Developer ID Team、clean tag、公证/Gatekeeper 与真实已安装旧 Release → 新 Release 验收。

---

## Settings 控件节奏与视觉证据(v6.7.0 精修)

- General、Notifications、Usage 与 Updates 中的原生 switch 必须使用同一全宽双列行：标题与
  副标题固定从左边线开始，switch 固定在卡片右边线；文案长度、语言或换行不得改变控件的
  水平位置。不得恢复为由原生 `Toggle` label 自身宽度决定整行尺寸的布局。
- 可见标题/副标题与 switch 的可访问名称必须保持单一语义：屏幕文字不得被 VoiceOver
  重复读取，switch 仍需提供本地化标题与副标题 hint。截图只能证明静态对齐，不能替代
  VoiceOver 顺序、键盘焦点或真实窗口交互验收。
- Production 更新页版本号只允许来自 App Bundle。DEBUG 离屏截图可以显式注入产品版本，
  避免把 Swift 测试宿主版本误呈现为 Dev Island 版本；该注入不得改变 runtime updater。
- 视觉门禁必须同时覆盖 English 的 General / Notifications / Usage / Updates 与简体中文
  六个 Settings 页面，并在接受前检查当前运行生成的 PNG，不得沿用旧截图作结论。

---

## 本地 CLI 版本探针调度稳定性(v6.8.0 加固)

- 版本准备度必须区分内容结论与执行结论：精确版本为 `verified`；可正常读取但版本漂移或
  输出格式无法解析为 `review-required`；未安装为 `unavailable`；spawn 失败、timeout、
  stdout 超限、非零退出或其他进程边界失败为 `check-failed`。瞬时系统负载不得再向用户
  宣称“版本需要兼容性复核”，所有非 `verified` 状态仍保持 fail-closed
- Production 的 Claude/Codex 版本探针继续保持单次 2 秒、stdout 4 KiB、stderr 丢弃、
  nonblocking drain、monotonic deadline 与进程组 TERM→KILL；不得通过放宽生产边界掩盖
  测试机调度压力。
- 快速退出回归验证的是 `waitpid` 与 stdout 完整读取，不得再把“每个新进程必须在 0.5 秒内
  获得调度”混入同一断言。该回归每个子进程使用 5 秒隔离预算，12 次总耗时仍须小于
  15 秒；挂起和忽略 TERM 的独立测试继续使用 50 ms timeout，保留硬终止证明。
- PR CI 在完整 `swift test` 之后必须使用同一已构建测试二进制重复该回归 20 轮，共启动
  240 个真实子进程。成功时只追加一个低基数 PASS；失败时只输出失败 case/断言，不追加
  第二个 XCTest aggregate count，确保脱敏诊断仍报告权威的 616 项全量总数。
- 稳定性 runner 必须使用私有随机临时目录并在退出时删除逐轮原始日志；不得上传原始
  子进程输出、环境或本机路径。任何一轮失败都必须让既有 `tests` gate 失败，后续命令
  不得把先前完整套件或稳定性失败重新变绿。
- Settings 的 `check-failed` 文案必须引导用户重新检查，英文与简体中文保持相同语义；
  CLI 只能输出 `action=check-<source>-version-again`，不得退回
  `action=review-<source>-version`。

---

## 本地准备度重试语义与视觉层级(v6.9.0 精修)

- `check-failed` 只表示本轮只读检查没有完成，不是用户配置错误，禁止计入
  `%lld setup action(s) remain`。当它是唯一未验证项时，Settings 必须显示独立的
  `Live check incomplete` / `实时检查未完成`，详情只陈述暂时无法验证具体 Agent，
  恢复动作由相邻 `Check again` / `再次检查` 按钮唯一表达，不重复堆叠 CTA 文案。
- retry 状态使用静态 cyan 九宫格 ring 与更弱边框，区别于 amber 设置注意状态和持续旋转的
  checking 状态；不得通过常驻动画制造仍在检查的假象。文字必须承担完整语义，颜色不能是
  唯一提示。
- 同一 snapshot 里若还存在 listener 离线、CLI 缺失、版本复核、Hook 更新/启用或 Codex
  trust 等已知设置阻塞，必须优先计数并显示这个具体动作；瞬时 check failure 不得遮蔽可立即
  修复的真实阻塞。对应 Hook 修改仍会使旧 snapshot 失效，下一次由用户显式重新检查。
- 英文与简体中文必须各有当前源码离屏截图，确认 720 × 520 Settings 视口内标题、详情、按钮、
  点阵和边框不裁切、不漂移。截图不能替代 VoiceOver 顺序、键盘焦点、真实 Reduce Motion 或
  交互验收。
- oversized-output 子进程回归与 fast-exit 回归一样，只证明有界 drain/终止而不考核测试机调度；
  使用 5 秒测试隔离预算和 5.5 秒总上限。Production 默认仍由独立回归锁定为 2 秒。

---

## tmux 后台子进程清理调度稳定性(v6.10.0 加固)

- Production tmux 每条查询/选择命令继续保持 2 秒 monotonic deadline，失败时仍激活宿主终端；
  不得为了让测试在繁忙机器上变绿而延长用户点击路径。该默认值必须有直接单元回归，不能只靠
  CI 文本搜索。
- 后台 descendant 清理回归验证的是：leader 正常退出后，共享 POSIX runner 仍对完整进程组
  发出 KILL，且后台 child 最终消失。它不考核临时 shell 是否在 2 秒内首次获得 CPU，因此使用
  5 秒测试隔离预算和最多 5 秒的 child 消失观察窗。
- tmux 无限输出回归同样只验证 4 KiB drain 上限与有界组终止，使用 5 秒测试预算和 5.5 秒总上限；
  忽略 TERM 的独立硬 deadline 回归继续使用 100 ms，不能被宽化。
- PR CI 在权威全量套件及 240 个 version-probe 子进程之后，必须复用同一测试二进制再执行 tmux
  descendant 清理 20 轮。逐轮日志只存在于随机私有临时目录并在退出时删除；成功只输出一个
  低基数 PASS，失败只输出 case/断言，不追加第二个 XCTest aggregate count。

---

## 解锁性能证据与显示会话判定(v6.11.0 加固)

- Performance sampler 不能只检查 `CGSSessionScreenIsLocked` 是否存在：macOS 在正常未锁定
  会话里可能省略该 key。省略时，只有同一 CoreGraphics current-session dictionary 同时证明
  `kCGSSessionOnConsoleKey=true` 与 `kCGSessionLoginDoneKey=true`，才允许判定为 unlocked；显式
  locked 永远优先，缺字典、非 console 或 login 未完成均为 unknown 并失败关闭。
- 显示会话分类器必须是可独立运行、自带确定性 fixture 的源码组件。locked、显式 unlocked、
  正常 omitted-key、login 未完成和非 console 五类边界均需由 CI 执行，不得只靠文本搜索。
- Sampler 每次运行只编译一次探针，并在 App 启动前、warmup 后、每个一秒 CPU/RSS 样本前和
  最终样本后复核。任一时点 locked/unknown 都必须以 exit 5 使 append-never 证据失败；不能让
  App Nap 或 compositor pause 产生虚假的低 CPU 结论。
- 成功摘要除既有 `screen_locked=false` 外，必须记录
  `screen_state_initial=unlocked` 与 `screen_state_final=unlocked`。显式 smoke override 只能用于
  harness 集成，locked/unknown 摘要不得作为产品或 Release 性能证据。
- 解锁性能验收必须保留隔离 Performance QA App 的哈希、四场景原始 CSV/App log/summary、
  至少一轮展开 20 会话长样本、Time Profiler trace 与真实界面截图。合成分析、锁屏 smoke 或
  单张截图都不能替代这组证据；视觉帧节奏、VoiceOver、Reduce Motion 与长时 30 分钟趋势是
  独立验收门，必须分别由后续证据关闭，不能从本条基线自动推定通过。

---

## 连续开合帧节奏与 Instruments 隔离(v6.12.0 加固)

- 性能夹具必须提供 `transition-running-20`：20 个 Running 会话在一秒稳定后，以 800 ms
  间隔交替展开/收起。每次边沿必须记录 iteration、目标状态与 monotonic uptime；marker 写入只能
  进入独立 utility queue，不能让 `xctrace --target-stdout` 的 deferred 保存反压 UI 主线程。
- 连续开合不能只用 CPU 或静态展开截图验收。必须保留 60 秒 Animation Hitches 原始 trace、
  TOC、App log，以及 hitches/render/update/GPU/frame-lifetime/potential-hang/hang-risk 导出；结论
  必须区分 App update、render、GPU 与 compositor-only 帧，不能把单一颜色或 `potential-hangs`
  行直接解释成产品根因。
- Marker cadence 是独立的主线程调度证据。若 trace narrative 在一段窗口内缺少本应按 uptime
  出现的主队列 marker，而 App log 仍保持有界间隔，该窗口必须登记为 trace/model data gap，
  不能伪装成已定位的业务调用栈；同样也不能因此忽略真实 render/update 长帧。
- Xcode 26 `Power Profiler` 不支持 macOS 目标。macOS 能耗基线必须显式记录该限制，并使用同口径
  Activity Monitor trace 对比 idle 与 expanded-running-20 的 CPU time、稳定期 CPU、physical
  footprint、idle wakeups、App Nap、preventing-sleep 与磁盘写入；这些数据不能改称电池续航结论。
- Leaks/Allocations 只能附加到主 App 带 `com.apple.security.get-task-allow=true` 的隔离
  Performance QA 签名。依赖闭包必须先无调试 entitlement 深签，再只重签外层 App；该 entitlement
  不得进入 Sparkle helper/XPC 或普通生产构建，构建脚本与生产/夹具交叉门禁必须扫描全部 Mach-O。
  泄漏报告必须分别统计 Apple 系统框架责任帧与 Dev Island 责任帧，不得用“总字节很小”宣称
  绝对零泄漏。
- `Package.resolved` 是 App 源码身份的一部分。PR/Release checkout 必须先证明它已被 Git
  跟踪且为普通非链接文件，再允许一致性 resolve；完整测试和两个架构的 App build 均必须使用
  `--only-use-versions-from-resolved-file`，禁止 SwiftPM 在测试或产物边界自动修复锁文件。
  `build-app.sh` 另限制锁文件为 1 byte–1 MiB，并在双架构编译后复核 SHA-256 未漂移；缺失、
  符号链接、空/超限、过期解析或构建中变化全部 fail closed。Performance QA、production app
  与普通开发测试继续使用物理隔离的 SwiftPM scratch。所有测量输出 append-never，并绑定最终
  已签名 executable SHA-256；带空格的 T7 路径是受支持路径，调用分析器时必须完整引用。
- `VERSION` 同时进入 `CFBundleShortVersionString`、`CFBundleVersion`、Cask、归档名、Appcast、
  SBOM 与下载者验证器，因此必须经过唯一共享验证器。文件必须是当前用户拥有的普通非链接、
  单硬链接、不可 group/other 写、1–64 bytes，内容只能是一行带单个结尾换行的 canonical
  `major.minor.patch`；major 最多 4 位，minor/patch 最多 2 位，除零外禁止前导零。缺失不得
  回退旧版本，`v` 前缀、预发布 suffix、多行、空白与 sed/path 字符全部在编译和凭据加载前
  失败。当前 Release 只支持 Apple bundle 两字段共用的数字正式版本；未来 prerelease 必须先
  单独冻结 marketing/build version 与 Sparkle 比较策略，不能把 `-beta` 直接塞入 Info.plist。

## Debug QA 构建与解锁交互证据边界（v6.29.0 加固）

- `build-app.sh` 只接受精确 `CONFIG=debug|release`。普通 Release App、DEBUG-only Sandbox 与
  Performance QA 必须分别使用固定 flavor `app-production`、`app-debug`、
  `app-performance-qa`；默认位于仓库 `.build`，显式外置根必须通过 v6.49.0 scratch 边界。
  三者不得共享 bundle build graph，也不得回退到无 flavor 的普通 `.build`。
  该边界同时避免长生命周期 production → DEBUG 切换进入 SwiftPM 无编译子进程的内部等待。
- Debug Sandbox 只能在 `#if DEBUG` 中存在，但审批、问答和 Plan Review 必须继续经过生产
  `TaskStore.pendingActionRequests`、`AgentActionRequest` 与响应路径，禁止为截图另造旁路 UI。
  真实交互 QA 启动 Debug App 时必须使用 T7 上独立的 `CFFIXED_USER_HOME`，且不得更新真实
  Claude/Codex managed Hook、读取生产历史或把 Debug App 当作可分发构建。
- 解锁验收必须保留真实 AX 状态与合成安全截图，并明确记录交互结果：Codex `⌘↩` Allow Once
  后 waiting → running；Claude 第一题单选、第二题多选、Back 草稿保持、再次前进和 `⌘↩`
  最终提交后 waiting → running。该证据证明窗口与键盘路径，不替代真实 CLI Hook 或 VoiceOver。
- Support 诊断的真实 Save Panel 验收必须覆盖 Escape 取消、同名覆盖确认后取消、成功写入、
  只读目录失败与零残留；成功文件保持 owner-only `0600`、单硬链接、仅聚合内容。Settings
  打开时运行实例必须为 regular activation policy，关闭后恢复 accessory，以证明 Dock 租约闭环。

## 三种 App 构建风味的可执行产物边界（v6.39.0）

- Production、Performance QA 与 Debug 不只隔离 SwiftPM scratch；`build-app.sh` 必须在双架构
  lipo 完成后直接检查最终 `IslandApp` 可执行文件。Production 不得包含任何 Performance 或
  DEBUG-only 标记；Performance QA 必须包含全部三个 Performance 标记且不得包含 DEBUG-only
  标记；Debug 必须包含全部三个 DEBUG-only 标记且不得包含 Performance 标记。
- Performance 固定标记为 `DEV_ISLAND_PERFORMANCE_READY uptime=`、
  `DEV_ISLAND_PERFORMANCE_SCENARIO` 和 `DEV_ISLAND_PERFORMANCE_TRANSITION iteration=`；
  DEBUG-only 固定标记为 `DEV_ISLAND_FORCE_INCREASED_CONTRAST`、`Seed 3 (preview set)` 和
  `Sandbox-injected waiting prompt`。新增 fixture 或 Sandbox 入口必须先更新同一共享矩阵，不能
  依赖 `CONFIG`、Bundle ID、scratch 名称或调用者声明推断真实产物内容。
- `scripts/ci/verify-performance-fixture-isolation.sh` 是唯一共享验证器：单 App 模式验证三种
  flavor，双 App 模式额外绑定 production / Performance QA Bundle ID 与
  `DevIslandPerformanceFixture` plist 标记；`--self-test` 必须覆盖每个标记泄漏或缺失的 21 个
  负向用例。安全静态门禁还必须证明每条 App 构建路径都会调用该验证器。
- 该维护者检查只在本地或 CI 对刚构建的最终可执行文件运行 `/usr/bin/strings`，只查询上述
  固定低基数字面量。原始 strings、源码内容或匹配上下文不得写入日志或证据；它不读取已安装
  App、任务、会话、路径、Keychain、Agent 配置或任何用户数据，也不访问网络。
- 三种本地 QA App 即使全部通过 marker、Universal、依赖闭包与签名检查，也仍分别是
  ad-hoc 验证包；不得把 Performance QA 或 Debug 分发，不得据此宣称 Developer ID、公证、
  Gatekeeper、真实 Agent、VoiceOver 或系统开关验收已经完成。

## 离线法律文件与签名 App 字节绑定（v6.40.0）

- 仓库根目录 `PRIVACY.md` 与 `TERMS.md` 是当前 App 行为对应的唯一工程审阅原文。每份文件
  必须是当前用户拥有、单硬链接、group/other 不可写、1–512 KiB 的普通 UTF-8 文件；中英文
  只能由一个精确分隔符连接，一级标题必须匹配文件类型，双方 `Last updated` / `最后更新`
  日期必须相同，并保留双语 draft/草案披露与两个已审阅联系地址。
- `scripts/release/verify-legal-documents.rb` 必须通过 no-follow descriptor 读取并复验 file
  identity/size/mode/owner/nlink/mtime/ctime。自测覆盖 source symlink、hard link、可写 mode、
  超限、无效 UTF-8、缺失中文、双语日期漂移、重复分隔符、Bundle 字节漂移与额外文件共
  10 个负向用例；错误只报告低基数边界，不回显法律正文。
- `build-app.sh` 在依赖解析前先验证原文，在签名前把两份文件原样安装到
  `Contents/Resources/Legal/`，再要求该目录精确只有 `PRIVACY.md` 与 `TERMS.md` 且逐字节等于
  根目录来源。不得把可能落后于当前数据流的在线页面、构建机绝对路径或重新手写的摘要冒充
  随 App 交付的法律副本。
- Settings 的 **Privacy & Support** 必须在诊断/历史动作之前提供两份离线入口。展示层只从
  `Bundle.main/Legal` 读取，重做 512 KiB/普通文件/非链接/UTF-8/双语结构/标题/日期检查；解析
  失败只显示固定重装提示，不展示路径或原始错误。Markdown 出站链接只允许两个已审阅
  `mailto:` 地址与无 userinfo/port 的 `https://devisland.app`，相对路径、`file:` 与其他 origin
  仅保留可读文字，不得离开 App。
- 当前文档仍明确标注 owner/legal review draft。把它们离线打包证明“当前二进制里能读到哪份
  原文”，不代表律师审阅、网站发布、购买时同意、Seller/Merchant of Record、价格、退款或
  商业政策已经获批；未来 consent、checkout 与 activation UI 必须复用同一版本化入口后才能发布。

## Welcome 最终决策页出口收敛（v6.41.0）

- Welcome 第 1、2 页保留低权重 `Skip tour`，让已理解产品的用户快速退出；第 3 页已经进入
  通知偏好与 **Start Dev Island** 决策，不得再并列提供语义重复的 `Skip tour`。
- 最终页只保留标准窗口关闭、`Back` 与唯一主动作 **Start Dev Island**。关闭继续代表不请求
  通知授权，主动作继续由窗口 owner 在退出动画后请求授权；本轮不改变偏好写入或权限时序。
- `OnboardingNavigationPolicy` 必须对页码与总页数 fail closed，只有合法且非最终页返回
  `showsSkipAction=true`。负页码、单页流程和最终页均不得产生隐藏但仍可被点击/朗读的 Skip。
- Welcome 的 280 ms 无回弹方向过渡保持不变：向前从右侧进入、向后从左侧进入；Reduce Motion
  继续只使用 opacity。本轮静态截图与纯策略测试不冒充真实点击、焦点、VoiceOver 或帧节奏验收。

## App 内法律资源 descriptor 原子读取边界（v6.42.0）

- `Bundle` 只负责解析固定 `Legal/PRIVACY.md` 与 `Legal/TERMS.md` 路径；展示层不得再使用
  `URL.resourceValues` 后另行 `Data(contentsOf:)` 的 check-then-read 路径。每次打开必须通过一次
  `O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK` 获得唯一 descriptor，并只从该
  descriptor 有界读取。
- 首次 `fstat` 必须固定普通文件、单硬链接、1–512 KiB、group/other 不可写且无 set-ID bit。
  读取超过上限的第一个字节即失败；不得依赖预先声明的文件大小分配或映射无界内容。
- 读取结束后必须同时复验 descriptor 和原路径的 `dev/inode/mode/nlink/size/mtime/ctime`，并要求
  实际字节数等于首次固定的大小。任何修改、换 inode、换链接、路径消失或 metadata 漂移都只
  返回既有固定“重新安装已签名版本”提示，不得向界面或日志泄漏路径、errno 或文档片段。
- 定向回归必须覆盖正常单链接文件、symlink、hardlink、group/other 可写 mode、1–512 KiB
  上下界与打开后原子替换；静态安全门禁同时禁止法律展示层重新出现 `Data(contentsOf:)` 或
  `resourceValues(forKeys:)`。这些测试证明本地读取边界，不替代 Developer ID、公证或律师审批。

## PR CI hermetic App 真实启动与正常退出（v6.43.0）

- PR CI 不能再以“Universal 构建 + 静态 Bundle 扫描”代替 App 实际可启动。隔离 Performance QA
  构建完成后必须从最终 `.app` 内的真实 `IslandApp` 可执行文件启动 `idle` 场景，等待首个
  `DEV_ISLAND_PERFORMANCE_READY`，随后连续取得 8 个一秒存活样本；readiness 缺失、提前退出或
  任一样本无法读取都必须让同一 `performance-build` gate 失败。
- 启动必须使用本次私有临时目录作为 `CFFIXED_USER_HOME`。Performance QA 的编译期分支继续
  禁止 SQLite、Keychain、本地 Hook、Manus、通知、Welcome 与更新网络，因此门禁不得读取或
  修改当前用户/runner 的真实 App 偏好、Agent 配置或凭据，也不得读取 `DiagnosticReports`。
- 采样结束不能再由 trap 的 SIGTERM 冒充正常退出。Sampler 必须以精确 PID 构造
  `NSRunningApplication` 并调用 AppKit `terminate()`，最多等待 5 秒，随后要求 child 的真实
  exit status 为 `0`；Bundle ID 广播、杀死同名进程、非零退出或超时都失败关闭。失败路径的
  trap 只负责回收本次 PID，不能把强制清理记为通过。
- Summary 必须绑定原始 launch PID、Bundle ID/版本、可执行 SHA-256、机器/系统、显示会话、
  `isolated_user_home=true`、`normal_termination=true`、`app_exit_status=0` 与 8 项 sample count。
  锁屏/unknown 仅可在 CI smoke 显式 override 下检查进程存活，summary 仍保留真实屏幕状态，
  且不得用于 CPU、内存、帧节奏、能耗、首帧或 Release 性能宣称。
- 所有可能位于外置盘的脚本、App 与证据路径必须作为一个 shell 参数安全传递；尤其分析器必须
  通过 `"$QA_ANALYZER"` 调用，不能把 `/Volumes/T7 Shield/...` 拆成多个 token。静态性能门禁
  必须固定该引用形式；T7 含空格路径下的一次真实 smoke 是本契约的回归证据。
- 这条门禁证明 hermetic 构建的依赖加载、AppKit/SwiftUI 初始面、状态栏、readiness 与正常退出
  路径；它不执行 production TaskStore bootstrap，不替代签名/公证后最终 App、真实 Keychain、
  Agent 链路、解锁视觉、VoiceOver、通知、声音或跨机器性能验收。

---

## Performance 证据文件 descriptor 所有权（v6.44.0）

- CSV、App log 与 summary 必须在 App 启动前作为一个 append-never 集合声明。三条路径必须
  无换行/回车、彼此不同并位于同一当前用户拥有、不可 group/other 写且非 symlink 的最终目录；
  普通预存在文件、目录或 symlink 在创建任何前序文件前拒绝。
- Sampler 固定 `umask 077`，并在单个 Bash `exec` 中对三条 final component 启用
  `noclobber` 后分别打开 descriptor 7/8/9。该 O_EXCL 语义是并发安全边界：两个同时运行的
  claimant 只能有一个取得完整集合，loser 不得截断 winner 或用户既有字节。成功文件必须始终
  为当前用户、普通单硬链接、`0600`。
- 每个 descriptor 打开后立即从 `fstat` 固定 `device:inode` token；路径与仍打开 descriptor
  在 readiness 读取、采样结束、分析前后和 summary 写入后都必须回绑同一 token。路径被 rename、
  替换、改成链接、换 owner/mode/nlink 或超限时，即使 writer 仍持有旧 inode 也必须失败关闭。
- App 的 stdout/stderr 只能写已固定 App-log descriptor；CSV header/行和 summary 只能写各自
  固定 descriptor，不得恢复 `>"$QA_*"` 或 `>>"$QA_*"` 路径重开。CSV 最大 32 MiB、App log
  最大 1 MiB、summary 最大 128 KiB；warmup 与采样时长各自最多 86,400 秒。
- 分析器不能对公共 CSV 路径做多次不相关读取。Sampler 必须以
  `RDONLY|NOFOLLOW|NONBLOCK` 打开第二个 reader，将其 `dev/inode` 与 writer token 绑定，再用
  单次有界 `pread` 生成私有 `0700` sampler 目录内的精确快照；读取前后 descriptor/path 的
  owner/mode/nlink/size/mtime/ctime 必须稳定，只有该快照进入统计分析。
- 自测必须真实覆盖含空格私有目录、任一预存在目标、symlink、两个并发 claimant 只有一个
  winner、reserve 后路径替换连同分析快照拒绝，以及 readiness App log 被 FIFO 替换时的
  nonblocking 拒绝。该文件边界证明证据不会被普通竞态或链接重定向，不证明 App 性能、远端
  CI 已执行或恶意同用户在脚本退出后无法删除用户自己的文件。

---

## Performance readiness App-log 原子读取（v6.45.0）

- Readiness 轮询不得再通过 `awk "$QA_APP_LOG"`、`cat`、`sed`、`head` 或 `tail` 反复打开公共
  App-log 路径。每轮只能以 `RDONLY|NOFOLLOW|NONBLOCK` 打开 reader，将 device/inode 与仍打开的
  App-log writer descriptor 8 绑定，并在 1 MiB 上限内单次 `pread` 到私有 `0700` sampler 目录。
- Reader 必须在读取前后复验 owner/mode/nlink/size/mtime/ctime，并把公共路径重新绑定到同一
  metadata。公共路径被替换为 FIFO、symlink、目录、超限普通文件或另一 inode 时必须立即失败，
  不得先进入阻塞读取或把攻击者字节交给 readiness parser。
- Readiness parser 只读取上述私有快照。允许 marker 尚未出现；一旦出现必须恰好一条
  `DEV_ISLAND_PERFORMANCE_READY uptime=<bounded decimal>`，重复、空值、非十进制或附加内容全部
  失败关闭。marker uptime 必须不早于 launch uptime，且差值不得超过 5.5 秒；负数、非有限值、
  反向时间与超窗值不得写入 summary。
- 静态性能门禁必须拒绝恢复任何针对公共 App-log 路径的文本解析，并固定私有快照、严格 marker
  parser 与 launch-window 计算。确定性 fixture 同时覆盖有效 marker、malformed、duplicate、
  反向/超窗时间和 FIFO 替换；真实锁屏 smoke 仍只证明 harness 整合，不构成性能或视觉结论。

---

## Performance 输入 App 私有快照与执行身份（v6.46.0）

- Sampler 不得在校验公开 Performance QA App 后再从该可替换路径启动。所选 App 只作为输入：
  其主 executable 与 `Info.plist` 必须通过 descriptor-backed
  `RDONLY|NOFOLLOW|NONBLOCK` 有界读取，要求当前用户 owner、单硬链接、不可 group/other 写，
  executable 为 1–256 MiB 且可执行，plist 为 1 Byte–1 MiB；每个 SHA-256 读取前后都必须复验
  dev/inode/mode/nlink/size/mtime/ctime 以及公共路径回绑。
- 复制前必须通过所选 App 的 strict deep 签名；随后只能用 `ditto` 将 Bundle 冻结到随机私有
  `0700` sampler root。复制后必须再次取得所选 executable/plist 的稳定哈希，要求复制前后源
  哈希不变并与私有副本逐字节哈希相等；所选 App 和私有副本还须各自通过 strict deep 签名。
- 真正进入 Bundle metadata 读取、6-Mach-O 依赖闭包、Performance marker 验证与进程 launch 的
  只能是私有 App。`QA_SELECTED_BINARY` 公共路径禁止出现在 launch command；私有 executable/plist
  必须在启动前和 App 正常退出后重新绑定初始哈希与安全 metadata，防止 sampler 自己的临时输入
  在采样期间漂移。
- 所选公开 App 也必须在启动前与正常退出后重新绑定复制时固定的 executable/plist 哈希并再次
  通过 strict deep 签名。它在运行中被替换、修改或失去签名时，本次采样即使私有副本正常退出也
  必须失败关闭，summary 保持空；不能让 summary 描述一个已不再对应本轮选择输入的 Bundle。
- 成功 summary 同时记录私有 `executable_sha256`、来源 `selected_executable_sha256` 与
  `isolated_app_snapshot=true`；两个哈希必须为相同的 64 位小写十六进制。PR CI 的 8 样本 smoke
  必须执行这些运行时断言。7 类确定性 fixture 覆盖普通输入字节变化以及 symlink/FIFO 拒绝；
  单独的真实替换攻击必须证明来源 `Info.plist` 被原子替换后 exit 3 且不发布 summary。
- 该边界证明被启动的 Performance QA executable/plist 与被审计、被摘要绑定的私有副本一致，
  不把公开 QA 路径变成不可变存储，也不证明锁屏 CPU/RSS、首帧、动效、VoiceOver、Developer ID、
  公证或生产 App 的真实体验。

---

## PR CI Performance summary 进程内交付（v6.47.0）

- Sampler 成功时的 stdout 必须只包含同一份已写入 descriptor 9 并完成最终 metadata 回绑的
  `QA_SUMMARY_CONTENT`；被测 App 的 stdout/stderr 固定进入 descriptor 8，且 App launch 时关闭
  descriptor 7/9，不能向 workflow 的 stdout 或 summary writer 注入字节。Summary 继续受
  128 KiB 上限约束。
- PR CI 必须在启用 `set -euo pipefail` 的同一个 Bash `run` step 中，以带引号 command
  substitution 将 sampler stdout 一次性捕获到 `performance_summary`。Sampler 非零退出必须使
  assignment 和 step 直接失败；不能用 `|| true`、管道尾命令或后置文件读取抹掉 producer 状态。
- `isolated_user_home`、`isolated_app_snapshot`、正常退出、status 0、8 samples 以及来源/私有
  executable SHA-256 相等断言只能读取该 shell 变量。Sampler 退出后，workflow 禁止再对
  `${RUNNER_TEMP}/dev-island-launch-smoke.summary.txt` 使用 `grep`、`sed`、`awk`、`cat`、`head`
  或 `tail`；公开路径即使被残留 QA descendant 替换，也不能改变已捕获的 acceptance input。
- 公开 CSV/App log/summary 仍只用于 runner-temporary 调试并且不进入失败诊断 artifact；进程内
  summary 变量随 step 结束消失，不写 GitHub output、environment、cache 或 artifact。它只包含
  已有低基数 fixture/机器/聚合指标，不新增用户数据流。
- 静态性能门禁必须固定 command substitution 与 here-string 消费方式，拒绝 public-summary
  post-exit reopen；确定性 fixture 同时放置失败内容的可替换 public summary，再证明所有成功
  断言和哈希只来自不可受其替换影响的 producer output。该边界不证明远端 GitHub workflow
  已执行，也不解决当前 `main` 未强制 CI/review 的仓库设置阻塞项。

---

## 本地 listener 无副作用 transport 夹具（v6.48.0）

- `local-hermetic-listener-check` 只使用随机 loopback 端口、进程内 256-bit 随机授权和空 Agent
  descriptor 集合；不得创建生产 Header 文件，也不得暴露任何 `/hooks/<source>` route。
- 成功必须同时证明 listener 启动、外部 challenge-response 和 stop 后路由不可达。底层
  Hummingbird 日志保持关闭；CLI 固定五行低基数 stdout、零 stderr。权威入口连续运行十轮，
  但该夹具不替代正在运行的 App、managed Hook、Codex `/hooks` 信任或真实会话验收。

---

## App SwiftPM 外置 scratch 边界（v6.49.0）

- `DEV_ISLAND_SWIFT_SCRATCH_ROOT` 只改变 App 的 SwiftPM build graph 根；最终子目录仍由构建
  脚本固定为 `app-production`、`app-debug` 或 `app-performance-qa`。未设置时继续使用仓库
  `.build/<flavor>`，CI/tag 行为不变。
- 最终 scratch 在任何 `swift build` 前必须经过 `app-build-output-boundary.rb prepare-scratch`。
  已有目录必须为当前用户拥有、非链接、不可 group/other 写的真实目录；新目录只能在一个已存在
  且同样安全的直接父目录下以 `0700` 创建。仓库内只允许 `.build/<flavor-or-child>`，并拒绝
  仓库根/祖先、`.build` 根、`.git`、源码目录、文件系统根、symlink、不安全权限和缺失多级父目录。
- 这条边界允许维护者把完整 SwiftPM checkout/artifact/build database 放到 T7，避开 File
  Provider 把仓库内旧 `.build` 文件变为 `dataless` 后普通读取永久等待的问题。不得删除或复用
  已知 dataless graph；Production、Debug 与 Performance QA 仍须使用三个固定 flavor 物理隔离。
- 外置 scratch 只包含公开依赖 checkout、构建中间产物与编译缓存，不读取或复制 Agent Hook、
  Codex trust、Keychain、SQLite 或任务内容；它不是发布产物，保留/删除由维护者控制。

---

## Production App hermetic 真实启动门禁（v6.50.0）

- 编译期 hermetic Performance QA App 不能代替真正的 Production Bundle。`production-launch-smoke`
  只接受精确 `app.devisland.Island`、无 Performance plist marker 且通过 build-flavor、依赖闭包与
  strict deep 签名检查的 App；所选 executable/plist 先经 descriptor 稳定哈希，再把整个 Bundle
  冻结到随机私有 `0700` sampler root，只有该副本可以启动。
- Production 隔离模式必须同时收到且只收到一次
  `--dev-island-hermetic-launch-smoke-v1`，并从环境精确收到
  `DEV_ISLAND_HERMETIC_LAUNCH_SMOKE=v1`。缺失任一半、重复参数、lookalike 或其他环境值都按普通
  Production 启动处理；该模式不授予能力，只让 `TaskStore.shared` 选择
  `TaskStore(bootstrap: false)`，并跳过 LaunchHealth、TaskNotifier、Sparkle 与 Welcome。普通
  Finder、LaunchServices 与用户命令行启动行为不得改变。
- 真实 Production 路径仍必须构造可见岛、`StatusItemController` 和 shipping SwiftUI/AppKit
  surface。两者布局完成后才可从非主线程输出一次
  `DEV_ISLAND_PRODUCTION_READY uptime=<monotonic>`；readiness 缺失、重复、格式错误、反向/超窗、
  提前退出或状态栏未构造都失败关闭。
- Sampler 使用私有 `CFFIXED_USER_HOME`，固定零 warmup、8 个一秒存活样本且禁止 CPU/RSS
  threshold。readiness 后及每个样本都必须证明精确 PID 没有网络 socket，隔离 HOME 内没有
  `tasks.sqlite` 或 `local-hook-authorization.header`；正常退出后再次检查无产品状态。采样结束
  必须用精确 PID 的 `NSRunningApplication.terminate()`，在 5 秒内得到真实 status `0`。
- 成功 summary 必须明确包含 `scenario=production-launch-smoke`、
  `launch_profile=production-hermetic`、`production_services_isolated=true`、
  `isolated_user_home=true`、`isolated_app_snapshot=true`、8 项 sample count、正常退出以及相等的
  selected/private executable SHA-256。锁屏 override 只证明 loader、UI 构造、8 秒存活与退出，
  这些 CPU/RSS 样本禁止用于性能、丝滑度、首帧、能耗或 Release 宣传。
- PR CI 的 `app-build` 必须在 Universal Production 构建后执行该 smoke；tag Release 必须在 App
  公证、staple、Gatekeeper 校验之后、DMG 打包之前对同一 notarized App 再执行一次。workflow 的
  acceptance 仍只读取 sampler 的有界 stdout shell 变量，不得在 producer 退出后重开 public
  summary。该门禁不读取真实 Keychain、SQLite、Hook/Agent 配置、任务、通知历史或 crash report，
  也不替代真实 Agent、真实用户数据迁移、Developer ID 分发、解锁视觉、VoiceOver 或跨机器验收。

---

## Settings Agent Hook 配置 I/O 主线程隔离（v6.51.0）

- **Agent Connections** 打开时的单 Agent `isInstalled` / managed-entry 扫描、全部 Agent 的
  `hasManagedHooks` 汇总，以及用户触发的 Enable / Update / Disable 都可能读取和解析最大 4 MiB
  JSON/TOML 或 256 KiB 插件，并在写入路径执行 file/directory `fsync`；这些动作不得直接运行在
  SwiftUI MainActor。Settings 必须统一通过 `LocalAgentConfigurationExecutor` 进入 detached worker，
  主线程只接收 `.absent` / `.current` / `.updateRequired`、成功布尔值与既有固定错误文案。
- 初次状态固定为 `.checking`，读取完成前只显示有界 ProgressView，不得短暂呈现可能错误的 Enable
  或 Disable。后台刷新使用 latest-operation-wins token：新 refresh 可取代旧 refresh，晚到旧结果
  不得覆盖界面；mutation 独占同一行，执行期间第二次 refresh/mutation 必须被拒绝。
- Enable / Update / Disable 返回后必须重新从 descriptor-backed 配置边界读取实际状态；只有写入
  未抛错且实际状态等于动作期望值才显示成功。外部进程在写后立即修改配置时必须保留实际状态并
  显示固定失败文案，不能凭用户点击目标伪造 Connected。
- mutation/refresh 开始必须使旧 Codex activation probe token 失效；晚到的 Hook trust 结果不能覆盖
  新配置状态。视图离开时只让 UI token 失效，不强制取消已经进入原子写边界的操作；重新打开后
  必须从磁盘重新检查。
- `LocalAgentHookMaintenance.removeAllManagedHooks()` 继续使用既有 prepare-first/rollback 事务并在
  detached worker 执行；完成后的全局 managed-Hook 汇总同样不得回到主线程扫描。中英文忙碌态、
  ProgressView 无障碍标签、状态机竞态和 MainActor→非主线程真实断言必须由本地化与 XCTest 固定。
  该边界改善 Settings 响应性，不代表真实 Claude/Codex Hook 已获用户更新或信任。

---

## Settings Agent 配置全局操作所有权（v6.57.0）

- `SettingsView` 必须在 pane switch 之上持有唯一 `LocalAgentConnectionsOperationState`。单 Agent
  Enable / Update / Disable 与 **Disconnect All…** 是同一个配置表面的互斥 mutation；不得由每个
  row 或当前 Agent pane 各自维护忙碌状态。切到 General、Support 等页面再返回时，在途操作仍须
  保持可见和不可竞争，不能因为子视图重建而恢复可点击按钮。
- mutation 开始后，全部 Agent 配置动作、Codex trust **Check again**、readiness **Check this Mac**
  和全局维护动作都必须拒绝竞争执行。完成必须同时匹配 operation ID 与 mutation kind；晚到、
  错类型或旧视图结果不得释放另一项操作的所有权。
- 每次合法完成增加一次 `completionGeneration`，让当前或重新创建的 Agent pane 统一重扫单行状态、
  managed-Hook 汇总并废弃旧 readiness。UI 不得依赖已销毁 row 的本地 completion 才恢复真实状态。
- **Disconnect All…** 的跨文件 prepare/write/rollback 仍由既有安全事务负责，但 View 不得直接创建
  detached 维护任务；它必须通过共享 `LocalAgentConfigurationExecutor`。worker 只返回
  no-changes、断开数量或 failed，不能把配置路径、原始错误或用户拥有的 Hook 内容带回主线程。
- 新 mutation 清除旧维护提示；提示和 ProgressView 使用固定中英文低基数文案。该状态机契约可以
  证明无并发产品写入和无晚到解锁，不能替代解锁后的切页手感、真实大配置耗时、VoiceOver 或
  Animation Hitches 验收。

---

## Manus 签名窗口重放与终态单调性（v6.58.0）

- Webhook 必须先完成 RSA、完整注册 URL、原始正文与 300 秒时间窗验签，再解析并登记
  `event_id`。replay retention 使用本次认证时间戳的精确 `signedAt + maximumClockSkew`，不能按
  首次到达时间猜测，也不能只保留首次签名；同 ID 携带较新有效签名时必须把 expiry 向后延长。
- 最多保留 1,024 个仍在有效签名窗口内的 ID。容量已满时，新 ID 必须以 HTTP 503 拒绝，让
  provider 稍后重试；不得通过 FIFO/LRU 驱逐仍有效 ID。已保留 ID 的重复投递继续返回 200 且
  不进入 `StateReconciler`，避免 provider 因非 2xx 反复放大重复请求。
- 清理只允许移除 `expiry < acceptedAt` 的条目；签名恰在 300 秒边界仍有效，因此相同边界上的
  replay ID 也必须继续保留。该窗口只在 WebhookServer actor 内存中存在，不写日志、SQLite、
  UserDefaults 或诊断。
- 即使攻击者捕获多个不同 event ID，`StateReconciler` 也必须把 Manus Completed/Failed 作为
  单调终态：任何后来的 `task_stopped(ask/finish)` 都不再改写它。Running/Waiting 仍可正常前进到
  Waiting/Completed，漏掉 create 时也继续允许恢复一个新的 Manus task。
- 单元回归必须固定：重复拒绝、较新签名延长、容量饱和失败关闭、终态不回退和
  Waiting→Completed。Security 静态门禁还必须拒绝 FIFO 驱逐，并固定 503 delivery 行为。
  当前 Release 的 Manus realtime gate 仍为关闭；该代码/测试契约不等于真实账号已验收或可商用。

---

## Manus replay 真实 HTTP transport 回归（v6.59.0）

- `WebhookServer` 的 Production 公开构造必须始终使用固定 1,024 项 replay window。只有
  IslandCore module-internal 的测试构造可以注入更小正整数 capacity；IslandCore/CLI 的任何生产
  call site 都不得传入或覆盖该值，避免测试 seam 变成运行时弱化入口。
- transport 回归必须启动真实 Hummingbird loopback listener，为不同官方 v2 JSON body 生成真实
  RSA-2048 PKCS#1 v1.5 + SHA-256 签名，并经 `/webhook` HTTP route 发送；不得直接调用 router
  closure、伪造认证结果或只测试 `WebhookReplayWindow.register`。
- 同一个已签名事件首次请求必须返回 200 且恰好 delivery 一次；第二次必须仍返回 200，但 delivery
  计数不变。填满两个 live ID 后，第三个不同 ID 必须从真实 route 返回 503 且不 delivery。
- 饱和响应后再次发送最早 ID 必须继续返回幂等 200 且不 delivery，直接证明 HTTP 层没有为了给
  第三个事件腾位置而驱逐 live ID。每个测试使用随机空闲端口、ephemeral/no-proxy URLSession，
  完成与异常路径都停止 server，不依赖公网 Manus、Cloudflare、用户 Key 或真实任务。
- Security gate 必须固定测试名、Production capacity 构造和无生产覆盖 call site。该回归证明
  本机签名 transport 行为，不等于真实 Manus 注册、provider retry 策略、Cloudflare 转发或公网
  realtime 已验收；Release gate 继续保持关闭。

---

## Manus Webhook trust generation 与 cleanup transaction（v6.85.0）

- Webhook trust identity 固定为 **exact external URL + canonical RSA public-key identity**。
  RSA key 只有经 Security.framework 成功导入、明确至少 2,048-bit，并从 canonical external
  representation 计算 SHA-256 后才可提交；同一 key 的 PKCS#1/SPKI PEM 等价，真实 key 或 URL
  改变才原子轮换 generation 和 replay window。所有 candidate 验证先于状态写入。
- 每个认证成功的 HTTP 请求必须携带认证时的私有 generation UUID 到 replay registration。若期间
  `configure` 已提交新 tuple，旧请求返回 `staleTrustGeneration` / HTTP 401、零 delivery、零新代
  replay 占位；这条跨 actor suspension 边界必须由真实 Hummingbird POST + RSA 签名回归覆盖。
- 所有 Manus 已接受的 registration ID 都是 cleanup capability。返回后必须与对应 unresolved
  attempt 的解除一起原子写入 `webhookRecoveryStateV1`；legacy `webhookId` / `webhookIds` 仅继续
  镜像。replacement 前必须逐个删除所有旧 ID，交错生命周期产生的新 ID 不能覆盖正在删除或失败
  待重试的旧 ID。
- outcome unknown 的 attempt 可通过官方 `GET /v2/webhook.list` 保守恢复。严格 DTO 最多 1,024
  项，拒绝重复/不安全 ID、非 canonical HTTPS URL、未知状态、非法 Int64 时间、缺字段、错类型、
  redirect、超限列表或正文。归属只允许 `active` + exact callback digest + `startedAt ± 300s`，且
  同 digest 只能有一个 unresolved attempt；歧义、空 list、inactive、窗外与无关 row 均保留 marker
  且删除零项。并发 start/stop 必须共用 list single-flight。
- matched IDs 必须先作为 `discoveredWebhookIDs` 与 ledger/attempt 一起原子持久化并 readback，再
  删除。失败 ID 跨重启直接重试而不再次 list；最后一个 ID 经 2xx `ok:true` 或精确 official 404
  `not_found` 清除后，才可解除 attempt/token。legacy token-only 或 corrupt envelope 继续 fail closed。
- 一个 ID 的并发 stop/wake/heartbeat/late-registration cleanup 必须 join 同一个
  `WebhookDeletionOperation`。provider delete 只有 HTTP 2xx + JSON `response.ok == true` 才成功；
  先停止对应 process，确认后才清本地 ID。失败保留 ID，单次 stop 不做无界循环，并以
  `webhookCleanupFailed` 返回；heartbeat 不得注册 replacement，只能通知一次并退到 polling-only。
- credential-releasing stop 只有在全部已登记 registration operations 已完成、accepted IDs 已先
  持久化再 rollback、reconciliation 已闭合，且 known IDs、unresolved tokens/attempts、launch、
  deletion、listing ownership 全空且 envelope 未损坏时才可成功。超过有界 grace 仍未结束的
  cancellation-unaware operation 继续由 manager 持有，但当前 stop 立即以 cleanup failure 返回并
  禁止 credential release；晚到 ID 仍走补偿删除。即使旧 start 本应 `lifecycleSuperseded`，delete
  failure 也优先返回，确保调用方不会把 supersession 误当作已安全释放 credential。
- `TaskStore` 的 Disconnect **与换 key** 都必须执行 **delete-before-credential-release**。
  `clearAPIKey()` detach 当前服务、停止 poller、移除 Manus snapshots，在 Keychain credential 仍
  存在时 await 上述 tunnel stop；`configureAPIKey` 则先 join 已有 removal，并在 candidate Keychain
  save 前用旧 manager 完成同一 cleanup。失败时保留旧 credential / APIKeyStatus 与 cleanup owner，
  固定进入 `Remote callback cleanup pending; retry disconnect`；Settings 将其本地化为可操作的
  Retry Disconnect 文案，重试成功后才允许删除或覆盖 Keychain。
- realtime gate 关闭不能丢失 ledger ownership：polling-only 服务必须用内部
  `CleanupOnlyWebhookServer` + 普通 `TunnelManager` 装配一个永不启动 listener/tunnel/registration
  的 owner，从 shipping preferences 恢复遗留 ID，并让 Disconnect 或换 key 使用当前 credential
  清理。没有 credential 时不得假装旧 ID 已清理。
- 定向回归必须覆盖 canonical-equivalent key 不 reset、URL/真实 key reset、弱于 2,048-bit key 与
  非法 candidate 原子拒绝、旧代请求交错拒绝、多 ID 重叠持久化、遗留 ID 阻止 replacement、
  `ok:false` 不确认删除、strict 404 `not_found` 幂等完成、registration bounded fail-closed + late-ID
  compensation、active-only exact-digest `±300s` recovery、同 digest 歧义/空 list fail-closed、
  discovered-ID 跨重启重试、heartbeat cleanup failure、cleanup-only ledger、
  credential 保留/Disconnect 重试，以及 replacement key 在旧 cleanup 前零 Keychain overwrite。
  普通测试只使用 loopback、合成 key、隔离 preferences 与进程内 Keychain backend。
- 这些事务在代码和 hermetic 测试中闭合，不是 Manus/Cloudflare 公网证据。当前仍缺真实账号
  create → signed delivery → list/delete 以及 read-after-create/read-after-delete 一致性证据；
  `ManusRealtimeTrust.liveV2AcceptanceComplete` 继续固定为 `false`。没有新的真实账号 accepted 包，
  Release 仍只允许声明 polling-only fallback，不能宣称 realtime 或 Manus 集成可商用。

---

## Plan Review Markdown 单次后台渲染（v6.52.0）

- Claude `ExitPlanMode` Markdown 除 65,536 个 Swift `Character` 外必须同时受 262,144 UTF-8
  bytes 上限约束；单个由大量 combining scalar 组成的 grapheme 不得绕过真实内存边界。
- 展开岛的一秒动态路径只负责 duration/countdown。Plan Review 的块级解析与 Foundation
  inline Markdown → `AttributedString` 必须经 `PlanMarkdownRenderingExecutor` 在 detached worker
  中完成，并作为 immutable `PlanMarkdownDocument` 返回；`ActionRequestSurface` 的 body、
  `PlanMarkdownView` 和一秒重绘路径不得再调用两类 parser。
- 每个 request ID 只启动自己的 render generation；operation ID + request ID 同时匹配才可交付。
  新请求、视图离开或取消必须让旧结果失效，晚到 document 不得替换当前审批面。
- 单份 document 最多允许 512 个块进入 SwiftUI。空文档或超过 512 块必须产生不可决策的安全态，
  不得构造病理性 view tree，也不得截断后仍让用户误以为看到了完整计划。
- render 完成且 document 完整非空之前，Approve 与 Reject（含 `⌘↩` / `⌘D`）必须保持 disabled；
  **Continue in Claude** / `⌘O` 始终可用，让用户回到原生完整计划。加载态使用固定双语文案和
  ProgressView AX label，不显示 parser 错误或原始数据。
- DEBUG/QA 离屏快照可以显式注入同一 renderer 生成的最终 document，因为静态 host 不推进异步
  run loop；Production 默认字典必须为空并走真实后台路径。该入口不得接受手工拼装的替代视觉。
- 真实非主线程断言、latest-wins、离开失效、512 块上限、未完成前键盘拒绝及 combining-grapheme
  byte 攻击必须由 XCTest 和 performance CI 固定。代码/锁屏启动证据仍不能替代解锁大计划的
  Animation Hitches、滚动、VoiceOver 与真实 Claude Code 验收。

---

## 展开面板叶子时钟隔离（v6.53.0）

- `NotchPanelView`、`ScrollViewReader` 与 `LazyVStack` 必须完全 clock-free；不得重新引入面板级
  `TimelineView`，也不得把同一个 `context.date` / `now` 注入全部任务行和决策面。
- Running/Waiting 的可见 duration 只允许由对应 `TaskCard` 的一秒本地时钟更新；Completed/Failed
  必须使用 `updatedAt` 生成静态终态时长，不能保留永久 tick。任务行仍以同一 reference date
  生成可见文字和 AX label，避免 VoiceOver 读到与屏幕不一致的时长。
- `AgentActionRequest` 的 countdown 只允许在请求 header 子树内更新。Permission、Question、
  Plan Review 正文、选项、滚动内容、按钮、键盘路由和渲染 operation 不得因秒针重新求值。
- 面板尚未 live 或已开始收起时，任务行与请求头的本地时钟都必须 paused；DEBUG/静态 QA 可
  显式传入固定 `Date`，从而得到确定截图且不安装周期时钟。duration/countdown 必须继续使用
  monospaced digits、秒级显示、向上取整的到期剩余量及零下限。
- `PanelClockPresentation` 是唯一格式/调度语义：Running/Waiting 使用当前时刻，终态冻结于
  `updatedAt`，负时钟偏差归零，超过一小时使用 `h:mm:ss`。纯策略 XCTest 与 performance CI
  必须同时固定以上规则和容器无时钟边界。
- 该代码契约证明结构性失效范围从整棵面板缩到单行/请求头，不等于真实 unlocked 滚动、
  Animation Hitches、VoiceOver 或能耗已经验收。

---

## Welcome 连接配置操作所有权（v6.54.0）

- Welcome 的初始 Hook 健康扫描与 Add/Update/Update all 不得自行创建散落的 detached task；两条
  路径统一通过 `LocalAgentConfigurationExecutor` 进入后台 worker，SwiftUI MainActor 只接收
  低基数 snapshot、目标失败集合和固定本地化错误文案。
- 初始/重复扫描使用 latest-wins refresh ID。新的 mutation 必须先废弃所有在途 refresh 的 UI
  所有权；旧扫描可以完成只读工作，但不得覆盖安装后的新状态。一个 Welcome surface 同时只允许
  一个 mutation，期间所有其他连接动作 disabled，批量操作的全部目标共同显示 working 状态。
- Add/Update/Update all 必须在后台完成全部 descriptor-backed 安装后重新读取完整 Hook snapshot；
  只有写入未抛错且最终状态为 `connected` 或有明确 vendor trust gate 的 `configured` 才算成功。
  `updateRequired`、`disconnected`、snapshot 缺项及写入异常都显示固定失败态，不得根据点击目标猜测
  Connected。Codex 是否从 Configured 提升为 Connected 继续只由既有只读 trust probe 决定。
- Welcome 离开或窗口关闭时必须使 refresh/mutation ID 失效并清空 presentation busy 状态，晚到结果
  不得写回已离开的 UI。已经进入 managed-config 原子事务的 worker 不被强制取消，避免在安全写入
  中途制造部分状态；重新打开后从磁盘重新扫描。
- `OnboardingConnectionOperationState`、纯 mutation 分类 seam 与 performance CI 必须固定刷新取代、
  mutation 独占、离开失效、写后复验和 View 内零直接 installer/detached 调用。该契约证明调度与
  状态可信边界，不等于锁屏下已经完成真实大配置点击延迟、视觉动效或 VoiceOver 验收。

---

## Support 诊断导出 I/O 主线程隔离（v6.56.0）

- **Copy / Save Diagnostics** 的 bounded Hook 状态读取，以及 Save 确认后的 file open/write、
  `fsync`、close 和 atomic rename，不得在 SwiftUI MainActor 上执行。Settings 必须通过
  `SupportDiagnosticsIOExecutor` 进入 detached worker；主线程只负责抓取已存在的低基数 App
  状态、展示 `NSSavePanel`、更新剪贴板，以及接收 `.saved` / 固定 `ExportError` 结果。
- 同一个 Support surface 同时只能有一个 Copy 或 Save operation。operation ID 从报告生成覆盖到
  Save Panel 取消/确认和后台 descriptor transaction 完成；切换设置页或视图离开会废弃 UI
  所有权，晚到报告、panel callback 或写入结果不得再修改已离开的界面。
- 已经进入 descriptor-backed 原子文件事务的写入不在视图离开时强制取消：它可以安全完成到用户
  已确认的位置，但完成结果不得回写旧 surface。取消 Save Panel 必须立即释放 operation ownership，
  不能让 Copy/Save 按钮永久 disabled。
- Copy 与 Saved/失败提示分别使用 feedback ID。旧的两秒/四秒延迟只能清除自己创建的反馈；即使
  用户连续得到逐字相同的提示，旧计时器也不得误清新结果。离开 Support 会同时废弃反馈身份。
- `SupportDiagnosticsOperationState`、`SupportDiagnosticsFeedbackState`、后台 executor 与 bounded
  worker outcome 必须有确定性 XCTest；performance/security CI 必须拒绝 Settings 重新直接调用
  `SupportDiagnosticsExporter.write`。真实测试须从 `@MainActor` 进入并观察 worker 的
  `Thread.isMainThread == false`。
- 该契约只证明阻塞文件系统调用与晚到 UI delivery 的调度边界。当前屏幕锁定时的源码测试和
  hermetic 启动不能替代真实慢盘/网络卷、Save Panel 交互、动画帧节奏或 VoiceOver 验收。

---

## Dock 重试与进程夹具调度隔离（v6.32.0）

- `DockVisibilityCoordinator` 的生产行为继续使用主线程 `16/32/64 ms` 指数退避并最多自动
  重试三次。重试调度器必须可注入，回归测试以确定性队列逐项排空，不得用固定
  `Task.sleep` 猜测 AppKit/主线程何时获得调度。
- 当 Settings/Welcome 租约变化使期望 activation policy 回到已应用状态时，必须立即轮换
  `retryID`；已经排队的旧回调只能因 generation 不匹配而退出，不能再制造一次无意义的
  AppKit 写入或主线程唤醒。
- Codex Hook trust 的 production 默认 timeout 继续固定为 3 秒，50 ms 超时回归也保持不变。
  所有需要观察真实子进程启动/退出、后台 descendant 或 PID 发布的隔离进程夹具统一使用
  5 秒调度预算，让新进程在高负载测试机上先获得一次运行机会；这包括 immediate-exit
  fixture。该预算不得进入 production 默认值，也不得代替独立 50 ms timeout 硬终止回归。
- 进程组测试仍必须实际读到 fixture 写出的 PID，并证明 descendant 已退出；不能把 PID 缺失
  当作成功。PID 未发布使用明确的 `FixtureError.pidNotPublished`，不得以网络超时错误伪装。
- 确定性 Dock 回归、Codex 五轮进程边界与全量测试只证明代码和测试调度边界；真实
  Settings/Welcome 打开关闭时的 Dock 动画、Command-Tab 与系统窗口体验仍以解锁实机证据为准。

---

## GitHub 仓库审计失败分类与诊断隐私（v6.33.0）

- `audit-github-repository-controls.sh` 的在线路径继续保持 GET-only，不得写 branch protection、
  Actions、security settings、Secret、workflow、tag 或 Release。PR CI 与 tag Release 都通过
  `verify-security-invariants.sh` 执行同一离线 fixture gate。
- `gh api` 失败不得统一冒充“缺少仓库管理员读取权限”。只允许输出低基数分类：
  `GitHub API network unavailable`、`GitHub authentication required`、
  `repository administration read access required`、`GitHub API rate limited` 或
  `unexpected GitHub API failure`；受控 endpoint label 可以保留，原始错误不得回显。
- `gh` stderr 可能含请求 URL、账户名、上游正文或其他运行环境细节，必须只写入本次 owner-only
  私有临时目录。诊断仅在 1 byte–64 KiB 时参与分类，成功后立即删除，失败退出时由 trap 清理；
  超限、空内容或无法读取统一进入 unexpected，不允许把原始内容拼入终端或证据包。
- 确定性 fake-`gh` fixture 必须覆盖 success、connection reset、HTTP 401、HTTP 403、HTTP 404、
  rate limit 与未知失败，并为每类注入禁止外泄的 sentinel。每个失败只允许一行固定分类；
  URL、token-like query 与 sentinel 任一出现在输出中都必须让安全门禁失败。
- 分类只说明本次在线读取为何不能形成控制结论，不把 network/rate-limit 当成仓库配置失败，也不
  把认证/权限失败伪装成已发现的 B/A/S finding。只有完整 snapshot 进入离线 validator 后，
  才能输出可作为 Release blocker 的固定 finding code。

---

## 权威测试 SwiftPM 构建图隔离（v6.34.0）

- PR CI 与 tag Release 不得直接调用无 `--scratch-path` 的 `swift test`。唯一入口为
  `scripts/ci/run-authoritative-tests.sh`，固定使用 `.build/tests-authoritative`；开发者默认
  `.build`、`.build/app-debug`、`.build/app-production` 与 `.build/app-performance-qa` 都不能
  与权威测试共享 `build.db`、checkout 或测试产物。
- `.build` 与 `.build/tests-authoritative` 在使用前必须是当前用户拥有的真实目录，不得是
  symlink 或 group/other writable。缺失时以 owner-only mode 创建；类型、owner 或 mode 漂移
  必须在 SwiftPM 启动前失败，不能静默回退默认 scratch。
- 权威入口先以 `--disable-keychain --only-use-versions-from-resolved-file` 在隔离 scratch 完成
  全量测试，再让 local-version 20 轮、hermetic listener CLI 10 轮、tmux 20 轮、Codex trust
  5 轮与 sleep/wake 20 轮复用同一构建图；其中 65 次 XCTest 重跑全部带同一
  `--scratch-path` 和 `--skip-build`，listener 夹具直接执行该图中已构建的唯一 CLI。成功路径
  只保留第一轮 XCTest aggregate count 与五条低基数 PASS，不重复编译或让稳定性脚本意外
  读取默认 `.build`。
- PR 失败诊断的 tests 复现命令和 tag Release 必须调用同一 wrapper；workflow 内出现直接
  `swift test` 视为绕过并由安全门禁拒绝。依赖解析仍可在前置独立步骤使用默认 SwiftPM
  workspace，但必须先完成且不得与权威测试共享数据库。
- fake-`swift` fixture 必须证明准确 66 次调用：1 次 full suite + 20 次 local-version + 20 次
  tmux + 5 次 Codex trust + 20 次 sleep/wake。每次都必须含精确 authoritative scratch；后 65
  次还必须包含 `--skip-build --filter`。调用数、filter 分布、顺序或路径任一漂移都失败。
- hermetic listener 夹具不调用 SwiftPM；它必须精确运行已构建 CLI 10 次，每次 stderr 为零且
  stdout 逐字等于五行 allowlist。任何 Hummingbird 日志、端口、路径、额外状态或非零退出都失败。
- 该隔离关闭的是开发构建、App 构建、依赖操作与权威测试互相持有 SwiftPM 数据库的风险；
  不把一次干净 fixture 通过解释为 runner 永不故障，也不替代 648 项真实执行、进程压力回归、
  Universal App 构建或真实产品体验验收。

## 权威测试单写者锁（v6.35.0）

- 固定 scratch 意味着同一工作树只能同时存在一个权威测试运行。入口必须在 SwiftPM 启动前
  打开 `.build/tests-authoritative.lock` 并通过 `/usr/bin/lockf -s -t 0 9` 立即取得 BSD
  advisory lock；不得等待另一个运行释放锁，也不得在竞争失败后改用默认或随机 scratch。
- 锁文件必须是当前用户拥有的真实普通文件，固定 `0600`、零字节、单硬链接且不得为 symlink。
  文件跨运行保留以维持 lock ordering；锁本身只随 descriptor 9 的生命周期存在，不写 PID、
  路径、测试名、GitHub context、Secret 或任何产品/用户数据。
- 第二个权威入口必须只输出一条固定低基数错误并在执行任何 `swift` 命令前退出。首个运行继续
  持有锁覆盖 full suite、全部 65 次 `--skip-build` 回归与 10 次 hermetic listener CLI 回归，
  不能在 full suite 后提前释放。
- 并发 fake-`swift` fixture 必须真实暂停首个 full-suite 调用、启动第二个 wrapper，并证明第二个
  在一秒边界内失败、Swift 调用数仍为 1；释放首个运行后，完整总数仍必须精确为 66。
- 独立临时 checkout 夹具必须拒绝 lockfile symlink、目录冒充、多硬链接、非 `0600` mode 与
  非空内容；每类只能产生一条固定错误，且不得执行 Swift 或进入稳定性脚本。
- 该锁关闭同一 checkout 内 CI、诊断复现或人工命令之间的 `build.db` 争用；不同 GitHub runner
  的独立 checkout 不共享锁。它不替代 hosted runner/tag 验收，也不授权终止其他开发进程。

---

## Welcome 编辑栏几何（v6.36.0）

- Welcome 三页必须共用同一固定几何：窗口宽 `760pt`，左右内边距各
  `32pt`，左侧编辑栏 `264pt`，栏间距 `28pt`，右侧功能标本 `404pt`；合计必须
  精确为 `760pt`，不得依赖隐式 slack 或视图压缩。
- English 三页的 display title 必须在固定两行内建立稳定视觉重心；第 2 页为
  `Bring your` / `agents together.`，不得回归三行。简中三页同样不得裁切或挤压右侧连接矩阵。
- `OnboardingLayoutTests` 必须用公开布局常量计算全宽并断言精确相等；CI 静态门禁
  同时固定常量值、实际布局用法和几何回归测试，防止仅改一处导致栏宽漂移。
- 离屏快照只能证明当前静态层级、换行和裁切边界；不得把它们解释为真实翻页动效、
  hover/press、键盘焦点、VoiceOver 朗读或 Reduce Motion 实机验收。

---

## 商业政策审批记录输入边界（v6.37.0）

- `scripts/commerce/commercial-policy.json` 是未来 Seller、Provider、价格、试用、设备、
  退款和法律决策的唯一机器记录。验证器不得在 `lstat` 后再按路径 `binread`；必须
  以 `O_NOFOLLOW|O_NONBLOCK` 打开并只解析同一 descriptor 中的有界字节。
- 最终文件必须是当前用户拥有、单硬链接、group/other 不可写、1–131,072 bytes 的
  普通文件。最终父目录必须是当前用户拥有、不可被 group/other 写入的真实目录，
  不得是 symlink。
- 读取前后必须精确复验 file descriptor 的 device/inode/owner/mode/link count/size/
  mtime/ctime；随后再将路径与父目录绑回同一 metadata snapshot。不完整读取、文件替换、
  目录替换或 metadata 漂移均须在 JSON 解析前失败。
- JSON 的每一层 object 都必须拒绝重复 key，不能依赖 Ruby 默认的 last-key-wins 语义。
  重复的 `decisionState`、价格或其他任意字段不得进入完整性/批准判断。
- 失败输出只允许固定低基数原因，不得回显政策内容、Seller/Provider 值、路径或原始系统
  错误。攻击夹具必须覆盖 symlink、hard link、不安全 mode、空/超限/目录冒充、父目录
  symlink、根/嵌套重复 key 与打开后替换。
- 该边界只证明记录输入可审计；当前 `decisionState: required` 仍必须保持，不能被解释为
  任何 Seller、Provider、价格、政策或法律批准，也不允许连接付款 UI 或生产 trust anchor。

---

## Codex App Server stdio 子进程边界（v6.19.0 加固）

- Codex Hook trust 继续只执行通过 Bundle ID、OpenAI Team ID 与全架构签名验证的官方 App
  内嵌 `codex app-server --stdio`；PATH、Homebrew/npm shim 和任意同名二进制不能进入自动探针。
- stdin 请求必须一次性限定在 1–64 KiB；stdout 总量限定 2 MiB，默认 3 秒且硬上限 10 秒。
  当前工作目录必须是绝对、真实存在的非链接目录；参数和最小环境的数量、单值字节数均有
  上限。stderr 固定到 `/dev/null`，原始 App Server 输出不记录、不持久化、不进入诊断。
- 子进程必须通过 `posix_spawn` 进入独立进程组；stdin/stdout 都使用 nonblocking descriptor，
  同一调用线程以 `poll` 同时写入请求、持续排空响应，并使用 monotonic deadline。直接子进程
  在没有目标 response ID 时退出，必须立即返回 `invalidResponse`，不得继续白等完整 3 秒。
  所有 pipe endpoint 在 file actions 前提升到标准 fd 以上并设 close-on-exec；parent 写端
  设置 Darwin `F_SETNOSIGPIPE`，对端抢先关闭 stdin 时只形成局部 `EPIPE`，不能终止 App。
- 收到目标响应、提前退出、I/O 失败、超量或超时的所有出口，都必须关闭 pipe、先向完整
  process group 发送 TERM、短宽限后 KILL、`waitpid` 回收直接子进程，并再次清理继承该组的
  后台 descendant。请求、分块缓冲、非目标行、最终响应在使用后尽力清零；任何失败只让
  Codex 保持 `configured`，不能误报 `connected`。

---

## 系统 sleep/wake 恢复顺序（v6.20.0 加固）

- `NSWorkspace.willSleepNotification` 必须先取消所有同步人工请求并把 Manus 状态降为
  `disconnected`。Tunnel suspend 可以异步执行，但其 `Task` 必须由 `TaskStore` 保留为下一次
  wake 的顺序 barrier；禁止恢复为无所有权的 `Task.detached` fire-and-forget。
- `didWakeNotification` 继续先幂等重启本地 Hook listener；Manus realtime 只有在对应 suspend
  完成后才能调用 `handleSleepWake()`，因此迟到的 suspend 不能在新 tunnel/webhook 建立后把它
  再次清除。没有 pending sleep 的重复 wake 不重启 public tunnel，也不消耗 restart budget。
- 每次 sleep、有效 wake 与 shutdown 都推进 power generation。Tunnel restart、失败降级、
  post-wake poll、401 与最终状态写入在各自 await 后必须同时复核 power generation 和 Manus
  service generation；新 sleep 或 Disconnect 可以让旧 wake 静默失效，不能把睡眠态误写成
  degraded/connected，也不能复活已断开的服务。
- `ManusTunnelLifecycleProtocol` 只暴露 TaskStore 所需的 start/stop/suspend/wake 表面；生产仍由
  `TunnelManager` actor 实现。阻塞 suspend、重复 wake、Disconnect 与新 sleep 竞态必须使用
  注入 actor 做确定性回归，并在 PR CI 对完整 TaskStore Manus 生命周期连续运行 20 轮。

---

## Tag Release checkout 凭据隔离（v6.21.0 加固）

- Release job 虽然为最终 GitHub Release 和 provenance 声明 `contents: write`、`id-token: write`
  与 `attestations: write`，但 checkout 必须固定 `persist-credentials: false`，也不得显式覆盖
  checkout 的 `token` input。这样 tagged revision 内的 `Package.swift`、构建脚本与仓库门禁运行时，
  本地 Git 配置中没有可复用的写权限凭据。
- checkout 必须是 job 的第一步且 action 固定完整 40 位 SHA。第一个仓库命令必须是独立安全
  YAML 验证器，在依赖解析、SwiftPM manifest 求值、测试或任何其他仓库代码之前，重新验证当前
  workflow 的 checkout、步骤顺序和 token 暴露边界。
- `GITHUB_TOKEN`/`GH_TOKEN` 及任何命名为 token/PAT 的 GitHub 凭据不得出现在 workflow、job
  或任何发布前 step 的环境、run/with 字段。
  唯一允许的显式 token 是最终 `Create GitHub Release` action 的 step-local
  `GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}`；该 action 必须位于完整资产校验与两个 provenance
  attestation 之后，并固定完整 action SHA。
- 结构化验证器还必须拒绝 workflow/job `env` 中任何 `${{ secrets.* }}`，并精确固定 App
  keychain setup → App 签名/公证/launch smoke → App keychain teardown → `Package DMG` → DMG
  keychain re-import → DMG 签名/公证 → DMG keychain teardown 的唯一性与顺序。`Package DMG`
  不得引用 Secret，其 `env` 必须逐项且只等于 `create_dmg_tool` 的 `root`、`executable`、
  `manifest` 三个 output。
- Prepare、两次 keychain setup、两次即时 teardown、`Package DMG`、`Sign + notarize DMG`
  与最终 `if: always()` cleanup 的完整 `run` body 必须绑定审核过的 SHA-256。负向夹具必须至少
  拒绝 workflow/job Apple Secret、Package Secret、将重新验证或 `/usr/bin/env -i` 注释掉、
  Package 提前到 App keychain teardown 之前、缺失 DMG keychain re-import/teardown，以及重复
  Package step；注释中的命令文本不能冒充实际边界。
- 验证器只接受 1 byte–1 MiB 的普通非链接 YAML，使用 safe YAML 解析而不是注释可欺骗的全局
  文本命中。缺失/启用 credential persistence、checkout token override、提前暴露 token、最终
  token/PAT 提前暴露、最终 token 缺失与 workflow symlink 都必须由独立攻击夹具拒绝。
- 该本地边界只限制 reviewed workflow 的凭据驻留，不会让任意人可推 tag 或可修改 workflow 的
  仓库自动安全。`main` review、required check、管理员执行、tag/release 权限与 Actions allowlist
  仍必须由 GitHub 远端控制单独验收；当前远端控制未通过前不得宣称商业发布链完整。

---

## Manus 真实账号验收证据边界（v6.22.0 加固）

- `scripts/qa/run-manus-live-acceptance.sh` 是唯一的一键留证入口。它必须先证明
  `/Volumes/T7 Shield` 是当前挂载点，再在固定 T7 根下随机创建 append-never、`0700` 的运行目录；
  SwiftPM scratch/cache/config/security、证据二进制与所有持久文件都不得回退到内置盘。
- 包装器不得读取参数、环境变量或管道中的 Manus Key。构建后执行 `IslandCoreCLI` 时使用
  `env -i` 的固定 PATH/TMPDIR/locale；Key 仍只由 CLI 内的
  `readpassphrase(..., RPP_REQUIRE_TTY)` 直接从交互终端读取。stdout 进入 transcript，stderr
  保持终端可见但不自动进入接受证据。
- 成功 transcript 必须精确包含四行固定前言、以下 11 个且各一次的 checkpoint：trust anchor、
  server、tunnel、registration started、signed registration probe、registration accepted、
  task created、finish、ask、webhook deleted、transports stopped，最后一行且唯一结果必须为
  `result=accepted`。finish/ask 的先后可互换，其余依赖顺序不可改变；signed probe 必须位于
  registration started 与 accepted 之间，远端删除必须早于本地 transport 停止。
- transcript 验证器只能通过 `O_NOFOLLOW` descriptor 读取 1 byte–64 KiB、当前用户所有、普通
  非链接、单硬链接且不可 group/other 写的 UTF-8/LF 文件。重复、缺失、乱序、未知行、URL、
  provider ID、raw error、CRLF、超限、符号链接、硬链接或可写权限全部失败，错误输出不得回显
  被拒绝的原文。
- 每次运行必须绑定产品版本、baseline commit、dirty/clean、开始/结束 UTC、CLI exit、构建结果、
  验证状态、CLI binary SHA-256，以及构建前后的完整本地输入/依赖闭包和工具链 manifest；
  任一输入或工具链在构建中变化必须失败。顶层 `SHA256SUMS` 覆盖包内每个普通文件。
- 只有 CLI exit 0、transcript 捕获成功且 `--require-accepted` 通过时才能创建 `ACCEPTED`。
  失败、取消、timeout、manual review、构建失败或包装器中断仍保留私有证据目录，但不得创建该
  marker；超出低基数 allowlist 的 transcript 必须移除并只留固定拒绝说明。自动化夹具或空凭据
  演练不能替代真实 Manus 账号与人工复核，也不能打开
  `ManusRealtimeTrust.liveV2AcceptanceComplete`。

---

## Codex 真实审批证据边界（v6.63.0 加固）

- `run-codex-live-approval-evidence.sh` 只能在已挂载的 `/Volumes/T7 Shield` 下随机创建
  append-never `0700` 运行目录；`--output` 由 wrapper 独占。每个持久文件最终为当前用户只读，
  顶层 `SHA256SUMS` 必须完整覆盖固定文件清单。
- 输入必须显式指定一个 Codex session JSONL、Dev Island SQLite、proof、被测签名 App、Codex CLI
  及 approval/running/completed 三张截图，并逐字确认
  `waiting,allow_once,running,completed`。该确认是有名称的人工作业门，不得描述成像素或
  VoiceOver 自动识别。
- session 只允许通过 no-follow descriptor 读取 1 byte–16 MiB、当前用户拥有、普通非链接、
  单硬链接且不可 group/other 写的稳定 UTF-8/LF JSONL；原始 session、developer/user message、
  reasoning、无关 tool output 均不得复制进证据。
- 提取器必须证明唯一 session metadata、精确外部 proof prompt、唯一 `require_escalated` 请求、
  固定 justification、先返回有界 pending cell、同 cell 的单一有界 wait、exit 0、精确
  `APPROVAL_ROUND_TRIP_COMPLETE` 与 task-complete 顺序；proof 必须位于 session workspace 外并
  严格等于 `dev-island-real-codex-approval\n`。
- 同一 session ID 必须在 descriptor 校验过且提取前后 SHA-256 不变的 Dev Island SQLite 中仅有
  一条 `source=codex,status=completed` 记录；created/updated 必须落在 session 时间边界附近。
  包内只保存该低基数脱敏行与数据库哈希，不复制数据库或其他会话。
- App 必须是 `app.devisland.Island`、版本等于仓库 `VERSION` 且通过 strict deep 签名验证；App
  executable、Codex CLI、session、SQLite、proof、截图分别绑定 SHA-256 与有界字节数；packager、
  validator 与 T7 wrapper 自身也必须进入 metadata/receipt 哈希，避免未审阅 producer 生成 accepted 包。
- 包内 transcript 只能是固定 11 行 checkpoint/result；metadata、task record、public receipt、
  proof、三张 JPEG、`ACCEPTED` 与 checksum manifest 组成精确 allowlist。链接、多硬链接、可写、
  超限、额外文件、CRLF、字段乱序、内容/哈希/版本漂移均失败关闭。
- 只有完整包通过独立 `--require-accepted` 校验时才允许生成 `ACCEPTED`。仓库只签入脱敏
  `docs/CODEX_LIVE_APPROVAL_RECEIPT.txt`，Security gate 以正向合成证据和 session symlink、错误
  final、proof/transcript/task/JPEG/checksum/权限/版本等攻击夹具验证 packager/validator，tag
  Release 通过既有 `verify-security-invariants.sh` 强制执行同一门禁。
- 该机制已经绑定一轮 v0.3.0 Codex `Allow once` 真实闭环，但只证明这一个 action/session；它不
  证明 Deny、timeout、native fallback、全部 Agent 或 VoiceOver，并且 `worktree_state=dirty` 会在
  receipt 中如实保留，不能冒充由 clean tag 可重现的正式 Release 证据。
- 该证据门禁的权威回归必须在同一孤立测试图上执行完整 XCTest 与
  20/10/20/5/20 轮版本探针、listener、tmux、Codex trust、sleep/wake。Codex immediate-exit
  进程 fixture 必须使用上述独立 5 秒调度预算，但 `CodexHookTrustProbe` 产品默认 3 秒边界不变。

---

## Codex 真实拒绝与超时分类证据边界（v6.65.0 加固）

- 新增 `run/package/validate-codex-live-decision-evidence` 独立链路，不修改既有 Allow Once
  receipt。wrapper 只能在已挂载 T7 Shield 的固定根下建立随机、append-never、`0700` 包，禁止
  调用 classification-only 模式伪造 accepted 输出；失败目录保留但不能出现 `ACCEPTED`。
- session 分类固定为且只能为四种：`explicit_island_deny`、`neutral_timeout_fallback`、
  `sandbox_rejection`、`interrupted_attempt`。`turn_aborted`、`<turn_aborted>` 或
  `aborted by user` 优先判为中断；非交互 `source=exec`、缺少 `require_escalated`、未进入 pending
  cell 或出现 sandbox/operation-not-permitted 只能判为 sandbox rejection；90 秒及以后才返回的正常
  拒绝只能判为 neutral timeout fallback。后三类永远不能进入 accepted packager。
- `explicit_island_deny` 必须来自 `Codex Desktop + source=cli + thread_source=user`，包含精确外部
  proof prompt、唯一精确 command、审核过的旧/当前 justification、`10,000 ms / 1,000 或 2,000
  token` 请求边界、同 cell 最多四次有界 wait、1–89 秒内明确 denial、唯一
  `DENIAL_ROUND_TRIP_COMPLETE` 与 task-complete，且全程不存在 turn abort、sandbox violation 或
  成功 proof。`workdir` 可省略并严格继承 session workspace；一旦显式提供就必须为非空绝对路径且
  realpath 与 workspace 相同。
- Codex 当前可能把 `exec_command` 参数留成严格 JSON，也可能留成 JavaScript object literal。验证器
  绝不 `eval`：fallback parser 只接受 `cmd/workdir/sandbox_permissions/justification/yield_time_ms/
  max_output_tokens` 六个无重复字段、两空格缩进、规范逗号，以及 JSON string 或十进制非负整数。
  表达式、函数调用、嵌套结构、未知/重复字段、畸形字符串一律拒绝且不能产生副作用。
- proof 路径必须绝对、规范、字符受限、父目录真实且稳定，并位于 session workspace 外。分类前、
  打包前以及写入 `ACCEPTED` 前都必须 `lstat` 得到 ENOENT；包内只保留路径 SHA-256、检查时间与
  `result=absent`，不保存路径本身。证明文件存在、父目录 device/inode 漂移或最终检查失败均拒绝。
- 同一 session 必须在稳定只读 SQLite 中只有一条 completed Codex row，时间落在 session 边界附近；
  App 版本/Bundle/signature、CLI、session、SQLite、两个脚本层与 wrapper 全部绑定哈希。视觉门固定为
  `waiting,deny,running`，只是一项有名称的人工复核，不冒充像素/AX 自动识别。
- accepted 包精确包含两张 JPEG、固定 11 行 transcript、一条脱敏 task record、
  `PROOF_ABSENCE.txt`、metadata、public receipt、`ACCEPTED` 与完整 `SHA256SUMS`。原始 JSONL、SQLite、
  prompt、reasoning、command/path 均不复制；链接、多硬链接、可写/额外/超限文件、字段顺序、哈希、
  版本或分类漂移均失败关闭。
- 拒绝回执只接受两种逐字审阅结构：旧客户端的完整 `Permission request denied by user` 终止输出，
  或当前客户端数组输出中逐字绑定同一 reviewed command、`/bin/zsh -lc` 与
  `CreateProcess { message: "Rejected(\"Denied in Dev Island.\")" }` 的失败正文。宽泛
  denied/rejected 文本、不同命令或缺失 wrapper 结构均不得作为显式岛内拒绝。
- Security gate 的合成正例和攻击夹具必须覆盖四类分类、strict JSON 与受限 JavaScript 两种真实格式、
  executable expression/duplicate field 零执行、已存在 proof、session symlink，以及包内链接、权限、
  extra file、classification/absence/JPEG/checksum/receipt 伪造。真实样本
  `01a0517c…` 固定为 `sandbox_rejection`，`01a0517d…` 与 `01a0517e…` 固定为
  `interrupted_attempt`；不得把 TUI 中曾出现 native prompt 当成 neutral-timeout accepted 证据。
- 已有一条解锁状态下的真实 Codex session 在岛内按下 **拒绝**，40 秒内正常恢复 Running 并完成；
  proof 始终不存在，DB/截图/App/CLI/session/脚本哈希一致，T7 wrapper 已产出 accepted 包。仓库只签入
  脱敏 `docs/CODEX_LIVE_DECISION_RECEIPT.txt`；该事实仍只证明此 action/session，不替代 timeout、
  native fallback、其他 Agent、clean tag、Developer ID、公证、Sparkle 或商业 owner 审批。
- 聚合 Security gate 必须直接要求并验证该 checked-in receipt，因此 CI 与 tag Release 共用相同
  真实证据门；缺失、链接/多硬链接、不安全权限、timeout/rejected 伪装、版本/哈希漂移、CRLF 或缺失
  末尾 LF 均由独立夹具拒绝。只验证合成 package 而不检查真实 receipt 不满足本契约。

---

## Manus 验收编译输入闭包（v6.23.0 加固）

- `generate-manus-live-build-inputs.rb` 必须递归枚举 `IslandCore/Sources/IslandCore` 与
  `IslandCoreCLI/Sources/IslandCoreCLI` 的全部文件，而不是维护容易漏项的手写列表。两个 target
  只允许普通非链接 `.swift`；新增 Swift 文件自动进入 manifest，未知扩展、symlink/device、
  错误 owner、多硬链接、group/other 可写、单文件超过 4 MiB 或遍历超过 1,024 项全部失败。
- 固定输入还必须覆盖 `Package.swift`、`Package.resolved`、`VERSION`、版本验证器、transcript
  验证器、build-input 生成器与 wrapper 自身。所有文件通过 `O_NOFOLLOW` descriptor 锚定
  device/inode/owner/mode/nlink/size，读取前后与路径最终复验一致后才计算 SHA-256。
- `Package.resolved` 只接受 schema 3、1–256 个唯一规范 identity、完整 40 位 revision 与有界
  version。SwiftPM `workspace-state.json` 的 source-control dependency 集合必须与 pins 精确相等，
  每个安全 subpath/revision 逐项匹配；checkout 必须位于 T7 scratch 的普通非链接私有目录。
- 每个 dependency checkout 使用固定系统 Git、`env -i`、关闭 fsmonitor 和 hooks 复核 HEAD；
  tracked/untracked change、任意 ignored local file、Git submodule 或 HEAD/revision 漂移全部拒绝。
  这使远端 commit SHA 成为依赖源码内容地址，同时防止 SwiftPM 复用被本机改写的 checkout。
- 首次运行允许先用 `--only-use-versions-from-resolved-file` 在 T7 materialize 依赖；只有 bootstrap
  成功后才生成 `BUILD_INPUTS_BEFORE_BUILD.json`，随后再次执行 reviewed build。构建结束必须重生
  `BUILD_INPUTS_AFTER_BUILD.json` 并逐字节相等；`Package.resolved` 不得被自动重写。
- `TOOLCHAIN_BEFORE/AFTER_BUILD.txt` 同时绑定机器架构、Swift/Xcode/macOS 版本、解析后的
  `swiftc` SHA-256、SDK path 与 `SDKSettings.json` SHA-256。工具链漂移与源码/依赖漂移同样禁止
  进入 CLI 执行或 `ACCEPTED`。
- 正向夹具必须证明新增本地 Swift 文件改变 manifest；负向夹具至少覆盖本地 symlink、可写源码、
  target 内未知文件、dirty checkout、ignored dependency file、revision mismatch、链接
  `Package.resolved` 与链接 workspace state。静态文本命中不得替代真实临时 Git checkout。

---

## GitHub Workflow 内嵌 Shell 语法边界（v6.24.0 加固）

- PR CI 与 tag Release 的每个 `run:` step 必须经过 safe YAML 解析后逐项验证，不能用全文正则、
  注释命中或一次手工 tag 运行代替。`run` 只接受 1 byte–256 KiB 的 UTF-8 非空字符串；当前
  macOS workflow 只允许默认 Bash 或显式 `bash`/`/bin/bash` shell，其他 shell 在建立对应
  parser/fixture 前保持失败关闭。
- Workflow 本身通过 `O_NOFOLLOW|O_NONBLOCK` descriptor 读取，只接受当前用户拥有、单硬链接、
  不可 group/other 写、1 byte–1 MiB 的普通文件。读取前后 device/inode/owner/mode/nlink/size
  必须稳定；symlink、hard link、可写权限、NUL、无效 UTF-8、YAML alias 或危险类型全部拒绝。
- 语法验证只把完整 `${{ ... }}` GitHub expression 替换为固定非敏感占位符，再使用最小环境的
  `/bin/bash -n` 从 stdin 解析；不得执行 step、展开命令替换、读取 Secret 或调用仓库命令。
  未闭合 GitHub expression、Bash `if`/引号/heredoc 等语法错误必须在真实 tag、依赖解析和
  Release 凭据加载前失败。
- PR CI 的第一个 repository `run` step 与 tag Release 的 `Repository release gates` 都必须
  同时验证 `ci.yml` 与 `release.yml`，且调用位于 `Package.resolved` 检查、SwiftPM manifest
  求值和测试之前；tag 路径还必须早于凭据预检。Release foundation 必须运行独立攻击夹具，
  至少覆盖重复未闭合 `if`、未闭合引号、非字符串 `run`、未知 shell、未闭合 expression、
  可写文件、hard link 与 symlink。
- 该边界只证明 reviewed YAML 中 Bash step 的静态语法和文件输入安全；它不验证 GitHub expression
  业务语义、命令运行成功、runner image、远端 Actions 策略、tag 权限或 branch protection。
  完整商业 Release 仍需真实远端 CI/tag、签名、公证、Gatekeeper、资产与 provenance 验收。

---

## GitHub Workflow YAML 结构歧义边界（v6.25.0 加固）

- 在 `YAML.safe_load` 生成可能已经折叠重复键的 Ruby Hash 之前，验证器必须先遍历 Psych AST。
  输入必须包含 exactly one YAML document；空文档、多文档、alias、非标量 mapping key 与显式
  tagged key 全部失败关闭。
- 每层 mapping 同时记录原始 scalar 值和与 Psych safe-load 一致的受限类型+值身份，
  因而既拒绝 plain `on` / quoted `"on"`、两个 `run`，也拒绝解析后会碰撞的 `on` 与 `true`。错误只报告
  line 坐标，不回显 key、脚本或 Secret。
- AST 遍历固定最多 20,000 个 AST node、128 层 nesting；workflow 与单 step 的既有 1 MiB /
  256 KiB 上限继续生效。descriptor 读取前后除 device/inode/owner/mode/nlink/size 外，还必须
  比较 `mtime` 与 `ctime`，同尺寸并发改写不再被视为稳定输入。
- 攻击夹具从 8 类扩展到 15 类，新增“损坏脚本藏在前一个重复 `run`”、plain/quoted 同名 key、
  `on`/`true` resolved collision、第二个 YAML document、非标量 key、过深 nesting 与 node 洪泛。
  Release foundation 同时固定 AST 资源上限、metadata 稳定字段与低基数拒绝原因。
- 该边界关闭的是本地 safe-YAML 解释歧义；它仍不替代 GitHub 自身的 workflow schema、
  expression 运行时、真实 runner、分支/标签权限和管理员仓库策略验收。

---

## GitHub Workflow 有效 Shell 解析边界（v6.26.0 加固）

- 每个 `run:` 的 shell 必须按 GitHub 的继承优先级解析：
  `step > job defaults > workflow defaults > macOS 默认 Bash`。只读取 step 上的 `shell` 会漏掉
  `defaults.run.shell`，不得作为发布门禁。
- workflow/job 的 `defaults` 与 `defaults.run` 若显式存在必须是 mapping；`shell` 若存在必须是
  string。畸形结构、null/list/number、expression 与未知 shell 都失败关闭，不能通过 `.to_s`
  或忽略 defaults 静默降级。
- 当前审核集合只包含精确 `bash` 或 `/bin/bash`。`bash -c ...`、`bash {0}`、前后空白、换行、
  参数和任意自定义 template 即使以前缀 `bash` 开头也不在集合内，因为 template 自身可能携带
  未出现在 `run:` 正文中的 runner 命令。
- 验证器必须在使用继承值前先校验所有显式 workflow/job default；step 显式 shell 再按相同
  allowlist 校验。正向夹具覆盖 workflow → job → step 三层审核值，负向夹具覆盖 Bash command
  template、workflow 非 Bash default、job template default、畸形 defaults 与非字符串 step shell。
- 攻击夹具因此从 15 类扩展到 20 类。该静态边界仍不执行命令，也不证明 Bash fail-fast 参数、
  GitHub expression 业务语义或 runner 命令最终成功。

---

## 仓库脚本无执行语法闭包（v6.27.0 加固）

- Bash 会按完整 compound command 分段读取；真实临时脚本证明文件后半段存在未闭合 `if` 时，
  前半段写 marker 的命令仍会先执行，随后才 exit 2。Release 因此不能把“最终执行时自然报
  syntax error”当作无副作用保护；Ruby 虽会先整体编译，也进入同一预检闭包。
- `verify-repository-script-syntax.rb` 必须递归覆盖 `scripts/` 下全部 `.sh` / `.rb`。当前闭包是
  54 个 Bash 与 27 个 Ruby（包含验证器和夹具自身）；新增同扩展脚本必须自动进入，不维护
  容易漏项的手写列表。脚本总数最多 256，树最多 4,096 项，单文件最多 1 MiB。
- `scripts/` 全目录树拒绝 symlink、特殊文件、错误 owner 与 group/other 可写目录；脚本使用
  `O_NOFOLLOW|O_NONBLOCK` descriptor，只接受当前用户、普通、单硬链接、不可 group/other 写、
  可执行、有效 UTF-8、无 NUL 的文件，并在读取前后比较 dev/ino/uid/mode/nlink/size/mtime/ctime。
  全部目录 metadata 在解析结束后再次复验。
- `.sh` shebang 必须精确 `#!/usr/bin/env bash`，内容仅通过最小环境 `/bin/bash -n` stdin；
  `.rb` shebang 必须精确 `#!/usr/bin/env ruby`，内容仅通过最小环境 `/usr/bin/ruby -c` stdin。
  不从路径再次读取，不执行脚本，不回显 parser stderr 或源码正文。
- CI 的首个 repository `run` 与 tag 的 `Repository release gates` 都必须先完成两个 workflow
  验证，再运行仓库脚本闭包，随后才允许 Package/SwiftPM 解析；tag 还必须早于发布凭据加载。
- 正向夹具包含会写 marker 的合法 Bash/Ruby 内容并证明 marker 均不存在。11 类负向夹具覆盖
  Bash/Ruby 后置语法错误、unreviewed shebang、无执行位、可写权限、hard link、file/directory
  symlink、超限、NUL 与无效 UTF-8；Bash 损坏夹具同时证明前置 marker 未执行。
- 该闭包只证明仓库 Bash/Ruby 文件在冻结输入下可完整解析且预检无副作用；不证明脚本命令、
  Swift 脚本、外部工具、网络、runner image、签名、公证或发布结果成功。

---

## Swift 脚本 stdin-only Parse 闭包（v6.28.0 加固）

- `scripts/` 全量闭包必须同时包含 `.swift`，当前总数为 54 Bash + 27 Ruby + 9 Swift。
  `scripts/release/generate-sbom.swift` 会在 CI/tag 真实执行，其他品牌、菜单图标、声音与显示
  会话脚本也不得留在发布前语法盲区。
- Swift 文件继续使用同一 descriptor owner/type/mode/nlink/size/UTF-8/NUL 与目录稳定性边界；
  因 workflow 通过 `swift file.swift` 调用，Swift 文件不强制 executable。若首行存在 shebang，
  必须精确 `#!/usr/bin/env swift`；无 shebang 的普通 Swift 源也允许 parse，其他 `#!` 拒绝。
- 冻结字节只通过最小环境 stdin 交给 `/usr/bin/swiftc -parse -`。该模式不 type-check、link 或
  执行顶层代码；真实带 `Data.write` 副作用的正向夹具 exit 0 且 marker 不存在。
- Swift 后置损坏 `func` 夹具必须以固定 syntax 类别失败，且前置 marker 不存在；错误 shebang
  也失败。仓库脚本负向夹具由 11 类扩展为 13 类，三语言正向副作用均保持零执行。
- CI/tag 调用位置不变，因此三语言闭包仍在 Package/SwiftPM 解析前，tag 仍在发布凭据加载前。
  该 parse-only 证据不证明 Swift 脚本可 type-check、导入模块、运行或产生正确业务输出；实际
  SBOM 生成仍由后续 Release foundation、确定性双生成与资产门禁验证。

---

## 固定 create-dmg 发布工具边界（v6.88.0 加固）

- Tag Release 不得在签名证书或任何发布 Secret 加载后执行可变的 `brew install create-dmg`。
  `Repository release gates` 全部通过后、`Validate release credentials` 之前，必须仅由
  `scripts/release/prepare-pinned-create-dmg.sh` 准备工具。
- 上游输入固定为 `create-dmg` 1.3.0 的精确 commit
  `a2b71d0fda6d0df2a86dc7f67082d4d73e84c59f`；codeload 归档必须同时匹配 48,371 bytes 与
  SHA-256 `36577b966f16c12dd78d5bb5107c2ae3d069b044226b6ebbffa6a434ce142d0a`。
  同一个 `RDONLY|NOFOLLOW|NONBLOCK` descriptor 必须先完成 SHA-256，再 rewind 给 gzip/tar；
  size/hash 通过前不得调用 gzip/tar 等归档 parser，读取前后与路径复验的
  device/inode/owner/mode/nlink/size/mtime/ctime 必须一致。
- 归档形状固定为 28 个 tar record：首个且唯一的 global PAX record 必须逐字节绑定上述 commit，
  随后恰好 27 个 filesystem entry（17 个普通文件、10 个目录）。完整路径/type/size/count、
  74,666 filesystem logical bytes、74,718 total logical bytes、尾部零 padding 与四个 runtime
  文件 SHA-256 都必须精确匹配；link、special type、额外 PAX、路径逃逸、重复项和尾随 compressed
  data 全部拒绝。该 archive validator 必须在 tar 解包前运行，并在解包后、unlink 前再次运行。
- 归档只允许向 owner-only runner 临时目录解出主脚本、`.this-is-the-create-dmg-repo` sentinel、
  `support/template.applescript` 与 `support/eula-resources-template.xml`。最终闭包只能包含这
  4 个文件与 `support` 目录；目录固定 `0500`、主脚本 `0500`、其余文件 `0400`，并验证
  owner、普通文件/目录类型、单 hard link、每文件 SHA-256 与 `--pure-version == 1.3.0`。
- 四个 runtime digest 必须写入与 tool root 相邻、精确 369 bytes 的只读
  `runtime.SHA256`，其 SHA-256 固定为
  `35565e6e5d1086014d94fdddd246b8daa4b33bf3d6b9b49a1a9dac2d3a57526f`。Prepare step 只通过
  `GITHUB_OUTPUT` 传递由 `mktemp` 生成的绝对 `root`、`executable` 与 `manifest`，不得映射
  任何 `${{ secrets.* }}`；Package 内 runner 必须用 no-follow descriptor 重新绑定 manifest、
  目录闭包、metadata 和四个文件字节，并直接消费 verifier 返回的完整 frozen byte closure，不能
  在验证返回后重新打开 `${CREATE_DMG_EXECUTABLE}` pathname。
- `run-pinned-create-dmg.rb` 只允许 `--executable == File.join(root, "create-dmg")`，该参数只绑定
  workflow output，不得用于 reopen。它必须对 exact upstream bytes 做唯一的 support-discovery、
  AppleScript template 与 EULA template 三处变换，并将派生脚本固定为 22,095 bytes、SHA-256
  `46644c8da0d7eb1258e3ef05dd72967ca270d698df28d2aa6abd9402205e5beb`。派生脚本与两份 support
  resource 必须在 unlink 后才写入 owner-only anonymous FD，复验 `nlink == 0`、mode/size/bytes/hash，
  关闭 close-on-exec 后才以 `/bin/bash /dev/fd/N` 启动；support 也只能从继承 FD 完整读取。
- execution-boundary 夹具必须在 verifier 返回瞬间原子替换整个旧 tool 目录，并同时证明 runner
  仍输出审核过的 `1.3.0`、旧 pathname 已执行恶意 marker、两个 support FD 在 Ruby exec 后可由
  Bash 完整读取且 hash 匹配；错误 executable output、残余 resource pathname 或变换脚本语法失败
  都必须 fail closed。
- App 签名 keychain 只覆盖 App build、Developer ID codesign、公证/staple/验证和 notarized
  Production launch smoke。smoke 成功后必须立即删除该 keychain，并以 `security find-identity`
  确认同一个 `SIGNING_IDENTITY` 已不可访问；在此之前不得进入第三方 DMG packaging。
- 第三方 `Package DMG` 必须是完全无 Secret 的独立 step，`env` 精确只有上述三个 create-dmg
  output。它通过 `/usr/bin/env -i`、固定系统 PATH、`LC_ALL=C` 与私有 HOME/TMPDIR 执行上述
  descriptor-bound runner；直接执行 `${CREATE_DMG_EXECUTABLE}` 必须由结构化负向夹具拒绝。
  该命令非零必须失败，既有普通文件或 dangling symlink 均不得
  作为输出；新 DMG 还需通过 owner/nlink/mode 与 `hdiutil verify`。unsigned DMG SHA-256 只经
  `unsigned_dmg` step output 传递，后续签名前必须重新匹配同一普通、单链接、`0600` 文件。
- `Package DMG` 成功后才可重新导入同一 P12；`Setup DMG signing keychain` 必须证明新发现的
  `DMG_IDENTITY == SIGNING_IDENTITY`，随后独立 `Sign + notarize DMG` 才可接收 Apple 公证凭据。
  DMG codesign、公证、staple 与验证全部成功后，必须在 ZIP、Sparkle、attestation 与 GitHub
  Release action 之前立即删除第二个 keychain，并再次证明该 identity 已不可访问。最终
  `if: always()` cleanup 只是失败路径兜底；可变 Homebrew formula 或 PATH fallback 不得重新
  进入工作流。
- 该边界约束的是 tag runner 的第三方打包工具字节与凭据时序。它不证明 Finder AppleScript、
  `hdiutil`、codesign、公证或生成 DMG 的内容正确，也不证明 GitHub 远端策略、Developer ID
  真实凭据或已发布资产已验收；这些仍由后续 Release 资产、签名、远端控制与人工发布验收闭合，
  不得据此宣称产品已经完整商业可发布。

---

## App 构建输出与原子发布边界(v6.18.0 加固)

- `BUILD_DIR` 是允许 QA 指向 T7 的外部输入，但不能因此成为递归删除入口。构建前必须经
  `app-build-output-boundary.rb prepare` 解析为当前用户拥有、非链接、不可 group/other 写的
  最终目录，同时验证直接父目录；禁止文件系统根、仓库/祖先、仓库内 `build/` 之外的位置、
  缺失多级父目录和不安全目录。相对路径固定以仓库根为基准，外部 T7 绝对路径继续支持空格。
- App 必须先在 `BUILD_DIR/.dev-island-build.*` 的 `0700` 私有 sibling 中完整组装、依赖闭包
  验证并签名；最终 `BUILD_DIR/Dev Island.app` 在此之前不得删除或出现半成品。发布 helper
  只接受精确 production/Performance QA Bundle ID、`APPL`、`IslandApp` executable、owner/mode/
  nlink 安全的 plist/可执行文件和完整有效签名。既有目标若是 symlink、普通文件、冒名 App、
  未签名/损坏 App 或错误 owner/mode，必须在任何 rename 前失败并保留原字节。
- 替换一个已验证的旧 Dev Island 时，旧代际先在同目录原子 rename 到随机私有 backup，
  新代际再同文件系统 rename 到最终名，并在每个边沿同步目录 metadata、复核 inode 与签名；
  中途失败优先恢复旧代际，无法证明恢复安全时保留两代路径供人工恢复，不做进一步删除。
  成功后才删除已验证 backup 和空 staging root。`build-app.sh` 禁止恢复对最终 `${APP}` 的
  直接 `rm -rf`。

---

## 决策响应回执与 Animation Hitches 分段证据（v6.74.0）

- Action Request 的生产 response 仍必须先同步到 `TaskStore`/Agent，UI 回执不得增加 Hook 延迟。
  但对应 session 的回执占位必须在同步移除 request 之前以无动画 transaction 建立，防止中间状态
  构造完整 `TaskCard`。response 返回 false 时必须无动画删除同一 receipt ID；成功时只允许保留
  既有 0.9 秒 UI cadence，新的同 session request 仍优先于回执。
- Performance fixture 的 decision marker 必须同时包含 monotonic `uptime=` 与 epoch `wallUnix=`。
  queued/resolved 各只允许一个，resolved 必须晚于 queued 且两者都必须落在 trace duration 内；
  `wallUnix` 对齐失败时只能使用声明更大 uncertainty 的旧日志 fallback，不能把估算写成精确对齐。
- `summarize-animation-hitches.rb` 必须分别读取 TOC、Animation Hitches、SwiftUI update 与
  Potential Hangs 导出，并分别报告 App-attributed frame、render/GPU-only frame、App update、
  root update row 与 hang。startup/resolved/steady/recording-tail 不得混算；trace 外数据必须显示
  excluded count。整段录制最大值不能替代 resolved interaction window 结论。
- XML 与日志输入拒绝 symlink、DTD/entity、缺失/循环 ref、负数或非有限 timing、重复/错序 marker；
  JSON 输出必须 exclusive create，拒绝预存在文件与链接。分析器自测和 Performance CI 静态门禁
  必须同时固定 marker 字段、回执预留顺序、stale rollback 与三类 response 共用路径。
- accepted 当前源码证据必须真实完成动作、精确命中本次 App、完整覆盖 resolved window，并保留
  raw trace、四份导出、App log、JSON 与 SHA-256。动作发生在 trace 外、命中 stale/idle 实例、
  锁屏未完成或只有旧源码的样本只能标为 rejected/incomplete/partial，不能升级为当前体验结论。
- 当前 Permission Deny accepted trace 证明 resolved App update 从 132.257 ms 降至 21.238 ms，
  `>33/50/100 ms` 从 `2/2/1` 降为 `0/0/0`，54.802 ms interaction delay 消失；仍保留一帧
  34.722 ms App-attributed lifetime，因此契约不允许宣称“零慢帧”。Question 与 Plan 必须各自补齐
  fixed-source unlocked trace 后才能完成整组决策面帧级验收。

---

## 变更记录

| 日期 | 版本 | 描述 | Commit |
|---|---|---|---|
| 2026-04-24 | v1.0.0 | 初始版本 | `[S][contract] feat(store): initial TaskStore API` |
| 2026-07-28 | v1.1.0 | Claude Code 本地连接器(TaskStore API 不变) | `[S] feat(claude-code): local hooks connector` |
| 2026-07-28 | v1.2.0 | Codex 本地连接器:`CodexHooksInstaller`(API 形态同 `ClaudeHooksInstaller`,写 `~/.codex/hooks.json`),tasks 新增 `source == "codex"`,其余约定同 claude-code | `[S] feat(codex): local hooks connector` |
| 2026-07-29 | v1.3.0 | Cursor 本地连接器:`CursorHooksInstaller`(写 `~/.cursor/hooks.json`,扁平 entry + 顶层 `version: 1`),tasks 新增 `source == "cursor"`;仅订阅 fire-and-forget 事件(sessionStart / beforeSubmitPrompt / stop / sessionEnd),无 waiting 态;`stop.status == "error"` 映射为 failed | `[S] feat(cursor): local hooks connector` |
| 2026-07-29 | v1.4.0 | **契约冻结(J1/J2)**:新增 `TaskTransition` 结构与 `TaskStore.onTaskTransition` 回调(状态跃迁事件,通知投递用);新增 `TaskStore.jumpToTask(id:)`(app 级激活,失败回退 openTaskInBrowser 行为)。`openTaskInBrowser` 保持不变 | `[S][contract] feat: task transitions + jump-to-task` |
| 2026-08-03 | v1.5.0 | **契约冻结(J3)**:声明式连接器框架 — 新增 `LocalAgentRegistry` / `LocalAgentDescriptor` / `LocalHooksInstaller`(表驱动:设置行、hook 安装、服务器路由、跳回目标全部由注册表生成);三个旧安装器 enum 降级为兼容壳;三个旧连接器 actor 删除,统一为 `LocalAgentConnector`。`TaskStore` 公开 API 不变 | `[S][contract] feat: declarative local-agent framework` |
| 2026-08-05 | v1.5.1 | Gemini CLI 连接器提案；当前注册表未包含该连接器，仍列为 Roadmap Wave 1 | `[S][contract] proposal(gemini): deferred connector` |
| 2026-08-09 | v1.6.0 | **跨 agent 任务身份**:新增 `TaskIdentity(source,id)`、`AgentTask.identity`、source-aware open/jump API 与直接接收 `AgentTask` 的入口;旧裸 id API 保留兼容,遇到歧义拒绝执行;通知/列表/跳回统一使用复合身份 | `[S][contract] fix: source-aware task routing` |
| 2026-08-26 | v1.7.0 | **Codex / Claude Code 岛内审批**:新增 `AgentActionRequest` 队列、`TaskStore.pendingActionRequests`、`respond(to:decision:)`；两者的 `PermissionRequest` 均按各自官方 Hook 协议双向返回 Allow/Deny，未验证的交互继续保持 observe-only 或 lifecycle-only | `[S][contract] feat: verified bidirectional local approvals` |
| 2026-08-26 | v1.8.0 | **Claude Code 岛内问答**:新增结构化问题/选项/答案模型与 `respond(to:answers:)`；`PreToolUse` 精确匹配 `AskUserQuestion`，支持 1–4 个单选/多选、原生界面回退、严格答案校验与官方 `updatedInput` 响应 | `[S][contract] feat: answer Claude questions in island` |
| 2026-08-26 | v1.9.0 | **Gemini CLI Preview**:注册表新增 `geminiCLI`；五个低频 Hook 映射 lifecycle 与 `ToolPermission` Waiting，能力固定 observe-only；用户级配置 merge/更新/卸载沿用保守编辑器，真实 v0.57.0 验收前不得升级为已支持 | `[S][contract] feat: Gemini CLI preview connector` |
| 2026-08-26 | v2.0.0 | **本地监听器健康契约**:新增 `LocalHookServiceStatus`、`TaskStore.localHookServiceStatus` 与 `retryLocalHookService()`；私有 token readiness route 证明端口确由当前进程持有，端口冲突进入有界重试并可在 Settings 手动恢复 | `[S][contract] feat: observable local-hook health` |
| 2026-08-26 | v2.1.0 | **本地历史删除控制**:新增 `clearStoredTaskHistory()`；同一 SQLite 事务清空任务与进度表但保留当前 Running/Waiting 内存会话，Settings 必须经破坏性确认后调用并呈现失败状态 | `[S][contract] feat: clear persisted task history` |
| 2026-08-26 | v2.2.0 | **只读 Session History**:新增独立历史状态与 `refreshStoredTaskHistory()`；SQLite 任务主键从 vendor-local `id` 原子迁移为 `(source,id)`，本地 Agent 快照进入持久化；历史读取严格禁止写回 `tasks`、触发通知或参与灵动岛优先级 | `[S][contract] feat: source-safe local session history` |
| 2026-08-26 | v2.3.0 | **全局本地 Hook 清理**:新增 `LocalAgentHookMaintenance` 与 Settings 破坏性确认；全部配置先准备再写，中途失败做不覆盖外部编辑的安全回滚；单个/批量卸载均支持混合 handler 的手术式移除，损坏受管配置失败关闭 | `[S][contract] feat: transactional managed-hook removal` |
| 2026-08-26 | v2.4.0 | **Claude Code 计划审阅**:新增 `AgentPlanReview`、`.planReview` 请求/响应与能力标记；`PreToolUse(ExitPlanMode)` 在岛内渲染 Markdown，批准时无损回传完整注入输入，拒绝或原生回退遵循官方响应格式；异常与超限载荷失败中立 | `[S][contract] feat: review Claude plans in island` |
| 2026-08-26 | v2.5.0 | **精确终端/tmux 跳回**:受管终端 Hook 附带经过双重校验的宿主、TTY 与 tmux pane 元数据；`AgentTask.jumpContext` 仅在活跃内存存在；点击任务优先激活真实终端，tmux 通过无 shell 参数调用选择原始 window/pane，失败保持旧回退行为 | `[S][contract] feat: precise local session jump context` |
| 2026-08-26 | v2.6.0 | **本地只读用量/额度基础**:新增内容隔离的 Codex 数字快照模型与有界 rollout reader；Settings 默认关闭、按需刷新、不联网、不读取 Keychain，不存在或过期数据明确显示且不推测额度 | `[S][contract] feat: opt-in local usage insights` |
| 2026-08-26 | v2.7.0 | **Qwen Code Preview**:固定 v0.22.0 官方 Hook 契约；新增七类低频状态、双向 PermissionRequest、毫秒级 Hook timeout、Preview UI 标签、官方 Logo、配置安全/回环测试与真实 CLI 验收门禁 | `[S][contract] feat: Qwen Code preview connector` |
| 2026-08-26 | v2.8.0 | **GitHub Copilot CLI Preview**:固定 v1.0.80 与官方 Hook reference；独立 version-1 用户 Hook 文件订阅六类低频状态，权限/输入提醒固定隐私文案且 observe-only；增加官方 Copilot mark、配置保全、真实 command→loopback 测试与验收门禁 | `[S][contract] feat: Copilot CLI preview connector` |
| 2026-08-26 | v2.9.0 | **Kimi Code CLI Preview**:固定当前 npm v0.38.0 默认 v2 Hook 契约；八类低频生命周期/权限注意力保持 observe-only；新增 parser 校验、字节保全的 TOML managed-block 编辑器，JSON+TOML Disconnect All 事务、官方 Logo、隐私/回环测试与真实 CLI 验收门禁 | `[S][contract] feat: Kimi Code preview connector` |
| 2026-08-26 | v3.0.0 | **商业 License 验证与断开式存储底座**:登记 `CommercialLicenseDocumentStore` 与错误模型；唯一公开导入路径强制 verify-before-save，共用 32 KiB 上限，保存到 `commercial_license_v1` 的 `WhenUnlockedThisDeviceOnly` 非同步 Keychain；App 仍零 trust anchor、零实例化、零收费路径 | `[S][contract] feat: fail-closed commercial license storage foundation` |
| 2026-08-26 | v3.1.0 | **休眠/唤醒监听恢复契约**:生产重试仍为 5 次与 5/10/15/20 秒；重试耗尽后系统唤醒可重新监听，健康监听器收到 wake health check 时保持幂等；加入毫秒级确定性恢复测试与 CI 防漂移门禁 | `[S][contract] test: prove local-hook wake recovery` |
| 2026-08-26 | v3.2.0 | **运行日志隐私与 Manus 传输崩溃加固**:Unified log 移除 key、ID、URL、路径、cloudflared 输出及原始 Error；Manus API 用低基数操作名记录状态，非 HTTP 响应失败关闭为 `invalidResponse`；设置页错误文案不再反射 provider 内容；CI 锁定以上边界 | `[S][contract] security: minimize runtime diagnostics` |
| 2026-08-26 | v3.3.0 | **Manus realtime 生命周期可靠性**:进程与已注册 webhook 组成原子健康状态；注册/URL/wake/heartbeat 失败清理 transport 并显式降级 polling-only；polling 成功不得伪装 realtime connected；生命周期代际删除晚到注册，加入确定性 actor 测试与 CI 防漂移门禁 | `[S][contract] fix: make Manus realtime recovery transactional` |
| 2026-08-26 | v3.4.0 | **Manus polling 生命周期可靠性**:`PollingFallback` 改为 actor + 代际取消；stop/restart 后抑制不响应取消的晚到 fetch，TaskStore 对 snapshot/status/webhook 做第二层 service-generation 校验；401 显式失效 key、断开连接并关闭 realtime；加入确定性回归与 CI 门禁 | `[S][contract] fix: suppress stale Manus polling callbacks` |
| 2026-08-26 | v3.5.0 | **Manus 账户配置事务**:Connect/Disconnect 独立 configuration generation，latest-operation-wins；换 key 先 detach/await 旧服务；Disconnect 改为 async throws，Keychain 删除失败仍停止网络但不谎报 credential 已移除；增加真实 TaskStore 并发、晚到快照、401 与删除失败测试 | `[S][contract] fix: serialize Manus account ownership` |
| 2026-08-26 | v3.6.0 | **Manus 官方 Webhook v2 协议**:按官方当前文档改为 `api.manus.ai/v2` 注册/删除/公钥、双 Header、时间戳+完整 URL+raw-body hash 验签、300 秒重放窗、event ID 去重与真实 `event_type/task_detail` 结构；旧猜测协议被测试拒绝，Release 仍由真实账号验收 gate 关闭 | `[S][contract] security: implement official Manus v2 webhook protocol fail closed` |
| 2026-08-26 | v3.7.0 | **注意力与审阅呈现语义**:Waiting/Failed 继续长期领先；Completed 在并发 Running 前只保留 15 秒结果窗口，之后回到活跃工作但不删除完成记录；Plan Review 保留标题、列表、段落与代码块结构；Action header 使用稳定本地 Session 指纹，不显示原始 vendor ID | `[S][contract] fix: preserve focus after transient results` |
| 2026-08-26 | v3.8.0 | **只读本地 Hook 健康诊断**:新增 registry-driven current/update-required/disconnected 快照；模型不含配置路径或内容，CLI、Welcome 与 Support 复用同一判断且不得产生配置写入 | `[S][contract] feat: expose privacy-safe local-hook health` |
| 2026-08-26 | v3.9.0 | **注意力队列与稳定排序**:人工请求按到达队列稳定置顶；Waiting/Running 心跳不得重排行，Completed 继续受短结果窗口约束；窗口级快捷键只归最早人工请求且 Escape 永远不作决策 | `[S][contract] fix: keep multi-session attention order stable` |
| 2026-08-26 | v4.0.0 | **Provider-neutral 商业激活核心**:新增脱敏有界激活码、无 endpoint transport 契约与 actor 激活服务；无 trust anchor 时 transport 零调用，latest-operation-wins/取消阻止晚到响应，所有文档只经 verify-before-save Keychain 边界，App 仍零实例化 | `[S][contract] feat: add fail-closed commercial activation core` |
| 2026-08-26 | v4.1.0 | **Manus 真实验收工具安全边界**:CLI 改为显式子命令与 TTY 隐藏输入；checklist 区分 signed registration probe 和同运行任务生命周期；取消/超时/失败统一进入不取消清理，无法证明删除时要求人工复核；cloudflared 使用最小子进程环境，Release gate 保持关闭 | `[S][contract] security: make Manus live acceptance transactional` |
| 2026-08-26 | v4.2.0 | **人工介入界面去重与会话语言统一**:审批、问题与 Plan Review 在待处理时用单一决策面替代重复 TaskCard，同时保留安全 Session 指纹和会话标题；展开面板总数统一为 session(s)；Settings 导航与更新状态收敛为单行低噪音布局 | `[S][contract] polish: focus action surfaces and settings` |
| 2026-08-26 | v4.3.0 | **商业激活码秘密内存生命周期**:激活码从可复制且不清零的 `Data` 改为值拷贝共享的专用不可变缓冲区；最后引用释放时使用 `memset_s` 防优化清零，外部仍只有非逃逸 scoped bytes，商业模式继续保持零 trust anchor、零 transport、零 UI | `[S][contract] security: erase activation code memory on release` |
| 2026-08-26 | v4.4.0 | **Codex Hook 信任感知状态**:注册表新增 vendor-owned 激活要求；精确配置存在但 trust 无法由文件证明时使用 `configured`，Welcome、Settings、CLI 与 Support 不再误报 Connected，并固定 `/hooks` 人工确认边界 | `[S][contract] fix: distinguish Codex config from Hook trust` |
| 2026-08-26 | v4.5.0 | **Codex 官方 App Server 只读信任探针**:只执行 OpenAI 签名 App 内嵌二进制并有界调用 `hooks/list`；所有精确 Dev Island Hook 均启用且 `trusted/managed` 才从 `configured` 提升为 `connected`，失败与 schema drift 保守降级；原始输出不落盘、不记录并尽力清零 | `[S][contract] feat: verify Codex Hook trust read-only` |
| 2026-08-27 | v4.6.0 | **真实本地链路准备度预检**:新增显式 `local-live-readiness`；精确固定 Claude/Codex 实测版本，检查 managed Hook、Codex trust 与 challenge-response listener，输出仅低基数状态且不写配置；真实 Agent 会话仍保留人工验收门 | `[S][contract] feat: add read-only local live-readiness preflight` |
| 2026-08-27 | v4.7.0 | **OpenCode Preview**:固定 `1.18.23` 插件/Event 契约；七类隐私最小事件观察、1 秒 fail-open loopback、observe-only 权限注意力；新增完整文件 ownership、`0600`、symlink/超限/碰撞拒绝及 Disconnect All 删除回滚边界，真实 CLI 目录未修改且验收前不得升级 Stable | `[S][contract] feat: OpenCode preview connector` |
| 2026-08-27 | v4.8.0 | **Manus 入站内容与任务目的地边界**:API/Webhook 在进入 UI/SQLite 前限制响应、列表与展示字段，task URL 必须精确绑定 `https://manus.im/app/<same-id>`；Launch Services 二次验证 Manus 官方页或真实普通本地目录，文件/App/custom scheme/跨源与歧义 ID 均零调用 | `[S][contract] security: validate remote content and task destinations` |
| 2026-08-27 | v4.9.0 | **多 Agent 复合身份合并**:StateReconciler 的 polling/Webhook/本地 snapshot 全部使用 `(source,id)`；同 ID 的不同 Agent 独立，snapshot 只接受声明 source，重复身份稳定合并最新值，不再存在裸 ID 误更新或重复键崩溃 | `[S][contract] fix: isolate task state by composite identity` |
| 2026-08-27 | v5.0.0 | **岛内动作队列资源边界**:同步请求默认 90 秒/绝对 120 秒，全局 32 项/单会话 4 项；溢出中立回退且不保留 continuation；标题、消息、详情、问题和选项采用字符+UTF-8 双重限界并覆盖恶意 combining-grapheme | `[S][contract] security: bound local action queue resources` |
| 2026-08-27 | v5.1.0 | **本地会话与历史资源边界**:所有 Local Hook 共用身份/路径/展示文字限界；每连接器最多 128 个实时会话并优先保留人工阻塞；SQLite 打开和写入时确定性保留最新 5,000 个任务/20,000 条进度并清理孤立内容，活跃岛不受历史修剪影响 | `[S][contract] security: bound local sessions and persisted history` |
| 2026-08-27 | v5.2.0 | **SQLite 历史行内容信任边界**:新任务/进度按字段拒绝超限并保持批量事务原子；打开旧库时 SQL 侧清理异常类型/字节，历史读取在 materialize 前复用谓词；正常写入避免重复全表内容扫描 | `[S][contract] security: validate persisted rows before materialization` |
| 2026-08-27 | v5.3.0 | **SQLite 文件生命周期边界**:App-owned 最终目录/主库/sidecar 固定 `0700/0600`；链接、非普通文件、错误 owner 与多硬链接在 SQLite 访问前拒绝；目录+主库双 no-follow descriptor、`openat/fstatat` sidecar 操作与 device+inode 复验保护 schema、修剪和 Clear History 不被路径替换重定向 | `[S][contract] security: anchor private SQLite file ownership` |
| 2026-08-27 | v5.4.0 | **SQLite 运行期文件边界**:目录/主库 descriptor 与 Connection 同寿命；所有读写、修剪与 Clear History 前后复验，提交前漂移触发事务回滚，读取后漂移不返回内容；首次运行期失败关闭 store 并让后续调用持续 unavailable | `[S][contract] security: retain and enforce SQLite anchors at runtime` |
| 2026-08-27 | v5.5.0 | **Settings 主路径与微交互**:本地 Agent 分组固定领先可选 Manus，readiness 操作回到首屏；八个连接器副标题补齐审阅简中；Welcome/决策/设置按钮统一 hover/press 与 Reduce Motion，禁用按钮不再显示可点击指针，Quit 回归中性命令 | `[S][contract] polish: make setup local-first and interactions coherent` |
| 2026-08-27 | v5.6.0 | **Managed Hook 配置文件事务边界**:JSON/TOML/standalone plugin 共用 descriptor-backed 4 MiB/256 KiB 有界读写；安全解析配置目录 symlink，拒绝目标 symlink/hard link、非普通文件、错误 owner、不安全父目录与并发字节漂移；同目录私有临时文件、权限保留、file+directory fsync、原子 rename 与 snapshot-aware Disconnect All 回滚由攻击回归和 CI 固定 | `[S][contract] security: anchor managed Hook configuration writes` |
| 2026-08-27 | v5.7.0 | **Managed Hook 最终竞态闭合**:缺失目标继续使用排他 rename；已有目标改为原子交换后验证 displaced snapshot，删除改为 quarantine 后验证再 unlink；最终窗口中的外部替换会被无覆盖恢复，无法证明恢复安全时保留字节并失败关闭，确定性攻击回归与 CI 固定该 lost-update 边界 | `[S][contract] security: close managed config final races` |
| 2026-08-27 | v5.8.0 | **Cloudflared 有界子进程边界**:Quick Tunnel 启动改为独立持续 stderr drain、1 MiB 输出上限和不依赖 run loop 的硬 timeout/cancel；分片 URL 精确验证，成功后继续零保留排空；PATH 不再执行 `which` 且拒绝不安全 executable，停止在短 SIGTERM 宽限后 SIGKILL；5 项进程边界回归（其中 3 项启动真实子进程）与 CI 固定 | `[S][contract] security: bound cloudflared startup and shutdown` |
| 2026-08-27 | v5.9.0 | **tmux 跳回有界子进程边界**:移除 `Process.waitUntilExit` 与退出后才读 stdout 的死锁路径；共用 POSIX runner 在运行中 nonblocking drain、4 KiB 限界、monotonic deadline、独立进程组 TERM→KILL，tmux executable 解析后校验 owner/mode，子进程使用不含 HOME 的最小环境；挂起、忽略 TERM、无限输出与可写 executable 攻击回归由 CI 固定 | `[S][contract] security: bound precise tmux navigation` |
| 2026-08-27 | v6.0.0 | **本地 Codex Usage 文件资源边界**:候选扫描固定 8,192 entry 上限并仅保留 top-N，不再先累计完整目录；rollout 使用 `O_NOFOLLOW` descriptor 校验 owner/type/mode，以首次 `fstat` 锁定的 offset/length 执行 exact `pread`，并发增长不能突破 4 KiB–2 MiB 配置上限；增长、枚举压力与可写文件攻击回归由 CI 固定 | `[S][contract] security: bound local usage file reads` |
| 2026-08-27 | v6.1.0 | **Manus WebhookServer 所有权与健康边界**:本地服务必须在 2 秒内通过随机 loopback challenge 后才能启动 tunnel/注册远端 webhook；共享探针禁止 redirect/代理/Cookie/缓存并按精确 Content-Length 流式读取最多 256 字节；注册前后和 heartbeat 重验服务，失效即删除 webhook、停止进程并降级 polling-only；端口占用、启动失败与运行中死亡回归由 CI 固定 | `[S][contract] reliability: prove local webhook readiness before registration` |
| 2026-08-27 | v6.2.0 | **PR CI 脱敏诊断文件边界**:品牌资产纳入 11 道稳定门禁与首失败定位；checkout 不持久化 token，artifact 使用随机私有根；原始 security/test 日志以 no-follow descriptor 校验 owner/type/mode/nlink、精确有界 `pread` 与前后 metadata 稳定性，symlink/hard-link/超限/变化输入只产生 schema-v2 低基数 `sourceStatus`，不让诊断包消失 | `[S][contract] security: harden failed-run CI diagnostics` |
| 2026-08-28 | v6.3.0 | **本地 Agent 双向 Hook 顺序闭环**:同一同步 payload 的 lifecycle snapshot 必须 await 提交后才能排队 action，消除 Allow/Deny 后旧 Waiting 晚到覆盖 Running 的竞态；路由逐字绑定 descriptor source，并在 lifecycle 可解码时绑定同一 session；真实 loopback→TaskStore→Codex allow JSON 回归与错源/错会话拒绝由 CI 固定 | `[S][contract] fix: serialize lifecycle before local action decisions` |
| 2026-08-28 | v6.4.0 | **本地 Agent lifecycle 跨请求顺序与容量**:每个 source 使用单一有界 drain，pending passive 同 session 合并、跨 source 独立；队列固定 256，洪泛丢弃 passive，action 优先淘汰 passive/全 action 时中立失败；真实 HTTP 跨请求 barrier、串行/并行与容量回归由 CI 固定 | `[S][contract] reliability: bound and serialize local lifecycle delivery` |
| 2026-08-28 | v6.5.0 | **自动更新运行期状态与失败关闭**:Sparkle 改为 `startingUpdater: false` + throwing start；五态低基数状态机、单次启动、手动检查去重、失败控件隔离与 generation 晚到抑制由注入 runtime 回归固定，keyless build 保持零构造 | `[S][contract] reliability: make authenticated updater lifecycle observable` |
| 2026-08-28 | v6.6.0 | **自动更新发布私钥进程边界**:tag workflow 只经仓库包装器调用 Sparkle；私钥转入非导出缓冲后清空全部已知发布凭据环境，`env -i` 子进程只从 stdin 接收 key；真实 fake-generator 证明 child/parent env、argv/log 零泄漏，并拒绝缺 key、危险 tag 与 symlink generator | `[S][contract] security: isolate Sparkle signing secret from child environment` |
| 2026-08-28 | v6.7.0 | **Settings 控件节奏与视觉证据**:五个 switch 行统一为全宽左文案/右控件双列布局，跨中英文不再漂移；DEBUG 快照显式使用产品版本，新增 English 四页与简中六页当前源码证据，且不把静态截图误作 VoiceOver/动效验收 | `[S][contract] polish: align settings controls across languages` |
| 2026-08-28 | v6.8.0 | **本地 CLI 版本探针调度稳定性**:复现并拆分“快速退出 stdout/waitpid 竞态”与测试机调度延迟；新增 `check-failed`，将 spawn/timeout/超限/非零退出与真实版本漂移分离，避免瞬时负载误报兼容性复核；生产 2 秒边界不变，挂起测试继续 50 ms，快速回归使用 5 秒隔离预算且总耗时受限；PR CI 同一二进制额外执行 20 轮/240 子进程并保持诊断全量计数权威 | `[S][contract] reliability: distinguish probe failure from version drift` |
| 2026-08-28 | v6.9.0 | **本地准备度重试语义与视觉层级**:`check-failed` 不再伪装成“剩余设置项”，唯一失败时使用独立双语标题、静态 cyan ring 与单一 Check again CTA；已知 listener/安装/版本/Hook/trust 阻塞优先于 transient retry；新增双语当前源码截图与优先级回归，oversized-output 测试移除调度敏感的 1.5 秒假设 | `[S][contract] polish: distinguish retry from setup attention` |
| 2026-08-28 | v6.10.0 | **tmux 后台子进程清理调度稳定性**:生产 2 秒回退边界不变并新增直接回归；descendant/无限输出测试使用 5 秒隔离预算，避免把临时 fixture 的首次调度误作产品清理失败；PR CI 同一二进制追加 20 轮 descendant 清理，日志保持私有且不污染权威 XCTest 总数 | `[S][contract] reliability: isolate tmux cleanup from scheduler delay` |
| 2026-08-28 | v6.11.0 | **解锁性能证据与显示会话判定**:独立 CoreGraphics 探针在 lock key 省略时要求 console+login 双证明；确定性 fixture 覆盖 locked/unlocked/omitted/unknown，sampler 在 warmup、每秒样本和结束时持续复核并记录初末状态；四场景解锁 CPU/RSS、3 分钟展开态、Time Profiler 与真实截图首次形成可审计基线 | `[S][contract] reliability: validate unlocked performance evidence continuously` |
| 2026-08-29 | v6.12.0 | **连续开合帧节奏与 Instruments 隔离**:新增 20 会话 800 ms 连续开合夹具与异步 marker；Animation Hitches 按 update/render/GPU/compositor 分层留证；macOS Power Profiler 不支持时改用 Activity Monitor CPU/唤醒增量且禁止冒充电池结论；Leaks 仅给隔离 QA 主 App 配置 get-task-allow，Sparkle helper/XPC 与生产全部反向拒绝；锁文件构建与 T7 空格路径纳入门禁 | `[S][contract] performance: prove transition pacing with isolated instrumentation` |
| 2026-08-29 | v6.13.0 | **真实决策窗口焦点与可访问结构**:borderless 岛保持自动展开不抢焦点，仅直接点击可见轮廓后成为 key，收起释放；AX 窗口名固定为 Dev Island；问答草稿抽成确定性状态模型并完整覆盖单选/多选/Back/Submit；Increase Contrast 与 Reduce Motion 分支补齐，且明确 AX/截图不等于 VoiceOver 合规 | `[S][contract] accessibility: make island decisions keyboard-reachable without stealing focus` |
| 2026-08-29 | v6.14.0 | **本地 Hook 浏览器请求边界**:全部 `/hooks/<source>` 路由要求无 Origin 且携带精确 `X-Dev-Island-Hook: v1`；curl 与 OpenCode 插件统一生成，旧配置显示需更新；缺失/错误 Header、Origin-bearing 请求与未授权 CORS preflight 均保持 `{}` 且不交付 lifecycle/action | `[S][contract] security: require a non-simple header on local hook writes` |
| 2026-08-29 | v6.15.0 | **本地 Hook 跨用户授权边界**:每个监听 epoch 轮换 256-bit 随机凭据并常量时间校验；凭据只存在于 owner-only `0600`/128-byte Header 文件与瞬时内存，curl 通过 `-H @file`、OpenCode 有界读取，配置/插件/argv 均不含值；文件或随机源失败时拒绝启动无授权 listener，旧 epoch 凭据立即失效 | `[S][contract] security: authenticate local hook writes across macOS users` |
| 2026-08-29 | v6.16.0 | **SwiftPM 锁文件产物边界**:CI/Release 先证明 `Package.resolved` 已跟踪且非链接；完整测试与 Universal 双架构构建全部强制只用锁定版本，构建前后绑定同一 SHA-256；缺失、链接、空/超限、过期或构建中漂移均失败，离线双 tag 夹具证明默认 resolve 会改锁而强制模式保持原字节拒绝 | `[S][contract] security: bind tests and App artifacts to Package.resolved` |
| 2026-08-29 | v6.17.0 | **产品版本到发布产物边界**:新增共享 descriptor-backed `VERSION` 验证器并接入 App、CI/tag、Cask、清单及下载者工具；移除缺失时 0.1.0 回退，固定单行 numeric triple/权限/owner/nlink/大小，拒绝链接、前导零、suffix、多行与 sed/path 注入；prerelease 在单独冻结 Apple/Sparkle build-number 策略前保持 fail closed | `[S][contract] release: validate one canonical product version before build` |
| 2026-08-29 | v6.18.0 | **App 构建输出与原子发布边界**:移除对最终 App 的直接递归删除；BUILD_DIR 先固定 owner/mode/location，完整 App 在私有 sibling 暂存中验证签名后才 rename 发布；既有 symlink/文件/冒名或损坏 App 在任何替换前失败，已验证旧代际使用同目录 backup/恢复协议 | `[S][contract] release: stage and atomically publish verified App bundles` |
| 2026-08-29 | v6.19.0 | **Codex App Server stdio 进程边界**:Hook trust 探针移除 `Process`、reader thread 与 semaphore；POSIX 独立进程组用 nonblocking stdin/stdout、poll、monotonic deadline 和运行中 2 MiB 限界完成单次请求，提前退出不再白等，response/超时/超量均 TERM→KILL 完整 descendant group 并回收直接子进程 | `[S][contract] reliability: bound Codex App Server stdio lifecycle` |
| 2026-08-29 | v6.20.0 | **系统 sleep/wake 顺序屏障**:TaskStore 保留 Manus suspend task 并在 wake 前 await；power/service 双代际拒绝新 sleep、Disconnect 与 shutdown 后的晚到恢复，重复 wake 不重启 tunnel；4 项确定性竞态回归与 20 轮 CI 稳定性固定 | `[S][contract] reliability: serialize sleep before wake recovery` |
| 2026-08-29 | v6.21.0 | **Tag Release checkout 凭据隔离**:release checkout 禁止持久化或覆盖 token；safe-YAML 验证器在依赖解析与仓库代码前重验步骤顺序，唯一显式 GITHUB_TOKEN 严格限于最终 pinned publication action；6 类 credential 漂移与 symlink 攻击夹具由 Release foundation 固定 | `[S][contract] security: isolate release checkout credentials` |
| 2026-08-29 | v6.22.0 | **Manus 真实账号验收证据边界**:固定低基数 transcript 的 checkpoint/顺序/末行 accepted；no-follow 64 KiB 验证器拒绝链接、权限、注入与动态内容；T7 包装器绑定源码/二进制哈希、退出状态与顶层校验和，只有真实 CLI exit 0 + accepted validator 才能生成 ACCEPTED | `[S][contract] security: make Manus live acceptance evidence auditable` |
| 2026-08-29 | v6.23.0 | **Manus 验收编译输入闭包**:从手写关键文件哈希升级为 83 个 IslandCore/CLI Swift 源的自动完整枚举；Package.resolved 与 SwiftPM workspace/checkouts 逐项绑定 27 个 clean commit，ignored/dirty/submodule/revision 漂移失败；构建前后输入与 Swift/Xcode/SDK manifest 必须逐字一致 | `[S][contract] security: bind Manus evidence to the complete build-input closure` |
| 2026-08-29 | v6.24.0 | **GitHub Workflow 内嵌 Shell 语法边界**:safe-YAML 逐项提取 CI/Release 的 Bash `run` step，完整 GitHub expression 用固定占位符替换后以最小环境 `/bin/bash -n` 静态解析；descriptor 文件边界与 8 类攻击夹具拒绝语法、类型、shell、expression、权限和链接漂移，并在 tag 依赖解析/凭据加载前执行 | `[S][contract] release: validate every workflow Bash step before tagged execution` |
| 2026-08-29 | v6.25.0 | **GitHub Workflow YAML 结构歧义边界**:safe-load 前遍历 20,000-node/128-level Psych AST，只接受单文档、无 tag 的标量 mapping key；拒绝 plain/quoted 同名 key、`on`/`true` resolved collision、多文档/非标量 key 与结构洪泛，descriptor 稳定性增加 mtime/ctime，攻击夹具扩展到 15 类 | `[S][contract] security: reject ambiguous workflow YAML before shell validation` |
| 2026-08-29 | v6.26.0 | **GitHub Workflow 有效 Shell 解析边界**:按 step > job defaults > workflow defaults > macOS Bash 解析每个 run 的有效 shell；只允许精确 bash/`/bin/bash`，拒绝 bash 参数/template、非 Bash default、畸形 defaults、非字符串 shell，攻击夹具扩展到 20 类 | `[S][contract] release: validate the effective shell for every workflow run step` |
| 2026-08-29 | v6.27.0 | **仓库脚本无执行语法闭包**:依赖/凭据前 descriptor-backed 枚举 41 Bash + 14 Ruby；最小环境 stdin-only `bash -n`/`ruby -c`，目录与文件 metadata 复验，11 类夹具证明后置语法错误、链接/权限/大小/编码失败且无前置副作用 | `[S][contract] release: parse every repository Bash and Ruby script before execution` |
| 2026-08-29 | v6.28.0 | **Swift 脚本 stdin-only Parse 闭包**:仓库脚本闭包扩展为 41 Bash + 14 Ruby + 5 Swift；冻结 Swift 字节以最小环境 `/usr/bin/swiftc -parse -` 无执行解析，允许无 shebang 或精确 env-swift，Swift 副作用/后置语法/shebang 夹具把总攻击类扩展到 13 | `[S][contract] release: parse every repository Swift script before execution` |
| 2026-08-29 | v6.29.0 | **Debug graph 隔离与解锁交互闭环**:Debug Universal App 改用独立 `.build/app-debug`，拒绝未知 CONFIG，修复 production → DEBUG 同 scratch 的 SwiftPM 停滞；T7 隔离 home 下真实完成 Codex Allow Once、Claude 两题单选/多选/Back/提交、Save Panel 四路径及 Settings Dock policy 往返，明确不替代真实 CLI/VoiceOver | `[S][contract] reliability: isolate debug bundles and prove unlocked action flows` |
| 2026-08-29 | v6.30.0 | **产品级 Reduce Motion 空间静止契约**:bar↔panel 轮廓在 Reduce Motion 下改为无动画几何切换、hover 不再扩大 capsule，通用任务/图标按钮与 Welcome 连接动作统一移除 press-scale，仅保留短 opacity/颜色反馈；3 项纯策略回归、645 项全量测试与 Universal Debug QA 构建通过，锁屏下不宣称系统开关目视或 VoiceOver 已验收 | `[S][contract] accessibility: remove spatial feedback under Reduce Motion` |
| 2026-08-29 | v6.31.0 | **状态菜单实时摘要与隐私边界**:菜单首行、tooltip 与 VoiceOver value 共用注意力优先快照并明确追加总会话数；TaskStore 变化使用 Observation 事件驱动，最近完成仅安排一次到期刷新；AX 只暴露低基数健康状态，不含标题、Session ID、路径、URL 或原始错误。648 项全量回归、完整门禁与 Universal Debug QA 构建通过，真实菜单/VoiceOver 仍待解锁验收 | `[S][contract] polish: make status-menu state live, clear, and private` |
| 2026-08-29 | v6.32.0 | **Dock 重试与进程夹具调度隔离**:Dock policy 测试改为注入式确定性 scheduler，精确固定 16/32/64 ms 生产退避并在期望状态已应用时废弃旧 generation；Codex descendant/PID 夹具使用独立 5 秒调度预算而 production 默认仍为 3 秒，PID 未发布不再伪装成网络错误。Dock 50 轮/650 次与 Codex 5 轮稳定性、648 项全量回归通过 | `[S][contract] reliability: isolate scheduler-sensitive process and Dock regressions` |
| 2026-08-29 | v6.33.0 | **GitHub 仓库审计失败分类与诊断隐私**:在线 GET-only 审计不再把 connection reset 误报为管理员权限问题；network、authentication、administration read、rate limit 与 unexpected 使用固定低基数结果，raw stderr 只在 owner-only 临时目录内有界检查且永不回显。fake-gh 覆盖 success、reset、401/403/404、rate limit 与未知失败，并以 sentinel 固定零泄漏；PR/tag 共用安全门禁 | `[S][contract] reliability: classify GitHub audit failures without exposing diagnostics` |
| 2026-08-29 | v6.34.0 | **权威测试 SwiftPM 构建图隔离**:PR/tag 与诊断复现统一通过 `run-authoritative-tests.sh` 使用 `.build/tests-authoritative`；全量 648 项与后续 20+20+5+20 轮 `--skip-build` 共享同一二进制，不再接触开发者默认或 App/Performance scratch。fake-swift 精确固定 66 次调用、filter 分布和路径，workflow 直接 `swift test` 由门禁拒绝 | `[S][contract] reliability: isolate the complete authoritative test graph` |
| 2026-08-29 | v6.35.0 | **权威测试图单写者边界**:零字节 `0600`/单硬链接 lockfile 与非等待 BSD descriptor lock 覆盖 full suite + 65 次复用；并发第二入口在 Swift 前以单一低基数错误失败。真实暂停 fake-swift 的夹具证明竞争运行不执行命令、首运行释放后仍精确 66 次 | `[S][contract] reliability: serialize authoritative test graph ownership` |
| 2026-08-29 | v6.36.0 | **Welcome 编辑栏节奏**:固定 `32 + 264 + 28 + 404 + 32 = 760pt` 的无隐式余量布局，让 English 连接页标题从三行回归稳定两行，其余中英文 Welcome 页与右侧功能标本保持无裁切；几何单测与 CI 静态门禁固定常量和实际用法 | `[S][contract] polish: stabilize welcome editorial rhythm` |
| 2026-08-29 | v6.37.0 | **商业政策审批记录输入边界**:`O_NOFOLLOW` descriptor 有界读取固定 owner/mode/nlink/size 与前后 metadata，路径/父目录再绑定阻止替换；自定义 JSON object 拒绝根层和嵌套重复 key，18 类完整性、文件、语义与竞态夹具固定，当前政策仍保持 `required` | `[S][contract] security: anchor commercial policy approval input` |
| 2026-08-29 | v6.38.0 | **产品级 Increase Contrast 角色系统**:统一读取 SwiftUI/AppKit 系统状态，将 secondary/tertiary text、hairline、展开岛边界与 idle 点阵升级为标准/增强双态；必需安静文字标准态保持至少 4.5:1，增强态边界至少 1pt；39 组同尺寸双态快照、4 项策略回归、652 项全量与完整门禁通过，系统开关和 VoiceOver 真实验收仍待解锁 | `[S][contract] accessibility: extend Increase Contrast across the product` |
| 2026-08-29 | v6.39.0 | **三种 App 构建风味产物隔离**:Production、Performance QA 与 Debug 使用共享可执行文件 marker 矩阵，lipo 后立即验证实际二进制；固定 3 个 Performance + 3 个 DEBUG-only 标记及 18 类逐标记泄漏/缺失夹具，Bundle ID/plist 双向绑定且所有 App 构建路径由静态门禁强制调用 | `[S][contract] release: verify build flavor boundaries in final executables` |
| 2026-08-29 | v6.40.0 | **离线法律文件与签名 App 字节绑定**:Privacy/Terms 双语原文先经 descriptor、日期/结构与 10 类攻击夹具验证，再原样打包并逐字节回绑；Settings 在 Support 动作前提供离线阅读，运行时重复大小/类型/结构检查且链接只允许已审阅 mailto 与产品 origin，文档继续明确为待 owner/legal 审阅草案 | `[C][contract] feat: bundle verified offline legal review copies` |
| 2026-08-29 | v6.41.0 | **Welcome 最终决策页出口收敛**:前两页保留 Skip，最终通知决策页移除重复出口，只保留窗口关闭、Back 与唯一 Start 主动作；纯导航策略拒绝负页码/单页/最终页，改前改后三页同尺寸对比证明前两页逐字节不变 | `[C][contract] polish: simplify the welcome completion decision` |
| 2026-08-29 | v6.42.0 | **App 内法律资源 descriptor 原子读取边界**:运行时移除 resourceValues→Data 的 TOCTOU 路径，固定 no-follow/nonblocking descriptor、普通单链接文件、安全 mode 与 1–512 KiB；读取后双重绑定 descriptor/path 全 metadata，六类正常/攻击回归与 CI 反回退门禁固定 | `[S][contract] security: atomically read bundled legal resources` |
| 2026-08-29 | v6.43.0 | **PR CI hermetic App 真实启动与正常退出**:Performance QA 构建后以私有 CFFIXED home 启动最终 App，等待 readiness 并连续存活采样 8 秒；精确 PID AppKit terminate、5 秒退出界限与 status 0 进入同一 gate，锁屏 override 明确禁止用于性能宣称 | `[S][contract] reliability: launch and terminate the hermetic app in PR CI` |
| 2026-08-29 | v6.44.0 | **Performance 证据文件 descriptor 所有权**:CSV/App log/summary 在启动前以 umask 077 + 单次 noclobber exec 固定三个 0600 单链接 descriptor；device/inode token 全程回绑，分析器只读同 token 的 no-follow bounded pread 私有快照；预存在、symlink、并发 winner 与替换攻击夹具固定 | `[S][contract] security: atomically own performance evidence files` |
| 2026-08-29 | v6.45.0 | **Performance readiness App-log 原子读取**:readiness 轮询移除公共 App-log 路径 `awk` 重开，改为绑定 writer token 的 no-follow/nonblocking 1 MiB `pread` 私有快照；严格拒绝 FIFO/替换、malformed/duplicate marker、反向与超 5.5 秒 uptime | `[S][contract] security: atomically snapshot readiness App logs` |
| 2026-08-29 | v6.46.0 | **Performance 输入 App 私有快照与执行身份**:所选 QA App 的 executable/plist 以 no-follow descriptor 稳定哈希并在 strict deep 校验下复制到随机私有 sampler root；只有私有 Bundle 可验证和启动，来源与副本在启动前/正常退出后重新绑定，来源替换即使副本成功也失败且不发布 summary | `[S][contract] security: launch only a frozen Performance QA App snapshot` |
| 2026-08-29 | v6.47.0 | **PR CI Performance summary 进程内交付**:workflow 以带引号 command substitution 捕获 sampler 已验证 stdout；全部 smoke/哈希断言只读 shell 变量，禁止 sampler 退出后以 grep/sed 等重开 runner-temporary summary 路径，残留子进程替换 public file 不能篡改 CI acceptance input | `[S][contract] security: keep launch-smoke acceptance in process memory` |
| 2026-08-29 | v6.48.0 | **本地 listener 无副作用真实 transport 夹具**:新增随机 loopback 端口、内存随机授权与零 Agent route 的显式 CLI harness；challenge-response 与 stop 后不可达共同验收，底层 framework stderr 完全关闭。10 轮权威 CLI 回归固定五行低基数输出，真实 Claude/Codex 只读预检前后授权、Hook、SQLite 与 Keychain 文件指纹不变 | `[S][contract] reliability: verify local listener without touching user state` |
| 2026-08-29 | v6.49.0 | **App SwiftPM 外置 scratch 边界**:`DEV_ISLAND_SWIFT_SCRATCH_ROOT` 允许把三种固定 flavor graph 放到 T7；共享 boundary helper 在 SwiftPM 前拒绝仓库/祖先、`.build` 根、源码、symlink、不安全权限和缺失父目录，安全父目录下只创建 `0700` 子目录。默认 CI/tag 仍使用仓库 `.build`，避免 File Provider dataless 缓存让本机构建永久等待 | `[S][contract] reliability: validate external SwiftPM App scratch roots` |
| 2026-08-29 | v6.50.0 | **Production App hermetic 真实启动门禁**:精确参数+环境双重 opt-in 让冻结私有副本中的真实 Production UI 以 inert TaskStore 启动；岛与状态栏 readiness、8 秒逐样本无 socket/产品状态、精确 PID AppKit 正常 status 0 共同验收。PR 在 Universal 构建后运行，tag Release 在 App 公证后、DMG 前重复，锁屏样本明确禁止作为性能宣称 | `[S][contract] reliability: launch the real Production App without product services` |
| 2026-08-29 | v6.51.0 | **Settings Agent Hook 配置 I/O 主线程隔离**:单 Agent 扫描、全局 managed-Hook 汇总与 Enable/Update/Disable 全部经可测试 detached executor；初次 checking、refresh latest-wins、mutation 独占、晚到结果/旧 Codex trust 失效及写后实际状态复验共同防止卡顿和假 Connected，中英文忙碌/AX 文案同步固定 | `[S][contract] performance: move Agent configuration I/O off the main actor` |
| 2026-08-29 | v6.52.0 | **Plan Review Markdown 单次后台渲染**:65,536 字符/262,144 UTF-8 bytes 双上限，块级与 inline Markdown 解析移出每秒 TimelineView 重绘；request+operation generation、512 块 SwiftUI 上限、加载/不完整时禁用决策及始终可回 Claude 共同防止主线程停顿、晚到覆盖和截断误批准 | `[S][contract] performance: render Plan Review Markdown once off-main` |
| 2026-08-29 | v6.53.0 | **展开面板叶子时钟隔离**:移除包住 ScrollViewReader/LazyVStack/全部决策面的面板级 TimelineView；Running/Waiting duration 下沉到 TaskCard，终态行静止，请求 countdown 仅刷新 header，并在非 live 时暂停。5 项格式/调度回归与静态门禁防止整棵面板秒级重建 | `[S][contract] performance: isolate panel clocks to changing leaves` |
| 2026-08-29 | v6.54.0 | **Welcome 连接配置操作所有权**:初始扫描与 Add/Update/Update all 统一进入共享后台 executor；latest-wins refresh、surface 级 mutation 独占、离开失效与完整写后 snapshot 复验共同阻止旧扫描回跳、重复写入和假 Connected，批量更新只提交一次最终 UI 状态 | `[S][contract] performance: serialize welcome Agent configuration operations` |
| 2026-08-29 | v6.55.0 | **商业 License 单调代际与提交时有效期**:签名 payload 增加正整数 generation；同 License ID 的旧代际、同代异字节及高代际倒退 issuedAt 全部拒绝，过期旧文档仍保留 authenticated revision 下界，Keychain 比较写入在进程内串行；激活响应改为 commit 时重新取时钟，7 项攻击/竞态回归阻止跨启动回滚与在途过期绕过，商业模式继续零 trust anchor/零实例化 | `[S][contract] security: reject signed license rollback at commit` |
| 2026-08-29 | v6.56.0 | **Support 诊断导出 I/O 主线程隔离**:Hook 诊断读取与 Save 后 descriptor write/fsync/rename 统一进入后台 executor；单 surface operation ID 覆盖报告、Save Panel 与写入完成，离开后拒绝晚到回写；独立 feedback ID 防止相同文案的旧延迟误清新提示，静态门禁禁止 Settings 回退为同步导出 | `[S][contract] performance: isolate support diagnostics I/O and delivery` |
| 2026-08-29 | v6.57.0 | **Settings Agent 配置全局操作所有权**:唯一 Settings 顶层状态跨 pane 保持单 Agent 与 Disconnect All 互斥；operation ID+kind 拒绝晚到/错类完成，completion generation 统一重扫；全局移除经共享后台 executor 且只返回低基数结果，按钮禁用不再因切页失忆 | `[S][contract] reliability: serialize settings agent mutations across panes` |
| 2026-08-29 | v6.58.0 | **Manus 签名窗口重放与终态单调性**:event ID 保留到真实认证签名 expiry、更新签名延长窗口；1,024 个 live ID 饱和返回 503 而不驱逐，重复仍幂等 200；Completed/Failed 不再被旧 stopped/ask 拉回 Waiting | `[S][contract] security: fail closed on Manus replay-window saturation` |
| 2026-08-29 | v6.59.0 | **Manus replay 真实 HTTP transport 回归**:真实 Hummingbird listener + RSA-signed loopback POST 证明首次 200/一次 delivery、duplicate 200/零新增 delivery、饱和新 ID 503、最早 ID 未被驱逐；Production capacity 仍固定 1,024 | `[T][contract] test: exercise Manus replay saturation through live HTTP` |
| 2026-08-30 | v6.63.0 | **Codex 真实审批机器可验证证据**:T7 append-never 包绑定 no-follow Codex session、同 session SQLite completed 行、外部 proof、App/CLI hash 与三张人工复核截图；固定 transcript/receipt/checksum 和攻击夹具拒绝链接、权限、内容、版本与 accepted 伪造，Security/tag Release 不再只依赖 Markdown 声明；权威图 724 项与 20/10/20/5/20 稳定性闭合，immediate-exit fixture 统一 5 秒调度预算而产品 3 秒默认不变 | `[S][contract] security: make real Codex approval evidence auditable` |
| 2026-08-30 | v6.65.0 | **Codex 拒绝/超时证据分类**:新增四类互斥 session 分类，只有 90 秒前正常完成的真实岛内 Deny 可生成 accepted 包；严格 JSON 与受限 JavaScript object 均经无执行解析，proof 三阶段保持不存在，T7 包绑定 App/CLI/session/SQLite/脚本与两张人工复核图。合成包及攻击夹具已进入 Security gate，三条真实失败样本保持 sandbox/interrupted，解锁真实 Deny 与 receipt 仍明确 pending | `[S][contract] security: distinguish island denial from timeout and rejected evidence` |
| 2026-08-30 | v6.67.0 | **Codex 真实岛内拒绝证据闭环**:真实 Codex Desktop CLI session 在岛内 Deny 后 40 秒内恢复 Running、完成且 proof 始终不存在；当前客户端省略 workdir、2,000 token 与数组型 CreateProcess 拒绝回执按精确命令绑定解析，空/错 workdir 和篡改命令夹具失败关闭；T7 accepted 包与脱敏 receipt 已复验并由聚合 Security/tag gate 强制验证 | `[S][contract] security: bind real Codex island denial to auditable evidence` |
| 2026-08-30 | v6.69.0 | **Sparkle Ed25519 密码学闭环**:发布凭证以 stdin-only 私钥对固定 payload 真签并由配置公钥验签；离线资产门从 ZIP 内交付 App 提取 `SUPublicEDKey`，用 descriptor-backed CryptoKit 对完整 archive 与精确 feed prefix 真验签，拒绝 unrelated 64-byte 签名、prefix 篡改、App key 错配与 credential keypair 错配 | `[S][contract] security: cryptographically verify the complete Sparkle release chain` |
| 2026-08-30 | v6.70.0 | **Sparkle disposable old-to-new 真实闭环**:离线编译 pinned `sparkle-cli`，以随机 loopback、RFC fixture key 和一次性 v1/v2 App 真正完成 signed feed/archive 下载、解压、code-sign validity 与 bundle 替换；错 feed/archive/key 与破坏 App 签名四链失败关闭，随机偏好/cache 精确清零；不冒充 Developer ID/公证生产更新 | `[S][contract] release: exercise the real Sparkle updater before credentials` |
| 2026-08-30 | v6.71.0 | **普通测试图 Keychain 零副作用边界**:商业 License 与 Manus API-key 存储抽为注入式 backend；shipping 仍固定 `WhenUnlockedThisDeviceOnly` + 非同步 Keychain，普通 `swift test` 全部改用进程内存并由 Security gate 拒绝测试侧 `SecItem*`/生产静态入口。真实 Keychain 只允许在隔离账户/VM 的显式门禁中验收 | `[S][contract] reliability: keep ordinary tests out of the login Keychain` |
| 2026-08-30 | v6.72.0 | **岛内决策面一体化与响应回执**:移除模板化内层卡和常驻次级按钮底色；Permission/Question/Plan 在 Agent response 后显示 0.9 秒双语低噪音回执并回到 Running，保留请求优先级、键盘路由与 VoiceOver 聚合标签 | `[S][contract] polish: integrate decisions and acknowledge responses` |
| 2026-08-31 | v6.73.0 | **Codex Hook 信任旁路与激活指引**:真实复现 Continue without trusting 让审批留在 Codex 且 Hook 不运行；Settings/Live readiness 明确要求用户在 `/hooks` 审阅 Dev Island，禁止 App 自动修改 trust/config，timeout 正常回退继续保持待验收 | `[S][contract] reliability: explain and preserve Codex hook trust` |
| 2026-08-31 | v6.74.0 | **决策响应帧级分段与回执预留**:Instruments 分开统计 resolved App update/frame/GPU/hang 并以 wallUnix 精确对齐；先预留 receipt 再同步 response，消除瞬态 TaskCard 构造。Permission update 132.257→21.238 ms、54.802 ms delay 消失；Question/Plan 固定源码 trace 仍待解锁 | `[S][contract] performance: remove transient decision-card reconstruction` |
| 2026-08-31 | v6.75.0 | **商业激活 pre-provider loopback sandbox**:测试 target 以合成 Ed25519 key、随机 numeric loopback、真实 Hummingbird HTTP 和内存存储贯通生产 activation/verifier/store；未签名响应失败关闭，严格拒绝非精确本地 endpoint。shipping App 仍零 server/transport/endpoint/trust anchor/实例化，不构成 provider 或商业验收 | `[S][contract] test: exercise commercial activation over real loopback HTTP` |
| 2026-08-31 | v6.76.0 | **商业激活 transport 失败关闭矩阵**:真实 loopback 覆盖 code rejection、rate limit、5xx、未知状态、redirect 与超限 body；重定向目标零请求、provider 私有 body 不外泄、所有非成功路径零存储。该测试 transport 不得作为 production HTTPS/streaming 实现模板 | `[S][contract] test: harden commercial transport failure matrix` |
| 2026-08-31 | v6.77.0 | **商业激活真实 HTTP operation ownership**:取消不敏感的 bounded detached 请求确保签名 response 在 Cancel/Supersede 后真实晚到；显式取消仍零存储，旧/新双响应完成时只有最新 operation 可验签保存。测试时序由 request/response 计数而非猜测 sleep 固定 | `[S][contract] test: prove late HTTP activation responses cannot commit` |
| 2026-08-31 | v6.78.0 | **商业激活 pre-cancelled zero ownership**:进入 actor 前已经取消的 caller 在可信预检后直接返回 cancelled，不得 supersede 现有 pending operation、创建 transport task 或消耗一次性 code；受控 transport 与真实 loopback 均证明 request count 不增加，原 operation 继续激活 | `[S][contract] fix: reject pre-cancelled activation before operation ownership` |
| 2026-08-31 | v6.81.0 | **默认关闭的商业激活 HTTPS 流式边界**:新增未配置、未实例化的 shipping transport；严格固定 public-DNS HTTPS `/v1/activate`、ephemeral 无 proxy/cookie/cache/ambient credential、十秒 timeout、零 redirect、body-only secret、final URL/status/media-type 与低基数错误；declared/unknown length 均在读取过程中固定 32 KiB，caller cancellation 保持取消语义。真实 provider/政策/key/UI 仍未批准 | `[S][contract] security: bound commercial activation HTTPS while streaming` |
| 2026-08-31 | v6.82.0 | **商业激活 endpoint capability seal 与底层取消证据**:HTTPS transport 移除 public initializer/factory，module-internal endpoint 仅供测试和未来源码固定 provider adapter；shipping IslandCore/App/AppLib 继续零构造。取消回归直接观察 URLProtocol `stopLoading`，证明 caller cancellation 到达底层 URLSession request，同时保留 actor late-response 拒绝 | `[S][contract] security: seal activation endpoints and prove request cancellation` |
| 2026-08-31 | v6.83.0 | **同 Bundle 单实例接管**:普通启动在任何产品窗口、服务与 LaunchHealth 写入前按同 Bundle ID 的最低 live PID 确定唯一 owner；新实例仅在 AppKit 成功激活旧实例后退出，竞态消失则 fail open。退出回调保持零副作用，精确双 opt-in 的 hermetic Production smoke 明确绕过，避免 QA 干扰已安装 App | `[S][contract] reliability: keep one live island per login session` |
| 2026-08-31 | v6.84.0 | **可信代码身份单实例与 authoritative v3 验收**:Bundle ID 只筛候选，动态签名要求 Apple-anchored 同 Team 或同运行 slice 的明确 ad-hoc CDHash；SwiftUI root Settings Scene 在 gate 前保持 inert。v2 因 pre-gate Scene 风险拒绝；corrected v3 的锁屏 arm64 LaunchServices 矩阵 20/20 保持单 owner、单 listener、无其他观察 socket、duplicate home 空且不同-CDHash impostor activation `0 → 0`。同 Team Developer ID、Rosetta 跨 slice、解锁焦点/VoiceOver 与 LaunchServices 真实退出码继续明确未证明 | `[S][contract] reliability: bind trusted single-instance arbitration to authoritative evidence` |
| 2026-08-31 | v6.85.0 | **Manus trust generation、credential-safe cleanup 与正常 Quit 屏障**:exact callback URL + canonical ≥2048-bit RSA identity 绑定 replay generation，旧代已认证请求交错返回 401；所有 accepted webhook ID 立即持久化为集合，replacement/late registration/heartbeat/stop 共享可重试删除，只有 2xx + `ok:true` 才清 ID。Disconnect 与换 key 都在远端 cleanup 成功前保留旧 Keychain credential；Quit 同步 detach ingress 并 single-flight join Disconnect/sleep/poller/tunnel/listener，AppKit owner 用 tokenized finish-once 的两秒 `.terminateLater` 屏障，失败/超时保留 credential + ledger；三种无 owner QA/yield 路径直接 `.terminateNow`。Release realtime gate 关闭且无真实账号验收 | `[S][contract] reliability: bound Quit without releasing Manus cleanup capability` |
| 2026-08-31 | v6.86.0 | **Manus unknown-registration 原子 reconciliation**:官方 `GET /v2/webhook.list` 严格接收最多 1,024 项账号 inventory；单一 `webhookRecoveryStateV1` envelope 将 ID ledger、token、callback digest、±300 秒时间身份与 discovered IDs 一起 flush/readback。只归属 active exact-digest 且唯一 marker 的 row，歧义/空 list/legacy/corrupt 全部失败关闭；bound ID 跨重启直接重试，严格 official 404 `not_found` 完成幂等删除。Release gate 仍关闭，真实 create→signed delivery→list/delete 与一致性证据待补 | `[S][contract] security: reconcile unknown Manus registrations without guessing ownership` |
