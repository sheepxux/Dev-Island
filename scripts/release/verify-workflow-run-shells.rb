#!/usr/bin/env ruby

require "open3"
require "yaml"

MAX_WORKFLOW_BYTES = 1_048_576
MAX_RUN_BYTES = 262_144
MAX_YAML_NODES = 20_000
MAX_YAML_DEPTH = 128
VERIFIED_SHELLS = %w[bash /bin/bash].freeze

def fail(message)
  warn "error: #{message}"
  exit 1
end

def safe_label(value)
  value.to_s.gsub(/[^A-Za-z0-9_.-]/, "_").byteslice(0, 64)
end

def read_reviewed_file(path)
  flags = File::RDONLY | File::NOFOLLOW | File::NONBLOCK
  File.open(path, flags) do |file|
    before = file.stat
    fail("workflow must be a regular file") unless before.file?
    fail("workflow must have exactly one hard link") unless before.nlink == 1
    fail("workflow owner is unsafe") unless before.uid == Process.uid
    fail("workflow permissions are unsafe") unless (before.mode & 0o022).zero?
    fail("workflow size is invalid") unless before.size.between?(1, MAX_WORKFLOW_BYTES)

    contents = file.read(MAX_WORKFLOW_BYTES + 1)
    after = file.stat
    stable = %i[dev ino uid mode nlink size mtime ctime].all? do |field|
      before.public_send(field) == after.public_send(field)
    end
    fail("workflow changed during inspection") unless stable
    fail("workflow read was incomplete") unless contents.bytesize == before.size
    fail("workflow contains invalid UTF-8") unless contents.force_encoding(Encoding::UTF_8).valid_encoding?
    fail("workflow contains a NUL byte") if contents.include?("\0")
    contents
  end
rescue Errno::ENOENT
  fail("workflow does not exist")
rescue Errno::ELOOP
  fail("workflow must not be a symbolic link")
rescue SystemCallError
  fail("workflow could not be opened safely")
end

def canonical_yaml_key(node, scanner)
  line = node.respond_to?(:start_line) ? node.start_line + 1 : "unknown"
  fail("workflow mapping key must be a scalar: line-#{line}") unless
    node.is_a?(Psych::Nodes::Scalar)
  fail("workflow mapping key uses an explicit tag: line-#{line}") unless node.tag.nil?

  value = node.plain ? scanner.tokenize(node.value) : node.value
  [value.class.name, value.inspect]
end

def validate_unambiguous_yaml!(contents)
  stream = Psych.parse_stream(contents)
  fail("workflow must contain exactly one YAML document") unless stream.children.length == 1

  document = stream.children.first
  root = document.children.first
  fail("workflow YAML document is empty") if root.nil?

  scanner = Psych::ScalarScanner.new(Psych::ClassLoader::Restricted.new([], []))
  stack = [[root, 0]]
  node_count = 0

  until stack.empty?
    node, depth = stack.pop
    node_count += 1
    fail("workflow YAML structure is too large") if node_count > MAX_YAML_NODES
    fail("workflow YAML nesting is too deep") if depth > MAX_YAML_DEPTH

    case node
    when Psych::Nodes::Mapping
      fail("workflow YAML mapping is malformed") unless node.children.length.even?
      seen_raw = {}
      seen_resolved = {}
      node.children.each_slice(2) do |key, value|
        node_count += 1
        fail("workflow YAML structure is too large") if node_count > MAX_YAML_NODES
        identity = canonical_yaml_key(key, scanner)
        line = key.respond_to?(:start_line) ? key.start_line + 1 : "unknown"
        raw_identity = key.value
        if seen_raw.key?(raw_identity) || seen_resolved.key?(identity)
          fail("workflow contains a duplicate mapping key: line-#{line}")
        end
        seen_raw[raw_identity] = true
        seen_resolved[identity] = true
        stack << [value, depth + 1]
      end
    when Psych::Nodes::Sequence
      node.children.reverse_each { |child| stack << [child, depth + 1] }
    when Psych::Nodes::Alias
      fail("workflow YAML aliases are not allowed")
    when Psych::Nodes::Scalar
      next
    else
      fail("workflow YAML contains an unsupported node")
    end
  end
end

def sanitize_github_expressions(script)
  sanitized = script.gsub(/\$\{\{.*?\}\}/m, "GITHUB_EXPRESSION")
  fail("workflow run step contains an incomplete GitHub expression") if sanitized.include?("${{")
  sanitized
end

def run_default_shell(container, scope)
  return nil unless container.key?("defaults")

  defaults = container["defaults"]
  fail("workflow run defaults are malformed: #{scope}") unless defaults.is_a?(Hash)
  return nil unless defaults.key?("run")

  run_defaults = defaults["run"]
  fail("workflow run defaults are malformed: #{scope}") unless run_defaults.is_a?(Hash)
  return nil unless run_defaults.key?("shell")

  shell = run_defaults["shell"]
  fail("workflow run default shell must be a string: #{scope}") unless shell.is_a?(String)
  shell
end

def require_verified_shell!(shell, coordinate)
  fail("workflow run step uses an unverified shell: #{coordinate}") unless
    VERIFIED_SHELLS.include?(shell)
end

unless ARGV.length == 2 && ARGV[0] == "--workflow"
  warn "Usage: verify-workflow-run-shells.rb --workflow FILE"
  exit 64
end

workflow_path = ARGV[1]
contents = read_reviewed_file(workflow_path)

begin
  validate_unambiguous_yaml!(contents)
  workflow = YAML.safe_load(
    contents,
    permitted_classes: [],
    permitted_symbols: [],
    aliases: false
  )
rescue Psych::Exception
  fail("workflow is not valid safe YAML")
end
fail("workflow root must be a mapping") unless workflow.is_a?(Hash)

jobs = workflow["jobs"]
fail("workflow jobs mapping is missing") unless jobs.is_a?(Hash) && !jobs.empty?
workflow_default_shell = run_default_shell(workflow, "root")
require_verified_shell!(workflow_default_shell, "root/default") unless workflow_default_shell.nil?

run_step_count = 0
jobs.each do |job_id, job|
  job_label = safe_label(job_id)
  fail("workflow job is malformed: #{job_label}") unless job.is_a?(Hash)
  job_default_shell = run_default_shell(job, job_label)
  require_verified_shell!(job_default_shell, "#{job_label}/default") unless job_default_shell.nil?
  steps = job["steps"]
  next if steps.nil? && job.key?("uses")
  fail("workflow job steps are missing: #{job_label}") unless steps.is_a?(Array) && !steps.empty?

  steps.each_with_index do |step, index|
    fail("workflow step is malformed: #{job_label}/#{index + 1}") unless step.is_a?(Hash)
    next unless step.key?("run")

    run_step_count += 1
    script = step["run"]
    fail("workflow run step must be a string: #{job_label}/#{index + 1}") unless script.is_a?(String)
    fail("workflow run step size is invalid: #{job_label}/#{index + 1}") unless
      script.bytesize.between?(1, MAX_RUN_BYTES)
    fail("workflow run step contains a NUL byte: #{job_label}/#{index + 1}") if script.include?("\0")

    shell = if step.key?("shell")
      explicit_shell = step["shell"]
      fail("workflow run step shell must be a string: #{job_label}/#{index + 1}") unless
        explicit_shell.is_a?(String)
      explicit_shell
    else
      job_default_shell || workflow_default_shell || "bash"
    end
    require_verified_shell!(shell, "#{job_label}/#{index + 1}")

    sanitized = sanitize_github_expressions(script)
    _stdout, stderr, status = Open3.capture3(
      { "LC_ALL" => "C" },
      "/bin/bash",
      "-n",
      stdin_data: sanitized,
      unsetenv_others: true
    )
    next if status.success?

    line = stderr[/line (\d+)/, 1] || "unknown"
    fail("workflow run shell syntax is invalid: #{job_label}/#{index + 1}/line-#{line}")
  end
end

fail("workflow contains no run steps") if run_step_count.zero?
puts "Workflow run-shell syntax: PASS (#{run_step_count} steps)"
