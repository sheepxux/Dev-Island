#!/usr/bin/env ruby

require "json"
require "time"

STEP_ORDER = %w[
  toolchain
  dependencies
  sparkle-update
  security
  tests
  performance-build
  app-build
  bundle
  brand
  sbom
  isolation
  hygiene
].freeze

STEP_LABELS = {
  "toolchain" => "Toolchain",
  "dependencies" => "Dependency resolution",
  "sparkle-update" => "Disposable Sparkle old-to-new update",
  "security" => "Security and privacy invariants",
  "tests" => "Swift tests",
  "performance-build" => "Performance fixture build + launch smoke",
  "app-build" => "Universal app build + Production launch smoke",
  "bundle" => "App bundle verification",
  "brand" => "Bundled brand asset inventory",
  "sbom" => "SPDX generation",
  "isolation" => "Performance fixture isolation",
  "hygiene" => "Repository hygiene",
}.freeze

REPRODUCE = {
  "toolchain" => "xcodebuild -version && swift --version",
  "dependencies" => "git ls-files --error-unmatch VERSION scripts/release/validate-product-version.rb Package.resolved && ./scripts/release/validate-product-version.rb --version-file VERSION && swift package resolve && git diff --exit-code -- Package.resolved",
  "sparkle-update" => "./scripts/ci/verify-sparkle-old-to-new-update.sh",
  "security" => "./scripts/ci/verify-security-invariants.sh",
  "tests" => "./scripts/ci/run-authoritative-tests.sh",
  "performance-build" => "DEV_ISLAND_PERFORMANCE_QA=1 BUILD_DIR=/tmp/dev-island-performance ./scripts/build-app.sh && DEV_ISLAND_PERF_ALLOW_LOCKED=1 ./scripts/qa/measure-app-performance.sh '/tmp/dev-island-performance/Dev Island.app/Contents/MacOS/IslandApp' idle /tmp/dev-island-launch-smoke.csv 0 8",
  "app-build" => "BUILD_DIR=/tmp/dev-island-app ./scripts/build-app.sh && ./scripts/qa/measure-app-performance.sh '/tmp/dev-island-app/Dev Island.app/Contents/MacOS/IslandApp' production-launch-smoke /tmp/dev-island-production-launch-smoke.csv 0 8",
  "bundle" => "Review the Verify app bundle step in .github/workflows/ci.yml",
  "brand" => "Review the Verify bundled brand asset inventory step in .github/workflows/ci.yml",
  "sbom" => "Review the Generate and verify SPDX SBOM step in .github/workflows/ci.yml",
  "isolation" => "./scripts/ci/verify-performance-fixture-isolation.sh PRODUCTION_APP PERFORMANCE_APP",
  "hygiene" => "git diff --check && test -z \"$(git status --porcelain --untracked-files=no)\"",
}.freeze

def fail(message)
  warn "error: #{message}"
  exit 1
end

def usage
  warn <<~TEXT
    Usage: generate-ci-diagnostics.rb --output-dir DIR --repository OWNER/REPO \
      --run-id ID --run-attempt N --event EVENT --ref REF --sha SHA \
      --runner-os OS --runner-arch ARCH --security-log FILE|none \
      --test-log FILE|none --step ID=OUTCOME [--step ID=OUTCOME ...]
  TEXT
  exit 64
end

options = {}
steps = []
allowed = %w[
  --output-dir
  --repository
  --run-id
  --run-attempt
  --event
  --ref
  --sha
  --runner-os
  --runner-arch
  --security-log
  --test-log
]
index = 0
while index < ARGV.length
  key = ARGV[index]
  usage if index + 1 >= ARGV.length
  value = ARGV[index + 1]
  if key == "--step"
    steps << value
  elsif allowed.include?(key) && !options.key?(key)
    options[key] = value
  else
    usage
  end
  index += 2
end
usage unless options.keys.sort == allowed.sort

repository = options.fetch("--repository")
run_id = options.fetch("--run-id")
run_attempt = options.fetch("--run-attempt")
event = options.fetch("--event")
ref = options.fetch("--ref")
sha = options.fetch("--sha")
runner_os = options.fetch("--runner-os")
runner_arch = options.fetch("--runner-arch")

fail("repository identifier is invalid") unless repository.match?(/\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\z/)
fail("run ID is invalid") unless run_id.match?(/\A[1-9][0-9]{0,19}\z/)
fail("run attempt is invalid") unless run_attempt.match?(/\A[1-9][0-9]{0,5}\z/)
fail("event name is invalid") unless event.match?(/\A[A-Za-z0-9_]{1,64}\z/)
fail("Git ref is invalid") unless ref.match?(/\Arefs\/[A-Za-z0-9._\/@+-]{1,240}\z/) && !ref.include?("..")
fail("source SHA is invalid") unless sha.match?(/\A[0-9a-f]{40}\z/)
fail("runner OS is invalid") unless runner_os.match?(/\A[A-Za-z0-9_.-]{1,32}\z/)
fail("runner architecture is invalid") unless runner_arch.match?(/\A[A-Za-z0-9_.-]{1,32}\z/)

parsed_steps = steps.map do |entry|
  match = entry.match(/\A([a-z-]+)=(success|failure|cancelled|skipped)\z/)
  fail("CI step outcome is invalid: #{entry}") unless match
  {"id" => match[1], "outcome" => match[2]}
end
fail("CI diagnostic step set is incomplete or reordered") unless parsed_steps.map { |step| step["id"] } == STEP_ORDER

def unavailable_log(status)
  {"content" => nil, "sourceStatus" => status}
end

def read_log(path, maximum_bytes)
  return unavailable_log("not-provided") if path == "none"

  begin
    initial = File.lstat(path)
  rescue Errno::ENOENT
    return unavailable_log("missing")
  end
  return unavailable_log("unsafe-file") unless initial.file? && !initial.symlink?

  flags = File::RDONLY | File::NOFOLLOW | File::NONBLOCK
  begin
    File.open(path, flags) do |file|
      metadata = file.stat
      safe = metadata.file? &&
        metadata.uid == Process.euid &&
        metadata.nlink == 1 &&
        (metadata.mode & 0o022).zero?
      return unavailable_log("unsafe-file") unless safe
      return unavailable_log("empty") if metadata.size.zero?
      return unavailable_log("oversized") if metadata.size > maximum_bytes

      content = file.pread(metadata.size, 0)
      return unavailable_log("changed") unless content.bytesize == metadata.size

      after = file.stat
      stable = after.dev == metadata.dev &&
        after.ino == metadata.ino &&
        after.size == metadata.size &&
        after.mtime == metadata.mtime &&
        after.ctime == metadata.ctime
      return unavailable_log("changed") unless stable

      return {
        "content" => content.force_encoding(Encoding::UTF_8).scrub,
        "sourceStatus" => "available",
      }
    end
  rescue Errno::ENOENT
    unavailable_log("missing")
  rescue Errno::ELOOP, Errno::EACCES, Errno::EPERM, Errno::EISDIR, Errno::ENXIO, IOError, SystemCallError
    unavailable_log("unsafe-file")
  end
end

security_source = read_log(options.fetch("--security-log"), 2 * 1_024 * 1_024)
test_source = read_log(options.fetch("--test-log"), 16 * 1_024 * 1_024)
security_log = security_source.fetch("content")
test_log = test_source.fetch("content")

security_summary = {
  "available" => !security_log.nil?,
  "sourceStatus" => security_source.fetch("sourceStatus"),
  "passedGates" => [],
  "errorMarkerCount" => 0,
}
if security_log
  security_log.each_line do |line|
    stripped = line.strip
    if (match = stripped.match(/\A([A-Za-z][A-Za-z0-9 &+()\/-]{1,120}): PASS\z/))
      security_summary["passedGates"] << match[1]
    end
    security_summary["errorMarkerCount"] += 1 if stripped.start_with?("::error::")
  end
  security_summary["passedGates"] = security_summary["passedGates"].uniq.first(64)
end

test_summary = {
  "available" => !test_log.nil?,
  "sourceStatus" => test_source.fetch("sourceStatus"),
  "executed" => nil,
  "failures" => nil,
  "unexpected" => nil,
  "failedCases" => [],
}
if test_log
  totals = test_log.scan(/Executed ([0-9]+) tests, with ([0-9]+) failures \(([0-9]+) unexpected\)/)
  unless totals.empty?
    executed, failures, unexpected = totals.last
    test_summary["executed"] = executed.to_i
    test_summary["failures"] = failures.to_i
    test_summary["unexpected"] = unexpected.to_i
  end
  failed_cases = test_log.scan(/Test Case '([^'\n]{1,300})' failed/).flatten
  test_summary["failedCases"] = failed_cases.map do |name|
    name.gsub(/[^A-Za-z0-9_.:\-\[\] ]/, "?")
  end.uniq.first(100)
end

steps_with_details = parsed_steps.map do |step|
  step.merge(
    "label" => STEP_LABELS.fetch(step["id"]),
    "reproduce" => REPRODUCE.fetch(step["id"])
  )
end
first_failure = steps_with_details.find { |step| %w[failure cancelled].include?(step["outcome"]) }
job_status = if steps_with_details.any? { |step| step["outcome"] == "failure" }
  "failure"
elsif steps_with_details.any? { |step| step["outcome"] == "cancelled" }
  "cancelled"
elsif steps_with_details.any? { |step| step["outcome"] == "skipped" }
  "incomplete"
else
  "success"
end

document = {
  "schemaVersion" => 2,
  "generatedAt" => Time.now.utc.iso8601,
  "repository" => repository,
  "run" => {
    "id" => run_id,
    "attempt" => run_attempt.to_i,
    "event" => event,
    "ref" => ref,
    "sourceSha" => sha,
  },
  "runner" => {
    "os" => runner_os,
    "architecture" => runner_arch,
  },
  "status" => job_status,
  "steps" => steps_with_details,
  "firstFailure" => first_failure,
  "security" => security_summary,
  "tests" => test_summary,
  "privacy" => {
    "rawLogsIncluded" => false,
    "environmentIncluded" => false,
    "secretsIncluded" => false,
    "userAppDataIncluded" => false,
  },
}

output_directory = options.fetch("--output-dir")
fail("diagnostic output path must be absolute") unless output_directory.start_with?("/")
parent = File.dirname(output_directory)
begin
  parent_metadata = File.lstat(parent)
rescue Errno::ENOENT
  fail("diagnostic output parent does not exist")
end
fail("diagnostic output parent must be a regular non-symlink directory") unless parent_metadata.directory? && !parent_metadata.symlink?
begin
  File.lstat(output_directory)
  fail("refusing to overwrite an existing diagnostic output")
rescue Errno::ENOENT
  # Expected: this tool creates one new, isolated output directory.
end
Dir.mkdir(output_directory, 0o700)

def write_new(path, contents)
  File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
    file.write(contents)
    file.flush
    file.fsync
  end
end

json = JSON.pretty_generate(document) + "\n"
fail("CI diagnostic JSON exceeds 128 KiB") if json.bytesize > 128 * 1_024
write_new(File.join(output_directory, "summary.json"), json)

markdown = String.new
markdown << "# Dev Island CI diagnostics\n\n"
markdown << "Status: **#{job_status}**  \n"
markdown << "Source: `#{sha}`  \n"
markdown << "Ref: `#{ref}`  \n"
markdown << "Run: `#{run_id}` attempt `#{run_attempt}`\n\n"
markdown << "| Gate | Outcome |\n|---|---|\n"
steps_with_details.each do |step|
  markdown << "| #{step["label"]} | `#{step["outcome"]}` |\n"
end
markdown << "\n"
if first_failure
  markdown << "First failed gate: **#{first_failure["label"]}**\n\n"
  markdown << "Reproduce:\n\n```sh\n#{first_failure["reproduce"]}\n```\n\n"
end
if test_summary["executed"]
  markdown << "Tests: #{test_summary["executed"]} executed, #{test_summary["failures"]} failures, #{test_summary["unexpected"]} unexpected.\n\n"
end
unless test_summary["failedCases"].empty?
  markdown << "Failed cases:\n\n"
  test_summary["failedCases"].each { |name| markdown << "- `#{name}`\n" }
  markdown << "\n"
end
unless security_summary["passedGates"].empty?
  markdown << "Security sub-gates completed: #{security_summary["passedGates"].length}.\n\n"
end
markdown << "This bundle contains no raw logs, environment dump, secrets, or user App data.\n"
fail("CI diagnostic README exceeds 64 KiB") if markdown.bytesize > 64 * 1_024
write_new(File.join(output_directory, "README.md"), markdown)

puts "CI diagnostics: #{output_directory}"
