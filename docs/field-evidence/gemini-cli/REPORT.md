# Gemini CLI 0.57.0 — Windows real event evidence

Captured 2026-10-29 and 2026-10-30 (UTC), Windows with Node 22.14.0.
Invoked the separately installed 0.57.0 bundle directly; the interactive banner
and package metadata confirmed that version. Authentication used the user's
locally configured API-key mode; credentials were not read or exported.
Model for successful tests: gemini-3.8-flash, explicitly selected.

Project-only hooks registered SessionStart, BeforeAgent, Notification,
AfterAgent and SessionEnd, invoking the silent capture helper. Commands returned
no approval decision. Approvals used the native default approval mode.

## Scenarios

| Scenario | Observation |
| --- | --- |
| New turn and exit | Prompt-mode hi: SessionStart → BeforeAgent → AfterAgent → SessionEnd, exit 0. |
| Resume | Project A `--resume latest` returned resumed; lifecycle events retained session hash 60b72845. |
| Allow | Project B's native Allow once created a test file containing hello; AfterAgent followed. |
| Deny | Esc at the next write prompt showed Rejected and Request cancelled; the target did not exist. No AfterAgent was recorded for that rejected turn. |
| Wait/cancel | A third write stayed pending from 00:23:45 until approximately 00:24:50, without an automatic timeout. Ctrl+C displayed Request cancelled and Rejected; target absent. No AfterAgent for that turn. This is a bounded observation, not a claim that no longer timeout exists. |
| Mid-generation Ctrl+C | A long response was visibly streaming when interrupted. AfterAgent at 00:25:22 contained the partial response shape, stop_hook_active=false, and 15462 bytes. |
| API failure | An intentionally nonexistent model returned ModelNotFoundError/404 and exit 1. SessionStart → BeforeAgent → SessionEnd; no AfterAgent. No key or network configuration changed. |
| Concurrent projects | Project B e140aab9 remained at native approval while A 60b72845 completed hi and resume. Distinct IDs confirmed; not simultaneous model generation. |
| Remove configuration | After /quit, removed only our hooks from both project settings, preserving other keys and private backups. Fresh pinned-version hi returned exit 0; the separate local capture store stayed at 47 records. The committed export contains 30 pinned-version events; the other 17 local records belong to excluded earlier/version-unverified sessions. The unchanged local count is an operator observation, not independently provable from this filtered export. |

## Connector questions

- Observed Notification category: **ToolPermission**, for native file writes.
  No other category was observed; this is not an exhaustive vendor list.
- Notification was already captured when the native menu was inspected. The
  recorded event precedes our Allow/Reject action. Terminal polling does not
  establish whether it preceded the first painted UI frame.
- Largest observed AfterAgent: **15462 bytes**, below 1 MiB. This sample does
  not establish a maximum payload size; long responses can grow further.
- `/hooks panel` showed project hooks enabled, without a parsing warning in
  the inspected panel. Terminal color-support warnings are separate.

ToolPermission shape includes session_id, transcript_path, cwd, hook_event_name,
timestamp, notification_type, message and details. The observed details fields
are type/title/fileName/filePath/fileDiff/originalContent/newContent. All string
content and paths are length markers in the exported timeline.

Normal exit may emit **two SessionEnd records** for the same session. Consumers
should not treat them as two distinct sessions. No synthetic deduplication has
been applied to the evidence.

## Version boundaries and limitations

The globally installed Gemini was found to be 0.66.0 during earlier attempts.
Those attempts saw 503/retries, an unavailable model, cancellation and duplicate
SessionEnd; they are excluded from this pinned-version timeline. Earlier user
hi evidence with an unverified execution version is also excluded.

The first pinned interactive attempt encountered trust/restart behavior and
reached a ToolPermission event, but did not yield a verified completed approval.
Its partial session 9b3452dc remains explicitly incomplete. October 30's fresh
session supplies native allow/deny observations. A background update notice
appeared during the fresh session; the running banner remained 0.57.0 and the
isolated package metadata was still 0.57.0. No subsequent run is assumed pinned
without that direct bundle/version check.

Raw payloads, prompts, full paths and credentials remain local. Exported JSONL
was parsed and checked for ordinary field names and only known enum or
length/hash/type string values. IDs are correlation aids, not encryption.

Remaining owner work: macOS decoding/state mapping, UI and terminal-return
acceptance, payload-limit handling and Preview promotion. No Swift code or
support-status claims change in this evidence PR.
