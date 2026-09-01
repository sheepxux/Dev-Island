#!/usr/bin/env ruby

require "json"

def usage
  warn <<~TEXT
    Usage: validate-github-repository-controls.rb \
      --branch-protection FILE --actions-permissions FILE \
      --selected-actions FILE --workflow-permissions FILE --repository FILE
  TEXT
  exit 64
end

arguments = {}
allowed = %w[
  --branch-protection
  --actions-permissions
  --selected-actions
  --workflow-permissions
  --repository
]
index = 0
while index < ARGV.length
  key = ARGV[index]
  usage unless allowed.include?(key) && index + 1 < ARGV.length && !arguments.key?(key)
  arguments[key] = ARGV[index + 1]
  index += 2
end
usage unless arguments.keys.sort == allowed.sort

def load_bounded_json(path, label)
  begin
    metadata = File.lstat(path)
  rescue Errno::ENOENT
    warn "error: #{label} snapshot is missing"
    exit 1
  end
  unless metadata.file? && !metadata.symlink? && metadata.size.between?(1, 2 * 1_024 * 1_024)
    warn "error: #{label} snapshot must be a bounded regular non-symlink file"
    exit 1
  end
  begin
    value = JSON.parse(File.binread(path))
  rescue JSON::ParserError
    warn "error: #{label} snapshot is malformed JSON"
    exit 1
  end
  unless value.is_a?(Hash)
    warn "error: #{label} snapshot root must be a JSON object"
    exit 1
  end
  value
end

branch = load_bounded_json(arguments.fetch("--branch-protection"), "branch protection")
actions = load_bounded_json(arguments.fetch("--actions-permissions"), "Actions permissions")
selected = load_bounded_json(arguments.fetch("--selected-actions"), "selected Actions")
workflow = load_bounded_json(arguments.fetch("--workflow-permissions"), "workflow permissions")
repository = load_bounded_json(arguments.fetch("--repository"), "repository")

findings = []
add = ->(code, message) { findings << [code, message] }

status_checks = branch["required_status_checks"]
if !status_checks.is_a?(Hash)
  add.call("B01", "main does not require the CI status check before merge")
else
  add.call("B02", "required status checks do not require the branch to be current") unless status_checks["strict"] == true
  contexts = Array(status_checks["contexts"])
  contexts.concat(
    Array(status_checks["checks"]).map { |check| check["context"] if check.is_a?(Hash) }.compact
  )
  unless contexts.include?("Tests, security, universal build")
    add.call("B03", "the Dev Island quality job is not a required status check")
  end
end

reviews = branch["required_pull_request_reviews"]
if !reviews.is_a?(Hash)
  add.call("B04", "main can merge without an approving pull-request review")
else
  add.call("B05", "main requires fewer than one approving review") unless reviews["required_approving_review_count"].is_a?(Integer) && reviews["required_approving_review_count"] >= 1
  add.call("B06", "new commits do not dismiss stale approvals") unless reviews["dismiss_stale_reviews"] == true
  add.call("B07", "the last push does not require approval from another reviewer") unless reviews["require_last_push_approval"] == true
end

add.call("B08", "administrators can bypass main branch protection") unless branch.dig("enforce_admins", "enabled") == true
add.call("B09", "review conversations need not be resolved before merge") unless branch.dig("required_conversation_resolution", "enabled") == true
add.call("B10", "main does not require linear history") unless branch.dig("required_linear_history", "enabled") == true
add.call("B11", "force pushes are allowed on main") unless branch.dig("allow_force_pushes", "enabled") == false
add.call("B12", "main can be deleted") unless branch.dig("allow_deletions", "enabled") == false

if actions["enabled"] != true
  add.call("A01", "GitHub Actions is disabled")
elsif actions["allowed_actions"] != "selected"
  add.call("A02", "repository Actions are not restricted to an explicit allowlist")
else
  add.call("A03", "GitHub-owned Actions are not allowed") unless selected["github_owned_allowed"] == true
  add.call("A04", "all verified Marketplace Actions are allowed instead of an exact list") unless selected["verified_allowed"] == false
  expected_external_action = "softprops/action-gh-release@efb35369e0ad2afab669f228072c1b0d510eae64"
  patterns = selected["patterns_allowed"]
  unless patterns.is_a?(Array) && patterns == [expected_external_action]
    add.call("A05", "the only third-party Action must be the exact reviewed release-action commit")
  end
end
add.call("A06", "GitHub Actions does not require full commit-SHA pinning") unless actions["sha_pinning_required"] == true
add.call("A07", "workflow tokens have write permission by default") unless workflow["default_workflow_permissions"] == "read"
add.call("A08", "workflow tokens may approve pull requests") unless workflow["can_approve_pull_request_reviews"] == false

security = repository["security_and_analysis"]
if !security.is_a?(Hash)
  add.call("S01", "repository security-and-analysis settings are unavailable")
else
  add.call("S02", "secret scanning is not enabled") unless security.dig("secret_scanning", "status") == "enabled"
  add.call("S03", "secret-scanning push protection is not enabled") unless security.dig("secret_scanning_push_protection", "status") == "enabled"
  add.call("S04", "Dependabot security updates are not enabled") unless security.dig("dependabot_security_updates", "status") == "enabled"
end

if findings.empty?
  puts "GitHub repository controls: PASS"
  exit 0
end

warn "GitHub repository controls: FAIL (#{findings.length} findings)"
findings.each { |code, message| warn "#{code}: #{message}" }
exit 1
