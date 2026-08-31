#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C
umask 077

fail() {
  echo "error: $1" >&2
  exit 1
}

VALIDATOR="scripts/qa/validate-system-accessibility-evidence.rb"
PACKAGER="scripts/qa/package-system-accessibility-evidence.rb"
WRAPPER="scripts/qa/run-system-accessibility-evidence.sh"
RECEIPT="docs/SYSTEM_ACCESSIBILITY_RECEIPT.txt"

for file in "$VALIDATOR" "$PACKAGER" "$WRAPPER" "$RECEIPT"; do
  test -s "$file" || fail "system accessibility evidence artifact is missing: $file"
done
test -x "$VALIDATOR" && test -x "$PACKAGER" && test -x "$WRAPPER" \
  || fail "system accessibility evidence scripts must be executable"
ruby -c "$VALIDATOR" >/dev/null
ruby -c "$PACKAGER" >/dev/null
bash -n "$WRAPPER"

scan_user_environment_mutations() {
  local root="$1"
  ruby -r find - "$root" <<'RUBY'
root = File.realpath(ARGV.fetch(0))
extensions = %w[.sh .rb .swift .yml .yaml].freeze
pruned_directories = %w[.git .build dist docs].freeze
boundary = '(?:\\A|[[:space:];&|($`])'

commands = {
  "defaults mutation" => ["def", "aults"].join,
  "process-wide termination" => ["kill", "all"].join,
  "pattern-based process termination" => ["p", "kill"].join,
  "launch-service mutation" => ["launch", "ctl"].join,
  "AppleScript execution" => ["osa", "script"].join,
}.freeze

patterns = [
  [
    commands.fetch("defaults mutation"),
    Regexp.new("#{boundary}(?:/usr/bin/)?#{commands.fetch("defaults mutation")}[[:space:]]+(?:write|delete)\\b", Regexp::IGNORECASE),
  ],
  [
    commands.fetch("process-wide termination"),
    Regexp.new("#{boundary}(?:/usr/bin/)?#{commands.fetch("process-wide termination")}[[:space:]]+", Regexp::IGNORECASE),
  ],
  [
    commands.fetch("pattern-based process termination"),
    Regexp.new("#{boundary}(?:/usr/bin/)?#{commands.fetch("pattern-based process termination")}[[:space:]]+", Regexp::IGNORECASE),
  ],
  [
    commands.fetch("launch-service mutation"),
    Regexp.new("#{boundary}(?:/bin/)?#{commands.fetch("launch-service mutation")}[[:space:]]+(?:kill|stop|disable|bootout|remove)\\b", Regexp::IGNORECASE),
  ],
  [
    commands.fetch("AppleScript execution"),
    Regexp.new("#{boundary}(?:/usr/bin/)?#{commands.fetch("AppleScript execution")}\\b", Regexp::IGNORECASE),
  ],
  [
    "global preference API",
    Regexp.new(["CFPreferences", "SetAppValue"].join, Regexp::IGNORECASE),
  ],
  [
    "universal-access preference file",
    Regexp.new(["com.apple.", "universalaccess", ".plist"].join, Regexp::IGNORECASE),
  ],
].freeze

violations = []
Find.find(root) do |path|
  relative = path.delete_prefix(root + File::SEPARATOR)
  stat = File.lstat(path)
  if stat.directory?
    if !relative.empty? && pruned_directories.include?(relative.split(File::SEPARATOR).first)
      Find.prune
    end
    next
  end
  next unless extensions.include?(File.extname(path))
  if stat.symlink?
    violations << "#{relative}: symbolic links are not allowed in the audited executable surface"
    next
  end
  next unless stat.file?
  if stat.size > 4 * 1_024 * 1_024
    violations << "#{relative}: executable source exceeds the 4 MiB audit boundary"
    next
  end
  bytes = File.binread(path)
  if bytes.include?("\0") || !bytes.force_encoding(Encoding::UTF_8).valid_encoding?
    violations << "#{relative}: executable source is not bounded UTF-8 text"
    next
  end
  bytes.each_line.with_index(1) do |line, line_number|
    patterns.each do |label, pattern|
      violations << "#{relative}:#{line_number}: prohibited #{label}" if line.match?(pattern)
    end
  end
rescue Errno::ENOENT, Errno::EACCES => error
  violations << "#{relative}: source changed or became unreadable (#{error.class})"
end

unless violations.empty?
  warn violations.join("\n")
  exit 1
end
RUBY
}

# System-level QA is allowed to inspect current state, but no executable App,
# QA, CI, or Release source may mutate the maintainer's login-session
# preferences, invoke AppleScript, or terminate unrelated processes. System
# toggles belong only in an isolated macOS test account or VM.
scan_user_environment_mutations "$PWD" \
  || fail "repository executable surface can mutate the maintainer macOS environment"

for invariant in \
  'File::NOFOLLOW' \
  'must have exactly one hard link' \
  'real_process_operator_observed' \
  'command_d_then_command_return_operator_observed' \
  'Reduce Motion frames differ' \
  'reduce_motion=on\noriginal_reduce_motion=off' \
  'macos_system_settings_and_process_inspection' \
  'production_app_processes' \
  'SHA256SUMS' \
  'PUBLIC_RECEIPT.txt'; do
  rg -Fq "$invariant" "$VALIDATOR" "$PACKAGER" "$WRAPPER" \
    || fail "system accessibility evidence invariant is missing: $invariant"
done
rg -Fq 'scan_user_environment_mutations "$PWD"' "$0" \
  || fail "repository-wide macOS user-environment isolation gate is missing"

PRODUCT_VERSION="$(./scripts/release/validate-product-version.rb --version-file VERSION)"
"$VALIDATOR" --receipt "$RECEIPT" --product-version "$PRODUCT_VERSION" >/dev/null \
  || fail "checked-in system accessibility receipt was rejected"

receipt_value() {
  local key="$1"
  local value
  value="$(awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2) }' "$RECEIPT")"
  test -n "$value" || fail "system accessibility receipt field is missing: $key"
  test "$(rg -c "^${key}=" "$RECEIPT")" = "1" \
    || fail "system accessibility receipt field is duplicated: $key"
  printf '%s\n' "$value"
}

for binding in \
  "packager_sha256:$PACKAGER" \
  "validator_sha256:$VALIDATOR" \
  "wrapper_sha256:$WRAPPER"; do
  key="${binding%%:*}"
  path="${binding#*:}"
  expected="$(receipt_value "$key")"
  actual="$(shasum -a 256 "$path" | awk '{print $1}')"
  test "$actual" = "$expected" \
    || fail "checked-in system accessibility receipt is stale for $path"
done

TEMP_ROOT="$(mktemp -d -t dev-island-system-accessibility)"
case "$TEMP_ROOT" in
  /private/var/folders/*/T/dev-island-system-accessibility.*|\
  /var/folders/*/T/dev-island-system-accessibility.*|\
  /tmp/dev-island-system-accessibility.*) ;;
  *) fail "temporary fixture root escaped the reviewed system location" ;;
esac
trap 'rm -rf "$TEMP_ROOT"' EXIT
chmod 700 "$TEMP_ROOT"
TEMP_ROOT="$(cd "$TEMP_ROOT" && pwd -P)"

expect_environment_mutation_rejected() {
  local fixture="$1"
  local label="$2"
  if scan_user_environment_mutations "$fixture" >/dev/null 2>&1; then
    fail "macOS user-environment isolation gate accepted $label"
  fi
}

MUTATION_FIXTURE_ROOT="$TEMP_ROOT/environment-mutations"
mkdir "$MUTATION_FIXTURE_ROOT"
chmod 700 "$MUTATION_FIXTURE_ROOT"

DEFAULTS_FIXTURE="$MUTATION_FIXTURE_ROOT/defaults"
mkdir "$DEFAULTS_FIXTURE"
printf '%s %s %s %s %s\n' \
  '/usr/bin/defaults' 'write' 'com.apple.universalaccess' 'increaseContrast' '-bool true' \
  >"$DEFAULTS_FIXTURE/mutate.sh"
expect_environment_mutation_rejected "$DEFAULTS_FIXTURE" "a defaults preference mutation"

PROCESS_FIXTURE="$MUTATION_FIXTURE_ROOT/process"
mkdir "$PROCESS_FIXTURE"
printf '%s %s\n' '/usr/bin/killall' 'VoiceOver' >"$PROCESS_FIXTURE/mutate.sh"
expect_environment_mutation_rejected "$PROCESS_FIXTURE" "process-wide termination"

LAUNCH_FIXTURE="$MUTATION_FIXTURE_ROOT/launch"
mkdir "$LAUNCH_FIXTURE"
printf '%s %s %s\n' '/bin/launchctl' 'bootout' 'gui/501/com.apple.VoiceOver' \
  >"$LAUNCH_FIXTURE/mutate.sh"
expect_environment_mutation_rejected "$LAUNCH_FIXTURE" "a launch-service mutation"

SCRIPT_FIXTURE="$MUTATION_FIXTURE_ROOT/script"
mkdir "$SCRIPT_FIXTURE"
printf '%s%s %s %s\n' '/usr/bin/osa' 'script' '-e' 'return 1' >"$SCRIPT_FIXTURE/mutate.sh"
expect_environment_mutation_rejected "$SCRIPT_FIXTURE" "AppleScript execution"

PREFERENCE_API_FIXTURE="$MUTATION_FIXTURE_ROOT/preference-api"
mkdir "$PREFERENCE_API_FIXTURE"
printf '%s%s%s\n' 'CFPreferences' 'SetAppValue' '(key, value, domain)' \
  >"$PREFERENCE_API_FIXTURE/Mutate.swift"
expect_environment_mutation_rejected "$PREFERENCE_API_FIXTURE" "a global preference API mutation"

expect_receipt_rejected() {
  local fixture="$1"
  local label="$2"
  if "$VALIDATOR" --receipt "$fixture" --product-version "$PRODUCT_VERSION" >/dev/null 2>&1; then
    fail "system accessibility receipt validator accepted $label"
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

for mutation in result scope voiceover frame; do
  fixture="$TEMP_ROOT/receipt-$mutation.txt"
  case "$mutation" in
    result) sed 's/result=accepted/result=rejected/' "$RECEIPT" >"$fixture" ;;
    scope) sed 's/scope=ax_order_keyboard_transitions_reduce_motion_and_restoration/scope=full_voiceover_speech/' "$RECEIPT" >"$fixture" ;;
    voiceover) sed 's/voiceover_observation=real_process_operator_observed/voiceover_observation=machine_proven/' "$RECEIPT" >"$fixture" ;;
    frame) sed 's/frame_a_sha256=[0-9a-f]*/frame_a_sha256=ABCDEF/' "$RECEIPT" >"$fixture" ;;
  esac
  chmod 600 "$fixture"
  expect_receipt_rejected "$fixture" "a forged $mutation field"
done

sed $'s/$/\r/' "$RECEIPT" >"$TEMP_ROOT/receipt-crlf.txt"
chmod 600 "$TEMP_ROOT/receipt-crlf.txt"
expect_receipt_rejected "$TEMP_ROOT/receipt-crlf.txt" "CRLF line endings"
printf '%s' "$(<"$RECEIPT")" >"$TEMP_ROOT/receipt-no-lf.txt"
chmod 600 "$TEMP_ROOT/receipt-no-lf.txt"
expect_receipt_rejected "$TEMP_ROOT/receipt-no-lf.txt" "a missing final LF"

FIXTURE_APP="$TEMP_ROOT/Fixture.app"
FIXTURE_CAPTURE="$TEMP_ROOT/capture"
FIXTURE_RESTORATION="$TEMP_ROOT/restoration.txt"
FIXTURE_PACKAGE="$TEMP_ROOT/package"
mkdir -p "$FIXTURE_APP/Contents/MacOS" "$FIXTURE_CAPTURE" "$FIXTURE_PACKAGE"
chmod 700 "$FIXTURE_APP" "$FIXTURE_APP/Contents" "$FIXTURE_APP/Contents/MacOS" \
  "$FIXTURE_CAPTURE" "$FIXTURE_PACKAGE"
cp /usr/bin/true "$FIXTURE_APP/Contents/MacOS/IslandApp"
chmod 500 "$FIXTURE_APP/Contents/MacOS/IslandApp"
plutil -create xml1 "$FIXTURE_APP/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string app.devisland.Island "$FIXTURE_APP/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string "$PRODUCT_VERSION" "$FIXTURE_APP/Contents/Info.plist"
plutil -insert CFBundleExecutable -string IslandApp "$FIXTURE_APP/Contents/Info.plist"
chmod 400 "$FIXTURE_APP/Contents/Info.plist"

ruby - "$FIXTURE_CAPTURE" <<'RUBY'
# encoding: UTF-8
root = ARGV.fetch(0)
jpeg = "\xFF\xD8\xFF".b + ("A" * 256) + "\xFF\xD9".b
%w[
  01-voiceover-approval.png
  02-voiceover-after-deny.png
  03-voiceover-allow-once.png
  04-voiceover-after-allow-once.png
  05-reduce-motion-on.png
  06-reduce-motion-frame-a.png
  07-reduce-motion-frame-b.png
].each do |name|
  path = File.join(root, name)
  File.binwrite(path, jpeg)
  File.chmod(0o600, path)
end

common = <<~TEXT
  Window: "Dev Island", App: Dev Island.
  1 container
  2 unknown Description: Agent 连接, Details: 本地 Agent：已就绪，Manus：未连接
  3 按钮 Description: 连接 Agent, Help: 打开 Agent 连接设置
  4 按钮 Description: 打开 Dev Island 设置, Help: 在独立窗口中打开设置
  5 滚动区
  6 列表
TEXT
waiting = common + <<~TEXT
  7 unknown 专注，1。1 个等待中，2 个运行中。共 3 个会话。
  8 container Codex · 会话 ABCD 的 待批准：Fixture
  9 text Approve Bash
  10 按钮 Description: 拒绝, Help: 拒绝此权限请求
  11 按钮 Description: 仅允许一次, Help: 仅为此次请求授予此权限
TEXT
working = common + <<~TEXT
  7 unknown 工作中，3。3 个运行中。共 3 个会话。
  8 unknown Description: Codex，Fixture，进行中
TEXT
{
  "01-voiceover-approval-ax.txt" => waiting,
  "02-voiceover-after-deny-ax.txt" => working,
  "03-voiceover-allow-once-ax.txt" => waiting,
  "04-voiceover-after-allow-once-ax.txt" => working,
  "05-reduce-motion-on-ax.txt" => working,
  "05-reduce-motion-system-state.txt" => "reduce_motion=on\noriginal_reduce_motion=off\n",
}.each do |name, contents|
  path = File.join(root, name)
  File.binwrite(path, contents)
  File.chmod(0o600, path)
end
RUBY

PRODUCTION_SHA="$(shasum -a 256 /usr/bin/true | awk '{print $1}')"
PRODUCTION_BYTES="$(stat -f '%z' /usr/bin/true)"
{
  printf '%s\n' \
    'schema=dev-island-system-restoration-v1' \
    'recorded_at_utc=2026-08-30T06:40:00Z' \
    'reduce_motion=off' \
    'increase_contrast=off' \
    'reduce_transparency=off' \
    'voiceover_processes=0' \
    'debug_app_processes=0' \
    'production_app_processes=1' \
    "production_app_executable_sha256=$PRODUCTION_SHA" \
    "production_app_executable_bytes=$PRODUCTION_BYTES" \
    'method=macos_system_settings_and_process_inspection'
} >"$FIXTURE_RESTORATION"
chmod 600 "$FIXTURE_RESTORATION"

"$PACKAGER" \
  --repository "$PWD" \
  --capture-dir "$FIXTURE_CAPTURE" \
  --debug-app "$FIXTURE_APP" \
  --restoration-state "$FIXTURE_RESTORATION" \
  --output "$FIXTURE_PACKAGE" \
  --started-at 2026-08-30T06:34:59Z \
  --finished-at 2026-08-30T06:38:18Z \
  --confirm-voiceover-observation real_process_operator_observed \
  --confirm-keyboard-sequence command_d_then_command_return_operator_observed >/dev/null \
  || fail "valid synthetic system accessibility evidence was rejected"
"$VALIDATOR" --evidence "$FIXTURE_PACKAGE" --require-accepted \
  --product-version "$PRODUCT_VERSION" >/dev/null \
  || fail "valid synthetic system accessibility package was rejected"

expect_package_rejected() {
  local fixture="$1"
  local label="$2"
  if "$VALIDATOR" --evidence "$fixture" --require-accepted \
    --product-version "$PRODUCT_VERSION" >/dev/null 2>&1; then
    fail "system accessibility package validator accepted $label"
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
chmod 600 "$LINKED_PACKAGE/RESTORATION_STATE.txt"
rm "$LINKED_PACKAGE/RESTORATION_STATE.txt"
ln -s "$FIXTURE_PACKAGE/RESTORATION_STATE.txt" "$LINKED_PACKAGE/RESTORATION_STATE.txt"
expect_package_rejected "$LINKED_PACKAGE" "a linked restoration receipt"

HARDLINK_PACKAGE="$TEMP_ROOT/package-hardlink"
copy_package "$HARDLINK_PACKAGE"
ln "$HARDLINK_PACKAGE/01-voiceover-approval-ax.txt" "$TEMP_ROOT/ax-hardlink"
expect_package_rejected "$HARDLINK_PACKAGE" "a multiply linked AX capture"
rm "$TEMP_ROOT/ax-hardlink"

EXTRA_PACKAGE="$TEMP_ROOT/package-extra"
copy_package "$EXTRA_PACKAGE"
printf 'unexpected\n' >"$EXTRA_PACKAGE/EXTRA"
chmod 400 "$EXTRA_PACKAGE/EXTRA"
expect_package_rejected "$EXTRA_PACKAGE" "an unexpected package file"

FRAME_PACKAGE="$TEMP_ROOT/package-frame"
copy_package "$FRAME_PACKAGE"
chmod 600 "$FRAME_PACKAGE/07-reduce-motion-frame-b.jpeg"
printf '\001' >>"$FRAME_PACKAGE/07-reduce-motion-frame-b.jpeg"
chmod 400 "$FRAME_PACKAGE/07-reduce-motion-frame-b.jpeg"
expect_package_rejected "$FRAME_PACKAGE" "a changed Reduce Motion frame"

BAD_CAPTURE="$TEMP_ROOT/capture-bad-ax"
mkdir "$BAD_CAPTURE"
chmod 700 "$BAD_CAPTURE"
cp "$FIXTURE_CAPTURE"/* "$BAD_CAPTURE"/
chmod 600 "$BAD_CAPTURE"/*
sed '/仅允许一次/d' "$FIXTURE_CAPTURE/01-voiceover-approval-ax.txt" \
  >"$BAD_CAPTURE/01-voiceover-approval-ax.txt"
BAD_OUTPUT="$TEMP_ROOT/package-bad-ax"
mkdir "$BAD_OUTPUT"
chmod 700 "$BAD_OUTPUT"
if "$PACKAGER" \
  --repository "$PWD" \
  --capture-dir "$BAD_CAPTURE" \
  --debug-app "$FIXTURE_APP" \
  --restoration-state "$FIXTURE_RESTORATION" \
  --output "$BAD_OUTPUT" \
  --started-at 2026-08-30T06:34:59Z \
  --finished-at 2026-08-30T06:38:18Z \
  --confirm-voiceover-observation real_process_operator_observed \
  --confirm-keyboard-sequence command_d_then_command_return_operator_observed >/dev/null 2>&1; then
  fail "system accessibility packager accepted an incomplete approval AX sequence"
fi
test ! -e "$BAD_OUTPUT/ACCEPTED" \
  || fail "rejected system accessibility capture produced an ACCEPTED marker"

BAD_RESTORATION="$TEMP_ROOT/restoration-bad.txt"
sed 's/increase_contrast=off/increase_contrast=on/' "$FIXTURE_RESTORATION" >"$BAD_RESTORATION"
chmod 600 "$BAD_RESTORATION"
BAD_RESTORE_OUTPUT="$TEMP_ROOT/package-bad-restoration"
mkdir "$BAD_RESTORE_OUTPUT"
chmod 700 "$BAD_RESTORE_OUTPUT"
if "$PACKAGER" \
  --repository "$PWD" \
  --capture-dir "$FIXTURE_CAPTURE" \
  --debug-app "$FIXTURE_APP" \
  --restoration-state "$BAD_RESTORATION" \
  --output "$BAD_RESTORE_OUTPUT" \
  --started-at 2026-08-30T06:34:59Z \
  --finished-at 2026-08-30T06:38:18Z \
  --confirm-voiceover-observation real_process_operator_observed \
  --confirm-keyboard-sequence command_d_then_command_return_operator_observed >/dev/null 2>&1; then
  fail "system accessibility packager accepted an unrestored system setting"
fi
test ! -e "$BAD_RESTORE_OUTPUT/ACCEPTED" \
  || fail "unrestored system accessibility capture produced an ACCEPTED marker"

echo "System accessibility evidence, user-environment isolation, and attack fixtures: PASS"
