#!/usr/bin/env bash

set -euo pipefail

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

PERFORMANCE_MARKERS=(
  'DEV_ISLAND_PERFORMANCE_READY uptime='
  'DEV_ISLAND_PERFORMANCE_SCENARIO'
  'DEV_ISLAND_PERFORMANCE_TRANSITION iteration='
)

# These literals live in three independent DEBUG-only surfaces: the adaptive
# palette override, the developer control window, and TaskStore's synthetic
# action feed. A production or Performance-QA executable containing any one of
# them was built from the wrong graph even if its bundle identifier looks safe.
DEBUG_ONLY_MARKERS=(
  'DEV_ISLAND_FORCE_INCREASED_CONTRAST'
  'Seed 3 (preview set)'
  'Sandbox-injected waiting prompt'
)

fail() {
  echo "::error::$1" >&2
  exit 1
}

contains_marker() {
  local binary="$1"
  local marker="$2"
  # Do not use grep -q under pipefail. Its early exit can SIGPIPE `strings`
  # and turn a successful match into a false failure.
  /usr/bin/strings "$binary" | grep -F "$marker" >/dev/null
}

verify_binary_markers() {
  local flavor="$1"
  local binary="$2"

  [[ -f "$binary" && ! -L "$binary" ]] \
    || fail "Required build-flavor binary is missing or linked"

  case "$flavor" in
    production)
      for marker in "${PERFORMANCE_MARKERS[@]}"; do
        if contains_marker "$binary" "$marker"; then
          fail "Production binary contains performance fixture marker: $marker"
        fi
      done
      ;;
    performance-qa)
      for marker in "${PERFORMANCE_MARKERS[@]}"; do
        contains_marker "$binary" "$marker" \
          || fail "Performance binary is missing fixture marker: $marker"
      done
      ;;
    debug)
      for marker in "${PERFORMANCE_MARKERS[@]}"; do
        if contains_marker "$binary" "$marker"; then
          fail "Debug binary contains performance fixture marker: $marker"
        fi
      done
      for marker in "${DEBUG_ONLY_MARKERS[@]}"; do
        contains_marker "$binary" "$marker" \
          || fail "Debug binary is missing debug-only marker: $marker"
      done
      ;;
    *)
      fail "Unknown build flavor"
      ;;
  esac

  if [[ "$flavor" != "debug" ]]; then
    for marker in "${DEBUG_ONLY_MARKERS[@]}"; do
      if contains_marker "$binary" "$marker"; then
        fail "Release-shaped binary contains debug-only marker: $marker"
      fi
    done
  fi
}

verify_app_pair() {
  local production_app="$1"
  local performance_app="$2"
  local production_binary="${production_app}/Contents/MacOS/IslandApp"
  local performance_binary="${performance_app}/Contents/MacOS/IslandApp"
  local production_plist="${production_app}/Contents/Info.plist"
  local performance_plist="${performance_app}/Contents/Info.plist"

  for artifact in \
    "$production_binary" \
    "$performance_binary" \
    "$production_plist" \
    "$performance_plist"; do
    [[ -f "$artifact" && ! -L "$artifact" ]] \
      || fail "Required isolation artifact is missing or linked"
  done

  local production_bundle_id
  local performance_bundle_id
  production_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$production_plist")"
  performance_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$performance_plist")"
  [[ "$production_bundle_id" == "app.devisland.Island" ]] \
    || fail "Production bundle identifier is not production-safe"
  [[ "$performance_bundle_id" == "app.devisland.Island.PerformanceQA" ]] \
    || fail "Performance bundle identifier is not isolated"

  if /usr/libexec/PlistBuddy -c 'Print :DevIslandPerformanceFixture' "$production_plist" >/dev/null 2>&1; then
    fail "Production Info.plist contains DevIslandPerformanceFixture"
  fi
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :DevIslandPerformanceFixture' "$performance_plist")" == "true" ]] \
    || fail "Performance Info.plist is missing DevIslandPerformanceFixture=true"

  verify_binary_markers production "$production_binary"
  verify_binary_markers performance-qa "$performance_binary"
}

make_fixture_app() {
  local app="$1"
  local flavor="$2"
  local binary="${app}/Contents/MacOS/IslandApp"
  local plist="${app}/Contents/Info.plist"
  mkdir -p "${app}/Contents/MacOS"
  printf 'Dev Island build-flavor fixture\n' >"$binary"
  chmod 700 "$binary"
  /usr/bin/plutil -create xml1 "$plist"
  if [[ "$flavor" == "performance-qa" ]]; then
    /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string app.devisland.Island.PerformanceQA' "$plist"
    /usr/libexec/PlistBuddy -c 'Add :DevIslandPerformanceFixture bool true' "$plist"
    for marker in "${PERFORMANCE_MARKERS[@]}"; do
      printf '%s\n' "$marker" >>"$binary"
    done
  else
    /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string app.devisland.Island' "$plist"
  fi
}

make_debug_fixture_binary() {
  local binary="$1"
  printf 'Dev Island debug build-flavor fixture\n' >"$binary"
  for marker in "${DEBUG_ONLY_MARKERS[@]}"; do
    printf '%s\n' "$marker" >>"$binary"
  done
  chmod 700 "$binary"
}

expect_rejected() {
  local label="$1"
  local expected="$2"
  shift 2
  local output="${SELF_TEST_ROOT}/${label}.log"
  if "$@" >"$output" 2>&1; then
    fail "Unsafe build-flavor fixture unexpectedly passed: $label"
  fi
  rg -Fq "$expected" "$output" \
    || fail "Build-flavor fixture failed for the wrong reason: $label"
}

run_self_test() {
  SELF_TEST_ROOT="$(mktemp -d -t dev-island-build-flavor)"
  chmod 700 "$SELF_TEST_ROOT"
  trap 'rm -rf "$SELF_TEST_ROOT"' EXIT

  local production_app="${SELF_TEST_ROOT}/production/Dev Island.app"
  local performance_app="${SELF_TEST_ROOT}/performance/Dev Island.app"
  local debug_binary="${SELF_TEST_ROOT}/debug/IslandApp"
  mkdir -p "$(dirname "$debug_binary")"
  make_fixture_app "$production_app" production
  make_fixture_app "$performance_app" performance-qa
  make_debug_fixture_binary "$debug_binary"

  "$SCRIPT_PATH" "$production_app" "$performance_app" >/dev/null
  "$SCRIPT_PATH" --binary production "${production_app}/Contents/MacOS/IslandApp" >/dev/null
  "$SCRIPT_PATH" --binary performance-qa "${performance_app}/Contents/MacOS/IslandApp" >/dev/null
  "$SCRIPT_PATH" --binary debug "$debug_binary" >/dev/null

  local counter=0
  local marker
  local fixture
  for marker in "${PERFORMANCE_MARKERS[@]}"; do
    counter=$((counter + 1))
    fixture="${SELF_TEST_ROOT}/production-performance-${counter}.app"
    /usr/bin/ditto "$production_app" "$fixture"
    printf '%s\n' "$marker" >>"${fixture}/Contents/MacOS/IslandApp"
    expect_rejected "production-performance-${counter}" \
      "Production binary contains performance fixture marker: $marker" \
      "$SCRIPT_PATH" --binary production "${fixture}/Contents/MacOS/IslandApp"

    fixture="${SELF_TEST_ROOT}/performance-missing-${counter}.app"
    /usr/bin/ditto "$performance_app" "$fixture"
    /usr/bin/ruby -e '
      path, marker = ARGV
      bytes = File.binread(path)
      offset = bytes.index(marker) or abort("fixture marker unavailable")
      bytes.slice!(offset, marker.bytesize)
      File.binwrite(path, bytes)
    ' "${fixture}/Contents/MacOS/IslandApp" "$marker"
    expect_rejected "performance-missing-${counter}" \
      "Performance binary is missing fixture marker: $marker" \
      "$SCRIPT_PATH" --binary performance-qa "${fixture}/Contents/MacOS/IslandApp"

    fixture="${SELF_TEST_ROOT}/debug-performance-${counter}"
    /usr/bin/ditto "$debug_binary" "$fixture"
    printf '%s\n' "$marker" >>"$fixture"
    expect_rejected "debug-performance-${counter}" \
      "Debug binary contains performance fixture marker: $marker" \
      "$SCRIPT_PATH" --binary debug "$fixture"
  done

  counter=0
  for marker in "${DEBUG_ONLY_MARKERS[@]}"; do
    counter=$((counter + 1))
    fixture="${SELF_TEST_ROOT}/production-debug-${counter}.app"
    /usr/bin/ditto "$production_app" "$fixture"
    printf '%s\n' "$marker" >>"${fixture}/Contents/MacOS/IslandApp"
    expect_rejected "production-debug-${counter}" \
      "Release-shaped binary contains debug-only marker: $marker" \
      "$SCRIPT_PATH" --binary production "${fixture}/Contents/MacOS/IslandApp"

    fixture="${SELF_TEST_ROOT}/performance-debug-${counter}.app"
    /usr/bin/ditto "$performance_app" "$fixture"
    printf '%s\n' "$marker" >>"${fixture}/Contents/MacOS/IslandApp"
    expect_rejected "performance-debug-${counter}" \
      "Release-shaped binary contains debug-only marker: $marker" \
      "$SCRIPT_PATH" --binary performance-qa "${fixture}/Contents/MacOS/IslandApp"

    fixture="${SELF_TEST_ROOT}/debug-missing-${counter}"
    /usr/bin/ditto "$debug_binary" "$fixture"
    /usr/bin/ruby -e '
      path, marker = ARGV
      bytes = File.binread(path)
      offset = bytes.index(marker) or abort("fixture marker unavailable")
      bytes.slice!(offset, marker.bytesize)
      File.binwrite(path, bytes)
    ' "$fixture" "$marker"
    expect_rejected "debug-missing-${counter}" \
      "Debug binary is missing debug-only marker: $marker" \
      "$SCRIPT_PATH" --binary debug "$fixture"
  done

  echo "Build-flavor marker fixtures: PASS (18 negative cases)"
}

if [[ $# -eq 1 && "$1" == "--self-test" ]]; then
  run_self_test
elif [[ $# -eq 3 && "$1" == "--binary" ]]; then
  verify_binary_markers "$2" "$3"
  echo "Build-flavor marker boundary: PASS ($2)"
elif [[ $# -eq 2 ]]; then
  verify_app_pair "$1" "$2"
  echo "Production + Performance build isolation: PASS"
else
  echo "usage: $0 PRODUCTION_APP PERFORMANCE_QA_APP" >&2
  echo "       $0 --binary production|performance-qa|debug BINARY" >&2
  echo "       $0 --self-test" >&2
  exit 64
fi
