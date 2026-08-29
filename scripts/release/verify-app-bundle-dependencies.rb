#!/usr/bin/env ruby

require "find"
require "open3"
require "optparse"
require "pathname"
require "set"

class BundleDependencyError < StandardError; end

class AppBundleDependencyVerifier
  REQUIRED_ARCHITECTURES = Set.new(%w[arm64 x86_64]).freeze
  SYSTEM_PREFIXES = [
    "/System/Library/",
    "/usr/lib/",
    "/Library/Apple/System/Library/",
  ].freeze
  BUNDLE_EXTENSIONS = %w[.app .xpc .appex].freeze

  def initialize(app_path)
    @app = File.expand_path(app_path)
    raise BundleDependencyError, "App bundle is missing" unless File.directory?(@app)

    @app_real = File.realpath(@app)
    @mach_o_files = []
    @rpath_cache = {}
  end

  def verify!
    verify_symlinks!
    discover_mach_o_files!
    raise BundleDependencyError, "App bundle contains no Mach-O files" if @mach_o_files.empty?

    @mach_o_files.each do |binary|
      verify_architectures!(binary)
      REQUIRED_ARCHITECTURES.each do |architecture|
        verify_rpaths!(binary, architecture)
        verify_dependencies!(binary, architecture)
      end
    end

    main_directory = File.join(@app, "Contents", "MacOS")
    unless @mach_o_files.any? { |path| path.start_with?(main_directory + File::SEPARATOR) }
      raise BundleDependencyError, "App bundle has no main executable"
    end

    puts "App bundle dependency closure: PASS (#{@mach_o_files.length} Mach-O files, arm64+x86_64)"
  end

  private

  def run!(*command)
    stdout, stderr, status = Open3.capture3(*command)
    return stdout if status.success?

    tool = File.basename(command.first)
    detail = stderr.to_s.lines.first.to_s.strip
    detail = stdout.to_s.lines.first.to_s.strip if detail.empty?
    raise BundleDependencyError, "#{tool} failed#{detail.empty? ? "" : ": #{detail}"}"
  end

  def relative(path)
    Pathname.new(path).relative_path_from(Pathname.new(@app)).to_s
  rescue ArgumentError
    "outside app bundle"
  end

  def inside_bundle?(path)
    expanded = File.expand_path(path)
    expanded == @app || expanded.start_with?(@app + File::SEPARATOR)
  end

  def real_path_inside_bundle?(path)
    real = File.realpath(path)
    real == @app_real || real.start_with?(@app_real + File::SEPARATOR)
  rescue Errno::ENOENT, Errno::ELOOP
    false
  end

  def verify_symlinks!
    Find.find(@app) do |path|
      next unless File.symlink?(path)

      unless real_path_inside_bundle?(path)
        raise BundleDependencyError,
              "Bundle symlink escapes or is dangling: #{relative(path)}"
      end
    end
  end

  def discover_mach_o_files!
    Find.find(File.join(@app, "Contents")) do |path|
      next if File.symlink?(path)
      next unless File.file?(path)

      description = run!("/usr/bin/file", "-b", path)
      @mach_o_files << path if description.include?("Mach-O")
    end
    @mach_o_files.sort!
  end

  def architectures(binary)
    Set.new(run!("/usr/bin/lipo", "-archs", binary).split)
  end

  def verify_architectures!(binary)
    found = architectures(binary)
    return if found == REQUIRED_ARCHITECTURES

    raise BundleDependencyError,
          "Mach-O is not exactly arm64+x86_64: #{relative(binary)}"
  end

  def rpaths(binary, architecture)
    key = [binary, architecture]
    return @rpath_cache[key] if @rpath_cache.key?(key)

    output = run!("/usr/bin/otool", "-arch", architecture, "-l", binary)
    paths = []
    awaiting_path = false
    output.each_line do |line|
      stripped = line.strip
      if stripped == "cmd LC_RPATH"
        awaiting_path = true
      elsif awaiting_path && stripped.start_with?("path ")
        paths << stripped.split[1]
        awaiting_path = false
      end
    end
    @rpath_cache[key] = paths.uniq
  end

  def verify_rpaths!(binary, architecture)
    rpaths(binary, architecture).each do |raw_path|
      expanded = expand_token_path(raw_path, binary)
      if raw_path.start_with?("/")
        next if system_path?(raw_path)

        raise BundleDependencyError,
              "Mach-O contains a developer/external absolute rpath: #{relative(binary)}"
      end

      unless expanded && inside_bundle?(expanded)
        raise BundleDependencyError,
              "Mach-O contains an unsupported or escaping rpath: #{relative(binary)}"
      end
    end
  end

  def dependencies(binary, architecture)
    output = run!("/usr/bin/otool", "-arch", architecture, "-L", binary)
    output.lines.drop(1).each_with_object([]) do |line, found|
      stripped = line.strip
      next if stripped.empty?

      found << stripped.sub(/\s+\(compatibility version.*\z/, "")
    end
  end

  def install_ids(binary, architecture)
    output, = Open3.capture2("/usr/bin/otool", "-arch", architecture, "-D", binary)
    Set.new(output.lines.drop(1).map(&:strip).reject(&:empty?))
  end

  def verify_dependencies!(binary, architecture)
    ids = install_ids(binary, architecture)
    dependencies(binary, architecture).each do |dependency|
      next if ids.include?(dependency)
      next if system_path?(dependency)

      if dependency.start_with?("/")
        raise BundleDependencyError,
              "Mach-O links a developer/external absolute dependency: #{relative(binary)}"
      end

      resolved = resolve_dependency(dependency, binary, architecture)
      unless resolved
        raise BundleDependencyError,
              "Mach-O has an unresolved bundled dependency: #{relative(binary)}"
      end

      next if system_path?(resolved)

      unless File.exist?(resolved) && real_path_inside_bundle?(resolved)
        raise BundleDependencyError,
              "Mach-O dependency is missing or escapes the bundle: #{relative(binary)}"
      end

      unless mach_o?(resolved)
        raise BundleDependencyError,
              "Resolved dependency is not Mach-O: #{relative(binary)}"
      end

      unless architectures(resolved).include?(architecture)
        raise BundleDependencyError,
              "Resolved dependency lacks #{architecture}: #{relative(binary)}"
      end
    end
  end

  def mach_o?(path)
    run!("/usr/bin/file", "-b", path).include?("Mach-O")
  end

  def resolve_dependency(dependency, binary, architecture)
    if dependency.start_with?("@loader_path") || dependency.start_with?("@executable_path")
      return expand_token_path(dependency, binary)
    end

    return nil unless dependency.start_with?("@rpath/")

    suffix = dependency.delete_prefix("@rpath/")
    runpath_owners(binary).each do |owner|
      rpaths(owner, architecture).each do |raw_rpath|
        base = expand_token_path(raw_rpath, owner)
        next unless base

        candidate = File.expand_path(suffix, base)
        return candidate if File.exist?(candidate) || system_path?(candidate)
      end
    end
    nil
  end

  def runpath_owners(binary)
    owners = [binary]
    bundle = nearest_code_bundle(binary)
    main_directory = File.join(bundle, "Contents", "MacOS")
    if File.directory?(main_directory)
      Dir.children(main_directory).sort.each do |name|
        candidate = File.join(main_directory, name)
        owners << candidate if @mach_o_files.include?(candidate)
      end
    end

    # Frameworks loaded by nested helpers may inherit both the helper's and
    # the outer app's runpath chain. Include the root executable without
    # weakening path validation.
    root_main = File.join(@app, "Contents", "MacOS")
    if File.directory?(root_main)
      Dir.children(root_main).sort.each do |name|
        candidate = File.join(root_main, name)
        owners << candidate if @mach_o_files.include?(candidate)
      end
    end
    owners.uniq
  end

  def nearest_code_bundle(path)
    current = File.dirname(path)
    loop do
      return current if BUNDLE_EXTENSIONS.include?(File.extname(current))
      break if current == @app || current == File.dirname(current)

      current = File.dirname(current)
    end
    @app
  end

  def executable_directory(binary)
    File.join(nearest_code_bundle(binary), "Contents", "MacOS")
  end

  def expand_token_path(path, owner)
    case path
    when "@loader_path"
      File.dirname(owner)
    when %r{\A@loader_path/(.+)\z}
      File.expand_path(Regexp.last_match(1), File.dirname(owner))
    when "@executable_path"
      executable_directory(owner)
    when %r{\A@executable_path/(.+)\z}
      File.expand_path(Regexp.last_match(1), executable_directory(owner))
    when %r{\A/}
      path
    else
      nil
    end
  end

  def system_path?(path)
    return false unless path.start_with?("/")

    normalized = File.expand_path(path)
    SYSTEM_PREFIXES.any? { |prefix| normalized.start_with?(prefix) }
  end
end

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: verify-app-bundle-dependencies.rb --app PATH"
  parser.on("--app PATH", "App bundle to inspect") { |value| options[:app] = value }
end.parse!

unless options[:app] && ARGV.empty?
  warn "::error::Usage: verify-app-bundle-dependencies.rb --app PATH"
  exit 64
end

begin
  AppBundleDependencyVerifier.new(options[:app]).verify!
rescue BundleDependencyError => error
  warn "::error::#{error.message}"
  exit 1
rescue StandardError => error
  warn "::error::App bundle dependency verification failed (#{error.class})"
  exit 1
end
