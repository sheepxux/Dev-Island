#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C
umask 077

QA_EVIDENCE_DESCRIPTORS_OPEN=0
QA_CSV_FILE_TOKEN=""
QA_APP_LOG_FILE_TOKEN=""
QA_SUMMARY_FILE_TOKEN=""
QA_MAX_CSV_BYTES=$((32 * 1024 * 1024))
QA_MAX_APP_LOG_BYTES=$((1 * 1024 * 1024))
QA_MAX_SUMMARY_BYTES=$((128 * 1024))
QA_MAX_APP_EXECUTABLE_BYTES=$((256 * 1024 * 1024))
QA_MAX_APP_PLIST_BYTES=$((1 * 1024 * 1024))
QA_MAX_DURATION_SECONDS=86400

close_evidence_descriptors() {
  if [[ "$QA_EVIDENCE_DESCRIPTORS_OPEN" == "1" ]]; then
    exec 7>&-
    exec 8>&-
    exec 9>&-
    QA_EVIDENCE_DESCRIPTORS_OPEN=0
  fi
}

validate_evidence_parent() {
  local directory="$1"
  local owner permissions

  [[ -d "$directory" && ! -L "$directory" ]] \
    || { echo "error: performance evidence parent must be a regular directory" >&2; return 1; }
  owner="$(stat -f '%u' "$directory")"
  permissions="$(stat -f '%Lp' "$directory")"
  [[ "$owner" == "$(id -u)" ]] \
    || { echo "error: performance evidence parent has an unsafe owner" >&2; return 1; }
  [[ "$permissions" =~ ^[0-7]{3,4}$ ]] \
    || { echo "error: performance evidence parent mode is invalid" >&2; return 1; }
  (( (8#$permissions & 8#022) == 0 )) \
    || { echo "error: performance evidence parent must not be group/other writable" >&2; return 1; }
}

evidence_descriptor_metadata() {
  local descriptor="$1"
  /usr/bin/ruby -e '
    descriptor = Integer(ARGV.fetch(0), 10)
    metadata = IO.for_fd(descriptor, autoclose: false).stat
    printf(
      "%d:%d:%d:%o:%d:%d",
      metadata.dev,
      metadata.ino,
      metadata.uid,
      metadata.mode & 0o7777,
      metadata.nlink,
      metadata.size
    )
  ' "$descriptor"
}

evidence_file_token() {
  local descriptor="$1"
  local device inode _owner _permissions _links _size
  IFS=: read -r device inode _owner _permissions _links _size \
    <<<"$(evidence_descriptor_metadata "$descriptor")"
  printf '%s:%s\n' "$device" "$inode"
}

verify_evidence_descriptor() {
  local path="$1"
  local descriptor="$2"
  local expected_token="$3"
  local label="$4"
  local maximum_bytes="$5"
  local path_token descriptor_token device inode owner permissions links size

  [[ -f "$path" && ! -L "$path" ]] \
    || { echo "error: $label evidence path is no longer a regular file" >&2; return 1; }
  path_token="$(stat -f '%d:%i' "$path")"
  IFS=: read -r device inode owner permissions links size \
    <<<"$(evidence_descriptor_metadata "$descriptor")"
  descriptor_token="$device:$inode"
  [[ "$path_token" == "$expected_token" && "$descriptor_token" == "$expected_token" ]] \
    || { echo "error: $label evidence identity changed during sampling" >&2; return 1; }

  [[ "$owner" == "$(id -u)" && "$permissions" == "600" && "$links" == "1" ]] \
    || { echo "error: $label evidence metadata is unsafe" >&2; return 1; }
  (( size <= maximum_bytes )) \
    || { echo "error: $label evidence exceeds its size boundary" >&2; return 1; }
}

reserve_evidence_set() {
  local csv_path="$1"
  local app_log_path="$2"
  local summary_path="$3"
  local parent

  for path in "$csv_path" "$app_log_path" "$summary_path"; do
    [[ "$path" != *$'\n'* && "$path" != *$'\r'* ]] \
      || { echo "error: performance evidence path contains a control character" >&2; return 1; }
  done
  [[ "$csv_path" != "$app_log_path" && "$csv_path" != "$summary_path" && "$app_log_path" != "$summary_path" ]] \
    || { echo "error: performance evidence paths must be distinct" >&2; return 1; }

  parent="$(dirname "$csv_path")"
  mkdir -p "$parent"
  validate_evidence_parent "$parent" || return 1
  [[ "$(dirname "$app_log_path")" == "$parent" && "$(dirname "$summary_path")" == "$parent" ]] \
    || { echo "error: performance evidence files must share one parent" >&2; return 1; }
  for path in "$csv_path" "$app_log_path" "$summary_path"; do
    [[ ! -e "$path" && ! -L "$path" ]] \
      || { echo "error: evidence output already exists; performance evidence is append-never" >&2; return 1; }
  done

  # One exec statement keeps the three successful descriptors open for the
  # complete run. noclobber makes every final-component creation use O_EXCL;
  # an existing file, symlink, or concurrent winner therefore fails before
  # the App starts instead of being truncated by a later shell redirection.
  set -o noclobber
  if ! exec 7>"$csv_path" 8>"$app_log_path" 9>"$summary_path"; then
    set +o noclobber
    echo "error: evidence output already exists or was claimed concurrently; performance evidence is append-never" >&2
    return 1
  fi
  set +o noclobber
  QA_EVIDENCE_DESCRIPTORS_OPEN=1

  QA_CSV_FILE_TOKEN="$(evidence_file_token 7)"
  QA_APP_LOG_FILE_TOKEN="$(evidence_file_token 8)"
  QA_SUMMARY_FILE_TOKEN="$(evidence_file_token 9)"
  verify_evidence_descriptor "$csv_path" 7 "$QA_CSV_FILE_TOKEN" "CSV" "$QA_MAX_CSV_BYTES" \
    && verify_evidence_descriptor "$app_log_path" 8 "$QA_APP_LOG_FILE_TOKEN" "App log" "$QA_MAX_APP_LOG_BYTES" \
    && verify_evidence_descriptor "$summary_path" 9 "$QA_SUMMARY_FILE_TOKEN" "summary" "$QA_MAX_SUMMARY_BYTES"
}

snapshot_evidence_file() {
  local source_path="$1"
  local expected_token="$2"
  local maximum_bytes="$3"
  local destination_path="$4"

  /usr/bin/ruby -e '
    begin
      path = ARGV.fetch(0)
      expected_token = ARGV.fetch(1)
      maximum = Integer(ARGV.fetch(2), 10)
      stable = lambda do |left, right|
        left.dev == right.dev && left.ino == right.ino &&
          left.uid == right.uid && left.mode == right.mode &&
          left.nlink == right.nlink && left.size == right.size &&
          left.mtime == right.mtime && left.ctime == right.ctime
      end
      before = File.lstat(path)
      raise unless before.file? && !before.symlink?
      flags = File::RDONLY | File::NOFOLLOW | File::NONBLOCK
      bytes = File.open(path, flags) do |input|
        opened = input.stat
        token = "#{opened.dev}:#{opened.ino}"
        raise unless token == expected_token && stable.call(before, opened)
        raise unless opened.size <= maximum
        contents = input.pread(opened.size, 0)
        after = input.stat
        raise unless contents.bytesize == opened.size && stable.call(opened, after)
        rebound = File.lstat(path)
        raise unless !rebound.symlink? && stable.call(after, rebound)
        contents
      end
      STDOUT.write(bytes)
    rescue StandardError
      exit 1
    end
  ' "$source_path" "$expected_token" "$maximum_bytes" >"$destination_path"
}

read_readiness_uptime_from_snapshot() {
  local snapshot_path="$1"
  local marker="$2"
  awk -v marker="$marker" '
    index($0, marker) == 1 {
      count += 1
      value = substr($0, length(marker) + 1)
      if (value !~ /^[0-9]+([.][0-9]+)?$/) invalid = 1
    }
    END {
      if (invalid || count > 1) exit 1
      if (count == 1) print value
    }
  ' "$snapshot_path"
}

launch_ready_milliseconds() {
  local start="$1"
  local ready="$2"
  [[ "$start" =~ ^[0-9]+([.][0-9]+)?$ \
     && "$ready" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
  awk -v start="$start" -v ready="$ready" '
    BEGIN {
      delta = ready - start
      if (delta < 0 || delta > 5.5) exit 1
      printf "%.1f", delta * 1000
    }
  '
}

stable_regular_file_sha256() {
  local path="$1"
  local maximum_bytes="$2"
  local require_executable="$3"
  /usr/bin/ruby -rdigest -e '
    begin
      path = ARGV.fetch(0)
      maximum = Integer(ARGV.fetch(1), 10)
      require_executable = ARGV.fetch(2) == "1"
      stable = lambda do |left, right|
        left.dev == right.dev && left.ino == right.ino &&
          left.uid == right.uid && left.mode == right.mode &&
          left.nlink == right.nlink && left.size == right.size &&
          left.mtime == right.mtime && left.ctime == right.ctime
      end
      before = File.lstat(path)
      raise unless before.file? && !before.symlink?
      flags = File::RDONLY | File::NOFOLLOW | File::NONBLOCK
      digest = File.open(path, flags) do |input|
        opened = input.stat
        raise unless stable.call(before, opened)
        raise unless opened.uid == Process.uid && opened.nlink == 1
        raise unless (opened.mode & 0o022).zero?
        raise if require_executable && (opened.mode & 0o111).zero?
        raise unless opened.size.between?(1, maximum)
        result = Digest::SHA256.new
        offset = 0
        while offset < opened.size
          length = [64 * 1024, opened.size - offset].min
          chunk = input.pread(length, offset)
          raise unless chunk.bytesize == length
          result.update(chunk)
          offset += length
        end
        after = input.stat
        raise unless stable.call(opened, after)
        rebound = File.lstat(path)
        raise unless !rebound.symlink? && stable.call(after, rebound)
        result.hexdigest
      end
      STDOUT.write(digest)
    rescue StandardError
      exit 1
    end
  ' "$path" "$maximum_bytes" "$require_executable"
}

verify_private_app_snapshot_identity() {
  local binary_sha plist_sha
  binary_sha="$(stable_regular_file_sha256 \
    "$QA_BINARY" "$QA_MAX_APP_EXECUTABLE_BYTES" 1)" || return 1
  plist_sha="$(stable_regular_file_sha256 \
    "$QA_PLIST" "$QA_MAX_APP_PLIST_BYTES" 0)" || return 1
  [[ "$binary_sha" == "$QA_EXECUTABLE_SHA256" \
     && "$plist_sha" == "$QA_APP_PLIST_SHA256" ]] || return 1
  codesign --verify --strict --deep "$QA_APP" >/dev/null 2>&1
}

verify_selected_app_identity() {
  local binary_sha plist_sha
  binary_sha="$(stable_regular_file_sha256 \
    "$QA_SELECTED_BINARY" "$QA_MAX_APP_EXECUTABLE_BYTES" 1)" || return 1
  plist_sha="$(stable_regular_file_sha256 \
    "$QA_SELECTED_PLIST" "$QA_MAX_APP_PLIST_BYTES" 0)" || return 1
  [[ "$binary_sha" == "$QA_SELECTED_EXECUTABLE_SHA256" \
     && "$plist_sha" == "$QA_SELECTED_PLIST_SHA256" ]] || return 1
  codesign --verify --strict --deep "$QA_SELECTED_APP" >/dev/null 2>&1
}

snapshot_performance_app() {
  local selected_app="$1"
  local selected_binary="$2"
  local selected_plist="$3"
  local destination_app="$4"
  local expected_flavor="$5"
  local source_binary_before source_binary_after source_plist_before source_plist_after

  [[ -d "$selected_app" && ! -L "$selected_app" ]] || return 1
  for directory in \
    "$selected_app/Contents" \
    "$selected_app/Contents/MacOS" \
    "$selected_app/Contents/Resources" \
    "$selected_app/Contents/Frameworks"; do
    [[ -d "$directory" && ! -L "$directory" ]] || return 1
  done
  [[ ! -e "$destination_app" && ! -L "$destination_app" ]] || return 1

  source_binary_before="$(stable_regular_file_sha256 \
    "$selected_binary" "$QA_MAX_APP_EXECUTABLE_BYTES" 1)" || return 1
  source_plist_before="$(stable_regular_file_sha256 \
    "$selected_plist" "$QA_MAX_APP_PLIST_BYTES" 0)" || return 1
  codesign --verify --strict --deep "$selected_app" >/dev/null 2>&1 || return 1

  /usr/bin/ditto "$selected_app" "$destination_app" >/dev/null 2>&1 || return 1
  [[ -d "$destination_app" && ! -L "$destination_app" ]] || return 1

  QA_APP="$destination_app"
  QA_BINARY="$QA_APP/Contents/MacOS/IslandApp"
  QA_PLIST="$QA_APP/Contents/Info.plist"
  QA_EXECUTABLE_SHA256="$(stable_regular_file_sha256 \
    "$QA_BINARY" "$QA_MAX_APP_EXECUTABLE_BYTES" 1)" || return 1
  QA_APP_PLIST_SHA256="$(stable_regular_file_sha256 \
    "$QA_PLIST" "$QA_MAX_APP_PLIST_BYTES" 0)" || return 1

  source_binary_after="$(stable_regular_file_sha256 \
    "$selected_binary" "$QA_MAX_APP_EXECUTABLE_BYTES" 1)" || return 1
  source_plist_after="$(stable_regular_file_sha256 \
    "$selected_plist" "$QA_MAX_APP_PLIST_BYTES" 0)" || return 1
  [[ "$source_binary_before" == "$source_binary_after" \
     && "$source_binary_before" == "$QA_EXECUTABLE_SHA256" \
     && "$source_plist_before" == "$source_plist_after" \
     && "$source_plist_before" == "$QA_APP_PLIST_SHA256" ]] || return 1
  codesign --verify --strict --deep "$selected_app" >/dev/null 2>&1 || return 1
  verify_private_app_snapshot_identity || return 1

  "$QA_APP_DEPENDENCY_VERIFIER" --app "$QA_APP" >/dev/null 2>&1 || return 1
  "$QA_BUILD_FLAVOR_VERIFIER" \
    --binary "$expected_flavor" "$QA_BINARY" >/dev/null 2>&1 || return 1
  QA_SELECTED_EXECUTABLE_SHA256="$source_binary_before"
  QA_SELECTED_PLIST_SHA256="$source_plist_before"
}

run_evidence_boundary_self_test() {
  local root spaced csv app_log summary sentinel winner_one winner_two status_one status_two
  root="$(mktemp -d -t dev-island-performance-evidence-boundary)"
  chmod 700 "$root"
  trap 'rm -rf "$root"' EXIT

  # 1. A space-containing private parent creates three distinct 0600 files.
  spaced="$root/path with space"
  mkdir -m 700 "$spaced"
  csv="$spaced/samples.csv"
  app_log="$spaced/samples.app.log"
  summary="$spaced/samples.summary.txt"
  reserve_evidence_set "$csv" "$app_log" "$summary"
  printf 'csv\n' >&7
  printf 'ready\n' >&8
  printf 'summary\n' >&9
  verify_evidence_descriptor "$csv" 7 "$QA_CSV_FILE_TOKEN" "CSV" "$QA_MAX_CSV_BYTES"
  verify_evidence_descriptor "$app_log" 8 "$QA_APP_LOG_FILE_TOKEN" "App log" "$QA_MAX_APP_LOG_BYTES"
  verify_evidence_descriptor "$summary" 9 "$QA_SUMMARY_FILE_TOKEN" "summary" "$QA_MAX_SUMMARY_BYTES"
  snapshot_evidence_file "$csv" "$QA_CSV_FILE_TOKEN" "$QA_MAX_CSV_BYTES" "$spaced/private-snapshot.csv"
  cmp -s "$csv" "$spaced/private-snapshot.csv"
  close_evidence_descriptors

  # 2. Any existing target rejects the set before a preceding path is created.
  mkdir -m 700 "$root/existing"
  csv="$root/existing/samples.csv"
  app_log="$root/existing/samples.app.log"
  summary="$root/existing/samples.summary.txt"
  printf 'sentinel\n' >"$app_log"
  if reserve_evidence_set "$csv" "$app_log" "$summary" 2>/dev/null; then
    echo "error: pre-existing performance evidence unexpectedly passed" >&2
    exit 1
  fi
  [[ ! -e "$csv" && "$(cat "$app_log")" == "sentinel" ]]

  # 3. A symbolic-link first target is rejected without touching its target.
  mkdir -m 700 "$root/symlink"
  sentinel="$root/symlink/sentinel"
  printf 'sentinel\n' >"$sentinel"
  csv="$root/symlink/samples.csv"
  app_log="$root/symlink/samples.app.log"
  summary="$root/symlink/samples.summary.txt"
  ln -s sentinel "$csv"
  if reserve_evidence_set "$csv" "$app_log" "$summary" 2>/dev/null; then
    echo "error: symbolic-link performance evidence unexpectedly passed" >&2
    exit 1
  fi
  [[ "$(cat "$sentinel")" == "sentinel" ]]

  # 4. Two simultaneous claimants produce exactly one complete winner.
  mkdir -m 700 "$root/concurrent"
  csv="$root/concurrent/samples.csv"
  app_log="$root/concurrent/samples.app.log"
  summary="$root/concurrent/samples.summary.txt"
  (
    reserve_evidence_set "$csv" "$app_log" "$summary" 2>/dev/null
    printf 'winner-one\n' >&7
    close_evidence_descriptors
  ) &
  winner_one=$!
  (
    reserve_evidence_set "$csv" "$app_log" "$summary" 2>/dev/null
    printf 'winner-two\n' >&7
    close_evidence_descriptors
  ) &
  winner_two=$!
  set +e
  wait "$winner_one"; status_one=$?
  wait "$winner_two"; status_two=$?
  set -e
  (( (status_one == 0 && status_two != 0) || (status_one != 0 && status_two == 0) ))
  [[ -f "$csv" && -f "$app_log" && -f "$summary" ]]
  [[ "$(cat "$csv")" == "winner-one" || "$(cat "$csv")" == "winner-two" ]]

  # 5. Replacing a reserved path is detected against the still-open inode.
  mkdir -m 700 "$root/replaced"
  csv="$root/replaced/samples.csv"
  app_log="$root/replaced/samples.app.log"
  summary="$root/replaced/samples.summary.txt"
  reserve_evidence_set "$csv" "$app_log" "$summary"
  printf 'original\n' >&7
  mv "$csv" "$csv.moved"
  printf 'replacement\n' >"$csv"
  if verify_evidence_descriptor "$csv" 7 "$QA_CSV_FILE_TOKEN" "CSV" "$QA_MAX_CSV_BYTES" 2>/dev/null; then
    echo "error: replaced performance evidence unexpectedly passed" >&2
    exit 1
  fi
  if snapshot_evidence_file "$csv" "$QA_CSV_FILE_TOKEN" "$QA_MAX_CSV_BYTES" "$root/replaced/private-snapshot.csv" 2>/dev/null; then
    echo "error: replaced performance evidence snapshot unexpectedly passed" >&2
    exit 1
  fi
  close_evidence_descriptors

  # 6. Readiness parsing uses only a bounded private snapshot. Replacing the
  # public App-log path with a FIFO must fail without opening a blocking reader.
  mkdir -m 700 "$root/readiness"
  csv="$root/readiness/samples.csv"
  app_log="$root/readiness/samples.app.log"
  summary="$root/readiness/samples.summary.txt"
  reserve_evidence_set "$csv" "$app_log" "$summary"
  printf 'DEV_ISLAND_PERFORMANCE_READY uptime=1234.5\n' >&8
  snapshot_evidence_file \
    "$app_log" \
    "$QA_APP_LOG_FILE_TOKEN" \
    "$QA_MAX_APP_LOG_BYTES" \
    "$root/readiness/private-app-log.snapshot"
  [[ "$(read_readiness_uptime_from_snapshot \
    "$root/readiness/private-app-log.snapshot" \
    'DEV_ISLAND_PERFORMANCE_READY uptime=')" == "1234.5" ]]
  printf 'DEV_ISLAND_PRODUCTION_READY uptime=1234.75\n' \
    >"$root/readiness/production-app-log.snapshot"
  [[ "$(read_readiness_uptime_from_snapshot \
    "$root/readiness/production-app-log.snapshot" \
    'DEV_ISLAND_PRODUCTION_READY uptime=')" == "1234.75" ]]
  printf 'DEV_ISLAND_PERFORMANCE_READY uptime=invalid\n' \
    >"$root/readiness/malformed-app-log.snapshot"
  if read_readiness_uptime_from_snapshot \
    "$root/readiness/malformed-app-log.snapshot" \
    'DEV_ISLAND_PERFORMANCE_READY uptime=' >/dev/null 2>&1; then
    echo "error: malformed readiness uptime unexpectedly passed" >&2
    exit 1
  fi
  printf '%s\n' \
    'DEV_ISLAND_PERFORMANCE_READY uptime=1234.5' \
    'DEV_ISLAND_PERFORMANCE_READY uptime=1234.6' \
    >"$root/readiness/duplicate-app-log.snapshot"
  if read_readiness_uptime_from_snapshot \
    "$root/readiness/duplicate-app-log.snapshot" \
    'DEV_ISLAND_PERFORMANCE_READY uptime=' >/dev/null 2>&1; then
    echo "error: duplicate readiness markers unexpectedly passed" >&2
    exit 1
  fi
  [[ "$(launch_ready_milliseconds 1234 1235.25)" == "1250.0" ]]
  if launch_ready_milliseconds 1234 1233 >/dev/null 2>&1 \
    || launch_ready_milliseconds 1234 1240 >/dev/null 2>&1 \
    || launch_ready_milliseconds invalid 1235 >/dev/null 2>&1; then
    echo "error: invalid readiness launch window unexpectedly passed" >&2
    exit 1
  fi
  mv "$app_log" "$app_log.moved"
  mkfifo "$app_log"
  if snapshot_evidence_file \
    "$app_log" \
    "$QA_APP_LOG_FILE_TOKEN" \
    "$QA_MAX_APP_LOG_BYTES" \
    "$root/readiness/replaced-app-log.snapshot" 2>/dev/null; then
    echo "error: replaced readiness App log unexpectedly passed" >&2
    exit 1
  fi
  close_evidence_descriptors

  # 7. Selected-App identity inputs must be ordinary bounded files. The same
  # descriptor-backed hash changes with bytes and rejects links/FIFOs without
  # handing either special file to a blocking consumer.
  mkdir -m 700 "$root/app-input"
  printf '#!/bin/sh\nexit 0\n' >"$root/app-input/IslandApp"
  chmod 700 "$root/app-input/IslandApp"
  local first_input_hash second_input_hash
  first_input_hash="$(stable_regular_file_sha256 \
    "$root/app-input/IslandApp" "$QA_MAX_APP_EXECUTABLE_BYTES" 1)"
  printf '#!/bin/sh\nexit 1\n' >"$root/app-input/IslandApp"
  chmod 700 "$root/app-input/IslandApp"
  second_input_hash="$(stable_regular_file_sha256 \
    "$root/app-input/IslandApp" "$QA_MAX_APP_EXECUTABLE_BYTES" 1)"
  [[ "$first_input_hash" != "$second_input_hash" ]]
  ln -s IslandApp "$root/app-input/linked-app"
  if stable_regular_file_sha256 \
    "$root/app-input/linked-app" "$QA_MAX_APP_EXECUTABLE_BYTES" 1 \
    >/dev/null 2>&1; then
    echo "error: symbolic-link App input unexpectedly passed" >&2
    exit 1
  fi
  mkfifo "$root/app-input/fifo-app"
  if stable_regular_file_sha256 \
    "$root/app-input/fifo-app" "$QA_MAX_APP_EXECUTABLE_BYTES" 1 \
    >/dev/null 2>&1; then
    echo "error: FIFO App input unexpectedly passed" >&2
    exit 1
  fi

  trap - EXIT
  rm -rf "$root"
  echo "Performance evidence and App-input fixtures: PASS (7 cases)"
}

if [[ $# -eq 1 && "$1" == "--self-test-evidence-boundary" ]]; then
  run_evidence_boundary_self_test
  exit 0
fi

usage() {
  echo "usage: $0 APP_BINARY SCENARIO OUTPUT_CSV [WARMUP_SECONDS] [SAMPLE_SECONDS] [MAX_AVERAGE_CPU] [MAX_RSS_SLOPE_KB_PER_MINUTE] [MAX_RSS_GROWTH_KB]" >&2
  exit 64
}

[[ $# -ge 3 && $# -le 8 ]] || usage

QA_SELECTED_BINARY="$1"
QA_SCENARIO="$2"
QA_OUTPUT_CSV="$3"
QA_WARMUP_SECONDS="${4:-10}"
QA_SAMPLE_SECONDS="${5:-60}"
QA_MAX_AVERAGE_CPU="${6:-}"
QA_MAX_RSS_SLOPE="${7:-}"
QA_MAX_RSS_GROWTH="${8:-}"
QA_ALLOW_LOCKED="${DEV_ISLAND_PERF_ALLOW_LOCKED:-0}"
QA_PRODUCTION_SMOKE=0
QA_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QA_ANALYZER="$QA_SCRIPT_DIR/summarize-performance-samples.sh"
QA_SCREEN_PROBE_SOURCE="$QA_SCRIPT_DIR/display-session-state.swift"
QA_APP_DEPENDENCY_VERIFIER="$QA_SCRIPT_DIR/../release/verify-app-bundle-dependencies.rb"
QA_BUILD_FLAVOR_VERIFIER="$QA_SCRIPT_DIR/../ci/verify-performance-fixture-isolation.sh"

[[ -x "$QA_SELECTED_BINARY" ]] || { echo "error: selected app binary is not executable" >&2; exit 2; }
[[ "$QA_SELECTED_BINARY" == */Contents/MacOS/IslandApp ]] || { echo "error: expected a Dev Island app-bundle executable" >&2; exit 2; }
[[ "$QA_WARMUP_SECONDS" =~ ^[0-9]+$ ]] || usage
[[ "$QA_SAMPLE_SECONDS" =~ ^[1-9][0-9]*$ ]] || usage
(( QA_WARMUP_SECONDS <= QA_MAX_DURATION_SECONDS )) || usage
(( QA_SAMPLE_SECONDS <= QA_MAX_DURATION_SECONDS )) || usage
[[ -x "$QA_ANALYZER" ]] || { echo "error: performance sample analyzer is missing" >&2; exit 2; }
[[ -f "$QA_SCREEN_PROBE_SOURCE" ]] || { echo "error: display-session probe is missing" >&2; exit 2; }
[[ -x "$QA_APP_DEPENDENCY_VERIFIER" ]] || { echo "error: App dependency verifier is missing" >&2; exit 2; }
[[ -x "$QA_BUILD_FLAVOR_VERIFIER" ]] || { echo "error: build-flavor verifier is missing" >&2; exit 2; }
for threshold in \
  "$QA_MAX_AVERAGE_CPU" \
  "$QA_MAX_RSS_SLOPE" \
  "$QA_MAX_RSS_GROWTH"; do
  [[ -z "$threshold" || "$threshold" =~ ^[0-9]+([.][0-9]+)?$ ]] || usage
done

case "$QA_SCENARIO" in
  idle|compact-running-20|expanded-running-20|expanded-mixed-20|transition-running-20) ;;
  production-launch-smoke)
    QA_PRODUCTION_SMOKE=1
    QA_ALLOW_LOCKED=1
    [[ "$QA_WARMUP_SECONDS" == "0" \
       && "$QA_SAMPLE_SECONDS" == "8" \
       && -z "$QA_MAX_AVERAGE_CPU" \
       && -z "$QA_MAX_RSS_SLOPE" \
       && -z "$QA_MAX_RSS_GROWTH" ]] \
      || { echo "error: production launch smoke requires exactly 0 warmup, 8 survival samples and no performance thresholds" >&2; exit 2; }
    ;;
  *) echo "error: unsupported scenario: $QA_SCENARIO" >&2; exit 2 ;;
esac

QA_SELECTED_APP="${QA_SELECTED_BINARY%/Contents/MacOS/IslandApp}"
QA_SELECTED_PLIST="$QA_SELECTED_APP/Contents/Info.plist"

QA_TEMP_DIR="$(mktemp -d -t dev-island-performance-sampler)"
QA_SCREEN_PROBE="$QA_TEMP_DIR/display-session-state"
QA_ISOLATED_USER_ROOT="$QA_TEMP_DIR/cffixed-user-home"
QA_READINESS_LOG_SNAPSHOT="$QA_TEMP_DIR/readiness.app-log.snapshot"
if [[ "$QA_PRODUCTION_SMOKE" == "1" ]]; then
  QA_PRIVATE_APP="$QA_TEMP_DIR/Dev Island Production Smoke.app"
  QA_EXPECTED_BUILD_FLAVOR="production"
  QA_READINESS_MARKER="DEV_ISLAND_PRODUCTION_READY uptime="
  QA_SELECTED_APP_LABEL="Production App"
  QA_LAUNCH_PROFILE="production-hermetic"
  QA_PRODUCTION_SERVICES_ISOLATED="true"
else
  QA_PRIVATE_APP="$QA_TEMP_DIR/Dev Island Performance QA.app"
  QA_EXPECTED_BUILD_FLAVOR="performance-qa"
  QA_READINESS_MARKER="DEV_ISLAND_PERFORMANCE_READY uptime="
  QA_SELECTED_APP_LABEL="Performance QA App"
  QA_LAUNCH_PROFILE="performance-qa"
  QA_PRODUCTION_SERVICES_ISOLATED="not-applicable"
fi
QA_APP=""
QA_BINARY=""
QA_PLIST=""
QA_EXECUTABLE_SHA256=""
QA_SELECTED_EXECUTABLE_SHA256=""
QA_SELECTED_PLIST_SHA256=""
QA_APP_PLIST_SHA256=""
QA_PID=""
QA_LAUNCH_PID=""
QA_EXIT_STATUS=""

mkdir -m 700 "$QA_ISOLATED_USER_ROOT"

cleanup() {
  if [[ -n "$QA_PID" ]] && kill -0 "$QA_PID" 2>/dev/null; then
    kill "$QA_PID" 2>/dev/null || true
    wait "$QA_PID" 2>/dev/null || true
  fi
  close_evidence_descriptors
  rm -rf "$QA_TEMP_DIR"
}
trap cleanup EXIT INT TERM

snapshot_performance_app \
  "$QA_SELECTED_APP" \
  "$QA_SELECTED_BINARY" \
  "$QA_SELECTED_PLIST" \
  "$QA_PRIVATE_APP" \
  "$QA_EXPECTED_BUILD_FLAVOR" \
  || { echo "error: selected $QA_SELECTED_APP_LABEL could not be frozen and verified" >&2; exit 2; }

QA_MARKER="$(/usr/libexec/PlistBuddy -c 'Print :DevIslandPerformanceFixture' "$QA_PLIST" 2>/dev/null || true)"
QA_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$QA_PLIST" 2>/dev/null || true)"
if [[ "$QA_PRODUCTION_SMOKE" == "1" ]]; then
  [[ -z "$QA_MARKER" ]] || { echo "error: production launch smoke rejects a performance-fixture marker" >&2; exit 2; }
  [[ "$QA_BUNDLE_ID" == "app.devisland.Island" ]] || { echo "error: production bundle identifier is not exact" >&2; exit 2; }
else
  [[ "$QA_MARKER" == "true" ]] || { echo "error: refusing to measure an app without the performance-fixture marker" >&2; exit 2; }
  [[ "$QA_BUNDLE_ID" == "app.devisland.Island.PerformanceQA" ]] || { echo "error: performance bundle identifier is not isolated" >&2; exit 2; }
fi

xcrun swiftc -O "$QA_SCREEN_PROBE_SOURCE" -o "$QA_SCREEN_PROBE" \
  || { echo "error: failed to compile display-session probe" >&2; exit 2; }

read_screen_state() {
  "$QA_SCREEN_PROBE" 2>/dev/null || printf 'unknown\n'
}

require_unlocked_screen() {
  local state
  state="$(read_screen_state)"
  if [[ "$state" != "unlocked" && "$QA_ALLOW_LOCKED" != "1" ]]; then
    echo "error: screen is locked or unknown; App-Nap samples cannot support a product performance claim" >&2
    return 5
  fi
}

terminate_qa_app_normally() {
  [[ -n "$QA_PID" ]] || return 1

  # Target the exact process rather than a bundle identifier: a developer may
  # already have another Dev Island build running. NSRunningApplication sends
  # the ordinary AppKit terminate request, exercising applicationWillTerminate
  # and TaskStore shutdown instead of treating SIGTERM as a clean exit.
  /usr/bin/swift -e '
    import AppKit
    guard CommandLine.arguments.count == 2,
          let rawPID = Int32(CommandLine.arguments[1]),
          rawPID > 0,
          let app = NSRunningApplication(processIdentifier: rawPID),
          app.terminate() else {
        exit(1)
    }
  ' "$QA_PID" >/dev/null 2>&1 || return 1

  for _ in {1..50}; do
    kill -0 "$QA_PID" 2>/dev/null || break
    sleep 0.1
  done
  kill -0 "$QA_PID" 2>/dev/null && return 1

  set +e
  wait "$QA_PID"
  QA_EXIT_STATUS=$?
  set -e
  QA_PID=""
  [[ "$QA_EXIT_STATUS" == "0" ]]
}

verify_production_state_absent() {
  local forbidden_path
  for forbidden_path in \
    "$QA_ISOLATED_USER_ROOT/Library/Application Support/island-app/tasks.sqlite" \
    "$QA_ISOLATED_USER_ROOT/Library/Application Support/island-app/local-hook-authorization.header"; do
    [[ ! -e "$forbidden_path" && ! -L "$forbidden_path" ]] \
      || { echo "error: hermetic production launch created product state" >&2; return 1; }
  done
}

verify_production_runtime_isolation() {
  verify_production_state_absent || return 1

  # This scenario is a survival/isolation gate, not a performance run, so
  # re-checking the exact PID once per sample is intentional. It catches a
  # delayed Manus, Sparkle or listener bootstrap that a readiness-only check
  # could miss without inspecting payloads, destinations or user state.
  if /usr/sbin/lsof -nP -a -p "$QA_PID" -i 2>/dev/null \
      | awk 'NR > 1 { found = 1 } END { exit(found ? 0 : 1) }'; then
    echo "error: hermetic production launch opened a network socket" >&2
    return 1
  fi
}

QA_SCREEN_STATE_INITIAL="$(read_screen_state)"
case "$QA_SCREEN_STATE_INITIAL" in
  unlocked) QA_SCREEN_LOCKED="false" ;;
  locked) QA_SCREEN_LOCKED="true" ;;
  *) QA_SCREEN_LOCKED="unknown" ;;
esac
if [[ "$QA_SCREEN_STATE_INITIAL" != "unlocked" && "$QA_ALLOW_LOCKED" != "1" ]]; then
  echo "error: screen is locked or unknown; App-Nap samples cannot support a product performance claim" >&2
  exit 5
fi

QA_OUTPUT_STEM="${QA_OUTPUT_CSV%.csv}"
QA_APP_LOG="${QA_OUTPUT_STEM}.app.log"
QA_SUMMARY="${QA_OUTPUT_STEM}.summary.txt"
reserve_evidence_set "$QA_OUTPUT_CSV" "$QA_APP_LOG" "$QA_SUMMARY" || exit 2

QA_APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$QA_PLIST" 2>/dev/null || true)"
QA_APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$QA_PLIST" 2>/dev/null || true)"
[[ "$QA_APP_VERSION" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ \
   && "$QA_APP_BUILD" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]] \
  || { echo "error: selected $QA_SELECTED_APP_LABEL version metadata is invalid" >&2; exit 3; }
verify_private_app_snapshot_identity \
  || { echo "error: private $QA_SELECTED_APP_LABEL snapshot changed before launch" >&2; exit 3; }
verify_selected_app_identity \
  || { echo "error: selected $QA_SELECTED_APP_LABEL changed before launch" >&2; exit 3; }
QA_MACHINE_MODEL="$(sysctl -n hw.model 2>/dev/null || printf 'unknown')"
QA_MACOS_VERSION="$(sw_vers -productVersion 2>/dev/null || printf 'unknown')"
QA_MACHINE_ARCH="$(uname -m)"

QA_LAUNCH_STARTED_UPTIME="$(swift -e 'import Foundation; print(ProcessInfo.processInfo.systemUptime)' 2>/dev/null)"
[[ "$QA_LAUNCH_STARTED_UPTIME" =~ ^[0-9]+([.][0-9]+)?$ ]] \
  || { echo "error: launch uptime is invalid" >&2; exit 3; }
if [[ "$QA_PRODUCTION_SMOKE" == "1" ]]; then
  env \
    CFFIXED_USER_HOME="$QA_ISOLATED_USER_ROOT" \
    DEV_ISLAND_HERMETIC_LAUNCH_SMOKE=v1 \
    "$QA_BINARY" --dev-island-hermetic-launch-smoke-v1 \
    1>&8 2>&8 7>&- 9>&- &
else
  env \
    CFFIXED_USER_HOME="$QA_ISOLATED_USER_ROOT" \
    DEV_ISLAND_PERFORMANCE_SCENARIO="$QA_SCENARIO" \
    "$QA_BINARY" 1>&8 2>&8 7>&- 9>&- &
fi
QA_PID=$!
QA_LAUNCH_PID="$QA_PID"

QA_READY_UPTIME=""
for ((QA_READY_ATTEMPT = 0; QA_READY_ATTEMPT < 100; QA_READY_ATTEMPT += 1)); do
  snapshot_evidence_file "$QA_APP_LOG" \
    "$QA_APP_LOG_FILE_TOKEN" \
    "$QA_MAX_APP_LOG_BYTES" \
    "$QA_READINESS_LOG_SNAPSHOT" \
    || { echo "error: failed to snapshot readiness App log" >&2; exit 3; }
  if ! QA_READY_UPTIME="$(read_readiness_uptime_from_snapshot \
    "$QA_READINESS_LOG_SNAPSHOT" \
    "$QA_READINESS_MARKER")"; then
    echo "error: App published an invalid readiness marker" >&2
    exit 3
  fi
  verify_evidence_descriptor "$QA_APP_LOG" 8 "$QA_APP_LOG_FILE_TOKEN" "App log" "$QA_MAX_APP_LOG_BYTES" \
    || exit 3
  [[ -n "$QA_READY_UPTIME" ]] && break
  kill -0 "$QA_PID" 2>/dev/null || { echo "error: app exited before readiness" >&2; exit 3; }
  sleep 0.05
done
[[ -n "$QA_READY_UPTIME" ]] || { echo "error: app did not publish launch readiness" >&2; exit 3; }
if ! QA_LAUNCH_READY_MS="$(launch_ready_milliseconds \
  "$QA_LAUNCH_STARTED_UPTIME" \
  "$QA_READY_UPTIME")"; then
  echo "error: App readiness uptime is outside the launch window" >&2
  exit 3
fi

if [[ "$QA_PRODUCTION_SMOKE" == "1" ]]; then
  verify_production_runtime_isolation || exit 3
fi

sleep "$QA_WARMUP_SECONDS"
kill -0 "$QA_PID" 2>/dev/null || { echo "error: app exited during warmup" >&2; exit 3; }
require_unlocked_screen

printf 'timestamp_utc,elapsed_seconds,cpu_percent,rss_kb\n' >&7
for ((QA_INDEX = 0; QA_INDEX < QA_SAMPLE_SECONDS; QA_INDEX += 1)); do
  require_unlocked_screen
  if [[ "$QA_PRODUCTION_SMOKE" == "1" ]]; then
    verify_production_runtime_isolation || exit 3
  fi
  QA_SAMPLE="$(ps -p "$QA_PID" -o %cpu=,rss= | awk '{$1=$1; print $1 "," $2}')"
  [[ -n "$QA_SAMPLE" ]] || { echo "error: app exited during sampling" >&2; exit 3; }
  printf '%s,%d,%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$QA_INDEX" "$QA_SAMPLE" >&7
  if (( QA_INDEX + 1 < QA_SAMPLE_SECONDS )); then sleep 1; fi
done
require_unlocked_screen
QA_SCREEN_STATE_FINAL="$(read_screen_state)"

terminate_qa_app_normally \
  || { echo "error: app did not complete a normal zero-status termination" >&2; exit 3; }

if [[ "$QA_PRODUCTION_SMOKE" == "1" ]]; then
  verify_production_state_absent \
    || { echo "error: hermetic production launch retained product state" >&2; exit 3; }
fi

verify_private_app_snapshot_identity \
  || { echo "error: private $QA_SELECTED_APP_LABEL snapshot changed during sampling" >&2; exit 3; }
verify_selected_app_identity \
  || { echo "error: selected $QA_SELECTED_APP_LABEL changed during sampling" >&2; exit 3; }

verify_evidence_descriptor "$QA_OUTPUT_CSV" 7 "$QA_CSV_FILE_TOKEN" "CSV" "$QA_MAX_CSV_BYTES" \
  || exit 3
verify_evidence_descriptor "$QA_APP_LOG" 8 "$QA_APP_LOG_FILE_TOKEN" "App log" "$QA_MAX_APP_LOG_BYTES" \
  || exit 3

# Analyze an exact pread snapshot from a second no-follow descriptor whose
# identity is bound to the still-open CSV writer. The analyzer therefore never
# follows the public evidence pathname or performs repeated reads across a
# replaceable file.
QA_ANALYSIS_INPUT="$QA_TEMP_DIR/performance-samples.csv"
snapshot_evidence_file "$QA_OUTPUT_CSV" "$QA_CSV_FILE_TOKEN" "$QA_MAX_CSV_BYTES" "$QA_ANALYSIS_INPUT" \
  || { echo "error: failed to snapshot performance CSV descriptor" >&2; exit 3; }

set +e
QA_ANALYSIS="$("$QA_ANALYZER" \
  "$QA_ANALYSIS_INPUT" \
  "$QA_MAX_AVERAGE_CPU" \
  "$QA_MAX_RSS_SLOPE" \
  "$QA_MAX_RSS_GROWTH")"
QA_ANALYSIS_STATUS=$?
set -e
verify_evidence_descriptor "$QA_OUTPUT_CSV" 7 "$QA_CSV_FILE_TOKEN" "CSV" "$QA_MAX_CSV_BYTES" \
  || exit 3

QA_SUMMARY_CONTENT="$({
  printf 'scenario=%s\n' "$QA_SCENARIO"
  printf 'launch_profile=%s\n' "$QA_LAUNCH_PROFILE"
  printf 'production_services_isolated=%s\n' "$QA_PRODUCTION_SERVICES_ISOLATED"
  printf 'pid=%s\n' "$QA_LAUNCH_PID"
  printf 'bundle_identifier=%s\n' "$QA_BUNDLE_ID"
  printf 'app_version=%s\n' "$QA_APP_VERSION"
  printf 'app_build=%s\n' "$QA_APP_BUILD"
  printf 'executable_sha256=%s\n' "$QA_EXECUTABLE_SHA256"
  printf 'selected_executable_sha256=%s\n' "$QA_SELECTED_EXECUTABLE_SHA256"
  printf 'machine_model=%s\n' "$QA_MACHINE_MODEL"
  printf 'machine_arch=%s\n' "$QA_MACHINE_ARCH"
  printf 'macos_version=%s\n' "$QA_MACOS_VERSION"
  printf 'warmup_seconds=%s\n' "$QA_WARMUP_SECONDS"
  printf 'sample_seconds=%s\n' "$QA_SAMPLE_SECONDS"
  printf 'screen_locked=%s\n' "$QA_SCREEN_LOCKED"
  printf 'screen_state_initial=%s\n' "$QA_SCREEN_STATE_INITIAL"
  printf 'screen_state_final=%s\n' "$QA_SCREEN_STATE_FINAL"
  printf 'isolated_user_home=true\n'
  printf 'isolated_app_snapshot=true\n'
  printf 'normal_termination=true\n'
  printf 'app_exit_status=%s\n' "$QA_EXIT_STATUS"
  printf 'launch_ready_ms=%s\n' "$QA_LAUNCH_READY_MS"
  printf '%s\n' "$QA_ANALYSIS"
})"
printf '%s\n' "$QA_SUMMARY_CONTENT" >&9
verify_evidence_descriptor "$QA_SUMMARY" 9 "$QA_SUMMARY_FILE_TOKEN" "summary" "$QA_MAX_SUMMARY_BYTES" \
  || exit 3

printf '%s\n' "$QA_SUMMARY_CONTENT"
exit "$QA_ANALYSIS_STATUS"
