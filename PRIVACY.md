# Dev Island Privacy Notice

> Engineering-verified draft for owner and legal review. This file is not a
> substitute for legal advice and has not been published as a new policy.

Last updated: August 31, 2026

Dev Island is a local-first macOS application. The Dev Island maintainers do
not operate an account system, advertising network, product-analytics service,
or developer-controlled crash-reporting backend for the app. Some features do,
however, communicate with services that the user chooses to connect. This
notice distinguishes local processing from those third-party connections.

## 1. Data processed on your Mac

Dev Island may process:

- agent and session identifiers;
- task titles, status, phase, timestamps, and source URLs;
- waiting messages and progress messages;
- permission-request details, Claude Code questions, options, answers, and
  `ExitPlanMode` plan Markdown;
- bounded terminal host, TTY, and tmux pane hints used only to return to an
  active local CLI session;
- optional Codex rate-limit percentages, window lengths, reset times, and the
  provider event timestamp when you enable **Local Usage Insights**;
- transient Codex Hook metadata returned by the on-device official App Server
  while Dev Island checks whether its exact Hooks are enabled and trusted;
- when you explicitly run the engineering readiness command, bounded local
  Claude Code/Codex version output and an ephemeral loopback challenge used
  only to report low-cardinality readiness states;
- connector configuration state and notification preferences; and
- two local Boolean launch-health markers recording only whether a prior
  process started and reached AppKit's normal termination callback; and
- app version, macOS version, architecture, and aggregate session counts when
  you explicitly copy or save a diagnostic summary.

Local Claude Code, Codex, Cursor, preview Gemini CLI, preview Qwen Code,
preview GitHub Copilot CLI, and preview Kimi Code CLI hooks send data only to Dev Island's loopback
server at `127.0.0.1`. These CLIs may supply the Hook command with a complete
forward-extensible event payload, which may momentarily include a prompt,
response, transcript path, notification title/message, tool input, permission
suggestions, assistant output, error message/stack, or future fields; Dev
Island retains only the normalized task fields it needs and does not log or
persist the raw body. Copilot Preview additionally discards vendor-authored
notification text and stores only a fixed approval/input category message.
Kimi Preview likewise discards prompt, tool input, permission display/result
text, and error messages; only an allowlisted error category and fixed approval
copy can enter normalized state. Kimi's native UI remains the only approval
surface.
Before accepting any state-changing local Hook request, Dev Island requires a
fixed browser-preflight marker and a separate 256-bit random authorization
value that rotates whenever the listener starts or retries. The value is kept
only in memory and in the current user's private
`~/Library/Application Support/island-app/local-hook-authorization.header`
file (maximum 128 bytes, mode `0600`). Managed curl commands read that file
directly, and the OpenCode plugin stores only its path and reads a bounded
slice. The value is never written into Agent configuration, plugin source,
process arguments, SQLite, logs, copied/saved diagnostics, or a remote service.
This prevents another macOS user from forging local Hook writes; processes
running as the current login user remain inside the local-user trust boundary.
The preview OpenCode integration filters data inside its dependency-free plugin
before loopback transit. It sends only schema version, one of seven event
categories, session ID, cwd, an allowlisted `busy` / `idle` / `retry` status,
and bounded terminal/tmux headers. It does not send titles, prompts, messages,
tool arguments, permission metadata, or raw errors. Its one-second request is
not awaited and failure is ignored. Dev Island does not modify OpenCode's
`permission.ask` output; OpenCode remains the only approval surface.
When an exact Codex configuration is present, Dev Island may start a
short-lived OpenAI-signed Codex App Server process solely to call `hooks/list`.
The bounded response can momentarily include metadata for unrelated Hooks, but
only the aggregate activation result for Dev Island's exact definitions leaves
the probe. The response is not networked, persisted, logged, or copied to
diagnostics and is best-effort erased from memory after the check. The probe
cannot modify configuration or trust, and it does not start a Codex thread.
The explicit `local-live-readiness` engineering command checks only known
local executables, caps version stdout at 4 KiB, discards stderr, and erases
the captured bytes after comparing a semantic-version token with the reviewed
baseline. It also sends a random one-time challenge to the local Hook listener;
the endpoint rejects browser-originated requests and returns no task or config
data. The command does not install or update Hooks, change trust, open a
session, or contact a Dev Island remote service.
The separate `local-hermetic-listener-check` engineering command starts only a
temporary listener on a random loopback port with an in-memory random
authorization value and no Agent routes. It proves the challenge route, stops
the listener, and then proves that the route is gone. It does not read or write
the production authorization file, Agent configuration, Keychain, SQLite, or
tasks; framework logs are suppressed and only five fixed low-cardinality lines
are printed. This transport fixture does not mean that the production app or a
real Agent session is ready.

Enabling, updating, or removing a local Agent integration is always an
explicit action. Dev Island reads at most 4 MiB from a structured Agent
configuration file (and at most 256 KiB from its owned OpenCode plugin), edits
only its managed Hook entries, and does not upload the file. Mutating paths
reject target symbolic links, hard links, non-regular files, wrong ownership,
unsafe writable or dangling parent directories, and content drift detected
before commit. A safely symlinked configuration directory is resolved
once and anchored to support dotfiles layouts without allowing later
redirection. New configuration files use mode `0600`; updates preserve the
existing file permissions. A bounded read-only marker check may recognize an
unsafe legacy linked file so Settings can request review, but Dev Island does
not trust or modify that file.
Settings and Welcome perform the bounded configuration scans and explicit
enable/update/disable writes in an on-device background worker so JSON/TOML
parsing and file/directory synchronization do not block the interface. Only a
low-cardinality installed/configured/update-required/absent result, target
success/failure classification, or fixed error message returns to the main
actor; configuration bytes, paths, parser errors, and unrelated Hook content do
not. Operation IDs and progress state remain in memory only, and no new network
or persistence destination is created.
Settings keeps one in-memory mutation owner above its page switch, so a single
Agent change and **Disconnect All…** cannot run concurrently even if you leave
and reopen Agent Connections. The bulk worker returns only whether nothing
changed, an aggregate disconnected count, or a fixed failure; it does not send
configuration paths, raw errors, file contents, or unrelated Hooks to the
interface. Closing Settings releases this presentation state after any already
started atomic file transaction reaches its existing completion boundary.
Permission details, question forms, and plan-review content are held in memory
only while the request is pending. The exact injected plan input is echoed back
to Claude Code only after the user approves; it is not logged or persisted by
Dev Island. Plan Markdown is limited by both characters and 262,144 UTF-8
bytes. Its block and inline formatting are parsed once in an on-device
background worker; only an immutable document of at most 512 complete blocks
returns to the interface. Rendered blocks and operation IDs remain memory-only,
create no network or persistence destination, and late work is discarded.
Approve/Reject stays unavailable until the complete document is ready; an
empty or over-complex document must be continued in Claude Code instead of
being approved from a partial island view. Normalized terminal/tmux jump hints
are held only with the active
in-memory session and are excluded from SQLite, logs, history, and copied
diagnostics. When you click a tmux-backed task, Dev Island passes only the
validated socket and pane to a local trusted tmux executable without a shell,
HOME, or unrelated inherited environment; stdout is memory-only, capped at
4 KiB, and the command is forcibly bounded. Normalized task records and Manus
progress events can be stored locally in:

`~/Library/Application Support/island-app/tasks.sqlite`

**Project branch labels stay on your Mac.** To show which git branch a local
agent session is working on, Dev Island reads at most 4 KiB from the `.git`
entry and `HEAD` file of that session's project directory (walking up at most
eight parent directories) through a no-follow descriptor that must belong to
the current user. Only the bounded branch name or a seven-character commit
prefix reaches the interface. No other project file is opened, and the branch
is never logged, stored in the database, copied into diagnostics, or sent
anywhere.

**Local Usage Insights is off by default.** When you enable it, Dev Island
looks on demand for Codex-authored `token_count` rate-limit events in bounded
suffixes of recent local Codex rollout files. A refresh examines at most 8,192
directory entries, retains only the newest 24 candidates, and reads the exact
initial at-most-512-KiB suffix through a validated no-follow descriptor; a file
that grows concurrently cannot expand that read. Its decoding model has no fields
for prompts, responses, paths, account/session IDs, or credentials; that
content is ignored and is never returned to the interface, logged, copied into
diagnostics, or stored by Dev Island. The interface receives only percentages,
window durations, reset timestamps, and the event time. No network request or
Keychain access is made for this feature. Turning it off clears the in-memory
snapshot.

Dev Island does not upload local hook payloads to the Dev Island maintainers.
You can remove one integration or use **Settings → Agent Connections →
Disconnect All…**. Both paths remove only Dev Island command handlers. User
settings and unrelated Hooks remain in their original configuration files;
the all-Agent action prepares every edit before writing and rolls back an
incomplete operation without overwriting a concurrent external edit.
For Kimi Code's shared TOML file, Dev Island validates the complete syntax but
never reserializes user settings; install/update/uninstall edits only explicit
managed blocks and otherwise preserves bytes exactly.
For OpenCode Preview, Dev Island owns only the complete marked
`~/.config/opencode/plugins/dev-island.js` file. Unowned collisions, symbolic
links, directories/devices and files over 256 KiB are not overwritten or
removed. A managed file uses mode `0600` and participates in the same rollback
boundary without replacing an externally recreated path.

## 2. Manus connector

The optional Manus connector communicates directly with
`https://api.manus.im` at your request. It sends your Manus API key in an
authenticated request and may send task or webhook identifiers and a stop-task
command. It receives task identifiers, titles, states, timestamps, and task
URLs. Manus' own terms and privacy policy govern its processing.

The API key is stored as a macOS Keychain item with service
`app.devisland.Island`, account `manus_api_key`, and
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Disconnecting Manus removes
that item. Polling results are accepted only for the currently active Manus
service generation; results that arrive after disconnect, reconnect, or key
replacement are discarded. If Manus returns an unauthorized response, the app
marks the stored key invalid, stops that polling lifecycle, disconnects the
realtime lifecycle if present, and asks you to reconnect. Concurrent Connect
attempts use the most recent request only; an older validation result cannot
replace the newer key. Disconnect stops Manus network activity and removes
live Manus tasks even if Keychain deletion fails. In that failure case the app
does not claim the credential was removed: it shows a fixed retry message and
keeps Disconnect available until device-local deletion succeeds.

Dev Island's ordinary unit and pull-request tests do not read, add, update, or
delete items in the signed-in user's Keychain. They inject process-memory
storage and inspect only the shipping adapter's fixed device-only,
non-synchronizing query policy. A random Keychain service name is not treated
as isolation. Any future live Keychain acceptance must be run explicitly in a
disposable macOS test account or virtual machine, not in a maintainer's normal
login session.

Public Manus Webhook creation/delivery and the Cloudflare quick tunnel are
disabled in the current Release configuration. Credential-backed cleanup and
reconciliation remain available so an earlier callback is not abandoned. Dev
Island implements Manus' documented v2 flow at `https://api.manus.ai`: an
authenticated request retrieves the RSA verification key, registration sends
the public callback URL, and `GET /v2/webhook.list` can return up to 1,024
account-owned Webhook IDs, exact callback URLs, active/inactive states, and
creation timestamps. A full listed URL is held only in memory while recovery
matches it. Before registration crosses the network, one versioned local
recovery envelope stores the callback URL's SHA-256 digest, a random attempt
token and start time together with the cleanup-ID ledger; Webhook payloads and
task content are not stored there. Any IDs discovered during recovery are
bound into that same envelope and read back before deletion is attempted.

Recovery considers only active entries whose exact URL digest and creation
time match one uniquely attributable attempt within 300 seconds before or
after its recorded start. Unrelated entries are never deleted. Multiple local
attempts with the same digest, malformed or oversized provider inventory, a
failed/empty list, inactive entries, timestamps outside the window, or corrupt
or legacy token-only local state remain unresolved and retain the credential.
Once exact IDs have been durably bound, later retries use those IDs without
listing the account again. Local state clears only after a 2xx JSON response
with `ok: true`, or Manus' exact authenticated 404 `not_found` response, confirms
the desired delete postcondition. A credential-releasing stop succeeds only
when the ID ledger, attempt/token records, and all registration, listing, and
deletion ownership are empty and uncorrupted.

The RSA key is cached in memory for at most one hour. This flow must not be
enabled until a real account proves create, signed delivery, lifecycle events,
list/delete recovery, and read-after-create/read-after-delete behavior and the
result is reviewed. If a future reviewed build enables
that path, Dev Island treats a tunnel as active only after Manus also confirms
the Webhook registration and a private, bounded loopback challenge proves that
this Dev Island process owns the local listener. The challenge response is
limited to 256 bytes and cannot follow redirects, use a proxy, or leave the
Mac. Startup, wake, registration, or heartbeat recovery failure closes the
unregistered tunnel and falls back to periodic API polling; a successful poll
alone is not reported as a healthy realtime connection.
Quick-tunnel startup output is read only in memory, capped at 1 MiB, never
logged or persisted, and continuously discarded after the validated callback
origin is found. Silent, excessive-output, cancelled, or unresponsive tunnel
processes are terminated within a bounded local cleanup path.
Signed delivery uses an in-memory replay window containing at most 1,024
bounded event identifiers. Each identifier remains only until its authenticated
signature timestamp expires; a newer authenticated retry extends that expiry.
If all entries are still live, a new identifier receives a temporary 503
response instead of causing a live entry to be evicted. Duplicate identifiers
return success without changing task state. Completed or failed Manus tasks
also cannot be moved back into the waiting queue by a later stopped event. The
window is not written to preferences, SQLite, logs, or diagnostics.

The source repository includes an explicit maintainer-only live-acceptance
wrapper. It never reads a Manus key from arguments or environment: the key
still enters only through the CLI's hidden interactive terminal prompt. When
the maintainer runs it, the wrapper keeps a private local evidence package on
T7 Shield containing a copied CLI binary, source/binary hashes, commit and
dirty/clean state, UTC timing, exit/validation states, and only fixed
low-cardinality checkpoints. It excludes provider identifiers, callback URLs,
payloads, task content, raw errors, and the key. No accepted marker is created
unless the CLI exits successfully and the exact transcript contract passes.
The source evidence automatically covers every local IslandCore/CLI compiler
input and exact clean dependency checkout revision, plus Swift/Xcode/SDK
fingerprints before and after the build; it records hashes and revisions, not
dependency source content or user data.

## 3. Updates

When authenticated automatic updates are enabled, Sparkle requests an XML
appcast and update archive from GitHub Releases. System profiling is disabled,
so Dev Island does not ask Sparkle to send a hardware or software profile.
GitHub may still receive ordinary network metadata such as IP address,
timestamp, and user agent under GitHub's privacy policy. Automatic checks can
be disabled in Dev Island Settings.

The update feed and archive are verified before installation. Local and CI
builds without the complete HTTPS and Ed25519 trust configuration do not start
the updater.

The source repository also includes a maintainer-only disposable old-to-new
update gate. It uses synthetic Apps, public fixture keys and a loopback-only
server inside one random current-user `0700` macOS temporary directory. The
pinned Sparkle source build and updater run receive separate private HOME
directories, and the runtime receives `__CFPREFERENCES_AVOID_DAEMON=1`; a
hash-bound source overlay routes helper cache and launch-job state there. The
gate never reads or writes the maintainer's real preferences/cache, invokes
`defaults write/delete`, touches an installed Dev Island App, or receives a
production update key. Its temporary root is removed on exit; failure cleanup
may signal only helper processes whose complete executable paths remain inside
that exact random root.

## 4. Notifications, logs, and diagnostics

If you grant notification permission, macOS Notification Center receives the
agent name and a task title, phase, or waiting message needed to show the
notification, plus the filename of a bundled short signal sound when sounds are
enabled. This is local operating-system processing; notification content may
appear on the lock screen according to your macOS settings. Signal sounds can
be muted in Settings and inherit macOS Focus and notification-sound policy.

Dev Island writes low-cardinality operational events to Apple's unified
logging system. These logs do not include API keys, task/session/webhook
identifiers, request or tunnel URLs, filesystem paths, external-process
output, raw response bodies, or raw error descriptions. They may include
allowlisted provider/Agent names, event categories, HTTP status codes,
aggregate counts, and bounded retry timing. Log retention and access are
controlled by macOS.

**Copy / Save Diagnostics** is user initiated. It places the same summary on
the clipboard or writes a private local text file to the folder you choose.
The summary contains app and OS versions, architecture, Manus connection
state, local Agent listener health, configured-key state, whether the previous
launch reached the app's brief ready milestone, a bounded consecutive startup-
interruption count, and aggregate counts. It excludes API keys,
prompts, task titles, task IDs, session IDs, URLs, and file-system paths. The
file is created with owner-only permissions and remains until you delete or
replace it. Nothing is uploaded or sent automatically; you decide whether and
where to paste or share it. Diagnostic preparation and the confirmed local-file
transaction run in an on-device background worker so file synchronization does
not block the interface. Leaving the Support pane discards late interface
updates; a file transaction already started at the destination you confirmed
may finish atomically. This adds no data or destination.

The signed App also includes exact, read-only copies of this notice and the
current Terms in `Contents/Resources/Legal`. Opening **Privacy Notice** or
**Terms of Use** in Settings reads only the selected bilingual App resource;
it creates no preference, cache, history, analytics event, or acceptance
record and makes no network request. Each copy is capped at 512 KiB and checked
for its expected titles, matching English/Chinese review date, UTF-8 structure,
and exact equality with the repository source before signing. Links remain
plain readable text unless they are one of the two reviewed support email
addresses or the exact `https://devisland.app` origin. These bundled copies are
still drafts for owner/legal review and are not proof of consent or publication.

The repository's maintainer-only pull-request CI also creates a separate
sanitized engineering diagnostic. It contains repository/run identifiers,
fixed build-gate outcomes, aggregate test counts, sanitized failed-test names,
completed security-gate names, and a low-cardinality status describing whether
its temporary input logs were safely readable. It does not collect data from a
user's installed App. Raw logs, arbitrary assertion/error text, environment
variables, credentials, and Dev Island user data are excluded. The summary is
shown in the GitHub job; on a failed run only, its two-file artifact is retained
by GitHub for 14 days. Unsafe, linked, oversized, or concurrently changed input
is omitted rather than copied.

The repository also contains a separate maintainer-only Codex live-approval
evidence wrapper. It runs only when a maintainer explicitly selects one local
Codex session, the Dev Island history database, a proof file, the tested App
and CLI, and three manually reviewed screenshots. The wrapper reads the raw
session and database through bounded no-follow descriptors but never copies
either source. It retains only a fixed low-cardinality state transcript, one
sanitized completed-task record, artifact and executable hashes, exact proof,
the three screenshots, and an explicit human confirmation of the visual
`waiting,allow_once,running,completed` sequence in a private `0700` T7 Shield
package. Symlinks, multiple hard links, unsafe permissions, changed inputs,
unexpected session events, version drift, invalid App signing, altered hashes,
or a missing Codex exit-zero/final marker cannot create `ACCEPTED`. A redacted
receipt is checked into the repository so CI and tagged Release gates can
require the recorded round trip without receiving raw Codex messages,
reasoning, unrelated database rows, local paths, or credentials. This is a
maintainer QA flow and does not inspect a user's installed App.

The repository also has a separate maintainer-only Codex live-decision
classifier and evidence wrapper for denial and timeout QA. It locally reads one
explicitly selected Codex session, the expected-absent proof path, one matching
Dev Island history row, the tested App/CLI, and two manually reviewed images;
there is no network destination. Raw JSONL, SQLite rows, prompts, reasoning,
commands, and local paths are never copied. A private T7 Shield package retains
only fixed checkpoints, a sanitized task row, hashes, two JPEGs, and a
proof-absence attestation. `explicit_island_deny`,
`neutral_timeout_fallback`, `sandbox_rejection`, and `interrupted_attempt` are
separate outcomes; only the first, completed before the 90-second fallback and
with the proof still absent, may create `ACCEPTED`. The parser never evaluates
recorded JavaScript. A real unlocked island denial has now passed the complete
package gate, so the repository contains only its redacted receipt; the raw
session, database, command, proof path, and local paths remain outside the
repository. This maintainer QA flow does not inspect a user's installed App or
change macOS accessibility or appearance settings, and the receipt does not
turn one dirty-worktree QA session into a clean commercial Release claim.

The Security gate additionally scans bounded UTF-8 App, QA, CI, Release, and
workflow source locally for commands or APIs that could mutate the
maintainer's macOS login-session preferences, terminate unrelated processes,
change launch-service state, or invoke AppleScript. The scan does not execute
source, access the network, or inspect installed-App or user content. It is a
repository safeguard, not a runtime sandbox for external automation or manual
actions; system-toggle QA therefore remains restricted to an isolated macOS
test account or VM.

Maintainer CI and tagged Release gates also statically parse the checked-in
workflow YAML and Bash `run` steps. A bounded structural pass rejects
ambiguous duplicate or multi-document YAML before safe loading. Complete GitHub expressions
are replaced by one inert placeholder before `/bin/bash -n`; the effective workflow/job/step shell
is also checked against the exact reviewed Bash set. The
scripts are not executed and no Secret, installed-App data, or user content is
read or retained. Temporary attack fixtures are removed when the local gate exits.

Before repository release gates execute other project tooling, they also parse
all repository Bash, Ruby, and Swift scripts from bounded, validated descriptors using
`bash -n`, `ruby -c`, or `swiftc -parse` over stdin. The scripts are not executed, no network or
installed-App data is accessed, and parser output/source content is not retained.

Maintainer App builds also inspect the newly built executable locally for six
fixed build-flavor markers: three Performance QA literals and three DEBUG-only
literals. The check streams `/usr/bin/strings` only into exact fixed-string
comparisons; raw strings and match context are not logged or retained. It does
not inspect a user's installed App or read tasks, sessions, file paths,
Keychain values, Agent configuration, credentials, or other user data, and it
does not use the network.

PR CI also launches only the newly built, compile-time-hermetic Performance QA
App with a private temporary `CFFIXED_USER_HOME`. That fixture disables SQLite,
Keychain, local Hooks, Manus, notifications, onboarding, and update networking.
The maintainer harness retains only Bundle/version/hash and machine metadata,
display classification, readiness, eight bounded CPU/RSS samples, the exact
fixture PID, and normal exit status in runner-temporary files; it does not read
an installed App, Agent configuration, credentials, or crash reports. Locked or
unknown display state may be accepted only for this startup-survival smoke and
cannot support a product or Release performance claim.

The separate maintainer-only `production-launch-smoke` freezes and launches the
real `app.devisland.Island` Bundle through an exact argument-and-environment
opt-in that ordinary Finder or LaunchServices starts do not receive. It renders
the shipping island and status item with an inert TaskStore while launch-health
tracking, notifications, onboarding, Sparkle, SQLite, Keychain, local Hooks and
Manus remain unstarted. Readiness and each of the eight one-second survival
samples check only whether the exact PID has any network socket and whether the
private home created SQLite or the Hook-authorization file; no destination or
payload is collected. PR CI runs this after Production build, and tag Release
repeats it after App notarization and before DMG packaging. These samples are an
artifact-survival/isolation gate, never product performance evidence.

Those three temporary evidence files are claimed together before launch using
current-user `0600` single-link descriptors. Existing files, symbolic links,
concurrent claimants, unsafe parents, or later device/inode replacement fail
closed. Readiness is parsed only from a bounded `NOFOLLOW`/`NONBLOCK` descriptor
snapshot rebound to the App-log writer identity; malformed or duplicate
markers, FIFO replacement, and reverse/out-of-window uptime fail closed.
Statistics use the equivalent CSV-writer-bound snapshot. Neither consumer
repeatedly reopens its public evidence path.

The selected Performance QA or Production App is likewise treated only as
bounded maintainer input. Its
main executable and `Info.plist` are descriptor-hashed and strict-signature
checked before a complete copy is made into the sampler's random private
`0700` directory. Only that private App is inspected and launched. Both source
and copy identities are rechecked before launch and after normal termination;
source replacement fails without publishing a summary. A successful summary
retains matching selected/private executable hashes and the fixed
`isolated_app_snapshot=true` state. The temporary copy is deleted when the
sampler exits and never reads an installed App or user content.

In pull-request CI, the verified summary used for acceptance is captured once
from the sampler's bounded stdout into a shell variable. All survival and hash
checks read only that in-process value; CI does not reopen the runner-temporary
summary path after the producer exits. This prevents a leftover QA descendant
from changing acceptance by replacing that public file. The variable is not
written to GitHub outputs, environment, caches, diagnostics, or artifacts and
is discarded when the step ends. It contains only the same fixture, machine,
display, and aggregate sample fields already described above.

## 5. Preferences and local retention

Dev Island uses local preferences for onboarding completion, notification
choices, updater settings, and bounded launch-health state: two Booleans, a
schema version, and a consecutive startup-interruption count capped at three.
The ready marker is written after the island and menu-bar surfaces stay alive
through a two-second startup window. A missing marker can follow a quick Force
Quit, power loss, an OS restart, or a crash; those events remain
indistinguishable. Dev Island does not inspect a crash report or infer which
event occurred. An older ambiguous clean-shutdown marker
is migrated silently and is not treated as evidence of a startup interruption.
Only if verified realtime is enabled in a future build, preferences may also
hold a temporary Manus webhook identifier. Launch at Login is managed by macOS
Service Management.

Task and progress history uses automatic finite retention in the local SQLite
database: Dev Island keeps at most the newest 5,000 task rows and 20,000
progress rows. It applies deterministic pruning whenever the database opens
and after every write, and removes progress that belongs to an evicted task.
New rows are rejected atomically if their identity or text fields exceed the
documented byte limits. When the database opens, wrong-type or oversized old
rows are removed once; history queries repeat the type and byte checks before
text is materialized in the app, including if another process modifies a row
after opening. Normal event writes use per-record validation rather than a
repeated full-table content scan.
The App-owned final database folder is restricted to the current user (`0700`),
and the database plus existing SQLite WAL/SHM/journal files are restricted to
the current user (`0600`). Dev Island rejects links, non-regular files,
wrong-owner entries, and multiply linked database files before SQLite access;
it also keeps no-follow anchors for both the final folder and main file, uses
directory-relative no-follow operations for existing sidecars, and retains
both descriptors for the full SQLite Connection lifetime. It rechecks the
anchored directory, main file, and sidecars before and after every history
read, write, retention pass, and Clear History transaction. A replacement
detected before commit rolls back the write; one detected after a read prevents
the materialized page from being returned. The first runtime boundary failure
terminally disables the active history-store instance, so later calls stay
unavailable instead of appearing as an empty history or successful clear.
Local Agent listening and current in-memory sessions continue.
You can delete the history sooner with **Settings → Support → Clear History**
or by removing the database manually. The private **View History** sheet reads
up to the 200 most recent task snapshots and lets you search locally by task
title or Agent name. Those rows are not restored into the live island and do
not cause notifications. The clear control removes both stored tables in one
transaction without hiding currently active sessions from the island.
Deleting the app bundle alone may not delete Application Support, preferences,
or Keychain items. Disconnect Manus before uninstalling if you want the app to
remove its stored API key.

## 6. Website and support

The product website is hosted by third-party infrastructure. Dev Island does
not intentionally install advertising or product-analytics trackers there,
but the hosting provider may process normal web-server metadata. Following a
GitHub download link is governed by GitHub's privacy policy.

If you email the maintainers, your mail provider and the maintainers' email
provider process the address, headers, and content you choose to send. Do not
send API keys, private prompts, or other secrets in support email.

## 7. No sale of personal information

The Dev Island maintainers do not sell personal information or use app data
for cross-context behavioral advertising. The app currently has no developer-
controlled telemetry or remote crash-reporting service.

## 8. Security and your choices

You can choose which connectors to enable, disable notifications or automatic
update checks, disconnect Manus, remove Dev Island's hook entries, and decide
whether to copy, save, or share diagnostics. No system can be guaranteed completely
secure; report a suspected vulnerability without including secrets.

## 9. Changes and contact

Material changes will update the date above and must describe any newly added
data flow before the corresponding feature ships. Questions can be sent to
[alsoaxu@gmail.com](mailto:alsoaxu@gmail.com) or
[puzhen913@gmail.com](mailto:puzhen913@gmail.com).

---

# Dev Island 隐私说明

> 这是经过工程实现核对的草案，仍需产品负责人及法律专业人士审阅；目前尚未作为
> 新版线上政策发布，也不构成法律意见。

最后更新：2026 年 8 月 31 日

Dev Island 是一款本地优先的 macOS 应用。维护者没有为 App 运行账号系统、广告
网络、产品分析服务或由开发者控制的崩溃上报服务。但当用户主动启用某些功能时，
App 会与用户选择的第三方服务通信。本说明会明确区分本机处理与第三方连接。

## 1. Mac 本机处理的数据

Dev Island 可能处理 Agent/会话标识、任务标题、状态、阶段、时间、来源 URL、等待
或进度消息，审批详情、Claude Code 问题、选项、回答与 `ExitPlanMode` 计划正文，以及
只用于返回活跃本地 CLI 会话的有限终端宿主、TTY 与 tmux pane 提示。App 还会在本机
偏好中保存两个布尔型启动健康标记，只记录上个进程是否启动并到达 AppKit 的正常退出
回调；它不读取或上传 macOS 崩溃报告。

Claude Code、Codex、Cursor、预览版 Gemini CLI、预览版 Qwen Code、预览版 GitHub
Copilot CLI 与预览版 Kimi Code CLI 的本地 Hook 只访问 `127.0.0.1`。这些 CLI 可能把完整且可扩展的事件载荷
交给 Hook 命令，其中可能短暂包含 Prompt、回复、transcript 路径、通知标题/正文、
工具输入、权限建议、错误 message/stack 或未来字段；Dev Island 只提取所需的标准化
任务字段，不记录或持久化原始正文。Copilot Preview 还会丢弃厂商生成的通知正文，
只保留固定的“需要审批/输入”类别文案；Kimi Preview 同样丢弃 Prompt、工具输入、
权限展示/结果正文与错误消息，只允许固定审批文案和白名单错误类别进入标准化状态，
并始终由 Kimi 原生界面完成审批。审批、问答与计划审阅内容只在请求等待期间
保存在内存中；用户批准
计划后，Dev Island 才把 Claude Code 注入的原始计划输入原样返回，且不会记录或
持久化这些内容。标准化终端/tmux 跳回提示只随活跃会话保存在内存中，不会进入
SQLite、日志、历史页面或复制的诊断。点击 tmux 会话时只把已验证的 socket/pane 交给
本机可信 tmux executable，不经过 shell，不继承 HOME 或无关环境；stdout 仅在内存中
处理、上限 4 KiB，命令超时或异常时会被强制结束。

所有会改变本地会话状态的 Hook 请求还必须同时携带固定的浏览器预检标记，以及每次
监听启动或重试都会轮换的 256-bit 随机授权值。该值只短暂存在于内存和当前用户私有的
`~/Library/Application Support/island-app/local-hook-authorization.header` 文件中；文件
最多 128 bytes、权限为 `0600`。托管 curl 命令直接通过 Header 文件读取，OpenCode 插件
只保存路径并有界读取。授权值不会写入 Agent 配置、插件源码、进程参数、SQLite、日志、
复制/保存的诊断或任何远程服务。这会阻止同一台 Mac 上的其他用户伪造 Hook；当前登录
用户下能够读取该文件的进程仍属于本地用户信任边界。

预览版 OpenCode 集成会在无依赖插件内先过滤数据，再发送到本机回环地址。它只发送
schema 版本、七类事件之一、会话 ID、cwd、`busy` / `idle` / `retry` 白名单状态以及
有限的终端/tmux Header；标题、Prompt、消息、工具参数、权限 metadata 与原始错误不会
进入传输。请求不会被 await，并在一秒后 abort，失败会被忽略。Dev Island 不修改
OpenCode 的 `permission.ask` output，审批始终回 OpenCode 完成。

当 Codex 的精确配置存在时，Dev Island 可能短暂启动由 OpenAI 签名的 Codex App
Server，仅调用 `hooks/list` 检查自身 Hook 是否已启用并受信任。有界响应可能瞬时包含
其他 Hook 的元数据，但只有 Dev Island 精确定义的汇总激活结果会离开探针；原始响应
不会联网、持久化、记录日志或进入诊断，并会在检查后尽力从内存清除。该探针不能修改
配置或信任，也不会创建 Codex 线程。

只有在用户显式运行工程诊断命令 `local-live-readiness` 时，Dev Island 才会对已知
本地 Claude Code/Codex 可执行文件执行有界的版本检查，并向本机 Hook 监听器发送
一次性随机 challenge。版本输出最多 4 KiB，只在内存中比较版本 token，之后清除，
不会打印、记录或持久化；监听器拒绝来自浏览器 Origin 的请求，也不会返回任务或
配置内容。该命令不会安装/更新 Hook、修改 Codex 信任、创建会话或访问 Dev Island
远程服务。

独立的工程诊断命令 `local-hermetic-listener-check` 只会在随机本机回环端口短暂启动
一个使用内存随机授权且不含任何 Agent route 的监听器。它先验证 challenge route，随后
停止监听器并再次确认 route 已消失；不会读取或写入生产授权文件、Agent 配置、Keychain、
SQLite 或任务。底层 framework 日志被关闭，终端只输出五行固定低基数状态。该 transport
夹具通过不代表生产 App 已监听，也不代表真实 Agent 会话已经可用。

Settings 与 Welcome 会在本机后台 worker 中执行这些有界配置扫描，以及用户明确触发的启用、更新和停用，
因此 JSON/TOML 解析与文件/目录同步不会阻塞界面。主线程只接收低基数的已安装/需更新/未安装
状态、等待 vendor trust 的已配置状态、目标成功/失败分类或固定错误文案；配置字节、路径、parser
错误和无关 Hook 内容都不会返回。
操作 ID 与进度状态只存在于内存中，不会新增网络或持久化目的地。
Settings 会在页面切换层之上保留一个仅内存的 mutation owner，因此即使离开并重新打开
Agent Connections，单 Agent 更改也不能与 **Disconnect All…** 并发。批量 worker 只返回
无变化、断开总数或固定失败，不会把配置路径、原始错误、文件内容或无关 Hook 带回界面。
关闭 Settings 后，该呈现状态会在任何已经开始的原子文件事务到达既有完成边界后释放。

Claude `ExitPlanMode` 计划正文同时受字符数与 262,144 UTF-8 bytes 上限约束。块级和 inline
Markdown 只会在本机后台 worker 中为每个请求解析一次，界面只接收最多 512 个完整块的不可变
document；渲染块、request/operation ID 与进度状态只存在于内存，不会新增网络或持久化目的地，
晚到结果会被丢弃。完整非空 document 准备好之前 Approve/Reject 不可用；空白或过度复杂的计划
不能在截断岛内视图中批准，只能选择回到 Claude Code 查看完整内容。

**本地用量洞察默认关闭。** 用户开启后，Dev Island 才会按需查找 Codex 写入的
`token_count` 限额事件。每次刷新最多检查 8,192 个目录项，仅保留最新 24 个候选，并
通过 no-follow descriptor 校验文件类型、owner 与权限，再精确读取首次测量的最多
512 KiB 尾部；文件并发增长不能扩大本次读取。解码模型不包含 Prompt、回复、路径、
账号/会话 ID 或凭据字段，只把百分比、窗口时长、重置时间与事件时间交给界面；不会
联网、访问钥匙串、写入数据库、日志或诊断。关闭功能会清除内存摘要。

**项目分支标签只留在你的 Mac 上。** 为了显示本地 Agent 会话正在哪个 git 分支上工作，
Dev Island 只会通过属于当前用户的 no-follow descriptor，从该会话项目目录（最多向上查找
八层父目录）的 `.git` 条目与 `HEAD` 文件读取至多 4 KiB。界面只会收到有界的分支名或
七位提交前缀；不会打开项目中的其他文件，分支也不会被记录到日志、数据库、诊断或发送到
任何地方。

标准化任务记录及 Manus 进度事件可能保存在：

`~/Library/Application Support/island-app/tasks.sqlite`

本地 Hook 原始载荷不会上传给 Dev Island 维护者。
用户可以逐个移除连接器，也可以使用 **设置 → Agent Connections → Disconnect
All…**。两种方式都只删除 Dev Island 的 command handler，用户设置和其他 Hook
继续保留；全局操作会在写入前准备全部编辑，中途失败时回滚，且不会覆盖同时发生的
外部配置修改。对于 Kimi Code 共用的 TOML 文件，Dev Island 会校验完整语法但不会
重新序列化用户设置，只编辑显式受管区块，其余字节保持不变。
对于 OpenCode Preview，Dev Island 只拥有带精确 marker 的完整
`~/.config/opencode/plugins/dev-island.js` 文件；不会覆盖或删除未归属冲突、符号链接、
目录/device 或超过 256 KiB 的文件。受管文件权限为 `0600`，并参与同一回滚边界，
但不会覆盖操作期间由外部重建的路径。

## 2. Manus 连接器

可选的 Manus 连接器会按用户操作直接访问 `https://api.manus.im`，发送 Manus API
Key、任务或 Webhook 标识以及停止任务指令，并接收任务标识、标题、状态、时间和
任务 URL。相关处理受 Manus 自身条款与隐私政策约束。

API Key 作为 macOS 钥匙串项目保存，service 为 `app.devisland.Island`，account 为
`manus_api_key`，且仅在本机解锁后可访问。断开 Manus 会删除该项目。

Dev Island 的普通单元测试与 PR 测试不会读取、新增、更新或删除当前登录用户的钥匙串项目；
它们注入进程内存存储，只检查 shipping adapter 固定的 device-only、非同步 query 策略。随机
Keychain service 名称不视为隔离。未来任何真实 Keychain 验收都必须在显式、可处置的 macOS
测试账户或虚拟机中运行，不得使用维护者的日常登录会话。

当前 Release 配置没有启用公网 Manus Webhook 创建/投递与 Cloudflare Quick Tunnel；但会保留
credential-backed 清理与 reconciliation，避免遗弃旧回调。Dev Island 已按 Manus 当前 v2 文档
实现 `https://api.manus.ai` 的鉴权公钥获取、回调注册与签名事件处理，并可通过
`GET /v2/webhook.list` 接收账号下最多 1,024 项 Webhook ID、精确回调 URL、active/inactive 状态与
创建时间。完整 list URL 只在恢复匹配时存在于内存。每次注册跨越网络前，单一 versioned 本机
recovery envelope 会把回调 URL 的 SHA-256 digest、随机 attempt token、开始时间与 cleanup-ID
ledger 一起保存；不保存 Webhook payload 或任务内容。恢复发现的 ID 也必须先原子绑定到同一
envelope 并完成 readback，之后才能删除。

恢复只考虑 active、精确 URL digest 相同、且创建时间位于 attempt 开始时间前后各 300 秒内的
条目，并且该 digest 必须只属于一个本机 attempt；无关条目永不删除。同 digest 对应多个本机
attempt、provider list 非法/超限、list 失败或为空、inactive、超出时间窗、损坏 envelope 或只有旧版
token 的状态都会失败关闭并保留凭据。精确 ID 一旦持久绑定，后续重试不再重新 list 账号。只有
2xx 且 JSON `ok: true`，或来自同一官方 origin 的精确 404 `not_found`，才能确认删除后置条件并
清除本机状态。credential-releasing stop 只有在 ID ledger、attempt/token 记录以及全部 registration、
listing、deletion ownership 均为空且未损坏时才能成功。

公钥最多只在内存缓存一小时。但真实账号仍未完成 create、签名投递、生命周期、list/delete 与
read-after-create/read-after-delete 一致性的端到端验收，因此正式版本继续失败关闭，未完成复核前
不得启用。Quick
Tunnel 启动输出仅在内存中有界读取（最多 1 MiB），不记录、不持久化；验证回调 Origin
后继续只排空并丢弃。远端注册前还必须用随机私有 challenge 证明本进程拥有本机监听器；
响应最多 256 字节，禁止重定向、代理与离开本机。静默、超量输出、取消、端口冲突或拒绝
退出的子进程都会进入有界终止清理。
签名事件使用最多 1,024 个有限 event ID 的纯内存重放窗口。每个 ID 只保留到对应已认证签名
时间戳到期；同 ID 的较新有效 retry 会延长到期点。若全部条目仍有效，新 ID 会临时返回 503，
而不是驱逐一个仍可被重放的旧条目；重复 ID 返回成功但不再次改变任务状态。已经 Completed
或 Failed 的 Manus 任务也不能被后来的 stopped 事件拉回 Waiting。该窗口不会写入偏好、
SQLite、日志或诊断。

源码仓库另含维护者主动运行的真实验收包装器。它不从参数或环境读取 Manus Key，Key
仍只进入 CLI 的交互式隐藏终端输入。运行时只在 T7 Shield 保存私有本机证据包，包括本轮
CLI 副本、源码/二进制哈希、commit 与 dirty/clean、UTC 时间及退出/验证状态，并只允许固定
低基数 checkpoint；Key、provider 标识、回调 URL、payload、任务内容和原始错误都不进入
证据。只有 CLI 成功退出且精确 transcript 契约通过时才会生成 accepted marker。
源码证据会自动覆盖全部 IslandCore/CLI 本地编译输入、精确且 clean 的 dependency checkout
revision，以及构建前后的 Swift/Xcode/SDK 指纹；只记录哈希与 revision，不复制依赖源码或
用户数据。

## 3. 自动更新

启用经过认证的自动更新后，Sparkle 会从 GitHub Releases 请求 XML Appcast 与更新
压缩包。Dev Island 关闭了 Sparkle 系统画像；GitHub 仍可能依据其隐私政策接收 IP、
时间与 User-Agent 等普通网络元数据。用户可在设置中关闭自动检查。

源码仓库还包含一条仅供维护者运行的一次性旧版→新版更新门禁。合成 App、公开 fixture key
和仅回环 server 全部位于 macOS 当前用户的随机 `0700` 临时目录；pinned Sparkle 源码构建与
更新运行分别收到两个私有 HOME，运行时设置 `__CFPREFERENCES_AVOID_DAEMON=1`，固定哈希
源码覆盖层把 helper cache 与 launch-job 状态路由到该临时根。门禁不会读取或写入维护者真实
偏好/cache，不调用 `defaults write/delete`，不触碰已安装 Dev Island，也不接收生产更新私钥。
退出时删除完整临时根；失败清理只允许向可执行文件完整路径仍位于本次随机根下的 helper 进程
发送信号。

## 4. 通知、日志与诊断

获得通知权限后，macOS 通知中心会接收显示通知所需的 Agent 名称、任务标题、阶段或
等待消息；开启状态音时还会收到一段 App 内置短音效的文件名。是否在锁屏显示由系统
设置决定。状态音可以在设置中关闭，并遵循 macOS 的专注模式与通知声音策略。

Dev Island 使用 Apple 统一日志记录运行事件，并设计为不写入 API Key 或原始响应
正文。**Copy / Save Diagnostics** 只在用户主动点击时，把同一份版本、系统、架构、
Manus 连接状态、本地 Agent 监听器健康状态和聚合数量放到剪贴板，或保存到用户选择的
本机文本文件；不包含 Key、Prompt、标题、任务/会话 ID、URL 或路径。文件以仅当前
用户可读写的权限创建，并由用户决定保留或删除。诊断会说明上个进程是否记录了正常
退出，但不会把强制退出、断电、系统重启或真实崩溃中的任何一种擅自判断为具体原因，
也不会上传或自动发送。诊断准备与用户确认后的本机文件事务会进入本机后台 worker，文件
同步不会阻塞界面；离开 Support 页面后，晚到结果不会再更新旧界面，但已在用户确认位置
开始的原子写入可以安全完成。该调度边界不会新增任何数据或目的地。

仓库维护者使用的 Pull Request CI 另有一份独立的脱敏工程诊断。它只包含仓库/运行标识、
固定构建门禁结果、测试聚合数量、已清理的失败测试名、已完成的安全子门禁，以及临时日志
是否可安全读取的低基数状态；不会从用户安装的 App 收集数据。原始日志、任意断言/错误
正文、环境变量、凭据和 Dev Island 用户数据均不进入诊断。摘要会显示在 GitHub Job 中；
只有运行失败时，两个脱敏文件组成的 artifact 才由 GitHub 保留 14 天。链接、不安全、
超限或读取中变化的输入会被省略，而不会被复制。

仓库还包含一套独立的、仅由维护者主动运行的 Codex 真实审批证据包装器。维护者必须显式
选择一个本机 Codex session、Dev Island 历史数据库、proof 文件、被测 App 与 CLI，以及三张
已经人工复核的状态截图。包装器通过有界 no-follow descriptor 读取原始 session 与数据库，
但绝不复制两者；私有 T7 Shield `0700` 证据包只保留固定低基数状态 transcript、一条脱敏的
Completed 任务记录、产物与可执行文件哈希、精确 proof、三张截图，以及对
`waiting,allow_once,running,completed` 视觉顺序的显式人工确认。符号链接、多硬链接、不安全权限、
读取中变化、意外 session 事件、版本漂移、无效 App 签名、哈希变化，或缺少 Codex exit-zero / 最终
marker 时都不能生成 `ACCEPTED`。仓库只签入脱敏 receipt，供 CI 与 tag Release 强制验证已记录的
闭环；原始 Codex 消息、reasoning、无关数据库行、本机路径或凭据不会进入仓库。该流程仅用于
维护者 QA，不检查用户已经安装的 App。

仓库另有一套仅供维护者使用的 Codex 拒绝/超时真实决策分类与证据包装器。它只在本机读取维护者
明确选择的一条 Codex session、预期始终不存在的 proof 路径、一条匹配的 Dev Island 历史记录、
被测 App/CLI 与两张人工复核图片，不访问网络。原始 JSONL、SQLite 行、prompt、reasoning、命令
和本机路径均不复制；私有 T7 Shield 包只保留固定 checkpoint、脱敏任务行、哈希、两张 JPEG 与
proof 不存在证明。`explicit_island_deny`、`neutral_timeout_fallback`、`sandbox_rejection` 与
`interrupted_attempt` 四类结果彼此独立；只有在 90 秒原生回退前完成、proof 仍不存在的第一类
可以生成 `ACCEPTED`。解析器绝不执行 session 中记录的 JavaScript。现已有一条解锁状态真实岛内
拒绝通过完整 package gate，仓库仅签入其脱敏 receipt；原始 session、数据库、命令、proof 路径和
本机路径仍不进入仓库。该维护者 QA 流程不检查用户安装的 App，也不改变 macOS 辅助功能或外观设置；
receipt 也不会把单次 dirty-worktree QA 会话变成 clean 商业 Release 声明。

Security gate 还会在本机对有界 UTF-8 的 App、QA、CI、Release 与 workflow 源码进行静态扫描，
拒绝可能修改维护者 macOS 登录会话偏好、终止无关进程、改变 launch-service 状态或调用
AppleScript 的命令/API。扫描不执行源码、不访问网络，也不检查已安装 App 或用户内容。它是仓库
防护而不是外部自动化或人工操作的运行时沙箱，因此系统开关 QA 仍只允许在隔离 macOS 测试账户
或 VM 中进行。

已签名 App 还会在 `Contents/Resources/Legal` 中带上本说明与当前使用条款的精确只读副本。
在设置中打开 **隐私说明** 或 **使用条款** 时，只会读取用户选择的双语 App 资源；不会创建
偏好、缓存、历史、分析事件或同意记录，也不会发起网络请求。每份副本上限为 512 KiB，签名前
会校验预期标题、中英文审阅日期一致、UTF-8 结构以及与仓库原文逐字节相同。除两个已审阅支持
邮箱与精确 `https://devisland.app` origin 外，其他链接只保留可读文字。这些随 App 交付的副本
仍是待 owner/legal 审阅的草案，不构成用户同意或已经发布的证明。

维护者 CI 与 tag Release 门禁还会静态解析仓库内的 workflow YAML 和 Bash `run` 步骤。
有界结构预检会在 safe-load 前拒绝歧义重复键或多文档 YAML。完整 GitHub expression 会先
替换为固定的惰性占位符，再交给 `/bin/bash -n`；workflow/job/step 的有效 shell 也会按精确
审核过的 Bash 集合检查。步骤不会被执行，也不会读取或保留 Secret、已安装 App 数据或用户
内容。攻击夹具仅存在于本地私有临时目录，并在门禁退出时删除。

在发布门禁执行其他项目工具前，还会从有界、校验过的 descriptor 读取并静态解析全部仓库 Bash、Ruby 与 Swift 脚本，
通过 stdin 交给 `bash -n`、`ruby -c` 或 `swiftc -parse`。脚本不会执行，不访问网络或
已安装 App 数据，也不保留 parser 输出或源码内容。

维护者构建 App 时还会在本机检查刚生成的可执行文件中六个固定构建风味标记：三个
Performance QA 字面量与三个 DEBUG-only 字面量。检查只把 `/usr/bin/strings` 的输出流入
精确固定字符串比较；原始 strings 与匹配上下文不会被记录或保留。它不检查用户安装的 App，
也不读取任务、会话、文件路径、Keychain、Agent 配置、凭据或其他用户数据，并且不访问网络。

PR CI 还会仅启动刚构建的、编译期 hermetic Performance QA App，并使用私有临时
`CFFIXED_USER_HOME`。该夹具关闭 SQLite、Keychain、本地 Hook、Manus、通知、Welcome 与更新
网络。维护者工具只在 runner 临时文件中保留 Bundle/版本/哈希和机器信息、显示会话分类、
readiness、八个有界 CPU/RSS 样本、精确夹具 PID 与正常退出状态；不读取已安装 App、Agent
配置、凭据或崩溃报告。锁屏或 unknown 显示状态只允许用于本次启动存活 smoke，不能支持产品
或 Release 性能结论。

另一条仅供维护者运行的 `production-launch-smoke` 会冻结并启动真正的
`app.devisland.Island` Bundle；它必须同时收到精确参数和环境值，普通 Finder 或
LaunchServices 启动不会进入该模式。真实 shipping 岛与状态栏会完成渲染，但 TaskStore 保持惰性，
LaunchHealth、通知、Welcome、Sparkle、SQLite、Keychain、本地 Hook 与 Manus 均不启动。
readiness 及八个有界 CPU/RSS 样本中的每一秒只检查精确 PID 是否出现网络 socket，以及私有 HOME
是否创建 SQLite 或 Hook 授权文件；不收集 socket 目的地或 payload。PR CI 在 Production 构建后
运行它，tag Release 则在 App 公证后、DMG 打包前重复运行。这些样本只构成产物存活/隔离门禁，
不能作为产品性能、丝滑度、首帧、能耗或 Release 宣传证据。

这三份临时证据会在启动前一次性声明为当前用户 `0600` 单硬链接 descriptor。预存在文件、
符号链接、并发抢占、不安全父目录或后续 device/inode 替换均失败关闭。统计只读取与 CSV writer
身份重新绑定的单次有界 `NOFOLLOW`/`NONBLOCK` descriptor 快照；readiness 也只解析与 App-log
writer 身份绑定的同类私有快照。FIFO 替换、malformed/重复 marker、反向或超窗 uptime 均失败
关闭；两者都不会反复重开公共证据路径。

被选择的 Performance QA 或 Production App 同样只作为维护者的有界输入。工具会通过 descriptor 对主 executable 与
`Info.plist` 做稳定哈希并校验 strict deep 签名，再把完整 Bundle 复制到 sampler 随机私有的
`0700` 目录；只有该私有 App 会继续接受依赖/标记检查并被启动。来源与副本会在启动前及正常
退出后重新绑定身份，来源被替换时不发布 summary。成功 summary 只保留相等的来源/私有
executable 哈希与固定 `isolated_app_snapshot=true` 状态；sampler 退出时删除临时副本，且整个
过程不读取用户已安装 App 或用户内容。

在 Pull Request CI 中，真正用于验收的已验证 summary 会从 sampler 的有界 stdout 一次性捕获
到 shell 变量；存活状态和哈希断言只读取该进程内值，producer 退出后不再重开 runner 临时
summary 路径。因此残留 QA descendant 即使替换公开文件也不能改变验收。该变量不会写入
GitHub output、环境、cache、诊断或 artifact，并随 step 结束销毁；内容仍只有前述夹具、机器、
显示会话与聚合样本字段。

## 5. 本地保留与删除

任务与进度历史在本机 SQLite 数据库中采用自动有限保留：Dev Island 最多保留最新
5,000 个任务与 20,000 条进度。数据库每次打开及每次写入后都会进行确定性修剪，
任务被淘汰时也会删除对应的孤立进度。用户仍可通过 **设置 → Support → Clear
History** 或手动删除数据库来提前清除。新记录的身份或文本字段超过文档字节上限时，
整项或整批事务会被拒绝；数据库打开时会一次性清理类型错误或超大的旧行，历史查询在
文字进入 App 内存前再次校验类型与字节，即使运行期间有其他进程修改数据库也不会把超大
内容带入界面。正常事件写入只做逐项验证，不重复全表内容扫描。App 自有的最终数据库
目录仅允许当前用户访问（`0700`），主数据库和已有的 SQLite
WAL/SHM/journal 文件同样仅允许当前用户访问（`0600`）。在 SQLite 访问前，Dev Island
会拒绝链接、非普通文件、错误 owner 和多硬链接数据库，以 no-follow descriptor 同时锚定
最终目录与主库，并通过相对目录且不跟随链接的操作处理已有 sidecar；两个 descriptor 会与
SQLite Connection 保持同寿命，并在每次历史读取、写入、保留期修剪和 Clear History 事务
前后复验目录、主库与 sidecar。提交前发现漂移会回滚写入，读取后发现漂移则不会返回已经
物化的历史页。首次运行期边界失败会持续关闭当前历史存储实例，让后续调用继续显示不可用，
而不是误报为空历史或清除成功；本地 Agent 监听和当前内存会话仍会继续。私有的
**View History** 页面只读取最近 200
条任务快照，并支持按任务标题或 Agent 名称在本机搜索；这些记录不会被恢复进实时
灵动岛，也不会触发通知。清除入口会在同一个事务中清空两张历史表，且不会让当前
仍在运行或等待的会话从灵动岛消失。只删除 App 本体不一定会删除 Application
Support、偏好或钥匙串项目。卸载前可先断开 Manus，让 App 删除其保存的 API Key。

## 6. 官网、支持与用户选择

官网由第三方基础设施托管。Dev Island 不主动安装广告或产品分析追踪器，但托管商
可能处理普通服务器日志。用户发送支持邮件时，邮件服务商会处理用户主动提供的地址、
邮件头和正文；请勿发送 API Key、私密 Prompt 或其他秘密。

维护者不出售个人信息，也不将 App 数据用于跨场景行为广告。用户可以选择启用哪些
连接器、关闭通知或自动更新、断开 Manus、移除 Hook，并自行决定是否分享诊断。

## 7. 变更与联系

新增数据流必须先更新本说明再随功能发布。问题可联系
[alsoaxu@gmail.com](mailto:alsoaxu@gmail.com) 或
[puzhen913@gmail.com](mailto:puzhen913@gmail.com)。
