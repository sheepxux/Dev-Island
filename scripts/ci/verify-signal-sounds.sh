#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$1" >&2
  exit 1
}

SOUND_NAMES=(
  DevIsland-Attention.wav
  DevIsland-Failure.wav
  DevIsland-Completed.wav
)
TEMP_DIR="$(mktemp -d -t dev-island-sounds)"
trap 'rm -rf "$TEMP_DIR"' EXIT

OUTPUT_DIR="$TEMP_DIR" swift scripts/make-signal-sounds.swift >/dev/null

for name in "${SOUND_NAMES[@]}"; do
  committed="IslandApp/Resources/${name}"
  generated="${TEMP_DIR}/${name}"
  test -s "$committed" || fail "Bundled signal sound is missing: $committed"
  cmp -s "$committed" "$generated" \
    || fail "Signal sound drifted from its deterministic source: $name"
  file "$committed" | rg -q 'WAVE audio, Microsoft PCM, 16 bit, mono 44100 Hz' \
    || fail "Signal sound must be 16-bit mono 44.1 kHz PCM: $name"
done

committed_paths=()
for name in "${SOUND_NAMES[@]}"; do
  committed_paths+=("IslandApp/Resources/${name}")
done
hash_count="$(shasum -a 256 "${committed_paths[@]}" | awk '{print $1}' | sort -u | wc -l | tr -d ' ')"
[[ "$hash_count" == "3" ]] || fail "Semantic signal sounds must remain distinct"

for name in "${SOUND_NAMES[@]}"; do
  rg -Fq "$name" IslandAppLib/Notifications/TaskNotifier.swift \
    || fail "TaskNotifier does not reference bundled signal sound: $name"
done
rg -q 'DevIsland-\*\.wav' scripts/build-app.sh \
  || fail "App bundling must copy semantic signal sounds"

echo "Signal sound invariants: PASS"
