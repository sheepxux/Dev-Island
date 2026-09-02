#!/usr/bin/env ruby

require "digest"
require "yaml"

# Treat any use of the secrets context inside one GitHub expression as secret
# exposure. This intentionally covers dot access, bracket access and whole-
# context helpers such as toJSON(secrets).
SECRET_EXPRESSION = /\$\{\{(?:(?!\}\}).)*\bsecrets\b(?:(?!\}\}).)*\}\}/im
PINNED_RUN_SHA256 = {
  "Prepare pinned create-dmg" =>
    "0590e81bdecec544ff27d86f1bde9fa73a98057d3d08e088609c3d22e8a07fef",
  "Setup App signing keychain" =>
    "dee165d6e2565777cec204348731ff57ed1ed087fcd57b5a44fd6ae55b2575ba",
  "Build .app (universal)" =>
    "0d215be302f7d049ee24e5e44fa1b143b01b6488a7c573d05b76945ea1e59d1c",
  "Verify app dependency closure" =>
    "d8d81ea616fa4cb6df7a3b70095acc76fc18036f6389c2b5426980169eb2e229",
  "Codesign with Developer ID" =>
    "42a34d84a9dbff696e67b9e5ead0b6842d4c94dc31217081f78a2318dbb3c9d9",
  "Notarize" =>
    "5061027e02dfb55858bcc8a98e5eb59808d94075669c4a90369db251970e0c5d",
  "Hermetically launch notarized production app" =>
    "d4a675156b40bd41f5f00bc1c290c50d7b4e7073e4951b53d70f56cfcc0ae4d6",
  "Tear down App signing keychain" =>
    "fcdc6469868124b66ee209db88b8710a88de110f9c0684b67f82a3cf1a1f87a8",
  "Package DMG" =>
    "eac34e6a2e7f3091823cfe59634a8f1ac075dbd1959081675e31aea14e26d5ac",
  "Setup DMG signing keychain" =>
    "81e4df6d030f97971515974570445b8199249e1d3ca082f5fab8020aa9a857cc",
  "Sign + notarize DMG" =>
    "8497e93082ec218c02f97bff9da8a3b0e8ec26e7fbda3c3ad995c9ab57970bc3",
  "Tear down DMG signing keychain" =>
    "addbb0eac6f1235f652b879162edc163aebd144120877281778d38d761a5fad2",
  "Tear down signing keychain" =>
    "a28e7a0e6edf01de873df4d7a0fae12c6be413c50a8688536b113c826f2d08fd"
}.freeze

APP_SIGNING_WINDOW_NAMES = [
  "Setup App signing keychain",
  "Build .app (universal)",
  "Verify app dependency closure",
  "Codesign with Developer ID",
  "Notarize",
  "Hermetically launch notarized production app",
  "Tear down App signing keychain"
].freeze

APP_SIGNING_ENV = {
  "P12_BASE64" => "${{ secrets.SIGNING_CERTIFICATE_P12_BASE64 }}",
  "P12_PASSWORD" => "${{ secrets.SIGNING_CERTIFICATE_P12_PASSWORD }}",
  "KEYCHAIN_PASSWORD" => "${{ secrets.KEYCHAIN_PASSWORD }}"
}.freeze

PACKAGE_DMG_ENV = {
  "CREATE_DMG_ROOT" => "${{ steps.create_dmg_tool.outputs.root }}",
  "CREATE_DMG_EXECUTABLE" => "${{ steps.create_dmg_tool.outputs.executable }}",
  "CREATE_DMG_MANIFEST" => "${{ steps.create_dmg_tool.outputs.manifest }}"
}.freeze

SIGN_DMG_ENV = {
  "APPLE_ID" => "${{ secrets.APPLE_ID }}",
  "APPLE_TEAM_ID" => "${{ secrets.APPLE_TEAM_ID }}",
  "APPLE_APP_PASSWORD" => "${{ secrets.APPLE_APP_PASSWORD }}",
  "STABLE_DMG" => "${{ steps.unsigned_dmg.outputs.path }}",
  "UNSIGNED_DMG_SHA256" => "${{ steps.unsigned_dmg.outputs.sha256 }}"
}.freeze

BUILD_APP_ENV = {
  "SPARKLE_PUBLIC_ED_KEY" => "${{ secrets.SPARKLE_PUBLIC_ED_KEY }}"
}.freeze

CODESIGN_APP_ENV = {
  "APPLE_TEAM_ID" => "${{ secrets.APPLE_TEAM_ID }}"
}.freeze

NOTARIZE_APP_ENV = {
  "APPLE_ID" => "${{ secrets.APPLE_ID }}",
  "APPLE_TEAM_ID" => "${{ secrets.APPLE_TEAM_ID }}",
  "APPLE_APP_PASSWORD" => "${{ secrets.APPLE_APP_PASSWORD }}"
}.freeze

def fail(message)
  warn "error: #{message}"
  exit 1
end

def any_string_matches?(value, pattern)
  case value
  when Hash
    value.any? do |key, child|
      any_string_matches?(key, pattern) || any_string_matches?(child, pattern)
    end
  when Array
    value.any? { |child| any_string_matches?(child, pattern) }
  when String
    value.match?(pattern)
  else
    false
  end
end

def require_step_keys(step, expected_keys, label)
  return if step.keys.sort == expected_keys.sort

  fail("#{label} step shape does not match the reviewed boundary")
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
fail("workflow and release job environments must be absent") if
  workflow.key?("env") || job.key?("env")
fail("workflow and release job run defaults must be absent") if
  workflow.key?("defaults") || job.key?("defaults")
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
prepare_index = index_for_name.call("Prepare pinned create-dmg")
app_keychain_index = index_for_name.call("Setup App signing keychain")
launch_smoke_index = index_for_name.call("Hermetically launch notarized production app")
app_teardown_index = index_for_name.call("Tear down App signing keychain")
package_index = index_for_name.call("Package DMG")
dmg_keychain_index = index_for_name.call("Setup DMG signing keychain")
dmg_sign_index = index_for_name.call("Sign + notarize DMG")
dmg_teardown_index = index_for_name.call("Tear down DMG signing keychain")
zip_index = index_for_name.call("Package release zip")
publication_index = index_for_name.call("Create GitHub Release")
final_teardown_index = index_for_name.call("Tear down signing keychain")

ordered_indexes = [
  checkout_index,
  gates_index,
  prepare_index,
  credentials_index,
  app_keychain_index,
  launch_smoke_index,
  app_teardown_index,
  package_index,
  dmg_keychain_index,
  dmg_sign_index,
  dmg_teardown_index,
  zip_index,
  publication_index,
  final_teardown_index
]
fail("release signing boundary ordering is invalid") unless
  ordered_indexes.each_cons(2).all? { |left, right| left < right }
fail("App teardown, DMG packaging, keychain re-import, and signing must be consecutive") unless
  app_teardown_index == launch_smoke_index + 1 &&
    package_index == app_teardown_index + 1 &&
    dmg_keychain_index == package_index + 1 &&
    dmg_sign_index == dmg_keychain_index + 1 &&
    dmg_teardown_index == dmg_sign_index + 1

credentialed_app_steps = steps[app_keychain_index..app_teardown_index]
fail("a third-party action must not run while the App signing keychain is available") if
  credentialed_app_steps.any? { |step| step.key?("uses") }

prepare = steps[prepare_index]
require_step_keys(prepare, %w[name id run], "Prepare pinned create-dmg")
fail("Prepare pinned create-dmg must expose only create_dmg_tool outputs") unless
  prepare["id"] == "create_dmg_tool" && !prepare.key?("env")

app_keychain = steps[app_keychain_index]
require_step_keys(app_keychain, %w[name env run], "Setup App signing keychain")
fail("App signing keychain environment does not match the reviewed boundary") unless
  app_keychain["env"] == APP_SIGNING_ENV

app_teardown = steps[app_teardown_index]
require_step_keys(app_teardown, %w[name run], "Tear down App signing keychain")
fail("App signing keychain teardown must be secret-free") if
  app_teardown.key?("env") || any_string_matches?(app_teardown, SECRET_EXPRESSION)

package = steps[package_index]
require_step_keys(package, %w[name id env run], "Package DMG")
fail("Package DMG step must not reference release secrets") if
  any_string_matches?(package, SECRET_EXPRESSION)
fail("Package DMG must expose only the unsigned_dmg outputs") unless
  package["id"] == "unsigned_dmg"
fail("Package DMG environment must match the three pinned create-dmg outputs exactly") unless
  package["env"] == PACKAGE_DMG_ENV

dmg_keychain = steps[dmg_keychain_index]
require_step_keys(dmg_keychain, %w[name env run], "Setup DMG signing keychain")
fail("DMG signing keychain environment does not match the reviewed boundary") unless
  dmg_keychain["env"] == APP_SIGNING_ENV

dmg_sign = steps[dmg_sign_index]
require_step_keys(dmg_sign, %w[name id env run], "Sign + notarize DMG")
fail("DMG signing environment does not match the reviewed artifact and credential boundary") unless
  dmg_sign["id"] == "dmg" && dmg_sign["env"] == SIGN_DMG_ENV

dmg_teardown = steps[dmg_teardown_index]
require_step_keys(dmg_teardown, %w[name run], "Tear down DMG signing keychain")
fail("DMG signing keychain teardown must be secret-free") if
  dmg_teardown.key?("env") || any_string_matches?(dmg_teardown, SECRET_EXPRESSION)

final_teardown = steps[final_teardown_index]
require_step_keys(final_teardown, %w[name if run], "Tear down signing keychain")
fail("final signing keychain teardown must always run") unless
  final_teardown["if"] == "always()" && !final_teardown.key?("env")

PINNED_RUN_SHA256.each do |name, expected_sha256|
  step = steps[index_for_name.call(name)]
  run = step["run"]
  fail("#{name} must contain one reviewed run body") unless run.is_a?(String) && !run.empty?
  actual_sha256 = Digest::SHA256.hexdigest(run.b)
  fail("#{name} run body does not match the reviewed SHA-256") unless
    actual_sha256 == expected_sha256
end

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
