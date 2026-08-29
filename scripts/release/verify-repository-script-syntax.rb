#!/usr/bin/env ruby

require "find"
require "open3"

MAX_SCRIPT_BYTES = 1_048_576
MAX_SCRIPT_COUNT = 256
MAX_TREE_ENTRIES = 4_096

def fail(message)
  warn "error: #{message}"
  exit 1
end

def safe_label(path, root)
  path.delete_prefix("#{root}/")
    .gsub(/[^A-Za-z0-9_.\/-]/, "_")
    .byteslice(0, 160)
end

def stable_stat?(before, after)
  %i[dev ino uid mode nlink size mtime ctime].all? do |field|
    before.public_send(field) == after.public_send(field)
  end
end

def read_reviewed_script(path, root, executable_required:)
  label = safe_label(path, root)
  flags = File::RDONLY | File::NOFOLLOW | File::NONBLOCK
  File.open(path, flags) do |file|
    before = file.stat
    fail("repository script must be a regular file: #{label}") unless before.file?
    fail("repository script must have exactly one hard link: #{label}") unless before.nlink == 1
    fail("repository script owner is unsafe: #{label}") unless before.uid == Process.uid
    fail("repository script permissions are unsafe: #{label}") unless (before.mode & 0o022).zero?
    if executable_required && (before.mode & 0o111).zero?
      fail("repository script must be executable: #{label}")
    end
    fail("repository script size is invalid: #{label}") unless before.size.between?(1, MAX_SCRIPT_BYTES)

    contents = file.read(MAX_SCRIPT_BYTES + 1)
    after = file.stat
    fail("repository script changed during inspection: #{label}") unless stable_stat?(before, after)
    fail("repository script read was incomplete: #{label}") unless contents.bytesize == before.size
    fail("repository script contains invalid UTF-8: #{label}") unless
      contents.force_encoding(Encoding::UTF_8).valid_encoding?
    fail("repository script contains a NUL byte: #{label}") if contents.include?("\0")
    contents
  end
rescue Errno::ENOENT
  fail("repository script disappeared during inspection: #{label}")
rescue Errno::ELOOP
  fail("repository script must not be a symbolic link: #{label}")
rescue SystemCallError
  fail("repository script could not be opened safely: #{label}")
end

def verify_script_syntax(path, contents, root)
  label = safe_label(path, root)
  extension = File.extname(path)
  expected_shebang, command, arguments, shebang_optional = case extension
  when ".sh"
    ["#!/usr/bin/env bash\n", "/bin/bash", ["-n"], false]
  when ".rb"
    ["#!/usr/bin/env ruby\n", "/usr/bin/ruby", ["-c"], false]
  when ".swift"
    ["#!/usr/bin/env swift\n", "/usr/bin/swiftc", ["-parse", "-"], true]
  else
    fail("repository script type is unsupported: #{label}")
  end

  shebang_valid = contents.start_with?(expected_shebang) ||
    (shebang_optional && !contents.start_with?("#!"))
  fail("repository script shebang is unreviewed: #{label}") unless shebang_valid
  _stdout, _stderr, status = Open3.capture3(
    { "LC_ALL" => "C" },
    command,
    *arguments,
    stdin_data: contents,
    unsetenv_others: true
  )
  fail("repository script syntax is invalid: #{label}") unless status.success?
  extension
end

unless ARGV.empty? || (ARGV.length == 2 && ARGV[0] == "--scripts-root")
  warn "Usage: verify-repository-script-syntax.rb [--scripts-root DIRECTORY]"
  exit 64
end

scripts_root = if ARGV.empty?
  File.expand_path("../..", __dir__) + "/scripts"
else
  File.expand_path(ARGV[1])
end

directory_snapshots = {}
script_paths = []
entry_count = 0

begin
  Find.find(scripts_root) do |path|
    entry_count += 1
    fail("repository scripts tree is too large") if entry_count > MAX_TREE_ENTRIES
    stat = File.lstat(path)
    label = safe_label(path, scripts_root)
    fail("repository scripts tree contains a symbolic link: #{label}") if stat.symlink?

    if stat.directory?
      fail("repository scripts directory owner is unsafe: #{label}") unless stat.uid == Process.uid
      fail("repository scripts directory permissions are unsafe: #{label}") unless
        (stat.mode & 0o022).zero?
      directory_snapshots[path] = stat
      next
    end

    fail("repository scripts tree contains a special file: #{label}") unless stat.file?
    script_paths << path if %w[.sh .rb .swift].include?(File.extname(path))
  end
rescue Errno::ENOENT
  fail("repository scripts directory does not exist")
rescue SystemCallError
  fail("repository scripts tree could not be inspected safely")
end

script_paths.sort!
fail("repository script count is invalid") unless script_paths.length.between?(1, MAX_SCRIPT_COUNT)

counts = Hash.new(0)
script_paths.each do |path|
  contents = read_reviewed_script(
    path,
    scripts_root,
    executable_required: File.extname(path) != ".swift"
  )
  counts[verify_script_syntax(path, contents, scripts_root)] += 1
end

directory_snapshots.each do |path, before|
  begin
    after = File.lstat(path)
    fail("repository scripts directory changed during inspection") unless
      after.directory? && !after.symlink? && stable_stat?(before, after)
  rescue SystemCallError
    fail("repository scripts directory changed during inspection")
  end
end

puts "Repository script syntax: PASS (#{counts['.sh']} Bash, #{counts['.rb']} Ruby, #{counts['.swift']} Swift)"
