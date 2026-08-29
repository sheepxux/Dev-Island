#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$1" >&2
  exit 1
}

BOUNDARY="scripts/release/app-build-output-boundary.rb"
BUILD_SCRIPT="scripts/build-app.sh"
test -x "$BOUNDARY" || fail "App build output boundary is missing or not executable"
ruby -c "$BOUNDARY" >/dev/null || fail "App build output boundary is not valid Ruby"

TEMP_ROOT="$(mktemp -d -t dev-island-build-output)"
TEMP_ROOT="$(cd "$TEMP_ROOT" && pwd -P)"
cleanup() {
  [[ "$TEMP_ROOT" == /private/var/folders/*/T/dev-island-build-output.* \
     || "$TEMP_ROOT" == /var/folders/*/T/dev-island-build-output.* \
     || "$TEMP_ROOT" == /tmp/dev-island-build-output.* ]] \
    && rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT
chmod 0700 "$TEMP_ROOT"

FAKE_REPOSITORY="$TEMP_ROOT/repository"
mkdir -m 0700 "$FAKE_REPOSITORY"
mkdir -m 0700 "$FAKE_REPOSITORY/.git" "$FAKE_REPOSITORY/.build" "$FAKE_REPOSITORY/.swiftpm"

expect_prepare_rejection() {
  local label="$1"
  local path="$2"
  if "$BOUNDARY" prepare --repository-root "$FAKE_REPOSITORY" --build-dir "$path" \
      >"$TEMP_ROOT/$label.output" 2>&1; then
    fail "Unsafe App build directory was accepted: $label"
  fi
  rg -q '^error: ' "$TEMP_ROOT/$label.output" \
    || fail "Unsafe App build directory failed without a bounded diagnostic: $label"
}

expect_prepare_rejection repository-root "$FAKE_REPOSITORY"
expect_prepare_rejection repository-ancestor "$TEMP_ROOT"
expect_prepare_rejection git-directory "$FAKE_REPOSITORY/.git/output"
expect_prepare_rejection swiftpm-scratch "$FAKE_REPOSITORY/.build/output"
expect_prepare_rejection arbitrary-source-directory "$FAKE_REPOSITORY/IslandApp"
expect_prepare_rejection missing-parent "$TEMP_ROOT/missing/child"

UNSAFE_PARENT="$TEMP_ROOT/unsafe-parent"
mkdir -m 0777 "$UNSAFE_PARENT"
expect_prepare_rejection unsafe-parent "$UNSAFE_PARENT/output"
chmod 0700 "$UNSAFE_PARENT"

SAFE_EXTERNAL="$TEMP_ROOT/safe-external"
PREPARED="$($BOUNDARY prepare \
  --repository-root "$FAKE_REPOSITORY" \
  --build-dir "$SAFE_EXTERNAL")"
EXPECTED_SAFE_EXTERNAL="$(cd "$(dirname "$SAFE_EXTERNAL")" && pwd -P)/$(basename "$SAFE_EXTERNAL")"
[[ "$PREPARED" == "$EXPECTED_SAFE_EXTERNAL" && -d "$PREPARED" && ! -L "$PREPARED" ]] \
  || fail "Safe external App build directory was not prepared canonically"
[[ "$(stat -f '%Lp' "$PREPARED")" == "700" ]] \
  || fail "New App build directory is not private"

SYMLINK_BUILD="$TEMP_ROOT/symlink-build"
ln -s "$SAFE_EXTERNAL" "$SYMLINK_BUILD"
expect_prepare_rejection symlink-build "$SYMLINK_BUILD"

WORLD_WRITABLE="$TEMP_ROOT/world-writable"
mkdir -m 0700 "$WORLD_WRITABLE"
chmod 0777 "$WORLD_WRITABLE"
expect_prepare_rejection world-writable "$WORLD_WRITABLE"
chmod 0700 "$WORLD_WRITABLE"

REPO_BUILD="$($BOUNDARY prepare \
  --repository-root "$FAKE_REPOSITORY" \
  --build-dir build)"
[[ "$REPO_BUILD" == "$FAKE_REPOSITORY/build" ]] \
  || fail "Repository-relative build directory did not resolve under build/"

expect_scratch_rejection() {
  local label="$1"
  local path="$2"
  if "$BOUNDARY" prepare-scratch --repository-root "$FAKE_REPOSITORY" --scratch-dir "$path" \
      >"$TEMP_ROOT/$label.scratch-output" 2>&1; then
    fail "Unsafe SwiftPM scratch directory was accepted: $label"
  fi
  rg -q '^error: ' "$TEMP_ROOT/$label.scratch-output" \
    || fail "Unsafe SwiftPM scratch failed without a bounded diagnostic: $label"
}

expect_scratch_rejection scratch-repository-root "$FAKE_REPOSITORY"
expect_scratch_rejection scratch-repository-ancestor "$TEMP_ROOT"
expect_scratch_rejection scratch-build-root "$FAKE_REPOSITORY/.build"
expect_scratch_rejection scratch-git-directory "$FAKE_REPOSITORY/.git/app-production"
expect_scratch_rejection scratch-source-directory "$FAKE_REPOSITORY/IslandCore/app-production"
expect_scratch_rejection scratch-missing-parent "$TEMP_ROOT/missing-scratch/app-production"

REPO_SCRATCH="$($BOUNDARY prepare-scratch \
  --repository-root "$FAKE_REPOSITORY" \
  --scratch-dir "$FAKE_REPOSITORY/.build/app-production")"
[[ "$REPO_SCRATCH" == "$FAKE_REPOSITORY/.build/app-production" \
   && "$(stat -f '%Lp' "$REPO_SCRATCH")" == "700" ]] \
  || fail "Repository-local flavor scratch was not prepared privately"

EXTERNAL_SCRATCH_PARENT="$TEMP_ROOT/external-scratch"
mkdir -m 0700 "$EXTERNAL_SCRATCH_PARENT"
EXTERNAL_SCRATCH="$($BOUNDARY prepare-scratch \
  --repository-root "$FAKE_REPOSITORY" \
  --scratch-dir "$EXTERNAL_SCRATCH_PARENT/app-production")"
[[ "$EXTERNAL_SCRATCH" == "$EXTERNAL_SCRATCH_PARENT/app-production" \
   && "$(stat -f '%Lp' "$EXTERNAL_SCRATCH")" == "700" ]] \
  || fail "External SwiftPM flavor scratch was not prepared privately"

SYMLINK_SCRATCH="$TEMP_ROOT/symlink-scratch"
ln -s "$EXTERNAL_SCRATCH" "$SYMLINK_SCRATCH"
expect_scratch_rejection scratch-symlink "$SYMLINK_SCRATCH"

WRITABLE_SCRATCH="$TEMP_ROOT/writable-scratch"
mkdir -m 0700 "$WRITABLE_SCRATCH"
chmod 0777 "$WRITABLE_SCRATCH"
expect_scratch_rejection scratch-writable "$WRITABLE_SCRATCH"
chmod 0700 "$WRITABLE_SCRATCH"

write_plist() {
  local path="$1"
  local bundle_id="$2"
  ruby - "$path" "$bundle_id" <<'RUBY'
path, bundle_id = ARGV
xml = <<~PLIST
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>#{bundle_id}</string>
    <key>CFBundleExecutable</key><string>IslandApp</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.3.0</string>
    <key>CFBundleVersion</key><string>0.3.0</string>
  </dict></plist>
PLIST
File.binwrite(path, xml)
RUBY
}

make_staged_app() {
  local build_dir="$1"
  local bundle_id="$2"
  local signed="${3:-yes}"
  local stage
  stage="$(mktemp -d "$build_dir/.dev-island-build.XXXXXX")"
  chmod 0700 "$stage"
  mkdir -p "$stage/Dev Island.app/Contents/MacOS"
  cp /usr/bin/true "$stage/Dev Island.app/Contents/MacOS/IslandApp"
  chmod 0755 "$stage/Dev Island.app/Contents/MacOS/IslandApp"
  write_plist "$stage/Dev Island.app/Contents/Info.plist" "$bundle_id"
  if [[ "$signed" == yes ]]; then
    codesign --force --deep --sign - -i "$bundle_id" "$stage/Dev Island.app" >/dev/null 2>&1
  fi
  printf '%s\n' "$stage"
}

publish() {
  local build_dir="$1"
  local stage="$2"
  local bundle_id="$3"
  "$BOUNDARY" publish \
    --repository-root "$FAKE_REPOSITORY" \
    --build-dir "$build_dir" \
    --staging-root "$stage" \
    --bundle-id "$bundle_id"
}

PUBLISH_DIR="$($BOUNDARY prepare \
  --repository-root "$FAKE_REPOSITORY" \
  --build-dir "$TEMP_ROOT/publish")"
FIRST_STAGE="$(make_staged_app "$PUBLISH_DIR" app.devisland.Island)"
PUBLISHED="$(publish "$PUBLISH_DIR" "$FIRST_STAGE" app.devisland.Island)"
[[ "$PUBLISHED" == "$PUBLISH_DIR/Dev Island.app" && -d "$PUBLISHED" && ! -e "$FIRST_STAGE" ]] \
  || fail "Valid staged App was not atomically published"
codesign --verify --deep --strict "$PUBLISHED" \
  || fail "Published App signature did not survive publication"

SECOND_STAGE="$(make_staged_app "$PUBLISH_DIR" app.devisland.Island.PerformanceQA)"
publish "$PUBLISH_DIR" "$SECOND_STAGE" app.devisland.Island.PerformanceQA >/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PUBLISHED/Contents/Info.plist")" == \
  "app.devisland.Island.PerformanceQA" ]] \
  || fail "A valid prior Dev Island generation was not replaceable"
if find "$PUBLISH_DIR" -mindepth 1 -maxdepth 1 \
    \( -name '.dev-island-previous.*' -o -name '.dev-island-failed.*' -o -name '.dev-island-build.*' \) \
    | rg -q .; then
  fail "Successful App publication left private staging or backup paths"
fi

expect_publish_rejection() {
  local label="$1"
  local build_dir="$2"
  local stage="$3"
  local bundle_id="$4"
  if publish "$build_dir" "$stage" "$bundle_id" >"$TEMP_ROOT/$label.publish-output" 2>&1; then
    fail "Unsafe App publication was accepted: $label"
  fi
  rg -q '^error: ' "$TEMP_ROOT/$label.publish-output" \
    || fail "Unsafe App publication failed without a bounded diagnostic: $label"
}

SYMLINK_DEST_DIR="$($BOUNDARY prepare \
  --repository-root "$FAKE_REPOSITORY" \
  --build-dir "$TEMP_ROOT/symlink-destination")"
SYMLINK_SENTINEL="$TEMP_ROOT/symlink-sentinel"
mkdir -m 0700 "$SYMLINK_SENTINEL"
printf 'preserve-me\n' >"$SYMLINK_SENTINEL/marker"
ln -s "$SYMLINK_SENTINEL" "$SYMLINK_DEST_DIR/Dev Island.app"
SYMLINK_STAGE="$(make_staged_app "$SYMLINK_DEST_DIR" app.devisland.Island)"
expect_publish_rejection symlink-destination "$SYMLINK_DEST_DIR" "$SYMLINK_STAGE" app.devisland.Island
[[ "$(cat "$SYMLINK_SENTINEL/marker")" == preserve-me ]] \
  || fail "Symlink destination content was modified"

FILE_DEST_DIR="$($BOUNDARY prepare \
  --repository-root "$FAKE_REPOSITORY" \
  --build-dir "$TEMP_ROOT/file-destination")"
printf 'unrelated-file\n' >"$FILE_DEST_DIR/Dev Island.app"
FILE_STAGE="$(make_staged_app "$FILE_DEST_DIR" app.devisland.Island)"
expect_publish_rejection file-destination "$FILE_DEST_DIR" "$FILE_STAGE" app.devisland.Island
[[ "$(cat "$FILE_DEST_DIR/Dev Island.app")" == unrelated-file ]] \
  || fail "Ordinary destination file was overwritten"

IMPOSTOR_DIR="$($BOUNDARY prepare \
  --repository-root "$FAKE_REPOSITORY" \
  --build-dir "$TEMP_ROOT/impostor-destination")"
IMPOSTOR_STAGE="$(make_staged_app "$IMPOSTOR_DIR" com.example.Unrelated)"
mv "$IMPOSTOR_STAGE/Dev Island.app" "$IMPOSTOR_DIR/Dev Island.app"
rmdir "$IMPOSTOR_STAGE"
VALID_STAGE="$(make_staged_app "$IMPOSTOR_DIR" app.devisland.Island)"
expect_publish_rejection impostor-destination "$IMPOSTOR_DIR" "$VALID_STAGE" app.devisland.Island
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$IMPOSTOR_DIR/Dev Island.app/Contents/Info.plist")" == \
  "com.example.Unrelated" ]] \
  || fail "Unrelated signed App was overwritten"

UNSIGNED_DIR="$($BOUNDARY prepare \
  --repository-root "$FAKE_REPOSITORY" \
  --build-dir "$TEMP_ROOT/unsigned-stage")"
UNSIGNED_STAGE="$(make_staged_app "$UNSIGNED_DIR" app.devisland.Island no)"
expect_publish_rejection unsigned-stage "$UNSIGNED_DIR" "$UNSIGNED_STAGE" app.devisland.Island
[[ ! -e "$UNSIGNED_DIR/Dev Island.app" ]] \
  || fail "Unsigned staged App reached the final destination"

RESTORE_DIR="$($BOUNDARY prepare \
  --repository-root "$FAKE_REPOSITORY" \
  --build-dir "$TEMP_ROOT/preserve-existing")"
RESTORE_FIRST="$(make_staged_app "$RESTORE_DIR" app.devisland.Island)"
publish "$RESTORE_DIR" "$RESTORE_FIRST" app.devisland.Island >/dev/null
ORIGINAL_HASH="$(shasum -a 256 "$RESTORE_DIR/Dev Island.app/Contents/Info.plist" | awk '{print $1}')"
WRONG_ID_STAGE="$(make_staged_app "$RESTORE_DIR" app.devisland.Island.PerformanceQA)"
expect_publish_rejection staged-id-mismatch "$RESTORE_DIR" "$WRONG_ID_STAGE" app.devisland.Island
[[ "$(shasum -a 256 "$RESTORE_DIR/Dev Island.app/Contents/Info.plist" | awk '{print $1}')" == "$ORIGINAL_HASH" ]] \
  || fail "Rejected staged App modified the known-good destination"

OUTSIDE_STAGE_DIR="$($BOUNDARY prepare \
  --repository-root "$FAKE_REPOSITORY" \
  --build-dir "$TEMP_ROOT/outside-stage")"
OUTSIDE_STAGE="$(make_staged_app "$OUTSIDE_STAGE_DIR" app.devisland.Island)"
expect_publish_rejection outside-stage "$RESTORE_DIR" "$OUTSIDE_STAGE" app.devisland.Island

for invariant in \
  'app-build-output-boundary.rb' \
  '.dev-island-build.XXXXXX' \
  '"${OUTPUT_BOUNDARY}" publish' \
  '"${OUTPUT_BOUNDARY}" prepare-scratch' \
  'DEV_ISLAND_SWIFT_SCRATCH_ROOT' \
  '--staging-root "${STAGING_ROOT}"' \
  'App build output boundary is missing or not executable'; do
  rg -Fq -- "$invariant" "$BUILD_SCRIPT" \
    || fail "App build script is missing the staged-output invariant: $invariant"
done
if rg -Fq 'rm -rf "${APP}"' "$BUILD_SCRIPT"; then
  fail "App build script must not recursively delete the final App destination"
fi

echo "App build output boundary: PASS"
