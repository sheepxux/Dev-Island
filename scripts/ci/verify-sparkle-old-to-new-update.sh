#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$ROOT/scripts/qa/sparkle-live-gate-helper.rb"
DISPOSABLE_SOURCE_PREPARER="$ROOT/scripts/qa/prepare-sparkle-disposable-source.rb"
PACKAGE_RESOLVED="$ROOT/Package.resolved"
SPARKLE_CHECKOUT="$ROOT/.build/checkouts/Sparkle"
SPARKLE_REVISION="ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a"
SPARKLE_VERSION="2.9.6"
SPARKLE_ARTIFACT="$ROOT/.build/artifacts/sparkle/Sparkle"
SPARKLE_FRAMEWORK="$SPARKLE_ARTIFACT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
SIGN_UPDATE="$SPARKLE_ARTIFACT/bin/sign_update"
FIXTURE_PRIVATE_KEY='nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A='
FIXTURE_PUBLIC_KEY='11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo='
MISMATCHED_PRIVATE_KEY='TM0Imyj/ltqdtsNG7BFOD1uKMZ81q6Yk2oz27U+4pvs='
MISMATCHED_PUBLIC_KEY='PUAXw+hDiVqStwqnTRt+vJyYLM8uxJaMwM1V8Sr0Zgw='

fail() {
  echo "error: $1" >&2
  exit 1
}

for tool in /bin/ps /usr/bin/codesign /usr/bin/ditto /usr/bin/ruby /usr/bin/stat /usr/bin/xcrun; do
  test -x "$tool" || fail "required macOS tool is unavailable: ${tool##*/}"
done
test -x "$HELPER" || fail "Sparkle live-gate helper is unavailable"
test -x "$DISPOSABLE_SOURCE_PREPARER" && test ! -L "$DISPOSABLE_SOURCE_PREPARER" \
  || fail "Sparkle disposable-source preparer is unavailable"
test -f "$PACKAGE_RESOLVED" && test ! -L "$PACKAGE_RESOLVED" \
  || fail "Package.resolved is missing or unsafe"
test -d "$SPARKLE_CHECKOUT" && test ! -L "$SPARKLE_CHECKOUT" \
  || fail "pinned Sparkle checkout is unavailable"
test -x "$SIGN_UPDATE" && test ! -L "$SIGN_UPDATE" \
  || fail "pinned Sparkle sign_update is unavailable"
test -d "$SPARKLE_FRAMEWORK" && test ! -L "$SPARKLE_FRAMEWORK" \
  || fail "pinned Sparkle framework is unavailable"

/usr/bin/ruby -rjson -e '
  path, expected_version, expected_revision = ARGV
  document = JSON.parse(File.binread(path))
  pins = document.fetch("pins")
  sparkle = pins.select { |pin| pin["identity"] == "sparkle" }
  abort("Sparkle Package.resolved pin is not unique") unless sparkle.length == 1
  state = sparkle.fetch(0).fetch("state")
  abort("Sparkle version pin drifted") unless state["version"] == expected_version
  abort("Sparkle revision pin drifted") unless state["revision"] == expected_revision
' "$PACKAGE_RESOLVED" "$SPARKLE_VERSION" "$SPARKLE_REVISION" \
  || fail "Sparkle dependency pin validation failed"
[[ "$(git -C "$SPARKLE_CHECKOUT" rev-parse HEAD)" == "$SPARKLE_REVISION" ]] \
  || fail "Sparkle checkout revision drifted"
[[ -z "$(git -C "$SPARKLE_CHECKOUT" status --porcelain --untracked-files=all)" ]] \
  || fail "Sparkle checkout is dirty"
/usr/bin/codesign --verify --deep --strict "$SPARKLE_FRAMEWORK" 2>/dev/null \
  || fail "Sparkle framework code signature is invalid"
/usr/bin/codesign --verify --strict "$SIGN_UPDATE" 2>/dev/null \
  || fail "Sparkle sign_update code signature is invalid"

umask 077
# Sparkle's launchd-managed installer helpers require a local runtime volume.
# Keep the entire run in macOS's private per-user temporary directory while
# still replacing HOME and all cache/preference roots with disposable paths.
TEMP_ROOT="$(mktemp -d -t dev-island-sparkle-old-to-new)"
chmod 0700 "$TEMP_ROOT"

SERVER_PID=""
RUN_TOKEN="$(/usr/bin/ruby -rsecurerandom -e 'print SecureRandom.hex(6)')"
[[ "$RUN_TOKEN" =~ ^[0-9a-f]{12}$ ]] || fail "fixture run token is invalid"
CLI_BUNDLE_ID="app.devisland.sparkle-cli-live-gate.$RUN_TOKEN"
DISPOSABLE_ROOT="$TEMP_ROOT/disposable-runtime"
DISPOSABLE_HOME="$DISPOSABLE_ROOT/home"
BUILD_HOME="$DISPOSABLE_ROOT/build-home"
DISPOSABLE_TMP="$DISPOSABLE_ROOT/tmp"
SOURCE_COPY="$DISPOSABLE_ROOT/Sparkle"
SOURCE_PRODUCTS="$DISPOSABLE_ROOT/products"
SOURCE_INTERMEDIATES="$DISPOSABLE_ROOT/intermediates"
SOURCE_BUILD_LOG="$DISPOSABLE_ROOT/source-build.log"
mkdir -p "$DISPOSABLE_HOME" "$BUILD_HOME" "$DISPOSABLE_TMP" \
  "$DISPOSABLE_HOME/Library/Caches" \
  "$DISPOSABLE_HOME/Library/Preferences" \
  "$BUILD_HOME/Library/Caches" \
  "$BUILD_HOME/Library/Preferences"
chmod 0700 "$DISPOSABLE_ROOT" "$DISPOSABLE_HOME" "$BUILD_HOME" "$DISPOSABLE_TMP"
chmod 0700 "$DISPOSABLE_HOME/Library" \
  "$DISPOSABLE_HOME/Library/Caches" \
  "$DISPOSABLE_HOME/Library/Preferences" \
  "$BUILD_HOME/Library" \
  "$BUILD_HOME/Library/Caches" \
  "$BUILD_HOME/Library/Preferences"

disposable_helpers_present() {
  local pid
  local command_line
  while read -r pid command_line; do
    case "$command_line" in
      "$TEMP_ROOT/"*'/Autoupdate'|"$TEMP_ROOT/"*'/Autoupdate '*|\
      "$TEMP_ROOT/"*'/Updater.app/Contents/MacOS/Updater'|"$TEMP_ROOT/"*'/Updater.app/Contents/MacOS/Updater '*)
        return 0
        ;;
    esac
  done < <(/bin/ps -wwaxo pid=,command= 2>/dev/null)
  return 1
}

signal_disposable_helpers() {
  local signal="$1"
  local pid
  local command_line
  while read -r pid command_line; do
    case "$command_line" in
      "$TEMP_ROOT/"*'/Autoupdate'|"$TEMP_ROOT/"*'/Autoupdate '*|\
      "$TEMP_ROOT/"*'/Updater.app/Contents/MacOS/Updater'|"$TEMP_ROOT/"*'/Updater.app/Contents/MacOS/Updater '*)
        kill -"$signal" "$pid" 2>/dev/null || true
        ;;
    esac
  done < <(/bin/ps -wwaxo pid=,command= 2>/dev/null)
}

cleanup() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill -TERM "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  signal_disposable_helpers TERM
  for _ in {1..100}; do
    disposable_helpers_present || break
    sleep 0.02
  done
  if disposable_helpers_present; then
    signal_disposable_helpers KILL
    for _ in {1..100}; do
      disposable_helpers_present || break
      sleep 0.02
    done
  fi
  case "$TEMP_ROOT" in
    '/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/tmp/sparkle-old-to-new.'*|/private/var/folders/*/T/dev-island-sparkle-old-to-new.*|/var/folders/*/T/dev-island-sparkle-old-to-new.*|/tmp/dev-island-sparkle-old-to-new.*)
      find "$TEMP_ROOT" -depth -delete 2>/dev/null || true
      ;;
  esac
}
trap cleanup EXIT INT TERM

CLI_APP="$TEMP_ROOT/sparkle.app"
CLI_EXECUTABLE="$CLI_APP/Contents/MacOS/sparkle"
mkdir -p "$CLI_APP/Contents/MacOS" "$CLI_APP/Contents/Frameworks" "$TEMP_ROOT/modules"
ARCH_NAME="$(uname -m)"
[[ "$ARCH_NAME" == arm64 || "$ARCH_NAME" == x86_64 ]] \
  || fail "unsupported live-gate architecture"

/usr/bin/ditto --norsrc "$SPARKLE_CHECKOUT" "$SOURCE_COPY"
chmod -R go-rwx,u+rwX "$SOURCE_COPY"
"$DISPOSABLE_SOURCE_PREPARER" \
  "$SOURCE_COPY" \
  "$DISPOSABLE_ROOT" \
  "$DISPOSABLE_HOME" \
  "$DISPOSABLE_TMP" >/dev/null

set +e
env -i \
  PATH='/usr/bin:/bin:/usr/sbin:/sbin' \
  HOME="$BUILD_HOME" \
  CFFIXED_USER_HOME="$BUILD_HOME" \
  TMPDIR="$DISPOSABLE_TMP/" \
  __CFPREFERENCES_AVOID_DAEMON='1' \
  /usr/bin/xcodebuild \
    -project "$SOURCE_COPY/Sparkle.xcodeproj" \
    -target Sparkle \
    -configuration Release \
    -arch "$ARCH_NAME" \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGN_IDENTITY=- \
    SYMROOT="$SOURCE_PRODUCTS" \
    OBJROOT="$SOURCE_INTERMEDIATES" \
    CLANG_MODULE_CACHE_PATH="$DISPOSABLE_ROOT/module-cache" \
    SHARED_PRECOMPS_DIR="$DISPOSABLE_ROOT/precompiled-headers" \
    -disableAutomaticPackageResolution \
    build >"$SOURCE_BUILD_LOG" 2>&1
source_build_result=$?
set -e
if [[ "$source_build_result" -ne 0 ]]; then
  tail -n 120 "$SOURCE_BUILD_LOG" >&2
  fail "offline disposable Sparkle source build failed"
fi
LIVE_SPARKLE_FRAMEWORK="$SOURCE_PRODUCTS/Release/Sparkle.framework"
test -d "$LIVE_SPARKLE_FRAMEWORK" && test ! -L "$LIVE_SPARKLE_FRAMEWORK" \
  || fail "offline disposable Sparkle framework was not produced"
/usr/bin/codesign --verify --deep --strict "$LIVE_SPARKLE_FRAMEWORK" 2>/dev/null \
  || fail "offline disposable Sparkle framework signature is invalid"
LIVE_AUTOUPDATE="$LIVE_SPARKLE_FRAMEWORK/Versions/B/Autoupdate"
test -x "$LIVE_AUTOUPDATE" && test ! -L "$LIVE_AUTOUPDATE" \
  || fail "offline disposable Sparkle Autoupdate helper is unavailable"
AUTOUPDATE_ENTITLEMENTS="$DISPOSABLE_ROOT/autoupdate-entitlements.plist"
/usr/bin/codesign -d --entitlements :- "$LIVE_AUTOUPDATE" \
  >"$AUTOUPDATE_ENTITLEMENTS" 2>/dev/null \
  || fail "offline disposable Sparkle Autoupdate entitlements are unavailable"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.application-identifier' \
  "$AUTOUPDATE_ENTITLEMENTS" 2>/dev/null)" == \
  'org.sparkle-project.Sparkle.Autoupdate' ]] \
  || fail "offline disposable Sparkle Autoupdate identity is invalid"

/usr/bin/xcrun clang \
  -arch "$ARCH_NAME" \
  -fobjc-arc \
  -fmodules \
  -fmodules-cache-path="$TEMP_ROOT/modules" \
  -mmacosx-version-min=13.0 \
  '-DSPU_OBJC_DIRECT=__attribute__((objc_direct))' \
  '-DSPU_OBJC_DIRECT_MEMBERS=__attribute__((objc_direct_members))' \
  -F "$(dirname "$LIVE_SPARKLE_FRAMEWORK")" \
  "$SPARKLE_CHECKOUT/sparkle-cli/main.m" \
  "$SPARKLE_CHECKOUT/sparkle-cli/SPUCommandLineDriver.m" \
  "$SPARKLE_CHECKOUT/sparkle-cli/SPUCommandLineUserDriver.m" \
  -framework Foundation \
  -framework AppKit \
  -framework Sparkle \
  '-Wl,-rpath,@executable_path/../Frameworks/' \
  -o "$CLI_EXECUTABLE"

/usr/bin/ruby - "$CLI_APP/Contents/Info.plist" "$CLI_BUNDLE_ID" <<'RUBY'
path, bundle_id = ARGV
abort("invalid CLI bundle identifier") unless bundle_id.match?(/\Aapp\.devisland\.sparkle-cli-live-gate\.[0-9a-f]{12}\z/)
File.binwrite(path, <<~PLIST)
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>sparkle</string>
    <key>CFBundleIdentifier</key><string>#{bundle_id}</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>sparkle</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>2.9.6</string>
    <key>CFBundleVersion</key><string>2.9.6</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
  </dict></plist>
PLIST
RUBY
/usr/bin/ditto "$LIVE_SPARKLE_FRAMEWORK" "$CLI_APP/Contents/Frameworks/Sparkle.framework"
CLI_FRAMEWORK="$CLI_APP/Contents/Frameworks/Sparkle.framework"
/usr/bin/codesign --verify --deep --strict "$CLI_FRAMEWORK" 2>/dev/null \
  || fail "copied Sparkle framework signature is invalid"
/usr/bin/codesign --force --sign - --timestamp=none "$CLI_APP" >/dev/null 2>&1
/usr/bin/codesign --verify --deep --strict "$CLI_APP" 2>/dev/null \
  || fail "offline-built Sparkle CLI bundle is invalid"

KEY_DIR="$TEMP_ROOT/keys"
mkdir -p "$KEY_DIR"
printf '%s\n' "$FIXTURE_PRIVATE_KEY" >"$KEY_DIR/correct.key"
printf '%s\n' "$MISMATCHED_PRIVATE_KEY" >"$KEY_DIR/mismatched.key"
chmod 0600 "$KEY_DIR/correct.key" "$KEY_DIR/mismatched.key"

make_fixture_app() {
  local app_path="$1"
  local bundle_id="$2"
  local version="$3"
  local marker="$4"
  local signer="$5"
  local public_key="$6"
  local source_path="${app_path%/*}/fixture-${marker}.c"
  local requirement

  mkdir -p "$app_path/Contents/MacOS"
  /usr/bin/ruby -e '
    path, marker = ARGV
    abort("invalid marker") unless marker.match?(/\A[a-z-]+\z/)
    File.binwrite(path, <<~SOURCE)
      #include <stdio.h>
      static const char *dev_island_fixture_marker = "#{marker}";
      int main(void) {
        puts(dev_island_fixture_marker);
        return 0;
      }
    SOURCE
  ' "$source_path" "$marker"
  /usr/bin/xcrun clang -arch "$ARCH_NAME" -Os "$source_path" \
    -o "$app_path/Contents/MacOS/DevIslandFixture"
  /usr/bin/ruby - "$app_path/Contents/Info.plist" "$bundle_id" \
    "$version" "$signer" "$public_key" <<'RUBY'
path, bundle_id, version, signer, public_key = ARGV
values = [bundle_id, version, signer, public_key]
abort("unsafe fixture plist value") unless values.all? { |value| value.match?(/\A[A-Za-z0-9.+\/= -]+\z/) }
File.binwrite(path, <<~PLIST)
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>DevIslandFixture</string>
    <key>CFBundleIdentifier</key><string>#{bundle_id}</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Dev Island</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>#{version}</string>
    <key>CFBundleVersion</key><string>#{version}</string>
    <key>DevIslandFixtureSigner</key><string>#{signer}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
    <key>SUPublicEDKey</key><string>#{public_key}</string>
    <key>SUEnableAutomaticChecks</key><false/>
    <key>SUVerifyUpdateBeforeExtraction</key><true/>
    <key>SURequireSignedFeed</key><true/>
    <key>SUSignedFeedFailureExpirationInterval</key><integer>0</integer>
  </dict></plist>
PLIST
RUBY
  requirement="=designated => identifier \"$bundle_id\" and info[DevIslandFixtureSigner] = \"$signer\""
  /usr/bin/codesign --force --sign - --timestamp=none \
    --requirements "$requirement" "$app_path" >/dev/null 2>&1
  /usr/bin/codesign --verify --deep --strict "$app_path" 2>/dev/null \
    || fail "fixture App code signature is invalid"
}

SERVE_ROOT="$TEMP_ROOT/server"
RUNTIME_ROOT="$TEMP_ROOT/runtime"
mkdir -p "$SERVE_ROOT" "$RUNTIME_ROOT"
chmod 0700 "$SERVE_ROOT" "$RUNTIME_ROOT"
PORT_FILE="$RUNTIME_ROOT/port"
SERVER_LOG="$RUNTIME_ROOT/server.log"
"$HELPER" serve "$SERVE_ROOT" "$PORT_FILE" "$SERVER_LOG" &
SERVER_PID=$!
for _ in {1..200}; do
  [[ -s "$PORT_FILE" ]] && break
  kill -0 "$SERVER_PID" 2>/dev/null || fail "loopback fixture server exited before readiness"
  sleep 0.02
done
[[ -s "$PORT_FILE" ]] || fail "loopback fixture server did not become ready"
PORT="$(tr -d '\n' <"$PORT_FILE")"
[[ "$PORT" =~ ^[1-9][0-9]{0,4}$ ]] && [[ "$PORT" -le 65535 ]] \
  || fail "loopback fixture server returned an invalid port"

case_bundle_id() {
  local name="$1"
  [[ "$name" =~ ^[a-z-]+$ ]] || fail "fixture case name is invalid"
  printf 'app.devisland.sparkle-live-gate.%s.%s' "$RUN_TOKEN" "$name"
}

make_update_archive() {
  local name="$1"
  local corrupt_signature="$2"
  local bundle_id
  local new_dir="$TEMP_ROOT/new-$name"
  bundle_id="$(case_bundle_id "$name")"
  mkdir -p "$new_dir"
  make_fixture_app "$new_dir/Dev Island.app" "$bundle_id" "2" \
    "new-$name" "A" "$FIXTURE_PUBLIC_KEY"
  if [[ "$corrupt_signature" == "1" ]]; then
    /usr/bin/ruby -e '
      path, marker = ARGV
      data = File.binread(path)
      offset = data.index(marker)
      abort("fixture marker is absent or ambiguous") if offset.nil? || data.index(marker, offset + 1)
      data.setbyte(offset, data.getbyte(offset) ^ 0x01)
      File.binwrite(path, data)
    ' "$new_dir/Dev Island.app/Contents/MacOS/DevIslandFixture" \
      "new-$name"
    if /usr/bin/codesign --verify --deep --strict "$new_dir/Dev Island.app" 2>/dev/null; then
      fail "corrupted code-signature fixture remained valid"
    fi
  elif [[ "$corrupt_signature" != "0" ]]; then
    fail "corrupted code-signature fixture flag is invalid"
  fi
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent \
    "$new_dir/Dev Island.app" "$SERVE_ROOT/update-$name.zip"
  chmod 0600 "$SERVE_ROOT/update-$name.zip"
}

make_update_archive "positive" "0"
make_update_archive "wrong-feed" "0"
make_update_archive "wrong-archive" "0"
make_update_archive "wrong-key" "0"
make_update_archive "corrupt-code-signature" "1"

archive_signature() {
  local archive_path="$1"
  local key_path="$2"
  local signature
  signature="$("$SIGN_UPDATE" --ed-key-file "$key_path" -p "$archive_path")"
  [[ "$signature" =~ ^[A-Za-z0-9+/]{86}==$ ]] \
    || fail "Sparkle archive signature is malformed"
  printf '%s' "$signature"
}

write_feed() {
  local feed_name="$1"
  local archive_name="$2"
  local archive_key="$3"
  local feed_key="$4"
  local archive_path="$SERVE_ROOT/$archive_name"
  local feed_path="$SERVE_ROOT/$feed_name"
  local signature
  local length
  signature="$(archive_signature "$archive_path" "$archive_key")"
  length="$(/usr/bin/stat -f '%z' "$archive_path")"
  /usr/bin/ruby - "$feed_path" "$PORT" "$archive_name" "$signature" "$length" <<'RUBY'
path, port, archive, signature, length = ARGV
abort("invalid fixture feed input") unless
  port.match?(/\A[0-9]{1,5}\z/) &&
    archive.match?(/\Aupdate-[a-z-]+\.zip\z/) &&
    signature.match?(/\A[A-Za-z0-9+\/]{86}==\z/) &&
    length.match?(/\A[1-9][0-9]{0,8}\z/)
File.binwrite(path, <<~XML)
  <?xml version="1.0" encoding="utf-8"?>
  <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
      <title>Dev Island Sparkle Live Gate</title>
      <link>http://127.0.0.1:#{port}/#{archive}</link>
      <description>Disposable local old-to-new verification.</description>
      <item>
        <title>2</title>
        <sparkle:version>2</sparkle:version>
        <sparkle:shortVersionString>2</sparkle:shortVersionString>
        <enclosure url="http://127.0.0.1:#{port}/#{archive}" length="#{length}" type="application/octet-stream" sparkle:edSignature="#{signature}" />
      </item>
    </channel>
  </rss>
XML
RUBY
  "$SIGN_UPDATE" --ed-key-file "$feed_key" "$feed_path" >/dev/null
  rg -q '<!-- sparkle-signatures:' "$feed_path" \
    || fail "Sparkle feed signature block is missing"
  chmod 0600 "$feed_path"
}

write_feed "feed-positive.xml" "update-positive.zip" \
  "$KEY_DIR/correct.key" "$KEY_DIR/correct.key"
write_feed "feed-wrong-feed.xml" "update-wrong-feed.zip" \
  "$KEY_DIR/correct.key" "$KEY_DIR/mismatched.key"
write_feed "feed-wrong-archive.xml" "update-wrong-archive.zip" \
  "$KEY_DIR/mismatched.key" "$KEY_DIR/correct.key"
write_feed "feed-wrong-key.xml" "update-wrong-key.zip" \
  "$KEY_DIR/correct.key" "$KEY_DIR/correct.key"
write_feed "feed-corrupt-code-signature.xml" "update-corrupt-code-signature.zip" \
  "$KEY_DIR/correct.key" "$KEY_DIR/correct.key"

feed_enclosure_signature() {
  /usr/bin/ruby -e '
    matches = File.binread(ARGV.fetch(0)).scan(/sparkle:edSignature="([A-Za-z0-9+\/]{86}==)"/)
    abort("feed enclosure signature is malformed") unless matches.length == 1
    print matches.fetch(0).fetch(0)
  ' "$1"
}

expect_archive_signature() {
  local expected_result="$1"
  local archive_path="$2"
  local feed_path="$3"
  local key_path="$4"
  local signature
  signature="$(feed_enclosure_signature "$feed_path")"
  if "$SIGN_UPDATE" --verify --ed-key-file "$key_path" \
      "$archive_path" "$signature" >/dev/null 2>&1; then
    [[ "$expected_result" == pass ]] \
      || fail "archive signature unexpectedly verified"
  else
    [[ "$expected_result" == fail ]] \
      || fail "archive signature did not verify"
  fi
}

expect_feed_signature() {
  local expected_result="$1"
  local feed_path="$2"
  local key_path="$3"
  if "$SIGN_UPDATE" --verify --ed-key-file "$key_path" \
      "$feed_path" >/dev/null 2>&1; then
    [[ "$expected_result" == pass ]] \
      || fail "feed signature unexpectedly verified"
  else
    [[ "$expected_result" == fail ]] \
      || fail "feed signature did not verify"
  fi
}

for name in positive wrong-feed wrong-key corrupt-code-signature; do
  expect_archive_signature pass "$SERVE_ROOT/update-$name.zip" \
    "$SERVE_ROOT/feed-$name.xml" "$KEY_DIR/correct.key"
done
expect_archive_signature fail "$SERVE_ROOT/update-wrong-archive.zip" \
  "$SERVE_ROOT/feed-wrong-archive.xml" "$KEY_DIR/correct.key"
expect_archive_signature pass "$SERVE_ROOT/update-wrong-archive.zip" \
  "$SERVE_ROOT/feed-wrong-archive.xml" "$KEY_DIR/mismatched.key"
for name in positive wrong-archive wrong-key corrupt-code-signature; do
  expect_feed_signature pass "$SERVE_ROOT/feed-$name.xml" "$KEY_DIR/correct.key"
done
expect_feed_signature fail "$SERVE_ROOT/feed-wrong-feed.xml" "$KEY_DIR/correct.key"
expect_feed_signature pass "$SERVE_ROOT/feed-wrong-feed.xml" "$KEY_DIR/mismatched.key"

run_case() {
  local name="$1"
  local feed_name="$2"
  local public_key="$3"
  local expected_result="$4"
  local expected_error="$5"
  local case_root="$TEMP_ROOT/cases/$name"
  local bundle_id
  local app_path="$case_root/Dev Island.app"
  local tmp_path="$case_root/tmp"
  local stdout_path="$case_root/stdout.log"
  local stderr_path="$case_root/stderr.log"
  local old_hash
  local result_code

  bundle_id="$(case_bundle_id "$name")"
  mkdir -p "$case_root" "$tmp_path"
  make_fixture_app "$app_path" "$bundle_id" "1" "old-$name" "A" "$public_key"
  old_hash="$(shasum -a 256 "$app_path/Contents/MacOS/DevIslandFixture" | awk '{print $1}')"

  set +e
  env -i \
    PATH='/usr/bin:/bin:/usr/sbin:/sbin' \
    HOME="$DISPOSABLE_HOME" \
    CFFIXED_USER_HOME="$DISPOSABLE_HOME" \
    TMPDIR="$DISPOSABLE_TMP/" \
    __CFPREFERENCES_AVOID_DAEMON='1' \
    NO_PROXY='127.0.0.1,localhost' \
    no_proxy='127.0.0.1,localhost' \
    /usr/bin/ruby "$HELPER" run 90 "$stdout_path" "$stderr_path" -- \
      "$CLI_EXECUTABLE" \
      --feed-url "http://127.0.0.1:$PORT/$feed_name" \
      --check-immediately \
      --user-agent-name 'Dev Island Sparkle Live Gate' \
      --verbose \
      "$app_path"
  result_code=$?
  set -e

  [[ "$result_code" -ne 124 ]] || fail "Sparkle update case timed out: $name"
  if [[ "$expected_result" == success ]]; then
    [[ "$result_code" -eq 0 ]] || {
      sed -n '1,160p' "$stderr_path" >&2
      fail "Sparkle positive update failed"
    }
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")" == "2" ]] \
      || fail "Sparkle positive update did not replace the bundle version"
    [[ "$("$app_path/Contents/MacOS/DevIslandFixture")" == "new-positive" ]] \
      || fail "Sparkle positive update did not replace the executable"
    /usr/bin/codesign --verify --deep --strict "$app_path" 2>/dev/null \
      || fail "Sparkle installed an invalidly signed fixture App"
    rg -Fq 'Installation Finished.' "$stderr_path" \
      || fail "Sparkle positive update did not report installation completion"
  else
    [[ "$result_code" -ne 0 ]] || fail "Sparkle negative update unexpectedly succeeded: $name"
    rg -Fq "$expected_error" "$stderr_path" \
      || {
        sed -n '1,160p' "$stderr_path" >&2
        fail "Sparkle negative update failed for the wrong reason: $name"
      }
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")" == "1" ]] \
      || fail "Sparkle negative update replaced the old bundle: $name"
    [[ "$(shasum -a 256 "$app_path/Contents/MacOS/DevIslandFixture" | awk '{print $1}')" == "$old_hash" ]] \
      || fail "Sparkle negative update changed the old executable: $name"
    /usr/bin/codesign --verify --deep --strict "$app_path" 2>/dev/null \
      || fail "Sparkle negative update damaged the old App: $name"
  fi
}

run_case "positive" "feed-positive.xml" "$FIXTURE_PUBLIC_KEY" \
  success ""
run_case "wrong-feed" "feed-wrong-feed.xml" "$FIXTURE_PUBLIC_KEY" \
  failure "The update feed is improperly signed"
run_case "wrong-archive" "feed-wrong-archive.xml" "$FIXTURE_PUBLIC_KEY" \
  failure "The update is improperly signed"
run_case "wrong-key" "feed-wrong-key.xml" "$MISMATCHED_PUBLIC_KEY" \
  failure "The update feed is improperly signed"
run_case "corrupt-code-signature" "feed-corrupt-code-signature.xml" "$FIXTURE_PUBLIC_KEY" \
  failure "The update is improperly signed"

for required_request in \
  'GET /feed-positive.xml' \
  'GET /update-positive.zip' \
  'GET /feed-wrong-feed.xml' \
  'GET /feed-wrong-archive.xml' \
  'GET /update-wrong-archive.zip' \
  'GET /feed-wrong-key.xml' \
  'GET /feed-corrupt-code-signature.xml' \
  'GET /update-corrupt-code-signature.zip'; do
  rg -Fxq "$required_request" "$SERVER_LOG" \
    || fail "live Sparkle transport request is missing: $required_request"
done
if rg -Fq 'GET /update-wrong-feed.zip' "$SERVER_LOG"; then
  fail "invalidly signed feed reached archive download"
fi
if rg -Fq 'GET /update-wrong-key.zip' "$SERVER_LOG"; then
  fail "mismatched embedded key reached archive download"
fi

if ! find "$DISPOSABLE_HOME/Library" -xdev -type f -print -quit | rg -q .; then
  fail "Sparkle disposable preference/cache routing produced no local evidence"
fi
for writable_runtime_root in "$DISPOSABLE_HOME" "$DISPOSABLE_TMP"; do
  runtime_link="$(find "$writable_runtime_root" -xdev -type l -print -quit)"
  if [[ -n "$runtime_link" ]]; then
    fail "Sparkle writable runtime created a symbolic link: ${runtime_link#"$DISPOSABLE_ROOT"/}"
  fi
  if find "$writable_runtime_root" -xdev \( -type f -o -type d \) \
      -perm -0022 -print -quit | rg -q .; then
    fail "Sparkle writable runtime created group/other-writable state"
  fi
done

echo "Sparkle old-to-new updater: PASS"
echo "Sparkle dependency: 2.9.6 @ ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a"
echo "Positive path: signed feed + signed archive + extraction + code-sign validation + bundle replacement"
echo "Negative paths: feed signature + archive signature + embedded key + corrupted code signature"
echo "Isolation: disposable App + loopback-only HTTP + injected private home/cache/preferences + non-production keys"
echo "Signing: native Sparkle ad-hoc helper identities preserved; only the disposable CLI host is newly signed"
