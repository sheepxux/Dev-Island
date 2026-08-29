#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="${ROOT}/dist/homebrew-island/Casks/dev-island.rb"
VERSION_VALIDATOR="${ROOT}/scripts/release/validate-product-version.rb"
VERSION_INPUT="${VERSION:-}"
SHA256="${SHA256:-}"
OUTPUT="${OUTPUT:-${ROOT}/build/dev-island.rb}"

[[ -x "${VERSION_VALIDATOR}" ]] \
  || { echo "error: product-version validator is missing" >&2; exit 1; }
VERSION="$("${VERSION_VALIDATOR}" --version "${VERSION_INPUT}")"
if [[ ! "${SHA256}" =~ ^[0-9a-f]{64}$ ]]; then
  echo "error: SHA256 must be exactly 64 lowercase hexadecimal characters" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"
TEMP_OUTPUT="$(mktemp -t dev-island-cask)"
trap 'rm -f "$TEMP_OUTPUT"' EXIT

sed -E \
  -e "s/^  version \"[^\"]+\"$/  version \"${VERSION}\"/" \
  -e "s/^  sha256 \"[0-9a-f]+\"$/  sha256 \"${SHA256}\"/" \
  "$TEMPLATE" > "$TEMP_OUTPUT"

grep -Fq "  version \"${VERSION}\"" "$TEMP_OUTPUT"
grep -Fq "  sha256 \"${SHA256}\"" "$TEMP_OUTPUT"
ruby -c "$TEMP_OUTPUT" >/dev/null
/usr/bin/install -m 0644 "$TEMP_OUTPUT" "$OUTPUT"

echo "Rendered Homebrew Cask: $OUTPUT"
