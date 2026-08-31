#!/usr/bin/env ruby

require "digest"
require "json"
require "time"
require_relative "package-codex-live-approval-evidence"
require_relative "validate-codex-live-decision-evidence"

module CodexLiveDecisionPackager
  extend self

  MAX_SESSION_BYTES = 16 * 1_024 * 1_024
  VISUAL_CONFIRMATION = "waiting,deny,running".freeze
  DENIAL_FINAL_MESSAGE = "DENIAL_ROUND_TRIP_COMPLETE".freeze
  CLASSIFICATIONS = %w[
    explicit_island_deny
    neutral_timeout_fallback
    sandbox_rejection
    interrupted_attempt
  ].freeze
  LEGACY_DENIAL_OUTPUT = /\AScript completed\nWall time [0-9]+(?:\.[0-9]+)? seconds\nOutput:\nPermission request denied by user\z/.freeze
  SANDBOX_OUTPUT = /sandbox|outside (?:the )?(?:workspace|writable roots?)|not permitted by (?:the )?policy|operation not permitted/im
  INTERRUPTED_OUTPUT = /aborted by user|conversation interrupted|turn_aborted/im
  REVIEWED_JUSTIFICATIONS = [
    "Allow writing the requested proof file outside the workspace?",
    "Do you approve writing the requested proof file to this T7 Shield path outside the current workspace?",
  ].freeze
  REVIEWED_OUTPUT_TOKEN_LIMITS = [1_000, 2_000].freeze

  def reject(message)
    CodexLiveDecisionEvidence.reject(message)
  end

  def message_text(payload)
    CodexLiveApprovalPackager.message_text(payload)
  end

  def output_text(payload)
    CodexLiveApprovalPackager.output_text(payload)
  end

  def canonical_utc(time)
    CodexLiveApprovalPackager.canonical_utc(time)
  end

  def parse_timestamp(value, label)
    CodexLiveApprovalPackager.parse_timestamp(value, label)
  end

  def stable_hash(path, **options)
    CodexLiveApprovalPackager.stable_hash(path, **options)
  end

  def parse_exec_arguments(input)
    prefix = "const r = await tools.exec_command("
    reject("permission tool input has an invalid prefix") unless
      input.is_a?(String) && input.start_with?(prefix)
    close_index = input.index(");\n", prefix.length)
    reject("permission tool input has no bounded argument object") unless close_index
    source = input[prefix.length...close_index]
    parsed = JSON.parse(source)
    reject("permission tool arguments are not an object") unless parsed.is_a?(Hash)
    parsed
  rescue JSON::ParserError
    parse_reviewed_javascript_object(source)
  end

  def explicit_denial_output?(text, expected_command)
    return true if text.match?(LEGACY_DENIAL_OUTPUT)

    match = text.match(
      /\AScript failed\nWall time [0-9]+(?:\.[0-9]+)? seconds\nOutput:\n(?<error>.*)\z/m
    )
    return false unless match

    rendered_command = expected_command.gsub("\\") { "\\\\" }.gsub('"', '\\"')
    expected_error =
      "Script error:\n" \
      "exec_command failed for `/bin/zsh -lc \"#{rendered_command}\"`: " \
      'CreateProcess { message: "Rejected(\\"Denied in Dev Island.\\")" }'
    match[:error] == expected_error
  end

  def parse_reviewed_javascript_object(source)
    lines = source.to_s.lines(chomp: true)
    reject("permission tool JavaScript object is malformed") unless
      lines.length.between?(3, 16) && lines.shift == "{" && lines.pop == "}"
    allowed_keys = %w[
      cmd
      workdir
      sandbox_permissions
      justification
      yield_time_ms
      max_output_tokens
    ]
    values = {}
    lines.each_with_index do |line, index|
      match = line.match(/\A  ([a-z_]+): (.+?)(,?)\z/)
      reject("permission tool JavaScript field is malformed") unless match
      key = match[1]
      reject("permission tool JavaScript field is not reviewed") unless allowed_keys.include?(key)
      reject("permission tool JavaScript field is duplicated") if values.key?(key)
      expected_comma = index < lines.length - 1
      reject("permission tool JavaScript comma placement is invalid") unless
        (match[3] == ",") == expected_comma
      literal = match[2]
      value = if literal.match?(/\A(?:0|[1-9][0-9]*)\z/)
        Integer(literal, 10)
      elsif literal.start_with?("\"") && literal.end_with?("\"")
        JSON.parse(literal)
      else
        reject("permission tool JavaScript value is not a string or integer literal")
      end
      values[key] = value
    rescue JSON::ParserError
      reject("permission tool JavaScript string is invalid")
    end
    values
  end

  def assert_proof_absent(path, expected_parent: nil)
    reject("proof path must be an absolute canonical path") unless
      path.is_a?(String) && path.start_with?("/") && File.expand_path(path) == path
    reject("proof path contains unsupported characters") unless
      path.match?(/\A\/[0-9A-Za-z ._\/-]+\z/) && !path.include?("//")
    basename = File.basename(path)
    reject("proof path has an invalid final component") if basename.empty? || %w[. ..].include?(basename)
    parent = File.dirname(path)
    parent_real = CodexLiveApprovalPackager.validate_directory(parent, "proof parent directory")
    reject("proof parent directory must already be canonical") unless parent_real == parent
    parent_stat = File.lstat(parent_real)
    if expected_parent
      reject("proof parent directory changed during evidence collection") unless
        parent_stat.dev == expected_parent.dev && parent_stat.ino == expected_parent.ino
    end
    begin
      File.lstat(path)
      reject("denial proof unexpectedly exists")
    rescue Errno::ENOENT
      # The missing output file is the reviewed denial invariant.
    end
    [path, parent_stat]
  end

  def parse_records(session_path)
    bytes, session_stat = CodexLiveDecisionEvidence.read_regular(
      session_path,
      label: "Codex session source",
      minimum_bytes: 1,
      maximum_bytes: MAX_SESSION_BYTES
    )
    text = CodexLiveDecisionEvidence.parse_text(bytes, "Codex session source")
    records = text.lines(chomp: true).map.with_index do |line, index|
      reject("Codex session source contains a blank record") if line.empty?
      record = JSON.parse(line)
      reject("Codex session record #{index + 1} is not an object") unless record.is_a?(Hash)
      record
    rescue JSON::ParserError
      reject("Codex session source contains invalid JSONL")
    end
    reject("Codex session source is outside the reviewed record boundary") unless
      records.length.between?(8, 10_000)
    [records, bytes, session_stat]
  end

  def response_records(records, type)
    records.select do |record|
      payload = record["payload"]
      record["type"] == "response_item" && payload.is_a?(Hash) && payload["type"] == type
    end
  end

  def parse_session(session_path, proof_path)
    proof_canonical, proof_parent_stat = assert_proof_absent(proof_path)
    records, bytes, session_stat = parse_records(session_path)

    meta_records = records.select { |record| record["type"] == "session_meta" }
    reject("Codex session source must contain exactly one session metadata record") unless meta_records.length == 1
    meta = meta_records.first["payload"]
    reject("Codex session metadata is invalid") unless meta.is_a?(Hash)
    session_id = meta["session_id"]
    reject("Codex session ID is invalid") unless
      session_id.is_a?(String) &&
        session_id.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    reject("Codex session metadata IDs differ") unless meta["id"] == session_id
    reject("Codex session did not originate from the supported client") unless
      meta["originator"] == "Codex Desktop" && %w[cli exec].include?(meta["source"]) &&
        meta["thread_source"] == "user"
    cli_version = meta["cli_version"]
    reject("Codex session CLI version is invalid") unless
      cli_version.is_a?(String) && cli_version.match?(/\A[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?\z/)
    workspace = meta["cwd"]
    reject("Codex session workspace is invalid") unless workspace.is_a?(String) && workspace.start_with?("/")
    workspace_real = File.realpath(workspace)
    reject("Codex session workspace must already be canonical") unless workspace_real == workspace
    reject("denial proof must be outside the Codex workspace") if
      proof_canonical == workspace_real || proof_canonical.start_with?(workspace_real + File::SEPARATOR)

    expected_command = "printf '%s\\n' 'dev-island-real-codex-deny' > '#{proof_canonical}'"
    expected_prompt = "Use the shell to run exactly this command: #{expected_command}. The target is intentionally outside the workspace, so request user approval. If the request is denied, do not retry, do not use another tool, and report only DENIAL_ROUND_TRIP_COMPLETE. If it unexpectedly succeeds, report only DENIAL_UNEXPECTED_SUCCESS."
    prompts = response_records(records, "message").select do |record|
      payload = record["payload"]
      payload["role"] == "user" && message_text(payload) == expected_prompt
    end
    reject("Codex session does not contain the exact reviewed denial prompt") unless prompts.length == 1

    all_output = records.map do |record|
      payload = record["payload"]
      next unless payload.is_a?(Hash) && %w[custom_tool_call_output function_call_output].include?(payload["type"])
      output_text(payload)
    end.compact.join("\n")
    interrupted = records.any? do |record|
      payload = record["payload"]
      (record["type"] == "event_msg" && payload.is_a?(Hash) && payload["type"] == "turn_aborted") ||
        (record["type"] == "response_item" && payload.is_a?(Hash) && payload["type"] == "message" &&
          payload["role"] == "developer" && message_text(payload).to_s.include?("<turn_aborted>"))
    end || all_output.match?(INTERRUPTED_OUTPUT)
    base = {
      bytes: bytes,
      byte_count: session_stat.size,
      sha256: Digest::SHA256.hexdigest(bytes),
      session_id: session_id,
      workspace: workspace_real,
      cli_version: cli_version,
      proof_path: proof_canonical,
      proof_path_sha256: Digest::SHA256.hexdigest(proof_canonical.b),
      proof_parent_stat: proof_parent_stat,
      started_at: parse_timestamp(meta["timestamp"], "Codex session start"),
    }
    return base.merge(classification: "interrupted_attempt") if interrupted

    command_calls = []
    response_records(records, "custom_tool_call").each do |record|
      payload = record["payload"]
      next unless payload["name"] == "exec"
      arguments = parse_exec_arguments(payload["input"])
      command_calls << [record, payload, arguments] if arguments["cmd"] == expected_command
    rescue CodexLiveApprovalEvidence::ValidationError
      next
    end
    reject("Codex session must contain exactly one reviewed command attempt") unless command_calls.length == 1
    permission_record, permission_payload, permission_arguments = command_calls.first
    call_id = permission_payload["call_id"]
    reject("Codex permission request call ID is invalid") unless call_id.is_a?(String) && !call_id.empty?

    related_outputs = response_records(records, "custom_tool_call_output").select do |record|
      record["payload"]["call_id"] == call_id
    end

    escalated = permission_arguments["sandbox_permissions"] == "require_escalated"
    pending_output = related_outputs.find do |record|
      output_text(record["payload"]).match?(/\AScript running with cell ID [1-9][0-9]*\nWall time [0-9]+(?:\.[0-9]+)? seconds\nOutput:\n\z/)
    end
    if meta["source"] == "exec" || !escalated || all_output.match?(SANDBOX_OUTPUT) || pending_output.nil?
      return base.merge(classification: "sandbox_rejection")
    end

    effective_workdir = workspace_real
    if permission_arguments.key?("workdir")
      requested_workdir = permission_arguments["workdir"]
      reject("Codex permission request workdir is invalid") unless
        requested_workdir.is_a?(String) && !requested_workdir.empty? && requested_workdir.start_with?("/")
      effective_workdir = File.realpath(requested_workdir)
    end
    reject("Codex permission request workdir differs from the session workspace") unless
      effective_workdir == workspace_real
    reject("Codex permission request justification is invalid") unless
      REVIEWED_JUSTIFICATIONS.include?(permission_arguments["justification"])
    reject("Codex permission request output boundary is invalid") unless
      REVIEWED_OUTPUT_TOKEN_LIMITS.include?(permission_arguments["max_output_tokens"]) &&
        permission_arguments["yield_time_ms"] == 10_000
    reject("Codex permission request was not marked completed by the client") unless
      permission_payload["status"] == "completed"
    pending_match = output_text(pending_output["payload"]).match(/\AScript running with cell ID ([1-9][0-9]*)\n/)
    cell_id = pending_match[1]

    wait_calls = response_records(records, "function_call").map do |record|
      payload = record["payload"]
      next unless payload["name"] == "wait"
      begin
        arguments = JSON.parse(payload["arguments"])
      rescue JSON::ParserError
        next
      end
      next unless arguments["cell_id"].to_s == cell_id
      reject("Codex permission wait boundary is invalid") unless
        arguments["yield_time_ms"].is_a?(Integer) && arguments["yield_time_ms"].between?(1, 60_000) &&
          arguments["max_tokens"].is_a?(Integer) && arguments["max_tokens"].between?(1, 10_000)
      [record, payload]
    end.compact
    reject("Codex session has no bounded wait for the permission request") if wait_calls.empty?
    reject("Codex session exceeded the reviewed permission wait count") if wait_calls.length > 4

    terminal_outputs = wait_calls.map do |record, payload|
      outputs = response_records(records, "function_call_output").select do |candidate|
        candidate["payload"]["call_id"] == payload["call_id"]
      end
      reject("Codex permission wait must have exactly one output") unless outputs.length == 1
      [record, outputs.first, output_text(outputs.first["payload"])]
    end.compact
    terminal = terminal_outputs.last
    terminal_text = terminal[2]
    return base.merge(classification: "interrupted_attempt") if terminal_text.match?(INTERRUPTED_OUTPUT)
    return base.merge(classification: "sandbox_rejection") if terminal_text.match?(SANDBOX_OUTPUT)
    reject("Codex permission result is not an explicit denial") unless
      explicit_denial_output?(terminal_text, expected_command)

    final_messages = response_records(records, "message").select do |record|
      payload = record["payload"]
      payload["role"] == "assistant" && payload["phase"] == "final_answer" &&
        message_text(payload) == DENIAL_FINAL_MESSAGE
    end
    reject("Codex session must contain exactly one denial final message") unless final_messages.length == 1
    task_completions = records.select do |record|
      payload = record["payload"]
      record["type"] == "event_msg" && payload.is_a?(Hash) && payload["type"] == "task_complete"
    end
    reject("Codex session must contain exactly one task-complete event") unless task_completions.length == 1

    requested_at = parse_timestamp(permission_record["timestamp"], "Codex permission request time")
    pending_at = parse_timestamp(pending_output["timestamp"], "Codex permission pending time")
    denied_at = parse_timestamp(terminal[1]["timestamp"], "Codex permission denial time")
    final_at = parse_timestamp(final_messages.first["timestamp"], "Codex final message time")
    finished_at = parse_timestamp(task_completions.first["timestamp"], "Codex task completion time")
    reject("Codex denial event order is invalid") unless
      base[:started_at] < requested_at && requested_at <= pending_at && pending_at < denied_at &&
        denied_at <= final_at && final_at <= finished_at
    wait_seconds = (denied_at - requested_at).round
    reject("Codex decision wait is outside the reviewed boundary") unless wait_seconds.between?(1, 1_800)

    classification = wait_seconds <= 89 ? "explicit_island_deny" : "neutral_timeout_fallback"
    base.merge(
      classification: classification,
      finished_at: finished_at,
      permission_wait_seconds: wait_seconds
    )
  rescue Errno::ENOENT, Errno::EACCES
    reject("Codex session workspace, proof parent, or proof path is unavailable")
  end

  def package(options)
    reject("visual state sequence was not explicitly confirmed") unless
      options.fetch(:visual_confirmation) == VISUAL_CONFIRMATION
    output = CodexLiveApprovalPackager.validate_directory(
      options.fetch(:output),
      "evidence output",
      require_empty: true
    )
    File.chmod(0o700, output)
    repository = CodexLiveApprovalPackager.repository_identity(options.fetch(:repository))
    session = parse_session(options.fetch(:session_log), options.fetch(:proof))
    reject("Codex session is not an explicit island denial: #{session[:classification]}") unless
      session[:classification] == "explicit_island_deny"
    history = CodexLiveApprovalPackager.read_history_record(options.fetch(:history_db), session)
    app = CodexLiveApprovalPackager.app_identity(options.fetch(:app))
    reject("evidence app version differs from VERSION") unless app[:version] == repository[:version]
    codex_hash, codex_bytes = stable_hash(
      options.fetch(:codex_cli),
      label: "Codex CLI binary",
      minimum_bytes: 1,
      maximum_bytes: CodexLiveApprovalPackager::MAX_BINARY_BYTES,
      executable: true
    )

    script_hashes = {}
    {
      "decision_packager_sha256" => __FILE__,
      "decision_validator_sha256" => File.expand_path("validate-codex-live-decision-evidence.rb", __dir__),
      "foundation_packager_sha256" => File.expand_path("package-codex-live-approval-evidence.rb", __dir__),
      "foundation_validator_sha256" => File.expand_path("validate-codex-live-approval-evidence.rb", __dir__),
      "wrapper_sha256" => File.expand_path("run-codex-live-decision-evidence.sh", __dir__),
    }.each do |key, path|
      script_hashes[key], = stable_hash(
        path,
        label: key.tr("_", " "),
        maximum_bytes: 1_024 * 1_024,
        executable: true
      )
    end

    image_inputs = {
      "01-live-codex-deny.jpeg" => options.fetch(:deny_screenshot),
      "02-live-codex-running.jpeg" => options.fetch(:running_screenshot),
    }
    images = {}
    image_inputs.each do |name, path|
      bytes, = CodexLiveDecisionEvidence.read_regular(
        path,
        label: name,
        minimum_bytes: CodexLiveDecisionEvidence::MIN_IMAGE_BYTES,
        maximum_bytes: CodexLiveDecisionEvidence::MAX_IMAGE_BYTES
      )
      CodexLiveDecisionEvidence.validate_jpeg(bytes, name)
      images[name] = bytes
    end

    proof_path, = assert_proof_absent(
      session.fetch(:proof_path),
      expected_parent: session.fetch(:proof_parent_stat)
    )
    absence_checked_at = Time.now.utc
    absence_values = {
      "schema" => "dev-island-codex-proof-absence-v1",
      "proof_path_sha256" => session.fetch(:proof_path_sha256),
      "checked_at_utc" => canonical_utc(absence_checked_at),
      "result" => "absent",
    }
    absence_text = CodexLiveApprovalPackager.key_value_text(
      CodexLiveDecisionEvidence::ABSENCE_KEYS,
      absence_values
    )
    task_values = {
      "schema" => "dev-island-codex-live-decision-task-record-v1",
      "source" => "codex",
      "session_id" => session[:session_id],
      "status" => "completed",
      "created_at_utc" => canonical_utc(history[:created_at]),
      "updated_at_utc" => canonical_utc(history[:updated_at]),
    }
    task_text = CodexLiveApprovalPackager.key_value_text(
      CodexLiveDecisionEvidence::TASK_RECORD_KEYS,
      task_values
    )
    transcript = CodexLiveDecisionEvidence::TRANSCRIPT_LINES.join("\n") + "\n"

    metadata_values = {
      "schema" => "dev-island-codex-live-decision-evidence-v1",
      "classification" => session[:classification],
      "started_at_utc" => canonical_utc(session[:started_at]),
      "finished_at_utc" => canonical_utc(session[:finished_at]),
      "product_version" => repository[:version],
      "baseline_commit" => repository[:commit],
      "worktree_state" => repository[:worktree_state],
      "session_id" => session[:session_id],
      "session_source_sha256" => session[:sha256],
      "session_source_bytes" => session[:byte_count].to_s,
      "history_database_sha256" => history[:sha256],
      "permission_wait_seconds" => session[:permission_wait_seconds].to_s,
      "app_bundle_id" => app[:bundle_id],
      "app_version" => app[:version],
      "app_executable_sha256" => app[:executable_sha256],
      "app_executable_bytes" => app[:executable_bytes].to_s,
      "codex_cli_version" => session[:cli_version],
      "codex_cli_sha256" => codex_hash,
      "codex_cli_bytes" => codex_bytes.to_s,
      "proof_path_sha256" => session[:proof_path_sha256],
      "proof_absence_checked_at_utc" => absence_values["checked_at_utc"],
      "deny_screenshot_sha256" => Digest::SHA256.hexdigest(images.fetch("01-live-codex-deny.jpeg")),
      "deny_screenshot_bytes" => images.fetch("01-live-codex-deny.jpeg").bytesize.to_s,
      "running_screenshot_sha256" => Digest::SHA256.hexdigest(images.fetch("02-live-codex-running.jpeg")),
      "running_screenshot_bytes" => images.fetch("02-live-codex-running.jpeg").bytesize.to_s,
      "visual_review" => VISUAL_CONFIRMATION,
      "proof_absence_validation" => "passed",
      "session_validation" => "passed",
      "history_record_validation" => "passed",
      "wrapper_result" => "accepted",
    }.merge(script_hashes)
    metadata_text = CodexLiveApprovalPackager.key_value_text(
      CodexLiveDecisionEvidence::METADATA_KEYS,
      metadata_values
    )

    receipt_values = {
      "schema" => "dev-island-codex-live-decision-public-receipt-v1",
      "classification" => session[:classification],
      "product_version" => repository[:version],
      "baseline_commit" => repository[:commit],
      "worktree_state" => repository[:worktree_state],
      "session_id" => session[:session_id],
      "started_at_utc" => metadata_values["started_at_utc"],
      "finished_at_utc" => metadata_values["finished_at_utc"],
      "permission_wait_seconds" => metadata_values["permission_wait_seconds"],
      "app_bundle_id" => app[:bundle_id],
      "app_version" => app[:version],
      "app_executable_sha256" => app[:executable_sha256],
      "codex_cli_version" => session[:cli_version],
      "codex_cli_sha256" => codex_hash,
      "session_source_sha256" => session[:sha256],
      "history_database_sha256" => history[:sha256],
      "transcript_sha256" => Digest::SHA256.hexdigest(transcript),
      "task_record_sha256" => Digest::SHA256.hexdigest(task_text),
      "proof_absence_sha256" => Digest::SHA256.hexdigest(absence_text),
      "proof_path_sha256" => session[:proof_path_sha256],
      "deny_screenshot_sha256" => metadata_values["deny_screenshot_sha256"],
      "running_screenshot_sha256" => metadata_values["running_screenshot_sha256"],
      "visual_review" => VISUAL_CONFIRMATION,
      "result" => "accepted",
    }.merge(script_hashes)
    receipt_text = CodexLiveApprovalPackager.key_value_text(
      CodexLiveDecisionEvidence::RECEIPT_KEYS,
      receipt_values
    )

    images.each do |name, bytes|
      CodexLiveApprovalPackager.write_exclusive(File.join(output, name), bytes)
    end
    CodexLiveApprovalPackager.write_exclusive(File.join(output, "PROOF_ABSENCE.txt"), absence_text)
    CodexLiveApprovalPackager.write_exclusive(File.join(output, "TASK_RECORD.txt"), task_text)
    CodexLiveApprovalPackager.write_exclusive(File.join(output, "transcript.txt"), transcript)
    CodexLiveApprovalPackager.write_exclusive(File.join(output, "EVIDENCE_METADATA.txt"), metadata_text)
    CodexLiveApprovalPackager.write_exclusive(File.join(output, "PUBLIC_RECEIPT.txt"), receipt_text)

    assert_proof_absent(proof_path, expected_parent: session.fetch(:proof_parent_stat))
    CodexLiveApprovalPackager.write_exclusive(File.join(output, "ACCEPTED"), "accepted=true\n")
    checksum_names = CodexLiveDecisionEvidence::PACKAGE_FILES.reject { |name| name == "SHA256SUMS" }.sort
    checksum_text = checksum_names.map do |name|
      bytes, = CodexLiveDecisionEvidence.read_regular(
        File.join(output, name),
        label: "generated evidence file #{name}",
        minimum_bytes: 1,
        maximum_bytes: name.end_with?(".jpeg") ? CodexLiveDecisionEvidence::MAX_IMAGE_BYTES : CodexLiveDecisionEvidence::MAX_TEXT_BYTES
      )
      "#{Digest::SHA256.hexdigest(bytes)}  #{name}"
    end.join("\n") + "\n"
    CodexLiveApprovalPackager.write_exclusive(File.join(output, "SHA256SUMS"), checksum_text)
    Dir.children(output).each { |name| File.chmod(0o400, File.join(output, name)) }
    CodexLiveDecisionEvidence.validate_package(
      output,
      require_accepted: true,
      expected_product_version: repository[:version]
    )
    output
  end
end

if $PROGRAM_NAME == __FILE__
  def usage
    warn <<~USAGE
      Usage:
        package-codex-live-decision-evidence.rb --classify-session FILE --proof FILE
        package-codex-live-decision-evidence.rb \\
          --repository DIR --session-log FILE --history-db FILE --proof FILE \\
          --app APP --codex-cli FILE --deny-screenshot FILE \\
          --running-screenshot FILE --output DIR \\
          --confirm-visual-state-sequence waiting,deny,running
    USAGE
    exit 64
  end

  arguments = ARGV.dup
  if arguments.first == "--classify-session"
    arguments.shift
    session_log = arguments.shift
    usage unless session_log && arguments.shift == "--proof"
    proof = arguments.shift
    usage unless proof && arguments.empty?
    begin
      result = CodexLiveDecisionPackager.parse_session(session_log, proof)
      puts "classification=#{result.fetch(:classification)}"
    rescue CodexLiveApprovalEvidence::ValidationError => error
      warn "error: #{error.message}"
      exit 1
    end
    exit 0
  end

  mapping = {
    "--repository" => :repository,
    "--session-log" => :session_log,
    "--history-db" => :history_db,
    "--proof" => :proof,
    "--app" => :app,
    "--codex-cli" => :codex_cli,
    "--deny-screenshot" => :deny_screenshot,
    "--running-screenshot" => :running_screenshot,
    "--output" => :output,
    "--confirm-visual-state-sequence" => :visual_confirmation,
  }
  options = {}
  until arguments.empty?
    option = arguments.shift
    key = mapping[option]
    usage unless key && !options.key?(key) && !arguments.empty?
    options[key] = arguments.shift
  end
  usage unless options.keys.sort == mapping.values.sort

  begin
    output = CodexLiveDecisionPackager.package(options)
    puts "Codex live decision evidence: ACCEPTED"
    puts "Evidence: #{output}"
  rescue CodexLiveApprovalEvidence::ValidationError => error
    warn "error: #{error.message}"
    exit 1
  end
end
