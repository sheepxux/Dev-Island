#!/usr/bin/env ruby

require "fileutils"
require "open3"
require "securerandom"

class BoundaryError < StandardError; end

MAXIMUM_PATH_BYTES = 4_096
PRODUCT_BUNDLE_IDS = [
  "app.devisland.Island",
  "app.devisland.Island.PerformanceQA",
].freeze

def fail_boundary!(message)
  raise BoundaryError, message
end

def path_exists?(path)
  File.lstat(path)
  true
rescue Errno::ENOENT
  false
end

def safe_path_text!(value, label)
  fail_boundary!("#{label} is empty") if value.nil? || value.empty?
  fail_boundary!("#{label} is too long") if value.bytesize > MAXIMUM_PATH_BYTES
  fail_boundary!("#{label} contains control characters") if value.match?(/[\x00-\x1f\x7f]/)
  value
end

def directory_metadata(stat)
  [stat.dev, stat.ino, stat.uid, stat.mode, stat.nlink]
end

def owned_private_directory!(path, label)
  stat = File.lstat(path)
  fail_boundary!("#{label} must be a regular non-symlink directory") unless stat.directory? && !stat.symlink?
  fail_boundary!("#{label} must be owned by the current user") unless stat.uid == Process.uid
  fail_boundary!("#{label} must not be group/other writable") unless (stat.mode & 0o022).zero?
  stat
rescue Errno::ENOENT
  fail_boundary!("#{label} is missing")
end

def canonical_existing_directory!(path, label)
  initial = owned_private_directory!(path, label)
  canonical = File.realpath(path)
  final = owned_private_directory!(canonical, label)
  fail_boundary!("#{label} changed while it was resolved") unless directory_metadata(initial) == directory_metadata(final)
  canonical
rescue Errno::EACCES, Errno::ELOOP, Errno::ENOTDIR
  fail_boundary!("#{label} could not be resolved safely")
end

def within?(path, root)
  path == root || path.start_with?(root + File::SEPARATOR)
end

def repository_root!(path)
  safe_path_text!(path, "repository root")
  canonical_existing_directory!(path, "repository root")
end

def validate_build_location!(candidate, repository_root)
  fail_boundary!("build output directory must not be the filesystem root") if candidate == File::SEPARATOR
  if within?(repository_root, candidate)
    fail_boundary!("build output directory must not be the repository or one of its ancestors")
  end

  return unless within?(candidate, repository_root)

  allowed_root = File.join(repository_root, "build")
  fail_boundary!("repository-local build output must stay under build/") unless within?(candidate, allowed_root)
end

def validate_scratch_location!(candidate, repository_root)
  fail_boundary!("SwiftPM scratch directory must not be the filesystem root") if candidate == File::SEPARATOR
  if within?(repository_root, candidate)
    fail_boundary!("SwiftPM scratch directory must not be the repository or one of its ancestors")
  end

  return unless within?(candidate, repository_root)

  allowed_root = File.join(repository_root, ".build")
  fail_boundary!("repository-local SwiftPM scratch must stay below .build/") \
    unless candidate != allowed_root && within?(candidate, allowed_root)
end

def prepare_build_directory!(input, repository_root)
  safe_path_text!(input, "build output directory")
  expanded = File.expand_path(input, repository_root)

  if path_exists?(expanded)
    stat = File.lstat(expanded)
    fail_boundary!("build output directory must not be a symbolic link") if stat.symlink?
    canonical = canonical_existing_directory!(expanded, "build output directory")
    parent = canonical_existing_directory!(File.dirname(canonical), "build output parent")
    validate_build_location!(canonical, repository_root)
    fail_boundary!("build output directory parent changed while it was resolved") unless File.dirname(canonical) == parent
    return canonical
  end

  parent_input = File.dirname(expanded)
  parent = canonical_existing_directory!(parent_input, "build output parent")
  candidate = File.join(parent, File.basename(expanded))
  validate_build_location!(candidate, repository_root)

  begin
    Dir.mkdir(candidate, 0o700)
  rescue Errno::EEXIST
    fail_boundary!("build output directory appeared while it was being created")
  rescue SystemCallError
    fail_boundary!("build output directory could not be created safely")
  end

  created = canonical_existing_directory!(candidate, "build output directory")
  fail_boundary!("build output directory resolved to an unexpected location") unless created == candidate
  created
end

def prepare_scratch_directory!(input, repository_root)
  safe_path_text!(input, "SwiftPM scratch directory")
  expanded = File.expand_path(input, repository_root)

  if path_exists?(expanded)
    stat = File.lstat(expanded)
    fail_boundary!("SwiftPM scratch directory must not be a symbolic link") if stat.symlink?
    canonical = canonical_existing_directory!(expanded, "SwiftPM scratch directory")
    parent = canonical_existing_directory!(File.dirname(canonical), "SwiftPM scratch parent")
    validate_scratch_location!(canonical, repository_root)
    fail_boundary!("SwiftPM scratch parent changed while it was resolved") unless File.dirname(canonical) == parent
    return canonical
  end

  parent = canonical_existing_directory!(File.dirname(expanded), "SwiftPM scratch parent")
  candidate = File.join(parent, File.basename(expanded))
  validate_scratch_location!(candidate, repository_root)

  begin
    Dir.mkdir(candidate, 0o700)
  rescue Errno::EEXIST
    fail_boundary!("SwiftPM scratch directory appeared while it was being created")
  rescue SystemCallError
    fail_boundary!("SwiftPM scratch directory could not be created safely")
  end

  created = canonical_existing_directory!(candidate, "SwiftPM scratch directory")
  fail_boundary!("SwiftPM scratch directory resolved to an unexpected location") unless created == candidate
  created
end

def regular_owned_file!(path, label, executable: false)
  stat = File.lstat(path)
  fail_boundary!("#{label} must be a regular non-symlink file") unless stat.file? && !stat.symlink?
  fail_boundary!("#{label} must be owned by the current user") unless stat.uid == Process.uid
  fail_boundary!("#{label} must have exactly one hard link") unless stat.nlink == 1
  fail_boundary!("#{label} must not be group/other writable") unless (stat.mode & 0o022).zero?
  fail_boundary!("#{label} must be executable") if executable && (stat.mode & 0o100).zero?
  stat
rescue Errno::ENOENT
  fail_boundary!("#{label} is missing")
end

def plist_value!(plist, key)
  stdout, _stderr, status = Open3.capture3(
    "/usr/libexec/PlistBuddy", "-c", "Print :#{key}", plist,
  )
  fail_boundary!("App Info.plist is missing #{key}") unless status.success?
  value = stdout.delete_suffix("\n")
  fail_boundary!("App Info.plist #{key} is malformed") if value.empty? || value.include?("\n")
  value
end

def validate_product_app!(app, expected_bundle_ids, label)
  root = owned_private_directory!(app, label)
  info = File.join(app, "Contents", "Info.plist")
  executable = File.join(app, "Contents", "MacOS", "IslandApp")
  regular_owned_file!(info, "#{label} Info.plist")
  regular_owned_file!(executable, "#{label} executable", executable: true)

  bundle_id = plist_value!(info, "CFBundleIdentifier")
  fail_boundary!("#{label} has an unexpected bundle identifier") unless expected_bundle_ids.include?(bundle_id)
  fail_boundary!("#{label} has an unexpected executable") unless plist_value!(info, "CFBundleExecutable") == "IslandApp"
  fail_boundary!("#{label} has an unexpected package type") unless plist_value!(info, "CFBundlePackageType") == "APPL"

  _stdout, _stderr, status = Open3.capture3(
    "/usr/bin/codesign", "--verify", "--deep", "--strict", app,
  )
  fail_boundary!("#{label} must have a valid complete code signature") unless status.success?
  root
end

def fsync_directory!(path)
  File.open(path, File::RDONLY) { |directory| directory.fsync }
rescue SystemCallError
  fail_boundary!("build output directory metadata could not be synchronized")
end

def unique_absent_path(parent, prefix)
  16.times do
    candidate = File.join(parent, "#{prefix}#{SecureRandom.hex(16)}")
    return candidate unless path_exists?(candidate)
  end
  fail_boundary!("could not allocate a private publication path")
end

def publish_app!(build_dir, staging_root, bundle_id, repository_root)
  fail_boundary!("bundle identifier is not a Dev Island product identifier") unless PRODUCT_BUNDLE_IDS.include?(bundle_id)
  build_dir = canonical_existing_directory!(build_dir, "build output directory")
  validate_build_location!(build_dir, repository_root)
  parent = canonical_existing_directory!(File.dirname(build_dir), "build output parent")
  fail_boundary!("build output directory parent changed while it was resolved") unless File.dirname(build_dir) == parent

  staging_stat = owned_private_directory!(staging_root, "App staging directory")
  fail_boundary!("App staging directory must be a direct child of the build output directory") \
    unless File.dirname(staging_root) == build_dir
  fail_boundary!("App staging directory name is invalid") \
    unless File.basename(staging_root).match?(/\A\.dev-island-build\.[A-Za-z0-9]+\z/)
  fail_boundary!("App staging directory must be private") unless (staging_stat.mode & 0o077).zero?

  staged_app = File.join(staging_root, "Dev Island.app")
  staged_stat = validate_product_app!(staged_app, [bundle_id], "staged App")
  destination = File.join(build_dir, "Dev Island.app")
  previous_stat = nil

  if path_exists?(destination)
    destination_lstat = File.lstat(destination)
    fail_boundary!("existing App destination must not be a symbolic link") if destination_lstat.symlink?
    previous_stat = validate_product_app!(destination, PRODUCT_BUNDLE_IDS, "existing App destination")
  end

  backup = previous_stat ? unique_absent_path(build_dir, ".dev-island-previous.") : nil
  failed_new = nil
  previous_moved = false
  new_moved = false

  begin
    if backup
      File.rename(destination, backup)
      moved = File.lstat(backup)
      fail_boundary!("existing App changed during publication") \
        unless directory_metadata(moved) == directory_metadata(previous_stat)
      previous_moved = true
      fsync_directory!(build_dir)
    end

    File.rename(staged_app, destination)
    moved = File.lstat(destination)
    fail_boundary!("staged App changed during publication") \
      unless directory_metadata(moved) == directory_metadata(staged_stat)
    new_moved = true
    fsync_directory!(build_dir)
    validate_product_app!(destination, [bundle_id], "published App")
  rescue BoundaryError, SystemCallError => error
    if new_moved && path_exists?(destination)
      failed_new = unique_absent_path(build_dir, ".dev-island-failed.")
      begin
        File.rename(destination, failed_new)
        new_moved = false
      rescue SystemCallError
        # Leave both generations untouched if the recovery rename itself
        # cannot be proven. The diagnostic remains low-detail and no further
        # destructive operation is attempted.
      end
    end
    if previous_moved && !path_exists?(destination)
      begin
        File.rename(backup, destination)
        previous_moved = false
        fsync_directory!(build_dir)
      rescue SystemCallError
        # Preserve the backup for manual recovery rather than deleting either
        # generation after a failed restore.
      end
    end
    FileUtils.remove_entry(failed_new) if failed_new && path_exists?(failed_new) && !new_moved
    fail_boundary!(error.is_a?(BoundaryError) ? error.message : "App publication failed safely")
  end

  if backup
    FileUtils.remove_entry(backup)
    fsync_directory!(build_dir)
  end
  Dir.rmdir(staging_root)
  fsync_directory!(build_dir)
  destination
rescue Errno::ENOENT, Errno::ELOOP, Errno::ENOTDIR
  fail_boundary!("App publication path changed unexpectedly")
end

def parse_options(arguments)
  options = {}
  until arguments.empty?
    key = arguments.shift
    fail_boundary!("unexpected argument") unless key&.start_with?("--") && !arguments.empty?
    fail_boundary!("duplicate argument: #{key}") if options.key?(key)
    options[key] = arguments.shift
  end
  options
end

begin
  command = ARGV.shift
  options = parse_options(ARGV)
  required = case command
             when "prepare"
               ["--repository-root", "--build-dir"]
             when "prepare-scratch"
               ["--repository-root", "--scratch-dir"]
             when "publish"
               ["--repository-root", "--build-dir", "--staging-root", "--bundle-id"]
             else
               fail_boundary!("usage: app-build-output-boundary.rb prepare|prepare-scratch|publish [options]")
             end
  fail_boundary!("incorrect arguments") unless options.keys.sort == required.sort

  repository_root = repository_root!(options.fetch("--repository-root"))
  if command == "prepare"
    puts prepare_build_directory!(options.fetch("--build-dir"), repository_root)
  elsif command == "prepare-scratch"
    puts prepare_scratch_directory!(options.fetch("--scratch-dir"), repository_root)
  else
    safe_path_text!(options.fetch("--build-dir"), "build output directory")
    safe_path_text!(options.fetch("--staging-root"), "App staging directory")
    build_dir = File.expand_path(options.fetch("--build-dir"), repository_root)
    validate_build_location!(build_dir, repository_root)
    puts publish_app!(
      build_dir,
      options.fetch("--staging-root"),
      options.fetch("--bundle-id"),
      repository_root,
    )
  end
rescue BoundaryError => error
  warn "error: #{error.message}"
  exit 1
rescue SystemCallError, ArgumentError
  warn "error: App build output boundary could not complete safely"
  exit 1
end
