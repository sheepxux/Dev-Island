#!/usr/bin/env ruby

# One product-version boundary shared by local App builds and tagged Release
# tooling. CFBundleShortVersionString and CFBundleVersion currently use the
# same value, so only Apple's canonical numeric three-component form is
# accepted. A prerelease channel needs an explicit, separately reviewed bundle
# build-number policy instead of smuggling suffixes into Info.plist.

MAXIMUM_FILE_BYTES = 64
VERSION_PATTERN = /\A(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,1})\.(0|[1-9][0-9]{0,1})\z/

def fail!(message, status = 1)
  warn "error: #{message}"
  exit status
end

def valid_version!(value)
  fail!("VERSION must be canonical numeric major.minor.patch") unless VERSION_PATTERN.match?(value)
  value
end

def read_version_file!(path)
  begin
    initial = File.lstat(path)
  rescue Errno::ENOENT
    fail!("VERSION file is missing")
  end
  fail!("VERSION must be a regular non-symlink file") unless initial.file? && !initial.symlink?
  fail!("VERSION must be owned by the current user") unless initial.uid == Process.uid
  fail!("VERSION must have exactly one hard link") unless initial.nlink == 1
  fail!("VERSION must not be group/other writable") unless (initial.mode & 0o022).zero?
  fail!("VERSION size must be between 1 and #{MAXIMUM_FILE_BYTES} bytes") \
    unless initial.size.between?(1, MAXIMUM_FILE_BYTES)

  flags = File::RDONLY
  flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
  bytes = nil
  File.open(path, flags) do |file|
    opened = file.stat
    fail!("VERSION changed before it could be read") \
      unless [opened.dev, opened.ino, opened.uid, opened.mode, opened.nlink, opened.size] ==
        [initial.dev, initial.ino, initial.uid, initial.mode, initial.nlink, initial.size]
    bytes = file.read(initial.size)
    fail!("VERSION read was incomplete") unless bytes&.bytesize == initial.size && file.read(1).to_s.empty?
    final = file.stat
    fail!("VERSION changed while it was read") \
      unless [final.dev, final.ino, final.uid, final.mode, final.nlink, final.size] ==
        [opened.dev, opened.ino, opened.uid, opened.mode, opened.nlink, opened.size]
  end

  match = bytes.match(/\A((?:0|[1-9][0-9]{0,3})\.(?:0|[1-9][0-9]{0,1})\.(?:0|[1-9][0-9]{0,1}))\n\z/)
  fail!("VERSION file must contain one canonical version and one trailing newline") unless match
  valid_version!(match[1])
rescue Errno::ELOOP
  fail!("VERSION must be a regular non-symlink file")
rescue SystemCallError
  fail!("VERSION could not be read safely")
end

version = case ARGV
when ["--version-file", ARGV[1]]
  read_version_file!(ARGV[1])
when ["--version", ARGV[1]]
  valid_version!(ARGV[1])
else
  fail!("Usage: validate-product-version.rb --version-file PATH | --version X.Y.Z", 64)
end

STDOUT.write(version)
STDOUT.write("\n")
