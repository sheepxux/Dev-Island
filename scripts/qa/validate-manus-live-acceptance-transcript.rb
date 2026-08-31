#!/usr/bin/env ruby

MINIMUM_BYTES = 1
MAXIMUM_BYTES = 64 * 1_024

LIVE_PREAMBLE = [
  "[CLI] Manus v2 live acceptance",
  "[CLI] This creates a temporary public tunnel and webhook, then removes both.",
  "[CLI] During the run, create one task that finishes and one task that pauses for input.",
  "[CLI] Provider identifiers, callback addresses, payload text and raw errors are never printed.",
].freeze

RECOVERY_PREAMBLE = [
  "[CLI] Manus v2 live acceptance recovery",
  "[CLI] This removes only a webhook proven by one explicit private journal.",
  "[CLI] Provider identifiers, callback addresses and raw errors are never printed.",
].freeze

LIVE_CHECKPOINTS = [
  "trust_anchor_validated",
  "server_started",
  "tunnel_started",
  "recovery_journal_persisted",
  "registration_started",
  "signed_registration_probe",
  "registration_accepted",
  "task_created",
  "task_stopped_finish",
  "task_stopped_ask",
  "webhook_deleted",
  "recovery_journal_cleared",
  "transports_stopped",
  "manual_webhook_review_required",
].freeze

RECOVERY_CHECKPOINTS = [
  "recovery_journal_validated",
  "recovery_inventory_checked",
  "recovery_webhook_bound",
  "webhook_deleted",
  "recovery_journal_cleared",
  "manual_webhook_review_required",
].freeze

ACCEPTED_CHECKPOINTS = (
  LIVE_CHECKPOINTS - ["manual_webhook_review_required"]
).freeze
FAILURE_STAGES = %w[
  trust_anchor
  server_startup
  server_configuration
  tunnel_startup
  registration
  lifecycle
].freeze

def usage
  warn "Usage: validate-manus-live-acceptance-transcript.rb --transcript FILE [--require-accepted]"
  exit 64
end

def reject(message)
  warn "error: #{message}"
  exit 1
end

def validate_file_metadata(stat)
  reject("transcript must be a regular non-symlink file") unless stat.file? && !stat.symlink?
  reject("transcript must be owned by the current user") unless stat.uid == Process.uid
  reject("transcript must have exactly one hard link") unless stat.nlink == 1
  reject("transcript must not be group- or world-writable") unless (stat.mode & 0o022).zero?
  reject("transcript size is outside the 1-64 KiB boundary") unless
    stat.size.between?(MINIMUM_BYTES, MAXIMUM_BYTES)
end

def terminal_kind(line, mode)
  shared = {
    "[CLI] credential_rejected" => "credential_rejected",
    "[CLI] result=journal_rejected" => "journal_rejected",
    "[CLI] result=manual_webhook_review_required" => "manual_webhook_review_required",
  }
  live = shared.merge(
    "[CLI] result=accepted" => "accepted",
    "[CLI] result=incomplete_cleanup" => "incomplete_cleanup",
    "[CLI] result=timed_out" => "timed_out",
    "[CLI] result=cancelled" => "cancelled",
  )
  recovery = shared.merge(
    "[CLI] result=recovered" => "recovered",
    "[CLI] result=no_recovery_journal" => "no_recovery_journal",
  )
  fixed = mode == :live ? live : recovery
  return fixed.fetch(line) if fixed.key?(line)

  return nil unless mode == :live

  match = line.match(/\A\[CLI\] result=failed stage=([a-z_]+)\z/)
  return nil unless match && FAILURE_STAGES.include?(match[1])

  "failed_#{match[1]}"
end

def require_predecessor(positions, checkpoint, predecessor)
  return unless positions.key?(checkpoint)

  reject("checkpoint dependency is missing") unless positions.key?(predecessor)
  reject("checkpoint order is invalid") unless positions.fetch(predecessor) < positions.fetch(checkpoint)
end

arguments = ARGV.dup
usage unless [2, 3].include?(arguments.length)
usage unless arguments[0] == "--transcript"
require_accepted = arguments.length == 3
usage if require_accepted && arguments[2] != "--require-accepted"
transcript_path = arguments[1]
usage if transcript_path.nil? || transcript_path.empty?

begin
  path_metadata = File.lstat(transcript_path)
rescue SystemCallError
  reject("transcript is unavailable")
end
validate_file_metadata(path_metadata)

flags = File::RDONLY | File::NOFOLLOW
flags |= File::CLOEXEC if File.const_defined?(:CLOEXEC)

bytes = nil
opened_metadata = nil
post_read_metadata = nil
begin
  File.open(transcript_path, flags) do |file|
    opened_metadata = file.stat
    validate_file_metadata(opened_metadata)
    reject("transcript path changed before descriptor anchoring") unless
      path_metadata.dev == opened_metadata.dev && path_metadata.ino == opened_metadata.ino
    bytes = file.read(MAXIMUM_BYTES + 1)
    post_read_metadata = file.stat
  end
rescue Errno::ELOOP
  reject("transcript must not be a symbolic link")
rescue SystemCallError
  reject("transcript could not be read through a no-follow descriptor")
end

reject("transcript read was incomplete") unless bytes && bytes.bytesize == opened_metadata.size
reject("transcript exceeded the 64 KiB read boundary") if bytes.bytesize > MAXIMUM_BYTES
reject("transcript changed while it was read") unless
  opened_metadata.dev == post_read_metadata.dev &&
    opened_metadata.ino == post_read_metadata.ino &&
    opened_metadata.size == post_read_metadata.size &&
    opened_metadata.uid == post_read_metadata.uid &&
    opened_metadata.mode == post_read_metadata.mode &&
    opened_metadata.nlink == post_read_metadata.nlink

begin
  final_path_metadata = File.lstat(transcript_path)
rescue SystemCallError
  reject("transcript path changed after descriptor read")
end
reject("transcript path changed after descriptor read") unless
  final_path_metadata.file? && !final_path_metadata.symlink? &&
    final_path_metadata.dev == opened_metadata.dev && final_path_metadata.ino == opened_metadata.ino

text = bytes.dup.force_encoding(Encoding::UTF_8)
reject("transcript must be valid UTF-8") unless text.valid_encoding?
reject("transcript must use LF line endings") if text.include?("\r")
reject("transcript must end with exactly one LF") unless text.end_with?("\n")
reject("transcript must not contain blank lines") if text.include?("\n\n")

lines = text.lines(chomp: true)
if lines.first(LIVE_PREAMBLE.length) == LIVE_PREAMBLE
  mode = :live
  preamble_length = LIVE_PREAMBLE.length
elsif lines.first(RECOVERY_PREAMBLE.length) == RECOVERY_PREAMBLE
  mode = :recovery
  preamble_length = RECOVERY_PREAMBLE.length
else
  reject("transcript preamble is missing or altered")
end
reject("--require-accepted rejects recovery transcripts") if
  require_accepted && mode == :recovery

body = lines.drop(preamble_length)
reject("transcript terminal result is missing") if body.empty?

terminal = body.last
kind = terminal_kind(terminal, mode)
reject("transcript terminal result is not allowlisted") unless kind

allowed_checkpoints = mode == :live ? LIVE_CHECKPOINTS : RECOVERY_CHECKPOINTS
checkpoint_lines = body[0...-1]
checkpoints = checkpoint_lines.map do |line|
  match = line.match(/\A\[CLI\] checkpoint=([a-z_]+)\z/)
  reject("transcript contains a non-allowlisted line") unless
    match && allowed_checkpoints.include?(match[1])
  match[1]
end
reject("transcript contains a duplicate checkpoint") unless checkpoints.uniq.length == checkpoints.length

positions = checkpoints.each_with_index.to_h
if mode == :live
  require_predecessor(positions, "server_started", "trust_anchor_validated")
  require_predecessor(positions, "tunnel_started", "server_started")
  require_predecessor(positions, "recovery_journal_persisted", "tunnel_started")
  require_predecessor(positions, "registration_started", "recovery_journal_persisted")
  require_predecessor(positions, "signed_registration_probe", "registration_started")
  require_predecessor(positions, "registration_accepted", "registration_started")
  require_predecessor(positions, "task_created", "registration_accepted")
  require_predecessor(positions, "task_stopped_finish", "task_created")
  require_predecessor(positions, "task_stopped_ask", "task_created")
  require_predecessor(positions, "webhook_deleted", "registration_accepted")
  require_predecessor(positions, "recovery_journal_cleared", "webhook_deleted")
  require_predecessor(positions, "manual_webhook_review_required", "transports_stopped")

  if positions.key?("signed_registration_probe") && positions.key?("registration_accepted")
    reject("signed registration probe must precede registration acceptance") unless
      positions.fetch("signed_registration_probe") < positions.fetch("registration_accepted")
  end
  if positions.key?("recovery_journal_cleared") && positions.key?("transports_stopped")
    reject("journal cleanup must precede local transport shutdown") unless
      positions.fetch("recovery_journal_cleared") < positions.fetch("transports_stopped")
  end
  if positions.key?("transports_stopped")
    permitted_after_stop = positions.key?("manual_webhook_review_required") ? 1 : 0
    reject("transports_stopped must be the final cleanup checkpoint") unless
      positions.fetch("transports_stopped") == checkpoints.length - 1 - permitted_after_stop
  end

  manual_checkpoint = positions.key?("manual_webhook_review_required")
  manual_result = kind == "manual_webhook_review_required"
  reject("manual-review checkpoint and result must agree") unless
    manual_checkpoint == manual_result
  reject("preflight rejection cannot follow lifecycle checkpoints") if
    %w[credential_rejected journal_rejected].include?(kind) && !checkpoints.empty?

  if kind == "accepted"
    reject("accepted transcript does not contain the exact required checkpoint set") unless
      checkpoints.sort == ACCEPTED_CHECKPOINTS.sort
    reject("accepted transcript has an invalid checkpoint count") unless
      checkpoints.length == ACCEPTED_CHECKPOINTS.length
    reject("accepted transcript must persist before registration") unless
      positions.fetch("recovery_journal_persisted") < positions.fetch("registration_started")
    reject("accepted transcript must clear journal after deletion") unless
      positions.fetch("webhook_deleted") < positions.fetch("recovery_journal_cleared")
    reject("accepted transcript must clear journal before stopping transports") unless
      positions.fetch("recovery_journal_cleared") < positions.fetch("transports_stopped")
  end
else
  recovered_bound = %w[
    recovery_journal_validated
    webhook_deleted
    recovery_journal_cleared
  ]
  recovered_discovered = %w[
    recovery_journal_validated
    recovery_inventory_checked
    recovery_webhook_bound
    webhook_deleted
    recovery_journal_cleared
  ]
  manual_paths = [
    %w[manual_webhook_review_required],
    %w[recovery_journal_validated manual_webhook_review_required],
    %w[recovery_journal_validated recovery_inventory_checked manual_webhook_review_required],
    %w[recovery_journal_validated recovery_inventory_checked recovery_webhook_bound manual_webhook_review_required],
    %w[recovery_journal_validated webhook_deleted manual_webhook_review_required],
    %w[recovery_journal_validated recovery_inventory_checked recovery_webhook_bound webhook_deleted manual_webhook_review_required],
  ]

  case kind
  when "recovered"
    reject("recovered transcript has an invalid checkpoint path") unless
      checkpoints == recovered_bound || checkpoints == recovered_discovered
  when "manual_webhook_review_required"
    reject("manual-review checkpoint and result must agree") unless
      manual_paths.include?(checkpoints)
  when "no_recovery_journal", "credential_rejected", "journal_rejected"
    reject("recovery preflight result cannot follow checkpoints") unless checkpoints.empty?
  else
    reject("recovery transcript terminal result is invalid")
  end
end

reject("transcript did not record an accepted live run") if
  require_accepted && kind != "accepted"

if mode == :live && kind == "accepted"
  puts "Manus live acceptance transcript: ACCEPTED"
else
  label = mode == :live ? "live acceptance" : "live acceptance recovery"
  puts "Manus #{label} transcript: VALID result=#{kind}"
end
