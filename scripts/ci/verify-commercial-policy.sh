#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

VERIFIER="scripts/release/verify-commercial-policy.rb"
POLICY="scripts/commerce/commercial-policy.json"

fail() {
  echo "::error::$1" >&2
  exit 1
}

test -x "$VERIFIER" || fail "Commercial policy verifier is missing"
test -s "$POLICY" || fail "Commercial policy record is missing"

TEMP_DIR="$(mktemp -d -t dev-island-commercial-policy)"
case "$TEMP_DIR" in
  /private/var/folders/*/T/dev-island-commercial-policy.*|/var/folders/*/T/dev-island-commercial-policy.*|/tmp/dev-island-commercial-policy.*) ;;
  *) fail "Refusing to use unexpected temporary path" ;;
esac
trap 'rm -rf "$TEMP_DIR"' EXIT

expect_failure() {
  local name="$1"
  local expected="$2"
  shift 2
  if "$@" >"$TEMP_DIR/$name.output" 2>&1; then
    fail "$name unexpectedly passed"
  fi
  rg -Fq "$expected" "$TEMP_DIR/$name.output" \
    || fail "$name failed for the wrong reason"
  if rg -Fq "$TEMP_DIR" "$TEMP_DIR/$name.output"; then
    fail "$name leaked a fixture path"
  fi
}

make_case() {
  local name="$1"
  local path="$TEMP_DIR/$name.json"
  cp "$POLICY" "$path"
  echo "$path"
}

make_approved() {
  local path="$1"
  ruby -r json - "$path" <<'RUBY'
path = ARGV.fetch(0)
policy = JSON.parse(File.binread(path))
policy["decisionState"] = "approved"
policy["approval"] = {
  "reviewedAt" => "2026-08-27T00:00:00Z",
  "reviewedBy" => "Fixture reviewer",
  "legalReviewReference" => "FIXTURE-LEGAL-0001",
}
policy["seller"] = {
  "model" => "merchant-of-record",
  "legalName" => "Fixture Seller",
  "jurisdiction" => "US",
  "supportContact" => "support@example.invalid",
}
policy["provider"] = {
  "id" => "fixture-provider",
  "checkoutOrigin" => "https://checkout.example.invalid",
  "webhookOrigin" => "https://api.example.invalid",
  "activationOrigin" => "https://licenses.example.invalid",
  "dataResidency" => "Fixture region",
  "retentionDays" => 30,
}
policy["offer"] = {
  "licenseModel" => "one-time",
  "priceMinorUnits" => 2_999,
  "currency" => "USD",
  "trialMode" => "time-limited",
  "trialDays" => 7,
  "trialStart" => "first-launch",
  "updatePolicy" => "time-limited",
  "includedUpdateMonths" => 12,
  "supportPolicy" => "best-effort",
}
policy["access"] = {
  "deviceLimit" => 3,
  "deviceIdentity" => "random-install-id",
  "transferPolicy" => "self-service",
  "reinstallPolicy" => "restore-existing",
  "offlineGraceDays" => 30,
  "recoveryPolicy" => "provider-account",
}
policy["lifecycle"] = {
  "refundDays" => 14,
  "cancellationPolicy" => "not-applicable",
  "refundEffect" => "end-of-grace",
  "chargebackEffect" => "immediate",
}
policy["legal"] = {
  "salesRegions" => ["CA", "US"],
  "termsVersion" => "fixture-terms-v1",
  "privacyVersion" => "fixture-privacy-v1",
  "mitRelationship" => "mit-distribution",
}
File.binwrite(path, JSON.pretty_generate(policy) + "\n")
RUBY
}

"$VERIFIER" --policy "$POLICY" >/dev/null
expect_failure require-approved \
  "commercial launch blocked by unapproved policy record" \
  "$VERIFIER" --policy "$POLICY" --require-approved

APPROVED="$(make_case approved)"
make_approved "$APPROVED"
"$VERIFIER" --policy "$APPROVED" --require-approved >/dev/null

UNKNOWN_FIELD="$(make_case unknown-field)"
ruby -r json - "$UNKNOWN_FIELD" <<'RUBY'
path = ARGV.fetch(0)
policy = JSON.parse(File.binread(path))
policy["unexpected"] = true
File.binwrite(path, JSON.pretty_generate(policy) + "\n")
RUBY
expect_failure unknown-field \
  "commercial policy record has unknown or missing fields" \
  "$VERIFIER" --policy "$UNKNOWN_FIELD"

INCOMPLETE="$(make_case incomplete-approved)"
ruby -r json - "$INCOMPLETE" <<'RUBY'
path = ARGV.fetch(0)
policy = JSON.parse(File.binread(path))
policy["decisionState"] = "approved"
File.binwrite(path, JSON.pretty_generate(policy) + "\n")
RUBY
expect_failure incomplete-approved \
  "approved commercial policy is incomplete" \
  "$VERIFIER" --policy "$INCOMPLETE"

HTTP_ORIGIN="$(make_case http-origin)"
make_approved "$HTTP_ORIGIN"
ruby -r json - "$HTTP_ORIGIN" <<'RUBY'
path = ARGV.fetch(0)
policy = JSON.parse(File.binread(path))
policy.fetch("provider")["activationOrigin"] = "http://licenses.example.invalid"
File.binwrite(path, JSON.pretty_generate(policy) + "\n")
RUBY
expect_failure http-origin \
  "commercial activation origin must be a credential-free HTTPS origin" \
  "$VERIFIER" --policy "$HTTP_ORIGIN"

CREDENTIALED_ORIGIN="$(make_case credentialed-origin)"
make_approved "$CREDENTIALED_ORIGIN"
ruby -r json - "$CREDENTIALED_ORIGIN" <<'RUBY'
path = ARGV.fetch(0)
policy = JSON.parse(File.binread(path))
policy.fetch("provider")["checkoutOrigin"] = "https://token@checkout.example.invalid"
File.binwrite(path, JSON.pretty_generate(policy) + "\n")
RUBY
expect_failure credentialed-origin \
  "commercial checkout origin must be a credential-free HTTPS origin" \
  "$VERIFIER" --policy "$CREDENTIALED_ORIGIN"

HARDWARE_ID="$(make_case hardware-id)"
make_approved "$HARDWARE_ID"
ruby -r json - "$HARDWARE_ID" <<'RUBY'
path = ARGV.fetch(0)
policy = JSON.parse(File.binread(path))
policy.fetch("access")["deviceIdentity"] = "hardware-fingerprint"
File.binwrite(path, JSON.pretty_generate(policy) + "\n")
RUBY
expect_failure hardware-id \
  "commercial device identity is invalid" \
  "$VERIFIER" --policy "$HARDWARE_ID"

INCOHERENT_TRIAL="$(make_case incoherent-trial)"
make_approved "$INCOHERENT_TRIAL"
ruby -r json - "$INCOHERENT_TRIAL" <<'RUBY'
path = ARGV.fetch(0)
policy = JSON.parse(File.binread(path))
policy.fetch("offer")["trialMode"] = "none"
File.binwrite(path, JSON.pretty_generate(policy) + "\n")
RUBY
expect_failure incoherent-trial \
  "commercial no-trial policy must not carry trial timing" \
  "$VERIFIER" --policy "$INCOHERENT_TRIAL"

INVALID_PRICE="$(make_case invalid-price)"
make_approved "$INVALID_PRICE"
ruby -r json - "$INVALID_PRICE" <<'RUBY'
path = ARGV.fetch(0)
policy = JSON.parse(File.binread(path))
policy.fetch("offer")["priceMinorUnits"] = 0
File.binwrite(path, JSON.pretty_generate(policy) + "\n")
RUBY
expect_failure invalid-price \
  "commercial price is invalid" \
  "$VERIFIER" --policy "$INVALID_PRICE"

SYMLINK="$TEMP_DIR/symlink.json"
ln -s "$POLICY" "$SYMLINK"
expect_failure symlink \
  "commercial policy record must not be a symbolic link" \
  "$VERIFIER" --policy "$SYMLINK"

HARD_LINK_SOURCE="$(make_case hard-link-source)"
HARD_LINK="$TEMP_DIR/hard-link.json"
ln "$HARD_LINK_SOURCE" "$HARD_LINK"
expect_failure hard-link \
  "commercial policy record must have exactly one hard link" \
  "$VERIFIER" --policy "$HARD_LINK"

UNSAFE_MODE="$(make_case unsafe-mode)"
chmod 0666 "$UNSAFE_MODE"
expect_failure unsafe-mode \
  "commercial policy record permissions are unsafe" \
  "$VERIFIER" --policy "$UNSAFE_MODE"

EMPTY="$TEMP_DIR/empty.json"
ruby - "$EMPTY" <<'RUBY'
File.binwrite(ARGV.fetch(0), "")
RUBY
expect_failure empty \
  "commercial policy record size is invalid" \
  "$VERIFIER" --policy "$EMPTY"

OVERSIZED="$TEMP_DIR/oversized.json"
ruby - "$OVERSIZED" <<'RUBY'
File.binwrite(ARGV.fetch(0), "x" * 131_073)
RUBY
expect_failure oversized \
  "commercial policy record size is invalid" \
  "$VERIFIER" --policy "$OVERSIZED"

DIRECTORY="$TEMP_DIR/directory.json"
mkdir "$DIRECTORY"
expect_failure directory \
  "commercial policy record must be a regular file" \
  "$VERIFIER" --policy "$DIRECTORY"

REAL_PARENT="$TEMP_DIR/real-parent"
PARENT_LINK="$TEMP_DIR/parent-link"
mkdir "$REAL_PARENT"
cp "$POLICY" "$REAL_PARENT/policy.json"
ln -s "$REAL_PARENT" "$PARENT_LINK"
expect_failure parent-symlink \
  "commercial policy parent directory is unsafe" \
  "$VERIFIER" --policy "$PARENT_LINK/policy.json"

DUPLICATE_ROOT="$TEMP_DIR/duplicate-root.json"
ruby -r json - "$POLICY" "$DUPLICATE_ROOT" <<'RUBY'
source, destination = ARGV
policy = File.binread(source)
policy = policy.sub(
  %Q{  "decisionState": "required",\n},
  %Q{  "decisionState": "approved",\n  "decisionState": "required",\n}
)
File.binwrite(destination, policy)
RUBY
expect_failure duplicate-root \
  "commercial policy record contains a duplicate JSON key" \
  "$VERIFIER" --policy "$DUPLICATE_ROOT"

DUPLICATE_NESTED="$TEMP_DIR/duplicate-nested.json"
ruby -r json - "$APPROVED" "$DUPLICATE_NESTED" <<'RUBY'
source, destination = ARGV
policy = File.binread(source)
policy = policy.sub(
  %Q{    "priceMinorUnits": 2999,\n},
  %Q{    "priceMinorUnits": 1,\n    "priceMinorUnits": 2999,\n}
)
File.binwrite(destination, policy)
RUBY
expect_failure duplicate-nested \
  "commercial policy record contains a duplicate JSON key" \
  "$VERIFIER" --policy "$DUPLICATE_NESTED" --require-approved

RACE_TARGET="$(make_case replaced-during-read)"
RACE_REPLACEMENT="$(make_case replacement)"
make_approved "$RACE_REPLACEMENT"
SWAP_HOOK="$TEMP_DIR/swap-policy-on-read.rb"
SWAP_HOOK="$SWAP_HOOK" ruby <<'RUBY'
require "fileutils"

hook_path = ENV.fetch("SWAP_HOOK")
hook = <<~'HOOK'
  require "fileutils"

  class File
    alias_method :dev_island_original_read, :read

    def read(*arguments)
      target = ENV["DEV_ISLAND_POLICY_SWAP_TARGET"]
      replacement = ENV["DEV_ISLAND_POLICY_SWAP_REPLACEMENT"]
      reads_target = target && File.expand_path(path) == File.expand_path(target)
      if reads_target && replacement && !ENV.key?("DEV_ISLAND_POLICY_SWAP_COMPLETE")
        ENV["DEV_ISLAND_POLICY_SWAP_COMPLETE"] = "1"
        File.rename(target, "#{target}.displaced")
        FileUtils.cp(replacement, target)
      end
      dev_island_original_read(*arguments)
    end
  end
HOOK
File.binwrite(hook_path, hook)
RUBY
if DEV_ISLAND_POLICY_SWAP_TARGET="$RACE_TARGET" \
   DEV_ISLAND_POLICY_SWAP_REPLACEMENT="$RACE_REPLACEMENT" \
   /usr/bin/ruby -r "$SWAP_HOOK" "$VERIFIER" --policy "$RACE_TARGET" \
   >"$TEMP_DIR/replaced-during-read.output" 2>&1; then
  fail "replaced-during-read unexpectedly passed"
fi
rg -Fq "commercial policy record changed during inspection" \
  "$TEMP_DIR/replaced-during-read.output" \
  || fail "replaced-during-read failed for the wrong reason"
if rg -Fq "$TEMP_DIR" "$TEMP_DIR/replaced-during-read.output"; then
  fail "replaced-during-read leaked a fixture path"
fi

echo "Commercial policy fixtures: PASS"
