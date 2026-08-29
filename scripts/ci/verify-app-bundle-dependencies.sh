#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

VERIFIER="scripts/release/verify-app-bundle-dependencies.rb"

fail() {
  echo "::error::$1" >&2
  exit 1
}

test -x "$VERIFIER" || fail "Executable app bundle dependency verifier is missing"
command -v xcrun >/dev/null || fail "xcrun is required for dependency fixtures"
command -v install_name_tool >/dev/null || fail "install_name_tool is required for dependency fixtures"

FIXTURE_ROOT="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

BASE_APP="$FIXTURE_ROOT/base/Fixture.app"
MAIN="$BASE_APP/Contents/MacOS/Fixture"
LIBRARY="$BASE_APP/Contents/Frameworks/libFixture.dylib"
LIBRARY_SOURCE='int fixture(void) { return 0; }'
MAIN_SOURCE='int fixture(void); int main(void) { return fixture(); }'
mkdir -p "$(dirname "$MAIN")" "$(dirname "$LIBRARY")"

for architecture in arm64 x86_64; do
  library_object="$FIXTURE_ROOT/libFixture.$architecture.o"
  library_binary="$FIXTURE_ROOT/libFixture.$architecture.dylib"
  main_object="$FIXTURE_ROOT/Fixture.$architecture.o"
  main_binary="$FIXTURE_ROOT/Fixture.$architecture"

  printf '%s\n' "$LIBRARY_SOURCE" \
    | xcrun clang -arch "$architecture" -x c -c - -o "$library_object"
  xcrun clang -arch "$architecture" \
    -dynamiclib \
    "$library_object" \
    '-Wl,-install_name,@rpath/libFixture.dylib' \
    -o "$library_binary"

  printf '%s\n' "$MAIN_SOURCE" \
    | xcrun clang -arch "$architecture" -x c -c - -o "$main_object"
  xcrun clang -arch "$architecture" \
    "$main_object" \
    "$library_binary" \
    '-Wl,-headerpad_max_install_names' \
    '-Wl,-rpath,@executable_path/../Frameworks' \
    -o "$main_binary"
done

lipo -create \
  "$FIXTURE_ROOT/libFixture.arm64.dylib" \
  "$FIXTURE_ROOT/libFixture.x86_64.dylib" \
  -output "$LIBRARY"
lipo -create \
  "$FIXTURE_ROOT/Fixture.arm64" \
  "$FIXTURE_ROOT/Fixture.x86_64" \
  -output "$MAIN"

chmod 0755 "$MAIN" "$LIBRARY"

PASS_OUTPUT="$("$VERIFIER" --app "$BASE_APP")"
rg -Fq 'App bundle dependency closure: PASS (2 Mach-O files, arm64+x86_64)' \
  <<<"$PASS_OUTPUT" \
  || fail "Valid Universal fixture did not pass dependency verification"

copy_case() {
  local name="$1"
  local destination="$FIXTURE_ROOT/$name/Fixture.app"
  mkdir -p "$(dirname "$destination")"
  /usr/bin/ditto "$BASE_APP" "$destination"
  printf '%s\n' "$destination"
}

expect_failure() {
  local name="$1"
  local expected="$2"
  local app="$3"
  local output
  local status

  set +e
  output="$("$VERIFIER" --app "$app" 2>&1)"
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || fail "Dependency attack fixture unexpectedly passed: $name"
  rg -Fq "$expected" <<<"$output" \
    || fail "Dependency attack fixture returned the wrong failure: $name"
}

MISSING_APP="$(copy_case missing-library)"
rm "$MISSING_APP/Contents/Frameworks/libFixture.dylib"
expect_failure \
  missing-library \
  'Mach-O has an unresolved bundled dependency' \
  "$MISSING_APP"

THIN_APP="$(copy_case single-architecture)"
lipo -thin arm64 \
  "$THIN_APP/Contents/MacOS/Fixture" \
  -output "$THIN_APP/Contents/MacOS/Fixture.thin"
mv "$THIN_APP/Contents/MacOS/Fixture.thin" "$THIN_APP/Contents/MacOS/Fixture"
expect_failure \
  single-architecture \
  'Mach-O is not exactly arm64+x86_64' \
  "$THIN_APP"

ABSOLUTE_APP="$(copy_case absolute-dependency)"
install_name_tool \
  -change '@rpath/libFixture.dylib' '/opt/homebrew/lib/libFixture.dylib' \
  "$ABSOLUTE_APP/Contents/MacOS/Fixture"
expect_failure \
  absolute-dependency \
  'Mach-O links a developer/external absolute dependency' \
  "$ABSOLUTE_APP"

SYSTEM_TRAVERSAL_APP="$(copy_case system-prefix-traversal)"
install_name_tool \
  -change '@rpath/libFixture.dylib' '/usr/lib/../../opt/homebrew/lib/libFixture.dylib' \
  "$SYSTEM_TRAVERSAL_APP/Contents/MacOS/Fixture"
expect_failure \
  system-prefix-traversal \
  'Mach-O links a developer/external absolute dependency' \
  "$SYSTEM_TRAVERSAL_APP"

RPATH_APP="$(copy_case developer-rpath)"
install_name_tool \
  -add_rpath '/Applications/Xcode.app/Contents/Developer/Toolchains/Untrusted/usr/lib' \
  "$RPATH_APP/Contents/MacOS/Fixture"
expect_failure \
  developer-rpath \
  'Mach-O contains a developer/external absolute rpath' \
  "$RPATH_APP"

LOADER_ESCAPE_APP="$(copy_case loader-escape)"
install_name_tool \
  -change '@rpath/libFixture.dylib' '@loader_path/../../../../tmp/libFixture.dylib' \
  "$LOADER_ESCAPE_APP/Contents/MacOS/Fixture"
expect_failure \
  loader-escape \
  'Mach-O dependency is missing or escapes the bundle' \
  "$LOADER_ESCAPE_APP"

NON_MACHO_APP="$(copy_case non-mach-o-dependency)"
printf '%s\n' 'not a dynamic library' \
  >"$NON_MACHO_APP/Contents/Frameworks/libFixture.dylib"
expect_failure \
  non-mach-o-dependency \
  'Resolved dependency is not Mach-O' \
  "$NON_MACHO_APP"

SYMLINK_APP="$(copy_case symlink-escape)"
ln -s '/tmp' "$SYMLINK_APP/Contents/Frameworks/Escape"
expect_failure \
  symlink-escape \
  'Bundle symlink escapes or is dangling' \
  "$SYMLINK_APP"

echo "App bundle dependency fixtures: PASS"
