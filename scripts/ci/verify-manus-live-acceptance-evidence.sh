#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$1" >&2
  exit 1
}

VALIDATOR="scripts/qa/validate-manus-live-acceptance-transcript.rb"
WRAPPER="scripts/qa/run-manus-live-acceptance.sh"
BUILD_INPUT_GENERATOR="scripts/qa/generate-manus-live-build-inputs.rb"
test -x "$VALIDATOR" && test -x "$WRAPPER" && test -x "$BUILD_INPUT_GENERATOR" \
  || fail "Manus live-acceptance evidence validator or wrapper is missing"
ruby -c "$VALIDATOR" >/dev/null || fail "Manus transcript validator is invalid Ruby"
ruby -c "$BUILD_INPUT_GENERATOR" >/dev/null \
  || fail "Manus build-input generator is invalid Ruby"
bash -n "$WRAPPER" || fail "Manus live-acceptance wrapper is invalid Bash"

for invariant in \
  'File::NOFOLLOW' \
  'stat\.nlink == 1' \
  'Process\.uid' \
  'MAXIMUM_BYTES = 64 \* 1_024' \
  'signed registration probe must precede registration acceptance' \
  'accepted transcript must persist before registration' \
  'accepted transcript must clear journal after deletion' \
  '--require-accepted rejects recovery transcripts' \
  'Manus v2 live acceptance recovery' \
  'accepted transcript does not contain the exact required checkpoint set'; do
  rg -q -- "$invariant" "$VALIDATOR" \
    || fail "Manus transcript validator invariant is missing: $invariant"
done
for invariant in \
  'LOCAL_SOURCE_ROOTS' \
  'File::NOFOLLOW' \
  'local source tree contains a non-Swift file' \
  'dependency checkout HEAD differs from Package.resolved' \
  'status.*--porcelain=v1' \
  'dependency checkout contains ignored local files' \
  'dependency checkout contains a Git submodule' \
  'SwiftPM workspace dependency set does not match Package.resolved'; do
  rg -q "$invariant" "$BUILD_INPUT_GENERATOR" \
    || fail "Manus build-input closure invariant is missing: $invariant"
done
for invariant in \
  '/Volumes/T7 Shield' \
  'umask 077' \
  '/usr/bin/env -i' \
  '--only-use-versions-from-resolved-file' \
  'BUILD_INPUTS_BEFORE_BUILD.json' \
  'TOOLCHAIN_BEFORE_BUILD.txt' \
  'generate-manus-live-build-inputs.rb' \
  '--require-accepted' \
  'TRANSCRIPT_REMOVED' \
  'handle_build_signal' \
  'record_live_signal' \
  'LIVE_RECOVERY_JOURNAL_RESULT' \
  'Private recovery journal (excluded from evidence)' \
  'manus-live-acceptance-recover' \
  '--journal "$LIVE_JOURNAL_PATH"' \
  '--recover ABSOLUTE_PRIVATE_JOURNAL' \
  '"$LIVE_RECOVERY_JOURNAL_RESULT" == "cleared"' \
  'ACCEPTED'; do
  rg -Fq -- "$invariant" "$WRAPPER" \
    || fail "Manus live-acceptance evidence invariant is missing: $invariant"
done
if rg -n 'MANUS_API_KEY|ProcessInfo\.processInfo\.environment' "$WRAPPER"; then
  fail "Manus evidence wrapper must never read a credential from the environment"
fi

TEMP_ROOT="$(mktemp -d -t dev-island-manus-live-evidence)"
cleanup() {
  [[ "$TEMP_ROOT" == /private/var/folders/*/T/dev-island-manus-live-evidence.* \
     || "$TEMP_ROOT" == /var/folders/*/T/dev-island-manus-live-evidence.* \
     || "$TEMP_ROOT" == /tmp/dev-island-manus-live-evidence.* ]] \
    && rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT
chmod 700 "$TEMP_ROOT"

BUILD_REPOSITORY="$TEMP_ROOT/build-input-repository"
BUILD_SCRATCH="$TEMP_ROOT/build-input-scratch"
BUILD_CHECKOUT="$BUILD_SCRATCH/checkouts/fixture-dep"
mkdir -p \
  "$BUILD_REPOSITORY/IslandCore/Sources/IslandCore" \
  "$BUILD_REPOSITORY/IslandCoreCLI/Sources/IslandCoreCLI" \
  "$BUILD_REPOSITORY/scripts/qa" \
  "$BUILD_REPOSITORY/scripts/release" \
  "$BUILD_CHECKOUT/Sources/FixtureDep"
cp "$VALIDATOR" "$BUILD_REPOSITORY/$VALIDATOR"
cp "$WRAPPER" "$BUILD_REPOSITORY/$WRAPPER"
cp "$BUILD_INPUT_GENERATOR" "$BUILD_REPOSITORY/$BUILD_INPUT_GENERATOR"
cp scripts/release/validate-product-version.rb \
  "$BUILD_REPOSITORY/scripts/release/validate-product-version.rb"
printf '0.3.0\n' >"$BUILD_REPOSITORY/VERSION"
printf '%s\n' \
  '// swift-tools-version: 5.10' \
  'import PackageDescription' \
  'let package = Package(name: "BuildInputFixture")' \
  >"$BUILD_REPOSITORY/Package.swift"
printf 'public let coreFixture = true\n' \
  >"$BUILD_REPOSITORY/IslandCore/Sources/IslandCore/Core.swift"
printf 'print("fixture")\n' \
  >"$BUILD_REPOSITORY/IslandCoreCLI/Sources/IslandCoreCLI/main.swift"

printf 'ignored.swift\n' >"$BUILD_CHECKOUT/.gitignore"
printf 'public let fixtureDependency = true\n' \
  >"$BUILD_CHECKOUT/Sources/FixtureDep/Fixture.swift"
git -C "$BUILD_CHECKOUT" init -q
git -C "$BUILD_CHECKOUT" config user.name "Dev Island Fixture"
git -C "$BUILD_CHECKOUT" config user.email "fixture@devisland.invalid"
git -C "$BUILD_CHECKOUT" add .gitignore Sources
git -C "$BUILD_CHECKOUT" commit -q -m "fixture dependency"
BUILD_REVISION="$(git -C "$BUILD_CHECKOUT" rev-parse HEAD)"

ruby -r json - "$BUILD_REPOSITORY/Package.resolved" "$BUILD_SCRATCH/workspace-state.json" "$BUILD_REVISION" <<'RUBY'
resolved_path, workspace_path, revision = ARGV
resolved = {
  "originHash" => "fixture",
  "pins" => [{
    "identity" => "fixture-dep",
    "kind" => "remoteSourceControl",
    "location" => "https://example.invalid/fixture-dep.git",
    "state" => {"revision" => revision, "version" => "1.0.0"},
  }],
  "version" => 3,
}
workspace = {
  "object" => {
    "artifacts" => [],
    "dependencies" => [{
      "basedOn" => nil,
      "packageRef" => {
        "identity" => "fixture-dep",
        "kind" => "remoteSourceControl",
        "location" => "https://example.invalid/fixture-dep.git",
        "name" => "fixture-dep",
      },
      "state" => {
        "checkoutState" => {"revision" => revision, "version" => "1.0.0"},
        "name" => "sourceControlCheckout",
      },
      "subpath" => "fixture-dep",
    }],
    "prebuilts" => [],
  },
  "version" => 6,
}
File.binwrite(resolved_path, JSON.pretty_generate(resolved) + "\n")
File.binwrite(workspace_path, JSON.pretty_generate(workspace) + "\n")
RUBY

generate_build_inputs() {
  "$BUILD_INPUT_GENERATOR" \
    --repository "$BUILD_REPOSITORY" \
    --scratch "$BUILD_SCRATCH"
}

expect_build_inputs_rejected() {
  local label="$1"
  if generate_build_inputs >/dev/null 2>&1; then
    fail "Manus build-input generator accepted $label"
  fi
}

SAFE_BUILD_INPUTS="$TEMP_ROOT/safe-build-inputs.json"
generate_build_inputs >"$SAFE_BUILD_INPUTS" \
  || fail "safe Manus build-input closure fixture was rejected"
ruby -r json - "$SAFE_BUILD_INPUTS" <<'RUBY'
manifest = JSON.parse(File.binread(ARGV.fetch(0)))
abort "build-input schema mismatch" unless manifest["schema"] == "dev-island-manus-live-build-inputs-v1"
totals = manifest.fetch("totals")
abort "local build-input coverage mismatch" unless totals["localInputFiles"] == 9
abort "dependency build-input coverage mismatch" unless totals["dependencyCheckouts"] == 1
RUBY

printf 'public let newlyDiscoveredInput = true\n' \
  >"$BUILD_REPOSITORY/IslandCoreCLI/Sources/IslandCoreCLI/NewInput.swift"
NEW_BUILD_INPUTS="$TEMP_ROOT/new-build-inputs.json"
generate_build_inputs >"$NEW_BUILD_INPUTS" \
  || fail "new local Swift build input was not discoverable"
cmp -s "$SAFE_BUILD_INPUTS" "$NEW_BUILD_INPUTS" \
  && fail "new local Swift build input did not change the closure manifest"
ruby -r json -e 'abort unless JSON.parse(File.binread(ARGV.fetch(0))).dig("totals", "localInputFiles") == 10' \
  "$NEW_BUILD_INPUTS"
rm "$BUILD_REPOSITORY/IslandCoreCLI/Sources/IslandCoreCLI/NewInput.swift"

ln -s main.swift "$BUILD_REPOSITORY/IslandCoreCLI/Sources/IslandCoreCLI/Linked.swift"
expect_build_inputs_rejected "a linked local Swift source"
rm "$BUILD_REPOSITORY/IslandCoreCLI/Sources/IslandCoreCLI/Linked.swift"

chmod 666 "$BUILD_REPOSITORY/IslandCore/Sources/IslandCore/Core.swift"
expect_build_inputs_rejected "a group-writable local Swift source"
chmod 644 "$BUILD_REPOSITORY/IslandCore/Sources/IslandCore/Core.swift"

printf 'not a compiler input\n' \
  >"$BUILD_REPOSITORY/IslandCore/Sources/IslandCore/notes.txt"
expect_build_inputs_rejected "an unclassified local target file"
rm "$BUILD_REPOSITORY/IslandCore/Sources/IslandCore/notes.txt"

printf 'public let fixtureDependency = false\n' \
  >"$BUILD_CHECKOUT/Sources/FixtureDep/Fixture.swift"
expect_build_inputs_rejected "a dirty dependency checkout"
git -C "$BUILD_CHECKOUT" show HEAD:Sources/FixtureDep/Fixture.swift \
  >"$BUILD_CHECKOUT/Sources/FixtureDep/Fixture.swift"

printf 'ignored build input\n' >"$BUILD_CHECKOUT/ignored.swift"
expect_build_inputs_rejected "an ignored dependency-local file"
rm "$BUILD_CHECKOUT/ignored.swift"

cp "$BUILD_SCRATCH/workspace-state.json" "$TEMP_ROOT/workspace-state.safe.json"
ruby -r json -e '
path = ARGV.fetch(0)
document = JSON.parse(File.binread(path))
document.dig("object", "dependencies", 0, "state", "checkoutState")["revision"] = "0" * 40
File.binwrite(path, JSON.pretty_generate(document) + "\n")
' "$BUILD_SCRATCH/workspace-state.json"
expect_build_inputs_rejected "a checkout revision that differs from Package.resolved"
mv "$TEMP_ROOT/workspace-state.safe.json" "$BUILD_SCRATCH/workspace-state.json"

mv "$BUILD_REPOSITORY/Package.resolved" "$TEMP_ROOT/Package.resolved.safe"
ln -s "$TEMP_ROOT/Package.resolved.safe" "$BUILD_REPOSITORY/Package.resolved"
expect_build_inputs_rejected "a linked Package.resolved"
rm "$BUILD_REPOSITORY/Package.resolved"
mv "$TEMP_ROOT/Package.resolved.safe" "$BUILD_REPOSITORY/Package.resolved"

mv "$BUILD_SCRATCH/workspace-state.json" "$TEMP_ROOT/workspace-state.safe.json"
ln -s "$TEMP_ROOT/workspace-state.safe.json" "$BUILD_SCRATCH/workspace-state.json"
expect_build_inputs_rejected "a linked SwiftPM workspace state"
rm "$BUILD_SCRATCH/workspace-state.json"
mv "$TEMP_ROOT/workspace-state.safe.json" "$BUILD_SCRATCH/workspace-state.json"

PREAMBLE=(
  '[CLI] Manus v2 live acceptance'
  '[CLI] This creates a temporary public tunnel and webhook, then removes both.'
  '[CLI] During the run, create one task that finishes and one task that pauses for input.'
  '[CLI] Provider identifiers, callback addresses, payload text and raw errors are never printed.'
)
ACCEPTED="$TEMP_ROOT/accepted.txt"
printf '%s\n' \
  "${PREAMBLE[@]}" \
  '[CLI] checkpoint=trust_anchor_validated' \
  '[CLI] checkpoint=server_started' \
  '[CLI] checkpoint=tunnel_started' \
  '[CLI] checkpoint=recovery_journal_persisted' \
  '[CLI] checkpoint=registration_started' \
  '[CLI] checkpoint=signed_registration_probe' \
  '[CLI] checkpoint=registration_accepted' \
  '[CLI] checkpoint=task_created' \
  '[CLI] checkpoint=task_stopped_ask' \
  '[CLI] checkpoint=task_stopped_finish' \
  '[CLI] checkpoint=webhook_deleted' \
  '[CLI] checkpoint=recovery_journal_cleared' \
  '[CLI] checkpoint=transports_stopped' \
  '[CLI] result=accepted' >"$ACCEPTED"
chmod 600 "$ACCEPTED"
"$VALIDATOR" --transcript "$ACCEPTED" --require-accepted >/dev/null \
  || fail "valid accepted Manus transcript was rejected"

FAILED="$TEMP_ROOT/failed.txt"
printf '%s\n' \
  "${PREAMBLE[@]}" \
  '[CLI] checkpoint=transports_stopped' \
  '[CLI] result=failed stage=trust_anchor' >"$FAILED"
chmod 600 "$FAILED"
"$VALIDATOR" --transcript "$FAILED" >/dev/null \
  || fail "allowlisted failed Manus transcript was rejected"
if "$VALIDATOR" --transcript "$FAILED" --require-accepted >/dev/null 2>&1; then
  fail "failed Manus transcript was accepted as live evidence"
fi

expect_rejected() {
  local fixture="$1"
  local label="$2"
  if "$VALIDATOR" --transcript "$fixture" >/dev/null 2>&1; then
    fail "Manus transcript validator accepted $label"
  fi
}

RECOVERY_PREAMBLE=(
  '[CLI] Manus v2 live acceptance recovery'
  '[CLI] This removes only a webhook proven by one explicit private journal.'
  '[CLI] Provider identifiers, callback addresses and raw errors are never printed.'
)
RECOVERED_BOUND="$TEMP_ROOT/recovered-bound.txt"
printf '%s\n' \
  "${RECOVERY_PREAMBLE[@]}" \
  '[CLI] checkpoint=recovery_journal_validated' \
  '[CLI] checkpoint=webhook_deleted' \
  '[CLI] checkpoint=recovery_journal_cleared' \
  '[CLI] result=recovered' >"$RECOVERED_BOUND"
chmod 600 "$RECOVERED_BOUND"
"$VALIDATOR" --transcript "$RECOVERED_BOUND" >/dev/null \
  || fail "valid bound-journal recovery transcript was rejected"
if "$VALIDATOR" --transcript "$RECOVERED_BOUND" --require-accepted >/dev/null 2>&1; then
  fail "recovery transcript was accepted as live-account evidence"
fi

RECOVERED_DISCOVERED="$TEMP_ROOT/recovered-discovered.txt"
printf '%s\n' \
  "${RECOVERY_PREAMBLE[@]}" \
  '[CLI] checkpoint=recovery_journal_validated' \
  '[CLI] checkpoint=recovery_inventory_checked' \
  '[CLI] checkpoint=recovery_webhook_bound' \
  '[CLI] checkpoint=webhook_deleted' \
  '[CLI] checkpoint=recovery_journal_cleared' \
  '[CLI] result=recovered' >"$RECOVERED_DISCOVERED"
chmod 600 "$RECOVERED_DISCOVERED"
"$VALIDATOR" --transcript "$RECOVERED_DISCOVERED" >/dev/null \
  || fail "valid discovered-journal recovery transcript was rejected"

RECOVERY_MANUAL="$TEMP_ROOT/recovery-manual.txt"
printf '%s\n' \
  "${RECOVERY_PREAMBLE[@]}" \
  '[CLI] checkpoint=recovery_journal_validated' \
  '[CLI] checkpoint=recovery_inventory_checked' \
  '[CLI] checkpoint=manual_webhook_review_required' \
  '[CLI] result=manual_webhook_review_required' >"$RECOVERY_MANUAL"
chmod 600 "$RECOVERY_MANUAL"
"$VALIDATOR" --transcript "$RECOVERY_MANUAL" >/dev/null \
  || fail "valid manual-review recovery transcript was rejected"

NO_RECOVERY_JOURNAL="$TEMP_ROOT/no-recovery-journal.txt"
printf '%s\n' \
  "${RECOVERY_PREAMBLE[@]}" \
  '[CLI] result=no_recovery_journal' >"$NO_RECOVERY_JOURNAL"
chmod 600 "$NO_RECOVERY_JOURNAL"
"$VALIDATOR" --transcript "$NO_RECOVERY_JOURNAL" >/dev/null \
  || fail "valid empty recovery transcript was rejected"

RECOVERY_MISSING_BIND="$TEMP_ROOT/recovery-missing-bind.txt"
rg -v 'checkpoint=recovery_webhook_bound' \
  "$RECOVERED_DISCOVERED" >"$RECOVERY_MISSING_BIND"
chmod 600 "$RECOVERY_MISSING_BIND"
expect_rejected "$RECOVERY_MISSING_BIND" \
  "a discovered recovery transcript without durable binding"

RECOVERY_MANUAL_MISMATCH="$TEMP_ROOT/recovery-manual-mismatch.txt"
sed 's/result=manual_webhook_review_required/result=recovered/' \
  "$RECOVERY_MANUAL" >"$RECOVERY_MANUAL_MISMATCH"
chmod 600 "$RECOVERY_MANUAL_MISMATCH"
expect_rejected "$RECOVERY_MANUAL_MISMATCH" \
  "a recovery transcript whose manual checkpoint and result disagree"

MISSING="$TEMP_ROOT/missing-checkpoint.txt"
rg -v 'checkpoint=task_stopped_ask' "$ACCEPTED" >"$MISSING"
chmod 600 "$MISSING"
expect_rejected "$MISSING" "a transcript with a missing checkpoint"

DUPLICATE="$TEMP_ROOT/duplicate-checkpoint.txt"
awk '{ print; if ($0 == "[CLI] checkpoint=task_created") print }' "$ACCEPTED" >"$DUPLICATE"
chmod 600 "$DUPLICATE"
expect_rejected "$DUPLICATE" "a transcript with a duplicate checkpoint"

OUT_OF_ORDER="$TEMP_ROOT/out-of-order.txt"
sed \
  -e 's/checkpoint=signed_registration_probe/checkpoint=registration_accepted/' \
  -e '0,/checkpoint=registration_accepted/s//checkpoint=signed_registration_probe/' \
  "$ACCEPTED" >"$OUT_OF_ORDER" 2>/dev/null \
  || ruby -e 's=File.binread(ARGV[0]); a="checkpoint=signed_registration_probe"; b="checkpoint=registration_accepted"; s.sub!(a,"__swap__"); s.sub!(b,a); s.sub!("__swap__",b); File.binwrite(ARGV[1],s)' "$ACCEPTED" "$OUT_OF_ORDER"
chmod 600 "$OUT_OF_ORDER"
expect_rejected "$OUT_OF_ORDER" "an out-of-order signed registration probe"

PERSISTED_AFTER_REGISTRATION="$TEMP_ROOT/persisted-after-registration.txt"
ruby -e '
s = File.binread(ARGV.fetch(0))
a = "checkpoint=recovery_journal_persisted"
b = "checkpoint=registration_started"
s.sub!(a, "__swap__")
s.sub!(b, a)
s.sub!("__swap__", b)
File.binwrite(ARGV.fetch(1), s)
' "$ACCEPTED" "$PERSISTED_AFTER_REGISTRATION"
chmod 600 "$PERSISTED_AFTER_REGISTRATION"
expect_rejected "$PERSISTED_AFTER_REGISTRATION" \
  "a registration checkpoint before durable journal persistence"

CLEARED_BEFORE_DELETE="$TEMP_ROOT/cleared-before-delete.txt"
ruby -e '
s = File.binread(ARGV.fetch(0))
a = "checkpoint=webhook_deleted"
b = "checkpoint=recovery_journal_cleared"
s.sub!(a, "__swap__")
s.sub!(b, a)
s.sub!("__swap__", b)
File.binwrite(ARGV.fetch(1), s)
' "$ACCEPTED" "$CLEARED_BEFORE_DELETE"
chmod 600 "$CLEARED_BEFORE_DELETE"
expect_rejected "$CLEARED_BEFORE_DELETE" \
  "a journal clear before remote webhook deletion"

TRANSPORTS_BEFORE_CLEAR="$TEMP_ROOT/transports-before-clear.txt"
ruby -e '
s = File.binread(ARGV.fetch(0))
a = "checkpoint=recovery_journal_cleared"
b = "checkpoint=transports_stopped"
s.sub!(a, "__swap__")
s.sub!(b, a)
s.sub!("__swap__", b)
File.binwrite(ARGV.fetch(1), s)
' "$ACCEPTED" "$TRANSPORTS_BEFORE_CLEAR"
chmod 600 "$TRANSPORTS_BEFORE_CLEAR"
expect_rejected "$TRANSPORTS_BEFORE_CLEAR" \
  "transport shutdown before durable journal clearing"

UNCLEARED_ACCEPTED="$TEMP_ROOT/uncleared-accepted.txt"
rg -v 'checkpoint=recovery_journal_cleared' \
  "$ACCEPTED" >"$UNCLEARED_ACCEPTED"
chmod 600 "$UNCLEARED_ACCEPTED"
expect_rejected "$UNCLEARED_ACCEPTED" \
  "an accepted claim with a retained recovery journal"

URL_INJECTION="$TEMP_ROOT/url-injection.txt"
sed '$d' "$ACCEPTED" >"$URL_INJECTION"
printf '%s\n' \
  '[CLI] callback=https://example.invalid/webhook?id=provider-secret' \
  '[CLI] result=accepted' >>"$URL_INJECTION"
chmod 600 "$URL_INJECTION"
expect_rejected "$URL_INJECTION" "a callback URL injection"

RAW_ERROR="$TEMP_ROOT/raw-error.txt"
sed '$d' "$ACCEPTED" >"$RAW_ERROR"
printf '%s\n' \
  '[CLI] result=failed stage=lifecycle error=provider-auth-token' >>"$RAW_ERROR"
chmod 600 "$RAW_ERROR"
expect_rejected "$RAW_ERROR" "a raw provider error"

CRLF="$TEMP_ROOT/crlf.txt"
sed $'s/$/\r/' "$ACCEPTED" >"$CRLF"
chmod 600 "$CRLF"
expect_rejected "$CRLF" "CRLF line endings"

NO_FINAL_LF="$TEMP_ROOT/no-final-lf.txt"
printf '%s' "$(<"$ACCEPTED")" >"$NO_FINAL_LF"
chmod 600 "$NO_FINAL_LF"
expect_rejected "$NO_FINAL_LF" "a transcript without a final LF"

OVERSIZED="$TEMP_ROOT/oversized.txt"
dd if=/dev/zero of="$OVERSIZED" bs=65537 count=1 2>/dev/null
chmod 600 "$OVERSIZED"
expect_rejected "$OVERSIZED" "an oversized transcript"

SYMLINK="$TEMP_ROOT/symlink.txt"
ln -s "$ACCEPTED" "$SYMLINK"
expect_rejected "$SYMLINK" "a symbolic-link transcript"

HARDLINK="$TEMP_ROOT/hardlink.txt"
ln "$ACCEPTED" "$HARDLINK"
expect_rejected "$HARDLINK" "a multiply linked transcript"
rm "$HARDLINK"

GROUP_WRITABLE="$TEMP_ROOT/group-writable.txt"
cp "$ACCEPTED" "$GROUP_WRITABLE"
chmod 620 "$GROUP_WRITABLE"
expect_rejected "$GROUP_WRITABLE" "a group-writable transcript"

echo "Manus live-acceptance transcript and build-input fixtures: PASS"
