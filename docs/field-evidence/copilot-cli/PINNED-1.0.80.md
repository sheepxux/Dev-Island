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

Still pending for this pinned version: a dedicated approval timeout/cancel run,
controlled API/network failure and recoverable classification, configuration
removal with a clean follow-up request, and macOS integration acceptance. Local
project probes remain installed for those follow-ups. No global hooks changed.
