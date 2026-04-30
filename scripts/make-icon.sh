#!/usr/bin/env bash
# Convert a square PNG into AppIcon.icns and drop it where build-app.sh
# will pick it up.
#
# Usage:
#   scripts/make-icon.sh <path-to-source.png>
#
# Source PNG must be square and at least 512×512 (1024×1024 ideal —
# any smaller and the 512@2x slice gets upscaled and the icon looks
# fuzzy on Retina displays). We don't enforce a hard minimum because
# `sips` will silently upscale if asked, but the script prints a
# warning when source < 1024.
#
# Output: IslandApp/Resources/AppIcon.icns
#
# How `iconutil` works:
#
# It expects a folder named `*.iconset/` containing exactly these 10
# files (Apple's required set per
# https://developer.apple.com/design/human-interface-guidelines/app-icons):
#
#   icon_16x16.png       icon_16x16@2x.png
#   icon_32x32.png       icon_32x32@2x.png
#   icon_128x128.png     icon_128x128@2x.png
#   icon_256x256.png     icon_256x256@2x.png
#   icon_512x512.png     icon_512x512@2x.png
#
# `@2x` files are physically twice the listed dimension (so 16x16@2x is
# really 32×32, etc.) — macOS picks the right one based on display
# density at runtime.
#
# We use `sips` (macOS-native) for resizing rather than ImageMagick to
# avoid a brew dependency for icon generation.

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <path-to-source.png>" >&2
    exit 64
fi

SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RES_DIR="${ROOT}/IslandApp/Resources"
OUT_ICNS="${RES_DIR}/AppIcon.icns"

if [[ ! -f "${SRC}" ]]; then
    echo "Error: source PNG not found at ${SRC}" >&2
    exit 1
fi

# Sanity-check dimensions. sips emits "  pixelWidth: NNNN" etc.
WIDTH="$(sips -g pixelWidth "${SRC}" | awk '/pixelWidth:/ {print $2}')"
HEIGHT="$(sips -g pixelHeight "${SRC}" | awk '/pixelHeight:/ {print $2}')"

if [[ "${WIDTH}" != "${HEIGHT}" ]]; then
    echo "Warning: source is ${WIDTH}×${HEIGHT}, not square. macOS will" >&2
    echo "         non-uniformly scale; consider cropping to square first." >&2
fi
if [[ "${WIDTH}" -lt 1024 ]]; then
    echo "Warning: source is ${WIDTH}px wide; ideal is 1024+. The" >&2
    echo "         512@2x slice (1024×1024) will be upscaled and look" >&2
    echo "         soft on Retina displays." >&2
fi

# Build the .iconset/ tree in a tmp dir so a failure mid-way doesn't
# leave half-baked output in the repo.
TMP_ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "${TMP_ICONSET}"

# Pairs of (filename, target-pixel-size). @2x sizes are listed at their
# real pixel dimensions, not the @1x label.
SIZES=(
    "icon_16x16.png:16"
    "icon_16x16@2x.png:32"
    "icon_32x32.png:32"
    "icon_32x32@2x.png:64"
    "icon_128x128.png:128"
    "icon_128x128@2x.png:256"
    "icon_256x256.png:256"
    "icon_256x256@2x.png:512"
    "icon_512x512.png:512"
    "icon_512x512@2x.png:1024"
)

echo "==> Generating 10 icon sizes from ${SRC}"
for entry in "${SIZES[@]}"; do
    NAME="${entry%%:*}"
    PX="${entry##*:}"
    sips -z "${PX}" "${PX}" "${SRC}" --out "${TMP_ICONSET}/${NAME}" >/dev/null
done

echo "==> Compiling AppIcon.icns"
mkdir -p "${RES_DIR}"
iconutil -c icns "${TMP_ICONSET}" -o "${OUT_ICNS}"
rm -rf "$(dirname "${TMP_ICONSET}")"

echo "==> Wrote: ${OUT_ICNS}"
ls -lh "${OUT_ICNS}"
