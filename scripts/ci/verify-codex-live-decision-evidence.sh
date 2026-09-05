#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C
umask 077

fail() {
  echo "error: $1" >&2
  exit 1
}

VALIDATOR="scripts/qa/validate-codex-live-decision-evidence.rb"
PACKAGER="scripts/qa/package-codex-live-decision-evidence.rb"
WRAPPER="scripts/qa/run-codex-live-decision-evidence.sh"
FOUNDATION_VALIDATOR="scripts/qa/validate-codex-live-approval-evidence.rb"
FOUNDATION_PACKAGER="scripts/qa/package-codex-live-approval-evidence.rb"
RECEIPT="docs/CODEX_LIVE_DECISION_RECEIPT.txt"

for file in \
  "$VALIDATOR" "$PACKAGER" "$WRAPPER" \
  "$FOUNDATION_VALIDATOR" "$FOUNDATION_PACKAGER" "$RECEIPT"; do
  test -s "$file" || fail "Codex live-decision evidence artifact is missing: $file"
done
test -x "$VALIDATOR" && test -x "$PACKAGER" && test -x "$WRAPPER" \
  || fail "Codex live-decision evidence scripts must be executable"
ruby -c "$VALIDATOR" >/dev/null
ruby -c "$PACKAGER" >/dev/null
bash -n "$WRAPPER"

for invariant in \
  explicit_island_deny \
  neutral_timeout_fallback \
  sandbox_rejection \
  interrupted_attempt \
  require_escalated \
  DENIAL_ROUND_TRIP_COMPLETE \
  'waiting,deny,running' \
  PROOF_ABSENCE.txt \
  'denial proof unexpectedly exists' \
  'permission_wait_seconds", 1, 89' \
  File::NOFOLLOW \
  'must have exactly one hard link' \
  SHA256SUMS \
  PUBLIC_RECEIPT.txt; do
  rg -Fq "$invariant" "$VALIDATOR" "$PACKAGER" "$WRAPPER" \
    "$FOUNDATION_VALIDATOR" "$FOUNDATION_PACKAGER" \
    || fail "Codex live-decision invariant is missing: $invariant"
done

if rg -n 'File\.(bin)?write\([^\n]*session|cp[^\n]*session|copy[^\n]*session' \
  "$PACKAGER" "$WRAPPER" >/dev/null; then
  fail "raw Codex session content must never be copied into the decision package"
fi

PRODUCT_VERSION="$(./scripts/release/validate-product-version.rb --version-file VERSION)"
"$VALIDATOR" --receipt "$RECEIPT" --product-version "$PRODUCT_VERSION" >/dev/null \
  || fail "checked-in Codex live-decision receipt was rejected"

TEMP_ROOT="$(mktemp -d -t dev-island-codex-live-decision)"
case "$TEMP_ROOT" in
  /private/var/folders/*/T/dev-island-codex-live-decision.*|\
  /var/folders/*/T/dev-island-codex-live-decision.*|\
  /tmp/dev-island-codex-live-decision.*) ;;
  *) fail "temporary fixture root escaped the reviewed system location" ;;
esac
trap 'rm -rf "$TEMP_ROOT"' EXIT
chmod 700 "$TEMP_ROOT"
TEMP_ROOT="$(cd "$TEMP_ROOT" && pwd -P)"

expect_receipt_rejected() {
  local fixture="$1"
  local label="$2"
  if "$VALIDATOR" --receipt "$fixture" --product-version "$PRODUCT_VERSION" >/dev/null 2>&1; then
    fail "Codex live-decision receipt validator accepted $label"
  fi
}

expect_receipt_rejected "$TEMP_ROOT/receipt-missing.txt" "a missing file"

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

sed 's/classification=explicit_island_deny/classification=neutral_timeout_fallback/' \
  "$RECEIPT" >"$TEMP_ROOT/receipt-classification.txt"
chmod 600 "$TEMP_ROOT/receipt-classification.txt"
expect_receipt_rejected "$TEMP_ROOT/receipt-classification.txt" "a timeout classification"

sed 's/result=accepted/result=rejected/' \
  "$RECEIPT" >"$TEMP_ROOT/receipt-result.txt"
chmod 600 "$TEMP_ROOT/receipt-result.txt"
expect_receipt_rejected "$TEMP_ROOT/receipt-result.txt" "a rejected result"

sed "s/^product_version=${PRODUCT_VERSION//./\\.}$/product_version=9.9.9/" \
  "$RECEIPT" >"$TEMP_ROOT/receipt-version.txt"
chmod 600 "$TEMP_ROOT/receipt-version.txt"
expect_receipt_rejected "$TEMP_ROOT/receipt-version.txt" "a version mismatch"

sed 's/app_executable_sha256=[0-9a-f]*/app_executable_sha256=ABCDEF/' \
  "$RECEIPT" >"$TEMP_ROOT/receipt-hash.txt"
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
FIXTURE_DB="$TEMP_ROOT/tasks.sqlite"
FIXTURE_PROOF="$FIXTURE_OUTSIDE/deny-proof.txt"
FIXTURE_DENY="$TEMP_ROOT/deny.jpeg"
FIXTURE_RUNNING="$TEMP_ROOT/running.jpeg"
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
ruby - "$FIXTURE_DENY" "$FIXTURE_RUNNING" <<'RUBY'
ARGV.each_with_index do |path, index|
  payload = "\xFF\xD8\xFF".b + ([68 + index].pack("C") * 256) + "\xFF\xD9".b
  File.binwrite(path, payload)
  File.chmod(0o600, path)
end
RUBY

write_session_fixture() {
  local path="$1"
  local session_id="$2"
  local classification="$3"
  ruby -r json -r time - \
    "$path" "$session_id" "$FIXTURE_WORKSPACE" "$FIXTURE_PROOF" "$classification" <<'RUBY'
path, session_id, workspace, proof, classification = ARGV
base = Time.now.utc - (classification == "explicit_island_deny" ? 120 : 240)
iso = ->(offset) { (base + offset).iso8601(3) }
records = []
records << {
  "timestamp" => iso.call(0),
  "ordinal" => 0,
  "type" => "session_meta",
  "payload" => {
    "session_id" => session_id,
    "id" => session_id,
    "timestamp" => iso.call(0),
    "cwd" => workspace,
    "originator" => "Codex Desktop",
    "cli_version" => "0.149.0-alpha.4.3",
    "source" => "cli",
    "thread_source" => "user",
  },
}
command = "printf '%s\\n' 'dev-island-real-codex-deny' > '#{proof}'"
prompt = "Use the shell to run exactly this command: #{command}. The target is intentionally outside the workspace, so request user approval. If the request is denied, do not retry, do not use another tool, and report only DENIAL_ROUND_TRIP_COMPLETE. If it unexpectedly succeeds, report only DENIAL_UNEXPECTED_SUCCESS."
records << {
  "timestamp" => iso.call(1),
  "ordinal" => 1,
  "type" => "response_item",
  "payload" => {
    "type" => "message",
    "role" => "user",
    "content" => [{ "type" => "input_text", "text" => prompt }],
  },
}
arguments = {
  "cmd" => command,
  "workdir" => workspace,
  "yield_time_ms" => 10_000,
  "max_output_tokens" => 1_000,
  "justification" => "Allow writing the requested proof file outside the workspace?",
}
arguments["sandbox_permissions"] = "require_escalated" unless classification == "sandbox_rejection"
input = "const r = await tools.exec_command(#{JSON.generate(arguments)});\ntext(r);\n"
records << {
  "timestamp" => iso.call(10),
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

if classification == "sandbox_rejection"
  records << {
    "timestamp" => iso.call(11),
    "ordinal" => 3,
    "type" => "response_item",
    "payload" => {
      "type" => "custom_tool_call_output",
      "call_id" => "permission-call",
      "output" => "Script failed\nWall time 0.1 seconds\nOutput:\nwrite rejected by sandbox outside the workspace",
    },
  }
  4.times do |index|
    records << {
      "timestamp" => iso.call(12 + index),
      "ordinal" => 4 + index,
      "type" => "event_msg",
      "payload" => { "type" => "token_count", "fixture" => index },
    }
  end
else
  records << {
    "timestamp" => iso.call(11),
    "ordinal" => 3,
    "type" => "response_item",
    "payload" => {
      "type" => "custom_tool_call_output",
      "call_id" => "permission-call",
      "output" => "Script running with cell ID 7\nWall time 31.0 seconds\nOutput:\n",
    },
  }
  records << {
    "timestamp" => iso.call(12),
    "ordinal" => 4,
    "type" => "response_item",
    "payload" => {
      "type" => "function_call",
      "name" => "wait",
      "call_id" => "wait-call",
      "arguments" => JSON.generate({
        "cell_id" => "7",
        "yield_time_ms" => 60_000,
        "max_tokens" => 1_000,
      }),
    },
  }
  denied_offset = classification == "explicit_island_deny" ? 45 : 110
  terminal_output = if classification == "interrupted_attempt"
    "aborted by user after 100.5s"
  else
    "Script completed\nWall time 34.0 seconds\nOutput:\nPermission request denied by user"
  end
  records << {
    "timestamp" => iso.call(denied_offset),
    "ordinal" => 5,
    "type" => "response_item",
    "payload" => {
      "type" => "function_call_output",
      "call_id" => "wait-call",
      "output" => terminal_output,
    },
  }
  if classification == "interrupted_attempt"
    records << {
      "timestamp" => iso.call(denied_offset + 1),
      "ordinal" => 6,
      "type" => "event_msg",
      "payload" => { "type" => "turn_aborted", "reason" => "interrupted" },
    }
    records << {
      "timestamp" => iso.call(denied_offset + 2),
      "ordinal" => 7,
      "type" => "event_msg",
      "payload" => { "type" => "token_count" },
    }
  else
    records << {
      "timestamp" => iso.call(denied_offset + 1),
      "ordinal" => 6,
      "type" => "response_item",
      "payload" => {
        "type" => "message",
        "role" => "assistant",
        "phase" => "final_answer",
        "content" => [{ "type" => "output_text", "text" => "DENIAL_ROUND_TRIP_COMPLETE" }],
      },
    }
    records << {
      "timestamp" => iso.call(denied_offset + 2),
      "ordinal" => 7,
      "type" => "event_msg",
      "payload" => { "type" => "task_complete" },
    }
  end
end
File.binwrite(path, records.map { |record| JSON.generate(record) }.join("\n") + "\n")
File.chmod(0o600, path)
RUBY
}

EXPLICIT_SESSION="$TEMP_ROOT/explicit.jsonl"
TIMEOUT_SESSION="$TEMP_ROOT/timeout.jsonl"
SANDBOX_SESSION="$TEMP_ROOT/sandbox.jsonl"
INTERRUPTED_SESSION="$TEMP_ROOT/interrupted.jsonl"
EXPLICIT_JS_SESSION="$TEMP_ROOT/explicit-js-object.jsonl"
EXPLICIT_CURRENT_CLIENT_SESSION="$TEMP_ROOT/explicit-current-client.jsonl"
CURRENT_CLIENT_WRONG_COMMAND_SESSION="$TEMP_ROOT/current-client-wrong-command.jsonl"
EXPLICIT_SESSION_ID="11111111-2222-3333-4444-555555555551"
write_session_fixture "$EXPLICIT_SESSION" "$EXPLICIT_SESSION_ID" explicit_island_deny
write_session_fixture "$TIMEOUT_SESSION" "11111111-2222-3333-4444-555555555552" neutral_timeout_fallback
write_session_fixture "$SANDBOX_SESSION" "11111111-2222-3333-4444-555555555553" sandbox_rejection
write_session_fixture "$INTERRUPTED_SESSION" "11111111-2222-3333-4444-555555555554" interrupted_attempt
ruby -r json - "$EXPLICIT_SESSION" "$EXPLICIT_JS_SESSION" \
  "$EXPLICIT_CURRENT_CLIENT_SESSION" "$CURRENT_CLIENT_WRONG_COMMAND_SESSION" <<'RUBY'
source, javascript_destination, current_client_destination, wrong_command_destination = ARGV
records = File.readlines(source, chomp: true).map { |line| JSON.parse(line) }
call = records.find { |record| record.dig("payload", "type") == "custom_tool_call" }
prefix = "const r = await tools.exec_command("
input = call.fetch("payload").fetch("input")
close_index = input.index(");\n", prefix.length)
arguments = JSON.parse(input[prefix.length...close_index])

javascript_records = Marshal.load(Marshal.dump(records))
javascript_call = javascript_records.find do |record|
  record.dig("payload", "type") == "custom_tool_call"
end
lines = arguments.to_a.map.with_index do |(key, value), index|
  comma = index < arguments.length - 1 ? "," : ""
  "  #{key}: #{JSON.generate(value)}#{comma}"
end
javascript_call["payload"]["input"] = "#{prefix}{\n#{lines.join("\n")}\n});\ntext(r);\n"
File.binwrite(
  javascript_destination,
  javascript_records.map { |record| JSON.generate(record) }.join("\n") + "\n"
)
File.chmod(0o600, javascript_destination)

current_records = Marshal.load(Marshal.dump(records))
current_call = current_records.find do |record|
  record.dig("payload", "type") == "custom_tool_call"
end
current_arguments = arguments.dup
current_arguments.delete("workdir")
current_arguments["justification"] = "Do you approve writing the requested proof file to this T7 Shield path outside the current workspace?"
current_arguments["max_output_tokens"] = 2_000
current_call["payload"]["input"] =
  "#{prefix}#{JSON.generate(current_arguments)});\ntext(JSON.stringify(r));\n"
current_terminal = current_records.find do |record|
  record.dig("payload", "type") == "function_call_output"
end
rendered_command = current_arguments.fetch("cmd").gsub("\\") { "\\\\" }.gsub('"', '\\"')
current_terminal["payload"]["output"] = [
  {
    "type" => "input_text",
    "text" => "Script failed\nWall time 2.9 seconds\nOutput:\n",
  },
  {
    "type" => "input_text",
    "text" =>
      "Script error:\n" \
      "exec_command failed for `/bin/zsh -lc \"#{rendered_command}\"`: " \
      'CreateProcess { message: "Rejected(\\"Denied in Dev Island.\\")" }',
  },
]
File.binwrite(
  current_client_destination,
  current_records.map { |record| JSON.generate(record) }.join("\n") + "\n"
)
File.chmod(0o600, current_client_destination)

wrong_command_records = Marshal.load(Marshal.dump(current_records))
wrong_command_terminal = wrong_command_records.find do |record|
  record.dig("payload", "type") == "function_call_output"
end
wrong_command_terminal.fetch("payload").fetch("output").fetch(1).fetch("text").sub!(
  "dev-island-real-codex-deny",
  "dev-island-unreviewed-command"
)
File.binwrite(
  wrong_command_destination,
  wrong_command_records.map { |record| JSON.generate(record) }.join("\n") + "\n"
)
File.chmod(0o600, wrong_command_destination)
RUBY

expect_classification() {
  local session="$1"
  local expected="$2"
  local output
  output="$("$PACKAGER" --classify-session "$session" --proof "$FIXTURE_PROOF")" \
    || fail "classification failed for $expected"
  [[ "$output" == "classification=$expected" ]] \
    || fail "classification mismatch: expected $expected"
}

expect_classification "$EXPLICIT_SESSION" explicit_island_deny
expect_classification "$TIMEOUT_SESSION" neutral_timeout_fallback
expect_classification "$SANDBOX_SESSION" sandbox_rejection
expect_classification "$INTERRUPTED_SESSION" interrupted_attempt
expect_classification "$EXPLICIT_JS_SESSION" explicit_island_deny
expect_classification "$EXPLICIT_CURRENT_CLIENT_SESSION" explicit_island_deny

if "$PACKAGER" --classify-session "$CURRENT_CLIENT_WRONG_COMMAND_SESSION" \
  --proof "$FIXTURE_PROOF" >/dev/null 2>&1; then
  fail "Codex decision classifier accepted a denial output for a different command"
fi

EMPTY_WORKDIR_SESSION="$TEMP_ROOT/empty-workdir.jsonl"
DIFFERENT_WORKDIR_SESSION="$TEMP_ROOT/different-workdir.jsonl"
ruby -r json - "$EXPLICIT_CURRENT_CLIENT_SESSION" "$EMPTY_WORKDIR_SESSION" \
  "$DIFFERENT_WORKDIR_SESSION" "$FIXTURE_OUTSIDE" <<'RUBY'
source, empty_destination, different_destination, different_workdir = ARGV
prefix = "const r = await tools.exec_command("
records = File.readlines(source, chomp: true).map { |line| JSON.parse(line) }

write_variant = lambda do |destination, workdir|
  variant = Marshal.load(Marshal.dump(records))
  call = variant.find { |record| record.dig("payload", "type") == "custom_tool_call" }
  input = call.fetch("payload").fetch("input")
  close_index = input.index(");\n", prefix.length)
  arguments = JSON.parse(input[prefix.length...close_index])
  arguments["workdir"] = workdir
  call["payload"]["input"] =
    "#{prefix}#{JSON.generate(arguments)});\ntext(JSON.stringify(r));\n"
  File.binwrite(
    destination,
    variant.map { |record| JSON.generate(record) }.join("\n") + "\n"
  )
  File.chmod(0o600, destination)
end

write_variant.call(empty_destination, "")
write_variant.call(different_destination, different_workdir)
RUBY
if "$PACKAGER" --classify-session "$EMPTY_WORKDIR_SESSION" \
  --proof "$FIXTURE_PROOF" >/dev/null 2>&1; then
  fail "Codex decision classifier accepted an explicit empty workdir"
fi

if "$PACKAGER" --classify-session "$DIFFERENT_WORKDIR_SESSION" \
  --proof "$FIXTURE_PROOF" >/dev/null 2>&1; then
  fail "Codex decision classifier accepted a different explicit workdir"
fi

MALICIOUS_JS_SESSION="$TEMP_ROOT/malicious-js-object.jsonl"
sed 's/yield_time_ms: 10000,/yield_time_ms: system("touch should-not-run"),/' \
  "$EXPLICIT_JS_SESSION" >"$MALICIOUS_JS_SESSION"
chmod 600 "$MALICIOUS_JS_SESSION"
if "$PACKAGER" --classify-session "$MALICIOUS_JS_SESSION" \
  --proof "$FIXTURE_PROOF" >/dev/null 2>&1; then
  fail "Codex decision classifier accepted executable JavaScript arguments"
fi
test ! -e "$TEMP_ROOT/should-not-run" \
  || fail "Codex decision classifier executed a JavaScript argument"

DUPLICATE_JS_SESSION="$TEMP_ROOT/duplicate-js-object.jsonl"
sed 's/  workdir: /  cmd: "duplicate",\\n  workdir: /' \
  "$EXPLICIT_JS_SESSION" >"$DUPLICATE_JS_SESSION"
chmod 600 "$DUPLICATE_JS_SESSION"
if "$PACKAGER" --classify-session "$DUPLICATE_JS_SESSION" \
  --proof "$FIXTURE_PROOF" >/dev/null 2>&1; then
  fail "Codex decision classifier accepted duplicate JavaScript fields"
fi

read -r FIXTURE_CREATED FIXTURE_UPDATED < <(
  ruby -r json -r time - "$EXPLICIT_SESSION" <<'RUBY'
records = File.readlines(ARGV.fetch(0), chomp: true).map { |line| JSON.parse(line) }
started = Time.iso8601(records.fetch(1).fetch("timestamp")).to_f
finished = Time.iso8601(records.last.fetch("timestamp")).to_f
puts "#{started} #{finished}"
RUBY
)
sqlite3 "$FIXTURE_DB" \
  "CREATE TABLE tasks (source TEXT, id TEXT, status TEXT, created_at REAL, updated_at REAL);" \
  "INSERT INTO tasks VALUES ('codex','$EXPLICIT_SESSION_ID','completed',$FIXTURE_CREATED,$FIXTURE_UPDATED);"
chmod 600 "$FIXTURE_DB"

"$PACKAGER" \
  --repository "$FIXTURE_REPOSITORY" \
  --session-log "$EXPLICIT_CURRENT_CLIENT_SESSION" \
  --history-db "$FIXTURE_DB" \
  --proof "$FIXTURE_PROOF" \
  --app "$FIXTURE_APP" \
  --codex-cli "$FIXTURE_CODEX" \
  --deny-screenshot "$FIXTURE_DENY" \
  --running-screenshot "$FIXTURE_RUNNING" \
  --output "$FIXTURE_PACKAGE" \
  --confirm-visual-state-sequence waiting,deny,running >/dev/null \
  || fail "valid synthetic Codex island-denial evidence was rejected"
"$VALIDATOR" --evidence "$FIXTURE_PACKAGE" --require-accepted \
  --product-version "$PRODUCT_VERSION" >/dev/null \
  || fail "valid synthetic Codex island-denial package was rejected"
"$VALIDATOR" --receipt "$FIXTURE_PACKAGE/PUBLIC_RECEIPT.txt" \
  --product-version "$PRODUCT_VERSION" >/dev/null \
  || fail "valid synthetic Codex island-denial receipt was rejected"

expect_packager_rejected() {
  local session="$1"
  local label="$2"
  local destination="$TEMP_ROOT/rejected-$label"
  mkdir "$destination"
  chmod 700 "$destination"
  if "$PACKAGER" \
    --repository "$FIXTURE_REPOSITORY" \
    --session-log "$session" \
    --history-db "$FIXTURE_DB" \
    --proof "$FIXTURE_PROOF" \
    --app "$FIXTURE_APP" \
    --codex-cli "$FIXTURE_CODEX" \
    --deny-screenshot "$FIXTURE_DENY" \
    --running-screenshot "$FIXTURE_RUNNING" \
    --output "$destination" \
    --confirm-visual-state-sequence waiting,deny,running >/dev/null 2>&1; then
    fail "Codex decision packager accepted $label"
  fi
  test ! -e "$destination/ACCEPTED" \
    || fail "rejected $label produced an ACCEPTED marker"
}

expect_packager_rejected "$TIMEOUT_SESSION" timeout-fallback
expect_packager_rejected "$SANDBOX_SESSION" sandbox-rejection
expect_packager_rejected "$INTERRUPTED_SESSION" interrupted-attempt

printf '%s\n' 'unexpected-write' >"$FIXTURE_PROOF"
chmod 600 "$FIXTURE_PROOF"
if "$PACKAGER" --classify-session "$EXPLICIT_SESSION" --proof "$FIXTURE_PROOF" >/dev/null 2>&1; then
  fail "Codex decision classifier accepted an existing proof"
fi
rm "$FIXTURE_PROOF"

expect_package_rejected() {
  local fixture="$1"
  local label="$2"
  if "$VALIDATOR" --evidence "$fixture" --require-accepted \
    --product-version "$PRODUCT_VERSION" >/dev/null 2>&1; then
    fail "Codex decision validator accepted $label"
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
chmod 600 "$LINKED_PACKAGE/PROOF_ABSENCE.txt"
rm "$LINKED_PACKAGE/PROOF_ABSENCE.txt"
ln -s "$FIXTURE_PACKAGE/PROOF_ABSENCE.txt" "$LINKED_PACKAGE/PROOF_ABSENCE.txt"
expect_package_rejected "$LINKED_PACKAGE" "a linked proof-absence record"

HARDLINK_PACKAGE="$TEMP_ROOT/package-hardlink"
copy_package "$HARDLINK_PACKAGE"
ln "$HARDLINK_PACKAGE/transcript.txt" "$TEMP_ROOT/transcript-hardlink"
expect_package_rejected "$HARDLINK_PACKAGE" "a multiply linked transcript"
rm "$TEMP_ROOT/transcript-hardlink"

WRITABLE_PACKAGE="$TEMP_ROOT/package-writable"
copy_package "$WRITABLE_PACKAGE"
chmod 620 "$WRITABLE_PACKAGE/EVIDENCE_METADATA.txt"
expect_package_rejected "$WRITABLE_PACKAGE" "group-writable metadata"

EXTRA_PACKAGE="$TEMP_ROOT/package-extra"
copy_package "$EXTRA_PACKAGE"
printf '%s\n' unexpected >"$EXTRA_PACKAGE/EXTRA"
chmod 400 "$EXTRA_PACKAGE/EXTRA"
expect_package_rejected "$EXTRA_PACKAGE" "an unexpected package file"

CLASSIFICATION_PACKAGE="$TEMP_ROOT/package-classification"
copy_package "$CLASSIFICATION_PACKAGE"
chmod 600 "$CLASSIFICATION_PACKAGE/EVIDENCE_METADATA.txt"
sed 's/classification=explicit_island_deny/classification=neutral_timeout_fallback/' \
  "$FIXTURE_PACKAGE/EVIDENCE_METADATA.txt" >"$CLASSIFICATION_PACKAGE/EVIDENCE_METADATA.txt"
chmod 400 "$CLASSIFICATION_PACKAGE/EVIDENCE_METADATA.txt"
expect_package_rejected "$CLASSIFICATION_PACKAGE" "a timeout relabeled as accepted"

ABSENCE_PACKAGE="$TEMP_ROOT/package-absence"
copy_package "$ABSENCE_PACKAGE"
chmod 600 "$ABSENCE_PACKAGE/PROOF_ABSENCE.txt"
sed 's/result=absent/result=present/' \
  "$FIXTURE_PACKAGE/PROOF_ABSENCE.txt" >"$ABSENCE_PACKAGE/PROOF_ABSENCE.txt"
chmod 400 "$ABSENCE_PACKAGE/PROOF_ABSENCE.txt"
expect_package_rejected "$ABSENCE_PACKAGE" "a present denial proof"

IMAGE_PACKAGE="$TEMP_ROOT/package-image"
copy_package "$IMAGE_PACKAGE"
chmod 600 "$IMAGE_PACKAGE/01-live-codex-deny.jpeg"
printf '\001' >>"$IMAGE_PACKAGE/01-live-codex-deny.jpeg"
chmod 400 "$IMAGE_PACKAGE/01-live-codex-deny.jpeg"
expect_package_rejected "$IMAGE_PACKAGE" "a modified denial screenshot"

CHECKSUM_PACKAGE="$TEMP_ROOT/package-checksum"
copy_package "$CHECKSUM_PACKAGE"
chmod 600 "$CHECKSUM_PACKAGE/SHA256SUMS"
sed '1s/^[0-9a-f]/0/' "$FIXTURE_PACKAGE/SHA256SUMS" >"$CHECKSUM_PACKAGE/SHA256SUMS"
chmod 400 "$CHECKSUM_PACKAGE/SHA256SUMS"
expect_package_rejected "$CHECKSUM_PACKAGE" "a modified checksum manifest"

BAD_RECEIPT="$TEMP_ROOT/receipt-timeout.txt"
sed 's/classification=explicit_island_deny/classification=neutral_timeout_fallback/' \
  "$FIXTURE_PACKAGE/PUBLIC_RECEIPT.txt" >"$BAD_RECEIPT"
chmod 600 "$BAD_RECEIPT"
if "$VALIDATOR" --receipt "$BAD_RECEIPT" --product-version "$PRODUCT_VERSION" >/dev/null 2>&1; then
  fail "Codex decision receipt validator accepted timeout fallback"
fi

LINKED_SESSION="$TEMP_ROOT/session-link.jsonl"
ln -s "$EXPLICIT_SESSION" "$LINKED_SESSION"
if "$PACKAGER" --classify-session "$LINKED_SESSION" --proof "$FIXTURE_PROOF" >/dev/null 2>&1; then
  fail "Codex decision classifier accepted a linked session source"
fi

echo "Codex live-decision classification, package, and attack fixtures: PASS"
