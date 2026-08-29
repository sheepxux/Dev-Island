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
# Output: build/Dev Island.app (Universal Mach-O, arm64+x86_64)
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
PERFORMANCE_QA="${DEV_ISLAND_PERFORMANCE_QA:-0}"
case "${CONFIG}" in
    debug|release)
        ;;
    *)
        echo "error: CONFIG must be debug or release"
        exit 1
        ;;
esac
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
EXEC_NAME="IslandApp"
# Bundle identifier in reverse-DNS form. The product domain is
# devisland.app, so the reverse is `app.devisland.X` where X is the
# stable product code. We use `Island` for X to match the Swift
# target / executable name; the user-facing "Dev Island" name lives
# in CFBundleDisplayName in Info.plist.
BUNDLE_ID="app.devisland.Island"
if [[ "${PERFORMANCE_QA}" == "1" ]]; then
    BUNDLE_ID="app.devisland.Island.PerformanceQA"
elif [[ "${PERFORMANCE_QA}" != "0" ]]; then
    echo "error: DEV_ISLAND_PERFORMANCE_QA must be 0 or 1"
    exit 1
fi
if [[ "${PERFORMANCE_QA}" == "1" && "${CONFIG}" != "release" ]]; then
    echo "error: performance-QA builds must use CONFIG=release"
    exit 1
fi

# SwiftPM does not reliably treat ad-hoc `-Xswiftc -D...` flags as a distinct
# cache identity. Reusing the default `.build` scratch directory allowed a QA
# compile to be considered up-to-date by a later production build, carrying
# fixture-only code into the ordinary executable. Keep production, DEBUG-only
# sandbox, and performance-fixture build graphs physically separate from each
# other and from developer `swift build` / `swift test` output. This also
# avoids a stalled SwiftPM graph when a DEBUG build follows a production build
# in the same long-lived scratch workspace.
SWIFT_SCRATCH_ROOT="${DEV_ISLAND_SWIFT_SCRATCH_ROOT:-${ROOT}/.build}"
if [[ "${PERFORMANCE_QA}" == "1" ]]; then
    SWIFT_SCRATCH_FLAVOR="app-performance-qa"
elif [[ "${CONFIG}" == "debug" ]]; then
    SWIFT_SCRATCH_FLAVOR="app-debug"
else
    SWIFT_SCRATCH_FLAVOR="app-production"
fi
SWIFT_SCRATCH_INPUT="${SWIFT_SCRATCH_ROOT%/}/${SWIFT_SCRATCH_FLAVOR}"

# VERSION is embedded into both Apple bundle version fields and later reused
# for Cask, archive, Appcast and SBOM identity. Never substitute unreviewed
# text through sed or silently relabel an App as 0.1.0 when the source file is
# absent. The shared validator enforces a stable descriptor-backed file and
# Apple's current canonical numeric major.minor.patch policy.
VERSION_VALIDATOR="${ROOT}/scripts/release/validate-product-version.rb"
if [[ ! -x "${VERSION_VALIDATOR}" ]]; then
    echo "error: product-version validator is missing or not executable"
    exit 1
fi
VERSION="$("${VERSION_VALIDATOR}" --version-file "${ROOT}/VERSION")"

# Privacy and Terms are product resources, not website pointers. Validate the
# canonical bilingual documents before dependency resolution so a linked,
# mutable, malformed, date-drifted, or incomplete legal copy can never become
# part of an otherwise valid signed App.
LEGAL_DOCUMENT_VERIFIER="${ROOT}/scripts/release/verify-legal-documents.rb"
if [[ ! -x "${LEGAL_DOCUMENT_VERIFIER}" ]]; then
    echo "error: legal-document verifier is missing or not executable"
    exit 1
fi
"${LEGAL_DOCUMENT_VERIFIER}" \
    --source \
    "${ROOT}/PRIVACY.md" \
    "${ROOT}/TERMS.md"

# BUILD_DIR is caller-controlled for T7 QA builds. Resolve it once through a
# repository-owned ownership/mode/location boundary before any output is
# created. The final App is never assembled in place: a private sibling stage
# is signed and verified first, then published by the same boundary helper.
OUTPUT_BOUNDARY="${ROOT}/scripts/release/app-build-output-boundary.rb"
if [[ ! -x "${OUTPUT_BOUNDARY}" ]]; then
    echo "error: App build output boundary is missing or not executable"
    exit 1
fi
BUILD_DIR="$("${OUTPUT_BOUNDARY}" prepare \
    --repository-root "${ROOT}" \
    --build-dir "${BUILD_DIR}")"
FINAL_APP="${BUILD_DIR}/Dev Island.app"

# The resolved dependency graph is part of the source identity of every App
# artifact. SwiftPM's default behavior may rewrite an absent or stale lock file
# during `swift build`, which would let tests and the final Universal binary use
# different dependency revisions. Reject links/oversized input, force both
# architecture builds to consume the checked-in resolution without automatic
# repair, and verify that the bytes did not drift while the two slices built.
PACKAGE_RESOLVED="${ROOT}/Package.resolved"
if [[ ! -f "${PACKAGE_RESOLVED}" || -L "${PACKAGE_RESOLVED}" ]]; then
    echo "error: Package.resolved must be a regular non-symlink file"
    exit 1
fi
PACKAGE_RESOLVED_BYTES="$(stat -f '%z' "${PACKAGE_RESOLVED}")"
if [[ "${PACKAGE_RESOLVED_BYTES}" -lt 1 || "${PACKAGE_RESOLVED_BYTES}" -gt 1048576 ]]; then
    echo "error: Package.resolved must be between 1 byte and 1 MiB"
    exit 1
fi
PACKAGE_RESOLVED_SHA256="$(shasum -a 256 "${PACKAGE_RESOLVED}" | awk '{print $1}')"

# A caller may place only the build graph outside a File Provider-backed
# checkout (for example on T7 Shield). Resolve the exact flavor directory
# through the same descriptor-oriented boundary used for App publication.
# The default remains the conventional repository-local `.build/<flavor>` in
# CI, while an explicit root avoids dataless cache files stalling SwiftPM.
SWIFT_SCRATCH_DIR="$("${OUTPUT_BOUNDARY}" prepare-scratch \
    --repository-root "${ROOT}" \
    --scratch-dir "${SWIFT_SCRATCH_INPUT}")"

# Sparkle's public Ed25519 key is injected only for authenticated release
# builds. It is public material, but keeping the build-time gate explicit
# prevents a developer build from accidentally pointing at a production feed
# without a complete trust configuration.
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
SPARKLE_FEED_URL="https://github.com/sheepxux/Dev-Island/releases/latest/download/appcast.xml"

if [[ "${PERFORMANCE_QA}" == "1" && -n "${SPARKLE_PUBLIC_ED_KEY}" ]]; then
    echo "error: performance-QA fixtures cannot be combined with a production update key"
    exit 1
fi

if [[ -n "${SPARKLE_PUBLIC_ED_KEY}" ]]; then
    if [[ ! "${SPARKLE_FEED_URL}" =~ ^https:// ]]; then
        echo "error: Sparkle feed must use HTTPS"
        exit 1
    fi
    if ! KEY_BYTES="$(printf '%s' "${SPARKLE_PUBLIC_ED_KEY}" | base64 -D 2>/dev/null | wc -c | tr -d ' ')"; then
        echo "error: SPARKLE_PUBLIC_ED_KEY must be valid base64"
        exit 1
    fi
    if [[ "${KEY_BYTES}" != "32" ]]; then
        echo "error: SPARKLE_PUBLIC_ED_KEY must decode to exactly 32 bytes"
        exit 1
    fi
fi

echo "==> Building IslandApp (${CONFIG}, universal)"
echo "==> SwiftPM scratch: ${SWIFT_SCRATCH_DIR}"
cd "${ROOT}"

# Build for both architectures separately, then lipo. SPM's
# `--arch arm64 --arch x86_64` does support universal in one pass on
# recent toolchains, but we keep the separate-then-lipo path because
# it works reliably across older Xcode versions and produces clearer
# error messages when one arch fails.
build_architecture() {
    local architecture="$1"
    if [[ "${PERFORMANCE_QA}" == "1" ]]; then
        # All package dependencies are public and exactly pinned. Avoid an
        # unnecessary GitHub-credential lookup, which can block indefinitely
        # when a non-interactive or locked Mac cannot unlock Login Keychain.
        swift build --disable-keychain --scratch-path "${SWIFT_SCRATCH_DIR}" \
            --only-use-versions-from-resolved-file \
            -c "${CONFIG}" --arch "${architecture}" \
            --product "${EXEC_NAME}" -Xswiftc -DDEV_ISLAND_PERFORMANCE_QA
    else
        # Bash 3.2 + `set -u` treats an expanded empty array as unbound. Keep
        # the normal release invocation explicit so keyless production/QA
        # builds cannot fail before compilation merely because they have no
        # extra Swift flags.
        swift build --disable-keychain --scratch-path "${SWIFT_SCRATCH_DIR}" \
            --only-use-versions-from-resolved-file \
            -c "${CONFIG}" --arch "${architecture}" \
            --product "${EXEC_NAME}"
    fi
}

if [[ "${PERFORMANCE_QA}" == "1" ]]; then
    echo "==> Performance QA fixture enabled (never publish this bundle)"
fi
build_architecture arm64
build_architecture x86_64

if [[ ! -f "${PACKAGE_RESOLVED}" || -L "${PACKAGE_RESOLVED}" ]]; then
    echo "error: Package.resolved changed type during the Universal build"
    exit 1
fi
if [[ "$(shasum -a 256 "${PACKAGE_RESOLVED}" | awk '{print $1}')" != "${PACKAGE_RESOLVED_SHA256}" ]]; then
    echo "error: Package.resolved changed during the Universal build"
    exit 1
fi

ARM_BIN="${SWIFT_SCRATCH_DIR}/arm64-apple-macosx/${CONFIG}/${EXEC_NAME}"
X86_BIN="${SWIFT_SCRATCH_DIR}/x86_64-apple-macosx/${CONFIG}/${EXEC_NAME}"

echo "==> Lipoing into universal binary"
STAGING_ROOT="$(mktemp -d "${BUILD_DIR}/.dev-island-build.XXXXXX")"
chmod 0700 "${STAGING_ROOT}"
cleanup_staging() {
    if [[ -n "${STAGING_ROOT:-}" \
       && "${STAGING_ROOT}" == "${BUILD_DIR}"/.dev-island-build.* \
       && -d "${STAGING_ROOT}" \
       && ! -L "${STAGING_ROOT}" ]]; then
        rm -rf -- "${STAGING_ROOT}"
    fi
}
trap cleanup_staging EXIT
APP="${STAGING_ROOT}/Dev Island.app"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources" "${APP}/Contents/Frameworks"
lipo -create -output "${APP}/Contents/MacOS/${EXEC_NAME}" "${ARM_BIN}" "${X86_BIN}"
chmod +x "${APP}/Contents/MacOS/${EXEC_NAME}"

# Verify the actual lipo'd executable, not only compiler flags or scratch-path
# names. This rejects both directions of SwiftPM graph leakage: performance
# fixtures in production/debug, and DEBUG-only palette/sandbox/store surfaces
# in either Release-shaped flavor.
BUILD_FLAVOR_VERIFIER="${ROOT}/scripts/ci/verify-performance-fixture-isolation.sh"
if [[ ! -x "${BUILD_FLAVOR_VERIFIER}" ]]; then
    echo "error: build-flavor marker verifier is missing or not executable"
    exit 1
fi
if [[ "${PERFORMANCE_QA}" == "1" ]]; then
    BUILD_FLAVOR="performance-qa"
elif [[ "${CONFIG}" == "debug" ]]; then
    BUILD_FLAVOR="debug"
else
    BUILD_FLAVOR="production"
fi
"${BUILD_FLAVOR_VERIFIER}" \
    --binary "${BUILD_FLAVOR}" \
    "${APP}/Contents/MacOS/${EXEC_NAME}"

# SwiftPM links dynamic binary targets through @rpath but its bare executable
# does not know it will later live inside Contents/MacOS. Add the canonical app
# bundle Frameworks search path to both slices of the lipo'd executable.
install_name_tool \
    -add_rpath '@executable_path/../Frameworks' \
    "${APP}/Contents/MacOS/${EXEC_NAME}"

# SwiftPM may embed the active Xcode toolchain's absolute Swift-library path
# as an LC_RPATH. System Swift libraries resolve through /usr/lib/swift and
# product frameworks must resolve inside Contents/Frameworks, so a shipping
# bundle must never depend on the build Mac's Xcode installation. Remove known
# developer-toolchain paths and fail closed on any other unexpected rpath.
for ARCH in arm64 x86_64; do
    otool -arch "${ARCH}" -l "${APP}/Contents/MacOS/${EXEC_NAME}"
done \
    | awk '$1 == "cmd" && $2 == "LC_RPATH" { found=1; next }
           found && $1 == "path" { print $2; found=0 }' \
    | sort -u \
    | while IFS= read -r RPATH; do
        case "${RPATH}" in
            /usr/lib/swift|@loader_path|@executable_path/../Frameworks)
                ;;
            /Applications/Xcode.app/*|/Library/Developer/*)
                echo "==> Removing developer-only rpath"
                install_name_tool -delete_rpath \
                    "${RPATH}" \
                    "${APP}/Contents/MacOS/${EXEC_NAME}"
                ;;
            *)
                echo "error: unexpected runtime search path in IslandApp"
                exit 1
                ;;
        esac
    done

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

if [[ "${PERFORMANCE_QA}" == "1" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" "${APP}/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Dev Island Performance QA" "${APP}/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName Dev Island Performance QA" "${APP}/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :DevIslandPerformanceFixture bool true" "${APP}/Contents/Info.plist"
elif /usr/libexec/PlistBuddy -c "Print :DevIslandPerformanceFixture" "${APP}/Contents/Info.plist" >/dev/null 2>&1; then
    echo "error: production Info.plist contains the performance-fixture marker"
    exit 1
fi

if [[ -n "${SPARKLE_PUBLIC_ED_KEY}" ]]; then
    /usr/libexec/PlistBuddy -c "Add :SUFeedURL string ${SPARKLE_FEED_URL}" "${APP}/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string ${SPARKLE_PUBLIC_ED_KEY}" "${APP}/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "${APP}/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUScheduledCheckInterval integer 86400" "${APP}/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUAutomaticallyUpdate bool false" "${APP}/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUEnableSystemProfiling bool false" "${APP}/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUVerifyUpdateBeforeExtraction bool true" "${APP}/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SURequireSignedFeed bool true" "${APP}/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUSignedFeedFailureExpirationInterval integer 0" "${APP}/Contents/Info.plist"
    echo "==> Enabled authenticated Sparkle update channel"
else
    echo "==> Sparkle update channel disabled (no release public key)"
fi

# SwiftPM links Sparkle dynamically. Preserve the framework's symlink layout
# exactly; flattening it would invalidate both its load path and code signature.
SPARKLE_FRAMEWORK="${SWIFT_SCRATCH_DIR}/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "${SPARKLE_FRAMEWORK}" ]]; then
    echo "error: Sparkle.framework not found at expected SwiftPM artifact path"
    exit 1
fi
/usr/bin/ditto "${SPARKLE_FRAMEWORK}" "${APP}/Contents/Frameworks/Sparkle.framework"
echo "==> Bundled Sparkle.framework"

if ! otool -L "${APP}/Contents/MacOS/${EXEC_NAME}" | grep '@rpath/Sparkle.framework' >/dev/null; then
    echo "error: IslandApp is not linked to the bundled Sparkle framework"
    exit 1
fi
if ! otool -l "${APP}/Contents/MacOS/${EXEC_NAME}" | grep '@executable_path/../Frameworks' >/dev/null; then
    echo "error: IslandApp is missing the app-bundle Frameworks rpath"
    exit 1
fi
SPARKLE_ARCHS="$(lipo -archs "${APP}/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle")"
if [[ "${SPARKLE_ARCHS}" != *arm64* || "${SPARKLE_ARCHS}" != *x86_64* ]]; then
    echo "error: Sparkle.framework is not universal: ${SPARKLE_ARCHS}"
    exit 1
fi

# Preserve the license notices required by Dev Island and every resolved Swift
# package. Binary redistribution still carries these obligations even when the
# dependency is statically linked and has no user-visible About panel.
LICENSE_DIR="${APP}/Contents/Resources/ThirdPartyLicenses"
mkdir -p "${LICENSE_DIR}"
/usr/bin/install -m 0644 "${ROOT}/LICENSE" "${LICENSE_DIR}/Dev-Island-LICENSE"
for PACKAGE_DIR in "${SWIFT_SCRATCH_DIR}/checkouts/"*; do
    [[ -d "${PACKAGE_DIR}" ]] || continue
    PACKAGE_NAME="$(basename "${PACKAGE_DIR}")"
    for LICENSE_FILE in \
        "${PACKAGE_DIR}/LICENSE" \
        "${PACKAGE_DIR}/LICENSE."* \
        "${PACKAGE_DIR}/COPYING" \
        "${PACKAGE_DIR}/COPYING."*; do
        [[ -f "${LICENSE_FILE}" ]] || continue
        # Checkouts can mark license files read-only. Normalize permissions in
        # the app bundle so xattr cleanup and signing never depend on package
        # checkout metadata.
        /usr/bin/install -m 0644 \
            "${LICENSE_FILE}" \
            "${LICENSE_DIR}/${PACKAGE_NAME}-$(basename "${LICENSE_FILE}")"
    done
done
for LICENSE_FILE in "${ROOT}/scripts/licenses/"*; do
    [[ -f "${LICENSE_FILE}" ]] || continue
    /usr/bin/install -m 0644 \
        "${LICENSE_FILE}" \
        "${LICENSE_DIR}/$(basename "${LICENSE_FILE}")"
done
echo "==> Bundled $(find "${LICENSE_DIR}" -type f | wc -l | tr -d ' ') license notices"

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
"${ROOT}/scripts/release/verify-brand-assets.rb" \
    --manifest "${ROOT}/scripts/assets/agent-logos/manifest.json" \
    --trademark-reviews "${ROOT}/scripts/assets/agent-logos/trademark-reviews.json" \
    --source-dir "${ROOT}/scripts/assets/agent-logos" \
    --bundle-dir "${ROOT}/IslandApp/Resources" \
    --licenses-dir "${ROOT}/scripts/licenses"
for LOGO in "${ROOT}/IslandApp/Resources/"AgentLogo-*.png; do
    [[ -f "${LOGO}" ]] || continue
    cp "${LOGO}" "${APP}/Contents/Resources/$(basename "${LOGO}")"
    echo "==> Bundled $(basename "${LOGO}")"
done

# Short semantic signal sounds are delivered through UNUserNotificationCenter
# so macOS can apply Focus, lock-screen and notification-sound policy. Keep
# filenames stable: TaskNotificationKind references these bundle resources.
for SOUND in "${ROOT}/IslandApp/Resources/"DevIsland-*.wav; do
    [[ -f "${SOUND}" ]] || continue
    /usr/bin/install -m 0644 "${SOUND}" "${APP}/Contents/Resources/$(basename "${SOUND}")"
    echo "==> Bundled $(basename "${SOUND}")"
done

# App-localized resources are authored in IslandAppLib so SwiftPM tests and
# the packaged application share one source of truth. Copy each lproj into
# the main bundle as well: SwiftUI's literal labels resolve through
# Bundle.main, while model-generated strings use L10n's explicit bundle
# lookup. Missing languages are a release error rather than a silent
# English-only artifact.
for LANGUAGE in en zh-Hans; do
    SOURCE_LPROJ="${ROOT}/IslandAppLib/Resources/${LANGUAGE}.lproj"
    if [[ ! -f "${SOURCE_LPROJ}/Localizable.strings" ]]; then
        echo "error: missing localization resource: ${SOURCE_LPROJ}/Localizable.strings"
        exit 1
    fi
    /usr/bin/ditto \
        "${SOURCE_LPROJ}" \
        "${APP}/Contents/Resources/${LANGUAGE}.lproj"
    echo "==> Bundled ${LANGUAGE} localization"
done

# Ship the exact repository-reviewed legal text for offline reading in
# Settings. Do not point the App at website pages that may lag the executable's
# real data flows. The second verifier pass binds the signed bundle bytes back
# to the canonical sources and rejects any extra/unreviewed Legal resource.
LEGAL_RESOURCE_DIR="${APP}/Contents/Resources/Legal"
mkdir -p "${LEGAL_RESOURCE_DIR}"
chmod 0755 "${LEGAL_RESOURCE_DIR}"
/usr/bin/install -m 0644 "${ROOT}/PRIVACY.md" "${LEGAL_RESOURCE_DIR}/PRIVACY.md"
/usr/bin/install -m 0644 "${ROOT}/TERMS.md" "${LEGAL_RESOURCE_DIR}/TERMS.md"
"${LEGAL_DOCUMENT_VERIFIER}" \
    --bundle \
    "${ROOT}/PRIVACY.md" \
    "${ROOT}/TERMS.md" \
    "${LEGAL_RESOURCE_DIR}"
echo "==> Bundled verified offline Privacy and Terms"

ICON_SRC="${ROOT}/IslandApp/Resources/AppIcon.icns"
if [[ -f "${ICON_SRC}" ]]; then
    cp "${ICON_SRC}" "${APP}/Contents/Resources/AppIcon.icns"
    echo "==> Bundled AppIcon.icns"
else
    echo "    (no AppIcon.icns yet — bundle will use generic icon)"
fi

# Validate the complete dynamic-loader closure, not just today's Sparkle
# dependency. Every Mach-O (main executable, framework, XPC service and helper)
# must be Universal, all non-system dependencies must resolve inside the app,
# absolute developer/Homebrew paths are forbidden, and bundle symlinks may not
# escape. This runs before signing so a broken bundle is never legitimized by
# a valid outer signature.
DEPENDENCY_VERIFIER="${ROOT}/scripts/release/verify-app-bundle-dependencies.rb"
if [[ ! -x "${DEPENDENCY_VERIFIER}" ]]; then
    echo "error: app bundle dependency verifier is missing or not executable"
    exit 1
fi
"${DEPENDENCY_VERIFIER}" --app "${APP}"

# Strip extended attributes before signing. macOS automatically tags
# anything copied through Finder / downloaded over the network with
# com.apple.quarantine, com.apple.FinderInfo, etc. — codesign refuses
# to sign in their presence ("resource fork, Finder information, or
# similar detritus not allowed").
echo "==> Stripping extended attributes"

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
sign_and_verify_bundle() {
    # Desktop and File Provider-backed workspaces can immediately reattach
    # forbidden FinderInfo/file-provider attributes while codesign walks a new
    # bundle. Clear the complete tree immediately before every bounded attempt.
    xattr -cr "${APP}"
    xattr -d com.apple.FinderInfo "${APP}" 2>/dev/null || true
    xattr -d 'com.apple.fileprovider.fpfs#P' "${APP}" 2>/dev/null || true
    codesign --force --deep --sign - -i "${BUNDLE_ID}" "${APP}" || return 1
    codesign --verify --strict --deep --verbose=2 "${APP}" || return 1
}

SIGNED=0
for ATTEMPT in 1 2 3; do
    if sign_and_verify_bundle; then
        SIGNED=1
        break
    fi
    echo "==> Signing metadata changed (attempt ${ATTEMPT}/3); cleaning and retrying"
done
if [[ "${SIGNED}" != "1" ]]; then
    echo "error: unable to keep the App free of forbidden extended attributes during signing"
    echo "error: if this workspace is managed by iCloud/File Provider, set BUILD_DIR to a non-File-Provider path (for example a mounted T7 Shield directory)"
    exit 1
fi

PUBLISHED_APP="$("${OUTPUT_BOUNDARY}" publish \
    --repository-root "${ROOT}" \
    --build-dir "${BUILD_DIR}" \
    --staging-root "${STAGING_ROOT}" \
    --bundle-id "${BUNDLE_ID}")"
[[ "${PUBLISHED_APP}" == "${FINAL_APP}" ]] || {
    echo "error: App build output boundary returned an unexpected destination"
    exit 1
}
trap - EXIT
APP="${PUBLISHED_APP}"

echo
echo "==> Built: ${APP}"
du -sh "${APP}"
