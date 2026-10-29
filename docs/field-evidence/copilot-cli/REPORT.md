# Copilot CLI 1.0.105 — Windows 真实事件证据（阶段性）

- 日期：2026-10-29，时间线使用 UTC。
- 环境：Windows NT 10.0.26300.0；捕获脚本 Node 22.14.0。
- 实际执行版本：Copilot CLI 1.0.105。npm 包元数据为 1.0.80，启动时使用了已下载的更新版本；本报告不验收 1.0.80。
- 登录：使用本机已有 GitHub 登录；未读取、复制或提交凭据。
- 执行方式：用户提供的交互截图、代理控制的真实终端（PTY）以及明确标记的 prompt 模式。
- 捕获脚本：`fix/windows-capture-validation` 的 `690b5a3`，静默、退出 0，不返回审批决定。
- 配置：空测试仓库中的 `.github/hooks/devisland-capture.json`，`type: command`、Windows `powershell` 命令、`timeoutSec: 5`。未修改全局 Hook 配置。
- 注册：SessionStart / UserPromptSubmit / Notification / Stop / ErrorOccurred / SessionEnd / PermissionRequest / permissionRequest。
- 本报告是阶段性证据，不能据此将连接器转为 Stable。

## 场景结果

| 场景 | 实际事件/结果 | 证据时间 UTC |
| --- | --- | --- |
| 用户交互发送 hi | 真实回复 hi；仅注册 SessionStart，不能据此判断其他事件缺失 | 00:15:24 |
| prompt 模式 hi | SessionStart → UserPromptSubmit → Stop → SessionEnd；退出 0 | 00:39:58–00:40:01 |
| prompt 模式 --continue | 回复 hi、退出 0，但没有新增 Hook 记录；恢复配置加载/信任行为待查，ID 延续未证实 | 上述轮次之后 |
| 交互创建文件、单次允许 | 原生审批框显示后选择 Yes；文件确实创建，内容 hello；随后 Stop | 00:57:44–00:58:03 |
| 交互创建文件、拒绝 | 选择 No 并要求不重试；界面显示 rejected，目标文件不存在；随后 Stop | 00:58:20 左右–00:58:55 |
| 不处理审批 | 等待超过两分钟未自动超时、无新增 Hook；随后 Ctrl+C 取消，文件未创建 | 00:59:14–01:01:29 |
| 正常退出 | /exit，SessionEnd | 01:01:44 |
| 移除配置后复测 | 将本次项目 Hook 移出加载目录，prompt 模式正常回复 hi、退出 0；时间线保持 21 行 | 正常退出之后 |

## 关键发现

### 两种大小写注册都会执行，但 payload 仍为 camelCase

一次原生文件创建审批，先后触发 `permissionRequest` 和 `PermissionRequest`。这是同时注册两个探针的结果，**不是两个独立审批请求**。两条记录的会话哈希相同，bytes 相同。

两者的输入字段均为：

```text
hookName: string
sessionId: string（时间线只留哈希）
timestamp: number（时间线只留类型）
cwd: string
toolName: string
toolInput: object
  file_path: string
  diff: string
permissionSuggestions: array（本次为空）
```

本次 `PermissionRequest` 未包含 `hook_event_name` 或 `session_id`。不可因配置名为 PascalCase 就假设审批 payload 一定是 snake_case。

### Notification 混合使用命名风格

审批通知记录包含 `sessionId`、数值 `timestamp`、`cwd`、`message`、`title`，同时有 `hook_event_name: Notification` 与 `notification_type: permission_prompt`。

### 原生审批回落已观察

捕获脚本不返回审批决定时，CLI 显示原生 Yes / Yes and don't ask again / No 菜单。单次允许和拒绝都有效；未选择持续自动批准。代理通过终端按键操作菜单，没有通过 Hook 模拟审批。

事件时间线显示两个 permission 探针先于 permission_prompt 通知；界面出现时这些事件已落盘。终端轮询不是逐帧测量，不能声称精确的 UI 弹出时延。

### 其他

- 正常 lifecycle payload 使用 `session_id`，而审批/通知使用 `sessionId`。
- 文件创建审批的 toolInput 是 `file_path` 与 `diff`，不是预设 shell 命令结构。
- `recoverable == false` 尚未观察；不能从正常 Stop 或工具拒绝推断模型 API 错误行为。
- 仅观察到 permission_prompt 通知，不能声称已覆盖所有通知类别。

## 隐私与限制

`timeline.jsonl` 仅包含捕获脚本生成的形状及时间/字节数；原始 payload 保留在本机隔离目录，不提交。人工检查键名，未发现动态隐私键。未知枚举值被隐藏，无法仅凭 timeline 恢复其原文。数组只记录前三项。

未完成的验收：固定 1.0.80、恢复会话 ID 连续性、API 失败及 recoverable 分类、真正并发、macOS Dev Island 映射与界面验收。后续补充的取消/等待结果见下文。

## 取消与配置清理

原生审批菜单等待超过两分钟未自动超时；01:01:29 前按 Ctrl+C，界面显示 Operation cancelled by user，文件未创建。当时没有新增 Stop/ErrorOccurred 事件。之后 /exit 才记录 SessionEnd。这里只验证了审批等待中的 Ctrl+C，尚未验证模型生成中的中断。

代理测试结束后，project-b 的捕获配置移到本机备份目录，正常请求仍可完成，时间线行数保持 21。project-a 的探针仍留作用户后续测试，用户原有全局设置未改动。

## 复现及数据审查

Windows Hook 条目结构：

```json
{
  "version": 1,
  "hooks": {
    "PermissionRequest": [{
      "type": "command",
      "powershell": "& '<node executable>' '<capture-hook.mjs>' copilot PermissionRequest",
      "timeoutSec": 5,
      "env": { "DEVISLAND_CAPTURE_ROOT": "<private capture directory>" }
    }]
  }
}
```

替换占位符后对八个事件分别注册。命令行探测使用 `--trust-folder -p`、空 `--available-tools`、`--disable-builtin-mcps`；交互审批使用 `-i` 与默认 Manual Approval。未开启 allow-all/yolo。只信任当前隔离测试仓库，不持久授予所有文件操作权限。

采集范围：21 条真实事件。提交前解析全部 JSONL，检查所有 shape 字符串仅为长度/ID/类型标记或已观察的枚举值，键名仅为普通字段名；未提交 raw、终端日志、登录信息或本机绝对路径。允许文件内容核实为 hello；拒绝/取消两个目标文件均不存在。
