#!/usr/bin/env ruby

require "digest"
require "json"
require "open3"
require "time"
require_relative "validate-codex-live-approval-evidence"

module CodexLiveApprovalPackager
  extend self

  MAX_SESSION_BYTES = 16 * 1_024 * 1_024
  MAX_BINARY_BYTES = 512 * 1_024 * 1_024
  PROOF_TEXT = "dev-island-real-codex-approval\n".freeze
  VISUAL_CONFIRMATION = "waiting,allow_once,running,completed".freeze

  def reject(message)
    CodexLiveApprovalEvidence.reject(message)
  end

  def command_output(*arguments)
    environment = {
      "PATH" => "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin",
      "LC_ALL" => "C",
    }
    stdout, stderr, status = Open3.capture3(environment, *arguments, unsetenv_others: true)
    reject("command failed: #{File.basename(arguments.first)}") unless status.success?
    reject("command wrote unexpected diagnostic output: #{File.basename(arguments.first)}") unless stderr.empty?
    stdout
  rescue Errno::ENOENT
    reject("required command is unavailable: #{File.basename(arguments.first)}")
  end

  def stable_hash(path, label:, minimum_bytes: 1, maximum_bytes: MAX_BINARY_BYTES, executable: false)
    path_stat = File.lstat(path)
    CodexLiveApprovalEvidence.validate_regular_metadata(
      path_stat,
      label,
      minimum_bytes,
      maximum_bytes
    )
    reject("#{label} must be executable") if executable && (path_stat.mode & 0o111).zero?

    flags = File::RDONLY | File::NOFOLLOW
    flags |= File::CLOEXEC if File.const_defined?(:CLOEXEC)
    digest = Digest::SHA256.new
    opened_stat = nil
    post_read_stat = nil
    File.open(path, flags) do |file|
      opened_stat = file.stat
      CodexLiveApprovalEvidence.validate_regular_metadata(
        opened_stat,
        label,
        minimum_bytes,
        maximum_bytes
      )
      reject("#{label} must be executable") if executable && (opened_stat.mode & 0o111).zero?
      reject("#{label} path changed before descriptor anchoring") unless
        path_stat.dev == opened_stat.dev && path_stat.ino == opened_stat.ino
      while (chunk = file.read(1_024 * 1_024))
        digest.update(chunk)
      end
      post_read_stat = file.stat
    end
    reject("#{label} changed while it was hashed") unless
      opened_stat.dev == post_read_stat.dev &&
        opened_stat.ino == post_read_stat.ino &&
        opened_stat.size == post_read_stat.size &&
        opened_stat.uid == post_read_stat.uid &&
        opened_stat.mode == post_read_stat.mode &&
        opened_stat.nlink == post_read_stat.nlink
    final_stat = File.lstat(path)
    reject("#{label} path changed after descriptor hashing") unless
      final_stat.file? && !final_stat.symlink? &&
        final_stat.dev == opened_stat.dev && final_stat.ino == opened_stat.ino
    [digest.hexdigest, opened_stat.size]
  rescue Errno::ENOENT
    reject("#{label} is unavailable")
  rescue Errno::ELOOP
    reject("#{label} must not be a symbolic link")
  rescue SystemCallError
    reject("#{label} could not be hashed through a no-follow descriptor")
  end

  def parse_timestamp(value, label)
    reject("#{label} is unavailable") unless value.is_a?(String)
    Time.iso8601(value)
  rescue ArgumentError
    reject("#{label} is invalid")
  end

  def canonical_utc(time)
    time.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
  end

  def message_text(payload)
    content = payload["content"]
    return nil unless content.is_a?(Array)
    pieces = content.map do |item|
      next unless item.is_a?(Hash)
      item["text"] if %w[input_text output_text].include?(item["type"])
    end.compact
    pieces.join
  end

  def output_text(payload)
    output = payload["output"]
    return output if output.is_a?(String)
    return "" unless output.is_a?(Array)
    output.map { |item| item.is_a?(Hash) ? item["text"].to_s : "" }.join
  end

  def parse_exec_arguments(input)
    prefix = "const r = await tools.exec_command("
    reject("permission tool input has an invalid prefix") unless input.is_a?(String) && input.start_with?(prefix)
    close_index = input.index(");\n", prefix.length)
    reject("permission tool input has no bounded JSON argument") unless close_index
    json = input[prefix.length...close_index]
    arguments = JSON.parse(json)
    reject("permission tool arguments are not an object") unless arguments.is_a?(Hash)
    arguments
  rescue JSON::ParserError
    reject("permission tool arguments are not valid JSON")
  end

  def parse_session(session_path, proof_path)
    bytes, session_stat = CodexLiveApprovalEvidence.read_regular(
      session_path,
      label: "Codex session source",
      minimum_bytes: 1,
      maximum_bytes: MAX_SESSION_BYTES
    )
    text = CodexLiveApprovalEvidence.parse_text(bytes, "Codex session source")
    records = text.lines(chomp: true).map.with_index do |line, index|
      reject("Codex session source contains a blank record") if line.empty?
      record = JSON.parse(line)
      reject("Codex session record #{index + 1} is not an object") unless record.is_a?(Hash)
      record
    rescue JSON::ParserError
      reject("Codex session source contains invalid JSONL")
    end
    reject("Codex session source is outside the reviewed record boundary") unless records.length.between?(8, 10_000)

    session_meta_records = records.select { |record| record["type"] == "session_meta" }
    reject("Codex session source must contain exactly one session metadata record") unless session_meta_records.length == 1
    meta_record = session_meta_records.first
    meta = meta_record["payload"]
    reject("Codex session metadata is invalid") unless meta.is_a?(Hash)
    session_id = meta["session_id"]
    reject("Codex session ID is invalid") unless
      session_id.is_a?(String) &&
        session_id.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    reject("Codex session metadata IDs differ") unless meta["id"] == session_id
    reject("Codex session did not originate from the supported client") unless
      meta["originator"] == "Codex Desktop" && meta["source"] == "cli" && meta["thread_source"] == "user"
    cli_version = meta["cli_version"]
    reject("Codex session CLI version is invalid") unless
      cli_version.is_a?(String) && cli_version.match?(/\A[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?\z/)
    workspace = meta["cwd"]
    reject("Codex session workspace is invalid") unless workspace.is_a?(String) && workspace.start_with?("/")
    workspace_real = File.realpath(workspace)
    proof_real = File.realpath(proof_path)
    reject("approval proof must be outside the Codex workspace") if
      proof_real == workspace_real || proof_real.start_with?(workspace_real + File::SEPARATOR)

    expected_prompt = "Use the shell to write exactly the single line dev-island-real-codex-approval to #{proof_path}. This target is intentionally outside the workspace. Request user approval when needed, and wait for the decision. Do not use apply_patch, Python, or another workaround. After the command succeeds, report only APPROVAL_ROUND_TRIP_COMPLETE."
    prompts = records.select do |record|
      payload = record["payload"]
      record["type"] == "response_item" && payload.is_a?(Hash) &&
        payload["type"] == "message" && payload["role"] == "user" &&
        message_text(payload) == expected_prompt
    end
    reject("Codex session does not contain the exact reviewed approval prompt") unless prompts.length == 1

    expected_command = "printf '%s\\n' 'dev-island-real-codex-approval' > '#{proof_path}'"
    permission_calls = []
    records.each do |record|
      payload = record["payload"]
      next unless record["type"] == "response_item" && payload.is_a?(Hash)
      next unless payload["type"] == "custom_tool_call" && payload["name"] == "exec"
      arguments = parse_exec_arguments(payload["input"])
      next unless arguments["cmd"] == expected_command
      permission_calls << [record, payload, arguments]
    end
    reject("Codex session must contain exactly one reviewed permission request") unless permission_calls.length == 1
    permission_record, permission_payload, permission_arguments = permission_calls.first
    reject("Codex permission request did not require escalation") unless
      permission_arguments["sandbox_permissions"] == "require_escalated"
    reject("Codex permission request workdir differs from the session workspace") unless
      File.realpath(permission_arguments["workdir"].to_s) == workspace_real
    reject("Codex permission request justification is invalid") unless
      permission_arguments["justification"] == "Allow writing the requested single-line proof file outside the current workspace?"
    reject("Codex permission request output boundary is invalid") unless
      permission_arguments["max_output_tokens"] == 1_000 && permission_arguments["yield_time_ms"] == 10_000
    reject("Codex permission request was not marked completed by the client") unless
      permission_payload["status"] == "completed"
    call_id = permission_payload["call_id"]
    reject("Codex permission request call ID is invalid") unless call_id.is_a?(String) && !call_id.empty?

    pending_outputs = records.select do |record|
      payload = record["payload"]
      record["type"] == "response_item" && payload.is_a?(Hash) &&
        payload["type"] == "custom_tool_call_output" && payload["call_id"] == call_id
    end
    reject("Codex permission request must have exactly one pending output") unless pending_outputs.length == 1
    pending_text = output_text(pending_outputs.first["payload"])
    pending_match = pending_text.match(/\AScript running with cell ID ([1-9][0-9]*)\nWall time [0-9]+(?:\.[0-9]+)? seconds\nOutput:\n\z/)
    reject("Codex permission request did not enter a bounded waiting state") unless pending_match
    cell_id = pending_match[1]

    wait_calls = records.select do |record|
      payload = record["payload"]
      next false unless record["type"] == "response_item" && payload.is_a?(Hash)
      next false unless payload["type"] == "function_call" && payload["name"] == "wait"
      begin
        arguments = JSON.parse(payload["arguments"])
        arguments["cell_id"].to_s == cell_id &&
          arguments["yield_time_ms"].is_a?(Integer) && arguments["yield_time_ms"].between?(1, 60_000) &&
          arguments["max_tokens"].is_a?(Integer) && arguments["max_tokens"].between?(1, 10_000)
      rescue JSON::ParserError
        false
      end
    end
    reject("Codex session must contain exactly one bounded wait for the permission request") unless wait_calls.length == 1
    wait_payload = wait_calls.first["payload"]
    wait_outputs = records.select do |record|
      payload = record["payload"]
      record["type"] == "response_item" && payload.is_a?(Hash) &&
        payload["type"] == "function_call_output" && payload["call_id"] == wait_payload["call_id"]
    end
    reject("Codex permission wait must have exactly one completion output") unless wait_outputs.length == 1
    completion_text = output_text(wait_outputs.first["payload"])
    reject("Codex permission request did not resume with exit zero") unless
      completion_text.match?(/\AScript completed\nWall time [0-9]+(?:\.[0-9]+)? seconds\nOutput:\n\{"exit_code":0,"wall_time_seconds":[0-9]+(?:\.[0-9]+)?\}\z/)

    final_messages = records.select do |record|
      payload = record["payload"]
      record["type"] == "response_item" && payload.is_a?(Hash) &&
        payload["type"] == "message" && payload["role"] == "assistant" &&
        payload["phase"] == "final_answer" && message_text(payload) == "APPROVAL_ROUND_TRIP_COMPLETE"
    end
    reject("Codex session must contain exactly one accepted final message") unless final_messages.length == 1
    task_completions = records.select do |record|
      payload = record["payload"]
      record["type"] == "event_msg" && payload.is_a?(Hash) && payload["type"] == "task_complete"
    end
    reject("Codex session must contain exactly one task-complete event") unless task_completions.length == 1

    started_at = parse_timestamp(meta["timestamp"], "Codex session start")
    requested_at = parse_timestamp(permission_record["timestamp"], "Codex permission request time")
    pending_at = parse_timestamp(pending_outputs.first["timestamp"], "Codex permission pending time")
    resumed_at = parse_timestamp(wait_outputs.first["timestamp"], "Codex permission resume time")
    final_at = parse_timestamp(final_messages.first["timestamp"], "Codex final message time")
    finished_at = parse_timestamp(task_completions.first["timestamp"], "Codex task completion time")
    reject("Codex approval event order is invalid") unless
      started_at < requested_at && requested_at <= pending_at && pending_at < resumed_at &&
        resumed_at <= final_at && final_at <= finished_at
    permission_wait_seconds = (resumed_at - requested_at).round
    reject("Codex approval wait is outside the reviewed boundary") unless permission_wait_seconds.between?(1, 1_800)

    {
      bytes: bytes,
      byte_count: session_stat.size,
      sha256: Digest::SHA256.hexdigest(bytes),
      session_id: session_id,
      workspace: workspace_real,
      cli_version: cli_version,
      started_at: started_at,
      finished_at: finished_at,
      permission_wait_seconds: permission_wait_seconds,
    }
  rescue Errno::ENOENT, Errno::EACCES
    reject("Codex session workspace or proof path is unavailable")
  end

  def ensure_no_history_sidecars(database_path)
    %w[-wal -shm -journal].each do |suffix|
      sidecar = database_path + suffix
      reject("Dev Island history database has a live sidecar; close the App and retry") if
        File.exist?(sidecar) || File.symlink?(sidecar)
    end
  end

  def read_history_record(database_path, session)
    ensure_no_history_sidecars(database_path)
    first_hash, = stable_hash(
      database_path,
      label: "Dev Island history database",
      minimum_bytes: 1,
      maximum_bytes: 64 * 1_024 * 1_024
    )
    session_id = session.fetch(:session_id)
    query = "SELECT source,id,status,created_at,updated_at FROM tasks WHERE source='codex' AND id='#{session_id}';"
    output = command_output("/usr/bin/sqlite3", "-readonly", "-separator", "|", database_path, query)
    second_hash, = stable_hash(
      database_path,
      label: "Dev Island history database",
      minimum_bytes: 1,
      maximum_bytes: 64 * 1_024 * 1_024
    )
    ensure_no_history_sidecars(database_path)
    reject("Dev Island history database changed during evidence extraction") unless first_hash == second_hash
    lines = output.lines(chomp: true)
    reject("Dev Island history must contain exactly one matching Codex task") unless lines.length == 1
    fields = lines.first.split("|", -1)
    reject("Dev Island history task record is malformed") unless fields.length == 5
    source, id, status, created_raw, updated_raw = fields
    reject("Dev Island history source is invalid") unless source == "codex"
    reject("Dev Island history session ID differs") unless id == session_id
    reject("Dev Island history task is not completed") unless status == "completed"
    reject("Dev Island history timestamps are invalid") unless
      created_raw.match?(/\A[0-9]+(?:\.[0-9]+)?\z/) && updated_raw.match?(/\A[0-9]+(?:\.[0-9]+)?\z/)
    created_at = Time.at(Float(created_raw)).utc
    updated_at = Time.at(Float(updated_raw)).utc
    reject("Dev Island history timestamps are out of order") unless created_at <= updated_at
    reject("Dev Island history task starts outside the Codex session") unless
      created_at >= session[:started_at] - 10 && created_at <= session[:finished_at]
    reject("Dev Island history task finishes outside the Codex session") unless
      updated_at >= session[:started_at] && updated_at <= session[:finished_at] + 10
    {
      sha256: first_hash,
      created_at: created_at,
      updated_at: updated_at,
    }
  rescue ArgumentError
    reject("Dev Island history timestamps could not be parsed")
  end

  def validate_directory(path, label, require_empty: false)
    stat = File.lstat(path)
    reject("#{label} must be a real directory") unless stat.directory? && !stat.symlink?
    reject("#{label} must be owned by the current user") unless stat.uid == Process.uid
    reject("#{label} must not be group- or world-writable") unless (stat.mode & 0o022).zero?
    reject("#{label} must be empty") if require_empty && !Dir.children(path).empty?
    File.realpath(path)
  rescue Errno::ENOENT
    reject("#{label} is unavailable")
  end

  def app_identity(app_path)
    app_real = validate_directory(app_path, "Dev Island app bundle")
    info_plist = File.join(app_real, "Contents", "Info.plist")
    plist_bytes_before, = CodexLiveApprovalEvidence.read_regular(
      info_plist,
      label: "Dev Island Info.plist",
      minimum_bytes: 1,
      maximum_bytes: 1_024 * 1_024
    )
    reject("Dev Island Info.plist is empty") if plist_bytes_before.empty?
    bundle_id = command_output("/usr/bin/plutil", "-extract", "CFBundleIdentifier", "raw", info_plist).strip
    version = command_output("/usr/bin/plutil", "-extract", "CFBundleShortVersionString", "raw", info_plist).strip
    executable_name = command_output("/usr/bin/plutil", "-extract", "CFBundleExecutable", "raw", info_plist).strip
    reject("Dev Island bundle identifier is invalid") unless bundle_id == "app.devisland.Island"
    reject("Dev Island app version is invalid") unless
      version.match?(/\A(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\z/)
    reject("Dev Island executable name is invalid") unless executable_name.match?(/\A[0-9A-Za-z ._-]+\z/)
    executable_path = File.join(app_real, "Contents", "MacOS", executable_name)
    hash, bytes = stable_hash(
      executable_path,
      label: "Dev Island executable",
      minimum_bytes: 1,
      maximum_bytes: MAX_BINARY_BYTES,
      executable: true
    )
    command_output("/usr/bin/codesign", "--verify", "--deep", "--strict", app_real)
    final_hash, final_bytes = stable_hash(
      executable_path,
      label: "Dev Island executable",
      minimum_bytes: 1,
      maximum_bytes: MAX_BINARY_BYTES,
      executable: true
    )
    reject("Dev Island executable changed during signature verification") unless
      final_hash == hash && final_bytes == bytes
    plist_bytes_after, = CodexLiveApprovalEvidence.read_regular(
      info_plist,
      label: "Dev Island Info.plist",
      minimum_bytes: 1,
      maximum_bytes: 1_024 * 1_024
    )
    reject("Dev Island Info.plist changed during identity verification") unless
      plist_bytes_after == plist_bytes_before
    { bundle_id: bundle_id, version: version, executable_sha256: hash, executable_bytes: bytes }
  end

  def repository_identity(repository_path)
    repository = validate_directory(repository_path, "repository")
    version_path = File.join(repository, "VERSION")
    version_bytes, = CodexLiveApprovalEvidence.read_regular(
      version_path,
      label: "VERSION",
      minimum_bytes: 2,
      maximum_bytes: 128
    )
    version_text = CodexLiveApprovalEvidence.parse_text(version_bytes, "VERSION").strip
    reject("VERSION is invalid") unless
      version_text.match?(/\A(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\z/)
    commit = command_output("/usr/bin/git", "-C", repository, "rev-parse", "HEAD").strip
    reject("repository baseline commit is invalid") unless commit.match?(/\A[0-9a-f]{40}\z/)
    status = command_output("/usr/bin/git", "-C", repository, "status", "--porcelain", "--untracked-files=normal")
    { root: repository, version: version_text, commit: commit, worktree_state: status.empty? ? "clean" : "dirty" }
  end

  def write_exclusive(path, bytes, mode = 0o600)
    flags = File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW
    flags |= File::CLOEXEC if File.const_defined?(:CLOEXEC)
    File.open(path, flags, mode) do |file|
      written = file.write(bytes)
      reject("could not write complete evidence artifact") unless written == bytes.bytesize
      file.flush
      file.fsync
    end
  rescue Errno::EEXIST, Errno::ELOOP
    reject("refusing to replace an existing evidence artifact")
  end

  def key_value_text(keys, values)
    keys.map { |key| "#{key}=#{values.fetch(key)}" }.join("\n") + "\n"
  end

  def package(options)
    reject("visual state sequence was not explicitly confirmed") unless
      options.fetch(:visual_confirmation) == VISUAL_CONFIRMATION
    output = validate_directory(options.fetch(:output), "evidence output", require_empty: true)
    File.chmod(0o700, output)
    repository = repository_identity(options.fetch(:repository))
    packager_hash, = stable_hash(
      File.expand_path(__FILE__),
      label: "Codex evidence packager",
      maximum_bytes: 1_024 * 1_024,
      executable: true
    )
    validator_hash, = stable_hash(
      File.expand_path("validate-codex-live-approval-evidence.rb", __dir__),
      label: "Codex evidence validator",
      maximum_bytes: 1_024 * 1_024,
      executable: true
    )
    wrapper_hash, = stable_hash(
      File.expand_path("run-codex-live-approval-evidence.sh", __dir__),
      label: "Codex evidence wrapper",
      maximum_bytes: 1_024 * 1_024,
      executable: true
    )
    session = parse_session(options.fetch(:session_log), options.fetch(:proof))
    history = read_history_record(options.fetch(:history_db), session)
    app = app_identity(options.fetch(:app))
    reject("evidence app version differs from VERSION") unless app[:version] == repository[:version]
    codex_hash, codex_bytes = stable_hash(
      options.fetch(:codex_cli),
      label: "Codex CLI binary",
      minimum_bytes: 1,
      maximum_bytes: MAX_BINARY_BYTES,
      executable: true
    )

    proof, proof_stat = CodexLiveApprovalEvidence.read_regular(
      options.fetch(:proof),
      label: "approval proof",
      minimum_bytes: 1,
      maximum_bytes: 1_024
    )
    reject("approval proof content is invalid") unless proof == PROOF_TEXT
    image_inputs = {
      "01-live-codex-approval.jpeg" => options.fetch(:approval_screenshot),
      "02-live-codex-running.jpeg" => options.fetch(:running_screenshot),
      "03-live-codex-completed.jpeg" => options.fetch(:completed_screenshot),
    }
    images = {}
    image_inputs.each do |name, path|
      bytes, = CodexLiveApprovalEvidence.read_regular(
        path,
        label: name,
        minimum_bytes: CodexLiveApprovalEvidence::MIN_IMAGE_BYTES,
        maximum_bytes: CodexLiveApprovalEvidence::MAX_IMAGE_BYTES
      )
      CodexLiveApprovalEvidence.validate_jpeg(bytes, name)
      images[name] = bytes
    end

    task_values = {
      "schema" => "dev-island-codex-live-task-record-v1",
      "source" => "codex",
      "session_id" => session[:session_id],
      "status" => "completed",
      "created_at_utc" => canonical_utc(history[:created_at]),
      "updated_at_utc" => canonical_utc(history[:updated_at]),
    }
    task_text = key_value_text(CodexLiveApprovalEvidence::TASK_RECORD_KEYS, task_values)
    transcript = CodexLiveApprovalEvidence::TRANSCRIPT_LINES.join("\n") + "\n"
    metadata_values = {
      "schema" => "dev-island-codex-live-approval-evidence-v1",
      "started_at_utc" => canonical_utc(session[:started_at]),
      "finished_at_utc" => canonical_utc(session[:finished_at]),
      "product_version" => repository[:version],
      "baseline_commit" => repository[:commit],
      "worktree_state" => repository[:worktree_state],
      "session_id" => session[:session_id],
      "session_source_sha256" => session[:sha256],
      "session_source_bytes" => session[:byte_count].to_s,
      "history_database_sha256" => history[:sha256],
      "packager_sha256" => packager_hash,
      "validator_sha256" => validator_hash,
      "wrapper_sha256" => wrapper_hash,
      "permission_wait_seconds" => session[:permission_wait_seconds].to_s,
      "app_bundle_id" => app[:bundle_id],
      "app_version" => app[:version],
      "app_executable_sha256" => app[:executable_sha256],
      "app_executable_bytes" => app[:executable_bytes].to_s,
      "codex_cli_version" => session[:cli_version],
      "codex_cli_sha256" => codex_hash,
      "codex_cli_bytes" => codex_bytes.to_s,
      "proof_sha256" => Digest::SHA256.hexdigest(proof),
      "proof_bytes" => proof_stat.size.to_s,
      "approval_screenshot_sha256" => Digest::SHA256.hexdigest(images.fetch("01-live-codex-approval.jpeg")),
      "approval_screenshot_bytes" => images.fetch("01-live-codex-approval.jpeg").bytesize.to_s,
      "running_screenshot_sha256" => Digest::SHA256.hexdigest(images.fetch("02-live-codex-running.jpeg")),
      "running_screenshot_bytes" => images.fetch("02-live-codex-running.jpeg").bytesize.to_s,
      "completed_screenshot_sha256" => Digest::SHA256.hexdigest(images.fetch("03-live-codex-completed.jpeg")),
      "completed_screenshot_bytes" => images.fetch("03-live-codex-completed.jpeg").bytesize.to_s,
      "visual_review" => "operator_confirmed",
      "session_validation" => "passed",
      "history_record_validation" => "passed",
      "wrapper_result" => "accepted",
    }
    metadata_text = key_value_text(CodexLiveApprovalEvidence::METADATA_KEYS, metadata_values)
    receipt_values = {
      "schema" => "dev-island-codex-live-approval-public-receipt-v1",
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
      "packager_sha256" => packager_hash,
      "validator_sha256" => validator_hash,
      "wrapper_sha256" => wrapper_hash,
      "transcript_sha256" => Digest::SHA256.hexdigest(transcript),
      "task_record_sha256" => Digest::SHA256.hexdigest(task_text),
      "proof_sha256" => metadata_values["proof_sha256"],
      "approval_screenshot_sha256" => metadata_values["approval_screenshot_sha256"],
      "running_screenshot_sha256" => metadata_values["running_screenshot_sha256"],
      "completed_screenshot_sha256" => metadata_values["completed_screenshot_sha256"],
      "visual_review" => "operator_confirmed",
      "result" => "accepted",
    }
    receipt_text = key_value_text(CodexLiveApprovalEvidence::RECEIPT_KEYS, receipt_values)

    write_exclusive(File.join(output, "approval-proof.txt"), proof)
    images.each { |name, bytes| write_exclusive(File.join(output, name), bytes) }
    write_exclusive(File.join(output, "TASK_RECORD.txt"), task_text)
    write_exclusive(File.join(output, "transcript.txt"), transcript)
    write_exclusive(File.join(output, "EVIDENCE_METADATA.txt"), metadata_text)
    write_exclusive(File.join(output, "PUBLIC_RECEIPT.txt"), receipt_text)
    write_exclusive(File.join(output, "ACCEPTED"), "accepted=true\n")

    checksum_names = CodexLiveApprovalEvidence::PACKAGE_FILES.reject { |name| name == "SHA256SUMS" }.sort
    checksum_text = checksum_names.map do |name|
      bytes, = CodexLiveApprovalEvidence.read_regular(
        File.join(output, name),
        label: "generated evidence file #{name}",
        minimum_bytes: 1,
        maximum_bytes: name.end_with?(".jpeg") ? CodexLiveApprovalEvidence::MAX_IMAGE_BYTES : CodexLiveApprovalEvidence::MAX_TEXT_BYTES
      )
      "#{Digest::SHA256.hexdigest(bytes)}  #{name}"
    end.join("\n") + "\n"
    write_exclusive(File.join(output, "SHA256SUMS"), checksum_text)
    Dir.children(output).each { |name| File.chmod(0o400, File.join(output, name)) }
    CodexLiveApprovalEvidence.validate_package(
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
      Usage: package-codex-live-approval-evidence.rb \\
        --repository DIR --session-log FILE --history-db FILE --proof FILE \\
        --app APP --codex-cli FILE --approval-screenshot FILE \\
        --running-screenshot FILE --completed-screenshot FILE --output DIR \\
        --confirm-visual-state-sequence waiting,allow_once,running,completed
    USAGE
    exit 64
  end

  arguments = ARGV.dup
  options = {}
  mapping = {
    "--repository" => :repository,
    "--session-log" => :session_log,
    "--history-db" => :history_db,
    "--proof" => :proof,
    "--app" => :app,
    "--codex-cli" => :codex_cli,
    "--approval-screenshot" => :approval_screenshot,
    "--running-screenshot" => :running_screenshot,
    "--completed-screenshot" => :completed_screenshot,
    "--output" => :output,
    "--confirm-visual-state-sequence" => :visual_confirmation,
  }
  until arguments.empty?
    option = arguments.shift
    key = mapping[option]
    usage unless key && !options.key?(key) && !arguments.empty?
    options[key] = arguments.shift
  end
  usage unless options.keys.sort == mapping.values.sort

  begin
    output = CodexLiveApprovalPackager.package(options)
    puts "Codex live approval evidence: ACCEPTED"
    puts "Evidence: #{output}"
  rescue CodexLiveApprovalEvidence::ValidationError => error
    warn "error: #{error.message}"
    exit 1
  end
end
