#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/release/verify-workflow-run-shells.rb"
RELEASE="$ROOT/.github/workflows/release.yml"
CI="$ROOT/.github/workflows/ci.yml"

fail() {
  echo "error: $1" >&2
  exit 1
}

test -x "$VALIDATOR" || fail "workflow run-shell validator is unavailable"

"$VALIDATOR" --workflow "$CI" >/dev/null
"$VALIDATOR" --workflow "$RELEASE" >/dev/null

FIXTURE_ROOT="$(mktemp -d -t dev-island-workflow-shells)"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

side_effect_workflow="$FIXTURE_ROOT/no-execution.yml"
side_effect_marker="$FIXTURE_ROOT/must-not-exist"
ruby -e '
  workflow, marker = ARGV
  File.binwrite(workflow, <<~YAML)
    name: Fixture
    jobs:
      test:
        runs-on: macos-15
        steps:
          - run: |
              printf "%s\\n" "${{ github.ref_name }}"
              printf "%s\\n" "$(touch "#{marker}")"
  YAML
' "$side_effect_workflow" "$side_effect_marker"
"$VALIDATOR" --workflow "$side_effect_workflow" >/dev/null
test ! -e "$side_effect_marker" \
  || fail "workflow syntax validation executed a run step"

reviewed_defaults="$FIXTURE_ROOT/reviewed-defaults.yml"
ruby -e '
  File.binwrite(ARGV.fetch(0), <<~YAML)
    name: Fixture
    defaults:
      run:
        shell: bash
    jobs:
      inherited:
        runs-on: macos-15
        steps:
          - run: echo workflow-default
      overridden:
        defaults:
          run:
            shell: /bin/bash
        runs-on: macos-15
        steps:
          - run: echo job-default
          - shell: bash
            run: echo step-override
  YAML
' "$reviewed_defaults"
"$VALIDATOR" --workflow "$reviewed_defaults" >/dev/null

expect_rejected() {
  local fixture="$1"
  local expected="$2"
  local output="$FIXTURE_ROOT/rejected.log"
  if "$VALIDATOR" --workflow "$fixture" >"$output" 2>&1; then
    fail "unsafe workflow fixture unexpectedly passed: $(basename "$fixture")"
  fi
  rg -Fq "$expected" "$output" \
    || fail "workflow fixture failed for the wrong reason: $(basename "$fixture")"
}

duplicate_if="$FIXTURE_ROOT/duplicate-if.yml"
cp "$RELEASE" "$duplicate_if"
ruby -e '
  path = ARGV.fetch(0)
  source = File.binread(path)
  line = %(          if [[ -z "${IDENTITY}" ]]; then\n)
  abort "fixture anchor missing" unless source.sub!(line, line + line)
  File.binwrite(path, source)
' "$duplicate_if"
expect_rejected "$duplicate_if" "workflow run shell syntax is invalid"

unterminated_quote="$FIXTURE_ROOT/unterminated-quote.yml"
cp "$CI" "$unterminated_quote"
ruby -e '
  path = ARGV.fetch(0)
  source = File.binread(path)
  abort "fixture anchor missing" unless source.sub!("          swift --version\n", "          echo \"unterminated\n")
  File.binwrite(path, source)
' "$unterminated_quote"
expect_rejected "$unterminated_quote" "workflow run shell syntax is invalid"

non_string="$FIXTURE_ROOT/non-string.yml"
ruby -e '
  File.binwrite(ARGV.fetch(0), <<~YAML)
    name: Fixture
    jobs:
      test:
        runs-on: macos-15
        steps:
          - run: 42
  YAML
' "$non_string"
expect_rejected "$non_string" "workflow run step must be a string"

unsupported_shell="$FIXTURE_ROOT/unsupported-shell.yml"
ruby -e '
  File.binwrite(ARGV.fetch(0), <<~YAML)
    name: Fixture
    jobs:
      test:
        runs-on: macos-15
        steps:
          - shell: pwsh
            run: Write-Output ok
  YAML
' "$unsupported_shell"
expect_rejected "$unsupported_shell" "workflow run step uses an unverified shell"

shell_template="$FIXTURE_ROOT/shell-template.yml"
ruby -e '
  File.binwrite(ARGV.fetch(0), <<~YAML)
    name: Fixture
    jobs:
      test:
        runs-on: macos-15
        steps:
          - shell: bash -c "printf hidden-command"
            run: echo apparently-safe
  YAML
' "$shell_template"
expect_rejected "$shell_template" "workflow run step uses an unverified shell"

workflow_default_shell="$FIXTURE_ROOT/workflow-default-shell.yml"
ruby -e '
  File.binwrite(ARGV.fetch(0), <<~YAML)
    name: Fixture
    defaults:
      run:
        shell: pwsh
    jobs:
      test:
        runs-on: macos-15
        steps:
          - run: echo apparently-safe
  YAML
' "$workflow_default_shell"
expect_rejected "$workflow_default_shell" "workflow run step uses an unverified shell: root/default"

job_default_shell="$FIXTURE_ROOT/job-default-shell.yml"
ruby -e '
  File.binwrite(ARGV.fetch(0), <<~YAML)
    name: Fixture
    jobs:
      test:
        defaults:
          run:
            shell: bash {0}
        runs-on: macos-15
        steps:
          - run: echo apparently-safe
  YAML
' "$job_default_shell"
expect_rejected "$job_default_shell" "workflow run step uses an unverified shell: test/default"

malformed_defaults="$FIXTURE_ROOT/malformed-defaults.yml"
ruby -e '
  File.binwrite(ARGV.fetch(0), <<~YAML)
    name: Fixture
    defaults:
      run: []
    jobs:
      test:
        runs-on: macos-15
        steps:
          - run: echo apparently-safe
  YAML
' "$malformed_defaults"
expect_rejected "$malformed_defaults" "workflow run defaults are malformed: root"

non_string_shell="$FIXTURE_ROOT/non-string-shell.yml"
ruby -e '
  File.binwrite(ARGV.fetch(0), <<~YAML)
    name: Fixture
    jobs:
      test:
        runs-on: macos-15
        steps:
          - shell: [bash]
            run: echo apparently-safe
  YAML
' "$non_string_shell"
expect_rejected "$non_string_shell" "workflow run step shell must be a string"

incomplete_expression="$FIXTURE_ROOT/incomplete-expression.yml"
ruby -e '
  File.binwrite(ARGV.fetch(0), <<~YAML)
    name: Fixture
    jobs:
      test:
        runs-on: macos-15
        steps:
          - run: echo "${{ github.ref_name }"
  YAML
' "$incomplete_expression"
expect_rejected "$incomplete_expression" "workflow run step contains an incomplete GitHub expression"

duplicate_key="$FIXTURE_ROOT/duplicate-key.yml"
ruby -e '
  File.binwrite(ARGV.fetch(0), <<~YAML)
    name: Fixture
    jobs:
      test:
        runs-on: macos-15
        steps:
          - run: |
              if true; then
            run: echo apparently-safe
  YAML
' "$duplicate_key"
expect_rejected "$duplicate_key" "workflow contains a duplicate mapping key"

resolved_duplicate_key="$FIXTURE_ROOT/resolved-duplicate-key.yml"
ruby -e '
  File.binwrite(ARGV.fetch(0), <<~YAML)
    name: Fixture
    on:
      push:
    true:
      pull_request:
    jobs:
      test:
        runs-on: macos-15
        steps:
          - run: echo apparently-safe
  YAML
' "$resolved_duplicate_key"
expect_rejected "$resolved_duplicate_key" "workflow contains a duplicate mapping key"

styled_duplicate_key="$FIXTURE_ROOT/styled-duplicate-key.yml"
ruby -e '
  File.binwrite(ARGV.fetch(0), <<~YAML)
    name: Fixture
    on:
      push:
    "on":
      pull_request:
    jobs:
      test:
        runs-on: macos-15
        steps:
          - run: echo apparently-safe
  YAML
' "$styled_duplicate_key"
expect_rejected "$styled_duplicate_key" "workflow contains a duplicate mapping key"

multiple_documents="$FIXTURE_ROOT/multiple-documents.yml"
ruby -e '
  File.binwrite(ARGV.fetch(0), <<~YAML)
    name: Fixture
    jobs:
      test:
        runs-on: macos-15
        steps:
          - run: echo apparently-safe
    ---
    jobs:
      hidden:
        runs-on: macos-15
        steps:
          - run: |
              if true; then
  YAML
' "$multiple_documents"
expect_rejected "$multiple_documents" "workflow must contain exactly one YAML document"

non_scalar_key="$FIXTURE_ROOT/non-scalar-key.yml"
ruby -e '
  File.binwrite(ARGV.fetch(0), <<~YAML)
    name: Fixture
    jobs:
      test:
        runs-on: macos-15
        steps:
          - ? [run]
            : echo apparently-safe
  YAML
' "$non_scalar_key"
expect_rejected "$non_scalar_key" "workflow mapping key must be a scalar"

excessive_depth="$FIXTURE_ROOT/excessive-depth.yml"
ruby -e '
  path = ARGV.fetch(0)
  padding = "[" * 130 + "x" + "]" * 130
  File.binwrite(path, <<~YAML)
    padding: #{padding}
    jobs:
      test:
        runs-on: macos-15
        steps:
          - run: echo apparently-safe
  YAML
' "$excessive_depth"
expect_rejected "$excessive_depth" "workflow YAML nesting is too deep"

excessive_nodes="$FIXTURE_ROOT/excessive-nodes.yml"
ruby -e '
  path = ARGV.fetch(0)
  padding = "  - x\n" * 20_000
  File.binwrite(path, "padding:\n#{padding}" + <<~YAML)
    jobs:
      test:
        runs-on: macos-15
        steps:
          - run: echo apparently-safe
  YAML
' "$excessive_nodes"
expect_rejected "$excessive_nodes" "workflow YAML structure is too large"

writable="$FIXTURE_ROOT/writable.yml"
cp "$CI" "$writable"
chmod 666 "$writable"
expect_rejected "$writable" "workflow permissions are unsafe"

hardlink_source="$FIXTURE_ROOT/hardlink-source.yml"
hardlink="$FIXTURE_ROOT/hardlink.yml"
cp "$CI" "$hardlink_source"
ln "$hardlink_source" "$hardlink"
expect_rejected "$hardlink" "workflow must have exactly one hard link"

symlink="$FIXTURE_ROOT/symlink.yml"
ln -s "$CI" "$symlink"
expect_rejected "$symlink" "workflow must not be a symbolic link"

echo "Workflow run-shell syntax fixtures: PASS"
