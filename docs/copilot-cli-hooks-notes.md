# GitHub Copilot CLI Hook integration notes

Last reviewed: 2026-08-26

## Release claim

Dev Island implements **GitHub Copilot CLI Preview** lifecycle and attention
observation. It is not counted as stable support and does not render an island
Allow/Deny control.

This Mac did not have a `copilot` executable on `PATH`; no package was
installed or executed, no GitHub login was attempted, and no real Copilot
configuration was read or changed. Promotion from Preview requires the real
acceptance checklist at the end of this document.

## Pinned official evidence

- npm package: `@github/copilot@1.0.80`
- official repository tag: `v1.0.80`
- tag commit: `ef627e1baad937d3c8da45f8a5541c6fc3c97b6a`
- official GitHub Docs Hook reference commit:
  `be8d08aa6e3a95d7f531c6a00cbeff883e4e9814`
- reference source:
  `content/copilot/reference/hooks-reference.md` in `github/docs`
- official Copilot mark: Primer Octicons `copilot-24.svg` at commit
  `0e21a4c2d8449102f10e533d241f04797af0914c`

The GitHub Docs reference documents versioned JSON Hook files, personal Hook
discovery under `~/.copilot/hooks/*.json`, command hooks, PascalCase
VS Code-compatible event names, notification categories, and failure behavior.
The npm version and docs snapshot must be re-pinned together before upgrading
this connector.

## Installed Preview contract

Dev Island owns one isolated personal Hook file:

`~/.copilot/hooks/dev-island.json`

It uses the documented top-level `version: 1` and flat command entries. Dev
Island subscribes only to six low-frequency PascalCase events:

| Hook | Dev Island state |
| --- | --- |
| `SessionStart` | Running |
| `UserPromptSubmit` | Running |
| `Notification(permission_prompt)` | Waiting · Needs approval |
| `Notification(elicitation_dialog)` | Waiting · Needs input |
| `Stop` | Completed |
| `ErrorOccurred(recoverable == false)` | Failed with a categorical phase |
| `SessionEnd` | Remove the live session |

PascalCase is deliberate. Copilot's documented compatible payload contains
`hook_event_name` and snake_case fields; the native camelCase payload examples
do not contain an event discriminator. Dev Island routes all events for one
Agent through one endpoint, so accepting native camelCase payloads would
require guessing the event from overlapping fields.

Informational notifications such as shell completion, subagent completion and
agent idle are ignored. Recoverable errors do not replace the last known live
state with a false terminal failure.

## Privacy and failure boundary

- The command sends stdin only to `http://127.0.0.1:7824/hooks/copilot-cli`.
- It bypasses configured proxies for numeric loopback, times out after two
  seconds, discards response output, and ends in `|| true`.
- If Dev Island is absent, slow, restarting, or unable to decode a future
  payload, Copilot continues without a Hook error.
- The complete forward-extensible Hook body may momentarily transit the local
  listener. Dev Island models only session ID, cwd, event kind, notification
  category, recoverability, and error category.
- Notification message/title, prompt, transcript, error message/stack, tool
  arguments, model output, and unknown fields are not retained or logged.
- Waiting copy is fixed (`Approval needed in Copilot CLI` / `Input needed in
  Copilot CLI`) so vendor- or tool-authored text cannot enter SQLite,
  notifications, diagnostics, or history through this Preview connector.
- Managed terminal/tmux headers are allowlisted and remain live-memory-only.

Installation is conservative: a missing dedicated file is created, unrelated
top-level values and Hook entries are preserved, installation is idempotent,
and uninstall removes only commands containing `/hooks/copilot-cli`. Invalid
JSON, incompatible Hook containers, or a non-`1` file version fail closed
without changing the original bytes. **Disconnect All…** includes this file in
the existing prepare-first, rollback-safe multi-file transaction.

## Why permission actions remain observe-only

The official reference proves that `permissionRequest` can return
`behavior: "allow" | "deny"`, but the reviewed reference does not publish a
complete `permissionRequest` input payload schema. Dev Island will not infer
an action request from adjacent `preToolUse` fields or put an unverified
approval response on a user's real CLI path.

The documented `preToolUse` schema is complete, but using it for island
approval would intercept ordinary tool execution rather than only requests
that Copilot's permission service would actually ask the user about. That
would add friction and change the Agent's security semantics, so it is not
used as a substitute.

## Automated evidence

The connector and installer suites cover:

1. the pinned compatible payload and ignored sensitive/unknown fields;
2. Running, attention, Completed, Failed, recovery and removal semantics;
3. fixed privacy-minimal waiting copy;
4. ignored informational notifications and recoverable errors;
5. exact descriptor, Preview and observe-only capability invariants;
6. versioned dedicated-file rendering and bounded fail-open command behavior;
7. preservation of user fields and unrelated Hooks;
8. idempotent install, stale managed-command repair, and surgical uninstall;
9. invalid JSON and wrong-version byte preservation; and
10. a real command → curl → loopback server → normalized Waiting event with
    terminal/tmux context and no action request.

## Real acceptance checklist

1. Under owner supervision, install or run exactly
   `@github/copilot@1.0.80` in a non-sensitive test directory and sign in.
2. Enable the connector in Dev Island, then verify
   `~/.copilot/hooks/dev-island.json` is accepted by Copilot with no warning.
3. Exercise a new session, resumed session, prompt, main-agent stop,
   non-recoverable error and session end; compare captured categories with the
   official reference without recording prompt/model content.
4. Trigger a permission prompt and an elicitation dialog. Verify the island
   raises attention without suppressing or replacing Copilot's native UI.
5. Trigger informational notification categories and recoverable errors;
   verify they do not steal attention or overwrite the last good state.
6. Quit Dev Island and repeat a turn; verify the two-second fail-open command
   cannot block or fail Copilot.
7. Disable the connector and run **Disconnect All…** in separate fixtures;
   verify unrelated personal/repository/policy/plugin Hooks survive.
8. Run two repositories and colliding vendor-local session IDs, then verify
   stable attention ordering, total-session copy and exact terminal return.
9. Complete unlocked visual, keyboard, VoiceOver, Reduced Motion,
   notification and sound acceptance.

Only after this checklist passes may documentation promote GitHub Copilot CLI
from Preview to stable or add island Allow/Deny support.
