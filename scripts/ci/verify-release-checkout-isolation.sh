#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

VALIDATOR="scripts/release/verify-workflow-checkout-isolation.rb"
WORKFLOW=".github/workflows/release.yml"

fail() {
  echo "::error::$1" >&2
  exit 1
}

test -x "$VALIDATOR" || fail "Release checkout-isolation validator is not executable"
"$VALIDATOR" --workflow "$WORKFLOW" >/dev/null \
  || fail "Current Release checkout credential boundary failed"

TEMP_ROOT="$(mktemp -d -t dev-island-release-checkout-isolation)"
case "$TEMP_ROOT" in
  /private/var/folders/*/T/dev-island-release-checkout-isolation.*|/var/folders/*/T/dev-island-release-checkout-isolation.*|/tmp/dev-island-release-checkout-isolation.*) ;;
  *) fail "Refusing to use an unexpected temporary path" ;;
esac
cleanup() {
  case "$TEMP_ROOT" in
    /private/var/folders/*/T/dev-island-release-checkout-isolation.*|/var/folders/*/T/dev-island-release-checkout-isolation.*|/tmp/dev-island-release-checkout-isolation.*)
      rm -rf "$TEMP_ROOT"
      ;;
  esac
}
trap cleanup EXIT

mutate_fixture() {
  local mode="$1"
  local output="$TEMP_ROOT/$mode.yml"
  ruby - "$WORKFLOW" "$output" "$mode" <<'RUBY'
source_path, output_path, mode = ARGV
source = File.binread(source_path)
case mode
when "missing-persistence-policy"
  changed = source.sub!(
    /        with:\n(?:          #.*\n){3}          persist-credentials: false\n/,
    ""
  )
when "persisted-credentials"
  changed = source.sub!("          persist-credentials: false\n", "          persist-credentials: true\n")
when "checkout-token-override"
  changed = source.sub!(
    "          persist-credentials: false\n",
    "          persist-credentials: false\n          token: ${{ secrets.GITHUB_TOKEN }}\n"
  )
when "early-token-environment"
  changed = source.sub!(
    "      - name: Repository release gates\n        run: |\n",
    "      - name: Repository release gates\n        env:\n          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}\n        run: |\n"
  )
when "early-pat-environment"
  changed = source.sub!(
    "      - name: Repository release gates\n        run: |\n",
    "      - name: Repository release gates\n        env:\n          RELEASE_PAT: ${{ secrets.RELEASE_PAT }}\n        run: |\n"
  )
when "publication-token-missing"
  changed = source.sub!(
    "        env:\n          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}\n\n      # Always clean up",
    "\n      # Always clean up"
  )
else
  abort "unknown fixture mode"
end
abort "fixture mutation did not match" unless changed
File.binwrite(output_path, source)
RUBY
  printf '%s\n' "$output"
}

expect_rejected() {
  local fixture="$1"
  local label="$2"
  ruby - "$fixture" <<'RUBY' >/dev/null
require "yaml"
document = YAML.safe_load(
  File.binread(ARGV.fetch(0)),
  permitted_classes: [],
  permitted_symbols: [],
  aliases: false
)
abort "fixture is not a YAML mapping" unless document.is_a?(Hash)
RUBY
  if "$VALIDATOR" --workflow "$fixture" >/dev/null 2>&1; then
    fail "Release checkout validator accepted $label"
  fi
}

for mode in \
  missing-persistence-policy \
  persisted-credentials \
  checkout-token-override \
  early-token-environment \
  early-pat-environment \
  publication-token-missing; do
  fixture="$(mutate_fixture "$mode")"
  expect_rejected "$fixture" "$mode"
done

ln -s "$ROOT/$WORKFLOW" "$TEMP_ROOT/symlink.yml"
expect_rejected "$TEMP_ROOT/symlink.yml" "a symbolic-link workflow"

echo "Release checkout credential isolation fixtures: PASS"
