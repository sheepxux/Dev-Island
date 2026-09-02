#!/usr/bin/env bash

set -euo pipefail

# Download the reviewed create-dmg source archive into a private runner-temp
# directory, verify it before extraction, and expose only the four files the
# release job actually needs. The exact commit is used instead of a mutable tag
# or Homebrew formula so a release cannot silently pick up new upstream code.

umask 077

readonly CREATE_DMG_VERSION="1.3.0"
readonly CREATE_DMG_COMMIT="a2b71d0fda6d0df2a86dc7f67082d4d73e84c59f"
readonly CREATE_DMG_ARCHIVE_URL="https://codeload.github.com/create-dmg/create-dmg/tar.gz/${CREATE_DMG_COMMIT}"
readonly CREATE_DMG_ARCHIVE_SHA256="36577b966f16c12dd78d5bb5107c2ae3d069b044226b6ebbffa6a434ce142d0a"
readonly CREATE_DMG_ARCHIVE_BYTES="48371"
readonly CREATE_DMG_SCRIPT_SHA256="bb9ea3194e55f2f76a821e87541513748d0fedc69f45cf4f0951cad15ae0cae5"
readonly CREATE_DMG_SENTINEL_SHA256="fb2494eb10146a84bbb20ebb198c2a09fb72aed119706dc55b6ec3644018383f"
readonly CREATE_DMG_TEMPLATE_SHA256="b5dd7c55ddaa5db1884ac5cf523c4413d452a75df967daf55b8d45ba501fe457"
readonly CREATE_DMG_EULA_TEMPLATE_SHA256="a804e533e9c99491a74cb4502c435b00d902dc7a45d3693057a29674e584a70b"

fail() {
  printf 'prepare-pinned-create-dmg: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
Usage:
  prepare-pinned-create-dmg.sh
  prepare-pinned-create-dmg.sh --verify-root /absolute/private/tool/root \
    --manifest /absolute/private/runtime.SHA256

The prepare form prints the absolute tool root and manifest path separated by
one tab. The verify form rechecks the extracted closure without downloading or
modifying it.
USAGE
  exit 64
}

stat_value() {
  local format="$1"
  local path="$2"
  LC_ALL=C /usr/bin/stat -f "$format" "$path"
}

sha256() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

verify_private_directory() {
  local path="$1"
  local expected_mode="$2"

  [[ -d "$path" && ! -L "$path" ]] \
    || fail "expected a real directory: $path"
  [[ "$(stat_value '%HT' "$path")" == "Directory" ]] \
    || fail "unexpected directory type: $path"
  [[ "$(stat_value '%u' "$path")" == "$(/usr/bin/id -u)" ]] \
    || fail "directory is not owned by the runner user: $path"
  [[ "$(stat_value '%Lp' "$path")" == "$expected_mode" ]] \
    || fail "directory mode drifted from $expected_mode: $path"
}

verify_pinned_file() {
  local path="$1"
  local expected_mode="$2"
  local expected_sha256="$3"

  [[ -f "$path" && ! -L "$path" ]] \
    || fail "expected a real regular file: $path"
  [[ "$(stat_value '%HT' "$path")" == "Regular File" ]] \
    || fail "unexpected file type: $path"
  [[ "$(stat_value '%u' "$path")" == "$(/usr/bin/id -u)" ]] \
    || fail "file is not owned by the runner user: $path"
  [[ "$(stat_value '%l' "$path")" == "1" ]] \
    || fail "file must have exactly one hard link: $path"
  [[ "$(stat_value '%Lp' "$path")" == "$expected_mode" ]] \
    || fail "file mode drifted from $expected_mode: $path"
  [[ "$(sha256 "$path")" == "$expected_sha256" ]] \
    || fail "SHA-256 mismatch: $path"
}

verify_tool_root() {
  local tool_root="$1"
  local manifest="$2"
  local script_dir
  local verifier

  [[ "$tool_root" == /* && "$tool_root" != *[$'\r\n\t']* ]] \
    || fail "tool root must be an absolute single-line path"
  [[ "$manifest" == /* && "$manifest" != *[$'\r\n\t']* ]] \
    || fail "manifest must be an absolute single-line path"

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  verifier="$script_dir/verify-pinned-create-dmg-tool.rb"
  [[ -x "$verifier" && ! -L "$verifier" ]] \
    || fail "descriptor-backed runtime verifier is unavailable"
  "$verifier" --root "$tool_root" --manifest "$manifest"

  [[ "$(
    /usr/bin/env -i \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      LC_ALL=C \
      "$tool_root/create-dmg" --pure-version
  )" == "$CREATE_DMG_VERSION" ]] \
    || fail "create-dmg did not report the reviewed version"

  # The version probe executes upstream bytes. Re-open and re-hash the complete
  # closure afterwards so any mutation during that probe fails closed.
  "$verifier" --root "$tool_root" --manifest "$manifest"
}

prepare_tool() {
  local runner_temp="${RUNNER_TEMP:-}"
  local work_root
  local archive
  local tool_root
  local manifest
  local script_dir
  local archive_validator
  local archive_prefix="create-dmg-${CREATE_DMG_COMMIT}"

  [[ "$runner_temp" == /* && "$runner_temp" != *[$'\r\n\t']* ]] \
    || fail "RUNNER_TEMP must be an absolute single-line path"
  [[ -d "$runner_temp" && ! -L "$runner_temp" ]] \
    || fail "RUNNER_TEMP must be a real directory"

  work_root="$(/usr/bin/mktemp -d "${runner_temp%/}/dev-island-create-dmg.XXXXXXXX")"
  work_root="$(cd "$work_root" && pwd -P)"
  archive="$work_root/source.tar.gz"
  tool_root="$work_root/tool"
  manifest="$work_root/runtime.SHA256"
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  archive_validator="$script_dir/validate-pinned-create-dmg-archive.rb"

  verify_private_directory "$work_root" "700"
  [[ -x "$archive_validator" && ! -L "$archive_validator" ]] \
    || fail "descriptor-backed archive validator is unavailable"

  /usr/bin/curl \
    --proto '=https' \
    --tlsv1.2 \
    --fail \
    --silent \
    --show-error \
    --retry 3 \
    --retry-connrefused \
    --connect-timeout 15 \
    --max-time 120 \
    --output "$archive" \
    "$CREATE_DMG_ARCHIVE_URL"

  [[ -f "$archive" && ! -L "$archive" ]] \
    || fail "download did not produce a real regular file"
  [[ "$(stat_value '%HT' "$archive")" == "Regular File" ]] \
    || fail "downloaded archive has an unexpected file type"
  [[ "$(stat_value '%u' "$archive")" == "$(/usr/bin/id -u)" ]] \
    || fail "downloaded archive is not owned by the runner user"
  [[ "$(stat_value '%l' "$archive")" == "1" ]] \
    || fail "downloaded archive must have exactly one hard link"
  [[ "$(stat_value '%Lp' "$archive")" == "600" ]] \
    || fail "downloaded archive must remain private"
  [[ "$(stat_value '%z' "$archive")" == "$CREATE_DMG_ARCHIVE_BYTES" ]] \
    || fail "downloaded archive size does not match the reviewed bytes"
  [[ "$(sha256 "$archive")" == "$CREATE_DMG_ARCHIVE_SHA256" ]] \
    || fail "downloaded archive SHA-256 does not match the reviewed commit"

  # Parser-facing operations are deliberately delayed until the exact byte
  # digest succeeds. The validator hashes and parses from one no-follow file
  # descriptor and rejects every unreviewed tar member shape before extraction.
  "$archive_validator" \
    --archive "$archive" \
    --archive-sha256 "$CREATE_DMG_ARCHIVE_SHA256" \
    --commit "$CREATE_DMG_COMMIT" \
    --script-sha256 "$CREATE_DMG_SCRIPT_SHA256" \
    --sentinel-sha256 "$CREATE_DMG_SENTINEL_SHA256" \
    --template-sha256 "$CREATE_DMG_TEMPLATE_SHA256" \
    --eula-template-sha256 "$CREATE_DMG_EULA_TEMPLATE_SHA256" \
    >/dev/null

  # Extract only the reviewed runtime closure into the private empty root.
  /bin/mkdir -m 700 "$tool_root"
  /usr/bin/tar -xzf "$archive" \
    -C "$tool_root" \
    --strip-components 1 \
    "$archive_prefix/.this-is-the-create-dmg-repo" \
    "$archive_prefix/create-dmg" \
    "$archive_prefix/support/eula-resources-template.xml" \
    "$archive_prefix/support/template.applescript"

  /bin/chmod 500 "$tool_root" "$tool_root/support" "$tool_root/create-dmg"
  /bin/chmod 400 \
    "$tool_root/.this-is-the-create-dmg-repo" \
    "$tool_root/support/eula-resources-template.xml" \
    "$tool_root/support/template.applescript"

  # Close the validator-to-tar reopen interval before discarding the archive.
  # The descriptor-bound digest makes any concurrent archive drift fail here;
  # the runtime verifier below independently binds all extracted bytes.
  "$archive_validator" \
    --archive "$archive" \
    --archive-sha256 "$CREATE_DMG_ARCHIVE_SHA256" \
    --commit "$CREATE_DMG_COMMIT" \
    --script-sha256 "$CREATE_DMG_SCRIPT_SHA256" \
    --sentinel-sha256 "$CREATE_DMG_SENTINEL_SHA256" \
    --template-sha256 "$CREATE_DMG_TEMPLATE_SHA256" \
    --eula-template-sha256 "$CREATE_DMG_EULA_TEMPLATE_SHA256" \
    >/dev/null
  /bin/unlink "$archive"

  printf '%s\n' \
    'fb2494eb10146a84bbb20ebb198c2a09fb72aed119706dc55b6ec3644018383f  .this-is-the-create-dmg-repo' \
    'bb9ea3194e55f2f76a821e87541513748d0fedc69f45cf4f0951cad15ae0cae5  create-dmg' \
    'a804e533e9c99491a74cb4502c435b00d902dc7a45d3693057a29674e584a70b  support/eula-resources-template.xml' \
    'b5dd7c55ddaa5db1884ac5cf523c4413d452a75df967daf55b8d45ba501fe457  support/template.applescript' \
    > "$manifest"
  /bin/chmod 400 "$manifest"

  verify_tool_root "$tool_root" "$manifest"
  printf '%s\t%s\n' "$tool_root" "$manifest"
}

case "${1:-}" in
  "")
    [[ "$#" -eq 0 ]] || usage
    prepare_tool
    ;;
  --verify-root)
    [[ "$#" -eq 4 && "$3" == "--manifest" ]] || usage
    verify_tool_root "$2" "$4"
    ;;
  *)
    usage
    ;;
esac
