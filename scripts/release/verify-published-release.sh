#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "error: $1" >&2
  exit 1
}

if [[ $# -ne 1 ]]; then
  echo "Usage: verify-published-release.sh vX.Y.Z" >&2
  exit 64
fi

TAG="$1"
[[ "$TAG" == v* ]] || fail "tag must begin with v"
VERSION_VALIDATOR="$ROOT/scripts/release/validate-product-version.rb"
test -x "$VERSION_VALIDATOR" || fail "product-version validator is missing"
VERSION="$("$VERSION_VALIDATOR" --version "${TAG#v}")"
REPOSITORY="sheepxux/Dev-Island"
SIGNER_WORKFLOW="github.com/${REPOSITORY}/.github/workflows/release.yml"
SOURCE_REF="refs/tags/${TAG}"
LOCAL_VERIFIER="$ROOT/scripts/release/verify-release-assets.sh"
METADATA_VALIDATOR="$ROOT/scripts/release/validate-published-release-metadata.rb"

command -v gh >/dev/null 2>&1 || fail "GitHub CLI is required"
test -x "$LOCAL_VERIFIER" || fail "repository-owned Release asset verifier is unavailable"
test -x "$METADATA_VALIDATOR" || fail "repository-owned Release metadata validator is unavailable"
gh auth status --hostname github.com >/dev/null 2>&1 \
  || fail "GitHub CLI is not authenticated for github.com"

TEMP_DIR="$(mktemp -d -t dev-island-published-release)"
cleanup() {
  [[ "$TEMP_DIR" == /private/var/folders/*/T/dev-island-published-release.* \
     || "$TEMP_DIR" == /var/folders/*/T/dev-island-published-release.* \
     || "$TEMP_DIR" == /tmp/dev-island-published-release.* ]] \
    && rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

RELEASE_JSON="$TEMP_DIR/release.json"
if ! gh api "repos/${REPOSITORY}/releases/tags/${TAG}" >"$RELEASE_JSON"; then
  fail "published GitHub Release does not exist: ${TAG}"
fi
"$METADATA_VALIDATOR" --json "$RELEASE_JSON" --tag "$TAG"

SOURCE_REVISION="$(gh api "repos/${REPOSITORY}/commits/${TAG}" --jq '.sha')"
[[ "$SOURCE_REVISION" =~ ^[0-9a-f]{40}$ ]] \
  || fail "GitHub did not resolve the tag to a commit SHA"

ASSET_DIR="$TEMP_DIR/assets"
mkdir "$ASSET_DIR"
gh release download "$TAG" --repo "$REPOSITORY" --dir "$ASSET_DIR"

"$LOCAL_VERIFIER" \
  --tag "$TAG" \
  --asset-dir "$ASSET_DIR" \
  --source-revision "$SOURCE_REVISION"

ATTESTATION_FLAGS=(
  --repo "$REPOSITORY"
  --signer-workflow "$SIGNER_WORKFLOW"
  --source-ref "$SOURCE_REF"
  --source-digest "$SOURCE_REVISION"
  --deny-self-hosted-runners
)

ASSETS=(
  "Dev-Island.dmg"
  "Dev-Island-${VERSION}.dmg"
  "Dev-Island.zip"
  "Dev-Island-${VERSION}.zip"
  "Dev-Island.spdx.json"
  "SHA256SUMS"
  "appcast.xml"
  "dev-island.rb"
)
for asset in "${ASSETS[@]}"; do
  gh attestation verify "$ASSET_DIR/$asset" \
    "${ATTESTATION_FLAGS[@]}" >/dev/null
  echo "Verified build provenance: $asset"
done

for asset in \
  "Dev-Island.dmg" \
  "Dev-Island-${VERSION}.dmg" \
  "Dev-Island.zip" \
  "Dev-Island-${VERSION}.zip"; do
  gh attestation verify "$ASSET_DIR/$asset" \
    "${ATTESTATION_FLAGS[@]}" \
    --predicate-type "https://spdx.dev/Document" >/dev/null
  echo "Verified SPDX attestation: $asset"
done

echo "Published Release verification: PASS (${TAG}, ${SOURCE_REVISION})"
