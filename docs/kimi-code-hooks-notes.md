# Kimi Code CLI Preview — pinned Hook notes

Last evidence review: 2026-08-26

Status: **Preview**. Implementation, fixtures and a real managed-command →
loopback receiver test pass. No Kimi Code binary was installed, authenticated,
launched or configured on this Mac, so this document is not a real-session
acceptance record.

## Pinned product identity

- Product/package: `@moonshot-ai/kimi-code@0.38.0`
- Repository: [`MoonshotAI/kimi-code`](https://github.com/MoonshotAI/kimi-code)
- Peeled release commit:
  [`0999454bdcb5ddd98f39bffee434dcf0a810f394`](https://github.com/MoonshotAI/kimi-code/tree/0999454bdcb5ddd98f39bffee434dcf0a810f394)
- Runtime requirement: Node `>=22.19.0`
- User configuration: `~/.kimi-code/config.toml`
- Upstream Hook reference:
  [`docs/en/customization/hooks.md`](https://github.com/MoonshotAI/kimi-code/blob/0999454bdcb5ddd98f39bffee434dcf0a810f394/docs/en/customization/hooks.md)
- Strict Hook schema:
  [`packages/agent-core-v2/src/features/externalHooks/configSection.ts`](https://github.com/MoonshotAI/kimi-code/blob/0999454bdcb5ddd98f39bffee434dcf0a810f394/packages/agent-core-v2/src/features/externalHooks/configSection.ts)
- Event and permission wiring:
  [`packages/agent-core-v2/src/features/externalHooks/`](https://github.com/MoonshotAI/kimi-code/tree/0999454bdcb5ddd98f39bffee434dcf0a810f394/packages/agent-core-v2/src/features/externalHooks)

The older Python repository/package `MoonshotAI/kimi-cli` is in migration and
is not Dev Island's target. Reusing its old `~/.kimi/config.toml` path or its
event assumptions would configure the wrong product.

Kimi Code 0.38.0 selects agent-core-v2 by default for the interactive TUI and
`kimi -p`. `KIMI_CODE_LEGACY_FLAG` explicitly opts into the older engine. This
Preview targets the current default engine only; it does not claim compatibility
with the legacy flag.

## Upstream event surface and selected subset

The default v2 source accepts 20 event names:

```text
PreToolUse             PostToolUse          PostToolUseFailure
PermissionRequest      PermissionResult     UserPromptSubmit
UserPromptQueued       TurnStarted          Stop
StopFailure            Interrupt            SessionStart
SessionEnd             SessionHeartbeat     SubagentStart
SubagentStop           TaskStarted          PreCompact
PostCompact            Notification
```

Dev Island subscribes to only eight:

| Event | Upstream behavior | Dev Island state |
| --- | --- | --- |
| `SessionStart` | Session created/resumed | Running |
| `TurnStarted` | Fire-and-forget after a turn begins | Running |
| `PermissionRequest` | Fire-and-forget immediately before native approval | Waiting with fixed “Approval needed in Kimi Code CLI” copy |
| `PermissionResult` | Fire-and-forget after native approval resolves | Running |
| `Stop` | Blockable end-of-turn Hook; Dev Island always exits neutral/allow | Completed |
| `StopFailure` | Observation-only categorical failure | Failed with an allowlisted category |
| `Interrupt` | Observation-only user cancellation | Completed, phase “Interrupted” |
| `SessionEnd` | Session exited/archived | Remove live session |

`TurnStarted` is intentional. `UserPromptSubmit` is blockable and runs before
the model call; putting a passive status integration there would add an
unnecessary synchronous dependency to every submitted prompt.

High-frequency tool events and compaction events are not needed for a glanceable
surface. `UserPromptQueued` and `TurnStarted` payloads can carry prompt text, but
the selected decoder models no prompt field. `SessionHeartbeat` would create
unnecessary traffic. `TaskStarted` and `Notification` describe background work
that the current generic connector cannot yet represent as nested child tasks;
mapping them onto the parent would invent misleading state.

## Interaction boundary

Kimi's `PermissionRequest` and `PermissionResult` wiring calls
`fireAndForget`; Hook stdout cannot approve or deny the pending request. Dev
Island therefore declares `permissionRequests == .observeOnly`, has no action
decoder/response encoder, and must never render Allow/Deny for Kimi.

Kimi's own UI remains the single decision surface. `PermissionResult` tells the
island when it can leave Waiting. This gives useful attention without creating
two competing approval authorities.

Although `Stop` is blockable upstream, Dev Island's command discards stdout,
ends in `|| true`, and is bounded by curl's two-second timeout plus a five-second
Kimi Hook timeout. It cannot ask the model to continue or inject content.

## Data minimization

The complete Hook JSON body transits only the loopback request. Depending on
event, upstream may include session title/client/cwd, prompt and turn origin,
tool name/input/display, approval decision/feedback, error message, task data
and future fields.

`KimiCodeEvent` decodes only:

```text
hook_event_name
session_id
cwd
error_type
```

Raw bodies are not retained or logged. Tool input, permission display, prompts,
session titles, error messages, feedback and future fields have no model slot
and cannot reach task persistence accidentally. Only a small `error_type`
allowlist changes the user-facing phase; every unknown class becomes the fixed
“Turn failed” label.

The managed shell command adds only bounded terminal/tmux headers already used
by the other terminal connectors. They are validated again at the HTTP boundary
and remain live-memory-only.

## Lossless TOML maintenance

Kimi stores user settings and Hooks in the same TOML document. Re-encoding the
whole file would normalize formatting, reorder keys and destroy comments, so
Dev Island does not serialize user TOML.

The installer instead:

1. parses the complete UTF-8 document with exactly pinned `swift-toml` 2.0.0;
2. locates only real TOML comment markers outside basic, literal and multiline
   strings;
3. removes only complete Dev Island managed blocks whose parsed body is exactly
   one strict `[[hooks]]` row containing `/hooks/kimi-code`;
4. appends the current eight generated rows without changing any existing byte;
5. records ownership of a delimiter newline when the original file had no
   trailing newline, so uninstall restores that original shape exactly;
6. parses and verifies the complete candidate again before an atomic write.

The upstream Hook schema allows only `event`, `matcher`, `command` and `timeout`.
Unknown fields inside a managed block therefore fail closed. Malformed TOML,
invalid UTF-8, incomplete/nested markers, marker-to-row count disagreement and
unwrapped older endpoint entries all remain byte-for-byte unchanged and require
manual review.

Comments, ordering, whitespace, dates, inline tables, unknown non-Hook settings
and user-owned Hooks survive install/update/uninstall. “Disconnect All” prepares
JSON and TOML edits before its first write, compares each original immediately
before writing, preserves file permissions, rolls earlier writes back after a
later failure, and never overwrites a concurrent external edit.

## Logo provenance

The source mark is Kimi Code 0.38.0's
`apps/vscode/resources/kimi-icon.svg` at the pinned commit.

```text
source SVG SHA-256  60685e25b2db869030290485a35eed8ca77e535d2c6b7731374df49edbfa98c8
40 px PNG SHA-256   bf7b0b9ce75f3986caaaa8360ca986eb3129ac42d23e420f72f6be3d5b9e825b
80 px PNG SHA-256   b24739d6a5c3e179da4fd71214e97a60d3681166566215cf7892dc9f925ca81e
```

The transparent monochrome source is used as a SwiftUI template and receives
Dev Island's semantic tint at runtime.

## Automated evidence

The test suites cover:

- exact descriptor/version/event/capability assumptions;
- lifecycle, permission request/result, failure sanitization, interruption and
  session removal;
- unusable IDs, unknown events and same-ID cross-source isolation;
- missing-file install, exact eight-row rendering, idempotence and stale update;
- comments/order/whitespace and user-Hook preservation;
- exact round-trip with and without a terminal newline;
- marker-looking text inside multiline basic/literal strings;
- malformed TOML, incomplete markers, unwrapped endpoints and unknown managed
  fields failing without mutation;
- JSON + TOML Disconnect All preparation, permission preservation and rollback;
- real installed command → `127.0.0.1` route → normalized Waiting event,
  including validated terminal/tmux context and no actionable approval request.

## Required real `0.38.0` acceptance

Promotion from Preview requires an owner-approved environment with Node
`>=22.19.0`, the default v2 engine and an authenticated Kimi account. Record all
of the following without putting prompts, tokens or tool input in the evidence:

1. Existing comments, user Hooks and formatting survive enable, update,
   disable and Disconnect All; Kimi reloads the result successfully.
2. Start/resume and turn start produce Running without noticeable prompt-submit
   latency.
3. A real manual tool approval produces Waiting before the native prompt;
   approve, reject and cancel each produce `PermissionResult` and return Running.
4. Normal stop, provider/auth/rate-limit failure, user interrupt, exit and archive
   map to the documented states exactly once.
5. Dev Island stopped, loopback port occupied, request timeout, malformed body,
   app sleep/wake and app shutdown never block or corrupt a Kimi turn.
6. Two simultaneous projects remain distinct; clicking each returns to the
   actual terminal and selects its tmux pane when present.
7. Settings, compact island, expanded panel, notification/sound, keyboard,
   VoiceOver and Reduced Motion behavior pass on an unlocked display.

Until that record exists, product copy must say **Kimi Code CLI — Preview**, and
must not claim native approval, legacy-engine compatibility or stable support.
