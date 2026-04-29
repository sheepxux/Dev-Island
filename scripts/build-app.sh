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
BUILD_DIR="${ROOT}/build"
APP="${BUILD_DIR}/Island.app"
EXEC_NAME="IslandApp"
BUNDLE_ID="com.island.app"

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

# Ad-hoc sign so Gatekeeper at least recognizes a code signature
# structure. This is NOT a substitute for Developer ID + notarization
# (which the release workflow handles); it just makes the local build
# launch-able after right-click → Open without a corrupted-signature
# error on recent macOS.
#
# `-i com.island.app` binds the bundle identifier into the signature,
# matching CFBundleIdentifier in Info.plist. Without `-i`, codesign
# defaults to the executable name (IslandApp), which fails subsequent
# `codesign --verify --strict` because the identifier doesn't match
# the plist.
echo "==> Ad-hoc signing (replace with Developer ID in CI)"
codesign --force --deep --sign - -i "${BUNDLE_ID}" "${APP}"
codesign --verify --verbose=2 "${APP}"

echo
echo "==> Built: ${APP}"
du -sh "${APP}"
