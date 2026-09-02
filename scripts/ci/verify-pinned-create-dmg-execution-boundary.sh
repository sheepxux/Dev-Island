#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
PREPARER="$ROOT/scripts/release/prepare-pinned-create-dmg.sh"
RUNNER="$ROOT/scripts/release/run-pinned-create-dmg.rb"

fail() {
  printf 'verify-pinned-create-dmg-execution-boundary: %s\n' "$1" >&2
  exit 1
}

TEMP_ROOT="$(mktemp -d -t dev-island-create-dmg-exec)"
cleanup() {
  chmod -R u+rwX "$TEMP_ROOT" 2>/dev/null || true
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT
mkdir -m 700 \
  "$TEMP_ROOT/runner-temp" \
  "$TEMP_ROOT/anonymous-home" \
  "$TEMP_ROOT/anonymous-temp"

test -x "$PREPARER" || fail "preparer is unavailable"
test -x "$RUNNER" || fail "descriptor-bound runner is unavailable"

PREPARED="$(RUNNER_TEMP="$TEMP_ROOT/runner-temp" "$PREPARER")"
IFS=$'\t' read -r TOOL_ROOT TOOL_MANIFEST <<<"$PREPARED"
[[ -n "$TOOL_ROOT" && -n "$TOOL_MANIFEST" ]] \
  || fail "preparer did not return the runtime closure"

# Prove that Ruby exec and the child Bash preserve both anonymous support
# descriptors, then consume every byte from each descriptor after exec.
SUPPORT_OUTPUT="$(
  HOME="$TEMP_ROOT/anonymous-home" \
  TMPDIR="$TEMP_ROOT/anonymous-temp" \
  ruby - "$RUNNER" "$TOOL_ROOT" "$TOOL_MANIFEST" <<'RUBY'
launcher, tool_root, manifest = ARGV
require launcher

closure = PinnedCreateDMGTool.verify(root: tool_root, manifest: manifest)
temp_directory = PinnedCreateDMGRunner.private_runtime_directory("TMPDIR")
home_directory = PinnedCreateDMGRunner.private_runtime_directory("HOME")
template_sha = PinnedCreateDMGTool::EXPECTED_FILES.fetch(
  "support/template.applescript"
).fetch(:sha256)
eula_sha = PinnedCreateDMGTool::EXPECTED_FILES.fetch(
  "support/eula-resources-template.xml"
).fetch(:sha256)
probe = <<~BASH
  #!/usr/bin/env bash
  set -euo pipefail
  template_sha="$(/usr/bin/shasum -a 256 <&"${DEV_ISLAND_CREATE_DMG_TEMPLATE_FD}" | /usr/bin/awk '{print $1}')"
  eula_sha="$(/usr/bin/shasum -a 256 <&"${DEV_ISLAND_CREATE_DMG_EULA_TEMPLATE_FD}" | /usr/bin/awk '{print $1}')"
  test "$template_sha" = "#{template_sha}"
  test "$eula_sha" = "#{eula_sha}"
  printf 'support descriptors inherited and verified\n'
BASH

runtimes = {
  script: PinnedCreateDMGRunner.anonymous_verified_file(
    probe.b,
    "support-probe",
    temp_directory
  ),
  template: PinnedCreateDMGRunner.anonymous_verified_file(
    closure.fetch("support/template.applescript"),
    "probe-template",
    temp_directory
  ),
  eula_template: PinnedCreateDMGRunner.anonymous_verified_file(
    closure.fetch("support/eula-resources-template.xml"),
    "probe-eula-template",
    temp_directory
  )
}
environment = PinnedCreateDMGRunner.execution_environment(
  home_directory: home_directory,
  temp_directory: temp_directory,
  template_fd: runtimes.fetch(:template).fileno,
  eula_template_fd: runtimes.fetch(:eula_template).fileno
)
exec(
  environment,
  "/bin/bash",
  "/dev/fd/#{runtimes.fetch(:script).fileno}",
  unsetenv_others: true
)
RUBY
)"
[[ "$SUPPORT_OUTPUT" == "support descriptors inherited and verified" ]] \
  || fail "Bash did not inherit and consume both verified support descriptors"

if HOME="$TEMP_ROOT/anonymous-home" \
   TMPDIR="$TEMP_ROOT/anonymous-temp" \
   "$RUNNER" \
     --root "$TOOL_ROOT" \
     --executable "$TOOL_ROOT/not-create-dmg" \
     --manifest "$TOOL_MANIFEST" \
     -- --pure-version \
     >"$TEMP_ROOT/mismatched-executable.stdout" \
     2>"$TEMP_ROOT/mismatched-executable.stderr"; then
  fail "runner accepted an executable output outside the verified member"
fi
rg -Fq \
  "executable path must be the create-dmg member of the verified root" \
  "$TEMP_ROOT/mismatched-executable.stderr" \
  || fail "runner did not explain the rejected executable output"

# This replacement is intentionally outside the verified work root so the
# attack can atomically rename it over the pathname immediately after the
# verifier returns.
mkdir -m 700 "$TEMP_ROOT/malicious-tool"
printf '%s\n' '#!/usr/bin/env bash' 'printf '\''PATHNAME ATTACK EXECUTED\n'\''' \
  > "$TEMP_ROOT/malicious-tool/create-dmg"
chmod 500 "$TEMP_ROOT/malicious-tool/create-dmg"

OUTPUT="$(
  HOME="$TEMP_ROOT/anonymous-home" \
  TMPDIR="$TEMP_ROOT/anonymous-temp" \
  ruby - \
    "$RUNNER" "$TOOL_ROOT" "$TOOL_MANIFEST" "$TEMP_ROOT/malicious-tool" <<'RUBY'
launcher, tool_root, manifest, replacement = ARGV
require launcher

verified_tool = PinnedCreateDMGTool.method(:verify)
PinnedCreateDMGTool.define_singleton_method(:verify) do |root:, manifest:|
  closure = verified_tool.call(root: root, manifest: manifest)
  # The attacker owns the directory, so it can first make the read-only tool
  # root writable. macOS refuses to rename a directory whose own mode denies
  # writing (EACCES on the release runner), and the verifier has already
  # returned, so this does not weaken what the fixture proves.
  File.chmod(0o700, root)
  File.rename(root, "#{root}.verified")
  File.rename(replacement, root)
  closure
end

exit PinnedCreateDMGRunner.run([
  "--root", tool_root,
  "--executable", File.join(tool_root, "create-dmg"),
  "--manifest", manifest,
  "--",
  "--pure-version"
])
RUBY
)"

[[ "$OUTPUT" == "1.3.0" ]] \
  || fail "runner did not execute the descriptor-verified script bytes"
[[ "$("$TOOL_ROOT/create-dmg")" == "PATHNAME ATTACK EXECUTED" ]] \
  || fail "fixture did not replace the old executable pathname"

# The exact descriptor-support transform is itself pinned and must remain a
# syntactically valid Bash program.
ruby - "$RUNNER" "$TOOL_ROOT.verified/create-dmg" "$TEMP_ROOT/transformed.sh" <<'RUBY'
launcher, upstream_path, output_path = ARGV
require launcher
upstream = File.binread(upstream_path)
derived = PinnedCreateDMGRunner.execution_script(upstream)
abort "support pathname survived the descriptor transform" if derived.include?(
  '$CDMG_SUPPORT_DIR/template.applescript'
)
abort "EULA support pathname survived the descriptor transform" if derived.include?(
  '${CDMG_SUPPORT_DIR}/eula-resources-template.xml'
)
abort "unbound AppleScript resource name survived the descriptor transform" if derived.include?(
  'template.applescript'
)
abort "unbound EULA resource name survived the descriptor transform" if derived.include?(
  'eula-resources-template.xml'
)
abort "unexpected support-directory use survived the descriptor transform" unless
  derived.scan('CDMG_SUPPORT_DIR').length == 4
File.binwrite(output_path, derived)
RUBY
/bin/bash -n "$TEMP_ROOT/transformed.sh"

echo "Pinned create-dmg execution-boundary fixtures: PASS"
