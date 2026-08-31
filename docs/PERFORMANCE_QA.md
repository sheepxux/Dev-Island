# Dev Island Performance QA

Performance claims require retained raw samples. A screenshot, a single `top`
line, or an unversioned marketing number is not sufficient evidence.

## Hermetic fixture build

Build the dedicated QA bundle on T7 Shield:

```sh
DEV_ISLAND_PERFORMANCE_QA=1 \
DEV_ISLAND_SWIFT_SCRATCH_ROOT='/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/performance/swiftpm' \
BUILD_DIR='/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/performance' \
./scripts/build-app.sh
```

This compiles `DEV_ISLAND_PERFORMANCE_QA`, changes the bundle identifier to
`app.devisland.Island.PerformanceQA`, writes a
`DevIslandPerformanceFixture = true` plist marker, and refuses any Sparkle
production public key. The resulting app never touches the user's SQLite,
Keychain, Hook server, Manus account, notification state, onboarding state, or
update network. Never publish this bundle.

The fixture uses the fixed `app-performance-qa` flavor; packaged production
builds use `app-production`; the DEBUG-only interaction sandbox uses
`app-debug`; and ordinary `swift build` / `swift test` continue to use `.build`.
Without an override these App flavors live below repository `.build`. On a
File Provider-backed checkout, pre-create the explicit T7 scratch root as a
current-user-owned, non-symlink, non-group/other-writable directory and pass it
through `DEV_ISLAND_SWIFT_SCRATCH_ROOT` as above. The build boundary creates
only the final `0700` flavor child and rejects missing multi-level parents,
unsafe permissions, symlinks, repository/source roots, and the bare `.build`
root before SwiftPM runs. This physical SwiftPM scratch separation is required because neither
an ad-hoc `-Xswiftc -D...` flag nor a long-lived DEBUG/release configuration
switch is a sufficiently reliable cache identity for a distributable bundle.
It also avoids blocking forever when macOS has converted an old checkout-local
SwiftPM DerivedSources file into a File Provider `dataless` placeholder. Do not
delete or reuse that stalled graph as part of QA; select a new validated root.
Every bundle build also inspects the final universal executable: production
must contain neither QA readiness/scenario marker, while the fixture must
contain both. PR CI builds the fixture first and production second, then checks
both binaries and both plists with
`scripts/ci/verify-performance-fixture-isolation.sh`.

## Scenarios

- `idle`: compact island, no sessions, no animated timeline.
- `compact-running-20`: compact island with twenty running sessions and one
  visible compositor-driven 3×3 orbit signal.
- `expanded-running-20`: expanded task list with twenty running sessions and a
  row-local one-second duration clock plus compositor-driven opacity loops.
- `expanded-mixed-20`: twenty sessions spanning Waiting, Failed, Done, and
  Running to exercise priority, layout, and static/animated signals.
- `transition-running-20`: twenty Running sessions with a deterministic
  collapsed ↔ expanded edge every 800 ms after a one-second settle. The next
  edge starts only after the 300 ms silhouette morph and delayed live effects
  have settled. QA-only transition markers retain iteration, target state, and
  system uptime for trace alignment. Marker writes run on a dedicated utility
  queue: a deferred Instruments recording may pause its stdout reader while
  compressing, and evidence I/O must never stall the UI thread being measured.

## Animation architecture

The panel container is clock-free. Running and Waiting task durations own a
one-second row-local clock; terminal rows are static, and action countdowns
update only the request header. `ScrollViewReader`, `LazyVStack`, Plan Review,
question options and decision controls therefore do not re-evaluate merely
because a time label changed. Running and Waiting 3×3 marks use nine fixed Core
Animation layers whose opacity keyframes are composited without rebuilding the
task row or list. Hidden panel rows stop both local clocks and their loops, and
Reduce Motion renders the same semantic grid at rest.

Identical semantic marks also share a bounded opacity-keyframe cache. A 20-row
Running panel therefore calculates the 49 phase samples for each of nine dots
once per `(pattern, motion, intensity)` signature instead of repeating the same
441 opacity calculations for every row. The cache is lock-protected and capped
at 16 signatures. Each installation captures wall-clock phase and media time
once, so all nine layers join one synchronized loop without nine duplicate
clock reads.

Layer geometry has a separate `(bounds width, bounds height, requested size)`
signature. State, color, intensity, SwiftUI updates, and repeated layout passes
do not recreate the nine dot frames or shadow paths while the real size is
unchanged. `DotMatrixRenderingTests` fixes both contracts: one cache generation
for concurrent identical requests with a hard entry bound, and no geometry
rebuild until dimensions actually change.

The root island also constructs one immutable `IslandPresentationSnapshot` per
SwiftUI body evaluation. It attention-sorts the current sessions exactly once,
then shares the resulting rows, primary state, primary task and status counts
between the expanded panel and compact bar. Before this snapshot, the same
20-session input could be sorted five times during one hover/mode/status
refresh, including a hidden sort inside `BarState.derive`. Status counts now use
one switch pass instead of four independent collection scans. Three semantic
regressions and the performance invariant gate preserve the single-snapshot
contract.

Panel visibility and panel activity are separate lifecycle phases. The static
hierarchy begins its opacity reveal 40 ms into expansion, but row/header clocks
and continuous point-matrix layers stay paused until 40 ms after
the 300 ms silhouette morph finishes. In the 20-session Running fixture this
moves installation of up to 189 opacity keyframe animations (one header and 20
row matrices) out of the critical geometry transition. Collapse disables the
loops immediately, and one generation token invalidates both delayed callbacks
during rapid open/close/open sequences. Reduce Motion skips the spatial settle
delay and keeps every point loop disabled through its own accessibility gate.

Pending action requests also use one immutable presentation projection for the
whole expanded panel. The projection records the first request and additional
count per visible session, preserves orphan arrival order, and identifies the
single keyboard-primary request in one pass. It is rebuilt only when real panel
input changes; a local countdown tick no longer rebuilds or rescans it. The
panel header and VoiceOver summary consume the root island's existing
single-pass status summary rather than recounting the same tasks. Two semantic
regressions preserve arrival order, orphan handling and keyboard ownership, and
the performance invariant gate rejects a return to per-row queue scans.

The borderless island window uses global/local mouse-move monitors and
silhouette-change callbacks for immediate click-through boundary transitions.
Its repeating timer is only a watchdog. The 25 Hz cadence is now scoped to a
pointer inside the **collapsed** island, where macOS can visibly clobber the
pointing-hand cursor. Both a pointer outside the silhouette and a pointer
resting anywhere in the expanded panel use 1 Hz (at most 60 wakeups/minute),
because expanded controls own their cursors and boundary changes remain
event-driven. This removes 1,440 unnecessary main-thread timer wakes per minute
from the common “panel open while reading” state. The previous idle baseline
was already reduced from 4 Hz. `IslandWindowMouseTrackingPolicyTests` pins all
three branches of this energy/latency contract. This is architectural evidence,
not a substitute for an unlocked Energy Log or Time Profiler run.

## Settings Agent configuration responsiveness (v6.51.0)

Opening **Agent Connections** can inspect several Agent-owned JSON/TOML files,
each bounded at 4 MiB, while Enable/Update/Disable may also perform atomic file
and directory `fsync`. Those operations now cross one testable
`LocalAgentConfigurationExecutor` into a detached worker. The SwiftUI main
actor receives only a low-cardinality installation state, a success Boolean,
and fixed product copy; configuration bytes, paths, parser errors and unrelated
Hook content remain outside the presentation layer. The all-Agent managed-Hook
summary uses the same boundary.

The row starts in a real checking state, so it cannot flash an unverified
Enable or Disable action. Refresh is latest-wins, a mutation is exclusive, and
leaving the row invalidates late UI delivery without interrupting a write that
has already entered the atomic configuration boundary. Every mutation then
re-reads the actual configuration and reports success only when it matches the
requested terminal state. Starting either path also invalidates an older Codex
Hook-trust result, preventing a late probe from restoring stale Connected copy.

`LocalAgentInstallationPresentationTests` pins checking, refresh supersession,
mutation ownership, invalidation and operation copy. Its async regression is
entered from `@MainActor`, asserts that the worker ran with
`Thread.isMainThread == false`, and then confirms control returned to the main
thread. `verify-performance-analysis.sh` also rejects direct installer I/O in
`SettingsView` and fixes the four intended executor call sites.

This is architectural responsiveness evidence. It proves that bounded config
parsing and synchronization are not scheduled on the main thread; it does not
invent a latency percentile, prove animation frame pacing, or replace an
unlocked Instruments/real-large-config interaction run.

The retained v6.51 gate pairs this contract with 677 passing authoritative
tests, 65 process/lifecycle stress rounds, 10 hermetic-listener rounds and a
fresh Universal Production App. Its locked-session eight-sample launch smoke
proves only loader/readiness/service isolation/normal exit; the recorded CPU,
RSS and readiness values are not a Settings responsiveness baseline.

## Settings Agent mutation ownership across panes (v6.57.0)

The earlier row-level installation state prevented duplicate clicks only while
that row existed. Starting **Disconnect All…**, switching to another Settings
pane, and returning could reconstruct Agent Connections with idle row state
while the cross-file removal still ran. A new Enable/Update/Disable could then
enter the Core transaction concurrently, producing avoidable status jumps or a
fixed failure even though the file layer correctly detected conflicts.

`SettingsView` now owns one `LocalAgentConnectionsOperationState` above the
pane switch. Single-Agent changes and **Disconnect All…** acquire the same
operation slot. All row mutations, Codex trust rechecks, live-readiness checks,
and bulk maintenance remain unavailable until the exact operation ID and kind
complete. A completion generation then refreshes every recreated row and the
managed-Hook summary rather than relying on the local state of a departed row.

Bulk removal uses `LocalAgentConfigurationExecutor` instead of a View-local
detached task. Its worker returns only no changes, aggregate disconnected count,
or failure, keeping paths and raw transaction errors out of MainActor delivery.
Four focused state-machine tests pin cross-pane exclusivity, exact completion,
late/wrong-kind rejection and stale-feedback clearing. Static performance and
security gates pin the top-level Binding, four executor call sites, bounded
worker outcome, and reject a detached-task regression inside Disconnect All.

Final-source verification covers 708 tests with zero failures. This proves
operation serialization and delivery ownership, not unlocked page-switch
latency, button animation pacing, VoiceOver behavior, or real large-config
responsiveness; those remain separate hands-on acceptance work.

## Plan Review render isolation (v6.52.0)

At v6.52, the expanded panel still had one one-second `TimelineView` for
durations and action countdowns. Previously, `PlanMarkdownView.body` also
reparsed as many as 65,536
characters into block structure and then reparsed every inline fragment into
`AttributedString` whenever that subtree was redrawn. A pending Plan Review
therefore coupled static document work to an otherwise cheap clock tick.

The block and inline parsers now run through
`PlanMarkdownRenderingExecutor` on a detached worker once for a request
generation. SwiftUI receives an immutable `PlanMarkdownDocument`; its redraw
path performs layout only and contains neither parser call. Request ID plus
operation ID provide latest-wins delivery, and disappearance invalidates late
results. A real test enters from `@MainActor`, observes
`Thread.isMainThread == false` in the worker, and confirms main-thread return.

Plan input now has both a 65,536-character and 262,144-byte limit. At most 512
complete blocks may enter SwiftUI, preventing a pathological document from
creating an unbounded view tree. Loading, empty, or over-complex documents keep
Approve/Reject and their shortcuts disabled; Continue in Claude remains
available, so performance failure cannot become approval of an unseen or
truncated plan. Static QA hosts inject only the same renderer's final document
because they do not advance an asynchronous run loop; Production always leaves
that injection empty.

The deterministic regressions and performance gate prove parser placement,
generation ownership, block/byte bounds, and decision availability. They do
not provide an unlocked large-plan scroll/hitch percentile or VoiceOver result;
those remain real-window acceptance work.

The retained v6.52 gate pairs this contract with 684 passing authoritative
tests, 65 process/lifecycle stress rounds, 10 hermetic-listener rounds and a
fresh six-Mach-O Universal Production App. The frozen private App completed all
eight one-second survival/isolation samples, matched selected/private
executable SHA-256, and exited normally through AppKit with status 0. Because
the display was locked, its CPU/RSS and 1,118.7 ms readiness values are retained
only as harness facts and are invalid as Plan Review smoothness, scroll,
Animation Hitches, energy, first-frame or VoiceOver evidence. The scoped
read-only record is:

`/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/plan-review-render-isolation-v1-20260829/PLAN_REVIEW_RENDER_ISOLATION_EVIDENCE.md`

## Panel clock leaf isolation (v6.53.0)

The former panel-level `TimelineView` enclosed `ScrollViewReader`,
`LazyVStack`, every task row and every action surface. One changing duration or
countdown therefore re-evaluated stable scrolling, hover, Plan Review,
question-option and decision-control structure once per second.

`NotchPanelView` is now clock-free. Running and Waiting tasks own row-local
one-second timelines so their visible duration and matching accessibility label
use the same reference date; Completed and Failed tasks freeze at `updatedAt`
without a timeline. Each pending request owns a header-local timeline, leaving
its form, rendered document, scrolling content and buttons outside the tick.
Both clocks pause until panel effects are live and stop immediately on collapse;
fixed-date injection keeps tests and static captures deterministic.

Five pure policy regressions pin live/terminal scheduling, hour formatting,
terminal freeze, negative-clock clamping, ceil countdown and zero clamping.
The performance gate rejects a `TimelineView` or shared `now` returning to the
panel container. The retained gate adds 689 authoritative tests, 65
process/lifecycle stress rounds, 10 hermetic-listener rounds and a fresh
six-Mach-O Universal Production App. Its private frozen copy completed 8/8
survival/isolation samples and normal AppKit status 0. Since the display was
locked, CPU/RSS and 1,515.2 ms readiness are harness facts only—not evidence of
scroll smoothness, Animation Hitches, hover continuity, energy or VoiceOver.

`/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/panel-clock-leaf-isolation-v1-20260829/PANEL_CLOCK_LEAF_ISOLATION_EVIDENCE.md`

## Launch readiness, CPU and memory samples

```sh
scripts/qa/measure-app-performance.sh \
  '/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/performance/Dev Island.app/Contents/MacOS/IslandApp' \
  idle \
  '/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/idle.csv' \
  10 60 1.0
```

The script refuses a normal production/QA app and treats the CSV, app log, and
summary as one append-never evidence set: if any target already exists, the run
stops rather than mixing samples from different launches. Before launch it
uses `umask 077` and one noclobber `exec` to hold all three `0600`, single-link
files open on dedicated descriptors. The selected parent must be current-user
owned, non-symlink, and not group/other writable. Every later write uses those
descriptors; path and descriptor must continue to share the initially fixed
device/inode token.

The selected QA App is an input, not the launch location. The sampler hashes
its main executable and `Info.plist` from bounded
`RDONLY|NOFOLLOW|NONBLOCK` descriptors, verifies a strict deep signature, and
copies the complete Bundle with `ditto` into the random private `0700` sampler
root. Source hashes must remain stable across the copy and equal the private
copy; both Bundles then pass strict signature checks, while only the private
copy enters the six-Mach-O dependency-closure check, Performance marker check,
metadata parsing, and launch command. The private executable/plist and selected
source are rebound to their original hashes before launch and again after
normal termination. Replacing the selected source during sampling fails the run
and leaves the summary empty even though the isolated process can continue
safely.

It launches that isolated private bundle with a private per-run
`CFFIXED_USER_HOME`, waits for a QA-only readiness marker after the initial island
and status item have completed one main-runloop layout/display turn, warms up,
records one-second CPU/RSS samples, and writes the separate summary and app log.
After the final sample it targets the exact launch PID through
`NSRunningApplication.terminate()`, waits at most five seconds, and requires a
real exit status of zero. A cleanup signal may recover a failed run, but it can
never satisfy the normal-termination gate or appear as a successful summary.

All executable and evidence paths must remain one quoted shell argument. This
includes scripts invoked from variables: the analyzer is called as
`"$QA_ANALYZER"`, so a source checkout or retained evidence root such as
`/Volumes/T7 Shield/...` is not split at the volume-name space. The static
performance gate pins that command form, and the retained v6.43 smoke was run
from a T7 path containing the space.

Neither readiness parsing nor statistics reopen their public evidence path.
Each readiness poll takes a bounded 1-MiB `RDONLY|NOFOLLOW|NONBLOCK` snapshot
that must match the still-open App-log writer token and stable metadata; only
that private snapshot is parsed. A marker must be absent or appear exactly once
with a decimal uptime inside the 5.5-second launch window. FIFO/path replacement,
malformed or duplicate markers, reverse time, and out-of-window values fail
closed without entering a blocking public-path read.

Likewise, the public CSV is never handed directly to the multi-pass analyzer.
After sampling, a second descriptor must match the CSV writer's device/inode
token and stable metadata; one bounded `pread` creates an exact snapshot inside
the private sampler directory. Only that snapshot is analyzed.
CSV, App-log and summary limits are 32 MiB, 1 MiB and 128 KiB respectively;
warmup and sampling are each capped at 86,400 seconds. Deterministic fixtures
cover a spaced path, an existing target, a symlink, two concurrent claimants,
replacement after reservation, App-log FIFO replacement, strict marker parsing,
readiness-window validation, descriptor-backed App-input byte drift, and
nonblocking App-input symlink/FIFO rejection (seven top-level cases).

The summary binds the sample to the bundle ID, version/build, executable
SHA-256, selected-source executable SHA-256, machine model/architecture, macOS
version, screen state, warmup, and sample duration. A valid summary requires
the private and selected hashes to match and records
`isolated_app_snapshot=true`. It also retains `isolated_user_home`,
`normal_termination`, and `app_exit_status`. `launch_ready_ms` is measured from uptime captured directly
before process launch to the readiness marker. It is a repeatable
application-readiness metric, not proof that the display compositor presented a
frame; visual launch still requires an unlocked screen recording or Instruments
evidence.

`summarize-performance-samples.sh` validates the exact CSV schema and strictly
increasing elapsed time before emitting:

- CPU average, nearest-rank p50/p95, and maximum;
- RSS average, nearest-rank p50/p95, and maximum;
- starting/ending RSS and absolute growth; and
- ordinary least-squares RSS slope in KiB per minute over post-warmup samples.

The optional arguments after `SAMPLE_SECONDS` are, in order, maximum average
CPU percentage, maximum RSS slope in KiB/minute, and maximum RSS growth in KiB.
Limits are inclusive and any exceeded limit exits with status 4 while retaining
the raw evidence and summary. The current sustained-idle CPU gate is `1.0`.
Leak slope/growth and launch-readiness release thresholds must be chosen only
after retaining representative unlocked baselines across supported Macs; the
analyzer measures them now but does not invent a product threshold.

The sampler fails closed when screen lock state is locked **or unknown**, because
compositor pause and App Nap can create unrealistically low numbers. macOS
normally omits `CGSSessionScreenIsLocked` while unlocked, so the dedicated
display-session probe accepts that omission only when the same CoreGraphics
session dictionary proves both active-console ownership and a completed login.
The classifier has deterministic fixtures for locked, explicitly unlocked,
normal omitted-key, incomplete-login, and non-console sessions.

The compiled probe runs before launch, after warmup, before every one-second
CPU/RSS sample, and after the final sample. A mid-run locked or indeterminate
state therefore invalidates the append-never evidence instead of allowing an
artificially low partial result. Summaries retain both `screen_state_initial`
and `screen_state_final`. Set `DEV_ISLAND_PERF_ALLOW_LOCKED=1` only for a short
harness integration smoke test; the resulting summary remains marked
`screen_locked=true/unknown` when applicable and is invalid for product or
release claims.

PR CI performs that narrow integration smoke immediately after building the
Performance QA App: zero-second warmup, eight one-second idle samples, private
user root, readiness, exact-PID normal termination, and exit status zero. This
is a real dependency/loader/startup regression gate, but its locked-runner
metrics are deliberately excluded from performance claims and from the
sanitized failed-run diagnostic artifact.

The workflow does not reopen the runner-temporary summary after the sampler
exits. Under `set -euo pipefail`, one quoted command substitution captures the
sampler's bounded success stdout in `performance_summary`; a nonzero producer
status fails the assignment and step. Every survival flag, sample count, and
selected/private SHA-256 assertion consumes only that shell variable. The App's
stdout/stderr are already isolated on the fixed App-log descriptor and its CSV
and summary descriptors are closed at launch, so a QA descendant cannot inject
workflow stdout. A later replacement of the public `.summary.txt` may affect a
discarded runner-temporary debug file but cannot change CI acceptance.

For a long-run unlocked leak sample without prematurely enforcing a limit:

```sh
scripts/qa/measure-app-performance.sh \
  '/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/performance/Dev Island.app/Contents/MacOS/IslandApp' \
  expanded-running-20 \
  '/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/expanded-running-20-long.csv' \
  30 1800
```

After approved baselines exist, append all three reviewed limits to the command
so regression runs fail automatically.

## Instruments

For current-run Time Profiler evidence:

```sh
xcrun xctrace record \
  --template 'Time Profiler' \
  --time-limit 60s \
  --no-prompt \
  --output '/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/expanded-running-20.trace' \
  --env DEV_ISLAND_PERFORMANCE_SCENARIO=expanded-running-20 \
  --launch -- \
  '/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/performance/Dev Island.app/Contents/MacOS/IslandApp'
```

Retain the `.trace`, CSV, summary, app log, exact executable SHA-256, display
state, and reproduction command. The sampler now records the remaining machine
and OS identity in the summary. Sleep/wake and animation smoothness remain
separate gates; RSS slope can identify a long-run growth trend but cannot prove
the absence of every allocation leak without Instruments.

For the real bar ↔ panel path, use the installed `Animation Hitches` template
with `transition-running-20`. A static expanded fixture cannot support a
smoothness claim because it never exercises the geometry morph. Run Power
Profiler and Leaks separately from hitch capture so their recording overhead
does not contaminate one another.

## Welcome connection operation ownership (v6.54.0)

Welcome previously moved each Hook scan/install off the main actor, but owned
those detached tasks directly. That removed synchronous file parsing while
leaving no generation boundary between a scan and a later install, no
view-departure invalidation, and no final disk read-back before presenting a
successful connection.

The surface now routes its read and mutation paths through the same tested
`LocalAgentConfigurationExecutor` used by Settings. A latest-wins refresh ID
rejects older scans. One mutation owns the entire connection surface, disables
competing actions, and represents every bulk target as working while a single
background batch runs. Closing Welcome invalidates delivery but deliberately
does not cancel a managed-config transaction that may already be inside its
atomic write boundary.

After the batch, the worker performs one complete diagnostic read-back,
including the existing bounded Codex trust resolution. A target succeeds only
when its write did not fail and the resulting state is Connected or the
documented Configured-pending-trust state. Missing, stale, disconnected or
write-failed targets keep actual disk state and receive fixed error copy. The
main actor therefore receives one coherent final snapshot instead of a series
of per-row detached completions.

Four focused operation/classification regressions and the static performance
gate pin refresh supersession, mutation exclusivity, view invalidation, final
read-back, two shared-executor call sites, and zero direct installer/detached
work in `OnboardingView`. This is scheduling and state-integrity evidence; a
locked display cannot provide real click latency, frame pacing, visual polish,
VoiceOver or large-config interaction acceptance.

Final-source verification completed with 693 tests and zero failures. The
fresh keyless Production App contains six Universal Mach-O files, passes strict
deep ad-hoc signing and dependency closure, and completes the 8/8 hermetic
launch with isolated services and normal status 0. The locked launch metrics
remain non-performance harness facts. Read-only evidence:

`/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/performance/onboarding-operation-ownership-v1-20260829/WELCOME_CONNECTION_OPERATION_EVIDENCE.md`

## Support diagnostics responsiveness (v6.56.0)

The Support save path previously returned from `NSSavePanel` directly into a
MainActor closure and synchronously performed descriptor open/write, `fsync`,
close, and atomic rename there. A slow local disk or mounted network volume
could therefore freeze Settings after the user pressed Save. Report generation
also owned an ad-hoc detached task, while view departure and delayed feedback
had no shared delivery identity.

Hook inspection and the complete confirmed file transaction now cross the
testable `SupportDiagnosticsIOExecutor`. The AppKit panel and pasteboard stay on
the main actor; the blocking worker returns only a bounded report or
`SupportDiagnosticsExportOutcome`. A focused async regression enters from
`@MainActor`, records `Thread.isMainThread == false` inside the worker, and then
returns normally.

One operation ID owns Copy or Save from report preparation through panel
cancel/confirmation and write completion. Leaving Support invalidates late UI
delivery without interrupting an atomic descriptor transaction already in
progress. Separate feedback IDs make the two- and four-second confirmations
latest-wins even when two successive localized messages are identical. Static
performance and security gates reject any direct
`SupportDiagnosticsExporter.write` call from `SettingsView`.

Four new focused regressions plus the existing seven report/export tests pin
non-main execution, operation invalidation, identical-message timer ordering,
bounded outcome mapping, private permissions, atomic replacement, and symlink
rejection. This is an architectural responsiveness result; a locked display
cannot prove real slow-volume latency, Save Panel visual polish, frame pacing,
or VoiceOver behavior.

## Decision-response Instruments segmentation (v6.74.0)

Decision recordings must use the `decision-approval`, `decision-question`, or
`decision-plan-review` Performance QA scenario and export Animation Hitches,
SwiftUI update events, Potential Hangs, and the trace TOC. The App log must
contain exactly one queued and one resolved marker for the action. New markers
carry both monotonic `uptime=` and epoch `wallUnix=`; `wallUnix` is the primary
trace alignment, while uptime proves the action delta. Legacy logs may use the
documented bounded fallback but must retain their larger uncertainty.

Run `scripts/qa/summarize-animation-hitches.rb` over the four exports and App
log. The JSON separates startup, the resolved interaction window, steady state,
and the recording tail. App-attributed frame lifetimes, render/GPU-only frame
lifetimes, App update events, root update rows, and potential hangs remain
distinct metrics. Rows outside the trace duration are counted and excluded.
Do not use whole-recording maxima to label the response transition when the
event occurred in another segment.

The analyzer accepts only bounded ordinary inputs and fails closed on links,
DTD/entity input, missing table references, malformed/negative timing,
duplicate markers, and unsafe output replacement. Its deterministic self-test
and `verify-performance-analysis.sh` must pass before a summary is retained.

The current permission-deny diagnosis and fix are recorded at:

`/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/decision-motion-v1-20260831/DECISION_MOTION_AUDIT.md`

The accepted fixed-source trace reports a resolved App-update maximum of
21.238 ms, zero App updates over 33/50/100 ms, and zero resolved potential
hangs. The pre-fix diagnostic baseline was 132.257 ms with a 54.802 ms
Potential Interaction Delay. Fixed-source Question Submit and Plan Review
remain pending because the Mac locked before they could be completed; the
incomplete trace must not be promoted to acceptance evidence.

## Trusted single-instance arbitration acceptance (v6.84.0)

Unit tests and static gates can establish bounded candidate selection, signing
policy, revalidation order, fail-open behavior, and pre-UI wiring. They do not
prove that two real AppKit processes arbitrate without a duplicate Island,
status item, listener, backend owner, or visible focus error. Real-process
acceptance must use a fresh Universal Production App built after the source is
stable. A build that overlaps later source edits is rejected even if it
launches successfully; the retained report must bind the source manifest,
executable SHA-256, signing identity class, display state, and exact commands.

For ad-hoc dynamic code, CDHash is the identity of the Mach-O architecture
slice selected by the running process, not a single architecture-neutral
identity for the entire Universal bundle. The two trusted copies in a round
must therefore use the same recorded runtime architecture. On Apple silicon,
retain both the process architecture and translated/native state for every
PID. A native arm64 process and a forced-Rosetta x86_64 process can resolve to
different CDHashes and must not be expected to trust one another; cross-slice
coexistence is a negative identity case, while arm64 and x86_64 trusted-copy
acceptance must be run separately with two same-slice processes. Equal bundle
or executable SHA-256 values alone do not override the dynamic CDHash result.

The local ad-hoc bridge gate uses two byte-identical copies of that artifact.
Before the first launch, verify that both executables have the same SHA-256,
both signatures are explicitly ad-hoc, and both expose the same nonempty
CDHash. Start one ordinary owner from a clean QA state and wait for its process,
listener, and backend ownership to stabilize; when the display is unlocked,
also confirm its Island and status item. Then launch the second copy in at
least 20 consecutive rounds. Every round must retain both PIDs, monotonic
launch-to-disappearance duration, an exit status when the harness owns a
waitable child process, owner/process snapshots, listener/backend ownership,
and any unexpected UI or LaunchHealth side effect. A direct-child run must exit
normally with status 0 before constructing product UI or services. A real
LaunchServices run may instead prove that its returned PID disappeared before
product ownership, but because the harness cannot `wait()` that process it must
record the exact exit status as not observable and must not infer status 0. In
either mode, exactly one original owner must remain and stay responsive. Report
the complete timing distribution; do not replace it with a selected best round
or infer an unreviewed latency threshold.

`CFFIXED_USER_HOME` redirects home-backed files and preferences but does not
create or select a separate login Keychain. An ordinary Production owner run
that uses this variable is therefore not hermetic and must not be described as
isolated from the user's Keychain. Process-level acceptance must record a
locked display and independently established Keychain-unavailable context, or
run in a disposable login account/VM with its own Keychain. If Keychain
unavailability is not proven without reading user secrets, record it as
unknown and keep the run out of hermetic/isolation claims.

For every one of the 20 rounds, retain an exact-PID socket snapshot. After the
newcomer exits, the complete App-owned INET socket set must contain only the
original owner's `127.0.0.1:7824` TCP listener; any additional loopback or
remote socket invalidates the state-isolation result. The root SwiftUI
`Settings` scene being inert is a required code-level precondition, not proof
that a yielding process stayed side-effect-free. Before and after each round,
the duplicate's private home must show no SQLite database or sidecars, no local
Hook authorization file, no LaunchHealth preference keys/artifact, and no
other product state. Reusing a private home is acceptable only when its empty
pre- and post-round snapshots are retained and paired with the pre-UI static
gate; a single final empty-directory snapshot is insufficient.

The rejection gate uses a minimal AppKit impostor with the same Bundle ID but a
different explicitly ad-hoc CDHash. Launch the impostor first, record its
activation and termination state, and then launch the real current-source App.
The real App must continue to readiness and own its expected product resources;
the impostor must neither be activated nor terminated by Dev Island. This
scenario is expected to leave two unrelated processes alive and proves only
that a Bundle-ID collision is not trusted. Its helper source, both executable
hashes, signing flags/CDHashes, PIDs, activation observations, and cleanup must
be retained with the report.

Same-Team cross-version arbitration remains unaccepted until two distinct
Developer ID artifacts with the exact code identifier, an Apple-generic
anchor, and the same certificate OU/Team ID are available for a real-process
run. Ad-hoc copies, equal resources, or a shared Bundle ID cannot substitute
for that evidence. The Developer ID run must bind both artifact hashes and
prove the older trusted process remains the only owner when the newer version
launches.

Every run must record screen-lock state. A `locked` or `unknown` display may
support only process-level facts such as signature resolution, PID lifetime,
exit status, and listener/backend counts. It cannot establish visible winner
activation, focus or window routing, launch smoothness, animation pacing,
interaction latency, energy, first frame, or VoiceOver behavior; any reported
timing from such a run is a harness fact rather than product-performance
evidence. A complete interaction acceptance therefore requires a separate
unlocked current-source run, and locked/incomplete samples must be labelled
accordingly instead of being promoted into the v6.84 result.

### Authoritative corrected-artifact result

`single-instance-identity-v2-20260831` is rejected and non-authoritative. Its
root Settings Scene could construct TaskStore-backed content before the gate,
so its static/binary observations and any partial live samples remain diagnostic
only and are excluded from accepted timing statistics.

The corrected `single-instance-identity-v3-20260831` artifact passed the
authoritative `live-identity-matrix-v6` process-level matrix on 2026-08-31. The
source executable SHA-256 was
`0605763b23990ffe2094435fac895bbf104151e8661823c96a9ca409145ef1f3` and the
running arm64 ad-hoc CDHash was
`70b870d790f6ccd809df3ce54144982a57177b3e`. All 20/20 byte-identical duplicate
LaunchServices PIDs disappeared. The complete distribution was 231 ms minimum,
235.5 ms median, 302 ms p95 and 1,155 ms maximum; rejected v1–v5 harness runs
were not merged into those statistics.

Every accepted round retained one App owner and that same PID as the sole
`127.0.0.1:7824` listener owner. Exact-PID socket checks observed no other INET
socket, and the duplicate private user root was empty before and after every
round. In the different-CDHash impostor case, activation count remained
`0 → 0`; the impostor was neither activated nor terminated, while the real App
survived as the unique listener owner. Exact cleanup left no same-Bundle process
or port-7824 listener. The checksum-bound evidence is retained at:

`/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/qa/single-instance-identity-v3-20260831/live-identity-matrix-v6/`

This is authoritative only for locked, arm64, same-slice ad-hoc process
arbitration, listener/socket ownership, duplicate-home state isolation and
different-CDHash rejection. The ordinary owner was explicitly classified
`not-hermetic-login-keychain-not-isolated`; the harness did not read Keychain
content, but that is not proof that ordinary TaskStore bootstrap was isolated
from the login Keychain.

Same-Team cross-version behavior still requires two real Developer ID artifacts.
Native arm64 and Rosetta x86_64 use different slice CDHashes and remain a
fail-open cross-slice case, not trusted-copy evidence. Because the display was
locked from start to finish, visible activation, focus/window routing, motion,
first frame and VoiceOver remain unaccepted. LaunchServices exposed PID
disappearance but no waitable child status, so the 20 rounds do not establish a
real exit code or status 0; the separate hermetic smoke's status 0 cannot be
substituted for that missing LaunchServices fact.
