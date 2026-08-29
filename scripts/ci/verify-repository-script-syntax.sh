#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/release/verify-repository-script-syntax.rb"

fail() {
  echo "error: $1" >&2
  exit 1
}

test -x "$VALIDATOR" || fail "repository script syntax validator is unavailable"
"$VALIDATOR" >/dev/null

FIXTURE_ROOT="$(mktemp -d -t dev-island-repository-scripts)"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

make_valid_root() {
  local root="$1"
  local shell_marker="$2"
  local ruby_marker="$3"
  local swift_marker="$4"
  mkdir -p "$root"
  ruby -e '
    root, shell_marker, ruby_marker, swift_marker = ARGV
    File.binwrite(
      File.join(root, "valid.sh"),
      "#!/usr/bin/env bash\nprintf x > #{shell_marker.dump}\n"
    )
    File.binwrite(
      File.join(root, "valid.rb"),
      "#!/usr/bin/env ruby\nFile.binwrite(#{ruby_marker.dump}, \"x\")\n"
    )
    File.binwrite(
      File.join(root, "valid.swift"),
      "#!/usr/bin/env swift\nimport Foundation\ntry! Data(\"x\".utf8).write(to: URL(fileURLWithPath: #{swift_marker.dump}))\n"
    )
  ' "$root" "$shell_marker" "$ruby_marker" "$swift_marker"
  chmod 700 "$root/valid.sh" "$root/valid.rb"
  chmod 600 "$root/valid.swift"
}

expect_rejected() {
  local root="$1"
  local expected="$2"
  local output="$FIXTURE_ROOT/rejected.log"
  if "$VALIDATOR" --scripts-root "$root" >"$output" 2>&1; then
    fail "unsafe repository-script fixture unexpectedly passed: $(basename "$root")"
  fi
  rg -Fq "$expected" "$output" \
    || fail "repository-script fixture failed for the wrong reason: $(basename "$root")"
}

positive="$FIXTURE_ROOT/positive"
positive_shell_marker="$FIXTURE_ROOT/positive-shell-marker"
positive_ruby_marker="$FIXTURE_ROOT/positive-ruby-marker"
positive_swift_marker="$FIXTURE_ROOT/positive-swift-marker"
make_valid_root "$positive" "$positive_shell_marker" "$positive_ruby_marker" "$positive_swift_marker"
"$VALIDATOR" --scripts-root "$positive" >/dev/null
test ! -e "$positive_shell_marker" \
  && test ! -e "$positive_ruby_marker" \
  && test ! -e "$positive_swift_marker" \
  || fail "repository syntax validation executed a reviewed script"

broken_bash="$FIXTURE_ROOT/broken-bash"
broken_bash_marker="$FIXTURE_ROOT/broken-bash-marker"
make_valid_root "$broken_bash" "$broken_bash_marker" "$FIXTURE_ROOT/unused-ruby-marker" "$FIXTURE_ROOT/unused-swift-marker"
ruby -e 'File.open(ARGV.fetch(0), "ab") { |file| file.write("if true; then\n") }' \
  "$broken_bash/valid.sh"
expect_rejected "$broken_bash" "repository script syntax is invalid: valid.sh"
test ! -e "$broken_bash_marker" \
  || fail "Bash syntax validation executed content before a later syntax error"

broken_ruby="$FIXTURE_ROOT/broken-ruby"
broken_ruby_marker="$FIXTURE_ROOT/broken-ruby-marker"
make_valid_root "$broken_ruby" "$FIXTURE_ROOT/unused-shell-marker" "$broken_ruby_marker" "$FIXTURE_ROOT/unused-swift-marker"
ruby -e 'File.open(ARGV.fetch(0), "ab") { |file| file.write("def broken(\n") }' \
  "$broken_ruby/valid.rb"
expect_rejected "$broken_ruby" "repository script syntax is invalid: valid.rb"
test ! -e "$broken_ruby_marker" \
  || fail "Ruby syntax validation executed content before a later syntax error"

broken_swift="$FIXTURE_ROOT/broken-swift"
broken_swift_marker="$FIXTURE_ROOT/broken-swift-marker"
make_valid_root "$broken_swift" "$FIXTURE_ROOT/unused-shell-marker" "$FIXTURE_ROOT/unused-ruby-marker" "$broken_swift_marker"
ruby -e 'File.open(ARGV.fetch(0), "ab") { |file| file.write("func broken(\n") }' \
  "$broken_swift/valid.swift"
expect_rejected "$broken_swift" "repository script syntax is invalid: valid.swift"
test ! -e "$broken_swift_marker" \
  || fail "Swift syntax validation executed content before a later syntax error"

bad_shebang="$FIXTURE_ROOT/bad-shebang"
make_valid_root "$bad_shebang" "$FIXTURE_ROOT/unused-shell-marker" "$FIXTURE_ROOT/unused-ruby-marker" "$FIXTURE_ROOT/unused-swift-marker"
ruby -e '
  path = ARGV.fetch(0)
  source = File.binread(path)
  File.binwrite(path, source.sub("#!/usr/bin/env bash", "#!/bin/sh"))
' "$bad_shebang/valid.sh"
expect_rejected "$bad_shebang" "repository script shebang is unreviewed: valid.sh"

bad_swift_shebang="$FIXTURE_ROOT/bad-swift-shebang"
make_valid_root "$bad_swift_shebang" "$FIXTURE_ROOT/unused-shell-marker" "$FIXTURE_ROOT/unused-ruby-marker" "$FIXTURE_ROOT/unused-swift-marker"
ruby -e '
  path = ARGV.fetch(0)
  source = File.binread(path)
  File.binwrite(path, source.sub("#!/usr/bin/env swift", "#!/usr/bin/swift"))
' "$bad_swift_shebang/valid.swift"
expect_rejected "$bad_swift_shebang" "repository script shebang is unreviewed: valid.swift"

non_executable="$FIXTURE_ROOT/non-executable"
make_valid_root "$non_executable" "$FIXTURE_ROOT/unused-shell-marker" "$FIXTURE_ROOT/unused-ruby-marker" "$FIXTURE_ROOT/unused-swift-marker"
chmod 600 "$non_executable/valid.sh"
expect_rejected "$non_executable" "repository script must be executable: valid.sh"

writable="$FIXTURE_ROOT/writable"
make_valid_root "$writable" "$FIXTURE_ROOT/unused-shell-marker" "$FIXTURE_ROOT/unused-ruby-marker" "$FIXTURE_ROOT/unused-swift-marker"
chmod 722 "$writable/valid.sh"
expect_rejected "$writable" "repository script permissions are unsafe: valid.sh"

hardlink="$FIXTURE_ROOT/hardlink"
make_valid_root "$hardlink" "$FIXTURE_ROOT/unused-shell-marker" "$FIXTURE_ROOT/unused-ruby-marker" "$FIXTURE_ROOT/unused-swift-marker"
ln "$hardlink/valid.sh" "$hardlink/peer"
expect_rejected "$hardlink" "repository script must have exactly one hard link: valid.sh"

symlink_file="$FIXTURE_ROOT/symlink-file"
make_valid_root "$symlink_file" "$FIXTURE_ROOT/unused-shell-marker" "$FIXTURE_ROOT/unused-ruby-marker" "$FIXTURE_ROOT/unused-swift-marker"
ln -s "$symlink_file/valid.sh" "$symlink_file/linked.sh"
expect_rejected "$symlink_file" "repository scripts tree contains a symbolic link: linked.sh"

symlink_target="$FIXTURE_ROOT/symlink-target"
mkdir -p "$symlink_target"
symlink_directory="$FIXTURE_ROOT/symlink-directory"
make_valid_root "$symlink_directory" "$FIXTURE_ROOT/unused-shell-marker" "$FIXTURE_ROOT/unused-ruby-marker" "$FIXTURE_ROOT/unused-swift-marker"
ln -s "$symlink_target" "$symlink_directory/linked"
expect_rejected "$symlink_directory" "repository scripts tree contains a symbolic link: linked"

oversized="$FIXTURE_ROOT/oversized"
make_valid_root "$oversized" "$FIXTURE_ROOT/unused-shell-marker" "$FIXTURE_ROOT/unused-ruby-marker" "$FIXTURE_ROOT/unused-swift-marker"
ruby -e '
  path = ARGV.fetch(0)
  File.open(path, "ab") { |file| file.write("#" * 1_048_576) }
' "$oversized/valid.sh"
expect_rejected "$oversized" "repository script size is invalid: valid.sh"

nul_byte="$FIXTURE_ROOT/nul-byte"
make_valid_root "$nul_byte" "$FIXTURE_ROOT/unused-shell-marker" "$FIXTURE_ROOT/unused-ruby-marker" "$FIXTURE_ROOT/unused-swift-marker"
ruby -e 'File.open(ARGV.fetch(0), "ab") { |file| file.write("\0") }' "$nul_byte/valid.sh"
expect_rejected "$nul_byte" "repository script contains a NUL byte: valid.sh"

invalid_utf8="$FIXTURE_ROOT/invalid-utf8"
make_valid_root "$invalid_utf8" "$FIXTURE_ROOT/unused-shell-marker" "$FIXTURE_ROOT/unused-ruby-marker" "$FIXTURE_ROOT/unused-swift-marker"
ruby -e 'File.open(ARGV.fetch(0), "ab") { |file| file.write([0xFF].pack("C")) }' \
  "$invalid_utf8/valid.sh"
expect_rejected "$invalid_utf8" "repository script contains invalid UTF-8: valid.sh"

echo "Repository script syntax fixtures: PASS"
