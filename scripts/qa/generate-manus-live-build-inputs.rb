#!/usr/bin/env ruby

require "digest"
require "json"
require "open3"

MAXIMUM_INPUT_BYTES = 4 * 1_024 * 1_024
MAXIMUM_INPUT_FILES = 1_024
MAXIMUM_DEPENDENCIES = 256
MAXIMUM_GIT_OUTPUT_BYTES = 4 * 1_024 * 1_024

LOCAL_SOURCE_ROOTS = [
  "IslandCore/Sources/IslandCore",
  "IslandCoreCLI/Sources/IslandCoreCLI",
].freeze

FIXED_INPUTS = [
  "VERSION",
  "Package.swift",
  "Package.resolved",
  "scripts/release/validate-product-version.rb",
  "scripts/qa/generate-manus-live-build-inputs.rb",
  "scripts/qa/validate-manus-live-acceptance-transcript.rb",
  "scripts/qa/run-manus-live-acceptance.sh",
].freeze

def usage
  warn "Usage: generate-manus-live-build-inputs.rb --repository ROOT --scratch SWIFTPM_SCRATCH"
  exit 64
end

def reject(message)
  warn "error: #{message}"
  exit 1
end

def validate_directory(path, label)
  metadata = File.lstat(path)
  reject("#{label} must be a regular non-symlink directory") unless
    metadata.directory? && !metadata.symlink?
  reject("#{label} must be owned by the current user") unless metadata.uid == Process.uid
  reject("#{label} must not be group- or world-writable") unless (metadata.mode & 0o022).zero?
  metadata
rescue SystemCallError
  reject("#{label} is unavailable")
end

def safely_read(path, label, maximum_bytes: MAXIMUM_INPUT_BYTES)
  initial = File.lstat(path)
  reject("#{label} must be a regular non-symlink file") unless initial.file? && !initial.symlink?
  reject("#{label} must be owned by the current user") unless initial.uid == Process.uid
  reject("#{label} must have exactly one hard link") unless initial.nlink == 1
  reject("#{label} must not be group- or world-writable") unless (initial.mode & 0o022).zero?
  reject("#{label} size is outside its reviewed boundary") unless
    initial.size.between?(1, maximum_bytes)

  flags = File::RDONLY | File::NOFOLLOW
  flags |= File::CLOEXEC if File.const_defined?(:CLOEXEC)
  bytes = nil
  File.open(path, flags) do |file|
    opened = file.stat
    reject("#{label} changed before descriptor anchoring") unless
      [opened.dev, opened.ino, opened.uid, opened.mode, opened.nlink, opened.size] ==
        [initial.dev, initial.ino, initial.uid, initial.mode, initial.nlink, initial.size]
    bytes = file.read(initial.size)
    reject("#{label} read was incomplete") unless
      bytes&.bytesize == initial.size && file.read(1).to_s.empty?
    final = file.stat
    reject("#{label} changed while it was read") unless
      [final.dev, final.ino, final.uid, final.mode, final.nlink, final.size] ==
        [opened.dev, opened.ino, opened.uid, opened.mode, opened.nlink, opened.size]
  end
  path_after = File.lstat(path)
  reject("#{label} path changed after descriptor read") unless
    path_after.file? && !path_after.symlink? &&
      path_after.dev == initial.dev && path_after.ino == initial.ino
  bytes
rescue Errno::ELOOP
  reject("#{label} must be a regular non-symlink file")
rescue SystemCallError
  reject("#{label} could not be read safely")
end

def collect_swift_inputs(repository_root, relative_root, output)
  absolute_root = File.join(repository_root, relative_root)
  validate_directory(absolute_root, "local source directory")
  stack = [[absolute_root, relative_root]]
  until stack.empty?
    absolute_directory, relative_directory = stack.pop
    children = Dir.children(absolute_directory).sort.reverse
    children.each do |name|
      reject("local source path contains a control character") if name.match?(/[\x00-\x1f\x7f]/)
      absolute_path = File.join(absolute_directory, name)
      relative_path = File.join(relative_directory, name)
      metadata = File.lstat(absolute_path)
      if metadata.directory? && !metadata.symlink?
        validate_directory(absolute_path, "local source directory")
        stack << [absolute_path, relative_path]
      elsif metadata.file? && !metadata.symlink?
        reject("local source tree contains a non-Swift file") unless name.end_with?(".swift")
        output << relative_path
      else
        reject("local source tree contains a linked or non-regular entry")
      end
      reject("local source input count exceeds the reviewed boundary") if
        output.length > MAXIMUM_INPUT_FILES
    end
  end
rescue SystemCallError
  reject("local source tree could not be enumerated safely")
end

def run_git(checkout, *arguments)
  environment = {
    "PATH" => "/usr/bin:/bin:/usr/sbin:/sbin",
    "LC_ALL" => "C",
  }
  command = [
    "/usr/bin/git",
    "-c", "core.fsmonitor=false",
    "-c", "core.hooksPath=/dev/null",
    "-C", checkout,
    *arguments,
  ]
  stdout, _stderr, status = Open3.capture3(environment, *command, unsetenv_others: true)
  reject("dependency checkout Git verification failed") unless status.success?
  reject("dependency checkout Git output exceeded its boundary") if
    stdout.bytesize > MAXIMUM_GIT_OUTPUT_BYTES
  stdout
rescue SystemCallError
  reject("trusted system Git is unavailable")
end

arguments = ARGV.dup
usage unless arguments.length == 4 && arguments[0] == "--repository" && arguments[2] == "--scratch"

begin
  repository_root = File.realpath(arguments[1])
  scratch_root = File.realpath(arguments[3])
rescue SystemCallError
  reject("repository or SwiftPM scratch root is unavailable")
end
validate_directory(repository_root, "repository root")
validate_directory(scratch_root, "SwiftPM scratch root")

local_paths = FIXED_INPUTS.dup
LOCAL_SOURCE_ROOTS.each do |relative_root|
  collect_swift_inputs(repository_root, relative_root, local_paths)
end
reject("local build input list contains duplicates") unless local_paths.uniq.length == local_paths.length
local_paths.sort!

local_inputs = local_paths.map do |relative_path|
  absolute_path = File.join(repository_root, relative_path)
  bytes = safely_read(absolute_path, "local build input")
  {
    "path" => relative_path,
    "bytes" => bytes.bytesize,
    "sha256" => Digest::SHA256.hexdigest(bytes),
  }
end

resolved_input = local_inputs.find { |entry| entry.fetch("path") == "Package.resolved" }
resolved_bytes = safely_read(
  File.join(repository_root, "Package.resolved"),
  "Package.resolved",
  maximum_bytes: 1 * 1_024 * 1_024
)
reject("Package.resolved changed during local input collection") unless
  Digest::SHA256.hexdigest(resolved_bytes) == resolved_input.fetch("sha256")

begin
  resolved_document = JSON.parse(resolved_bytes)
rescue JSON::ParserError
  reject("Package.resolved is not valid JSON")
end
reject("Package.resolved schema is unsupported") unless resolved_document["version"] == 3
pins = resolved_document["pins"]
reject("Package.resolved pin set is outside its reviewed boundary") unless
  pins.is_a?(Array) && pins.length.between?(1, MAXIMUM_DEPENDENCIES)

pins_by_identity = {}
pins.each do |pin|
  reject("Package.resolved contains a malformed pin") unless pin.is_a?(Hash)
  identity = pin["identity"]
  state = pin["state"]
  reject("Package.resolved identity is invalid") unless
    identity.is_a?(String) && identity.match?(/\A[a-z0-9._-]{1,128}\z/)
  reject("Package.resolved contains a duplicate identity") if pins_by_identity.key?(identity)
  reject("Package.resolved pin state is invalid") unless state.is_a?(Hash)
  revision = state["revision"]
  version = state["version"]
  reject("Package.resolved revision is invalid") unless
    revision.is_a?(String) && revision.match?(/\A[0-9a-f]{40}\z/)
  reject("Package.resolved version is invalid") unless
    version.is_a?(String) && version.match?(/\A[0-9A-Za-z.+-]{1,64}\z/)
  pins_by_identity[identity] = {"revision" => revision, "version" => version}
end

workspace_state_path = File.join(scratch_root, "workspace-state.json")
workspace_state_bytes = safely_read(
  workspace_state_path,
  "SwiftPM workspace state",
  maximum_bytes: 2 * 1_024 * 1_024
)
begin
  workspace_state = JSON.parse(workspace_state_bytes)
rescue JSON::ParserError
  reject("SwiftPM workspace state is not valid JSON")
end
workspace_dependencies = workspace_state.dig("object", "dependencies")
reject("SwiftPM workspace dependency set is invalid") unless workspace_dependencies.is_a?(Array)

states_by_identity = {}
workspace_dependencies.each do |dependency|
  reject("SwiftPM workspace contains a malformed dependency") unless dependency.is_a?(Hash)
  identity = dependency.dig("packageRef", "identity")
  checkout_state = dependency["state"]
  subpath = dependency["subpath"]
  reject("SwiftPM workspace dependency identity is invalid") unless
    identity.is_a?(String) && identity.match?(/\A[a-z0-9._-]{1,128}\z/)
  reject("SwiftPM workspace contains a duplicate dependency") if states_by_identity.key?(identity)
  reject("SwiftPM checkout subpath is invalid") unless
    subpath.is_a?(String) && subpath.match?(/\A[A-Za-z0-9._-]{1,128}\z/) &&
      subpath != "." && subpath != ".."
  reject("SwiftPM checkout state is invalid") unless
    checkout_state.is_a?(Hash) && checkout_state["name"] == "sourceControlCheckout"
  revision = checkout_state.dig("checkoutState", "revision")
  reject("SwiftPM checkout revision is invalid") unless
    revision.is_a?(String) && revision.match?(/\A[0-9a-f]{40}\z/)
  states_by_identity[identity] = {"revision" => revision, "subpath" => subpath}
end
reject("SwiftPM workspace dependency set does not match Package.resolved") unless
  states_by_identity.keys.sort == pins_by_identity.keys.sort

checkouts_root = File.join(scratch_root, "checkouts")
validate_directory(checkouts_root, "SwiftPM checkouts root")
dependencies = pins_by_identity.keys.sort.map do |identity|
  pin = pins_by_identity.fetch(identity)
  workspace = states_by_identity.fetch(identity)
  reject("SwiftPM checkout revision differs from Package.resolved") unless
    workspace.fetch("revision") == pin.fetch("revision")
  checkout = File.join(checkouts_root, workspace.fetch("subpath"))
  validate_directory(checkout, "SwiftPM dependency checkout")
  reject("SwiftPM dependency checkout escaped the scratch root") unless
    File.realpath(checkout) == checkout && checkout.start_with?(checkouts_root + File::SEPARATOR)

  head = run_git(checkout, "rev-parse", "--verify", "HEAD^{commit}").strip
  reject("dependency checkout HEAD differs from Package.resolved") unless head == pin.fetch("revision")
  status = run_git(checkout, "status", "--porcelain=v1", "--untracked-files=all")
  reject("dependency checkout contains tracked or untracked changes") unless status.empty?
  ignored = run_git(checkout, "ls-files", "--others", "--ignored", "--exclude-standard", "-z")
  reject("dependency checkout contains ignored local files") unless ignored.empty?
  staged = run_git(checkout, "ls-files", "--stage", "-z")
  reject("dependency checkout contains a Git submodule") if
    staged.split("\0", -1).any? { |entry| entry.start_with?("160000 ") }

  {
    "identity" => identity,
    "version" => pin.fetch("version"),
    "revision" => pin.fetch("revision"),
    "checkoutSubpath" => workspace.fetch("subpath"),
  }
end

manifest = {
  "schema" => "dev-island-manus-live-build-inputs-v1",
  "localInputs" => local_inputs,
  "dependencies" => dependencies,
  "totals" => {
    "localInputFiles" => local_inputs.length,
    "localInputBytes" => local_inputs.sum { |entry| entry.fetch("bytes") },
    "dependencyCheckouts" => dependencies.length,
  },
}
STDOUT.write(JSON.pretty_generate(manifest))
STDOUT.write("\n")
