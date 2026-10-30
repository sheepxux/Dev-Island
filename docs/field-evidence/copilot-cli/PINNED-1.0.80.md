# Copilot CLI 1.0.80 — additional Windows observations

2026-10-29, UTC. Invoked the installed native 1.0.80 executable directly with
`--no-auto-update`; verified version in the terminal. Same capture helper and
project hook configuration as REPORT.md. No credentials or raw payloads included.
`timeline-1.0.80.jsonl` contains only the two sessions from this run.

| Scenario | Observation |
| --- | --- |
| New sessions | Two isolated project sessions were open concurrently, with hashes `0a078e60` and `28a98209`; both replied hi. Requests themselves did not overlap. |
| Resume | Project B exited normally, then resumed using its explicit session identifier. The resumed prompt, SessionStart and Stop retained hash `28a98209`. |
| Allow | Native single-use Yes created a file containing hello; Stop followed. |
| Deny | Native No plus an explanation rejected a new file creation. The target was absent; Stop followed. |
| Interrupt generation | Ctrl+C while a long response was visibly streaming displayed Operation cancelled by user. No Stop/ErrorOccurred was recorded for that interrupted turn before SessionEnd. |
| Exit | Both projects recorded SessionEnd on /exit. |

In these startup runs UserPromptSubmit was recorded before SessionStart. Consumers
must not assume the reverse order from this capture. Both permission aliases again
received camelCase sessionId/toolName/toolInput with file_path/diff; notification
type was permission_prompt. Both aliases represent one native request.

An earlier attempted deny used batched arrow keys that did not select No: the
file was created, so that attempt is classified as an additional allow, not a
successful denial. The successful repeat used separate key presses and verified
the denied file was absent. A conversational approval question preceded the
earlier attempt; that question is not the native file permission decision.

## Follow-up: waiting, failure and cleanup

At 18:02:11 UTC the native permission menu was left untouched. It remained open
for about 85 seconds without a timeout or further hook event. Ctrl+C cancelled
the request; the target file was absent. No Stop/ErrorOccurred followed the
cancellation; /exit recorded SessionEnd at 18:03:41. This bounds the observation
window; it does not prove there is no longer timeout.

A process-local unreachable HTTP(S) proxy stopped GitHub token validation before
a model turn. That startup failure did not produce ErrorOccurred. No stored
credentials or system proxy settings were changed.

A separate process used documented offline/BYOK mode with an unreachable
loopback endpoint (port 1) and no API key. This is an induced transport failure,
not evidence of a GitHub-hosted API failure. The real CLI emitted six
ErrorOccurred records at 18:05:48–18:06:03; every one had `recoverable: true`,
including the last attempt before the terminal reported retry exhaustion.
Fields: error.message/name/stack, error_context, session_id, timestamp, cwd and
hook_event_name. No `recoverable: false` was observed; do not infer false from
the terminal's final error. /exit recorded SessionEnd.

After closing both pinned sessions, their two project hook files were moved to
private backups. A fresh 1.0.80 prompt-mode hi completed with exit 0 and no new
timeline events (last record remained 18:06:50). No global hooks changed.

Remaining limitations: recoverable=false and other notification categories have
not been observed; network failure coverage is limited to the cases above.
macOS integration acceptance remains with the owner.
