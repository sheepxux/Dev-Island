#!/usr/bin/env ruby

require "digest"
require "time"
require_relative "validate-codex-live-approval-evidence"

module CodexLiveDecisionEvidence
  extend self

  MAX_TEXT_BYTES = CodexLiveApprovalEvidence::MAX_TEXT_BYTES
  MAX_IMAGE_BYTES = CodexLiveApprovalEvidence::MAX_IMAGE_BYTES
  MIN_IMAGE_BYTES = CodexLiveApprovalEvidence::MIN_IMAGE_BYTES

  PACKAGE_FILES = %w[
    01-live-codex-deny.jpeg
    02-live-codex-running.jpeg
    ACCEPTED
    EVIDENCE_METADATA.txt
    PROOF_ABSENCE.txt
    PUBLIC_RECEIPT.txt
    SHA256SUMS
    TASK_RECORD.txt
    transcript.txt
  ].freeze

  METADATA_KEYS = %w[
    schema
    classification
    started_at_utc
    finished_at_utc
    product_version
    baseline_commit
    worktree_state
    session_id
    session_source_sha256
    session_source_bytes
    history_database_sha256
    decision_packager_sha256
    decision_validator_sha256
    foundation_packager_sha256
    foundation_validator_sha256
    wrapper_sha256
    permission_wait_seconds
    app_bundle_id
    app_version
    app_executable_sha256
    app_executable_bytes
    codex_cli_version
    codex_cli_sha256
    codex_cli_bytes
    proof_path_sha256
    proof_absence_checked_at_utc
    deny_screenshot_sha256
    deny_screenshot_bytes
    running_screenshot_sha256
    running_screenshot_bytes
    visual_review
    proof_absence_validation
    session_validation
    history_record_validation
    wrapper_result
  ].freeze

  TASK_RECORD_KEYS = %w[
    schema
    source
    session_id
    status
    created_at_utc
    updated_at_utc
  ].freeze

  ABSENCE_KEYS = %w[
    schema
    proof_path_sha256
    checked_at_utc
    result
  ].freeze

  RECEIPT_KEYS = %w[
    schema
    classification
    product_version
    baseline_commit
    worktree_state
    session_id
    started_at_utc
    finished_at_utc
    permission_wait_seconds
    app_bundle_id
    app_version
    app_executable_sha256
    codex_cli_version
    codex_cli_sha256
    session_source_sha256
    history_database_sha256
    decision_packager_sha256
    decision_validator_sha256
    foundation_packager_sha256
    foundation_validator_sha256
    wrapper_sha256
    transcript_sha256
    task_record_sha256
    proof_absence_sha256
    proof_path_sha256
    deny_screenshot_sha256
    running_screenshot_sha256
    visual_review
    result
  ].freeze

  TRANSCRIPT_LINES = [
    "[CODEX] Dev Island live decision round trip",
    "[CODEX] checkpoint=session_started",
    "[CODEX] checkpoint=permission_requested",
    "[DEV_ISLAND] checkpoint=waiting_visual_reviewed",
    "[DEV_ISLAND] checkpoint=deny_visual_reviewed",
    "[CODEX] checkpoint=permission_denied",
    "[DEV_ISLAND] checkpoint=running_visual_reviewed",
    "[CODEX] checkpoint=proof_absence_verified",
    "[CODEX] checkpoint=session_completed",
    "[CODEX] classification=explicit_island_deny",
    "[CODEX] result=accepted",
  ].freeze

  def reject(message)
    CodexLiveApprovalEvidence.reject(message)
  end

  def read_regular(path, label:, minimum_bytes: 1, maximum_bytes: MAX_TEXT_BYTES)
    CodexLiveApprovalEvidence.read_regular(
      path,
      label: label,
      minimum_bytes: minimum_bytes,
      maximum_bytes: maximum_bytes
    )
  end

  def parse_text(bytes, label)
    CodexLiveApprovalEvidence.parse_text(bytes, label)
  end

  def parse_key_value(text, keys, label)
    CodexLiveApprovalEvidence.parse_key_value(text, keys, label)
  end

  def sha256(bytes)
    Digest::SHA256.hexdigest(bytes)
  end

  def validate_sha256(value, label)
    CodexLiveApprovalEvidence.validate_sha256(value, label)
  end

  def validate_integer(value, label, minimum, maximum)
    CodexLiveApprovalEvidence.validate_integer(value, label, minimum, maximum)
  end

  def parse_utc(value, label)
    CodexLiveApprovalEvidence.parse_utc(value, label)
  end

  def validate_jpeg(bytes, label)
    CodexLiveApprovalEvidence.validate_jpeg(bytes, label)
  end

  def validate_metadata(values)
    reject("decision evidence metadata schema is invalid") unless
      values["schema"] == "dev-island-codex-live-decision-evidence-v1"
    reject("accepted evidence is not an explicit island denial") unless
      values["classification"] == "explicit_island_deny"
    reject("product version is invalid") unless
      values["product_version"].match?(/\A(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\z/)
    reject("baseline commit is invalid") unless values["baseline_commit"].match?(/\A[0-9a-f]{40}\z/)
    reject("worktree state is invalid") unless %w[clean dirty].include?(values["worktree_state"])
    reject("session ID is invalid") unless
      values["session_id"].match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)

    started_at = parse_utc(values["started_at_utc"], "started_at_utc")
    finished_at = parse_utc(values["finished_at_utc"], "finished_at_utc")
    absence_at = parse_utc(values["proof_absence_checked_at_utc"], "proof_absence_checked_at_utc")
    reject("evidence timestamps are out of order") unless started_at < finished_at
    reject("proof absence check predates the completed session") unless absence_at >= finished_at
    reject("proof absence check is too remote from the reviewed session") unless
      absence_at <= finished_at + (7 * 24 * 60 * 60)

    %w[
      session_source_sha256
      history_database_sha256
      decision_packager_sha256
      decision_validator_sha256
      foundation_packager_sha256
      foundation_validator_sha256
      wrapper_sha256
      app_executable_sha256
      codex_cli_sha256
      proof_path_sha256
      deny_screenshot_sha256
      running_screenshot_sha256
    ].each { |key| validate_sha256(values[key], key) }

    validate_integer(values["session_source_bytes"], "session_source_bytes", 1, 16 * 1_024 * 1_024)
    validate_integer(values["permission_wait_seconds"], "permission_wait_seconds", 1, 89)
    validate_integer(values["app_executable_bytes"], "app_executable_bytes", 1, 512 * 1_024 * 1_024)
    validate_integer(values["codex_cli_bytes"], "codex_cli_bytes", 1, 512 * 1_024 * 1_024)
    %w[deny running].each do |kind|
      validate_integer(
        values["#{kind}_screenshot_bytes"],
        "#{kind}_screenshot_bytes",
        MIN_IMAGE_BYTES,
        MAX_IMAGE_BYTES
      )
    end

    reject("app bundle identifier is invalid") unless values["app_bundle_id"] == "app.devisland.Island"
    reject("app version does not match product version") unless
      values["app_version"] == values["product_version"]
    reject("Codex CLI version is invalid") unless
      values["codex_cli_version"].match?(/\A[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?\z/)
    reject("visual review was not explicitly confirmed") unless
      values["visual_review"] == "waiting,deny,running"
    reject("proof absence validation did not pass") unless
      values["proof_absence_validation"] == "passed"
    reject("session validation did not pass") unless values["session_validation"] == "passed"
    reject("history record validation did not pass") unless values["history_record_validation"] == "passed"
    reject("wrapper did not accept the evidence") unless values["wrapper_result"] == "accepted"
    values
  end

  def validate_task_record(values, metadata)
    reject("task record schema is invalid") unless
      values["schema"] == "dev-island-codex-live-decision-task-record-v1"
    reject("task record source is invalid") unless values["source"] == "codex"
    reject("task record session differs from evidence metadata") unless
      values["session_id"] == metadata["session_id"]
    reject("task record is not completed") unless values["status"] == "completed"
    created_at = parse_utc(values["created_at_utc"], "task created_at_utc")
    updated_at = parse_utc(values["updated_at_utc"], "task updated_at_utc")
    reject("task record timestamps are out of order") unless created_at <= updated_at
    evidence_start = parse_utc(metadata["started_at_utc"], "started_at_utc")
    evidence_finish = parse_utc(metadata["finished_at_utc"], "finished_at_utc")
    reject("task record starts outside the evidence session") unless
      created_at >= evidence_start - 10 && created_at <= evidence_finish
    reject("task record finishes outside the evidence session") unless
      updated_at >= evidence_start && updated_at <= evidence_finish + 10
  end

  def validate_absence_record(values, metadata)
    reject("proof absence schema is invalid") unless
      values["schema"] == "dev-island-codex-proof-absence-v1"
    validate_sha256(values["proof_path_sha256"], "proof absence path hash")
    reject("proof absence path differs from evidence metadata") unless
      values["proof_path_sha256"] == metadata["proof_path_sha256"]
    parse_utc(values["checked_at_utc"], "proof absence checked_at_utc")
    reject("proof absence time differs from evidence metadata") unless
      values["checked_at_utc"] == metadata["proof_absence_checked_at_utc"]
    reject("proof was not recorded absent") unless values["result"] == "absent"
  end

  def validate_receipt_values(values, expected_product_version: nil)
    reject("public receipt schema is invalid") unless
      values["schema"] == "dev-island-codex-live-decision-public-receipt-v1"
    reject("public receipt classification is invalid") unless
      values["classification"] == "explicit_island_deny"
    reject("public receipt product version is invalid") unless
      values["product_version"].match?(/\A(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\z/)
    if expected_product_version
      reject("public receipt product version differs from VERSION") unless
        values["product_version"] == expected_product_version
    end
    reject("public receipt baseline commit is invalid") unless
      values["baseline_commit"].match?(/\A[0-9a-f]{40}\z/)
    reject("public receipt worktree state is invalid") unless %w[clean dirty].include?(values["worktree_state"])
    reject("public receipt session ID is invalid") unless
      values["session_id"].match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    started_at = parse_utc(values["started_at_utc"], "receipt started_at_utc")
    finished_at = parse_utc(values["finished_at_utc"], "receipt finished_at_utc")
    reject("public receipt timestamps are out of order") unless started_at < finished_at
    validate_integer(values["permission_wait_seconds"], "receipt permission_wait_seconds", 1, 89)
    reject("public receipt bundle identifier is invalid") unless values["app_bundle_id"] == "app.devisland.Island"
    reject("public receipt app version differs from product version") unless
      values["app_version"] == values["product_version"]
    reject("public receipt Codex CLI version is invalid") unless
      values["codex_cli_version"].match?(/\A[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?\z/)
    %w[
      app_executable_sha256
      codex_cli_sha256
      session_source_sha256
      history_database_sha256
      decision_packager_sha256
      decision_validator_sha256
      foundation_packager_sha256
      foundation_validator_sha256
      wrapper_sha256
      transcript_sha256
      task_record_sha256
      proof_absence_sha256
      proof_path_sha256
      deny_screenshot_sha256
      running_screenshot_sha256
    ].each { |key| validate_sha256(values[key], "receipt #{key}") }
    reject("public receipt visual review is invalid") unless
      values["visual_review"] == "waiting,deny,running"
    reject("public receipt is not accepted") unless values["result"] == "accepted"
    values
  end

  def validate_receipt(path, expected_product_version: nil)
    bytes, = read_regular(path, label: "public receipt")
    values = parse_key_value(parse_text(bytes, "public receipt"), RECEIPT_KEYS, "public receipt")
    validate_receipt_values(values, expected_product_version: expected_product_version)
  end

  def validate_package(directory, require_accepted: false, expected_product_version: nil)
    directory_stat = File.lstat(directory)
    reject("evidence package must be a real directory") unless
      directory_stat.directory? && !directory_stat.symlink?
    reject("evidence package must be owned by the current user") unless directory_stat.uid == Process.uid
    reject("evidence package must be private") unless (directory_stat.mode & 0o077).zero?

    entries = Dir.children(directory).sort
    reject("evidence package file inventory is invalid") unless entries == PACKAGE_FILES.sort

    files = {}
    PACKAGE_FILES.each do |name|
      maximum = name.end_with?(".jpeg") ? MAX_IMAGE_BYTES : MAX_TEXT_BYTES
      minimum = name.end_with?(".jpeg") ? MIN_IMAGE_BYTES : 1
      files[name], = read_regular(
        File.join(directory, name),
        label: "evidence file #{name}",
        minimum_bytes: minimum,
        maximum_bytes: maximum
      )
    end

    metadata = validate_metadata(parse_key_value(
      parse_text(files.fetch("EVIDENCE_METADATA.txt"), "evidence metadata"),
      METADATA_KEYS,
      "evidence metadata"
    ))
    expected_transcript = TRANSCRIPT_LINES.join("\n") + "\n"
    reject("evidence transcript differs from the low-cardinality contract") unless
      parse_text(files.fetch("transcript.txt"), "evidence transcript") == expected_transcript

    task_record = parse_key_value(
      parse_text(files.fetch("TASK_RECORD.txt"), "task record"),
      TASK_RECORD_KEYS,
      "task record"
    )
    validate_task_record(task_record, metadata)
    absence_record = parse_key_value(
      parse_text(files.fetch("PROOF_ABSENCE.txt"), "proof absence record"),
      ABSENCE_KEYS,
      "proof absence record"
    )
    validate_absence_record(absence_record, metadata)

    %w[01-live-codex-deny.jpeg 02-live-codex-running.jpeg].each do |name|
      validate_jpeg(files.fetch(name), name)
    end
    cross_checks = {
      "deny_screenshot_sha256" => "01-live-codex-deny.jpeg",
      "running_screenshot_sha256" => "02-live-codex-running.jpeg",
    }
    cross_checks.each do |metadata_key, file_name|
      reject("#{metadata_key} differs from packaged artifact") unless
        metadata[metadata_key] == sha256(files.fetch(file_name))
    end
    size_checks = {
      "deny_screenshot_bytes" => "01-live-codex-deny.jpeg",
      "running_screenshot_bytes" => "02-live-codex-running.jpeg",
    }
    size_checks.each do |metadata_key, file_name|
      reject("#{metadata_key} differs from packaged artifact") unless
        Integer(metadata[metadata_key], 10) == files.fetch(file_name).bytesize
    end

    receipt = validate_receipt_values(parse_key_value(
      parse_text(files.fetch("PUBLIC_RECEIPT.txt"), "public receipt"),
      RECEIPT_KEYS,
      "public receipt"
    ), expected_product_version: expected_product_version)
    receipt_to_metadata = %w[
      classification
      product_version
      baseline_commit
      worktree_state
      session_id
      started_at_utc
      finished_at_utc
      permission_wait_seconds
      app_bundle_id
      app_version
      app_executable_sha256
      codex_cli_version
      codex_cli_sha256
      session_source_sha256
      history_database_sha256
      decision_packager_sha256
      decision_validator_sha256
      foundation_packager_sha256
      foundation_validator_sha256
      wrapper_sha256
      proof_path_sha256
      deny_screenshot_sha256
      running_screenshot_sha256
      visual_review
    ]
    receipt_to_metadata.each do |key|
      reject("public receipt #{key} differs from evidence metadata") unless receipt[key] == metadata[key]
    end
    reject("public receipt transcript hash is invalid") unless
      receipt["transcript_sha256"] == sha256(files.fetch("transcript.txt"))
    reject("public receipt task-record hash is invalid") unless
      receipt["task_record_sha256"] == sha256(files.fetch("TASK_RECORD.txt"))
    reject("public receipt proof-absence hash is invalid") unless
      receipt["proof_absence_sha256"] == sha256(files.fetch("PROOF_ABSENCE.txt"))

    accepted = parse_text(files.fetch("ACCEPTED"), "accepted marker")
    reject("accepted marker is invalid") unless accepted == "accepted=true\n"
    reject("accepted evidence was required") if require_accepted && receipt["result"] != "accepted"

    checksum_lines = parse_text(files.fetch("SHA256SUMS"), "checksum manifest").lines(chomp: true)
    expected_names = (PACKAGE_FILES - ["SHA256SUMS"]).sort
    reject("checksum manifest entry count is invalid") unless checksum_lines.length == expected_names.length
    checksum_lines.each_with_index do |line, index|
      match = line.match(/\A([0-9a-f]{64})  ([0-9A-Za-z_.-]+)\z/)
      reject("checksum manifest contains an invalid entry") unless match
      name = match[2]
      reject("checksum manifest order is invalid") unless name == expected_names[index]
      reject("checksum manifest hash mismatch for #{name}") unless match[1] == sha256(files.fetch(name))
    end

    if expected_product_version
      reject("evidence product version differs from VERSION") unless
        metadata["product_version"] == expected_product_version
    end
    metadata
  rescue Errno::ENOENT
    reject("evidence package is unavailable")
  end
end

if $PROGRAM_NAME == __FILE__
  def usage
    warn "Usage: validate-codex-live-decision-evidence.rb (--evidence DIR | --receipt FILE) [--require-accepted] [--product-version VERSION]"
    exit 64
  end

  arguments = ARGV.dup
  mode = arguments.shift
  target = arguments.shift
  usage unless %w[--evidence --receipt].include?(mode) && target && !target.empty?

  require_accepted = false
  product_version = nil
  until arguments.empty?
    option = arguments.shift
    case option
    when "--require-accepted"
      usage if require_accepted
      require_accepted = true
    when "--product-version"
      usage if product_version || arguments.empty?
      product_version = arguments.shift
    else
      usage
    end
  end
  usage if mode == "--receipt" && require_accepted

  begin
    if mode == "--evidence"
      CodexLiveDecisionEvidence.validate_package(
        target,
        require_accepted: require_accepted,
        expected_product_version: product_version
      )
      puts "Codex live decision evidence: ACCEPTED"
    else
      CodexLiveDecisionEvidence.validate_receipt(
        target,
        expected_product_version: product_version
      )
      puts "Codex live decision public receipt: VALID"
    end
  rescue CodexLiveApprovalEvidence::ValidationError => error
    warn "error: #{error.message}"
    exit 1
  end
end
