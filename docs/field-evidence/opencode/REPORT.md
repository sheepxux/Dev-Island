# OpenCode 1.18.23 — Windows real event evidence

Captured 2026-10-29 and 2026-10-30 (UTC) on Windows, using the existing OpenCode
provider credential and Big Pickle model. No credentials were read or exported.
The dedicated global plugin imported the capture helper and registered `event`
and `permission.ask`; neither changed hook output or returned permission decisions.
Project settings asked for edit/bash approval and disabled automatic updates.

## Results

| Scenario | Observed result |
| --- | --- |
| Global discovery and normal turn | The plugin under the user's global plugins directory captured session.created, repeated busy, idle and session.idle; hi returned successfully. |
| Resume | Project B's `run --continue` replied resumed with the same session hash d550216e. |
| Native allow | In the mini TUI, Allow once created allow.txt containing hello; permission.replied preceded subsequent busy/idle. |
| Native deny | Esc opened a rejection explanation; submitting it rejected the write. deny.txt was absent. |
| Waiting | A third file request remained pending for over two minutes without automatic timeout. Ctrl+C at the permission dialog had no observed effect; Esc plus rejection feedback ended the request. wait.txt was absent. |
| Interrupt generation | On October 30, Ctrl+C during a streaming long response, followed by a second Ctrl+C, ended that turn. The CLI recorded an aborted session.error and idle; the terminal session then exited. These are actual key presses, not a synthetic error injection. |
| Network failure | A process-only unreachable loopback HTTP(S) proxy produced repeated busy/retry, then session.error with isRetryable=true, idle and session.idle; run exited 1. System network settings and saved credentials were unchanged. |
| Concurrent projects | Project A's pending approval session ff6eb6b5 remained open while project B d550216e completed hi and resume. IDs differed. This proves concurrently open sessions, not simultaneous model generation. |
| Remove plugin | After test sessions closed, only our global plugin was moved to a private backup. A fresh run returned hi, exit 0; the private timeline stayed at 8590 lines. |

## Contract differences

The actual permission-request event is **permission.asked**, not
permission.updated. No permission.updated was observed. Request schema:

```text
id: string
type: permission.asked
properties:
  id: string
  sessionID: string
  permission: string
  patterns: string[]
  metadata:
    filepath: string
    diff: string
  always: string[]
  tool:
    messageID: string
    callID: string
```

permission.replied has properties.sessionID/requestID/reply. It follows the
native decision. The capture was already present when the permission UI was
inspected; polling cannot establish exact UI-frame latency.

Despite registering `permission.ask`, **zero invocations** were captured for
these real file approvals. Therefore its input/output contract remains unknown;
do not invent a shape or implement Allow/Deny against this evidence.

Normal status sequence contains repeated busy before idle, then session.idle.
The induced network failure alternated busy/retry before error/idle. Error
properties contain sessionID and error.name/data; the network data includes
message, isRetryable and metadata.url, all content redacted in the timeline.

## Execution caveats

- `run -i` auto-rejected the requested write in this terminal. It is recorded
  as automatic rejection, not human/native-menu coverage; successful native
  allow/deny used the mini TUI afterward.
- During an initial full-screen TUI attempt, terminal input coincided with an
  update dialog and updated the installed CLI to 1.19.5. That attempt is not
  counted as a successful permission test. The package was restored to 1.18.23
  before subsequent tests and project autoupdate disabled. No model turn was
  run on 1.19.5. The aborted initial session is retained in the evidence.
- On October 29 a single Ctrl+C did not conclusively stop generation; the
  October 30 repeat supplies the interruption observation. No stronger claim
  is made about the earlier turn.

## Privacy and handoff

The export selects lifecycle/permission events, excluding high-volume text
delta events. The original capture helper hid permission.asked because it was
not in its enum list. Export recovered only that reviewed event-name enum by
matching hashed event IDs against local raw records; timestamps and shapes
otherwise remain from capture. Unknown reply strings remain length markers.
All exported string leaves and field names were checked. Raw data stays local.

Remaining: exact permission.ask support, permission.updated compatibility,
timeouts longer than the observed window, session deletion, and Mac integration
acceptance. This evidence does not promote the Preview connector or prove App
mapping, native terminal focus or installation/removal behavior on macOS.
