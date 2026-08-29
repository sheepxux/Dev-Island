# Qwen Code Hooks research and acceptance notes

Last evidence review: 2026-08-26

This document pins the contract used by Dev Island's **Qwen Code Preview**
connector. It is an engineering boundary and acceptance checklist, not a
claim that the connector has passed real-user compatibility testing.

## Pinned upstream

| Item | Pin | Use |
| --- | --- | --- |
| CLI package | `@qwen-code/qwen-code@0.22.0` | Real acceptance target |
| Source commit | [`e38665674e2978f98cd35e7c6f6eac057741647f`](https://github.com/QwenLM/qwen-code/commit/e38665674e2978f98cd35e7c6f6eac057741647f) | Immutable protocol source |
| Hook reference | [`docs/users/features/hooks.md`](https://github.com/QwenLM/qwen-code/blob/e38665674e2978f98cd35e7c6f6eac057741647f/docs/users/features/hooks.md) | Config, input, output and failure behavior |
| Hook types | [`packages/core/src/hooks/types.ts`](https://github.com/QwenLM/qwen-code/blob/e38665674e2978f98cd35e7c6f6eac057741647f/packages/core/src/hooks/types.ts) | Exact `PermissionRequest` decision shape |
| Logo | [`packages/desktop-shell/bootstrap/qwen-code-logo.svg`](https://github.com/QwenLM/qwen-code/blob/e38665674e2978f98cd35e7c6f6eac057741647f/packages/desktop-shell/bootstrap/qwen-code-logo.svg) | Official mark, template-rendered in the app |

Qwen's Hook input is explicitly forward-extensible. Dev Island ignores
unknown fields instead of rejecting a payload because a future optional field
appears.

## Managed configuration

Dev Island manages only command handlers containing `/hooks/qwen-code` in the
user-level `~/.qwen/settings.json` file. The installed shape is:

```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "curl … http://127.0.0.1:7824/hooks/qwen-code …",
            "timeout": 100000,
            "statusMessage": "Waiting for Dev Island"
          }
        ]
      }
    ]
  }
}
```

The `100000` timeout is milliseconds, as required by Qwen command Hooks. The
inner curl keeps a shorter 95-second bound. Lifecycle handlers use a two-second
curl timeout, discard stdout/stderr and finish with `|| true`. If Dev Island is
closed, Qwen keeps its native behavior instead of failing the turn.

Install and update merge with existing JSON. Uninstall removes only Dev
Island's handlers, including when they share a group with user-owned handlers.
Malformed roots, Hook containers or event arrays fail without changing the
original bytes. `disableAllHooks` and every unrelated setting are preserved.

## Subscribed events

| Qwen event | Dev Island state | Notes |
| --- | --- | --- |
| `SessionStart` | Running | New or resumed session |
| `UserPromptSubmit` | Running | A supported model-bound turn started |
| `PermissionRequest` | Waiting + island Allow/Deny | Uses Qwen's documented structured response |
| `Notification(permission_prompt)` | Waiting | Native attention fallback |
| `Notification(idle_prompt)` | Waiting | User input is useful |
| other `Notification` | Ignored | Does not invent attention state |
| `Stop` | Completed | Successful turn boundary |
| `StopFailure` | Failed | Only a bounded error category reaches task state |
| `SessionEnd` | Removed | Session no longer live |

High-frequency `MessageDisplay`, tool result, subagent and todo payloads are
not subscribed. This keeps the island quiet and avoids processing streamed
assistant content or tool results that are unnecessary for status.

## Permission response

The Preview implementation decodes `session_id`, `tool_name` and `tool_input`
from the documented request. Allow returns:

```json
{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}
```

Deny returns the same structure with `behavior: "deny"` and a short message.
A timeout, cancellation, app shutdown, malformed request or unavailable island
returns `{}`. Dev Island does not modify `updatedInput`, persist permission
suggestions or grant durable permissions.

## Data boundary

Qwen sends the complete event JSON to the managed command. It can include a
session ID, transcript path, cwd, timestamp, permission mode, prompt or model
content, tool input, assistant output, error details and future fields. The raw
body exists only long enough for the loopback request and is neither logged nor
persisted.

The lifecycle decoder retains only session ID, cwd, event category, tool name,
notification message/type and a bounded failure category. The permission form
holds a bounded rendered tool input in memory only while pending. Normalized
task state may enter local SQLite; terminal/tmux jump metadata remains in live
memory only.

## Verification completed

- forward-extensible lifecycle fixtures and ignored high-frequency payloads;
- status transitions, attention filtering and bounded failure categories;
- exact Allow/Deny/neutral response fixtures;
- real loopback HTTP request/response simulation;
- Qwen's millisecond timeout rendering;
- idempotent install/update and surgical uninstall;
- preservation of unrelated settings and user Hooks;
- malformed-config no-mutation behavior;
- official logo rasterization at both bundle densities.

## Real CLI acceptance still required

This Mac did not have Qwen Code installed or authenticated during the review.
Do not silently install it or edit a real `~/.qwen/settings.json` for testing.
Before removing Preview status, an owner-approved environment must pass:

1. install and sign in to exactly `@qwen-code/qwen-code@0.22.0`;
2. enable the connector from Settings and inspect Qwen's Hooks UI/debug output;
3. start two projects and confirm independent session identities;
4. trigger an actual permission request and verify Allow, Deny and timeout/native fallback;
5. verify Stop, StopFailure, resume and SessionEnd events;
6. close Dev Island and prove a Hook failure never blocks Qwen;
7. jump back to the emitting terminal and a real tmux pane;
8. disable the connector and confirm unrelated settings/Hooks remain;
9. complete unlocked visual, keyboard, VoiceOver, Reduced Motion, sound and notification QA.
