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
step records all 11 stable gates—including the bundled brand-asset inventory—generates the summary, publishes
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
