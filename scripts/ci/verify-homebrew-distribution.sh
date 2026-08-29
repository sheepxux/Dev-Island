#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$1" >&2
  exit 1
}

CASK="dist/homebrew-island/Casks/dev-island.rb"
CASK_DOC="dist/homebrew-island/README.md"
RENDERER="scripts/render-homebrew-cask.sh"
VERSION="$(cat VERSION)"

for file in "$CASK" "$CASK_DOC" "$RENDERER"; do
  test -s "$file" || fail "Homebrew distribution artifact missing: $file"
done
test -x "$RENDERER" || fail "Homebrew Cask renderer must be executable"
command -v ruby >/dev/null || fail "Ruby is required to validate the Homebrew Cask"
command -v brew >/dev/null || fail "Homebrew is required to run the real Cask style and readall gates"

[[ "$(rg -c '^  version "' "$CASK")" -eq 1 ]] \
  || fail "Cask must contain exactly one version stanza"
[[ "$(rg -c '^  sha256 "' "$CASK")" -eq 1 ]] \
  || fail "Cask must contain exactly one SHA-256 stanza"
rg -Fqx "  version \"${VERSION}\"" "$CASK" \
  || fail "Cask version must match VERSION"
rg -q '^  sha256 "[0-9a-f]{64}"$' "$CASK" \
  || fail "Cask must pin one lowercase SHA-256"

for invariant in \
  '  url "https://github.com/sheepxux/Dev-Island/releases/download/v#{version}/Dev-Island.zip"' \
  '  name "Dev Island"' \
  '  homepage "https://devisland.app/"' \
  '  depends_on macos: :sonoma' \
  '  app "Dev Island.app"' \
  '  uninstall quit: "app.devisland.Island"' \
  '    "~/Library/Application Support/island-app",' \
  '    "~/Library/Caches/app.devisland.Island",' \
  '    "~/Library/Preferences/app.devisland.Island.plist",' \
  '    "~/Library/Saved Application State/app.devisland.Island.savedState",'; do
  rg -Fqx "$invariant" "$CASK" \
    || fail "Homebrew distribution invariant missing: $invariant"
done

if rg -n \
  'sha256[[:space:]]+:no_check|/latest/|releases/latest|^[[:space:]]*(preflight|postflight|binary|pkg|installer)[[:space:]]|^[[:space:]]*system[[:space:]]|depends_on.*cloudflared|security delete-generic-password' \
  "$CASK"; then
  fail "Cask reintroduced an unpinned download, install-time code execution, or unsafe dependency/Keychain behavior"
fi
rg -Fq 'Disconnect Manus' "$CASK_DOC" \
  || fail "Cask docs must explain how users remove the intentionally retained Keychain item"
rg -Fq './scripts/ci/verify-homebrew-distribution.sh' "$CASK_DOC" \
  || fail "Cask docs must use the repository-owned validation command"

ruby -c "$CASK" >/dev/null || fail "Source Cask is not valid Ruby"

TEMP_DIR="$(mktemp -d -t dev-island-homebrew-distribution)"
TEMP_TAP="dev-island-ci-$$/dev-island-ci-$$"
cleanup() {
  if HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_DEVELOPER=1 brew tap \
      | rg -Fxq "$TEMP_TAP"; then
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_DEVELOPER=1 \
      brew untap --force "$TEMP_TAP" >/dev/null 2>&1 || true
  fi
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

DUMMY_SHA="$(printf 'a%.0s' {1..64})"
RENDERED="$TEMP_DIR/dev-island.rb"
VERSION="$VERSION" SHA256="$DUMMY_SHA" OUTPUT="$RENDERED" \
  "$RENDERER" >/dev/null
rg -Fqx "  version \"${VERSION}\"" "$RENDERED" \
  || fail "Rendered Cask version is incorrect"
rg -Fqx "  sha256 \"${DUMMY_SHA}\"" "$RENDERED" \
  || fail "Rendered Cask SHA-256 is incorrect"
[[ "$(stat -f '%Lp' "$RENDERED")" == "644" ]] \
  || fail "Rendered Cask must use mode 0644"
ruby -c "$RENDERED" >/dev/null || fail "Rendered Cask is not valid Ruby"

SECOND_RENDER="$TEMP_DIR/dev-island-second.rb"
VERSION="$VERSION" SHA256="$DUMMY_SHA" OUTPUT="$SECOND_RENDER" \
  "$RENDERER" >/dev/null
cmp -s "$RENDERED" "$SECOND_RENDER" \
  || fail "Identical Homebrew inputs must render byte-identical Casks"

if VERSION="v${VERSION}" SHA256="$DUMMY_SHA" \
    OUTPUT="$TEMP_DIR/invalid-version.rb" "$RENDERER" >/dev/null 2>&1; then
  fail "Renderer must reject a leading-v release version"
fi
UPPERCASE_SHA="$(printf '%s' "$DUMMY_SHA" | tr '[:lower:]' '[:upper:]')"
if VERSION="$VERSION" SHA256="$UPPERCASE_SHA" \
    OUTPUT="$TEMP_DIR/invalid-sha.rb" "$RENDERER" >/dev/null 2>&1; then
  fail "Renderer must reject non-lowercase SHA-256 input"
fi

if HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_DEVELOPER=1 brew tap \
    | rg -Fxq "$TEMP_TAP"; then
  fail "Reserved temporary Homebrew tap already exists: $TEMP_TAP"
fi
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_DEVELOPER=1 \
  brew tap-new --no-git "$TEMP_TAP" >/dev/null
TAP_DIR="$(HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_DEVELOPER=1 \
  brew --repository "$TEMP_TAP")"
mkdir -p "$TAP_DIR/Casks"
/usr/bin/install -m 0644 "$RENDERED" "$TAP_DIR/Casks/dev-island.rb"
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_DEVELOPER=1 \
  brew style --cask "$TAP_DIR/Casks/dev-island.rb"
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_DEVELOPER=1 \
  brew readall "$TEMP_TAP"

echo "Homebrew distribution contract: PASS"
