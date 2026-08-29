#!/usr/bin/env bash

set -euo pipefail

feed_directory=""
for argument in "$@"; do
  feed_directory="$argument"
done
[[ -d "$feed_directory" ]] || exit 71

for forbidden_name in \
  APPLE_ID \
  APPLE_TEAM_ID \
  APPLE_APP_PASSWORD \
  P12_BASE64 \
  P12_PASSWORD \
  KEYCHAIN_PASSWORD \
  SPARKLE_PUBLIC_ED_KEY \
  SPARKLE_PRIVATE_ED_KEY; do
  if env | grep -q "^${forbidden_name}="; then
    exit 72
  fi
done

printf '%s\n' "$@" >"${feed_directory}/observed-arguments.txt"
env | sort >"${feed_directory}/observed-environment.txt"
ps eww -p "$PPID" -o command= >"${feed_directory}/observed-parent.txt"
cat >"${feed_directory}/observed-private-key.txt"
