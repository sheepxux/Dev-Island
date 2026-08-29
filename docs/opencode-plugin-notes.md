# OpenCode Plugin Notes — Preview Contract

Last reviewed: 2026-08-29

OpenCode support is a **fixture-verified Preview**, not a stable-support claim.
The implementation is pinned to OpenCode / `@opencode-ai/plugin` **1.18.23**
at commit
[`13c27598d35f6f91fa4763a0b61a220ab7fcb263`](https://github.com/anomalyco/opencode/tree/13c27598d35f6f91fa4763a0b61a220ab7fcb263).
No real OpenCode configuration, login, process or plugin directory was changed
while establishing this contract.

## Reviewed upstream surfaces

- Plugin function and Hook types:
  [`packages/plugin/src/index.ts`](https://github.com/anomalyco/opencode/blob/13c27598d35f6f91fa4763a0b61a220ab7fcb263/packages/plugin/src/index.ts)
- Generated Event union:
  [`packages/sdk/js/src/gen/types.gen.ts`](https://github.com/anomalyco/opencode/blob/13c27598d35f6f91fa4763a0b61a220ab7fcb263/packages/sdk/js/src/gen/types.gen.ts)
- Official plugin directory convention:
  `~/.config/opencode/plugins/`
- Official dark square brand mark:
  [`packages/console/app/src/asset/brand/opencode-logo-dark-square.svg`](https://github.com/anomalyco/opencode/blob/13c27598d35f6f91fa4763a0b61a220ab7fcb263/packages/console/app/src/asset/brand/opencode-logo-dark-square.svg),
  SHA-256
  `d6a0e3b8a295f413543f41cb73957e670351b5cb088c8d9dbd186b9e9d633cca`.
  Dev Island keeps the official geometry and converts its two fills to
  adaptive template alpha only at asset-generation time. The upstream MIT
  notice is bundled as `opencode-MIT-LICENSE`; this nominative logo use does
  not imply affiliation or endorsement.

The upstream API also exposes a mutable `permission.ask` output. Dev Island
does **not** use or modify it in this Preview. A real signed-in session must
prove its timing, decision semantics and native fallback before island actions
can be considered.

## Dev Island envelope

The dependency-free `dev-island.js` plugin allowlists seven low-frequency
events before posting to `http://127.0.0.1:7824/hooks/opencode`:

| Event | Retained fields | Dev Island state |
| --- | --- | --- |
| `session.created` | schema version, session ID, cwd | Running |
| `session.status` | schema version, session ID, cwd, `busy` / `idle` / `retry` | Running / Completed / Running |
| `session.idle` | schema version, session ID, cwd | Completed |
| `session.deleted` | schema version, session ID, cwd | Remove session |
| `session.error` | schema version, session ID, cwd | Failed with fixed product copy |
| `permission.updated` | schema version, session ID, cwd | Waiting with fixed approval copy |
| `permission.replied` | schema version, session ID, cwd | Running |

`retry` remains Running because it is vendor activity, not a request for human
intervention. Only `permission.updated` enters the human-attention queue.

Titles, prompts, messages, tool arguments, permission metadata, raw errors and
future vendor fields are not modeled or forwarded. The Swift decoder accepts
only schema version 1, a non-empty session ID, the seven event categories and
the three documented status values. Unknown events/status values are dropped.

Delivery is deliberately fail-open: `void fetch(...)` is not awaited, uses a
one-second `AbortController`, ignores network failure, and has no npm/runtime
dependency beyond globals already supplied by the OpenCode process. A stopped
Dev Island therefore cannot delay or fail an OpenCode turn.

Every plugin POST includes the shared `X-Dev-Island-Hook: v1` protocol Header.
The listener also rejects `Origin` and never authorizes CORS, so browser fetch
must fail its preflight and a simple HTML form cannot inject lifecycle or
permission-attention state. A separate 256-bit `X-Dev-Island-Authorization`
value rotates for each listener epoch. The plugin contains only its stable
owner-only Header-file path, uses a bounded Bun Blob slice to read and strictly
parse at most 128 bytes for each event, and never embeds the value in source.
Missing or malformed credentials skip delivery without failing the OpenCode
turn. This blocks other macOS users; processes under the current login that can
read the `0600` file remain inside the explicit local-user trust boundary.

The generated envelope is also exercised through an actual ephemeral
`127.0.0.1` Hummingbird listener and the registry-derived
`/hooks/opencode` route. That regression proves HTTP 200 / `{}` response,
privacy-minimal decoding and observe-only Waiting delivery without touching a
real OpenCode process or configuration. It is local route evidence, not a
substitute for the signed-in CLI promotion gates below.

## Installation and ownership boundary

The managed path is:

```text
~/.config/opencode/plugins/dev-island.js
```

Dev Island owns the complete file only when its exact marker is present:

```text
Dev Island managed local plugin: opencode
```

Install/update/uninstall behavior is fail-closed:

- create a missing file with mode `0600`;
- update only a regular, bounded file carrying the ownership marker;
- never overwrite or delete an unowned collision;
- reject symlinks, directories, devices and files over 256 KiB;
- keep installation idempotent and repair managed-file permissions;
- include deletion in Disconnect All's prepare-first, compare-before-write
  transaction;
- restore a deleted file and its permissions after a later write failure, but
  never overwrite an externally recreated file or dangling symlink.

These are local fixture guarantees. Ancestor-directory ownership and actual
OpenCode reload behavior still require a real-user acceptance run.

## Promotion gates

OpenCode must remain Preview until all of the following are recorded against
the exact pinned CLI:

1. install/login and plugin discovery from the global directory;
2. start, busy, retry, idle, error and delete lifecycle timing;
3. permission requested/replied timing without duplicate or stale attention;
4. two simultaneous projects and stable total-session presentation;
5. app stopped, loopback unavailable and one-second abort preserve the native
   OpenCode flow;
6. update, reload, individual disconnect and Disconnect All against a real
   user configuration;
7. terminal/tmux return behavior;
8. unlocked visual, keyboard, VoiceOver, Reduce Motion, notification and sound
   review;
9. only after the complete `permission.ask` contract is captured: explicit
   Allow/Deny/timeout/native-fallback tests before enabling island actions.

Until then, the Settings row must say Preview, capability remains
`permissionRequests: .observeOnly`, and approval is completed in OpenCode.
