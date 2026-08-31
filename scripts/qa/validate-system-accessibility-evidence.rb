#!/usr/bin/env ruby
# encoding: UTF-8

require "digest"
require "time"

module SystemAccessibilityEvidence
  class ValidationError < StandardError; end

  MAX_TEXT_BYTES = 128 * 1_024
  MAX_IMAGE_BYTES = 8 * 1_024 * 1_024
  MIN_IMAGE_BYTES = 128

  CAPTURE_FILES = %w[
    01-voiceover-approval.jpeg
    01-voiceover-approval-ax.txt
    02-voiceover-after-deny.jpeg
    02-voiceover-after-deny-ax.txt
    03-voiceover-allow-once.jpeg
    03-voiceover-allow-once-ax.txt
    04-voiceover-after-allow-once.jpeg
    04-voiceover-after-allow-once-ax.txt
    05-reduce-motion-on.jpeg
    05-reduce-motion-on-ax.txt
    06-reduce-motion-frame-a.jpeg
    07-reduce-motion-frame-b.jpeg
    REDUCE_MOTION_STATE.txt
  ].freeze

  PACKAGE_FILES = (
    CAPTURE_FILES + %w[
      ACCEPTED
      EVIDENCE_METADATA.txt
      PUBLIC_RECEIPT.txt
      RESTORATION_STATE.txt
      SHA256SUMS
    ]
  ).sort.freeze

  METADATA_KEYS = %w[
    schema
    product_version
    baseline_commit
    worktree_state
    app_bundle_id
    app_version
    debug_app_executable_sha256
    debug_app_executable_bytes
    started_at_utc
    finished_at_utc
    voiceover_observation
    keyboard_interaction_review
    ax_sequence_validation
    reduce_motion_validation
    restoration_validation
    packager_sha256
    validator_sha256
    wrapper_sha256
    result
  ].freeze

  RESTORATION_KEYS = %w[
    schema
    recorded_at_utc
    reduce_motion
    increase_contrast
    reduce_transparency
    voiceover_processes
    debug_app_processes
    production_app_processes
    production_app_executable_sha256
    production_app_executable_bytes
    method
  ].freeze

  RECEIPT_KEYS = %w[
    schema
    product_version
    baseline_commit
    worktree_state
    app_bundle_id
    app_version
    debug_app_executable_sha256
    started_at_utc
    finished_at_utc
    voiceover_observation
    keyboard_interaction_review
    approval_ax_sha256
    after_deny_ax_sha256
    allow_once_ax_sha256
    after_allow_once_ax_sha256
    reduce_motion_ax_sha256
    frame_a_sha256
    frame_b_sha256
    frames_identical
    restoration_state_sha256
    metadata_sha256
    packager_sha256
    validator_sha256
    wrapper_sha256
    scope
    result
  ].freeze

  module_function

  def reject(message)
    raise ValidationError, message
  end

  def stable_stat?(before, after)
    %i[dev ino uid mode nlink size mtime ctime].all? do |field|
      before.public_send(field) == after.public_send(field)
    end
  end

  def validate_regular_metadata(stat, label, minimum_bytes, maximum_bytes)
    reject("#{label} must be a regular non-symlink file") unless stat.file? && !stat.symlink?
    reject("#{label} must be owned by the current user") unless stat.uid == Process.uid
    reject("#{label} must have exactly one hard link") unless stat.nlink == 1
    reject("#{label} must not be group- or world-writable") unless (stat.mode & 0o022).zero?
    reject("#{label} size is outside its reviewed boundary") unless
      stat.size.between?(minimum_bytes, maximum_bytes)
  end

  def read_regular(path, label:, minimum_bytes: 1, maximum_bytes: MAX_TEXT_BYTES)
    path_stat = File.lstat(path)
    validate_regular_metadata(path_stat, label, minimum_bytes, maximum_bytes)

    flags = File::RDONLY | File::NOFOLLOW
    flags |= File::NONBLOCK if File.const_defined?(:NONBLOCK)
    flags |= File::CLOEXEC if File.const_defined?(:CLOEXEC)
    bytes = nil
    opened_stat = nil
    post_read_stat = nil
    File.open(path, flags) do |file|
      opened_stat = file.stat
      validate_regular_metadata(opened_stat, label, minimum_bytes, maximum_bytes)
      reject("#{label} path changed before descriptor anchoring") unless
        path_stat.dev == opened_stat.dev && path_stat.ino == opened_stat.ino
      bytes = file.pread(opened_stat.size, 0)
      post_read_stat = file.stat
    end

    reject("#{label} read was incomplete") unless bytes.bytesize == opened_stat.size
    reject("#{label} changed while it was read") unless stable_stat?(opened_stat, post_read_stat)
    final_stat = File.lstat(path)
    reject("#{label} path changed after descriptor read") unless
      final_stat.file? && !final_stat.symlink? &&
        final_stat.dev == opened_stat.dev && final_stat.ino == opened_stat.ino
    [bytes, opened_stat]
  rescue Errno::ENOENT
    reject("#{label} is unavailable")
  rescue Errno::ELOOP
    reject("#{label} must not be a symbolic link")
  rescue SystemCallError
    reject("#{label} could not be read through a no-follow descriptor")
  end

  def parse_text(bytes, label)
    text = bytes.dup.force_encoding(Encoding::UTF_8)
    reject("#{label} must be valid UTF-8") unless text.valid_encoding?
    reject("#{label} must use LF line endings") if text.include?("\r")
    reject("#{label} must end with exactly one LF") unless text.end_with?("\n")
    reject("#{label} must not contain NUL bytes") if text.include?("\0")
    text
  end

  def parse_key_value(text, keys, label)
    lines = text.lines(chomp: true)
    reject("#{label} field count is invalid") unless lines.length == keys.length
    values = {}
    lines.each_with_index do |line, index|
      key, value = line.split("=", 2)
      reject("#{label} field order is invalid") unless key == keys[index]
      reject("#{label} contains an empty value") if value.nil? || value.empty?
      reject("#{label} contains a duplicate field") if values.key?(key)
      values[key] = value
    end
    values
  end

  def sha256(bytes)
    Digest::SHA256.hexdigest(bytes)
  end

  def validate_sha256(value, label)
    reject("#{label} must be a lowercase SHA-256 digest") unless value.match?(/\A[0-9a-f]{64}\z/)
  end

  def validate_integer(value, label, minimum, maximum)
    reject("#{label} must be a canonical integer") unless value.match?(/\A(?:0|[1-9][0-9]*)\z/)
    integer = Integer(value, 10)
    reject("#{label} is outside its reviewed boundary") unless integer.between?(minimum, maximum)
    integer
  end

  def parse_utc(value, label)
    reject("#{label} must use canonical UTC seconds") unless
      value.match?(/\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\z/)
    Time.iso8601(value)
  rescue ArgumentError
    reject("#{label} is not a valid timestamp")
  end

  def validate_metadata(values)
    reject("evidence metadata schema is invalid") unless
      values["schema"] == "dev-island-system-accessibility-evidence-v1"
    reject("product version is invalid") unless
      values["product_version"].match?(/\A(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\z/)
    reject("baseline commit is invalid") unless values["baseline_commit"].match?(/\A[0-9a-f]{40}\z/)
    reject("worktree state is invalid") unless %w[clean dirty].include?(values["worktree_state"])
    reject("App bundle identifier is invalid") unless values["app_bundle_id"] == "app.devisland.Island"
    reject("App version differs from the product version") unless
      values["app_version"] == values["product_version"]
    validate_sha256(values["debug_app_executable_sha256"], "debug_app_executable_sha256")
    validate_integer(
      values["debug_app_executable_bytes"],
      "debug_app_executable_bytes",
      1,
      512 * 1_024 * 1_024
    )
    started_at = parse_utc(values["started_at_utc"], "started_at_utc")
    finished_at = parse_utc(values["finished_at_utc"], "finished_at_utc")
    reject("evidence timestamps are out of order") unless started_at < finished_at
    reject("VoiceOver observation was not explicitly reviewed") unless
      values["voiceover_observation"] == "real_process_operator_observed"
    reject("keyboard sequence was not explicitly reviewed") unless
      values["keyboard_interaction_review"] == "command_d_then_command_return_operator_observed"
    %w[ax_sequence_validation reduce_motion_validation restoration_validation].each do |key|
      reject("#{key} did not pass") unless values[key] == "passed"
    end
    %w[packager_sha256 validator_sha256 wrapper_sha256].each do |key|
      validate_sha256(values[key], key)
    end
    reject("evidence result is not accepted") unless values["result"] == "accepted"
    values
  end

  def validate_restoration(values)
    reject("restoration schema is invalid") unless
      values["schema"] == "dev-island-system-restoration-v1"
    parse_utc(values["recorded_at_utc"], "restoration recorded_at_utc")
    %w[reduce_motion increase_contrast reduce_transparency].each do |key|
      reject("#{key} was not restored") unless values[key] == "off"
    end
    %w[voiceover_processes debug_app_processes].each do |key|
      reject("#{key} remained active") unless values[key] == "0"
    end
    reject("latest Production App was not the sole running Dev Island process") unless
      values["production_app_processes"] == "1"
    validate_sha256(values["production_app_executable_sha256"], "production_app_executable_sha256")
    validate_integer(
      values["production_app_executable_bytes"],
      "production_app_executable_bytes",
      1,
      512 * 1_024 * 1_024
    )
    reject("restoration method is invalid") unless
      values["method"] == "macos_system_settings_and_process_inspection"
    values
  end

  def validate_receipt_values(values, expected_product_version: nil)
    reject("public receipt schema is invalid") unless
      values["schema"] == "dev-island-system-accessibility-public-receipt-v1"
    reject("public receipt product version is invalid") unless
      values["product_version"].match?(/\A(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\z/)
    if expected_product_version
      reject("public receipt version differs from VERSION") unless
        values["product_version"] == expected_product_version
    end
    reject("public receipt baseline commit is invalid") unless
      values["baseline_commit"].match?(/\A[0-9a-f]{40}\z/)
    reject("public receipt worktree state is invalid") unless
      %w[clean dirty].include?(values["worktree_state"])
    reject("public receipt bundle identifier is invalid") unless
      values["app_bundle_id"] == "app.devisland.Island"
    reject("public receipt App version differs from product version") unless
      values["app_version"] == values["product_version"]
    parse_utc(values["started_at_utc"], "receipt started_at_utc")
    parse_utc(values["finished_at_utc"], "receipt finished_at_utc")
    reject("public receipt VoiceOver scope is overstated") unless
      values["voiceover_observation"] == "real_process_operator_observed"
    reject("public receipt keyboard scope is overstated") unless
      values["keyboard_interaction_review"] == "command_d_then_command_return_operator_observed"
    %w[
      debug_app_executable_sha256
      approval_ax_sha256
      after_deny_ax_sha256
      allow_once_ax_sha256
      after_allow_once_ax_sha256
      reduce_motion_ax_sha256
      frame_a_sha256
      frame_b_sha256
      restoration_state_sha256
      metadata_sha256
      packager_sha256
      validator_sha256
      wrapper_sha256
    ].each { |key| validate_sha256(values[key], key) }
    reject("Reduce Motion frames were not byte-identical") unless values["frames_identical"] == "true"
    reject("public receipt scope is invalid") unless
      values["scope"] == "ax_order_keyboard_transitions_reduce_motion_and_restoration"
    reject("public receipt result is not accepted") unless values["result"] == "accepted"
    values
  end

  def require_in_order(text, tokens, label)
    offset = 0
    tokens.each do |token|
      index = text.index(token, offset)
      reject("#{label} is missing or reorders #{token.inspect}") unless index
      offset = index + token.length
    end
  end

  def validate_ax_capture(name, text)
    common = [
      'Window: "Dev Island", App: Dev Island.',
      "Description: Agent 连接",
      "本地 Agent：已就绪，Manus：未连接",
      "按钮 Description: 连接 Agent",
      "按钮 Description: 打开 Dev Island 设置",
      "滚动区",
      "列表"
    ]
    require_in_order(text, common, name)

    case name
    when "01-voiceover-approval-ax.txt", "03-voiceover-allow-once-ax.txt"
      require_in_order(
        text,
        ["1 个等待中", "container Codex · 会话 ", "待批准：", "Approve Bash", "按钮 Description: 拒绝", "按钮 Description: 仅允许一次"],
        name
      )
    when "02-voiceover-after-deny-ax.txt", "04-voiceover-after-allow-once-ax.txt"
      reject("#{name} did not return to Working") unless text.include?("工作中")
      reject("#{name} retained a pending action") if
        text.include?("按钮 Description: 拒绝") || text.include?("按钮 Description: 仅允许一次")
    when "05-reduce-motion-on-ax.txt"
      reject("Reduce Motion capture did not preserve the Working panel") unless text.include?("工作中")
      reject("Reduce Motion capture retained a pending action") if text.include?("按钮 Description: 仅允许一次")
    else
      reject("unexpected AX capture name")
    end
  end

  def validate_jpeg(bytes, label)
    reject("#{label} is not a complete JPEG") unless
      bytes.start_with?("\xFF\xD8\xFF".b) && bytes.end_with?("\xFF\xD9".b)
  end

  def validate_checksum_manifest(text, artifacts)
    expected_names = (PACKAGE_FILES - ["SHA256SUMS"]).sort
    lines = text.lines(chomp: true)
    reject("checksum manifest file count is invalid") unless lines.length == expected_names.length
    lines.each_with_index do |line, index|
      digest, name = line.split("  ", 2)
      reject("checksum manifest order is invalid") unless name == expected_names[index]
      validate_sha256(digest.to_s, "checksum for #{name}")
      reject("checksum mismatch for #{name}") unless digest == sha256(artifacts.fetch(name))
    end
  end

  def validate_package(path, expected_product_version: nil, require_accepted: false)
    directory_stat = File.lstat(path)
    reject("evidence package must be a private regular directory") unless
      directory_stat.directory? && !directory_stat.symlink? &&
        directory_stat.uid == Process.uid && (directory_stat.mode & 0o077).zero?
    names = Dir.children(path).sort
    reject("evidence package file set is invalid") unless names == PACKAGE_FILES

    artifacts = {}
    PACKAGE_FILES.each do |name|
      image = name.end_with?(".jpeg")
      bytes, = read_regular(
        File.join(path, name),
        label: name,
        minimum_bytes: image ? MIN_IMAGE_BYTES : 1,
        maximum_bytes: image ? MAX_IMAGE_BYTES : MAX_TEXT_BYTES
      )
      validate_jpeg(bytes, name) if image
      artifacts[name] = bytes
    end

    metadata = validate_metadata(
      parse_key_value(
        parse_text(artifacts.fetch("EVIDENCE_METADATA.txt"), "evidence metadata"),
        METADATA_KEYS,
        "evidence metadata"
      )
    )
    if expected_product_version
      reject("evidence metadata version differs from VERSION") unless
        metadata["product_version"] == expected_product_version
    end

    restoration = validate_restoration(
      parse_key_value(
        parse_text(artifacts.fetch("RESTORATION_STATE.txt"), "restoration state"),
        RESTORATION_KEYS,
        "restoration state"
      )
    )

    receipt = validate_receipt_values(
      parse_key_value(
        parse_text(artifacts.fetch("PUBLIC_RECEIPT.txt"), "public receipt"),
        RECEIPT_KEYS,
        "public receipt"
      ),
      expected_product_version: expected_product_version
    )

    reject("receipt and metadata disagree") unless
      %w[
        product_version baseline_commit worktree_state app_bundle_id app_version
        debug_app_executable_sha256 started_at_utc finished_at_utc voiceover_observation
        keyboard_interaction_review packager_sha256 validator_sha256 wrapper_sha256 result
      ].all? { |key| receipt[key] == metadata[key] }
    reject("receipt metadata hash is invalid") unless
      receipt["metadata_sha256"] == sha256(artifacts.fetch("EVIDENCE_METADATA.txt"))
    reject("receipt restoration hash is invalid") unless
      receipt["restoration_state_sha256"] == sha256(artifacts.fetch("RESTORATION_STATE.txt"))

    ax_receipt_keys = {
      "01-voiceover-approval-ax.txt" => "approval_ax_sha256",
      "02-voiceover-after-deny-ax.txt" => "after_deny_ax_sha256",
      "03-voiceover-allow-once-ax.txt" => "allow_once_ax_sha256",
      "04-voiceover-after-allow-once-ax.txt" => "after_allow_once_ax_sha256",
      "05-reduce-motion-on-ax.txt" => "reduce_motion_ax_sha256"
    }
    ax_receipt_keys.each do |name, key|
      text = parse_text(artifacts.fetch(name), name)
      validate_ax_capture(name, text)
      reject("receipt hash differs for #{name}") unless receipt[key] == sha256(artifacts.fetch(name))
    end

    reduce_state = parse_text(artifacts.fetch("REDUCE_MOTION_STATE.txt"), "Reduce Motion state")
    reject("Reduce Motion state is invalid") unless
      reduce_state == "reduce_motion=on\noriginal_reduce_motion=off\n"
    frame_a = artifacts.fetch("06-reduce-motion-frame-a.jpeg")
    frame_b = artifacts.fetch("07-reduce-motion-frame-b.jpeg")
    reject("Reduce Motion frames differ") unless frame_a == frame_b
    reject("receipt frame A hash differs") unless receipt["frame_a_sha256"] == sha256(frame_a)
    reject("receipt frame B hash differs") unless receipt["frame_b_sha256"] == sha256(frame_b)

    validate_checksum_manifest(
      parse_text(artifacts.fetch("SHA256SUMS"), "checksum manifest"),
      artifacts
    )
    accepted = parse_text(artifacts.fetch("ACCEPTED"), "accepted marker")
    if require_accepted
      reject("accepted marker is invalid") unless
        accepted == "dev-island-system-accessibility-evidence-v1\n"
    end
    { metadata: metadata, restoration: restoration, receipt: receipt }
  rescue Errno::ENOENT
    reject("evidence package is unavailable")
  rescue Errno::ELOOP
    reject("evidence package must not be a symbolic link")
  rescue SystemCallError
    reject("evidence package could not be inspected safely")
  end

  def validate_receipt(path, expected_product_version: nil)
    bytes, = read_regular(path, label: "public receipt")
    values = parse_key_value(parse_text(bytes, "public receipt"), RECEIPT_KEYS, "public receipt")
    validate_receipt_values(values, expected_product_version: expected_product_version)
  end
end

if __FILE__ == $PROGRAM_NAME
  mode = ARGV.shift
  begin
    case mode
    when "--evidence"
      path = ARGV.shift
      require_accepted = false
      expected_product_version = nil
      until ARGV.empty?
        case ARGV.shift
        when "--require-accepted"
          require_accepted = true
        when "--product-version"
          expected_product_version = ARGV.shift
        else
          raise SystemAccessibilityEvidence::ValidationError, "unknown argument"
        end
      end
      raise SystemAccessibilityEvidence::ValidationError, "missing evidence path" unless path
      SystemAccessibilityEvidence.validate_package(
        path,
        expected_product_version: expected_product_version,
        require_accepted: require_accepted
      )
      puts "System accessibility evidence: ACCEPTED"
    when "--receipt"
      path = ARGV.shift
      expected_product_version = nil
      if ARGV.shift == "--product-version"
        expected_product_version = ARGV.shift
      end
      raise SystemAccessibilityEvidence::ValidationError, "invalid receipt arguments" unless path && ARGV.empty?
      SystemAccessibilityEvidence.validate_receipt(path, expected_product_version: expected_product_version)
      puts "System accessibility receipt: ACCEPTED"
    else
      warn "Usage: validate-system-accessibility-evidence.rb --evidence DIR [--require-accepted] [--product-version VERSION]"
      warn "       validate-system-accessibility-evidence.rb --receipt FILE [--product-version VERSION]"
      exit 64
    end
  rescue SystemAccessibilityEvidence::ValidationError => error
    warn "error: #{error.message}"
    exit 1
  end
end
