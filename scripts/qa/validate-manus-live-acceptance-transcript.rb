#!/usr/bin/env ruby

MINIMUM_BYTES = 1
MAXIMUM_BYTES = 64 * 1_024

PREAMBLE = [
  "[CLI] Manus v2 live acceptance",
  "[CLI] This creates a temporary public tunnel and webhook, then removes both.",
  "[CLI] During the run, create one task that finishes and one task that pauses for input.",
  "[CLI] Provider identifiers, callback addresses, payload text and raw errors are never printed.",
].freeze

CHECKPOINTS = [
  "trust_anchor_validated",
  "server_started",
  "tunnel_started",
  "registration_started",
  "signed_registration_probe",
  "registration_accepted",
  "task_created",
  "task_stopped_finish",
  "task_stopped_ask",
  "webhook_deleted",
  "transports_stopped",
  "manual_webhook_review_required",
].freeze

ACCEPTED_CHECKPOINTS = (CHECKPOINTS - ["manual_webhook_review_required"]).freeze
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

def terminal_kind(line)
  fixed = {
    "[CLI] credential_rejected" => "credential_rejected",
    "[CLI] result=accepted" => "accepted",
    "[CLI] result=manual_webhook_review_required" => "manual_webhook_review_required",
    "[CLI] result=incomplete_cleanup" => "incomplete_cleanup",
    "[CLI] result=timed_out" => "timed_out",
    "[CLI] result=cancelled" => "cancelled",
  }
  return fixed.fetch(line) if fixed.key?(line)

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
reject("transcript preamble is missing or altered") unless lines.first(PREAMBLE.length) == PREAMBLE
body = lines.drop(PREAMBLE.length)
reject("transcript terminal result is missing") if body.empty?

terminal = body.last
kind = terminal_kind(terminal)
reject("transcript terminal result is not allowlisted") unless kind

checkpoint_lines = body[0...-1]
checkpoints = checkpoint_lines.map do |line|
  match = line.match(/\A\[CLI\] checkpoint=([a-z_]+)\z/)
  reject("transcript contains a non-allowlisted line") unless match && CHECKPOINTS.include?(match[1])
  match[1]
end
reject("transcript contains a duplicate checkpoint") unless checkpoints.uniq.length == checkpoints.length

positions = checkpoints.each_with_index.to_h
require_predecessor(positions, "server_started", "trust_anchor_validated")
require_predecessor(positions, "tunnel_started", "server_started")
require_predecessor(positions, "registration_started", "tunnel_started")
require_predecessor(positions, "signed_registration_probe", "registration_started")
require_predecessor(positions, "registration_accepted", "registration_started")
require_predecessor(positions, "task_created", "registration_accepted")
require_predecessor(positions, "task_stopped_finish", "task_created")
require_predecessor(positions, "task_stopped_ask", "task_created")
require_predecessor(positions, "webhook_deleted", "registration_accepted")
require_predecessor(positions, "manual_webhook_review_required", "transports_stopped")

if positions.key?("signed_registration_probe") && positions.key?("registration_accepted")
  reject("signed registration probe must precede registration acceptance") unless
    positions.fetch("signed_registration_probe") < positions.fetch("registration_accepted")
end
if positions.key?("webhook_deleted") && positions.key?("transports_stopped")
  reject("remote cleanup must precede local transport shutdown") unless
    positions.fetch("webhook_deleted") < positions.fetch("transports_stopped")
end
if positions.key?("transports_stopped")
  permitted_after_stop = positions.key?("manual_webhook_review_required") ? 1 : 0
  reject("transports_stopped must be the final cleanup checkpoint") unless
    positions.fetch("transports_stopped") == checkpoints.length - 1 - permitted_after_stop
end

manual_checkpoint = positions.key?("manual_webhook_review_required")
manual_result = kind == "manual_webhook_review_required"
reject("manual-review checkpoint and result must agree") unless manual_checkpoint == manual_result
reject("credential rejection cannot follow lifecycle checkpoints") if
  kind == "credential_rejected" && !checkpoints.empty?

if kind == "accepted"
  reject("accepted transcript does not contain the exact required checkpoint set") unless
    checkpoints.sort == ACCEPTED_CHECKPOINTS.sort
  reject("accepted transcript has an invalid checkpoint count") unless
    checkpoints.length == ACCEPTED_CHECKPOINTS.length
  reject("accepted transcript must delete the webhook before stopping transports") unless
    positions.fetch("webhook_deleted") < positions.fetch("transports_stopped")
end

reject("transcript did not record an accepted live run") if require_accepted && kind != "accepted"

if kind == "accepted"
  puts "Manus live acceptance transcript: ACCEPTED"
else
  puts "Manus live acceptance transcript: VALID result=#{kind}"
end
