#!/usr/bin/env bash

# Invoke Sparkle's pinned generate_appcast tool without leaving release
# credentials in either its argv or inherited environment. GitHub Actions must
# still inject the private key into this wrapper, but the third-party child
# receives it only through the explicit stdin key-file channel.

set -euo pipefail

fail() {
  echo "::error::$1" >&2
  exit 1
}

usage() {
  echo "usage: $0 GENERATOR FEED_DIRECTORY RELEASE_TAG" >&2
  exit 64
}

[[ $# -eq 3 ]] || usage

GENERATOR="$1"
FEED_DIRECTORY="$2"
RELEASE_TAG="$3"

[[ -f "$GENERATOR" && ! -L "$GENERATOR" && -x "$GENERATOR" ]] \
  || fail "Sparkle appcast generator must be a regular executable"
[[ -d "$FEED_DIRECTORY" && ! -L "$FEED_DIRECTORY" ]] \
  || fail "Sparkle feed directory must be a regular directory"
[[ "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ ]] \
  || fail "Sparkle release tag is malformed"
[[ -n "${SPARKLE_PRIVATE_ED_KEY:-}" ]] \
  || fail "SPARKLE_PRIVATE_ED_KEY is required to sign updates"

# A new, non-exported variable keeps the pipe source available after the
# inherited secret environment is removed. Also clear every other credential
# name used by release.yml so later workflow edits cannot accidentally widen
# the third-party generator's authority.
appcast_private_key="${SPARKLE_PRIVATE_ED_KEY}"
unset \
  APPLE_ID \
  APPLE_TEAM_ID \
  APPLE_APP_PASSWORD \
  P12_BASE64 \
  P12_PASSWORD \
  KEYCHAIN_PASSWORD \
  SPARKLE_PUBLIC_ED_KEY \
  SPARKLE_PRIVATE_ED_KEY

clear_private_key() {
  appcast_private_key=""
  unset appcast_private_key
}
trap clear_private_key EXIT INT TERM

# Do not pass HOME, GitHub tokens, runner metadata, signing credentials, or
# arbitrary workflow variables to Sparkle. The executable and all arguments
# are already resolved by this repository-owned wrapper; only system command
# lookup and deterministic locale are required by the pinned CLI.
printf '%s' "$appcast_private_key" \
  | env -i \
      PATH='/usr/bin:/bin' \
      LANG='C' \
      LC_ALL='C' \
      "$GENERATOR" \
        --ed-key-file - \
        --download-url-prefix \
          "https://github.com/sheepxux/Dev-Island/releases/download/${RELEASE_TAG}/" \
        --link 'https://devisland.app' \
        --maximum-versions 1 \
        --maximum-deltas 0 \
        "$FEED_DIRECTORY"
