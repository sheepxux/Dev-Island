# Codex integration field notes

Last official-source review: 2026-08-26

Status: the shipping integration remains a local Hook connector. A short-lived,
read-only App Server process is now used only to verify whether the exact Dev
Island Hooks are enabled and trusted; it is not a thread/session connector.
Codex Cloud task monitoring is not a public integration surface found in the
current official documentation.

## Decision summary

| Surface | What official documentation establishes | Dev Island decision |
| --- | --- | --- |
| Local Hooks | Codex loads user Hooks from `~/.codex/hooks.json` or inline config; non-managed definitions are trusted by their current hash and new/changed definitions are skipped until reviewed | Keep the existing local loopback integration. File inspection proves **Configured**; only the bounded trust probe may promote the exact definitions to **Connected** |
| App Server | A client-owned local JSONL protocol over stdio exposes threads, turns, approvals, events, and `hooks/list`; the current generated schema includes per-Hook `enabled`, `currentHash`, and `trustStatus`; WebSocket transport is experimental | Ship only the narrow `hooks/list` trust probe described below. Full thread/session control remains future work and must not take over a user's unrelated Codex process |
| Codex SDK | TypeScript and Python clients drive Codex threads through a local App Server runtime | Do not describe it as a Codex Cloud task-list API |
| Codex Cloud | Official docs describe ChatGPT/Codex UI, repository environments, and background tasks | No public API was found for listing or monitoring a user's existing Codex Cloud tasks; mark unsupported instead of leaving “API TBD” |
| Responses background mode + Webhooks | Generic Responses API jobs can run in the background and emit signed Webhooks | Treat this as a separate OpenAI API integration. Never label generic Responses jobs as Codex Cloud sessions |

## Current local Hook mode

Dev Island writes only its managed groups in `~/.codex/hooks.json`, preserving
the user's other keys and Hooks. Lifecycle events are short, passive loopback
posts. `PermissionRequest` is a bounded synchronous loopback request so the
island can return Codex's documented allow/deny response; timeout, app exit, or
listener failure returns a neutral result and leaves Codex's native path in
control.

Writing the file is not the final activation step. Codex requires review and
trust of the exact non-managed Hook definition and records that trust against
the current definition hash. A changed command therefore needs review again.
Dev Island does not read undocumented state to guess that decision. Its
configuration diagnostic has four states:

- `connected`: exact config is present and either the vendor has no separately
  declared activation gate or the documented vendor check proves that gate;
- `configured`: exact config is present, but the vendor-owned trust/activation
  result is not proved by config alone;
- `update-required`: a Dev Island entry exists but differs from the current
  managed definition;
- `disconnected`: no managed entry is present.

For Codex, an exact install first maps to `configured`. Welcome, Settings, CLI,
and Support run the read-only probe and promote it to `connected` only when all
exact Dev Island definitions are enabled and `trusted` or `managed`. Every
unavailable, timeout, parse, schema, discovery, disabled, modified, untrusted,
missing, path, event, or command mismatch fails conservatively back to
`configured`; Settings keeps `/hooks` guidance and offers **Check again**.
The exposed diagnostic remains low-cardinality and includes no paths, hashes,
Hook contents, prompts, or session identifiers.

## Shipping bounded App Server trust probe

The official App Server protocol documents `hooks/list`. A read-only check with
the installed `codex-cli 0.149.0-alpha.4.3` generated its v2 JSON Schema in a
temporary directory and confirmed that `HookMetadata` includes `enabled`,
`currentHash`, `sourcePath`, and `trustStatus`; the trust enum is `managed`,
`untrusted`, `trusted`, or `modified`. A short-lived stdio probe also returned
those fields without changing Hook configuration. No generated schema or raw
probe output is retained in the repository because real results contain local
paths and command definitions.

The shipping probe starts only the `codex` binary embedded in an installed
`com.openai.codex` application signed by OpenAI team `2DC432GLL2`. It does not
search PATH or run package-manager shims. The child receives a minimal
environment and exactly `app-server --stdio`, followed by `initialize`,
`initialized`, and `hooks/list` for the current home directory.

The request is capped at 64 KiB, the response at 2 MiB, and the complete
exchange at three seconds. The shipping path no longer uses Foundation
`Process`, a reader thread, a semaphore, or run-loop completion. It launches an
independent POSIX process group, writes stdin and drains stdout concurrently
through nonblocking descriptors and `poll`, and uses a monotonic deadline. A
direct child that exits without the requested response fails immediately
instead of making Settings wait for the full timeout. Response, timeout,
overflow, I/O failure, and early exit all terminate and reap the direct child
and any background descendants through a bounded TERM-to-KILL sequence.
The parent write descriptor suppresses Darwin `SIGPIPE`, so an App Server that
closes stdin during launch becomes a local I/O failure instead of terminating
Dev Island.

stderr is discarded, and raw request/output bytes exist only in memory until
best-effort erasure. Dev Island ignores unrelated Hook rows and requires every
expected source path, event, and command to match with `enabled == true` and
`trustStatus` equal to `trusted` or `managed`. Failure or schema drift never
upgrades the status. The process never writes config, changes trust, starts a
Codex thread, logs output, or contacts a Dev Island service.

## Optional future full App Server mode

Before using App Server for thread/session control or public copy beyond Hook
trust status, require all of the following:

1. Pin a Codex CLI/App Server version and generated request/response schema.
2. Start only a Dev Island-owned process and shut it down transactionally.
3. Prove reconnect, cancellation, sleep/wake, version skew, and absent-CLI
   behavior with a real signed-in installation.
4. Keep local Hook mode available and reversible; App Server adoption must not
   rewrite unrelated Codex configuration or migrate sessions silently.

Until those gates pass, full App Server control remains documented research,
not a shipping session connector or a cloud connector.

## Official sources

- [Codex Hooks](https://learn.chatgpt.com/docs/hooks)
- [Review and trust Hooks](https://learn.chatgpt.com/docs/hooks#review-and-trust-hooks)
- [Codex Hook configuration locations](https://learn.chatgpt.com/docs/config-file/config-advanced#hooks)
- [Codex App Server](https://learn.chatgpt.com/docs/app-server)
- [Codex SDK](https://learn.chatgpt.com/docs/codex-sdk)
- [Codex Cloud](https://learn.chatgpt.com/docs/cloud#getting-started)
- [OpenAI Webhooks](https://developers.openai.com/api/docs/guides/webhooks)
