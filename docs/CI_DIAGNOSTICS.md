# CI Diagnostics

Dev Island's PR job emits a sanitized diagnostic summary on every run and
uploads it as an artifact only when the job fails.

## Why this exists

GitHub's raw job log is useful for deep investigation, but it is slow to scan
and is not a stable machine-readable contract. The diagnostic bundle answers
the first operational questions without copying the full log:

- which release gate failed first;
- which later gates were skipped;
- the exact local reproduction command;
- aggregate XCTest counts and failed test names; and
- which security sub-gates completed before failure.

## Bundle contents

`dev-island-ci-diagnostics-RUN_ID-RUN_ATTEMPT` contains exactly:

- `summary.json` — schema v2 run, runner, gate, input-source, test and privacy data;
- `README.md` — a short human-readable table and first-failure command.

Both files are created with mode `0600` inside a new `0700` directory. The
workflow creates a private randomized parent under `RUNNER_TEMP`; the generator
refuses an existing output, malformed GitHub context, unknown/reordered gates,
or an unsafe output parent.

Security and test logs are optional evidence, never a prerequisite for emitting
the bundle. Each supplied log is opened once with `NOFOLLOW` and `NONBLOCK`, then
validated through that descriptor as a current-user-owned regular file with one
hard link and no group/other write bit. Security input is capped at 2 MiB and test
input at 16 MiB. The generator uses an exact descriptor `pread` and compares the
device, inode, size, modification time and change time before and after reading.

A missing, empty, symbolic-link, hard-linked, permission-unsafe, oversized, or
concurrently changed input therefore does not make the diagnostic step disappear.
Its section is emitted with `available: false` and a bounded `sourceStatus` such
as `missing`, `unsafe-file`, `oversized`, or `changed`; raw bytes are not reopened
by pathname or copied into the bundle.

The bundle deliberately excludes:

- raw security and test logs;
- environment variables and workflow contexts;
- secrets, tokens and credentials;
- build products and source archives; and
- Dev Island user/application data.

Only fixed-format PASS gate names, aggregate test totals, sanitized failed test
names and a count of security error markers are extracted. Assertion values and
arbitrary error text are never copied.

## Workflow behavior

The security and test steps use `tee` only to a runner-temporary file and retain
`errexit` and `pipefail`, so logging or a later command cannot turn a failing
full suite green. PR CI and tag Release call only
`scripts/ci/run-authoritative-tests.sh`, whose dedicated
`.build/tests-authoritative` SwiftPM graph is separate from developer builds,
dependency resolution, Debug/Release App builds and Performance QA. After the
authoritative full suite, the same built test binary repeats the fast-exit
local-version probe boundary 20 times (240 real child processes), tmux
background-descendant cleanup 20 times, Codex Hook trust 5 times and sleep/wake
lifecycle ordering 20 times. The same graph's already-built diagnostic CLI also
runs the memory-only, zero-Agent-route listener check 10 times; every run must
emit exactly five allowlisted stdout lines and zero stderr. Each runner appends
only one low-cardinality PASS line on success; on failure it appends the failed case without a second
aggregate XCTest count, so diagnostics continue to report the full-suite total.
The complete wrapper holds a non-waiting BSD descriptor lock on the persistent,
zero-byte `0600` `.build/tests-authoritative.lock`. A second invocation in the
same checkout exits before Swift with one controlled error instead of waiting on
or mutating the shared graph. The fixture pauses the first fake full-suite call,
proves the contended wrapper executes no Swift command, then releases the first
run and still requires the exact 66-command distribution.

The ordinary Swift test graph is also hermetic with respect to the macOS login
Keychain. Commercial-license and Manus API-key tests inject process-memory
storage backends; changing only a service/account name is not isolation because
`SecItemAdd` can still invoke login authorization. Tests verify the shipping
adapters' device-only, non-synchronizing query policy without executing
`SecItemAdd`, `SecItemUpdate`, `SecItemCopyMatching`, or `SecItemDelete`. The
Security gate rejects those calls anywhere in the ordinary Swift test sources,
as well as direct use of the production API-key store. A real Keychain exercise
is a separate explicit acceptance gate for a disposable macOS account or VM,
not part of PR CI or a maintainer's normal login session.

The same ordinary graph includes a pre-provider commercial-activation sandbox.
It uses a random numeric `127.0.0.1` port and a test-only Hummingbird server to
send a real HTTP activation request through the production provider-neutral
actor, verifier and verify-before-save path. Every key, code and document is
synthetic and the document backend is process-memory only. Endpoint attack
fixtures reject HTTPS, `localhost`, external addresses, userinfo, alternate
paths, query and fragment; an unsigned response must leave storage empty. This
proves only client wiring. It is not a provider/TLS/checkout/payment/policy,
production-key, real-Keychain, refund/revocation, device or recovery gate.

The v6.76 matrix additionally uses real loopback responses for 400/401/404,
429, 500/503, 302, an unknown status and a 32 KiB+1 body. Rejection bodies are
never surfaced or stored, the redirect target receives zero requests, and all
unknown/redirect/oversize outcomes fail as transport unavailable with empty
storage. Because this fixture intentionally buffers bounded synthetic local
data, it remains actor-wiring evidence rather than transport evidence.

The same ordinary graph separately exercises the disabled shipping HTTPS transport
with an in-process URLProtocol boundary. It fixes exact public-DNS
HTTPS endpoint syntax, body-only POST headers, ephemeral no-proxy/no-cookie/
no-cache/no-credential policy, redirect refusal, final URL/status/media-type
checks, low-cardinality errors, caller cancellation and both declared and
unknown-length 32 KiB streaming bounds. These tests perform no DNS/TLS/provider
request and do not enable commercial mode; real provider acceptance remains a
release gate.

The v6.82 tightening also keeps endpoint construction outside the public API:
the transport exposes neither a public initializer nor public factory, and the
Security gate rejects any shipping `IslandCore`, App or AppLib construction.
Provider enablement therefore requires a reviewed source change that adds one
no-URL factory with a fixed endpoint. The cancellation fixture additionally
waits for URLProtocol `stopLoading`, proving caller cancellation reached the
underlying URLSession request rather than only changing the wrapper outcome.

The v6.84 launch gate treats a shared Bundle ID only as a bounded candidate
filter. Security.framework must validate each dynamic PID and recover an exact
code identifier; non-ad-hoc Team identity must also satisfy an Apple-generic
anchor + certificate-OU requirement. Same-Team releases can match across
versions, while only explicitly ad-hoc QA copies may use the same nonempty
runtime Mach-O slice CDHash. A Universal App's native arm64 and Rosetta x86_64
slices have different CDHashes and must not trust one another. Team/hash mixing,
different identities, missing signing data, more than 32 candidates and every
resolution failure stay fail-open. The lowest older trusted PID is re-resolved
immediately before activation, so process exit, PID reuse or identity drift
cannot make the real App yield.

Callback-local ordering is not sufficient evidence for pre-service arbitration.
The SwiftUI root Settings Scene must remain inert before the gate and must not
construct a TaskStore-backed SettingsView while the root App or Scene graph is
being evaluated. Only after arbitration chooses the current process as owner may
the real Settings content, TaskStore, storage, listener, notifications or product
windows be constructed. The `single-instance-identity-v2-20260831` artifact is
rejected for this pre-gate Scene risk; its signature, dependency, disassembly
and live-process observations are diagnostic inputs only, not v6.84 acceptance
evidence. The corrected `single-instance-identity-v3-20260831` artifact is the
only authoritative v6.84 artifact: its inert root Scene, 23 focused tests and
780-test source graph were followed by a 20/20 native-arm64 ad-hoc live matrix.
Every duplicate PID disappeared while one App owner and one
`127.0.0.1:7824` listener remained; min / median / p95 / max arbitration time
was 231 / 235.5 / 302 / 1155 ms. The session stayed locked and LaunchServices
did not expose the duplicate's true exit status, so this is process/signature
evidence—not visible activation, focus, VoiceOver, Rosetta, simultaneous cold
launch, same-Team cross-version, Developer ID or Release acceptance.

The exact dual-opt-in Production hermetic launch bypasses this gate and selects
an inert TaskStore so CI cannot activate user state. This must not be conflated
with an ordinary listener-owning live owner: `CFFIXED_USER_HOME` does not isolate
the login Keychain, and normal TaskStore bootstrap may read the shipping Manus
credential and start network work. Such a run is ordinary-live, not hermetic,
and cannot support a no-Keychain or no-network claim without a separate boundary.

The v6.85 Manus transaction matrix stays hermetic. Live Hummingbird loopback
tests sign official-shape payloads with synthetic RSA keys and bind replay state
to the exact callback URL plus Security.framework's canonical public-key bytes.
They prove equivalent PKCS#1/SPKI encodings preserve a live window, a URL or real
key change resets it, keys below 2,048 bits fail closed, invalid candidates do
not partially commit, and a request suspended after old-generation authentication
returns 401 without delivery or consuming new-generation replay capacity.

Separate actor fixtures use isolated preferences and process-memory Keychain
backends to prove every accepted webhook ID is persisted, overlapping IDs are
not overwritten, stale IDs block replacement, and stop/wake/heartbeat share
deletion ownership. Stop first makes every attached launch process unreachable,
then gives each cancellation-unaware registration only a bounded completion
grace. If the provider outcome is still unknown, stop fails closed while the
credential, retained launch owner and durable ambiguity marker remain available
for a late accepted ID to be persisted and compensatingly deleted. The
credential-releasing stop also snapshots entry-time deletion operations and
their attempt sequence before its first suspension, joins those results, drains
late deletions, then attempts every persisted sibling ID not actually attempted
in this flight. A failed joined ID cannot suppress a sibling, and an unresolved
entry-time delete cannot be skipped before credential release. Successful
credential release requires all registration/deletion cleanup operations, the
webhook ledger and every ambiguity marker to be resolved. Even if a concurrent
failure path loses its specific error, stop must fail closed whenever the
authoritative ledger is nonempty. HTTP 2xx with `ok:false`,
a missing/invalid confirmation, or a transport failure cannot clear the local ID.
The process is stopped first; cleanup failure retains the ID, the API credential
and the tunnel cleanup owner, surfaces a fixed cleanup-pending state, and lets a
later Disconnect retry before Keychain release. The same fixtures require a new
Connect to join an in-flight removal and use the old credential/manager to finish
old cleanup before any candidate Keychain save; a failure leaves the old value
unchanged. Once old cleanup succeeds, the previous services and Manus snapshot
are detached before candidate persistence. A candidate save failure reads the
Keychain source of truth, remains disconnected, starts neither candidate nor
retired services, and leaves later Configure/Disconnect recovery available.
A cleanup-only manager also recovers multiple persisted IDs in polling-only
mode without starting a listener, process or registration. These tests contact
neither Manus nor Cloudflare and do not touch the login Keychain.
They are transaction evidence only: `ManusRealtimeTrust.liveV2AcceptanceComplete`
remains false, no real-account accepted artifact exists, and CI must not label
polling-only fallback as verified public realtime or commercial Manus acceptance.

The v6.85 normal-Quit matrix treats shutdown as an awaited, memoized TaskStore
transaction rather than fire-and-forget work. Its synchronous prefix marks the
store terminal, advances service generations, neutrally resumes action-request
continuations, detaches ingress, and removes power observers before suspension.
The retained operation joins an existing Disconnect, sleep suspension, poller,
tunnel, local-listener start/retry hop and listener stop, then the retained bootstrap;
guards after every bootstrap/storage/provider suspension prevent late service
resurrection. Concurrent callers share the exact same low-cardinality
`completed` / `cleanupPending` result, and cancelling a caller cannot cancel the
owned operation. A registered Disconnect whose cleanup body has not started is
still superseded and joined without a post-Quit Keychain delete. A queued local
retry is joined before the concrete listener stops, so it cannot restart the
server afterward. A remote cleanup failure leaves the device-only credential and
authoritative webhook ledger intact while the remaining local resources stop.

Joinable-stop regressions use cancellation-unaware connectors and real random
loopback ports. PollingFallback retains tokenized current and retiring poll
operations; start retires rather than forgets the previous handle, and stop
snapshots, cancels and awaits all of them before suppressing every late snapshot.
LocalHookServer applies the same current/retiring ownership to serve and readiness
operations across start, restart and automatic retry; stop awaits every retired
and current operation, not only the newest generation. WebhookServer also joins
its current serve task. The same port can be rebound immediately after return,
and no superseded operation can survive the termination barrier or reclaim it.

The AppKit-independent termination coordinator has a separate deterministic
matrix. A normal owner chooses `terminateLater`; cleanup and an independent
two-second hard timeout race one private token and can reply exactly once in
either order. Repeated owner requests do not start another cleanup. Yielded
duplicates, Performance QA and hermetic launch smoke choose `terminateNow` and
schedule no cleanup, timeout or reply, so their termination path never evaluates
`TaskStore.shared`. Cleanup failure or timeout permits exit but does not erase a
credential or webhook ledger; `applicationWillTerminate` does not launch a
second TaskStore shutdown. These are source/fixture lifecycle guarantees, not a
claim that a locked-screen run visually or interactively exercised normal Quit.

The final v6.85 evidence remains a historical snapshot for that exact source
tree: 118/118 checks across the eight Quit/Manus/listener/poller/
AppTermination suites, 28/28 additional ManusAPIClient and connection-
presentation checks, a warning-free IslandApp build, and an 822/822 full suite.
Its fresh T7 Production App, eight-sample hermetic launch, App-tree manifests and
SHA-256 seal also apply only to that snapshot. The later Tunnel and Local Hook
strict-join changes supersede the 822-test result, the Universal artifact and its
build hashes for the current working tree.

The replacement strict-join evidence is now authoritative for the current tree.
The complete wrapper passed 836/836 XCTest cases followed by 20 local-version
probe rounds (240 child processes), 10 hermetic-listener rounds, 20 tmux cleanup
rounds, 5 Codex Hook trust rounds and 20 sleep/wake rounds. Security, Legal/Data
Flow, Performance Analysis, Localization, Release Foundation, Repository Script
Syntax and repository-wide `git diff --check` also passed. A fresh T7 SwiftPM
scratch produced a warning-free Universal Production App whose six Mach-O files
are exactly arm64+x86_64. Dependency closure, the Production marker, bilingual
legal/localization and reviewed brand resources, 34 license notices, keyless
Sparkle, absence of `get-task-allow` across the complete Mach-O closure and
strict deep ad-hoc verification all passed. The main executable SHA-256 is
`1f94620c17c9387c09711bc9c4681a1971094e4c48daf671a195da81a263c609`.
Its eight-sample `production-launch-smoke` used the same selected/private hash,
isolated product services, App state and user home, and observed normal AppKit
status-0 termination. The screen stayed locked throughout, so the roughly
1.550-second readiness sample and CPU/RSS observations are launch-isolation
diagnostics only, not visual, focus, VoiceOver, animation-smoothness, energy or
real-world performance acceptance. Evidence is rooted at
`/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/v6.85-strict-join-20260831/`.

That follow-up closes the three local ownership gaps previously recorded here.
Tunnel heartbeat work now has tokenized current/retiring ownership and is
strictly joined before lifecycle callbacks are inspected. Those callbacks are
themselves retained operations: a TaskLocal token lets callback-owned `stop()`
exclude only its own edge, while an external `stop()` joins the callback before
returning either success or its cleanup error. A successor cannot promote a new
transport until the retiring heartbeat and every non-self callback have drained.
The retained launch operation also owns its local cloudflared process before
`process.start()` suspends, so stop can make a registration-blocked process
unreachable immediately. It waits only for the configured bounded launch grace;
on timeout it returns a cleanup failure while retaining the launch for late-
result cleanup.

Registration ambiguity is persisted before the provider request crosses the
network. A 409 Conflict and a 429/rate-limit failure are conservatively classified
as outcome unknown rather than definitive rejection; their marker survives a
restart, blocks overlapping registration and credential release, and is cleared
only when the outcome can be resolved. If an obsolete request later returns an
accepted ID, that ID is persisted before its compensating provider delete.

Local Hook event delivery now uses tokenized current/retiring drain ownership.
Stop rejects new work, empties every queue, resolves queued action barriers as
`false`, and joins cancellation-unaware delivery. TaskLocal drain identity
excludes only the callback that initiated its own stop, avoiding a callback ↔
listener self-wait. The concrete Hummingbird path requests graceful shutdown so
that in-flight action request can still return `{}` and release the loopback port.
The delivery and server generation remain retained; a later external stop joins
both before returning. The production TaskStore App-Quit listener cleanup runs
outside the delivery callback context and therefore takes this external strict-
join path.

The initial strict-join regression evidence was deliberately scoped.
`TunnelManagerTests` passed 32/32, then
the same suite passed ten consecutive `--skip-build` runs (10/10 runs, 32/32 in
each). `TaskStoreManusLifecycleTests` passed 24/24. The Local Hook scoped suites
passed 69 tests with 0 failures, and the five ownership/self-stop race tests
passed 20 consecutive repetitions. Tunnel- and Local-Hook-scoped
`git diff --check` runs both passed. Those focused checks are now supplemented by
the replacement 836-test authoritative wrapper and fresh Universal artifact
described above; they remain useful as repeated race-focused evidence rather
than being mistaken for the aggregate alone.

This code-level closure does not permit an `ACCEPTED` Manus receipt or a public-
realtime commercial claim. `ManusRealtimeTrust.liveV2AcceptanceComplete` remains
false. The official authenticated `GET /v2/webhook.list` recovery inventory is
now implemented: only an active row with the exact callback digest, inside the
persisted `startedAt ± 300s` window and owned by one unambiguous local marker is
bound, and the discovered ID is durably read back before delete. Empty or failed
inventory reads, same-digest marker ambiguity, inactive/out-of-window rows and
corrupt state retain the marker and fail closed. Live-v2 still cannot be accepted
until a real account proves create → signed delivery → list/delete together with
read-after-create/read-after-delete consistency; implementing the inventory API
is recovery capability, not evidence that the provider behavior was accepted.

Race soak subsequently found a shared-waiter terminal edge that a single full
suite did not expose. `start()` and credential-releasing `stop()` can await the
same account inventory task; if the start waiter binds a recovered ID and creates
its delete operation first, stop's intentionally stale unbound snapshot declines
to attribute it again. Stop now dynamically joins every retained deletion token
after reconciliation and before server teardown / terminal credential release.
The final drain does not filter by stale attempted webhook IDs and does not
enumerate the known-ID ledger again, so it joins replacement ownership without
retrying a provider failure inside the same stop. One deterministic interlock
proves the exact list-share, start-bind, two-delete-waiter order while the client
records one provider delete. A second seeds an already-known ID, lets stop delete
it once, then makes the stale list waiter publish a new operation for the same ID;
the waiter tokens are exactly `token1, token2, token2`, with two provider calls
rather than a third retry. The focused Tunnel suite passes 49/49 and each race
passes 100/100 independent Swift-test processes. The Security gate fixes the
reconciliation → token drain → server teardown order and rejects both stale-ID
filtering and ledger retry in that final interval. The post-fix authoritative
wrapper passes 885 tests with zero failures, followed by 20 local-version rounds
(240 child processes), 10 hermetic-listener rounds, 20 tmux cleanup rounds, five
Codex Hook trust rounds and 20 sleep/wake rounds.

The v6.77 operation-ownership cases use a test-only cancellation-insensitive
mode: a detached URLSession request remains bounded by two-second request and
resource timeouts and returns its signed response after the activation task is
cancelled or superseded. Request/response counters—not a guessed client sleep—
anchor the sequence. Explicit Cancel leaves storage empty after one returned
response; two returned responses produce one superseded operation and one
latest committed license. This adversarial mode is forbidden from shipping
source and is not a provider cancellation/retry design.

The v6.78 pre-cancelled ownership cases start one valid pending activation,
cancel the second caller before it enters `activate`, and require the second
outcome to be `cancelled` without another transport request. Both the controlled
transport and the real loopback recorder prove the original operation remains
the sole owner and can still activate. This protects one-time codes without
claiming a provider cancellation protocol.

App compilation has a separate v6.49 boundary. CI/tag keep the repository-local
`.build/app-production`, `.build/app-debug`, and `.build/app-performance-qa`
flavors. Maintainer QA may set `DEV_ISLAND_SWIFT_SCRATCH_ROOT` to a prepared T7
directory when a File Provider-backed checkout contains `dataless` SwiftPM
artifacts. `prepare-scratch` validates ownership, type, permissions, location,
and direct-parent existence before SwiftPM; the override never changes the
authoritative test graph, lock, diagnostic inputs, or aggregate XCTest count.
Five isolated-checkout fixtures additionally reject a symlink, directory,
multiple-hard-link, wrong-mode, or nonempty lock file before Swift runs.
The diagnostic reproduction command uses the same wrapper. Checkout does not
persist the GitHub token for repository scripts. The performance-build gate also
freezes the selected hermetic fixture into a private sampler root, launches only
that copy for eight samples, requires equal selected/private executable hashes,
`isolated_app_snapshot=true`, and an exact-PID normal zero-status termination;
its raw CSV/App log/summary remain runner-temporary. The sampler's bounded
success stdout is captured once in a Bash variable, and all acceptance checks
consume only that value; the workflow never reopens the public summary path
after producer exit. The v6.50 `app-build` gate independently freezes the real
`app.devisland.Island` Bundle and launches its shipping island/status item through
the paired hermetic opt-in. It requires eight per-second checks with no network
socket or isolated-home SQLite/Hook credential, plus exact-PID AppKit status-0
termination. The diagnostic label and reproduction command therefore describe
“Universal app build + Production launch smoke,” not static compilation alone.
The tag workflow repeats the same smoke after App notarization and before DMG
packaging. An `always()`
step records all 12 stable gates—including the disposable Sparkle update and bundled brand-asset inventory—generates the summary, publishes
only its private randomized output path, and writes the Markdown view to the
GitHub job summary.

`actions/upload-artifact` is:

- GitHub-owned;
- fixed to commit `ea165f8d65b6e75b540449e92b4886f43607fa02`;
- invoked only on `failure()`;
- scoped only to the sanitized output directory;
- configured to fail if the bundle is missing; and
- limited to 14-day retention.

Successful runs keep the concise GitHub job summary but do not create a
downloadable artifact.

The sampler and its local reproduction keep App, script and evidence paths
quoted end to end. In particular, a command-position script variable must be
invoked as `"$QA_ANALYZER"`; otherwise a valid T7 path such as
`/Volumes/T7 Shield/...` would be split and the performance-build gate could
report a tooling failure after the App had already launched and exited normally.
The three runner-temporary outputs are also claimed before launch through one
noclobber descriptor set. Existing files, links, concurrent claimants or later
inode replacement fail the performance-build gate. Readiness parsing receives
only a bounded no-follow/nonblocking App-log snapshot bound to descriptor 8;
the analyzer receives the equivalent CSV snapshot. Neither consumer reopens
its public evidence path for text parsing. The selected executable/plist are
descriptor-hashed before and after a strict-signature-checked `ditto` copy into
the sampler's private `0700` root. Only the private App is launched; both source
and copy are rebound before launch and after normal termination, so replacing
the workflow build output cannot make a successful summary describe a different
executable.

This stdout boundary matters even though the runner directory is temporary: PR
code is the program under test, so a faulty or adversarial QA descendant must
not be able to wait for sampler exit, replace the public summary, and influence
later `grep`/`sed` checks. The sampler redirects App output to descriptor 8 and
closes descriptors 7/9 in the App child. The workflow's quoted command
substitution therefore owns the only acceptance stream, and its shell variable
is discarded when the step ends.

## Local verification

```sh
./scripts/ci/verify-ci-diagnostics.sh
```

Fixtures cover a successful run, a failed test run, brand-gate first-failure
selection, test/security aggregation, output modes, fixed file count, raw
secret-marker non-disclosure and incomplete/reordered gates. Symbolic-link,
17 MiB sparse-file and multi-hard-link attacks prove that unsafe input degrades
to a bounded `sourceStatus` while the sanitized two-file bundle still exists.

The diagnostic artifact is operational evidence, not proof that CI ran on the
remote repository. GitHub branch protection must separately require the
`Tests, security, universal build` job as documented in
`docs/GITHUB_REPOSITORY_CONTROLS.md`.
