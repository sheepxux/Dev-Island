# Windows capture preflight — 2026-10-28

## Follow-up review — 2026-10-30

Six Node tests now pass, including dynamic map-key redaction and oversized stdin.
Unknown object keys become indexed key-length markers; only reviewed protocol
field names remain visible. Shapes sample at most 128 fields per object, three
array items and 32 nesting levels. This intentionally hides unreviewed schema
extensions until their field names have been inspected locally.

CLI stdin is limited to an 8 MiB buffered copy. Above that limit, the original
payload is discarded and only a capture_truncated/observed_bytes/limit_bytes
metadata record is stored, while input continues draining until EOF or the
existing deadline. Its timeline bytes describe that metadata, not the discarded
original. The imported plugin API does not apply this stdin buffering limit.

**Filesystem permissions:** local-only storage is not an owner-only Windows
access guarantee. Node's mode 0600 does not configure Windows ACLs; these files
inherit the destination directory's ACL. This helper does not change existing
directory ACLs. Use a directory restricted appropriately for the local machine
and never share raw files. Here, "private" capture-root names describe intended
use, not a verified ACL property or encryption.

permission.asked is now a reviewed enum, based on real OpenCode evidence in
PR #32. Previously collected evidence was manually checked before publication;
it is not claimed to have been captured using these later changes.

## Original preflight

This is a capture-tool validation report, **not real CLI event evidence**.
No connector is promoted from Preview by these results.

## Environment and branch

- Windows NT 10.0.26300.0; Node 22.14.0; npm 10.9.2.
- Based on main `8601d26`; capture helper originated in PR #26.
- Reviewed `s/v1-backend` (`f87f3b5`); its old backend/UI commits are not needed
  for standalone capture and were not merged.
- None of the five CLI commands were initially on PATH. Logged-in interactive
  sessions and native approval timing have not been verified.

## Capture helper findings and fixes

1. Enum **keys** alone did not prevent short prompts, paths or reasons from
   entering the timeline. Values now need an explicit allowlist too. Unknown
   enum values become string-length markers; raw local files preserve them for
   private review before extending the list.
2. Numeric payload values now become `<number>`; booleans and null remain
   visible, including Copilot's `recoverable` flag.
3. Same-millisecond events previously overwrote a raw file. UUID filenames and
   exclusive creation preserve each event and keep event labels out of paths.
4. Agent directory names are restricted to the five supported agents and
   `unknown`. Unknown event labels are redacted in the timeline.
5. `DEVISLAND_CAPTURE_ROOT` selects a local capture directory for isolated
   tests. Default remains `~/devisland-capture`. Never commit the raw directory.

## Windows checks

`node --test scripts/collab/capture-hook.test.mjs`: 4 tests passed.

- Valid JSON: no stdout/stderr, exit 0, raw retained, free text redacted,
  session hashes stable, booleans retained, UTF-8 byte count recorded.
- Invalid JSON and unknown event labels: no original text in timeline.
- Invalid agent / destination which is a regular file: silent exit 0.
- ES module import: no side effects; 20 same-millisecond plugin records
  retain 20 raw files; input/output objects are unchanged.

`node --check scripts/collab/capture-hook.mjs` and `git diff --check` passed.
The repository's full syntax validator needs Unix permissions, Ruby and Swift;
it was not run on this Windows host. macOS App behavior was not tested.

These are synthetic regression tests, never vendor timelines. Shape output
samples at most three array elements and retains object keys: inspect dynamic
map keys locally for private content before sharing any timeline. Hashes are
correlation aids, not encryption or a guarantee against guessing known IDs.

## Package preflight

The public npm registry returned the pinned versions for Gemini 0.57.0,
Qwen 0.22.0, Copilot 1.0.80 and Kimi 0.38.0. Node on this host is below the
plan's Kimi requirement of 22.19; upgrade/use a separate compatible runtime
before Kimi capture.

`opencode@1.18.23` returned 404. The correct npm package is
`opencode-ai@1.18.23` (version confirmed). See the
[official OpenCode installation documentation](https://docs.opencode.ai/docs/).

An isolated install of the four non-Kimi packages failed in OpenCode's
postinstall because its native Windows package was unavailable to the loader.
Installing Copilot alone succeeded (three packages), but launching its binary
failed during package extraction with `EPERM` on a rename in the sandbox cache.
No authenticated Copilot session or hook event was obtained. These are local
environment blockers, not evidence of a vendor hook-schema defect.

## Remaining real-session work

For each CLI, record the actual installed version and login method (never
credentials), then execute all seven scenarios in PR #26. Answer every
connector-specific question using observations. Keep approvals in the native
CLI, restore the original configuration, and verify a clean post-removal run.
Create one `REPORT.md` plus sanitized `timeline.jsonl` per CLI and one PR per
CLI. No fabricated event timeline is included here.
