#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$1" >&2
  exit 1
}

WORKFLOWS=(.github/workflows/ci.yml .github/workflows/release.yml)
CASK="dist/homebrew-island/Casks/dev-island.rb"
CASK_DOC="dist/homebrew-island/README.md"
RELEASE=".github/workflows/release.yml"
CREDENTIAL_VALIDATOR="scripts/ci/validate-release-credentials.sh"
CREATE_DMG_PREPARER="scripts/release/prepare-pinned-create-dmg.sh"
CREATE_DMG_TOOL_VERIFIER="scripts/release/verify-pinned-create-dmg-tool.rb"
CREATE_DMG_RUNNER="scripts/release/run-pinned-create-dmg.rb"
CREATE_DMG_ARCHIVE_VALIDATOR="scripts/release/validate-pinned-create-dmg-archive.rb"
CREATE_DMG_ARCHIVE_FIXTURES="scripts/ci/verify-pinned-create-dmg-archive.sh"
CREATE_DMG_EXECUTION_FIXTURES="scripts/ci/verify-pinned-create-dmg-execution-boundary.sh"
SPARKLE_SECRET_RUNNER="scripts/release/run-sparkle-appcast-generator.sh"
SPARKLE_SECRET_FIXTURES="scripts/ci/verify-sparkle-secret-isolation.sh"
INTEGRITY_GENERATOR="scripts/release/generate-release-integrity-manifest.sh"
SBOM_GENERATOR="scripts/release/generate-sbom.swift"
OPENCODE_LOGO="scripts/assets/agent-logos/opencode.svg"
OPENCODE_LOGO_LICENSE="scripts/licenses/opencode-MIT-LICENSE"
HOMEBREW_VERIFIER="scripts/ci/verify-homebrew-distribution.sh"
ASSET_VERIFIER="scripts/release/verify-release-assets.sh"
ASSET_VERIFIER_FIXTURES="scripts/ci/verify-release-asset-verifier.sh"
SPARKLE_SIGNATURE_VERIFIER="scripts/release/verify-sparkle-ed25519-signatures.swift"
SPARKLE_OLD_TO_NEW_GATE="scripts/ci/verify-sparkle-old-to-new-update.sh"
SPARKLE_LIVE_GATE_HELPER="scripts/qa/sparkle-live-gate-helper.rb"
PUBLISHED_RELEASE_VERIFIER="scripts/release/verify-published-release.sh"
PUBLISHED_RELEASE_METADATA_VALIDATOR="scripts/release/validate-published-release-metadata.rb"
BUNDLE_DEPENDENCY_VERIFIER="scripts/release/verify-app-bundle-dependencies.rb"
BUNDLE_DEPENDENCY_FIXTURES="scripts/ci/verify-app-bundle-dependencies.sh"
BRAND_ASSET_VERIFIER="scripts/release/verify-brand-assets.rb"
BRAND_ASSET_FIXTURES="scripts/ci/verify-brand-asset-inventory.sh"
BRAND_ASSET_MANIFEST="scripts/assets/agent-logos/manifest.json"
BRAND_TRADEMARK_REVIEWS="scripts/assets/agent-logos/trademark-reviews.json"
TRADEMARK_PACKET_GENERATOR="scripts/release/generate-trademark-review-packet.rb"
TRADEMARK_PACKET_FIXTURES="scripts/ci/verify-trademark-review-packet.sh"
APP_BUILD_OUTPUT_BOUNDARY="scripts/release/app-build-output-boundary.rb"
APP_BUILD_OUTPUT_FIXTURES="scripts/ci/verify-app-build-output-boundary.sh"
RELEASE_CHECKOUT_VALIDATOR="scripts/release/verify-workflow-checkout-isolation.rb"
RELEASE_CHECKOUT_FIXTURES="scripts/ci/verify-release-checkout-isolation.sh"
WORKFLOW_SHELL_VALIDATOR="scripts/release/verify-workflow-run-shells.rb"
WORKFLOW_SHELL_FIXTURES="scripts/ci/verify-workflow-shell-syntax.sh"
REPOSITORY_SCRIPT_VALIDATOR="scripts/release/verify-repository-script-syntax.rb"
REPOSITORY_SCRIPT_FIXTURES="scripts/ci/verify-repository-script-syntax.sh"
CI_WORKFLOW=".github/workflows/ci.yml"
VERSION="$(cat VERSION)"
ATTEST_ACTION="actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6"
RELEASE_ACTION="softprops/action-gh-release@efb35369e0ad2afab669f228072c1b0d510eae64"

for workflow in "${WORKFLOWS[@]}"; do
  while IFS= read -r use; do
    reference="${use##*@}"
    reference="${reference%% *}"
    [[ "$reference" =~ ^[0-9a-f]{40}$ ]] \
      || fail "GitHub Action must be pinned to a full commit SHA: $use"
  done < <(rg -o 'uses: [^[:space:]#]+@[^[:space:]#]+' "$workflow" || true)
done

test -x "$RELEASE_CHECKOUT_VALIDATOR" && test -x "$RELEASE_CHECKOUT_FIXTURES" \
  || fail "Release checkout credential validator or attack fixtures are missing"
"$RELEASE_CHECKOUT_FIXTURES" >/dev/null \
  || fail "Release checkout credential isolation fixtures failed"
for invariant in \
  'SECRET_EXPRESSION = /' \
  'PINNED_RUN_SHA256 = {' \
  'require_step_keys(' \
  'ordered_indexes.each_cons(2)' \
  'package_index == app_teardown_index + 1' \
  'dmg_teardown_index == dmg_sign_index + 1' \
  'package["env"] == PACKAGE_DMG_ENV' \
  'dmg_sign["id"] == "dmg" && dmg_sign["env"] == SIGN_DMG_ENV' \
  'Digest::SHA256.hexdigest(run.b)'; do
  rg -Fq "$invariant" "$RELEASE_CHECKOUT_VALIDATOR" \
    || fail "Structured release signing-boundary invariant missing: $invariant"
done
for fixture in \
  workflow-apple-secret \
  job-apple-secret \
  package-secret \
  comment-package-reverify \
  direct-package-pathname \
  comment-package-env-i \
  package-before-app-teardown \
  app-teardown-continue-on-error \
  third-party-during-app-keychain \
  missing-dmg-keychain-setup \
  missing-dmg-keychain-teardown; do
  rg -Fq "\"$fixture\"" "$RELEASE_CHECKOUT_FIXTURES" \
    || fail "Structured release signing-boundary attack fixture missing: $fixture"
done
test -x "$WORKFLOW_SHELL_VALIDATOR" && test -x "$WORKFLOW_SHELL_FIXTURES" \
  || fail "Workflow run-shell validator or attack fixtures are missing"
"$WORKFLOW_SHELL_FIXTURES" >/dev/null \
  || fail "Workflow run-shell syntax fixtures failed"
test -x "$REPOSITORY_SCRIPT_VALIDATOR" && test -x "$REPOSITORY_SCRIPT_FIXTURES" \
  || fail "Repository script syntax validator or attack fixtures are missing"
"$REPOSITORY_SCRIPT_FIXTURES" >/dev/null \
  || fail "Repository script syntax fixtures failed"
for invariant in \
  'MAX_SCRIPT_BYTES = 1_048_576' \
  'MAX_SCRIPT_COUNT = 256' \
  'MAX_TREE_ENTRIES = 4_096' \
  'File::RDONLY | File::NOFOLLOW | File::NONBLOCK' \
  '%i[dev ino uid mode nlink size mtime ctime]' \
  '"/bin/bash", ["-n"]' \
  '"/usr/bin/ruby", ["-c"]' \
  '"/usr/bin/swiftc", ["-parse", "-"]' \
  'unsetenv_others: true' \
  'directory_snapshots.each'; do
  rg -Fq "$invariant" "$REPOSITORY_SCRIPT_VALIDATOR" \
    || fail "Repository script syntax invariant missing: $invariant"
done
for invariant in \
  'MAX_YAML_NODES = 20_000' \
  'MAX_YAML_DEPTH = 128' \
  '%i[dev ino uid mode nlink size mtime ctime]' \
  'workflow must contain exactly one YAML document' \
  'workflow contains a duplicate mapping key' \
  'workflow mapping key must be a scalar' \
  'VERIFIED_SHELLS = %w[bash /bin/bash].freeze' \
  'workflow_default_shell = run_default_shell(workflow, "root")' \
  'job_default_shell = run_default_shell(job, job_label)' \
  'workflow run step shell must be a string'; do
  rg -Fq "$invariant" "$WORKFLOW_SHELL_VALIDATOR" \
    || fail "Workflow YAML ambiguity invariant missing: $invariant"
done

ci_workflow_shell_lines="$(rg -n './scripts/release/verify-workflow-run-shells\.rb' "$CI_WORKFLOW" | cut -d: -f1)"
ci_workflow_shell_count="$(wc -l <<<"$ci_workflow_shell_lines" | tr -d ' ')"
ci_workflow_shell_last_line="$(tail -1 <<<"$ci_workflow_shell_lines")"
ci_repository_script_lines="$(rg -n './scripts/release/verify-repository-script-syntax\.rb' "$CI_WORKFLOW" | cut -d: -f1)"
ci_repository_script_count="$(wc -l <<<"$ci_repository_script_lines" | tr -d ' ')"
ci_repository_script_line="$(tail -1 <<<"$ci_repository_script_lines")"
ci_dependency_line="$(rg -n 'name: Resolve dependencies' "$CI_WORKFLOW" | cut -d: -f1)"
ci_ripgrep_bootstrap_line="$(rg -nF 'HOMEBREW_NO_AUTO_UPDATE=1 brew install ripgrep' "$CI_WORKFLOW" | cut -d: -f1)"
[[ "$ci_workflow_shell_count" -eq 2 \
   && -n "$ci_workflow_shell_last_line" \
   && "$ci_repository_script_count" -eq 1 \
   && -n "$ci_repository_script_line" \
   && -n "$ci_dependency_line" \
   && -n "$ci_ripgrep_bootstrap_line" \
   && "$ci_ripgrep_bootstrap_line" -lt "$ci_workflow_shell_last_line" \
   && "$ci_workflow_shell_last_line" -lt "$ci_repository_script_line" \
   && "$ci_repository_script_line" -lt "$ci_dependency_line" ]] \
  || fail "PR CI must bootstrap ripgrep, then syntax-check workflows and repository scripts before dependency resolution"

gates_line="$(rg -n 'name: Repository release gates' "$RELEASE" | cut -d: -f1)"
version_line="$(rg -n 'name: Resolve version' "$RELEASE" | cut -d: -f1)"
create_dmg_prepare_line="$(rg -n 'name: Prepare pinned create-dmg' "$RELEASE" | cut -d: -f1)"
credential_line="$(rg -n 'name: Validate release credentials' "$RELEASE" | cut -d: -f1)"
app_keychain_line="$(rg -n 'name: Setup App signing keychain' "$RELEASE" | cut -d: -f1)"
app_build_line="$(rg -n 'name: Build \.app \(universal\)' "$RELEASE" | cut -d: -f1)"
checkout_guard_line="$(rg -n './scripts/release/verify-workflow-checkout-isolation\.rb' "$RELEASE" | cut -d: -f1)"
workflow_shell_guard_lines="$(rg -n './scripts/release/verify-workflow-run-shells\.rb' "$RELEASE" | cut -d: -f1)"
workflow_shell_guard_count="$(wc -l <<<"$workflow_shell_guard_lines" | tr -d ' ')"
workflow_shell_guard_first_line="$(head -1 <<<"$workflow_shell_guard_lines")"
workflow_shell_guard_last_line="$(tail -1 <<<"$workflow_shell_guard_lines")"
repository_script_guard_lines="$(rg -n './scripts/release/verify-repository-script-syntax\.rb' "$RELEASE" | cut -d: -f1)"
repository_script_guard_count="$(wc -l <<<"$repository_script_guard_lines" | tr -d ' ')"
repository_script_guard_line="$(tail -1 <<<"$repository_script_guard_lines")"
package_boundary_line="$(rg -n 'git ls-files --error-unmatch Package\.resolved' "$RELEASE" | cut -d: -f1)"
release_ripgrep_bootstrap_line="$(rg -nF 'HOMEBREW_NO_AUTO_UPDATE=1 brew install ripgrep' "$RELEASE" | cut -d: -f1)"
[[ -n "$gates_line" \
   && -n "$version_line" \
   && -n "$create_dmg_prepare_line" \
   && -n "$credential_line" \
   && -n "$app_keychain_line" \
   && -n "$app_build_line" \
   && -n "$checkout_guard_line" \
   && "$workflow_shell_guard_count" -eq 2 \
   && -n "$workflow_shell_guard_first_line" \
   && -n "$workflow_shell_guard_last_line" \
   && "$repository_script_guard_count" -eq 1 \
   && -n "$repository_script_guard_line" \
   && -n "$package_boundary_line" \
   && -n "$release_ripgrep_bootstrap_line" \
   && "$release_ripgrep_bootstrap_line" -lt "$gates_line" \
   && "$gates_line" -lt "$checkout_guard_line" \
   && "$checkout_guard_line" -lt "$workflow_shell_guard_first_line" \
   && "$workflow_shell_guard_last_line" -lt "$repository_script_guard_line" \
   && "$repository_script_guard_line" -lt "$package_boundary_line" \
   && "$gates_line" -lt "$version_line" \
   && "$version_line" -lt "$create_dmg_prepare_line" \
   && "$create_dmg_prepare_line" -lt "$credential_line" \
   && "$credential_line" -lt "$app_keychain_line" \
   && "$app_keychain_line" -lt "$app_build_line" ]] \
  || fail "Checkout isolation, release gates, pinned tooling, and credential preflight ordering is invalid"
for workflow in "$CI_WORKFLOW" "$RELEASE"; do
  for invariant in \
    'if ! command -v rg >/dev/null 2>&1; then' \
    'command -v brew >/dev/null 2>&1' \
    'HOMEBREW_NO_AUTO_UPDATE=1 brew install ripgrep' \
    'rg --version'; do
    [[ "$(rg -Fc "$invariant" "$workflow")" -eq 1 ]] \
      || fail "Workflow must bootstrap and identify ripgrep exactly once before repository gates: $workflow ($invariant)"
  done
done
credential_block="$(sed -n "${credential_line},$((app_keychain_line - 1))p" "$RELEASE")"
app_keychain_block="$(sed -n "${app_keychain_line},$((app_build_line - 1))p" "$RELEASE")"
create_dmg_prepare_block="$(sed -n "${create_dmg_prepare_line},$((credential_line - 1))p" "$RELEASE")"
release_gate_block="$(sed -n "${gates_line},$((credential_line - 1))p" "$RELEASE")"
test -x "$SPARKLE_OLD_TO_NEW_GATE" && test -x "$SPARKLE_LIVE_GATE_HELPER" \
  || fail "Sparkle old-to-new gate or bounded helper is unavailable"
rg -Fq './scripts/ci/verify-sparkle-old-to-new-update.sh' "$CI_WORKFLOW" \
  || fail "PR CI must execute the disposable Sparkle old-to-new gate"
rg -Fq './scripts/ci/verify-sparkle-old-to-new-update.sh' <<<"$release_gate_block" \
  || fail "Tagged releases must execute the disposable Sparkle old-to-new gate before credentials"
rg -Fq './scripts/ci/run-authoritative-tests.sh' "$RELEASE" \
  || fail "Tagged releases must run the isolated authoritative test suite"
rg -q 'verify-security-invariants\.sh' "$RELEASE" \
  || fail "Tagged releases must run repository security/privacy gates"
rg -Fq './scripts/release/verify-workflow-checkout-isolation.rb \' <<<"$release_gate_block" \
  || fail "Tagged releases must verify checkout credential isolation before repository code runs"
[[ "$(rg -Fc './scripts/release/verify-workflow-run-shells.rb \' <<<"$release_gate_block")" -eq 2 ]] \
  || fail "Tagged releases must syntax-check both workflows before loading credentials"
test -x "$APP_BUILD_OUTPUT_BOUNDARY" && test -x "$APP_BUILD_OUTPUT_FIXTURES" \
  || fail "App build output boundary or attack fixtures are missing"
rg -Fq 'app-build-output-boundary.rb' scripts/build-app.sh \
  || fail "Tagged App builds must prepare and publish through the output boundary"
if rg -Fq 'rm -rf "${APP}"' scripts/build-app.sh; then
  fail "Tagged App builds must never recursively delete the final App destination"
fi
rg -Fq './scripts/ci/verify-app-bundle-dependencies.sh' <<<"$release_gate_block" \
  || fail "Tagged releases must exercise app dependency attack fixtures before loading credentials"
rg -Fq './scripts/release/verify-brand-assets.rb' <<<"$release_gate_block" \
  || fail "Tagged releases must verify the complete brand asset inventory before loading credentials"
rg -Fq -- '--trademark-reviews scripts/assets/agent-logos/trademark-reviews.json' <<<"$release_gate_block" \
  || fail "Tagged releases must bind human trademark decisions before loading credentials"
rg -Fq -- '--require-release-reviewed' <<<"$release_gate_block" \
  || fail "Tagged releases must fail closed on pending brand provenance or trademark review"

test -x "$CREATE_DMG_PREPARER" \
  || fail "Pinned create-dmg preparer is missing or not executable"
test -x "$CREATE_DMG_TOOL_VERIFIER" \
  || fail "Descriptor-backed create-dmg runtime verifier is missing or not executable"
test -x "$CREATE_DMG_RUNNER" && test -x "$CREATE_DMG_EXECUTION_FIXTURES" \
  || fail "Descriptor-bound create-dmg runner or attack fixtures are missing"
test -x "$CREATE_DMG_ARCHIVE_VALIDATOR" && test -x "$CREATE_DMG_ARCHIVE_FIXTURES" \
  || fail "Pinned create-dmg archive validator or attack fixtures are missing"
"$CREATE_DMG_ARCHIVE_FIXTURES" >/dev/null \
  || fail "Pinned create-dmg archive attack fixtures failed"
"$CREATE_DMG_EXECUTION_FIXTURES" >/dev/null \
  || fail "Pinned create-dmg execution-boundary attack fixtures failed"
for invariant in \
  'readonly CREATE_DMG_VERSION="1.3.0"' \
  'readonly CREATE_DMG_COMMIT="a2b71d0fda6d0df2a86dc7f67082d4d73e84c59f"' \
  'readonly CREATE_DMG_ARCHIVE_URL="https://codeload.github.com/create-dmg/create-dmg/tar.gz/${CREATE_DMG_COMMIT}"' \
  'readonly CREATE_DMG_ARCHIVE_SHA256="36577b966f16c12dd78d5bb5107c2ae3d069b044226b6ebbffa6a434ce142d0a"' \
  'readonly CREATE_DMG_ARCHIVE_BYTES="48371"' \
  'readonly CREATE_DMG_SCRIPT_SHA256="bb9ea3194e55f2f76a821e87541513748d0fedc69f45cf4f0951cad15ae0cae5"' \
  'readonly CREATE_DMG_SENTINEL_SHA256="fb2494eb10146a84bbb20ebb198c2a09fb72aed119706dc55b6ec3644018383f"' \
  'readonly CREATE_DMG_TEMPLATE_SHA256="b5dd7c55ddaa5db1884ac5cf523c4413d452a75df967daf55b8d45ba501fe457"' \
  'readonly CREATE_DMG_EULA_TEMPLATE_SHA256="a804e533e9c99491a74cb4502c435b00d902dc7a45d3693057a29674e584a70b"' \
  '--proto '\''=https'\''' \
  '--tlsv1.2' \
  'downloaded archive SHA-256 does not match the reviewed commit' \
  'Parser-facing operations are deliberately delayed until the exact byte' \
  '--strip-components 1' \
  'verify_tool_root "$tool_root"' \
  '/usr/bin/env -i \' \
  'PATH="/usr/bin:/bin:/usr/sbin:/sbin" \' \
  'LC_ALL=C \' \
  '"$tool_root/create-dmg" --pure-version'; do
  rg -Fq -- "$invariant" "$CREATE_DMG_PREPARER" \
    || fail "Pinned create-dmg supply-chain invariant missing: $invariant"
done
[[ "$(rg -Fc '"$archive_validator" \' "$CREATE_DMG_PREPARER")" -eq 2 ]] \
  || fail "Pinned archive must be descriptor-validated before and after extraction"
for invariant in \
  '--archive-sha256 "$CREATE_DMG_ARCHIVE_SHA256"' \
  '--commit "$CREATE_DMG_COMMIT"' \
  '--script-sha256 "$CREATE_DMG_SCRIPT_SHA256"' \
  '--sentinel-sha256 "$CREATE_DMG_SENTINEL_SHA256"' \
  '--template-sha256 "$CREATE_DMG_TEMPLATE_SHA256"' \
  '--eula-template-sha256 "$CREATE_DMG_EULA_TEMPLATE_SHA256"'; do
  [[ "$(rg -Fc -- "$invariant" "$CREATE_DMG_PREPARER")" -eq 2 ]] \
    || fail "Pinned archive validation argument must bind both checks: $invariant"
done
for invariant in \
  'EXPECTED_RECORD_COUNT = 28' \
  'EXPECTED_FILESYSTEM_ENTRY_COUNT = 27' \
  'File::RDONLY | File::NOFOLLOW | File::NONBLOCK' \
  'compressed archive SHA-256 mismatch' \
  'archive_io.rewind' \
  'Gem::Package::TarReader.new(gzip)' \
  'first archive record must be the reviewed global PAX header' \
  'archive contains a link or special entry type' \
  'runtime member SHA-256 mismatch'; do
  rg -Fq "$invariant" "$CREATE_DMG_ARCHIVE_VALIDATOR" \
    || fail "Pinned archive validator invariant missing: $invariant"
done
if rg -Fq -- '--location' "$CREATE_DMG_PREPARER"; then
  fail "Pinned create-dmg download must not follow redirects away from codeload"
fi
for member in \
  '.this-is-the-create-dmg-repo' \
  'create-dmg' \
  'support/eula-resources-template.xml' \
  'support/template.applescript'; do
  rg -Fq "$member" "$CREATE_DMG_PREPARER" \
    || fail "Pinned create-dmg runtime closure is incomplete: $member"
done
for invariant in \
  'EXPECTED_MANIFEST_SHA256 = "35565e6e5d1086014d94fdddd246b8daa4b33bf3d6b9b49a1a9dac2d3a57526f"' \
  'File::RDONLY | File::NOFOLLOW | File::NONBLOCK' \
  'STAT_FIELDS = %i[dev ino uid mode nlink size mtime ctime].freeze' \
  'directory closure mismatch' \
  'file changed during verification' \
  'verified_files[relative_path] = read_verified_file(' \
  'verified_files.freeze' \
  'manifest must be adjacent to the tool root'; do
  rg -Fq "$invariant" "$CREATE_DMG_TOOL_VERIFIER" \
    || fail "Descriptor-backed create-dmg verifier invariant missing: $invariant"
done
for invariant in \
  'EXECUTION_SCRIPT_BYTES = 22_095' \
  'EXECUTION_SCRIPT_SHA256 = "46644c8da0d7eb1258e3ef05dd72967ca270d698df28d2aa6abd9402205e5beb"' \
  'closure = PinnedCreateDMGTool.verify(root: root, manifest: manifest)' \
  'executable == File.join(root, "create-dmg")' \
  'File.unlink(path)' \
  'anonymous.nlink == 0' \
  'file.close_on_exec = false' \
  '"/bin/bash"' \
  'unsetenv_others: true'; do
  rg -Fq "$invariant" "$CREATE_DMG_RUNNER" \
    || fail "Descriptor-bound create-dmg execution invariant missing: $invariant"
done
rg -Fq 'PREPARED_TOOL="$(./scripts/release/prepare-pinned-create-dmg.sh)"' \
  <<<"$create_dmg_prepare_block" \
  || fail "Release preflight must prepare the pinned create-dmg closure"
for output in \
  "printf 'root=%s\\n' \"\${TOOL_ROOT}\" >> \"\${GITHUB_OUTPUT}\"" \
  "printf 'executable=%s/create-dmg\\n' \"\${TOOL_ROOT}\" >> \"\${GITHUB_OUTPUT}\"" \
  "printf 'manifest=%s\\n' \"\${TOOL_MANIFEST}\" >> \"\${GITHUB_OUTPUT}\""; do
  rg -Fq "$output" <<<"$create_dmg_prepare_block" \
    || fail "Pinned create-dmg path is missing from GITHUB_OUTPUT: $output"
done
if rg -q '\$\{\{[[:space:]]*secrets\.' <<<"$create_dmg_prepare_block"; then
  fail "Pinned third-party tooling must be prepared without release secrets"
fi
if rg -Fq 'brew install create-dmg' "$RELEASE"; then
  fail "Release workflow must not install mutable create-dmg Homebrew state"
fi
app_keychain_teardown_line="$(rg -nF 'name: Tear down App signing keychain' "$RELEASE" | cut -d: -f1)"
dmg_package_line="$(rg -nF 'name: Package DMG' "$RELEASE" | cut -d: -f1)"
dmg_keychain_line="$(rg -nF 'name: Setup DMG signing keychain' "$RELEASE" | cut -d: -f1)"
dmg_sign_line="$(rg -nF 'name: Sign + notarize DMG' "$RELEASE" | cut -d: -f1)"
dmg_keychain_teardown_line="$(rg -nF 'name: Tear down DMG signing keychain' "$RELEASE" | cut -d: -f1)"
zip_package_line="$(rg -n 'name: Package release zip' "$RELEASE" | cut -d: -f1)"
[[ -n "$app_keychain_teardown_line" \
   && -n "$dmg_package_line" \
   && -n "$dmg_keychain_line" \
   && -n "$dmg_sign_line" \
   && -n "$dmg_keychain_teardown_line" \
   && -n "$zip_package_line" \
   && "$app_keychain_teardown_line" -lt "$dmg_package_line" \
   && "$dmg_package_line" -lt "$dmg_keychain_line" \
   && "$dmg_keychain_line" -lt "$dmg_sign_line" \
   && "$dmg_sign_line" -lt "$dmg_keychain_teardown_line" \
   && "$dmg_keychain_teardown_line" -lt "$zip_package_line" ]] \
  || fail "App keychain teardown, DMG package, keychain re-import, notarization, and ZIP ordering is invalid"
dmg_package_block="$(sed -n "${dmg_package_line},$((dmg_keychain_line - 1))p" "$RELEASE")"
dmg_keychain_block="$(sed -n "${dmg_keychain_line},$((dmg_sign_line - 1))p" "$RELEASE")"
dmg_sign_block="$(sed -n "${dmg_sign_line},$((dmg_keychain_teardown_line - 1))p" "$RELEASE")"
dmg_keychain_teardown_block="$(sed -n "${dmg_keychain_teardown_line},$((zip_package_line - 1))p" "$RELEASE")"
if rg -q '\$\{\{[[:space:]]*secrets\.' <<<"$dmg_package_block"; then
  fail "Third-party DMG packaging must run in a completely secret-free step"
fi
rg -Fq 'CREATE_DMG_ROOT: ${{ steps.create_dmg_tool.outputs.root }}' \
  <<<"$dmg_package_block" \
  || fail "DMG packaging must consume the private pinned-tool root"
rg -Fq 'CREATE_DMG_EXECUTABLE: ${{ steps.create_dmg_tool.outputs.executable }}' \
  <<<"$dmg_package_block" \
  || fail "DMG packaging must consume the pinned executable path"
rg -Fq 'CREATE_DMG_MANIFEST: ${{ steps.create_dmg_tool.outputs.manifest }}' \
  <<<"$dmg_package_block" \
  || fail "DMG packaging must consume the pinned runtime manifest"
for invariant in \
  'id: unsigned_dmg' \
  'umask 077' \
  '/usr/bin/env -i \' \
  'PATH="/usr/bin:/bin:/usr/sbin:/sbin" \' \
  'LC_ALL=C \' \
  'HOME="${CREATE_DMG_RUNTIME}/home" \' \
  'TMPDIR="${CREATE_DMG_RUNTIME}/tmp/" \' \
  '/usr/bin/ruby ./scripts/release/run-pinned-create-dmg.rb \' \
  '--root "${CREATE_DMG_ROOT}" \' \
  '--executable "${CREATE_DMG_EXECUTABLE}" \' \
  '--manifest "${CREATE_DMG_MANIFEST}" \' \
  '-- \' \
  '[[ ! -e "${STABLE_DMG}" && ! -L "${STABLE_DMG}" ]]' \
  '[[ -f "${STABLE_DMG}" && ! -L "${STABLE_DMG}" ]]' \
  'stat -f '\''%u:%l'\'' "${STABLE_DMG}"' \
  '(( (8#${DMG_MODE} & 022) == 0 ))' \
  'chmod 600 "${STABLE_DMG}"' \
  'hdiutil verify "${STABLE_DMG}"' \
  'printf '\''path=%s\n'\'' "${STABLE_DMG}" >> "${GITHUB_OUTPUT}"' \
  'printf '\''sha256=%s\n'\'' "$(shasum -a 256 "${STABLE_DMG}" | awk '\''{print $1}'\'')"'; do
  rg -Fq -- "$invariant" <<<"$dmg_package_block" \
    || fail "DMG packaging isolation invariant missing: $invariant"
done
if rg -Fq '|| true' <<<"$dmg_package_block"; then
  fail "Pinned create-dmg must fail closed on every nonzero exit"
fi
if rg -q '^[[:space:]]+"\$\{CREATE_DMG_EXECUTABLE\}" \\' <<<"$dmg_package_block"; then
  fail "DMG packaging must not reopen the verified create-dmg pathname"
fi
create_dmg_env_line="$(rg -nF '/usr/bin/env -i \' <<<"$dmg_package_block" | cut -d: -f1)"
create_dmg_runner_line="$(rg -nF '/usr/bin/ruby ./scripts/release/run-pinned-create-dmg.rb \' <<<"$dmg_package_block" | cut -d: -f1)"
[[ -n "$create_dmg_env_line" \
   && -n "$create_dmg_runner_line" \
   && "$create_dmg_env_line" -lt "$create_dmg_runner_line" ]] \
  || fail "Descriptor-bound create-dmg runner must execute below its clean environment boundary"
for secret in P12_BASE64 P12_PASSWORD KEYCHAIN_PASSWORD; do
  rg -q "^[[:space:]]+${secret}:.*secrets\." <<<"$dmg_keychain_block" \
    || fail "DMG signing keychain setup is missing its scoped secret: $secret"
done
for keychain_setup_block in "$app_keychain_block" "$dmg_keychain_block"; do
  rg -Fq 'umask 077' <<<"$keychain_setup_block" \
    || fail "Signing certificate staging must be owner-only"
  if rg -q -- '^[[:space:]]+-A([[:space:]]|$)' <<<"$keychain_setup_block"; then
    fail "Signing identities must not grant access to every local application"
  fi
done
rg -Fq 'if [[ "${DMG_IDENTITY}" != "${SIGNING_IDENTITY}" ]]; then' \
  <<<"$dmg_keychain_block" \
  || fail "DMG signing identity must match the App signing identity"
for secret in APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD; do
  rg -q "^[[:space:]]+${secret}:.*secrets\." <<<"$dmg_sign_block" \
    || fail "Credentialed DMG notarization is missing its scoped secret: $secret"
done
for invariant in \
  'id: dmg' \
  'STABLE_DMG: ${{ steps.unsigned_dmg.outputs.path }}' \
  'UNSIGNED_DMG_SHA256: ${{ steps.unsigned_dmg.outputs.sha256 }}' \
  'test "${STABLE_DMG}" = "build/Dev-Island.dmg"' \
  '[[ "${UNSIGNED_DMG_SHA256}" =~ ^[0-9a-f]{64}$ ]]' \
  'test "$(stat -f '\''%u:%l:%Lp'\'' "${STABLE_DMG}")" = "$(id -u):1:600"' \
  '"${UNSIGNED_DMG_SHA256}"' \
  'hdiutil verify "${STABLE_DMG}"' \
  'codesign --force --sign "${SIGNING_IDENTITY}" --timestamp "${STABLE_DMG}"' \
  'xcrun notarytool submit "${STABLE_DMG}"'; do
  rg -Fq "$invariant" <<<"$dmg_sign_block" \
    || fail "Credentialed DMG notarization invariant missing: $invariant"
done
if rg -Fq 'prepare-pinned-create-dmg.sh' <<<"$dmg_sign_block" \
   || rg -Fq 'CREATE_DMG_' <<<"$dmg_sign_block"; then
  fail "Credentialed notarization must not execute or revalidate third-party tooling"
fi
for invariant in \
  'security delete-keychain "${KEYCHAIN_PATH}"' \
  '[[ ! -e "${KEYCHAIN_PATH}" && ! -L "${KEYCHAIN_PATH}" ]]' \
  'security find-identity -v -p codesigning' \
  'DMG signing identity remained accessible after keychain teardown'; do
  rg -Fq "$invariant" <<<"$dmg_keychain_teardown_block" \
    || fail "DMG signing keychain teardown invariant missing: $invariant"
done

rg -q '^  group: release$' "$RELEASE" \
  || fail "All release tags must be serialized to protect stable assets"
for permission in 'contents: write' 'id-token: write' 'attestations: write'; do
  rg -q "^[[:space:]]+${permission}$" "$RELEASE" \
    || fail "Release provenance permission is missing: $permission"
done

for credential in \
  APPLE_ID \
  APPLE_TEAM_ID \
  APPLE_APP_PASSWORD \
  P12_BASE64 \
  P12_PASSWORD \
  KEYCHAIN_PASSWORD \
  SPARKLE_PUBLIC_ED_KEY \
  SPARKLE_PRIVATE_ED_KEY; do
  rg -q "^[[:space:]]+${credential}:" <<<"$credential_block" \
    || fail "Release credential environment is absent from the fail-fast preflight: $credential"
done
test -x "$CREDENTIAL_VALIDATOR" \
  || fail "Executable release-credential validator is missing"
test -f "$SPARKLE_SIGNATURE_VERIFIER" && test ! -L "$SPARKLE_SIGNATURE_VERIFIER" \
  || fail "CryptoKit Sparkle signature verifier is missing or unsafe"
rg -Fq 'Curve25519.Signing.PublicKey' "$SPARKLE_SIGNATURE_VERIFIER" \
  || fail "Sparkle verifier must perform real Ed25519 public-key verification"
rg -Fq './scripts/ci/validate-release-credentials.sh' <<<"$credential_block" \
  || fail "Release credential preflight must call the repository-owned validator"
test -x "$SPARKLE_SECRET_RUNNER" \
  || fail "Sparkle secret-isolation runner is missing"
test -x "$SPARKLE_SECRET_FIXTURES" \
  || fail "Sparkle secret-isolation fixtures are missing"
rg -Fq './scripts/release/run-sparkle-appcast-generator.sh' "$RELEASE" \
  || fail "Release workflow must use the repository-owned Sparkle runner"
"$SPARKLE_SECRET_FIXTURES" >/dev/null \
  || fail "Sparkle private-key process-boundary fixtures failed"
for invariant in \
  'dev-island-sparkle-generator-supervisor' \
  '"$@" <&3 3<&- &' \
  'generator_pid=$!' \
  'exec 3<&-' \
  '3<&0' \
  'wait "$generator_pid"'; do
  rg -Fq "$invariant" "$SPARKLE_SECRET_RUNNER" \
    || fail "Sparkle clean-parent supervisor invariant missing: $invariant"
done
for invariant in \
  'Required release credential is missing:' \
  'APPLE_TEAM_ID must be a 10-character Apple Team ID' \
  'KEYCHAIN_PASSWORD must contain at least 20 characters' \
  'SPARKLE_PUBLIC_ED_KEY must decode to exactly 32 bytes' \
  'SPARKLE_PUBLIC_ED_KEY and SPARKLE_PRIVATE_ED_KEY must form one Ed25519 key pair' \
  'SIGNING_CERTIFICATE_P12_BASE64 must be valid base64'; do
  rg -Fq "$invariant" "$CREDENTIAL_VALIDATOR" \
    || fail "Release credential validator invariant missing: $invariant"
done
rg -Fq 'TeamIdentifier=${APPLE_TEAM_ID}' "$RELEASE" \
  || fail "Developer ID TeamIdentifier must be bound to the notarization Team ID"
rg -Fq 'if: always()' "$RELEASE" \
  || fail "Temporary signing keychain teardown must run after failed releases"

sbom_line="$(rg -n 'name: Generate and verify SPDX SBOM' "$RELEASE" | cut -d: -f1)"
integrity_line="$(rg -n 'name: Generate release integrity manifest' "$RELEASE" | cut -d: -f1)"
asset_contract_line="$(rg -n 'name: Verify complete release asset contract' "$RELEASE" | cut -d: -f1)"
attestation_line="$(rg -n 'name: Attest release build provenance' "$RELEASE" | cut -d: -f1)"
sbom_attestation_line="$(rg -n 'name: Attest release SBOM' "$RELEASE" | cut -d: -f1)"
publication_line="$(rg -n 'name: Create GitHub Release' "$RELEASE" | cut -d: -f1)"
[[ -n "$sbom_line" \
   && -n "$integrity_line" \
   && -n "$asset_contract_line" \
   && -n "$attestation_line" \
   && -n "$sbom_attestation_line" \
   && -n "$publication_line" \
   && "$sbom_line" -lt "$integrity_line" \
   && "$integrity_line" -lt "$asset_contract_line" \
   && "$asset_contract_line" -lt "$attestation_line" \
   && "$attestation_line" -lt "$sbom_attestation_line" \
   && "$sbom_attestation_line" -lt "$publication_line" ]] \
  || fail "SBOM, integrity, complete asset verification, and both attestations must complete before publication"
[[ "$(rg -Fc "uses: ${ATTEST_ACTION}" "$RELEASE")" -eq 2 ]] \
  || fail "Both Release attestations must use the reviewed Node 24 actions/attest commit"
if rg -q 'uses: actions/(attest-build-provenance|attest-sbom)@' "$RELEASE"; then
  fail "Deprecated attestation wrapper Actions must not re-enter the Release workflow"
fi
[[ "$(rg -Fc "uses: ${RELEASE_ACTION}" "$RELEASE")" -eq 1 ]] \
  || fail "GitHub Release publication must use the reviewed Node 24 action commit"
test -x "$INTEGRITY_GENERATOR" \
  || fail "Executable release integrity generator is missing"
test -x "$SBOM_GENERATOR" \
  || fail "Executable deterministic SBOM generator is missing"
test -s "$OPENCODE_LOGO" && test -s "$OPENCODE_LOGO_LICENSE" \
  || fail "Reviewed OpenCode SBOM asset inputs are missing"
[[ "$(shasum -a 256 "$OPENCODE_LOGO" | awk '{print $1}')" == \
  "d6a0e3b8a295f413543f41cb73957e670351b5cb088c8d9dbd186b9e9d633cca" ]] \
  || fail "OpenCode SBOM asset input drifted from the reviewed upstream bytes"
for workflow in "${WORKFLOWS[@]}"; do
  [[ "$(rg -Fc -- '--brand-manifest scripts/assets/agent-logos/manifest.json' "$workflow")" -eq 2 ]] \
    || fail "CI and Release SBOM generation/check must both verify the brand manifest: $workflow"
  [[ "$(rg -Fc -- '--brand-source-dir scripts/assets/agent-logos' "$workflow")" -eq 2 ]] \
    || fail "CI and Release SBOM generation/check must both verify brand sources: $workflow"
  [[ "$(rg -Fc -- '--brand-bundle-dir "$APP/Contents/Resources"' "$workflow")" -eq 2 ]] \
    || fail "CI and Release SBOM generation/check must both verify packaged brand PNGs: $workflow"
done
for invariant in \
  'SPDXRef-Package-opencode-brand-square' \
  'SPDXRef-Package-agent-brand-' \
  'relationshipType": "CONTAINS"' \
  'brand source SHA-256 mismatch:' \
  'brand upstream SHA-256 mismatch after transform:' \
  'brand bundle SHA-256 mismatch:' \
  'duplicated brand asset self-test unexpectedly succeeded'; do
  rg -Fq "$invariant" "$SBOM_GENERATOR" \
    || fail "Brand asset SBOM invariant missing: $invariant"
done
test -x "$ASSET_VERIFIER" \
  || fail "Executable offline Release asset verifier is missing"
test -x "$ASSET_VERIFIER_FIXTURES" \
  || fail "Executable Release asset verifier fixture suite is missing"
test -x "$PUBLISHED_RELEASE_VERIFIER" \
  || fail "Executable published Release verifier is missing"
test -x "$PUBLISHED_RELEASE_METADATA_VALIDATOR" \
  || fail "Executable published Release metadata validator is missing"
test -x "$BUNDLE_DEPENDENCY_VERIFIER" \
  || fail "Executable app bundle dependency verifier is missing"
test -x "$BUNDLE_DEPENDENCY_FIXTURES" \
  || fail "Executable app bundle dependency attack fixtures are missing"
test -x "$BRAND_ASSET_VERIFIER" && test -x "$BRAND_ASSET_FIXTURES" \
  || fail "Executable brand asset verifier or attack fixtures are missing"
test -x "$TRADEMARK_PACKET_GENERATOR" && test -x "$TRADEMARK_PACKET_FIXTURES" \
  || fail "Executable trademark review packet generator or fixtures are missing"
test -s "$BRAND_ASSET_MANIFEST" \
  || fail "Brand asset manifest is missing"
test -s "$BRAND_TRADEMARK_REVIEWS" \
  || fail "Brand trademark review record is missing"
rg -Fq 'scripts/release/verify-brand-assets.rb' scripts/build-app.sh \
  || fail "Local App builds must verify brand source and generated PNG bytes before copying"
rg -Fq -- '--trademark-reviews "${ROOT}/scripts/assets/agent-logos/trademark-reviews.json"' scripts/build-app.sh \
  || fail "Local App builds must bind the trademark decision record"
"$BRAND_ASSET_VERIFIER" \
  --manifest "$BRAND_ASSET_MANIFEST" \
  --trademark-reviews "$BRAND_TRADEMARK_REVIEWS" \
  --source-dir scripts/assets/agent-logos \
  --bundle-dir IslandApp/Resources \
  --licenses-dir scripts/licenses >/dev/null \
  || fail "Repository brand asset inventory failed"
"$BRAND_ASSET_FIXTURES" >/dev/null \
  || fail "Brand asset attack fixtures failed"
"$TRADEMARK_PACKET_FIXTURES" >/dev/null \
  || fail "Trademark review packet fixtures failed"
"$BUNDLE_DEPENDENCY_FIXTURES" >/dev/null \
  || fail "App bundle dependency attack fixtures failed"

build_line="$(rg -n 'name: Build \.app \(universal\)' "$RELEASE" | cut -d: -f1)"
dependency_closure_line="$(rg -n 'name: Verify app dependency closure' "$RELEASE" | cut -d: -f1)"
codesign_line="$(rg -n 'name: Codesign with Developer ID' "$RELEASE" | cut -d: -f1)"
[[ -n "$build_line" \
   && -n "$dependency_closure_line" \
   && -n "$codesign_line" \
   && "$build_line" -lt "$dependency_closure_line" \
   && "$dependency_closure_line" -lt "$codesign_line" ]] \
  || fail "Dependency closure verification must run after build and before Developer ID signing"
dependency_closure_block="$(sed -n "${dependency_closure_line},$((codesign_line - 1))p" "$RELEASE")"
rg -Fq './scripts/release/verify-app-bundle-dependencies.rb' <<<"$dependency_closure_block" \
  || fail "Tagged releases must run the repository-owned app dependency verifier"
rg -Fq './scripts/release/verify-brand-assets.rb' <<<"$dependency_closure_block" \
  || fail "Tagged releases must verify the brand bytes inside the built App"
rg -Fq -- '--trademark-reviews scripts/assets/agent-logos/trademark-reviews.json' <<<"$dependency_closure_block" \
  || fail "Built release App must retain the bound trademark decision record"
rg -Fq -- '--require-release-reviewed' <<<"$dependency_closure_block" \
  || fail "Built release App must retain the human brand-review gate"
swift "$SBOM_GENERATOR" --self-test >/dev/null \
  || fail "Deterministic SBOM generator self-test failed"
rg -Fq './scripts/release/generate-release-integrity-manifest.sh' "$RELEASE" \
  || fail "Release workflow must use the repository-owned integrity generator"
asset_contract_block="$(sed -n "${asset_contract_line},$((attestation_line - 1))p" "$RELEASE")"
rg -Fq './scripts/release/verify-release-assets.sh' <<<"$asset_contract_block" \
  || fail "Release workflow must run the repository-owned complete asset verifier"
rg -Fq -- '--tag "${GITHUB_REF_NAME}"' <<<"$asset_contract_block" \
  || fail "Release asset verification must bind metadata to the exact tag"
rg -Fq -- '--source-revision "${GITHUB_SHA}"' <<<"$asset_contract_block" \
  || fail "Release asset verification must bind the SBOM to the tagged source revision"
"$ASSET_VERIFIER_FIXTURES" >/dev/null \
  || fail "Release asset verifier attack fixtures failed"
rg -Fq 'validate-published-release-metadata.rb' "$PUBLISHED_RELEASE_VERIFIER" \
  || fail "Published Release verifier must use the tested API metadata validator"
for invariant in \
  'gh release download "$TAG" --repo "$REPOSITORY"' \
  'gh attestation verify "$ASSET_DIR/$asset"' \
  '--signer-workflow "$SIGNER_WORKFLOW"' \
  '--source-ref "$SOURCE_REF"' \
  '--source-digest "$SOURCE_REVISION"' \
  '--deny-self-hosted-runners' \
  '--predicate-type "https://spdx.dev/Document"'; do
  rg -Fq -- "$invariant" "$PUBLISHED_RELEASE_VERIFIER" \
    || fail "Published Release verifier invariant missing: $invariant"
done
for workflow in .github/workflows/ci.yml "$RELEASE"; do
  rg -Fq 'swift scripts/release/generate-sbom.swift' "$workflow" \
    || fail "Workflow must use the repository-owned SBOM generator: $workflow"
  rg -Fq -- '--licenses-dir "$APP/Contents/Resources/ThirdPartyLicenses"' "$workflow" \
    || fail "SBOM must inventory the licenses inside the packaged App: $workflow"
  rg -Fq -- '--toml-header .build/app-production/checkouts/swift-toml/Sources/CTomlPlusPlus/toml.hpp' "$workflow" \
    || fail "SBOM must inventory the exact vendored toml++ header: $workflow"
  rg -Fq -- '--brand-manifest scripts/assets/agent-logos/manifest.json' "$workflow" \
    || fail "SBOM must inventory the reviewed brand manifest: $workflow"
  rg -Fq -- '--brand-bundle-dir "$APP/Contents/Resources"' "$workflow" \
    || fail "SBOM must inventory the exact packaged brand PNGs: $workflow"
  rg -Fq -- '--check "$SBOM"' "$workflow" \
    || fail "Workflow must byte-verify the canonical SBOM: $workflow"
done
rg -Fq '${{ steps.integrity.outputs.path }}' "$RELEASE" \
  || fail "SHA256SUMS must be published as a Release asset"
rg -Fq '${{ steps.sbom.outputs.path }}' "$RELEASE" \
  || fail "SPDX SBOM must be published as a Release asset"
attestation_block="$(sed -n "${attestation_line},$((sbom_attestation_line - 1))p" "$RELEASE")"
for subject in \
  '${{ steps.dmg.outputs.stable }}' \
  '${{ steps.dmg.outputs.versioned }}' \
  '${{ steps.package.outputs.stable }}' \
  '${{ steps.package.outputs.versioned }}' \
  '${{ steps.appcast.outputs.path }}' \
  '${{ steps.cask.outputs.path }}' \
  '${{ steps.sbom.outputs.path }}' \
  '${{ steps.integrity.outputs.path }}'; do
  rg -Fq "$subject" <<<"$attestation_block" \
    || fail "Published artifact is absent from build provenance: $subject"
done
sbom_attestation_block="$(sed -n "${sbom_attestation_line},$((publication_line - 1))p" "$RELEASE")"
for subject in \
  '${{ steps.dmg.outputs.stable }}' \
  '${{ steps.dmg.outputs.versioned }}' \
  '${{ steps.package.outputs.stable }}' \
  '${{ steps.package.outputs.versioned }}' \
  'sbom-path: ${{ steps.sbom.outputs.path }}'; do
  rg -Fq "$subject" <<<"$sbom_attestation_block" \
    || fail "Release binary or SPDX document is absent from SBOM attestation: $subject"
done

app_stapler_line="$(rg -nF 'xcrun stapler validate "build/Dev Island.app"' "$RELEASE" | cut -d: -f1)"
app_gatekeeper_line="$(rg -nF 'spctl -a -vvv -t exec "build/Dev Island.app"' "$RELEASE" | cut -d: -f1)"
dmg_stapler_line="$(rg -nF 'xcrun stapler validate "${STABLE_DMG}"' "$RELEASE" | cut -d: -f1)"
dmg_gatekeeper_line="$(rg -nF 'spctl -a -vvv -t open --context context:primary-signature "${STABLE_DMG}"' "$RELEASE" | cut -d: -f1)"
[[ -n "$app_stapler_line" \
   && -n "$app_gatekeeper_line" \
   && "$app_stapler_line" -lt "$app_gatekeeper_line" ]] \
  || fail "Notarized App must pass a hard Gatekeeper assessment before publication"
[[ -n "$dmg_stapler_line" \
   && -n "$dmg_gatekeeper_line" \
   && "$dmg_stapler_line" -lt "$dmg_gatekeeper_line" ]] \
  || fail "Notarized DMG must pass a hard Gatekeeper assessment before publication"

FIXTURE_PRIVATE_KEY="$(
  printf '%s' '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60' \
    | xxd -r -p | base64 | tr -d '\n'
)"
FIXTURE_PUBLIC_KEY='11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo='
MISMATCHED_PUBLIC_KEY='PUAXw+hDiVqStwqnTRt+vJyYLM8uxJaMwM1V8Sr0Zgw='
DUMMY_P12="$(printf 'structurally-base64-test-certificate' | base64 | tr -d '\n' | fold -w 8)"
run_credential_validator() {
  env \
    APPLE_ID='release@example.com' \
    APPLE_TEAM_ID="${1:-ABCDEF1234}" \
    APPLE_APP_PASSWORD='dummy-app-password' \
    P12_BASE64="${2:-$DUMMY_P12}" \
    P12_PASSWORD='dummy-p12-password' \
    KEYCHAIN_PASSWORD='dummy-keychain-password' \
    SPARKLE_PUBLIC_ED_KEY="${3:-$FIXTURE_PUBLIC_KEY}" \
    SPARKLE_PRIVATE_ED_KEY="${4-$FIXTURE_PRIVATE_KEY}" \
    "$CREDENTIAL_VALIDATOR"
}
run_credential_validator >/dev/null \
  || fail "Cryptographically paired release credentials must pass preflight"
if run_credential_validator 'ABCDEF1234' "$DUMMY_P12" "$FIXTURE_PUBLIC_KEY" '' >/dev/null 2>&1; then
  fail "Missing release credentials must fail preflight"
fi
if run_credential_validator 'bad-team' >/dev/null 2>&1; then
  fail "Malformed Apple Team IDs must fail release credential preflight"
fi
if run_credential_validator 'ABCDEF1234' "$DUMMY_P12" 'dG9vLXNob3J0' >/dev/null 2>&1; then
  fail "Wrong-sized Sparkle public keys must fail release credential preflight"
fi
if run_credential_validator 'ABCDEF1234' 'not-base64%%%' >/dev/null 2>&1; then
  fail "Malformed signing-certificate base64 must fail release credential preflight"
fi
if run_credential_validator \
  'ABCDEF1234' "$DUMMY_P12" "$MISMATCHED_PUBLIC_KEY" "$FIXTURE_PRIVATE_KEY" \
  >/dev/null 2>&1; then
  fail "Mismatched Sparkle public/private keys must fail release credential preflight"
fi

test -x "$HOMEBREW_VERIFIER" \
  || fail "Executable Homebrew distribution verifier is missing"
"$HOMEBREW_VERIFIER"

TEMP_DIR="$(mktemp -d -t dev-island-release-foundation)"
trap 'rm -rf "$TEMP_DIR"' EXIT
DUMMY_SHA="$(printf 'a%.0s' {1..64})"
VERSION="$VERSION" SHA256="$DUMMY_SHA" OUTPUT="$TEMP_DIR/dev-island.rb" \
  ./scripts/render-homebrew-cask.sh >/dev/null
rg -q "^  version \"${VERSION}\"$" "$TEMP_DIR/dev-island.rb" \
  || fail "Rendered Cask version is incorrect"
rg -q "^  sha256 \"${DUMMY_SHA}\"$" "$TEMP_DIR/dev-island.rb" \
  || fail "Rendered Cask SHA-256 is incorrect"
ruby -c "$TEMP_DIR/dev-island.rb" >/dev/null \
  || fail "Rendered Cask is not valid Ruby"

INTEGRITY_FIXTURE="$TEMP_DIR/integrity"
mkdir -p "$INTEGRITY_FIXTURE"
printf 'notarized-dmg' >"$INTEGRITY_FIXTURE/Dev-Island.dmg"
cp "$INTEGRITY_FIXTURE/Dev-Island.dmg" \
  "$INTEGRITY_FIXTURE/Dev-Island-${VERSION}.dmg"
printf 'notarized-zip' >"$INTEGRITY_FIXTURE/Dev-Island.zip"
cp "$INTEGRITY_FIXTURE/Dev-Island.zip" \
  "$INTEGRITY_FIXTURE/Dev-Island-${VERSION}.zip"
printf 'spdx-sbom' >"$INTEGRITY_FIXTURE/Dev-Island.spdx.json"
printf 'signed-appcast' >"$INTEGRITY_FIXTURE/appcast.xml"
printf 'cask' >"$INTEGRITY_FIXTURE/dev-island.rb"
VERSION="$VERSION" BUILD_DIR="$INTEGRITY_FIXTURE" \
  "$INTEGRITY_GENERATOR" >/dev/null
[[ "$(wc -l <"$INTEGRITY_FIXTURE/SHA256SUMS" | tr -d ' ')" -eq 7 ]] \
  || fail "Release integrity manifest must cover exactly seven artifacts"
(
  cd "$INTEGRITY_FIXTURE"
  shasum -a 256 -c SHA256SUMS >/dev/null
) || fail "Release integrity manifest fixture does not verify"
for artifact in \
  'Dev-Island.dmg' \
  "Dev-Island-${VERSION}.dmg" \
  'Dev-Island.zip' \
  "Dev-Island-${VERSION}.zip" \
  'Dev-Island.spdx.json' \
  'appcast.xml' \
  'dev-island.rb'; do
  rg -q "  ${artifact}$" "$INTEGRITY_FIXTURE/SHA256SUMS" \
    || fail "Release integrity manifest omits artifact: $artifact"
done
MANIFEST_BEFORE_FAILURE="$(shasum -a 256 "$INTEGRITY_FIXTURE/SHA256SUMS" | awk '{print $1}')"
printf 'mismatched-versioned-zip' >"$INTEGRITY_FIXTURE/Dev-Island-${VERSION}.zip"
if VERSION="$VERSION" BUILD_DIR="$INTEGRITY_FIXTURE" \
  "$INTEGRITY_GENERATOR" >/dev/null 2>&1; then
  fail "Integrity generation must reject different stable/versioned bytes"
fi
[[ "$(shasum -a 256 "$INTEGRITY_FIXTURE/SHA256SUMS" | awk '{print $1}')" == \
   "$MANIFEST_BEFORE_FAILURE" ]] \
  || fail "Failed integrity generation must preserve the last good manifest"
cp "$INTEGRITY_FIXTURE/Dev-Island.zip" \
  "$INTEGRITY_FIXTURE/Dev-Island-${VERSION}.zip"
mv "$INTEGRITY_FIXTURE/appcast.xml" "$INTEGRITY_FIXTURE/appcast.real.xml"
ln -s appcast.real.xml "$INTEGRITY_FIXTURE/appcast.xml"
if VERSION="$VERSION" BUILD_DIR="$INTEGRITY_FIXTURE" \
  "$INTEGRITY_GENERATOR" >/dev/null 2>&1; then
  fail "Integrity generation must reject symbolic-link artifact inputs"
fi
[[ "$(shasum -a 256 "$INTEGRITY_FIXTURE/SHA256SUMS" | awk '{print $1}')" == \
   "$MANIFEST_BEFORE_FAILURE" ]] \
  || fail "Rejected symbolic-link input must preserve the last good manifest"

echo "Release foundation invariants: PASS"
