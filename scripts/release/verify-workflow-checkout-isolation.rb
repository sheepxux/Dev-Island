#!/usr/bin/env ruby

require "yaml"

def fail(message)
  warn "error: #{message}"
  exit 1
end

unless ARGV.length == 2 && ARGV[0] == "--workflow"
  warn "Usage: verify-workflow-checkout-isolation.rb --workflow FILE"
  exit 64
end

workflow_path = ARGV[1]
begin
  metadata = File.lstat(workflow_path)
rescue Errno::ENOENT
  fail("release workflow does not exist")
end
fail("release workflow must be a regular non-symlink file") unless metadata.file? && !metadata.symlink?
fail("release workflow size is invalid") unless metadata.size.between?(1, 1_048_576)

begin
  workflow = YAML.safe_load(
    File.binread(workflow_path),
    permitted_classes: [],
    permitted_symbols: [],
    aliases: false
  )
rescue Psych::Exception
  fail("release workflow is not valid safe YAML")
end
fail("release workflow root must be a mapping") unless workflow.is_a?(Hash)

jobs = workflow["jobs"]
fail("release workflow jobs mapping is missing") unless jobs.is_a?(Hash)
job = jobs["build-sign-release"]
fail("build-sign-release job is missing") unless job.is_a?(Hash)
steps = job["steps"]
fail("release job steps are missing") unless steps.is_a?(Array) && !steps.empty?
fail("release job contains a malformed step") unless steps.all? { |step| step.is_a?(Hash) }

checkout_indexes = steps.each_index.select do |index|
  steps[index]["uses"].to_s.start_with?("actions/checkout@")
end
fail("release job must contain exactly one checkout step") unless checkout_indexes.length == 1
checkout_index = checkout_indexes.first
checkout = steps[checkout_index]
fail("checkout must be the first release step") unless checkout_index.zero?
fail("checkout action must be pinned to a full commit SHA") unless
  checkout["uses"].to_s.match?(/\Aactions\/checkout@[0-9a-f]{40}\z/)
checkout_with = checkout["with"]
fail("checkout settings are missing") unless checkout_with.is_a?(Hash)
fail("release checkout must set persist-credentials to false") unless
  checkout_with["persist-credentials"] == false
fail("release checkout must not override its token input") if checkout_with.key?("token")
fail("release checkout must not expose an environment") if checkout.key?("env")

index_for_name = lambda do |name|
  matches = steps.each_index.select { |index| steps[index]["name"] == name }
  fail("release job must contain exactly one #{name} step") unless matches.length == 1
  matches.first
end

gates_index = index_for_name.call("Repository release gates")
credentials_index = index_for_name.call("Validate release credentials")
publication_index = index_for_name.call("Create GitHub Release")
fail("release credential ordering is invalid") unless
  checkout_index < gates_index && gates_index < credentials_index && credentials_index < publication_index

publication = steps[publication_index]
fail("GitHub Release action must be pinned to a full commit SHA") unless
  publication["uses"].to_s.match?(/\Asoftprops\/action-gh-release@[0-9a-f]{40}\z/)
publication_env = publication["env"]
fail("GitHub Release action must have one scoped token environment") unless
  publication_env.is_a?(Hash) && publication_env.keys == ["GITHUB_TOKEN"]
fail("GitHub Release token must come from the job-scoped GitHub secret") unless
  publication_env["GITHUB_TOKEN"] == "${{ secrets.GITHUB_TOKEN }}"

token_name = lambda do |name|
  normalized = name.to_s.upcase
  normalized == "GITHUB_TOKEN" || normalized == "GH_TOKEN" ||
    normalized.include?("TOKEN") || normalized.end_with?("PAT")
end
token_expression = /\$\{\{\s*(?:github\.token|secrets\.[A-Z0-9_]*(?:TOKEN|PAT)[A-Z0-9_]*)\s*\}\}/i

[workflow["env"], job["env"]].compact.each do |environment|
  fail("workflow or job environment must be a mapping") unless environment.is_a?(Hash)
  fail("GitHub token must not be exposed at workflow or job scope") unless
    environment.keys.none? { |name| token_name.call(name) }
end

steps.each_with_index do |step, index|
  next if index == publication_index

  environment = step["env"]
  if environment
    fail("step environment must be a mapping") unless environment.is_a?(Hash)
    fail("GitHub token is exposed before final publication") unless
      environment.keys.none? { |name| token_name.call(name) }
  end

  stack = [step]
  until stack.empty?
    value = stack.pop
    case value
    when Hash
      value.each_value { |child| stack << child }
    when Array
      value.each { |child| stack << child }
    when String
      fail("GitHub token expression is exposed outside final publication") if value.match?(token_expression)
    end
  end
end

puts "Release checkout credential isolation: PASS"
