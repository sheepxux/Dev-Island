#!/usr/bin/env ruby

require "digest"
require "open3"
require "optparse"
require "pathname"
require_relative "validate-system-accessibility-evidence"

module SystemAccessibilityEvidencePackager
  class PackagingError < StandardError; end

  SOURCE_FILE_MAP = {
    "01-voiceover-approval.jpeg" => "01-voiceover-approval.png",
    "01-voiceover-approval-ax.txt" => "01-voiceover-approval-ax.txt",
    "02-voiceover-after-deny.jpeg" => "02-voiceover-after-deny.png",
    "02-voiceover-after-deny-ax.txt" => "02-voiceover-after-deny-ax.txt",
    "03-voiceover-allow-once.jpeg" => "03-voiceover-allow-once.png",
    "03-voiceover-allow-once-ax.txt" => "03-voiceover-allow-once-ax.txt",
    "04-voiceover-after-allow-once.jpeg" => "04-voiceover-after-allow-once.png",
    "04-voiceover-after-allow-once-ax.txt" => "04-voiceover-after-allow-once-ax.txt",
    "05-reduce-motion-on.jpeg" => "05-reduce-motion-on.png",
    "05-reduce-motion-on-ax.txt" => "05-reduce-motion-on-ax.txt",
    "06-reduce-motion-frame-a.jpeg" => "06-reduce-motion-frame-a.png",
    "07-reduce-motion-frame-b.jpeg" => "07-reduce-motion-frame-b.png",
    "REDUCE_MOTION_STATE.txt" => "05-reduce-motion-system-state.txt"
  }.freeze

  module_function

  def fail!(message)
    raise PackagingError, message
  end

  def read_text(path, label:, maximum_bytes: SystemAccessibilityEvidence::MAX_TEXT_BYTES)
    bytes, = SystemAccessibilityEvidence.read_regular(
      path,
      label: label,
      maximum_bytes: maximum_bytes
    )
    [bytes, SystemAccessibilityEvidence.parse_text(bytes, label)]
  end

  def run(*arguments, env: { "LC_ALL" => "C" })
    stdout, stderr, status = Open3.capture3(env, *arguments, unsetenv_others: true)
    fail!("reviewed command failed") unless status.success? && stderr.empty?
    stdout
  end

  def plist_value(info_plist, key)
    value = run("/usr/bin/plutil", "-extract", key, "raw", "-o", "-", info_plist).strip
    fail!("App plist field is invalid") if value.empty? || value.bytesize > 256
    value
  end

  def validate_bundle(app_path, product_version)
    app_stat = File.lstat(app_path)
    fail!("debug App must be a real directory") unless
      app_stat.directory? && !app_stat.symlink? && app_stat.uid == Process.uid
    fail!("debug App directory permissions are unsafe") unless (app_stat.mode & 0o022).zero?
    fail!("debug App path must not traverse a symbolic link") unless
      File.realpath(app_path) == File.expand_path(app_path)

    info_plist = File.join(app_path, "Contents", "Info.plist")
    bundle_id = plist_value(info_plist, "CFBundleIdentifier")
    version = plist_value(info_plist, "CFBundleShortVersionString")
    executable_name = plist_value(info_plist, "CFBundleExecutable")
    fail!("debug App bundle identifier is invalid") unless bundle_id == "app.devisland.Island"
    fail!("debug App version differs from VERSION") unless version == product_version
    fail!("debug App executable name is invalid") unless
      executable_name.match?(/\A[A-Za-z0-9._-]+\z/)
    executable_path = File.join(app_path, "Contents", "MacOS", executable_name)
    executable, executable_stat = SystemAccessibilityEvidence.read_regular(
      executable_path,
      label: "debug App executable",
      maximum_bytes: 512 * 1_024 * 1_024
    )
    [bundle_id, version, executable, executable_stat]
  rescue Errno::ENOENT, Errno::ELOOP, SystemCallError
    fail!("debug App could not be inspected safely")
  end

  def validate_repository(repository)
    repository_stat = File.lstat(repository)
    fail!("repository must be a real directory") unless
      repository_stat.directory? && !repository_stat.symlink? && repository_stat.uid == Process.uid
    version_bytes, version_text = read_text(File.join(repository, "VERSION"), label: "VERSION", maximum_bytes: 64)
    product_version = version_text.strip
    fail!("VERSION is invalid") unless
      product_version.match?(/\A(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\z/)
    fail!("VERSION contains unexpected bytes") unless version_bytes == "#{product_version}\n"
    baseline_commit = run("/usr/bin/git", "-C", repository, "rev-parse", "HEAD").strip
    fail!("baseline commit is invalid") unless baseline_commit.match?(/\A[0-9a-f]{40}\z/)
    status = run("/usr/bin/git", "-C", repository, "status", "--porcelain=v1")
    worktree_state = status.empty? ? "clean" : "dirty"
    [product_version, baseline_commit, worktree_state]
  rescue Errno::ENOENT, Errno::ELOOP, SystemCallError
    fail!("repository could not be inspected safely")
  end

  def validate_output_directory(path)
    stat = File.lstat(path)
    fail!("output must be a private regular directory") unless
      stat.directory? && !stat.symlink? && stat.uid == Process.uid && (stat.mode & 0o077).zero?
    fail!("output directory must be empty") unless Dir.children(path).empty?
  rescue Errno::ENOENT
    fail!("output directory must already exist")
  rescue SystemCallError
    fail!("output directory could not be inspected safely")
  end

  def write_new(path, bytes)
    flags = File::WRONLY | File::CREAT | File::EXCL
    flags |= File::CLOEXEC if File.const_defined?(:CLOEXEC)
    File.open(path, flags, 0o400) do |file|
      written = file.write(bytes)
      fail!("evidence artifact write was incomplete") unless written == bytes.bytesize
      file.flush
      file.fsync
    end
    File.chmod(0o400, path)
  rescue Errno::EEXIST
    fail!("evidence artifact already exists")
  rescue SystemCallError
    fail!("evidence artifact could not be written safely")
  end

  def key_value(keys, values)
    keys.map do |key|
      value = values.fetch(key)
      fail!("evidence value contains an unsafe line break") if value.include?("\n") || value.include?("\r")
      "#{key}=#{value}"
    end.join("\n") + "\n"
  end

  def package(options)
    required = %i[
      repository capture_dir debug_app restoration_state output started_at finished_at
      voiceover_observation keyboard_sequence
    ]
    missing = required.select { |key| options[key].nil? || options[key].empty? }
    fail!("missing required arguments") unless missing.empty?
    fail!("VoiceOver observation confirmation is invalid") unless
      options[:voiceover_observation] == "real_process_operator_observed"
    fail!("keyboard sequence confirmation is invalid") unless
      options[:keyboard_sequence] == "command_d_then_command_return_operator_observed"

    started_at = SystemAccessibilityEvidence.parse_utc(options[:started_at], "started_at")
    finished_at = SystemAccessibilityEvidence.parse_utc(options[:finished_at], "finished_at")
    fail!("capture timestamps are out of order") unless started_at < finished_at
    validate_output_directory(options[:output])

    product_version, baseline_commit, worktree_state = validate_repository(options[:repository])
    bundle_id, app_version, executable, executable_stat = validate_bundle(
      options[:debug_app],
      product_version
    )

    captured = {}
    SOURCE_FILE_MAP.each do |package_name, source_name|
      source_path = File.join(options[:capture_dir], source_name)
      image = package_name.end_with?(".jpeg")
      bytes, = SystemAccessibilityEvidence.read_regular(
        source_path,
        label: source_name,
        minimum_bytes: image ? SystemAccessibilityEvidence::MIN_IMAGE_BYTES : 1,
        maximum_bytes: image ? SystemAccessibilityEvidence::MAX_IMAGE_BYTES : SystemAccessibilityEvidence::MAX_TEXT_BYTES
      )
      SystemAccessibilityEvidence.validate_jpeg(bytes, source_name) if image
      captured[package_name] = bytes
    end

    SOURCE_FILE_MAP.keys.grep(/-ax\.txt\z/).each do |name|
      SystemAccessibilityEvidence.validate_ax_capture(
        name,
        SystemAccessibilityEvidence.parse_text(captured.fetch(name), name)
      )
    end
    reduce_state = SystemAccessibilityEvidence.parse_text(
      captured.fetch("REDUCE_MOTION_STATE.txt"),
      "Reduce Motion state"
    )
    fail!("Reduce Motion source state is invalid") unless
      reduce_state == "reduce_motion=on\noriginal_reduce_motion=off\n"
    fail!("Reduce Motion frames are not byte-identical") unless
      captured.fetch("06-reduce-motion-frame-a.jpeg") == captured.fetch("07-reduce-motion-frame-b.jpeg")

    restoration_bytes, restoration_text = read_text(
      options[:restoration_state],
      label: "restoration state"
    )
    restoration_values = SystemAccessibilityEvidence.parse_key_value(
      restoration_text,
      SystemAccessibilityEvidence::RESTORATION_KEYS,
      "restoration state"
    )
    SystemAccessibilityEvidence.validate_restoration(restoration_values)

    repository_root = File.expand_path(options[:repository])
    script_paths = {
      "packager_sha256" => File.join(repository_root, "scripts/qa/package-system-accessibility-evidence.rb"),
      "validator_sha256" => File.join(repository_root, "scripts/qa/validate-system-accessibility-evidence.rb"),
      "wrapper_sha256" => File.join(repository_root, "scripts/qa/run-system-accessibility-evidence.sh")
    }
    script_hashes = script_paths.transform_values do |path|
      bytes, = SystemAccessibilityEvidence.read_regular(path, label: File.basename(path))
      SystemAccessibilityEvidence.sha256(bytes)
    end

    metadata_values = {
      "schema" => "dev-island-system-accessibility-evidence-v1",
      "product_version" => product_version,
      "baseline_commit" => baseline_commit,
      "worktree_state" => worktree_state,
      "app_bundle_id" => bundle_id,
      "app_version" => app_version,
      "debug_app_executable_sha256" => SystemAccessibilityEvidence.sha256(executable),
      "debug_app_executable_bytes" => executable_stat.size.to_s,
      "started_at_utc" => options[:started_at],
      "finished_at_utc" => options[:finished_at],
      "voiceover_observation" => options[:voiceover_observation],
      "keyboard_interaction_review" => options[:keyboard_sequence],
      "ax_sequence_validation" => "passed",
      "reduce_motion_validation" => "passed",
      "restoration_validation" => "passed",
      "packager_sha256" => script_hashes.fetch("packager_sha256"),
      "validator_sha256" => script_hashes.fetch("validator_sha256"),
      "wrapper_sha256" => script_hashes.fetch("wrapper_sha256"),
      "result" => "accepted"
    }
    metadata = key_value(SystemAccessibilityEvidence::METADATA_KEYS, metadata_values)

    receipt_values = {
      "schema" => "dev-island-system-accessibility-public-receipt-v1",
      "product_version" => product_version,
      "baseline_commit" => baseline_commit,
      "worktree_state" => worktree_state,
      "app_bundle_id" => bundle_id,
      "app_version" => app_version,
      "debug_app_executable_sha256" => SystemAccessibilityEvidence.sha256(executable),
      "started_at_utc" => options[:started_at],
      "finished_at_utc" => options[:finished_at],
      "voiceover_observation" => options[:voiceover_observation],
      "keyboard_interaction_review" => options[:keyboard_sequence],
      "approval_ax_sha256" => SystemAccessibilityEvidence.sha256(captured.fetch("01-voiceover-approval-ax.txt")),
      "after_deny_ax_sha256" => SystemAccessibilityEvidence.sha256(captured.fetch("02-voiceover-after-deny-ax.txt")),
      "allow_once_ax_sha256" => SystemAccessibilityEvidence.sha256(captured.fetch("03-voiceover-allow-once-ax.txt")),
      "after_allow_once_ax_sha256" => SystemAccessibilityEvidence.sha256(captured.fetch("04-voiceover-after-allow-once-ax.txt")),
      "reduce_motion_ax_sha256" => SystemAccessibilityEvidence.sha256(captured.fetch("05-reduce-motion-on-ax.txt")),
      "frame_a_sha256" => SystemAccessibilityEvidence.sha256(captured.fetch("06-reduce-motion-frame-a.jpeg")),
      "frame_b_sha256" => SystemAccessibilityEvidence.sha256(captured.fetch("07-reduce-motion-frame-b.jpeg")),
      "frames_identical" => "true",
      "restoration_state_sha256" => SystemAccessibilityEvidence.sha256(restoration_bytes),
      "metadata_sha256" => SystemAccessibilityEvidence.sha256(metadata),
      "packager_sha256" => script_hashes.fetch("packager_sha256"),
      "validator_sha256" => script_hashes.fetch("validator_sha256"),
      "wrapper_sha256" => script_hashes.fetch("wrapper_sha256"),
      "scope" => "ax_order_keyboard_transitions_reduce_motion_and_restoration",
      "result" => "accepted"
    }
    receipt = key_value(SystemAccessibilityEvidence::RECEIPT_KEYS, receipt_values)

    artifacts = captured.merge(
      "RESTORATION_STATE.txt" => restoration_bytes,
      "EVIDENCE_METADATA.txt" => metadata,
      "PUBLIC_RECEIPT.txt" => receipt,
      "ACCEPTED" => "dev-island-system-accessibility-evidence-v1\n"
    )
    artifacts.each do |name, bytes|
      write_new(File.join(options[:output], name), bytes)
    end
    checksum_manifest = artifacts.keys.sort.map do |name|
      "#{SystemAccessibilityEvidence.sha256(artifacts.fetch(name))}  #{name}"
    end.join("\n") + "\n"
    write_new(File.join(options[:output], "SHA256SUMS"), checksum_manifest)

    SystemAccessibilityEvidence.validate_package(
      options[:output],
      expected_product_version: product_version,
      require_accepted: true
    )
    puts File.join(options[:output], "PUBLIC_RECEIPT.txt")
  rescue SystemAccessibilityEvidence::ValidationError => error
    File.unlink(File.join(options[:output], "ACCEPTED")) rescue nil if options[:output]
    fail!(error.message)
  end
end

options = {}
parser = OptionParser.new do |arguments|
  arguments.banner = "Usage: package-system-accessibility-evidence.rb [options]"
  arguments.on("--repository PATH") { |value| options[:repository] = value }
  arguments.on("--capture-dir PATH") { |value| options[:capture_dir] = value }
  arguments.on("--debug-app PATH") { |value| options[:debug_app] = value }
  arguments.on("--restoration-state PATH") { |value| options[:restoration_state] = value }
  arguments.on("--output PATH") { |value| options[:output] = value }
  arguments.on("--started-at UTC") { |value| options[:started_at] = value }
  arguments.on("--finished-at UTC") { |value| options[:finished_at] = value }
  arguments.on("--confirm-voiceover-observation VALUE") { |value| options[:voiceover_observation] = value }
  arguments.on("--confirm-keyboard-sequence VALUE") { |value| options[:keyboard_sequence] = value }
end

begin
  parser.parse!
  raise SystemAccessibilityEvidencePackager::PackagingError, "unexpected positional arguments" unless ARGV.empty?
  SystemAccessibilityEvidencePackager.package(options)
rescue OptionParser::ParseError, SystemAccessibilityEvidencePackager::PackagingError => error
  warn "error: #{error.message}"
  exit 1
end
