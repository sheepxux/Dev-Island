#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "optparse"
require "tempfile"
require_relative "verify-pinned-create-dmg-tool"

# Execute create-dmg from descriptor-verified bytes. The upstream program is a
# Bash script, so macOS cannot atomically fexecve(2) it, and invoking its
# verified pathname would reopen the tool after validation. Instead this
# launcher:
#
# 1. obtains the complete reviewed closure from the no-follow verifier;
# 2. performs one exact, digest-pinned rewrite that makes the two support-file
#    reads use inherited anonymous descriptors rather than relative paths; and
# 3. execs Bash with an anonymous, already-unlinked descriptor for the script.
#
# No pathname below the downloaded tool root is opened after verification.
module PinnedCreateDMGRunner
  class ExecutionError < StandardError; end

  SUPPORT_DISCOVERY = <<~'SOURCE'.b.freeze
    sentinel_file="$SCRIPT_DIR/.this-is-the-create-dmg-repo"
    if [[ -f "$sentinel_file" ]]; then
    	# We're running from inside a repo
    	CDMG_SUPPORT_DIR="$SCRIPT_DIR/support"
    else
    	# We're running inside an installed location
    	bin_dir="$SCRIPT_DIR"
    	prefix_dir=$(dirname "$bin_dir")
    	CDMG_SUPPORT_DIR="$prefix_dir/share/create-dmg/support"
    fi
  SOURCE
  DESCRIPTOR_BOUND_SUPPORT = <<~'SOURCE'.b.freeze
    sentinel_file="/dev/null"
    CDMG_SUPPORT_DIR="/dev/fd"
  SOURCE
  TEMPLATE_READ = 'cat "$CDMG_SUPPORT_DIR/template.applescript" \\'.b.freeze
  DESCRIPTOR_BOUND_TEMPLATE_READ = 'cat <&"${DEV_ISLAND_CREATE_DMG_TEMPLATE_FD}" \\'.b.freeze
  EULA_TEMPLATE_READ = '$(<${CDMG_SUPPORT_DIR}/eula-resources-template.xml)'.b.freeze
  DESCRIPTOR_BOUND_EULA_TEMPLATE_READ = '$(cat <&"${DEV_ISLAND_CREATE_DMG_EULA_TEMPLATE_FD}")'.b.freeze
  EXECUTION_SCRIPT_BYTES = 22_095
  EXECUTION_SCRIPT_SHA256 = "46644c8da0d7eb1258e3ef05dd72967ca270d698df28d2aa6abd9402205e5beb"

  module_function

  def fail_closed(reason)
    raise ExecutionError, reason
  end

  def replace_once(bytes, source, replacement, label)
    fail_closed("reviewed #{label} transform source is not unique") unless bytes.scan(source).length == 1
    bytes.sub(source, replacement)
  end

  def execution_script(upstream_bytes)
    bytes = upstream_bytes.dup
    bytes = replace_once(
      bytes,
      SUPPORT_DISCOVERY,
      DESCRIPTOR_BOUND_SUPPORT,
      "support discovery"
    )
    bytes = replace_once(
      bytes,
      TEMPLATE_READ,
      DESCRIPTOR_BOUND_TEMPLATE_READ,
      "AppleScript template read"
    )
    bytes = replace_once(
      bytes,
      EULA_TEMPLATE_READ,
      DESCRIPTOR_BOUND_EULA_TEMPLATE_READ,
      "EULA template read"
    )
    fail_closed("derived execution script size mismatch") unless bytes.bytesize == EXECUTION_SCRIPT_BYTES
    unless Digest::SHA256.hexdigest(bytes) == EXECUTION_SCRIPT_SHA256
      fail_closed("derived execution script digest mismatch")
    end
    bytes.freeze
  end

  def private_runtime_directory(variable)
    path = ENV.fetch(variable, "")
    expanded = File.expand_path(path)
    fail_closed("#{variable} must be an absolute directory") unless path.start_with?("/") &&
      !path.match?(/[\0\r\n\t]/)
    begin
      physical = File.realpath(expanded)
      stat = File.lstat(physical)
    rescue SystemCallError
      fail_closed("#{variable} is unavailable")
    end
    fail_closed("#{variable} must be a real directory") unless stat.directory?
    fail_closed("#{variable} owner mismatch") unless stat.uid == Process.uid
    fail_closed("#{variable} must not be accessible to other users") unless (stat.mode & 0o077) == 0
    physical
  end

  def anonymous_verified_file(bytes, label, temp_directory)
    file = Tempfile.new(["dev-island-create-dmg-#{label}-", ".runtime"], temp_directory)
    file.binmode
    file.chmod(0o600)
    created = file.stat
    fail_closed("#{label} runtime was not created safely") unless created.file? &&
      created.uid == Process.uid &&
      created.nlink == 1 &&
      (created.mode & 0o7777) == 0o600 &&
      created.size == 0

    # Remove the only pathname before materializing reviewed bytes. From this
    # point onward, the runtime is reachable only through this descriptor.
    path = file.path
    File.unlink(path)
    file.write(bytes)
    file.flush
    file.fsync
    file.rewind

    anonymous = file.stat
    fail_closed("#{label} runtime did not remain anonymous") unless anonymous.file? &&
      anonymous.uid == Process.uid &&
      anonymous.nlink == 0 &&
      (anonymous.mode & 0o7777) == 0o600 &&
      anonymous.size == bytes.bytesize
    materialized = file.read
    unless materialized == bytes && Digest::SHA256.hexdigest(materialized) == Digest::SHA256.hexdigest(bytes)
      fail_closed("#{label} runtime bytes changed while materializing")
    end

    file.rewind
    file.close_on_exec = false
    file
  rescue SystemCallError => error
    file&.close!
    fail_closed("could not materialize anonymous #{label} runtime: #{error.class}")
  end

  def parse(argv)
    separator = argv.index("--")
    fail_closed("a -- separator is required before create-dmg arguments") unless separator
    launcher_arguments = argv.take(separator)
    create_dmg_arguments = argv.drop(separator + 1)
    fail_closed("create-dmg arguments are required") if create_dmg_arguments.empty?

    options = {}
    parser = OptionParser.new do |config|
      config.on("--root PATH") { |value| options[:root] = value }
      config.on("--executable PATH") { |value| options[:executable] = value }
      config.on("--manifest PATH") { |value| options[:manifest] = value }
    end
    parser.parse!(launcher_arguments)
    fail_closed("unexpected launcher arguments") unless launcher_arguments.empty?
    root = options.fetch(:root)
    executable = options.fetch(:executable)
    manifest = options.fetch(:manifest)
    unless executable == File.join(root, "create-dmg")
      fail_closed("executable path must be the create-dmg member of the verified root")
    end
    [root, executable, manifest, create_dmg_arguments]
  rescue KeyError, OptionParser::ParseError => error
    fail_closed(error.message)
  end

  def execution_environment(home_directory:, temp_directory:, template_fd:, eula_template_fd:)
    {
      "PATH" => "/usr/bin:/bin:/usr/sbin:/sbin",
      "LC_ALL" => "C",
      "HOME" => home_directory,
      "TMPDIR" => "#{temp_directory}/",
      "DEV_ISLAND_CREATE_DMG_TEMPLATE_FD" => template_fd.to_s,
      "DEV_ISLAND_CREATE_DMG_EULA_TEMPLATE_FD" => eula_template_fd.to_s
    }
  end

  def run(argv)
    # Coarse stage marker for the fail-closed diagnostics below. It names
    # which boundary an operating-system error escaped from without ever
    # echoing a pathname, descriptor number, or argument.
    stage = "argument parsing"
    root, _executable, manifest, create_dmg_arguments = parse(argv)
    stage = "closure verification"
    closure = PinnedCreateDMGTool.verify(root: root, manifest: manifest)
    script_bytes = execution_script(closure.fetch("create-dmg"))
    stage = "runtime directory validation"
    temp_directory = private_runtime_directory("TMPDIR")
    home_directory = private_runtime_directory("HOME")

    # Keep strong Ruby references until exec so finalizers cannot close the
    # inherited descriptors. Each backing file is already unlinked.
    stage = "anonymous runtime materialization"
    runtimes = {
      script: anonymous_verified_file(script_bytes, "script", temp_directory),
      template: anonymous_verified_file(
        closure.fetch("support/template.applescript"),
        "template",
        temp_directory
      ),
      eula_template: anonymous_verified_file(
        closure.fetch("support/eula-resources-template.xml"),
        "eula-template",
        temp_directory
      )
    }

    environment = execution_environment(
      home_directory: home_directory,
      temp_directory: temp_directory,
      template_fd: runtimes.fetch(:template).fileno,
      eula_template_fd: runtimes.fetch(:eula_template).fileno
    )
    script_path = "/dev/fd/#{runtimes.fetch(:script).fileno}"
    stage = "bash exec"
    exec(
      environment,
      "/bin/bash",
      script_path,
      *create_dmg_arguments,
      unsetenv_others: true
    )
  rescue PinnedCreateDMGTool::ValidationError, ExecutionError => error
    warn "run-pinned-create-dmg: #{error.message}"
    1
  rescue SystemCallError => error
    warn "run-pinned-create-dmg: execution failed during #{stage}: #{error.class}"
    1
  end
end

exit PinnedCreateDMGRunner.run(ARGV) if $PROGRAM_NAME == __FILE__
