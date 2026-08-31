#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

RUNNER="scripts/release/run-sparkle-appcast-generator.sh"
FAKE_GENERATOR="scripts/ci/fixtures/fake-sparkle-appcast-generator.sh"

fail() {
  echo "::error::$1" >&2
  exit 1
}

test -x "$RUNNER" || fail "Sparkle secret-isolation runner is missing"
test -x "$FAKE_GENERATOR" || fail "Sparkle generator fixture is missing"

FIXTURE_ROOT="$(mktemp -d -t dev-island-sparkle-secret)"
case "$FIXTURE_ROOT" in
  /private/var/folders/*/T/dev-island-sparkle-secret.*|/var/folders/*/T/dev-island-sparkle-secret.*|/tmp/dev-island-sparkle-secret.*) ;;
  *) fail "Refusing unexpected Sparkle fixture root" ;;
esac
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

FEED_DIRECTORY="$FIXTURE_ROOT/feed"
EXPECTED_KEY="$FIXTURE_ROOT/expected-private-key.txt"
RUN_LOG="$FIXTURE_ROOT/run.log"
mkdir -m 0700 "$FEED_DIRECTORY"

fixture_private_key='fixture-private-key must exist only on stdin'
printf '%s' "$fixture_private_key" >"$EXPECTED_KEY"

APPLE_ID='fixture@example.invalid' \
APPLE_TEAM_ID='ABCDEFGHIJ' \
APPLE_APP_PASSWORD='fixture-apple-password' \
P12_BASE64='fixture-p12' \
P12_PASSWORD='fixture-p12-password' \
KEYCHAIN_PASSWORD='fixture-keychain-password' \
SPARKLE_PUBLIC_ED_KEY='fixture-public-key' \
SPARKLE_PRIVATE_ED_KEY="$fixture_private_key" \
  "$RUNNER" "$FAKE_GENERATOR" "$FEED_DIRECTORY" 'v9.8.7' \
  >"$RUN_LOG" 2>&1

cmp -s "$EXPECTED_KEY" "$FEED_DIRECTORY/observed-private-key.txt" \
  || fail "Sparkle private key did not reach the generator exactly through stdin"

for observed_file in \
  "$FEED_DIRECTORY/observed-arguments.txt" \
  "$FEED_DIRECTORY/observed-environment.txt" \
  "$FEED_DIRECTORY/observed-parent.txt" \
  "$RUN_LOG"; do
  if grep -Fq "$fixture_private_key" "$observed_file"; then
    fail "Sparkle private key escaped into generator metadata or output"
  fi
done

grep -Fq 'dev-island-sparkle-generator-supervisor' \
  "$FEED_DIRECTORY/observed-parent.txt" \
  || fail "Sparkle generator did not run below the clean parent supervisor"
if grep -Fq 'run-sparkle-appcast-generator.sh' \
  "$FEED_DIRECTORY/observed-parent.txt"; then
  fail "Sparkle secret-bearing wrapper remained the generator direct parent"
fi

for forbidden_name in \
  APPLE_ID \
  APPLE_TEAM_ID \
  APPLE_APP_PASSWORD \
  P12_BASE64 \
  P12_PASSWORD \
  KEYCHAIN_PASSWORD \
  SPARKLE_PUBLIC_ED_KEY \
  SPARKLE_PRIVATE_ED_KEY; do
  if grep -Eq "(^|[[:space:]])${forbidden_name}=" \
    "$FEED_DIRECTORY/observed-environment.txt" \
    "$FEED_DIRECTORY/observed-parent.txt"; then
    fail "Release credential remained visible to the Sparkle generator: ${forbidden_name}"
  fi
done

ARGUMENTS="$FEED_DIRECTORY/observed-arguments.txt"
grep -Fxq -- '--ed-key-file' "$ARGUMENTS" \
  || fail "Sparkle generator did not receive the stdin key-file option"
grep -Fxq -- '-' "$ARGUMENTS" \
  || fail "Sparkle generator key-file source is not stdin"
grep -Fxq -- 'https://github.com/sheepxux/Dev-Island/releases/download/v9.8.7/' "$ARGUMENTS" \
  || fail "Sparkle generator download prefix is not immutable"
grep -Fxq -- 'https://devisland.app' "$ARGUMENTS" \
  || fail "Sparkle generator product link drifted"
[[ "$(tail -n 1 "$ARGUMENTS")" == "$FEED_DIRECTORY" ]] \
  || fail "Sparkle generator did not receive the exact feed directory"

if env -u SPARKLE_PRIVATE_ED_KEY \
  "$RUNNER" "$FAKE_GENERATOR" "$FEED_DIRECTORY" 'v9.8.7' \
  >"$FIXTURE_ROOT/missing-secret.log" 2>&1; then
  fail "Sparkle runner accepted a missing private key"
fi
grep -Fq 'SPARKLE_PRIVATE_ED_KEY is required to sign updates' \
  "$FIXTURE_ROOT/missing-secret.log" \
  || fail "Sparkle missing-secret failure is not low-cardinality"

if SPARKLE_PRIVATE_ED_KEY="$fixture_private_key" \
  "$RUNNER" "$FAKE_GENERATOR" "$FEED_DIRECTORY" '../unsafe' \
  >"$FIXTURE_ROOT/unsafe-tag.log" 2>&1; then
  fail "Sparkle runner accepted an unsafe release tag"
fi

ln -s "$ROOT/$FAKE_GENERATOR" "$FIXTURE_ROOT/generator-link"
if SPARKLE_PRIVATE_ED_KEY="$fixture_private_key" \
  "$RUNNER" "$FIXTURE_ROOT/generator-link" "$FEED_DIRECTORY" 'v9.8.7' \
  >"$FIXTURE_ROOT/symlink-generator.log" 2>&1; then
  fail "Sparkle runner accepted a symbolic-link generator"
fi

echo "Sparkle release secret isolation: PASS"
