#!/usr/bin/env bash

set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/release/validate-pinned-create-dmg-archive.rb"
COMMIT="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
TEMP_ROOT="$(mktemp -d -t dev-island-create-dmg-archive)"
trap 'rm -rf "$TEMP_ROOT"' EXIT

fail() {
  echo "::error::$1" >&2
  exit 1
}

test -x "$VALIDATOR" || fail "Pinned create-dmg archive validator is not executable"

repeat_sha256() {
  ruby -rdigest -e 'print Digest::SHA256.hexdigest(ARGV.fetch(0) * Integer(ARGV.fetch(1), 10))' "$1" "$2"
}

SCRIPT_SHA256="$(repeat_sha256 S 22377)"
SENTINEL_SHA256="$(repeat_sha256 N 128)"
TEMPLATE_SHA256="$(repeat_sha256 T 1819)"
EULA_TEMPLATE_SHA256="$(repeat_sha256 E 2372)"

build_fixture() {
  local mode="$1"
  local archive="$2"

  VALIDATOR_SOURCE="$VALIDATOR" ruby - "$archive" "$mode" "$COMMIT" <<'RUBY'
require "zlib"
require ENV.fetch("VALIDATOR_SOURCE")

archive, mode, commit = ARGV
prefix = "create-dmg-#{commit}"

entries = PinnedCreateDMGArchive::EXPECTED_ENTRIES.map do |relative, (type, size)|
  full_name = relative == "." ? "#{prefix}/" : "#{prefix}/#{relative}"
  full_name = "#{full_name}/" if type == :directory && relative != "."
  {
    relative: relative,
    type: type == :directory ? "5" : "0",
    size: size,
    linkname: "",
    full_name: full_name
  }
end

def selected(entries, relative)
  entries.fetch(entries.index { |entry| entry.fetch(:relative) == relative })
end

case mode
when "valid"
  # No mutation.
when "traversal"
  selected(entries, ".gitignore")[:full_name] = "#{prefix}/../escape"
when "absolute"
  selected(entries, ".gitignore")[:full_name] = "/absolute-escape"
when "control"
  selected(entries, ".gitignore")[:full_name] = "#{prefix}/bad\nname"
when "deep"
  selected(entries, ".gitignore")[:full_name] = "#{prefix}/one/two/three/four/five"
when "duplicate"
  selected(entries, ".gitignore")[:full_name] = "#{prefix}/.editorconfig"
when "symlink"
  entry = selected(entries, ".gitignore")
  entry[:type] = "2"
  entry[:size] = 0
  entry[:linkname] = "../../escape"
when "hardlink"
  entry = selected(entries, "LICENSE")
  entry[:type] = "1"
  entry[:size] = 0
  entry[:linkname] = "#{prefix}/README.md"
when "character-device"
  entry = selected(entries, "Makefile")
  entry[:type] = "3"
  entry[:size] = 0
when "block-device"
  entry = selected(entries, "Makefile")
  entry[:type] = "4"
  entry[:size] = 0
when "fifo"
  entry = selected(entries, "Makefile")
  entry[:type] = "6"
  entry[:size] = 0
when "extra"
  selected(entries, ".gitignore")[:full_name] = "#{prefix}/unreviewed"
when "too-many"
  entries << {
    relative: "extra",
    type: "0",
    size: 1,
    linkname: "",
    full_name: "#{prefix}/extra"
  }
when "oversize"
  selected(entries, "README.md")[:size] = PinnedCreateDMGArchive::MAX_ENTRY_BYTES + 1
when "runtime-hash"
  selected(entries, "create-dmg")[:payload_marker] = "X"
when "runtime-size"
  selected(entries, "create-dmg")[:size] = 22_376
when "wrong-pax", "extra-pax", "extended-pax", "missing-pax"
  # PAX mutations are emitted below.
else
  abort "unknown fixture mode: #{mode}"
end

def split_ustar_name(full_name)
  trailing_slash = full_name.end_with?("/")
  body = trailing_slash ? full_name[0...-1] : full_name
  suffix = trailing_slash ? "/" : ""
  return ["#{body}#{suffix}", ""] if body.bytesize + suffix.bytesize <= 100

  separator = body.rindex("/")
  raise "fixture path cannot be represented in ustar" unless separator

  prefix = body[0...separator]
  name = "#{body[(separator + 1)..-1]}#{suffix}"
  raise "fixture ustar name is too long" if name.bytesize > 100 || prefix.bytesize > 155
  [name, prefix]
end

def write_record(io, full_name:, type:, size:, payload:, linkname: "")
  name, prefix = split_ustar_name(full_name)
  header = Gem::Package::TarHeader.new(
    name: name,
    prefix: prefix,
    mode: type == "5" ? 0o775 : 0o664,
    uid: 0,
    gid: 0,
    size: size,
    mtime: 0,
    typeflag: type,
    linkname: linkname,
    uname: "root",
    gname: "root"
  )
  io.write(header.to_s)
  io.write(payload)
  io.write("\0" * ((512 - (payload.bytesize % 512)) % 512))
end

def payload_for(entry)
  return "" if entry.fetch(:type) == "5" || entry.fetch(:size).zero?

  marker = entry[:payload_marker]
  marker ||= case entry.fetch(:relative)
             when "create-dmg" then "S"
             when ".this-is-the-create-dmg-repo" then "N"
             when "support/template.applescript" then "T"
             when "support/eula-resources-template.xml" then "E"
             else "f"
             end
  marker * entry.fetch(:size)
end

Zlib::GzipWriter.open(archive) do |gzip|
  unless mode == "missing-pax"
    pax_commit = mode == "wrong-pax" ? ("b" * 40) : commit
    pax_payload = "52 comment=#{pax_commit}\n"
    write_record(
      gzip,
      full_name: "pax_global_header",
      type: "g",
      size: pax_payload.bytesize,
      payload: pax_payload
    )
  end

  if mode == "extra-pax" || mode == "extended-pax"
    type = mode == "extra-pax" ? "g" : "x"
    payload = "20 comment=unexpected\n"
    write_record(
      gzip,
      full_name: mode == "extra-pax" ? "pax_global_header" : "PaxHeaders/entry",
      type: type,
      size: payload.bytesize,
      payload: payload
    )
  end

  entries.each do |entry|
    payload = if mode == "oversize" && entry.fetch(:relative) == "README.md"
                # The validator rejects the declared size before TarReader can
                # seek through the payload, keeping this attack fixture tiny.
                ""
              else
                payload_for(entry)
              end
    write_record(
      gzip,
      full_name: entry.fetch(:full_name),
      type: entry.fetch(:type),
      size: entry.fetch(:size),
      payload: payload,
      linkname: entry.fetch(:linkname)
    )
  end

  gzip.write("\0" * 1_024)
end
RUBY
  chmod 600 "$archive"
}

run_validator() {
  local archive="$1"
  local archive_sha256="${2:-}"
  if [[ -z "$archive_sha256" ]]; then
    archive_sha256="$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')"
  fi
  "$VALIDATOR" \
    --archive "$archive" \
    --archive-sha256 "$archive_sha256" \
    --commit "$COMMIT" \
    --script-sha256 "$SCRIPT_SHA256" \
    --sentinel-sha256 "$SENTINEL_SHA256" \
    --template-sha256 "$TEMPLATE_SHA256" \
    --eula-template-sha256 "$EULA_TEMPLATE_SHA256"
}

VALID_ARCHIVE="$TEMP_ROOT/valid.tar.gz"
build_fixture valid "$VALID_ARCHIVE"
[[ "$(run_validator "$VALID_ARCHIVE")" == "Pinned create-dmg archive: PASS" ]] \
  || fail "Reviewed archive fixture did not pass"

WRONG_ARCHIVE_SHA256="$(printf '0%.0s' {1..64})"
WRONG_ARCHIVE_SHA_LOG="$TEMP_ROOT/wrong-archive-sha.log"
if run_validator "$VALID_ARCHIVE" "$WRONG_ARCHIVE_SHA256" >"$WRONG_ARCHIVE_SHA_LOG" 2>&1; then
  fail "wrong expected compressed-archive SHA-256 unexpectedly passed"
fi
grep -Fq "compressed archive SHA-256 mismatch" "$WRONG_ARCHIVE_SHA_LOG" \
  || fail "wrong expected compressed-archive SHA-256 failed for the wrong reason"

INVALID_ARCHIVE_SHA_LOG="$TEMP_ROOT/invalid-archive-sha.log"
if run_validator "$VALID_ARCHIVE" "ABC" >"$INVALID_ARCHIVE_SHA_LOG" 2>&1; then
  fail "malformed expected compressed-archive SHA-256 unexpectedly passed"
fi
grep -Fq "archive SHA-256 must be lowercase 64hex" "$INVALID_ARCHIVE_SHA_LOG" \
  || fail "malformed expected compressed-archive SHA-256 failed for the wrong reason"

expect_rejected() {
  local label="$1"
  local mode="$2"
  local expected="$3"
  local archive="$TEMP_ROOT/${label}.tar.gz"
  local log="$TEMP_ROOT/${label}.log"

  build_fixture "$mode" "$archive"
  if run_validator "$archive" >"$log" 2>&1; then
    fail "$label fixture unexpectedly passed"
  fi
  grep -Fq "$expected" "$log" \
    || fail "$label fixture failed for the wrong reason: $(tr '\n' ' ' <"$log")"
}

expect_rejected traversal traversal "path traverses outside"
expect_rejected absolute absolute "path is absolute"
expect_rejected control control "control character"
expect_rejected deep deep "path is too deep"
expect_rejected duplicate duplicate "duplicate member"
expect_rejected symlink symlink "link or special entry type"
expect_rejected hardlink hardlink "link or special entry type"
expect_rejected character-device character-device "link or special entry type"
expect_rejected block-device block-device "link or special entry type"
expect_rejected fifo fifo "link or special entry type"
expect_rejected extra extra "unexpected member"
expect_rejected too-many too-many "too many records"
expect_rejected oversize oversize "member is too large"
expect_rejected wrong-pax wrong-pax "does not bind the reviewed commit"
expect_rejected extra-pax extra-pax "unexpected PAX header"
expect_rejected extended-pax extended-pax "unexpected PAX header"
expect_rejected missing-pax missing-pax "first archive record"
expect_rejected runtime-hash runtime-hash "runtime member SHA-256 mismatch"
expect_rejected runtime-size runtime-size "member size mismatch"

WRITABLE_ARCHIVE="$TEMP_ROOT/group-writable.tar.gz"
cp "$VALID_ARCHIVE" "$WRITABLE_ARCHIVE"
chmod 0660 "$WRITABLE_ARCHIVE"
if run_validator "$WRITABLE_ARCHIVE" >/dev/null 2>&1; then
  fail "group-writable archive unexpectedly passed"
fi

SYMLINK_ARCHIVE="$TEMP_ROOT/archive-symlink.tar.gz"
ln -s "$VALID_ARCHIVE" "$SYMLINK_ARCHIVE"
if run_validator "$SYMLINK_ARCHIVE" >/dev/null 2>&1; then
  fail "symbolic-link archive unexpectedly passed"
fi

HARDLINK_SOURCE="$TEMP_ROOT/hardlink-source.tar.gz"
HARDLINK_ARCHIVE="$TEMP_ROOT/archive-hardlink.tar.gz"
cp "$VALID_ARCHIVE" "$HARDLINK_SOURCE"
ln "$HARDLINK_SOURCE" "$HARDLINK_ARCHIVE"
if run_validator "$HARDLINK_ARCHIVE" >/dev/null 2>&1; then
  fail "hard-linked archive unexpectedly passed"
fi

MALFORMED_ARCHIVE="$TEMP_ROOT/malformed.tar.gz"
printf 'not a gzip archive' >"$MALFORMED_ARCHIVE"
if run_validator "$MALFORMED_ARCHIVE" >/dev/null 2>&1; then
  fail "malformed gzip archive unexpectedly passed"
fi

echo "Pinned create-dmg archive attack fixtures: PASS"
