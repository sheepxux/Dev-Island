#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C
umask 077

fail() {
  echo "error: $1" >&2
  exit 1
}

VALIDATOR="scripts/qa/validate-codex-live-approval-evidence.rb"
PACKAGER="scripts/qa/package-codex-live-approval-evidence.rb"
WRAPPER="scripts/qa/run-codex-live-approval-evidence.sh"
RECEIPT="docs/CODEX_LIVE_APPROVAL_RECEIPT.txt"

for file in "$VALIDATOR" "$PACKAGER" "$WRAPPER" "$RECEIPT"; do
  test -s "$file" || fail "Codex live-approval evidence artifact is missing: $file"
done
test -x "$VALIDATOR" && test -x "$PACKAGER" && test -x "$WRAPPER" \
  || fail "Codex live-approval evidence scripts must be executable"
ruby -c "$VALIDATOR" >/dev/null
ruby -c "$PACKAGER" >/dev/null
bash -n "$WRAPPER"

for invariant in \
  'File::NOFOLLOW' \
  'must have exactly one hard link' \
  'waiting,allow_once,running,completed' \
  'require_escalated' \
  'APPROVAL_ROUND_TRIP_COMPLETE' \
  'Dev Island history database changed during evidence extraction' \
  'Dev Island history database has a live sidecar' \
  'operator_confirmed' \
  'SHA256SUMS' \
  'PUBLIC_RECEIPT.txt'; do
  rg -Fq "$invariant" "$VALIDATOR" "$PACKAGER" "$WRAPPER" \
    || fail "Codex live-approval evidence invariant is missing: $invariant"
done

if rg -n 'File\.(bin)?write\([^\n]*session|cp[^\n]*session|copy[^\n]*session' \
  "$PACKAGER" "$WRAPPER" >/dev/null; then
  fail "raw Codex session content must never be copied into the evidence package"
fi

PRODUCT_VERSION="$(./scripts/release/validate-product-version.rb --version-file VERSION)"
"$VALIDATOR" --receipt "$RECEIPT" --product-version "$PRODUCT_VERSION" >/dev/null \
  || fail "checked-in Codex live-approval receipt was rejected"

TEMP_ROOT="$(mktemp -d -t dev-island-codex-live-evidence)"
case "$TEMP_ROOT" in
  /private/var/folders/*/T/dev-island-codex-live-evidence.*|\
  /var/folders/*/T/dev-island-codex-live-evidence.*|\
  /tmp/dev-island-codex-live-evidence.*) ;;
  *) fail "temporary fixture root escaped the reviewed system location" ;;
esac
trap 'rm -rf "$TEMP_ROOT"' EXIT
chmod 700 "$TEMP_ROOT"

expect_receipt_rejected() {
  local fixture="$1"
  local label="$2"
  if "$VALIDATOR" --receipt "$fixture" --product-version "$PRODUCT_VERSION" >/dev/null 2>&1; then
    fail "Codex receipt validator accepted $label"
  fi
}

cp "$RECEIPT" "$TEMP_ROOT/receipt-safe.txt"
chmod 600 "$TEMP_ROOT/receipt-safe.txt"

ln -s "$TEMP_ROOT/receipt-safe.txt" "$TEMP_ROOT/receipt-symlink.txt"
expect_receipt_rejected "$TEMP_ROOT/receipt-symlink.txt" "a symbolic link"

ln "$TEMP_ROOT/receipt-safe.txt" "$TEMP_ROOT/receipt-hardlink.txt"
expect_receipt_rejected "$TEMP_ROOT/receipt-safe.txt" "a multiply linked file"
rm "$TEMP_ROOT/receipt-hardlink.txt"

cp "$RECEIPT" "$TEMP_ROOT/receipt-writable.txt"
chmod 620 "$TEMP_ROOT/receipt-writable.txt"
expect_receipt_rejected "$TEMP_ROOT/receipt-writable.txt" "a group-writable file"

sed 's/result=accepted/result=rejected/' "$RECEIPT" >"$TEMP_ROOT/receipt-result.txt"
chmod 600 "$TEMP_ROOT/receipt-result.txt"
expect_receipt_rejected "$TEMP_ROOT/receipt-result.txt" "a rejected result"

sed 's/product_version=0\.3\.0/product_version=9.9.9/' "$RECEIPT" \
  >"$TEMP_ROOT/receipt-version.txt"
chmod 600 "$TEMP_ROOT/receipt-version.txt"
expect_receipt_rejected "$TEMP_ROOT/receipt-version.txt" "a version mismatch"

sed 's/app_executable_sha256=[0-9a-f]*/app_executable_sha256=ABCDEF/' "$RECEIPT" \
  >"$TEMP_ROOT/receipt-hash.txt"
chmod 600 "$TEMP_ROOT/receipt-hash.txt"
expect_receipt_rejected "$TEMP_ROOT/receipt-hash.txt" "a malformed binary hash"

sed $'s/$/\r/' "$RECEIPT" >"$TEMP_ROOT/receipt-crlf.txt"
chmod 600 "$TEMP_ROOT/receipt-crlf.txt"
expect_receipt_rejected "$TEMP_ROOT/receipt-crlf.txt" "CRLF line endings"

printf '%s' "$(<"$RECEIPT")" >"$TEMP_ROOT/receipt-no-lf.txt"
chmod 600 "$TEMP_ROOT/receipt-no-lf.txt"
expect_receipt_rejected "$TEMP_ROOT/receipt-no-lf.txt" "a missing final LF"

FIXTURE_REPOSITORY="$TEMP_ROOT/repository"
FIXTURE_WORKSPACE="$TEMP_ROOT/workspace"
FIXTURE_OUTSIDE="$TEMP_ROOT/outside"
FIXTURE_APP="$TEMP_ROOT/Fixture.app"
FIXTURE_CODEX="$TEMP_ROOT/codex"
FIXTURE_SESSION="$TEMP_ROOT/session.jsonl"
FIXTURE_DB="$TEMP_ROOT/tasks.sqlite"
FIXTURE_PROOF="$FIXTURE_OUTSIDE/approval-proof.txt"
FIXTURE_APPROVAL="$TEMP_ROOT/approval.jpeg"
FIXTURE_RUNNING="$TEMP_ROOT/running.jpeg"
FIXTURE_COMPLETED="$TEMP_ROOT/completed.jpeg"
FIXTURE_PACKAGE="$TEMP_ROOT/package"

mkdir -p "$FIXTURE_REPOSITORY" "$FIXTURE_WORKSPACE" "$FIXTURE_OUTSIDE" \
  "$FIXTURE_APP/Contents/MacOS" "$FIXTURE_PACKAGE"
chmod 700 "$FIXTURE_REPOSITORY" "$FIXTURE_WORKSPACE" "$FIXTURE_OUTSIDE" \
  "$FIXTURE_APP" "$FIXTURE_APP/Contents" "$FIXTURE_APP/Contents/MacOS" "$FIXTURE_PACKAGE"
printf '%s\n' "$PRODUCT_VERSION" >"$FIXTURE_REPOSITORY/VERSION"
git -C "$FIXTURE_REPOSITORY" init -q
git -C "$FIXTURE_REPOSITORY" config user.name 'Dev Island CI'
git -C "$FIXTURE_REPOSITORY" config user.email 'ci@devisland.invalid'
git -C "$FIXTURE_REPOSITORY" add VERSION
git -C "$FIXTURE_REPOSITORY" commit -qm 'fixture baseline'

cp /usr/bin/true "$FIXTURE_APP/Contents/MacOS/IslandApp"
chmod 500 "$FIXTURE_APP/Contents/MacOS/IslandApp"
plutil -create xml1 "$FIXTURE_APP/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string app.devisland.Island "$FIXTURE_APP/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string "$PRODUCT_VERSION" "$FIXTURE_APP/Contents/Info.plist"
plutil -insert CFBundleExecutable -string IslandApp "$FIXTURE_APP/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$FIXTURE_APP/Contents/Info.plist"
chmod 400 "$FIXTURE_APP/Contents/Info.plist"
codesign --force --deep --sign - "$FIXTURE_APP" >/dev/null 2>&1

cp /usr/bin/true "$FIXTURE_CODEX"
chmod 500 "$FIXTURE_CODEX"
printf '%s\n' 'dev-island-real-codex-approval' >"$FIXTURE_PROOF"
chmod 600 "$FIXTURE_PROOF"

ruby - "$FIXTURE_APPROVAL" "$FIXTURE_RUNNING" "$FIXTURE_COMPLETED" <<'RUBY'
ARGV.each_with_index do |path, index|
  payload = "\xFF\xD8\xFF".b + ([65 + index].pack("C") * 256) + "\xFF\xD9".b
  File.binwrite(path, payload)
  File.chmod(0o600, path)
end
RUBY

FIXTURE_SESSION_ID="11111111-2222-3333-4444-555555555555"
ruby -r json - "$FIXTURE_SESSION" "$FIXTURE_SESSION_ID" "$FIXTURE_WORKSPACE" "$FIXTURE_PROOF" <<'RUBY'
path, session_id, workspace, proof = ARGV
records = []
records << {
  "timestamp" => "2026-08-30T04:37:24.000Z",
  "ordinal" => 0,
  "type" => "session_meta",
  "payload" => {
    "session_id" => session_id,
    "id" => session_id,
    "timestamp" => "2026-08-30T04:37:23.000Z",
    "cwd" => workspace,
    "originator" => "Codex Desktop",
    "cli_version" => "0.149.0-alpha.4.3",
    "source" => "cli",
    "thread_source" => "user",
  },
}
prompt = "Use the shell to write exactly the single line dev-island-real-codex-approval to #{proof}. This target is intentionally outside the workspace. Request user approval when needed, and wait for the decision. Do not use apply_patch, Python, or another workaround. After the command succeeds, report only APPROVAL_ROUND_TRIP_COMPLETE."
records << {
  "timestamp" => "2026-08-30T04:37:25.000Z",
  "ordinal" => 1,
  "type" => "response_item",
  "payload" => {
    "type" => "message",
    "role" => "user",
    "content" => [{ "type" => "input_text", "text" => prompt }],
  },
}
command = "printf '%s\\n' 'dev-island-real-codex-approval' > '#{proof}'"
arguments = {
  "cmd" => command,
  "workdir" => workspace,
  "yield_time_ms" => 10_000,
  "max_output_tokens" => 1_000,
  "sandbox_permissions" => "require_escalated",
  "justification" => "Allow writing the requested single-line proof file outside the current workspace?",
}
input = "const r = await tools.exec_command(#{JSON.generate(arguments)});\nif (r.output) text(r.output);\n"
records << {
  "timestamp" => "2026-08-30T04:37:30.000Z",
  "ordinal" => 2,
  "type" => "response_item",
  "payload" => {
    "type" => "custom_tool_call",
    "name" => "exec",
    "status" => "completed",
    "call_id" => "permission-call",
    "input" => input,
  },
}
records << {
  "timestamp" => "2026-08-30T04:37:31.000Z",
  "ordinal" => 3,
  "type" => "response_item",
  "payload" => {
    "type" => "custom_tool_call_output",
    "call_id" => "permission-call",
    "output" => "Script running with cell ID 7\nWall time 1.0 seconds\nOutput:\n",
  },
}
records << {
  "timestamp" => "2026-08-30T04:37:32.000Z",
  "ordinal" => 4,
  "type" => "response_item",
  "payload" => {
    "type" => "function_call",
    "name" => "wait",
    "call_id" => "wait-call",
    "arguments" => JSON.generate({ "cell_id" => "7", "yield_time_ms" => 60_000, "max_tokens" => 1_000 }),
  },
}
records << {
  "timestamp" => "2026-08-30T04:38:38.000Z",
  "ordinal" => 5,
  "type" => "response_item",
  "payload" => {
    "type" => "function_call_output",
    "call_id" => "wait-call",
    "output" => "Script completed\nWall time 66.0 seconds\nOutput:\n{\"exit_code\":0,\"wall_time_seconds\":0.01}",
  },
}
records << {
  "timestamp" => "2026-08-30T04:38:40.000Z",
  "ordinal" => 6,
  "type" => "response_item",
  "payload" => {
    "type" => "message",
    "role" => "assistant",
    "phase" => "final_answer",
    "content" => [{ "type" => "output_text", "text" => "APPROVAL_ROUND_TRIP_COMPLETE" }],
  },
}
records << {
  "timestamp" => "2026-08-30T04:38:41.000Z",
  "ordinal" => 7,
  "type" => "event_msg",
  "payload" => { "type" => "task_complete" },
}
File.binwrite(path, records.map { |record| JSON.generate(record) }.join("\n") + "\n")
File.chmod(0o600, path)
RUBY

sqlite3 "$FIXTURE_DB" \
  "CREATE TABLE tasks (source TEXT, id TEXT, status TEXT, created_at REAL, updated_at REAL);" \
  "INSERT INTO tasks VALUES ('codex','$FIXTURE_SESSION_ID','completed',1788064646,1788064721);"
chmod 600 "$FIXTURE_DB"

"$PACKAGER" \
  --repository "$FIXTURE_REPOSITORY" \
  --session-log "$FIXTURE_SESSION" \
  --history-db "$FIXTURE_DB" \
  --proof "$FIXTURE_PROOF" \
  --app "$FIXTURE_APP" \
  --codex-cli "$FIXTURE_CODEX" \
  --approval-screenshot "$FIXTURE_APPROVAL" \
  --running-screenshot "$FIXTURE_RUNNING" \
  --completed-screenshot "$FIXTURE_COMPLETED" \
  --output "$FIXTURE_PACKAGE" \
  --confirm-visual-state-sequence waiting,allow_once,running,completed >/dev/null \
  || fail "valid synthetic Codex approval evidence was rejected by the packager"
"$VALIDATOR" --evidence "$FIXTURE_PACKAGE" --require-accepted \
  --product-version "$PRODUCT_VERSION" >/dev/null \
  || fail "valid synthetic Codex approval package was rejected"

expect_package_rejected() {
  local fixture="$1"
  local label="$2"
  if "$VALIDATOR" --evidence "$fixture" --require-accepted \
    --product-version "$PRODUCT_VERSION" >/dev/null 2>&1; then
    fail "Codex package validator accepted $label"
  fi
}

copy_package() {
  local destination="$1"
  mkdir "$destination"
  chmod 700 "$destination"
  cp "$FIXTURE_PACKAGE"/* "$destination"/
  chmod 400 "$destination"/*
}

LINKED_PACKAGE="$TEMP_ROOT/package-linked"
copy_package "$LINKED_PACKAGE"
chmod 600 "$LINKED_PACKAGE/approval-proof.txt"
rm "$LINKED_PACKAGE/approval-proof.txt"
ln -s "$FIXTURE_PACKAGE/approval-proof.txt" "$LINKED_PACKAGE/approval-proof.txt"
expect_package_rejected "$LINKED_PACKAGE" "a linked proof artifact"

HARDLINK_PACKAGE="$TEMP_ROOT/package-hardlink"
copy_package "$HARDLINK_PACKAGE"
chmod 600 "$HARDLINK_PACKAGE/approval-proof.txt"
ln "$HARDLINK_PACKAGE/approval-proof.txt" "$TEMP_ROOT/proof-hardlink"
expect_package_rejected "$HARDLINK_PACKAGE" "a multiply linked proof artifact"
rm "$TEMP_ROOT/proof-hardlink"

WRITABLE_PACKAGE="$TEMP_ROOT/package-writable"
copy_package "$WRITABLE_PACKAGE"
chmod 620 "$WRITABLE_PACKAGE/transcript.txt"
expect_package_rejected "$WRITABLE_PACKAGE" "a group-writable transcript"

EXTRA_PACKAGE="$TEMP_ROOT/package-extra"
copy_package "$EXTRA_PACKAGE"
printf 'unexpected\n' >"$EXTRA_PACKAGE/EXTRA"
chmod 400 "$EXTRA_PACKAGE/EXTRA"
expect_package_rejected "$EXTRA_PACKAGE" "an unexpected package file"

PROOF_PACKAGE="$TEMP_ROOT/package-proof"
copy_package "$PROOF_PACKAGE"
chmod 600 "$PROOF_PACKAGE/approval-proof.txt"
printf '%s\n' 'forged-proof' >"$PROOF_PACKAGE/approval-proof.txt"
chmod 400 "$PROOF_PACKAGE/approval-proof.txt"
expect_package_rejected "$PROOF_PACKAGE" "a forged proof"

TRANSCRIPT_PACKAGE="$TEMP_ROOT/package-transcript"
copy_package "$TRANSCRIPT_PACKAGE"
chmod 600 "$TRANSCRIPT_PACKAGE/transcript.txt"
sed 's/checkpoint=permission_requested/checkpoint=permission_skipped/' \
  "$FIXTURE_PACKAGE/transcript.txt" >"$TRANSCRIPT_PACKAGE/transcript.txt"
chmod 400 "$TRANSCRIPT_PACKAGE/transcript.txt"
expect_package_rejected "$TRANSCRIPT_PACKAGE" "a forged transcript"

TASK_PACKAGE="$TEMP_ROOT/package-task"
copy_package "$TASK_PACKAGE"
chmod 600 "$TASK_PACKAGE/TASK_RECORD.txt"
sed 's/status=completed/status=running/' "$FIXTURE_PACKAGE/TASK_RECORD.txt" \
  >"$TASK_PACKAGE/TASK_RECORD.txt"
chmod 400 "$TASK_PACKAGE/TASK_RECORD.txt"
expect_package_rejected "$TASK_PACKAGE" "a non-completed task record"

IMAGE_PACKAGE="$TEMP_ROOT/package-image"
copy_package "$IMAGE_PACKAGE"
chmod 600 "$IMAGE_PACKAGE/02-live-codex-running.jpeg"
printf '\001' >>"$IMAGE_PACKAGE/02-live-codex-running.jpeg"
chmod 400 "$IMAGE_PACKAGE/02-live-codex-running.jpeg"
expect_package_rejected "$IMAGE_PACKAGE" "a modified running screenshot"

CHECKSUM_PACKAGE="$TEMP_ROOT/package-checksum"
copy_package "$CHECKSUM_PACKAGE"
chmod 600 "$CHECKSUM_PACKAGE/SHA256SUMS"
sed '1s/^[0-9a-f]/0/' "$FIXTURE_PACKAGE/SHA256SUMS" \
  >"$CHECKSUM_PACKAGE/SHA256SUMS"
chmod 400 "$CHECKSUM_PACKAGE/SHA256SUMS"
expect_package_rejected "$CHECKSUM_PACKAGE" "a modified checksum manifest"

PUBLIC_PACKAGE="$TEMP_ROOT/package-public"
copy_package "$PUBLIC_PACKAGE"
chmod 755 "$PUBLIC_PACKAGE"
expect_package_rejected "$PUBLIC_PACKAGE" "a non-private package directory"

BAD_SESSION="$TEMP_ROOT/session-bad-final.jsonl"
sed 's/APPROVAL_ROUND_TRIP_COMPLETE/APPROVAL_NOT_PROVEN/' "$FIXTURE_SESSION" >"$BAD_SESSION"
chmod 600 "$BAD_SESSION"
BAD_OUTPUT="$TEMP_ROOT/package-bad-session"
mkdir "$BAD_OUTPUT"
chmod 700 "$BAD_OUTPUT"
if "$PACKAGER" \
  --repository "$FIXTURE_REPOSITORY" \
  --session-log "$BAD_SESSION" \
  --history-db "$FIXTURE_DB" \
  --proof "$FIXTURE_PROOF" \
  --app "$FIXTURE_APP" \
  --codex-cli "$FIXTURE_CODEX" \
  --approval-screenshot "$FIXTURE_APPROVAL" \
  --running-screenshot "$FIXTURE_RUNNING" \
  --completed-screenshot "$FIXTURE_COMPLETED" \
  --output "$BAD_OUTPUT" \
  --confirm-visual-state-sequence waiting,allow_once,running,completed >/dev/null 2>&1; then
  fail "Codex packager accepted a session without the approved final result"
fi
test ! -e "$BAD_OUTPUT/ACCEPTED" \
  || fail "rejected Codex session produced an ACCEPTED marker"

LINKED_SESSION="$TEMP_ROOT/session-link.jsonl"
ln -s "$FIXTURE_SESSION" "$LINKED_SESSION"
LINKED_OUTPUT="$TEMP_ROOT/package-linked-session"
mkdir "$LINKED_OUTPUT"
chmod 700 "$LINKED_OUTPUT"
if "$PACKAGER" \
  --repository "$FIXTURE_REPOSITORY" \
  --session-log "$LINKED_SESSION" \
  --history-db "$FIXTURE_DB" \
  --proof "$FIXTURE_PROOF" \
  --app "$FIXTURE_APP" \
  --codex-cli "$FIXTURE_CODEX" \
  --approval-screenshot "$FIXTURE_APPROVAL" \
  --running-screenshot "$FIXTURE_RUNNING" \
  --completed-screenshot "$FIXTURE_COMPLETED" \
  --output "$LINKED_OUTPUT" \
  --confirm-visual-state-sequence waiting,allow_once,running,completed >/dev/null 2>&1; then
  fail "Codex packager accepted a linked session source"
fi
test ! -e "$LINKED_OUTPUT/ACCEPTED" \
  || fail "linked Codex session produced an ACCEPTED marker"

SIDECAR_OUTPUT="$TEMP_ROOT/package-live-sidecar"
mkdir "$SIDECAR_OUTPUT"
chmod 700 "$SIDECAR_OUTPUT"
printf 'uncheckpointed fixture\n' >"$FIXTURE_DB-wal"
chmod 600 "$FIXTURE_DB-wal"
if "$PACKAGER" \
  --repository "$FIXTURE_REPOSITORY" \
  --session-log "$FIXTURE_SESSION" \
  --history-db "$FIXTURE_DB" \
  --proof "$FIXTURE_PROOF" \
  --app "$FIXTURE_APP" \
  --codex-cli "$FIXTURE_CODEX" \
  --approval-screenshot "$FIXTURE_APPROVAL" \
  --running-screenshot "$FIXTURE_RUNNING" \
  --completed-screenshot "$FIXTURE_COMPLETED" \
  --output "$SIDECAR_OUTPUT" \
  --confirm-visual-state-sequence waiting,allow_once,running,completed >/dev/null 2>&1; then
  fail "Codex packager accepted an uncheckpointed history database"
fi
test ! -e "$SIDECAR_OUTPUT/ACCEPTED" \
  || fail "live history sidecar produced an ACCEPTED marker"
rm "$FIXTURE_DB-wal"

echo "Codex live-approval evidence package and attack fixtures: PASS"
