# Dev Island — Next Connector Wave

Last evidence review: 2026-08-27

This is an implementation order, not a stable-support claim. A connector stays
explicitly labeled **Preview** in the README until its exact installed CLI
version passes the real acceptance gates below.

## Priority order

| Order | Agent | Why next | Verified integration surface | Main implementation risk | Current gate |
| ---: | --- | --- | --- | --- | --- |
| 1 | **Gemini CLI Preview → Stable** | Code, installer and simulated loopback path already exist; finishing it creates more value than starting another partial connector | Official lifecycle and `Notification(ToolPermission)` Hooks already pinned in `gemini-cli-hooks-notes.md` | No signed-in `@google/gemini-cli@0.57.0` on this Mac | Real CLI install/login and end-to-end acceptance |
| 2 | **Qwen Code Preview → Stable** | Preview code now covers low-frequency lifecycle, attention and the documented structured `PermissionRequest` decision | Pinned `0.22.0`; JSON command Hooks; exact response types; merge-safe user config | No installed, signed-in Qwen CLI is available, so payload timing and real fallback remain unproven | Real CLI install/login, actual Allow/Deny/timeout and Hooks UI/debug acceptance |
| 3 | **GitHub Copilot CLI Preview → Stable** | Broad developer reach; the Preview now has low-frequency lifecycle/attention, an isolated personal Hook file and official logo | Pinned `@github/copilot@1.0.80`; versioned personal command Hooks; compatible lifecycle, notification, stop and error payloads | No installed/signed-in CLI; official reference publishes permission output but not the complete `permissionRequest` input schema | Real CLI acceptance; keep actions observe-only until the complete request schema is pinned |
| 4 | **Kimi Code CLI Preview → Stable** | Strong fit for the Chinese developer market; the Preview now surfaces the real approval boundary without intercepting decisions | Pinned `@moonshot-ai/kimi-code@0.38.0` default v2 engine; eight low-frequency TOML command Hooks; syntax-validated byte-preserving install/update/uninstall; cross-format rollback; official logo | No installed/signed-in `0.38.0` CLI; native reload, timing and fallback are unproven; opt-in legacy engine is outside the Preview contract | Real default-engine install/login, permission request/result, failure, interrupt, reload, jump-back and human UI acceptance |
| 5 | **OpenCode Preview → Stable** | Broad developer reach; fixture work now proves a privacy-minimal observation path and lifecycle-safe complete-file plugin ownership | Pinned OpenCode / `@opencode-ai/plugin` `1.18.23` at commit `13c2759…`; seven low-frequency events; global plugin directory | No installed/signed-in CLI; plugin discovery/reload, event timing and native fallback remain unproven; mutable `permission.ask` is deliberately unused | Real CLI install/login and lifecycle/permission acceptance; keep actions observe-only |

The order intentionally favors depth and safe maintenance over a large badge
count. Qwen has a documented Preview action path; Copilot may reach island
actions only after its complete request payload is published and verified.
Kimi and OpenCode have earned fixture-verified lifecycle/attention Previews
and now need real CLI acceptance. OpenCode's standalone plugin architecture is
implemented, but the real global plugin directory remains untouched.

## Evidence pinned for this review

- Qwen Code Hooks at commit
  [`e38665674e2978f98cd35e7c6f6eac057741647f`](https://github.com/QwenLM/qwen-code/blob/e38665674e2978f98cd35e7c6f6eac057741647f/docs/users/features/hooks.md).
- GitHub Copilot CLI package `@github/copilot@1.0.80` / tag commit
  [`ef627e1baad937d3c8da45f8a5541c6fc3c97b6a`](https://github.com/github/copilot-cli/tree/ef627e1baad937d3c8da45f8a5541c6fc3c97b6a), plus the official GitHub Docs Hook reference at commit
  [`be8d08aa6e3a95d7f531c6a00cbeff883e4e9814`](https://github.com/github/docs/blob/be8d08aa6e3a95d7f531c6a00cbeff883e4e9814/content/copilot/reference/hooks-reference.md). The compatible lifecycle/notification schema is pinned; the complete `permissionRequest` input schema is still absent, so actions remain observe-only.
- Kimi Code package `@moonshot-ai/kimi-code@0.38.0` / release commit
  [`0999454bdcb5ddd98f39bffee434dcf0a810f394`](https://github.com/MoonshotAI/kimi-code/tree/0999454bdcb5ddd98f39bffee434dcf0a810f394),
  including the
  [Hook reference](https://github.com/MoonshotAI/kimi-code/blob/0999454bdcb5ddd98f39bffee434dcf0a810f394/docs/en/customization/hooks.md),
  strict TOML Hook schema, default-v2 engine gate, permission request/result
  event wiring and official VS Code mark. The retired Python
  `MoonshotAI/kimi-cli` repository is not the implementation target.
- OpenCode plugin interface at commit
  [`13c27598d35f6f91fa4763a0b61a220ab7fcb263`](https://github.com/anomalyco/opencode/blob/13c27598d35f6f91fa4763a0b61a220ab7fcb263/packages/plugin/src/index.ts),
  generated SDK Event union, and the official global plugin path. The exact
  Dev Island boundary is recorded in
  [`opencode-plugin-notes.md`](opencode-plugin-notes.md).

These references prove an integration surface exists. They do not prove Dev
Island compatibility, installed-version behavior, or successful real use.

## Acceptance gates for every connector

| Gate | Required evidence |
| --- | --- |
| 1. Version pin | Exact CLI version and upstream commit/schema recorded in a connector note |
| 2. Data boundary | Complete inbound fields documented; sensitive fields classified; raw bodies prohibited from logs |
| 3. Config safety | Install/update/uninstall fixture tests preserve unrelated user entries byte-for-byte or semantically without format loss |
| 4. Failure behavior | Dev Island offline, loopback busy, timeout, malformed payload and app shutdown all preserve the Agent's native fallback |
| 5. Lifecycle | Real start, prompt, running, waiting, completion, failure, resume and end captured where the vendor exposes them |
| 6. Interaction | Allow/Deny or answers appear only after the vendor's exact synchronous response contract is captured and tested |
| 7. Multi-session | Two projects plus same vendor-local session ID collision test; stable attention ordering and total-session count verified |
| 8. Return | Actual emitting terminal is activated; tmux pane verified when applicable; no false claim for ordinary terminal tabs |
| 9. User control | Settings state, Update indicator, individual disconnect and Disconnect All rollback pass |
| 10. Human QA | Unlocked visual, keyboard, VoiceOver, Reduced Motion, notification and sound acceptance recorded |

## Current machine constraint

At review time only Claude Code (`2.1.197`) was available as a local CLI.
Gemini, Qwen, Kimi, OpenCode, Copilot, Amp, Kiro and Trae commands were not
installed. Dev Island did not install, authenticate, launch or edit any of
them during this review—including the real
`~/.config/opencode/plugins/` directory. Therefore all new-connector work
remains fixture-level until the owner chooses a real CLI acceptance
environment.
