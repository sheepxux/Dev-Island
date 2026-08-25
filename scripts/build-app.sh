#!/usr/bin/env bash
# Build a redistributable Island.app bundle from the SPM executable.
#
# Why a script and not an .xcodeproj:
#
# - We're already SPM-native (Package.swift owns the targets, deps,
#   tests). Maintaining a parallel xcodeproj just to produce a .app
#   means duplicating target definitions, resource membership, and
#   build settings — and they drift.
# - The macOS app bundle format is just a directory tree with a plist.
#   `swift build -c release` already produces the binary we need; the
#   only gap is the bundle wrapping, which is ~30 lines of shell.
# - A handful of mature SPM-based menubar apps (Maccy, Itsycal, etc.)
#   ship the same way.
#
# Output: build/Island.app (Universal Mach-O, arm64+x86_64)
#
# What this script does NOT do:
# - codesign / notarize / staple — that's the GitHub Actions release
#   workflow's job (it has access to certificate + Apple ID secrets).
#   Local invocations produce an unsigned bundle for testing only.
# - Bundle cloudflared. The Cask formula declares
#   `depends_on cask: "cloudflared"`; CloudflaredProcess resolves the
#   binary via Homebrew or $PATH at runtime.
#
# Usage:
#   scripts/build-app.sh           # release, universal, unsigned
#   CONFIG=debug scripts/build-app.sh   # debug build (testing only)

set -euo pipefail

CONFIG="${CONFIG:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Override for release-candidate verification outside File Provider-backed
# folders (for example `BUILD_DIR=/Volumes/... ./scripts/build-app.sh`).
# GitHub Actions and normal local builds keep the conventional repo-local path.
BUILD_DIR="${BUILD_DIR:-${ROOT}/build}"
# Bundle filename uses the user-facing display name with a space, so
# Finder shows "Dev Island" everywhere (Applications, Downloads, Dock,
# Spotlight) — not just the locations that consult CFBundleDisplayName.
# The Cask formula's `app "Dev Island.app"` line and the Info.plist
# CFBundleDisplayName must all agree on this name.
APP="${BUILD_DIR}/Dev Island.app"
EXEC_NAME="IslandApp"
# Bundle identifier in reverse-DNS form. The product domain is
# devisland.app, so the reverse is `app.devisland.X` where X is the
# stable product code. We use `Island` for X to match the Swift
# target / executable name; the user-facing "Dev Island" name lives
# in CFBundleDisplayName in Info.plist.
BUNDLE_ID="app.devisland.Island"

# Read version from VERSION file if present, else default. We keep the
# source-of-truth in a top-level VERSION file so the Cask formula and
# GitHub Actions tag-trigger can read the same value.
VERSION="$(cat "${ROOT}/VERSION" 2>/dev/null || echo "0.1.0")"

echo "==> Building IslandApp (${CONFIG}, universal)"
cd "${ROOT}"

# Build for both architectures separately, then lipo. SPM's
# `--arch arm64 --arch x86_64` does support universal in one pass on
# recent toolchains, but we keep the separate-then-lipo path because
# it works reliably across older Xcode versions and produces clearer
# error messages when one arch fails.
swift build -c "${CONFIG}" --arch arm64    --product "${EXEC_NAME}"
swift build -c "${CONFIG}" --arch x86_64   --product "${EXEC_NAME}"

ARM_BIN="${ROOT}/.build/arm64-apple-macosx/${CONFIG}/${EXEC_NAME}"
X86_BIN="${ROOT}/.build/x86_64-apple-macosx/${CONFIG}/${EXEC_NAME}"

echo "==> Lipoing into universal binary"
mkdir -p "${BUILD_DIR}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
lipo -create -output "${APP}/Contents/MacOS/${EXEC_NAME}" "${ARM_BIN}" "${X86_BIN}"
chmod +x "${APP}/Contents/MacOS/${EXEC_NAME}"

# Verify the resulting binary really is universal — caught a regression
# locally once where lipo silently passed through one arch.
echo "==> Verifying universal binary"
file "${APP}/Contents/MacOS/${EXEC_NAME}"
lipo -archs "${APP}/Contents/MacOS/${EXEC_NAME}"

# Info.plist — substitute version. We keep the template alongside the
# script (IslandApp/Resources/Info.plist) so the per-release values
# (CFBundleShortVersionString, CFBundleVersion) can be templated in
# without git churn on the template itself.
echo "==> Writing Info.plist"
sed \
    -e "s/{{VERSION}}/${VERSION}/g" \
    -e "s/{{BUILD}}/${VERSION}/g" \
    "${ROOT}/IslandApp/Resources/Info.plist" \
    > "${APP}/Contents/Info.plist"

# Icon — optional. We don't fail the build if it's missing so the
# script is usable before the icon is finalized; a missing icon just
# means macOS shows the generic "?"-in-document silhouette.
# Optional designer-supplied menu-bar icon (see StatusItemController).
# Both densities are copied when present; absence falls back to the
# built-in SF Symbol at runtime, so this is never an error.
for MB_ICON in "MenuBarIcon.png" "MenuBarIcon@2x.png"; do
    if [[ -f "${ROOT}/IslandApp/Resources/${MB_ICON}" ]]; then
        cp "${ROOT}/IslandApp/Resources/${MB_ICON}" "${APP}/Contents/Resources/${MB_ICON}"
        echo "==> Bundled ${MB_ICON}"
    fi
done

# Per-agent brand logos (template PNGs from scripts/make-agent-logos.swift).
# Glob-copied so adding an agent is: drop SVG, re-run the script — no build
# script edit. AgentBrand falls back to a monogram when an asset is absent.
for LOGO in "${ROOT}/IslandApp/Resources/"AgentLogo-*.png; do
    [[ -f "${LOGO}" ]] || continue
    cp "${LOGO}" "${APP}/Contents/Resources/$(basename "${LOGO}")"
    echo "==> Bundled $(basename "${LOGO}")"
done

ICON_SRC="${ROOT}/IslandApp/Resources/AppIcon.icns"
if [[ -f "${ICON_SRC}" ]]; then
    cp "${ICON_SRC}" "${APP}/Contents/Resources/AppIcon.icns"
    echo "==> Bundled AppIcon.icns"
else
    echo "    (no AppIcon.icns yet — bundle will use generic icon)"
fi

# Strip extended attributes before signing. macOS automatically tags
# anything copied through Finder / downloaded over the network with
# com.apple.quarantine, com.apple.FinderInfo, etc. — codesign refuses
# to sign in their presence ("resource fork, Finder information, or
# similar detritus not allowed").
echo "==> Stripping extended attributes"
xattr -cr "${APP}"
# Desktop and File Provider-backed workspaces can immediately reattach these
# bundle-root attributes even after a recursive clear. Both are forbidden on
# signed code, so remove them explicitly at the last possible moment before
# codesign. (They are absent on GitHub runners, but keeping the local artifact
# clean makes the release script reproducible everywhere.)
xattr -d com.apple.FinderInfo "${APP}" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "${APP}" 2>/dev/null || true

# Ad-hoc sign so Gatekeeper at least recognizes a code signature
# structure. This is NOT a substitute for Developer ID + notarization
# (which the release workflow handles); it just makes the local build
# launch-able after right-click → Open without a corrupted-signature
# error on recent macOS.
#
# `-i app.devisland.Island` binds the bundle identifier into the signature,
# matching CFBundleIdentifier in Info.plist. Without `-i`, codesign
# defaults to the executable name (IslandApp), which fails subsequent
# `codesign --verify --strict` because the identifier doesn't match
# the plist.
echo "==> Ad-hoc signing (replace with Developer ID in CI)"
if ! codesign --force --deep --sign - -i "${BUNDLE_ID}" "${APP}"; then
    # Some File Provider implementations attach FinderInfo when codesign first
    # discovers the new .app. Clear once more and retry; a real signing error
    # still fails on the second invocation because set -e remains active.
    echo "==> Metadata changed during signing; cleaning once and retrying"
    xattr -cr "${APP}"
    xattr -d com.apple.FinderInfo "${APP}" 2>/dev/null || true
    xattr -d 'com.apple.fileprovider.fpfs#P' "${APP}" 2>/dev/null || true
    codesign --force --deep --sign - -i "${BUNDLE_ID}" "${APP}"
fi
if ! codesign --verify --strict --deep --verbose=2 "${APP}"; then
    # The metadata race can also land immediately after a successful sign but
    # before verification. One final clean + re-sign closes that window.
    echo "==> Metadata changed after signing; cleaning once and retrying"
    xattr -cr "${APP}"
    xattr -d com.apple.FinderInfo "${APP}" 2>/dev/null || true
    xattr -d 'com.apple.fileprovider.fpfs#P' "${APP}" 2>/dev/null || true
    codesign --force --deep --sign - -i "${BUNDLE_ID}" "${APP}"
    codesign --verify --strict --deep --verbose=2 "${APP}"
fi

echo
echo "==> Built: ${APP}"
du -sh "${APP}"
