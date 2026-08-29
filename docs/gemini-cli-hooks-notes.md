# Gemini CLI Hooks 调研与验收笔记

> 核对日期：2026-08-26。本文记录 Dev Island 的 Gemini CLI 本地 Hook
> 契约、隐私边界和真机验收方法，不是 Gemini CLI 的完整 Hooks 教程。

## 版本与证据基线

| 项目 | 固定值 | 状态 |
| --- | --- | --- |
| 当前 stable | `@google/gemini-cli@0.57.0` | 真机冒烟目标；本机尚未安装或登录 |
| stable tag commit | [`6b0ae9a6c37aa117cc8b070d8b41c5bb4fa6d253`](https://github.com/google-gemini/gemini-cli/commit/6b0ae9a6c37aa117cc8b070d8b41c5bb4fa6d253) | 固定官方源码快照 |
| 旧实现基线 | `@google/gemini-cli@0.53.1` | 仅用于契约漂移对照 |
| `docs/hooks/reference.md` SHA-256 | `103bab9f0f8fd7251b97d06c6b7c4e52752427bf23cbacd1379f2aecaaf26e4c` | 0.53.1 与 0.57.0 相同 |

固定版本与 commit 是为了避免 `latest` 或 `main` 移动后把未经验证的新契约误当成
当前实现依据。升级连接器前必须重新对照官方 Hook reference 与 runner 实现。

官方资料：

- [Hooks overview](https://github.com/google-gemini/gemini-cli/blob/6b0ae9a6c37aa117cc8b070d8b41c5bb4fa6d253/docs/hooks/index.md)
- [Hooks reference](https://github.com/google-gemini/gemini-cli/blob/6b0ae9a6c37aa117cc8b070d8b41c5bb4fa6d253/docs/hooks/reference.md)
- [Writing hooks](https://github.com/google-gemini/gemini-cli/blob/6b0ae9a6c37aa117cc8b070d8b41c5bb4fa6d253/docs/hooks/writing-hooks.md)
- [Hooks best practices](https://github.com/google-gemini/gemini-cli/blob/6b0ae9a6c37aa117cc8b070d8b41c5bb4fa6d253/docs/hooks/best-practices.md)

## Dev Island 管理范围

Gemini CLI 会合并项目、用户、系统和扩展提供的设置。Dev Island **只管理用户级**
`~/.gemini/settings.json` 中命令包含 `/hooks/gemini-cli` 的条目：

- 不写项目级 `<project>/.gemini/settings.json`；
- 不写系统级配置；
- 安装和更新保留未知顶层字段、其他事件及用户自己的 Hook；
- 卸载只删除带 Dev Island endpoint 标记的组；
- 已有文件无法读取、不是 JSON object，或 `hooks`/事件容器类型不兼容时，拒绝
  安装并保持文件原字节不变。

Gemini 使用带空 matcher 的嵌套 command group。每个已订阅事件的形状为：

```json
{
  "hooks": {
    "BeforeAgent": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "curl --noproxy 127.0.0.1 -sf -m 2 -X POST http://127.0.0.1:7824/hooks/gemini-cli -H 'Content-Type: application/json' -H 'X-Dev-Island-Hook: v1' -H \"@${HOME}/Library/Application Support/island-app/local-hook-authorization.header\" --data-binary @- >/dev/null 2>&1 || true"
          }
        ]
      }
    ]
  }
}
```

命令只访问显式绕过代理的 `127.0.0.1`，网络等待上限 2 秒，丢弃 stdout/stderr，
且以 `|| true` 结束。Dev Island 未运行时不能让 Gemini turn 因 Hook 失败而中断。
Gemini Hook 位于同步 Agent loop 内，因此这里是“有上限的被动 Hook”，不能宣称为
真正无成本的后台投递。

## 事件与能力映射

第一版只订阅 5 个低频事件，不订阅 `BeforeTool`、`AfterTool`、`BeforeModel`、
`AfterModel` 等高频或内容密集事件。

| Gemini CLI 事件 | Dev Island 状态 | 说明 |
| --- | --- | --- |
| `SessionStart` | Running | 启动、恢复或 clear 后的会话 |
| `BeforeAgent` | Running | 新一轮开始 |
| `Notification` + `ToolPermission` | Waiting | 仅提示用户回 Gemini CLI 处理 |
| 其他 `Notification` | Ignore | 防止未知通知被误报为阻塞 |
| `AfterAgent` | Completed | 一轮完成，不代表 session 结束 |
| `SessionEnd` | Remove | best effort；遗漏时由 TTL 清理 |

Gemini 的 `ToolPermission` Notification 只证明“可以观察权限提示”，没有证明这条
被动 Hook 能返回用户的批准或拒绝。因此代码能力必须保持
`permissionRequests: .observeOnly`，`actionHookEvents` 必须为空，界面不得显示岛内
Allow/Deny 按钮。官方契约也没有可靠的 turn failure 事件，不能根据缺字段或
`SessionEnd.reason` 猜测 Failed。

## 数据与安全边界

Hook command 会把 Gemini 提供的完整 stdin 原样 POST 到本机回环地址；即使
Dev Island 的 decoder 只保留 session ID、cwd、事件、通知类型与 message，原始
payload 仍可能在传输瞬间包含 prompt、response、transcript path 或 details。

- receiver 必须只绑定 `127.0.0.1`，Gemini route 不得暴露到 Manus 公网 tunnel；
- route 必须拒绝 `Origin` 以及缺失/错误的 `X-Dev-Island-Hook: v1`；该非 simple-request
  Header 强制浏览器 fetch 预检且服务器不授权 CORS，旧 managed command 必须显示需更新；
- 每次监听启动必须轮换 256-bit `X-Dev-Island-Authorization`，命令只通过 owner-only
  `0600` Header 文件和 curl `-H @file` 读取；值不得进入 Gemini 配置、argv、日志或诊断，
  旧 epoch/缺失/错误凭据不得解码或交付 payload；
- 原始 body 不得落盘、写日志、进入诊断或遥测；
- 只把标准化任务字段写入本地 SQLite；
- 空或纯空白 session ID、未知事件和不可解码输入均静默丢弃；
- 其他 macOS 用户因无法读取私有凭据而不能伪造 loopback POST；当前登录用户下能读取
  该文件的进程仍属于本地用户信任边界，因此不能仅据此执行工具、写文件或授予权限；
- receiver 的 1 MiB body 上限可能丢弃很长的 `AfterAgent` payload，不能承诺每次
  Completed 都会到达，仍需依赖下一事件和 TTL 收敛。

## 验证状态

当前已完成：

- payload 解码与 Running → Waiting → Completed → Remove 模拟链路；
- 非权限 Notification 静默、空 session ID 丢弃；
- 安装、重复安装、旧命令更新、精准卸载；
- 保留用户设置与用户 Hook；
- 损坏 JSON、非 object 根及异常 Hook 容器原字节保护；
- observe-only 能力、空 action Hook、2 秒被动命令与 endpoint 不变量测试；
- Logo 资源生成与 App bundle 打包检查。

尚未完成：真实 `@google/gemini-cli@0.57.0` 的登录会话与 `/hooks panel` 验收。
因此 README 与 Roadmap 只能标为 **Preview / 待真机验收**，不能标为已完整支持。

## 真机验收步骤（不得覆盖用户配置）

1. 在无敏感数据的临时目录安装或运行固定的 `0.57.0` binary，确认版本。
2. 在 Dev Island 设置中启用 Gemini CLI；不要手写最小 JSON 覆盖已有 settings。
3. 用 Gemini `/hooks panel` 确认五类 Hook 各一个、没有 parse warning。
4. 普通 prompt 应保持 Running；触发一次无害工具授权（例如 `pwd`）应变 Waiting，
   但审批仍由 Gemini CLI 原生界面完成。
5. 最终回复后应变 Completed；下一 prompt 回到 Running；正常退出移除任务。
6. 强制终止一次，确认残留任务最终由 TTL 清理。
7. 完全退出 Dev Island 后再运行一轮 Gemini，验证 Hook 失败不会阻断 turn。
8. 从设置中关闭 Gemini，确认只移除 `/hooks/gemini-cli` 组，其他设置和 Hook 保留。

验收前后只做 diff，不得用旧备份直接覆盖用户测试期间产生的新设置。
