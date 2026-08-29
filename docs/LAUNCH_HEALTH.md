# Launch Health and Recovery Boundary

Dev Island uses a local readiness marker to detect repeated startup loops
without claiming that macOS reported a crash. It never reads `DiagnosticReports`,
installs a crash SDK, uploads telemetry, or changes Agent/Hook configuration.
Confirmed historical failure clusters and their code/artifact protections are
documented in `docs/LAUNCH_CRASH_ANALYSIS.md`.

## Ready milestone

`AppDelegate` arms the marker before constructing the first window. It records
ready only after all of the following are true:

1. the island window has been created and remains visible;
2. the conventional menu-bar controller exists;
3. the first SwiftUI/AppKit layout can be flushed on the main actor; and
4. the process remains alive through a two-second stability window.

The local `TaskStore` is constructed by the island view before this point, so
its SQLite, Keychain, and loopback-listener bootstrap has been scheduled. Those
services already fail into explicit unavailable/degraded states and are not a
reason to suppress the core island. A normal AppKit Quit closes the marker as
well, preventing an intentional quick Quit from creating a false startup-loop
warning.

## State machine

| Previous marker | Reported state | Persisted count |
| --- | --- | --- |
| No record | First launch | `0` |
| Ready | Ready | reset to `0` |
| Started, not ready | Startup interrupted | incremented, capped at `3` |
| Legacy clean exit | Ready | `0` |
| Legacy missing/false clean exit | Legacy unknown | `0`; no warning |

`startup interrupted` means only that the ready milestone was not reached. A
quick Force Quit, power loss, OS restart, and a crash remain indistinguishable.
The Settings notice therefore uses this exact language and stays out of the
island's attention queue.

## Recovery policy

- One interrupted startup shows a quiet, local Support notice.
- Two or more consecutive interruptions add a suggestion to keep the current
  launch open through the readiness window and, if the issue repeats, copy the
  privacy-safe diagnostic summary.
- The count can never exceed three.
- There is no automatic safe mode. Dev Island never disables the local Agent
  listener, edits Hooks, clears task history, removes credentials, or changes
  launch-at-login state in response to this marker.
- A future safe mode requires a separately reviewed allowlist of optional
  startup services and real crash-loop evidence. The local listener and user
  recovery surfaces must remain available.

## Privacy and migration

Schema v2 persists exactly four bounded `UserDefaults` values:

- `devIsland.launchHealth.schemaVersion`
- `devIsland.launchHealth.didStart`
- `devIsland.launchHealth.startupReady`
- `devIsland.launchHealth.consecutiveStartupInterruptions`

There are no timestamps, paths, task/session identifiers, prompts, stack traces,
or crash artifacts. The v1 `devIsland.launchHealth.cleanExit` value is read once
for migration and removed. A false or missing v1 value is deliberately mapped
to `legacyUnknown`, because it cannot establish that startup failed.

The hermetic `DEV_ISLAND_PERFORMANCE_QA` build cannot read or write any of this
state. Unit tests cover migration, idempotence, count capping, recovery reset,
and the allowlisted persistent key set.
