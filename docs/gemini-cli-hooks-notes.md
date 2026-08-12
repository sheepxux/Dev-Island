# Gemini CLI Hooks 调研笔记

> 核对日期：2026-08-05。本文记录 Dev Island 的 Gemini CLI 本地 hooks
> 接入依据、建议映射和一次性冒烟方法；它不是 Gemini CLI 的完整 hooks 教程。

## 版本基线

| 项目 | 固定值 | 说明 |
| --- | --- | --- |
| 冒烟目标包 | `@google/gemini-cli@0.53.1` | 2026-08-05 的 npm stable `latest`;本机 `npx` 版本探针已通过 |
| 对应上游 tag | [`19a68016bdc9cd4177a155846dd51f282c3c1c59`](https://github.com/google-gemini/gemini-cli/commit/19a68016bdc9cd4177a155846dd51f282c3c1c59) | `v0.53.1` 指向的官方仓库快照 |
| 最新文档交叉检查 | [`ac42fb0a24fe7349e9968e2359ef5232f1cb6e72`](https://github.com/google-gemini/gemini-cli/commit/ac42fb0a24fe7349e9968e2359ef5232f1cb6e72) | 四份 `docs/hooks/*.md` 与 v0.53.1 逐字节一致 |

集成验收固定 stable 的完整版本号，避免 `latest` 后续移动。最新 main 快照只用于
确认 hook 契约没有漂移，不能替代 v0.53.1 二进制的真实会话冒烟。

复核版本可用：

```sh
npm view @google/gemini-cli dist-tags --json
npm view @google/gemini-cli@latest version
npx -y @google/gemini-cli@0.53.1 --version
```

## 官方资料

以下 URL 都固定到 stable v0.53.1 对应 commit，避免 `main` 后续变化导致结论漂移：

- [Gemini CLI hooks 概览](https://github.com/google-gemini/gemini-cli/blob/19a68016bdc9cd4177a155846dd51f282c3c1c59/docs/hooks/index.md)
- [Hooks reference（配置、I/O、事件语义）](https://github.com/google-gemini/gemini-cli/blob/19a68016bdc9cd4177a155846dd51f282c3c1c59/docs/hooks/reference.md)
- [Writing hooks](https://github.com/google-gemini/gemini-cli/blob/19a68016bdc9cd4177a155846dd51f282c3c1c59/docs/hooks/writing-hooks.md)
- [Hooks best practices（性能、安全、隐私、排错）](https://github.com/google-gemini/gemini-cli/blob/19a68016bdc9cd4177a155846dd51f282c3c1c59/docs/hooks/best-practices.md)
- [Hook runner 实现](https://github.com/google-gemini/gemini-cli/blob/19a68016bdc9cd4177a155846dd51f282c3c1c59/packages/core/src/hooks/hookRunner.ts)

## 配置位置与结构

Gemini CLI 会合并以下配置层，官方列出的优先级从高到低为：

1. 项目：`<project>/.gemini/settings.json`
2. 用户：`~/.gemini/settings.json`
3. 系统：`/etc/gemini-cli/settings.json`
4. 已安装扩展提供的 hooks

Dev Island 应只管理用户级 `~/.gemini/settings.json` 中带自身 endpoint 标记的
条目；安装和卸载都要保留其他顶层字段、其他事件组以及用户自己写的 hooks。
项目级 hook 尤其不能由 Dev Island 自动写入。

Gemini CLI 使用嵌套 entry：事件值是 group 数组，每个 group 的 `hooks` 又是
command hook 数组。下面是 `BeforeAgent` 的 Dev Island 形状；同一 group 需要分别
出现在 `SessionStart`、`BeforeAgent`、`Notification`、`AfterAgent` 和
`SessionEnd` 下。

```json
{
  "hooks": {
    "BeforeAgent": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "curl -sf -m 2 -X POST http://127.0.0.1:7824/hooks/gemini-cli -H 'Content-Type: application/json' --data-binary @- >/dev/null 2>&1 || true"
          }
        ]
      }
    ]
  }
}
```

- 空 `matcher` 与 `"*"` 都表示匹配全部；工具事件 matcher 是正则，生命周期
  事件的非通配 matcher 是精确字符串。
- `type` 当前只有 `"command"`；官方默认超时是 60 秒。上面的 curl 自身以
  `-m 2` 把网络等待限制到 2 秒，并用 `|| true` 保证 Dev Island 未运行时不让
  Gemini turn 失败。
- hooks 是同步进入 agent loop 的。即使失败被吞掉，命令启动和本地 HTTP 请求
  仍会增加少量延迟，不能把这里的“fail-open”误称为真正的后台异步投递。
- 官方要求 stdout 不得混入普通文本。固定 commit 的 runner 接受 exit 0 且
  stdout 为空，所以上述重定向在该基线下是 no-op 输出；官方示例仍更推荐输出
  `{}`。如果以后 runner 改成强制 JSON，应换成“转发后打印 `{}`”的 wrapper，
  不能让 curl 的响应或诊断文字污染 stdout。

## 输入 payload

所有事件都会通过 stdin 收到以下基础字段：

```json
{
  "session_id": "8a54b3a0-example",
  "transcript_path": "/absolute/path/to/transcript.json",
  "cwd": "/absolute/path/to/project",
  "hook_event_name": "BeforeAgent",
  "timestamp": "2026-08-05T12:34:56.789Z"
}
```

Dev Island 当前只需要 `session_id`、`cwd` 和 `hook_event_name`，并按事件读取少量
附加字段；未知字段必须容忍。订阅事件的官方附加字段如下：

| 事件 | 附加输入 |
| --- | --- |
| `SessionStart` | `source`: `startup` / `resume` / `clear` |
| `BeforeAgent` | `prompt` |
| `Notification` | `notification_type`、`message`、`details`；当前公开类型为 `ToolPermission` |
| `AfterAgent` | `prompt`、`prompt_response`、`stop_hook_active` |
| `SessionEnd` | `reason`: `exit` / `clear` / `logout` / `prompt_input_exit` / `other` |

转发命令会把完整 stdin 原样 POST 到 loopback；“解码时忽略 prompt”并不等于
prompt 没有离开 Gemini 进程。因此接收端必须继续只绑定 `127.0.0.1`，不要把
这条路由挂到 Manus 的公网 tunnel，也不要记录原始 body。

## 事件语义与 Dev Island 映射

| Gemini CLI 事件 | 官方触发语义 | Dev Island 状态 | 注意事项 |
| --- | --- | --- | --- |
| `SessionStart` | 启动、恢复会话或 `/clear` 后 | `.running` | advisory；`decision` / `continue` 被忽略 |
| `BeforeAgent` | 用户提交 prompt 后、agent 开始规划前 | `.running` | 最可靠的“新一轮开始”信号 |
| `Notification` + `ToolPermission` | CLI 显示工具授权系统通知时 | `.waiting`，文案取 `message` | 只做观测，hook 不能代替用户授权 |
| 其他 `Notification` | 未知或未来通知类型 | 忽略 | 避免把非阻塞通知误报为等待用户 |
| `AfterAgent` | 每一轮最终回复生成后，正常情况下每 turn 一次 | `.completed` | 是 turn 完成，不是整个 session 结束 |
| `SessionEnd` | exit、clear、logout 等会话结束场景 | 删除该 session task | best effort；CLI 不等待 hook 完成，可能丢失 |

当前公开事件没有等价于“本轮失败”的可靠终止信号。`AfterAgent` 也没有成功/失败
字段，`SessionEnd.reason == "other"` 更不能安全推断成失败。因此第一版不要伪造
`.failed`：完成项依靠下一次 `BeforeAgent` 回到 `.running`，漏掉的 `SessionEnd`
依靠本地 task TTL 回收。

另外，`AfterAgent` hook 自身可以通过 deny 要求模型重试，但 Dev Island hook
只是观测器，应始终 allow/no-op，不注入 context、不修改参数、不阻断 tool/turn。

## 风险与边界

| 风险 | 对策 / 验收点 |
| --- | --- |
| hooks 以当前用户权限执行任意命令 | 只安装固定、可读的 loopback curl；不执行项目提供的脚本；卸载按 `/hooks/gemini-cli` 标记精准删除 |
| prompt、回复、transcript 路径属于敏感数据 | 仅监听 `127.0.0.1`；不进公网 tunnel、不持久化原始 payload、不写 telemetry 日志 |
| 本机其他进程可伪造 loopback POST | 把 endpoint 视为本机进程信任边界；严格校验非空 `session_id`、已知事件与 payload 大小，未知输入 200 后丢弃 |
| 同步 hook 拖慢 Gemini | curl 2 秒硬超时、失败返回成功；只订阅五个低频生命周期事件，不订阅 `AfterModel` 等逐 chunk 事件 |
| `SessionEnd` 是 best effort | 不能依赖它做唯一清理；保留 stale TTL，并测试 CLI 强退场景 |
| `AfterAgent` 是每 turn 而非每 session | UI 会在 completed 与下一轮 running 之间切换，这是预期语义 |
| 没有正式 failed 事件 | 不根据 stderr、`reason == other` 或缺失字段猜测失败 |
| stable 包与后续文档漂移 | 固定完整 npm 版本跑冒烟；升级前重读 pinned commit 到新 commit 的 hooks reference diff |
| stdout 规则变化 | 用 `/hooks panel` 检查 parse warning；必要时改用最终只输出 `{}` 的 wrapper |
| 用户已有复杂 settings | 安装前备份；merge 而非覆盖；重复安装应幂等；卸载后用户 entries 必须在 JSON 语义上完整保留（格式和键顺序可能规范化） |
| settings 使用注释 / JSONC 或结构异常 | 当前安装器保守拒绝并保持原文件字节不变,由 Settings 显示错误;不要为追求自动安装而丢弃注释或覆盖文件 |

当前 Dev Island 本地 receiver 还有 1 MiB body 上限。超长 `AfterAgent` payload 可能
被安全丢弃，因此不能把“completed 一定到达”当成强保证；这一点也应由 stale TTL
兜底。

## 临时 local-hooks 冒烟

以下流程不全局安装 npm 包，也不要求覆盖用户 settings。

### 1. 固定包并留配置快照

```sh
gemini_smoke_dir="$(mktemp -d)"
npm install --prefix "$gemini_smoke_dir/npm" \
  @google/gemini-cli@0.53.1
"$gemini_smoke_dir/npm/node_modules/.bin/gemini" --version

mkdir -p "$gemini_smoke_dir/config-backup"
if test -f "$HOME/.gemini/settings.json"; then
  cp "$HOME/.gemini/settings.json" \
    "$gemini_smoke_dir/config-backup/settings.json.before"
fi
```

启动 Dev Island，在 *Settings → Connected Services* 打开 Gemini CLI。不要手工用
一个最小 JSON 覆盖现有 `~/.gemini/settings.json`。用 `jq` 确认上述五个事件各有
且只有一个 command 含 `/hooks/gemini-cli`，同时原有键和 hooks 仍在。

### 2. 先测本地 receiver 状态机

保持 Dev Island 运行，依次发送最小 payload，并观察 island：

```sh
curl -sS -X POST http://127.0.0.1:7824/hooks/gemini-cli \
  -H 'Content-Type: application/json' \
  --data '{"session_id":"gemini-smoke","cwd":"/tmp/gemini-smoke","hook_event_name":"SessionStart","transcript_path":"/tmp/gemini-smoke.json","timestamp":"2026-08-05T12:00:00Z","source":"startup"}'

curl -sS -X POST http://127.0.0.1:7824/hooks/gemini-cli \
  -H 'Content-Type: application/json' \
  --data '{"session_id":"gemini-smoke","cwd":"/tmp/gemini-smoke","hook_event_name":"Notification","transcript_path":"/tmp/gemini-smoke.json","timestamp":"2026-08-05T12:00:01Z","notification_type":"ToolPermission","message":"Approve test tool?","details":{}}'

curl -sS -X POST http://127.0.0.1:7824/hooks/gemini-cli \
  -H 'Content-Type: application/json' \
  --data '{"session_id":"gemini-smoke","cwd":"/tmp/gemini-smoke","hook_event_name":"AfterAgent","transcript_path":"/tmp/gemini-smoke.json","timestamp":"2026-08-05T12:00:02Z","prompt":"smoke","prompt_response":"done","stop_hook_active":false}'

curl -sS -X POST http://127.0.0.1:7824/hooks/gemini-cli \
  -H 'Content-Type: application/json' \
  --data '{"session_id":"gemini-smoke","cwd":"/tmp/gemini-smoke","hook_event_name":"SessionEnd","transcript_path":"/tmp/gemini-smoke.json","timestamp":"2026-08-05T12:00:03Z","reason":"exit"}'
```

预期顺序是 running → waiting → completed → task 消失。再补一条未知
`notification_type` 和一条空 `session_id`，两者都应返回 HTTP 200 但不改变 UI。

### 3. 跑真实 Gemini CLI 链路

1. 从一个无敏感数据的临时目录运行固定 binary：
   `"$gemini_smoke_dir/npm/node_modules/.bin/gemini"`。
2. 在 Gemini CLI 内打开 `/hooks panel`，确认五类 Dev Island hook 已启用且没有
   JSON parse warning。
3. 会话启动后应出现 running；提交普通 prompt 后 `BeforeAgent` 应维持/恢复
   running。
4. 请求一次需要确认的 harmless tool（例如让它执行 `pwd`，不要使用自动批准
   模式），授权提示出现时应变成 waiting。
5. 完成或拒绝授权并让本轮生成最终回复，应变成 completed；再发一条 prompt 应
   回到 running。
6. 正常退出应移除 task；另做一次强制终止，确认残留 task 最终由 TTL 清理。
7. 关闭 Dev Island 后再运行一轮 Gemini；最多增加约 2 秒 hook 等待，CLI 不应因
   curl 失败而阻断 turn。重新打开 Dev Island 后继续验证。

### 4. 清理

在 Dev Island Settings 关闭 Gemini CLI，让产品走 marker-based uninstall；确认
只删除含 `/hooks/gemini-cli` 的 entries。与备份做 diff，但若冒烟期间用户另有
改动，不要直接用备份覆盖新文件。最后删除 `gemini_smoke_dir` 指向的临时 npm
目录。若测试前 settings 不存在，卸载后留下空 `{}` 也不应被误判为用户配置丢失。
