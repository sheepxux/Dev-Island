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
require "yaml"

source_path, output_path, mode = ARGV
workflow = YAML.safe_load(
  File.binread(source_path),
  permitted_classes: [],
  permitted_symbols: [],
  aliases: false
)
abort "workflow fixture root is malformed" unless workflow.is_a?(Hash)
job = workflow.fetch("jobs").fetch("build-sign-release")
steps = job.fetch("steps")

step_for = lambda do |name|
  matches = steps.select { |step| step["name"] == name }
  abort "expected one #{name} fixture step" unless matches.length == 1
  matches.first
end

case mode
when "missing-persistence-policy"
  checkout_with = step_for.call("Checkout").fetch("with")
  changed = checkout_with.key?("persist-credentials")
  checkout_with.delete("persist-credentials")
when "persisted-credentials"
  checkout_with = step_for.call("Checkout").fetch("with")
  changed = checkout_with["persist-credentials"] == false
  checkout_with["persist-credentials"] = true
when "checkout-token-override"
  checkout_with = step_for.call("Checkout").fetch("with")
  changed = !checkout_with.key?("token")
  checkout_with["token"] = "${{ secrets.GITHUB_TOKEN }}"
when "early-token-environment"
  gates = step_for.call("Repository release gates")
  changed = !gates.key?("env")
  gates["env"] = { "GITHUB_TOKEN" => "${{ secrets.GITHUB_TOKEN }}" }
when "early-pat-environment"
  gates = step_for.call("Repository release gates")
  changed = !gates.key?("env")
  gates["env"] = { "RELEASE_PAT" => "${{ secrets.RELEASE_PAT }}" }
when "publication-token-missing"
  changed = !step_for.call("Create GitHub Release").delete("env").nil?
when "workflow-apple-secret"
  environment = workflow["env"] ||= {}
  abort "workflow env fixture is malformed" unless environment.is_a?(Hash)
  changed = !environment.key?("INHERITED_APPLE_ID")
  environment["INHERITED_APPLE_ID"] = "${{ secrets.APPLE_ID }}"
when "job-apple-secret"
  environment = job["env"] ||= {}
  abort "job env fixture is malformed" unless environment.is_a?(Hash)
  changed = !environment.key?("INHERITED_APPLE_ID")
  environment["INHERITED_APPLE_ID"] = "${{ secrets.APPLE_ID }}"
when "job-apple-secret-bracket"
  environment = job["env"] ||= {}
  abort "job env fixture is malformed" unless environment.is_a?(Hash)
  changed = !environment.key?("INHERITED_APPLE_ID")
  environment["INHERITED_APPLE_ID"] = "${{ secrets['APPLE_ID'] }}"
when "workflow-whole-secret-context"
  environment = workflow["env"] ||= {}
  abort "workflow env fixture is malformed" unless environment.is_a?(Hash)
  changed = !environment.key?("INHERITED_SECRETS")
  environment["INHERITED_SECRETS"] = "${{ toJSON(secrets) }}"
when "job-bash-env"
  environment = job["env"] ||= {}
  abort "job env fixture is malformed" unless environment.is_a?(Hash)
  changed = !environment.key?("BASH_ENV")
  environment["BASH_ENV"] = "/tmp/unreviewed-release-bootstrap.sh"
when "workflow-custom-default-shell"
  changed = !workflow.key?("defaults")
  workflow["defaults"] = {
    "run" => { "shell" => "ruby ./scripts/release/unreviewed-shell.rb {0}" }
  }
when "job-custom-default-shell"
  changed = !job.key?("defaults")
  job["defaults"] = {
    "run" => { "shell" => "ruby ./scripts/release/unreviewed-shell.rb {0}" }
  }
when "package-secret"
  environment = step_for.call("Package DMG").fetch("env")
  changed = !environment.key?("APPLE_ID")
  environment["APPLE_ID"] = "${{ secrets.APPLE_ID }}"
when "package-secret-bracket"
  environment = step_for.call("Package DMG").fetch("env")
  changed = !environment.key?("APPLE_ID_BRACKET")
  environment["APPLE_ID_BRACKET"] = "${{ secrets['APPLE_ID'] }}"
when "package-whole-secret-context"
  environment = step_for.call("Package DMG").fetch("env")
  changed = !environment.key?("INHERITED_SECRETS")
  environment["INHERITED_SECRETS"] = "${{ toJSON(secrets) }}"
when "comment-package-reverify"
  package = step_for.call("Package DMG")
  lines = package.fetch("run").lines
  first = lines.index do |line|
    line.include?("./scripts/release/run-pinned-create-dmg.rb")
  end
  changed = !first.nil? &&
    lines.fetch(first + 1).include?("--root") &&
    lines.fetch(first + 2).include?("--executable") &&
    lines.fetch(first + 3).include?("--manifest") &&
    lines.fetch(first + 4).match?(/^\s*-- \\/)
  if changed
    (first..(first + 4)).each do |index|
      lines[index] = lines[index].sub(/\A(\s*)/, '\\1# ')
    end
    package["run"] = lines.join
  end
when "direct-package-pathname"
  package = step_for.call("Package DMG")
  lines = package.fetch("run").lines
  first = lines.index do |line|
    line.include?("./scripts/release/run-pinned-create-dmg.rb")
  end
  changed = !first.nil? &&
    lines.fetch(first + 1).include?("--root") &&
    lines.fetch(first + 2).include?("--executable") &&
    lines.fetch(first + 3).include?("--manifest") &&
    lines.fetch(first + 4).match?(/^\s*-- \\/)
  if changed
    indentation = lines.fetch(first)[/\A\s*/]
    lines[first, 5] = ["#{indentation}\"${CREATE_DMG_EXECUTABLE}\" \\\n"]
    package["run"] = lines.join
  end
when "comment-package-env-i"
  package = step_for.call("Package DMG")
  lines = package.fetch("run").lines
  index = lines.index { |line| line.include?("/usr/bin/env -i") }
  changed = !index.nil?
  lines[index] = lines[index].sub(/\A(\s*)/, '\\1# ') if changed
  package["run"] = lines.join
when "package-before-app-teardown"
  teardown_index = steps.index(step_for.call("Tear down App signing keychain"))
  package_index = steps.index(step_for.call("Package DMG"))
  changed = teardown_index < package_index
  steps[teardown_index], steps[package_index] = steps[package_index], steps[teardown_index] if changed
when "app-teardown-continue-on-error"
  teardown = step_for.call("Tear down App signing keychain")
  changed = !teardown.key?("continue-on-error")
  teardown["continue-on-error"] = true
when "third-party-during-app-keychain"
  setup_index = steps.index(step_for.call("Setup App signing keychain"))
  steps.insert(
    setup_index + 1,
    {
      "name" => "Unreviewed action fixture",
      "uses" => "example/unreviewed-action@#{'a' * 40}"
    }
  )
  changed = true
when "missing-dmg-keychain-setup"
  target = step_for.call("Setup DMG signing keychain")
  changed = !steps.delete(target).nil?
when "missing-dmg-keychain-teardown"
  target = step_for.call("Tear down DMG signing keychain")
  changed = !steps.delete(target).nil?
when "duplicate-package-step"
  package = step_for.call("Package DMG")
  package_index = steps.index(package)
  steps.insert(package_index + 1, Marshal.load(Marshal.dump(package)))
  changed = true
else
  abort "unknown fixture mode"
end
abort "fixture mutation did not match" unless changed
File.binwrite(output_path, YAML.dump(workflow))
RUBY
  printf '%s\n' "$output"
}

expect_rejected() {
  local fixture="$1"
  local label="$2"
  local expected="$3"
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
  local diagnostics
  if diagnostics="$("$VALIDATOR" --workflow "$fixture" 2>&1)"; then
    fail "Release checkout validator accepted $label"
  fi
  [[ "$diagnostics" == *"$expected"* ]] \
    || fail "Release checkout validator rejected $label for the wrong reason: $diagnostics"
}

for specification in \
  'missing-persistence-policy|persist-credentials' \
  'persisted-credentials|persist-credentials' \
  'checkout-token-override|must not override its token input' \
  'early-token-environment|GitHub token is exposed before final publication' \
  'early-pat-environment|GitHub token is exposed before final publication' \
  'publication-token-missing|must have one scoped token environment' \
  'workflow-apple-secret|workflow and release job environments must be absent' \
  'job-apple-secret|workflow and release job environments must be absent' \
  'job-apple-secret-bracket|workflow and release job environments must be absent' \
  'workflow-whole-secret-context|workflow and release job environments must be absent' \
  'job-bash-env|workflow and release job environments must be absent' \
  'workflow-custom-default-shell|workflow and release job run defaults must be absent' \
  'job-custom-default-shell|workflow and release job run defaults must be absent' \
  'package-secret|Package DMG step must not reference release secrets' \
  'package-secret-bracket|Package DMG step must not reference release secrets' \
  'package-whole-secret-context|Package DMG step must not reference release secrets' \
  'comment-package-reverify|Package DMG run body does not match the reviewed SHA-256' \
  'direct-package-pathname|Package DMG run body does not match the reviewed SHA-256' \
  'comment-package-env-i|Package DMG run body does not match the reviewed SHA-256' \
  'package-before-app-teardown|release signing boundary ordering is invalid' \
  'app-teardown-continue-on-error|Tear down App signing keychain step shape does not match the reviewed boundary' \
  'third-party-during-app-keychain|a third-party action must not run while the App signing keychain is available' \
  'missing-dmg-keychain-setup|must contain exactly one Setup DMG signing keychain step' \
  'missing-dmg-keychain-teardown|must contain exactly one Tear down DMG signing keychain step' \
  'duplicate-package-step|must contain exactly one Package DMG step'; do
  mode="${specification%%|*}"
  expected="${specification#*|}"
  fixture="$(mutate_fixture "$mode")"
  expect_rejected "$fixture" "$mode" "$expected"
done

ln -s "$ROOT/$WORKFLOW" "$TEMP_ROOT/symlink.yml"
expect_rejected \
  "$TEMP_ROOT/symlink.yml" \
  "a symbolic-link workflow" \
  "must be a regular non-symlink file"

echo "Release checkout credential isolation fixtures: PASS"
