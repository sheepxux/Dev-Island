#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "pathname"

EXPECTED_HASHES = {
  "Sparkle.xcodeproj/project.pbxproj" =>
    "19c340081c8274bf34b4c9531ebe273daa3502ed3bbdac826b36a4e175517ba4",
  "InstallerLauncher/SUInstallerLauncher.m" =>
    "04f6c2e44ddcf6bb5b1cb0530be2f970b2652a02cd81b6e1d7bd874bd92f915a",
  "Sparkle/SPULocalCacheDirectory.m" =>
    "35b631ed1927e922fb9bb187e2dd925e309746b22ae70fed6815bbbf62470b77",
}.freeze

PACKAGE_IDS = %w[
  727DBAE326B5BBFD00111F0C
  725C2EAB2782EF3C007CB7B5
  727DBAE426B5BBFD00111F0C
  727DBAE626B5C47800111F0C
  727DBAE826B5C48A00111F0C
  725C2EAC2782EF3C007CB7B5
  727DBAE526B5BBFD00111F0C
  727DBAE726B5C47800111F0C
  727DBAE926B5C48A00111F0C
].freeze

def fail(message)
  warn "error: #{message}"
  exit 1
end

def private_directory(path)
  expanded = File.realpath(path)
  status = File.lstat(expanded)
  fail("disposable source input is not a private directory") unless
    status.directory? &&
      status.uid == Process.euid &&
      (status.mode & 0o077).zero?
  expanded
rescue SystemCallError
  fail("disposable source input is unavailable")
end

def private_child_directory(path, root)
  expanded = private_directory(path)
  fail("disposable source path escaped its private root") unless
    expanded.start_with?("#{root}/")
  expanded
end

def owned_regular_file(path, root)
  expanded = File.expand_path(path)
  fail("Sparkle source path escaped its private root") unless
    expanded.start_with?("#{root}/")
  status = File.lstat(expanded)
  fail("Sparkle source file is unsafe") unless
    status.file? &&
      status.uid == Process.euid &&
      status.nlink == 1 &&
      (status.mode & 0o022).zero? &&
      status.size.between?(1, 4 * 1_024 * 1_024)
  expanded
rescue SystemCallError
  fail("Sparkle source file is unavailable")
end

def replace_once(text, needle, replacement, label)
  fail("Sparkle source anchor drifted: #{label}") unless text.scan(needle).length == 1
  text.sub(needle, replacement)
end

def replace_regex_once(text, pattern, replacement, label)
  fail("Sparkle source anchor drifted: #{label}") unless text.scan(pattern).length == 1
  text.sub(pattern, replacement)
end

def objective_c_string(value)
  "@\"#{value.gsub("\\", "\\\\").gsub("\"", "\\\"")}\""
end

def rewrite(path, expected_hash, root)
  file = owned_regular_file(path, root)
  bytes = File.binread(file)
  fail("pinned Sparkle source identity drifted") unless
    Digest::SHA256.hexdigest(bytes) == expected_hash
  rewritten = yield(bytes)
  fail("disposable Sparkle rewrite produced empty source") if rewritten.empty?
  File.binwrite(file, rewritten)
  File.chmod(0o600, file)
end

fail("Usage: prepare-sparkle-disposable-source.rb SOURCE_ROOT DISPOSABLE_ROOT HOME TMP") unless
  ARGV.length == 4

source_argument, disposable_argument, home_argument, temporary_argument = ARGV
disposable_root = private_directory(disposable_argument)
source_root = private_child_directory(source_argument, disposable_root)
home = private_child_directory(home_argument, disposable_root)
temporary_directory = private_child_directory(temporary_argument, disposable_root)
cache_root = File.join(home, "Library", "Caches")
preferences_root = File.join(home, "Library", "Preferences")
[cache_root, preferences_root].each do |path|
  FileUtils.mkdir_p(path, mode: 0o700)
  File.chmod(0o700, path)
end

project_relative = "Sparkle.xcodeproj/project.pbxproj"
rewrite(
  File.join(source_root, project_relative),
  EXPECTED_HASHES.fetch(project_relative),
  disposable_root
) do |text|
  text = text.gsub(
    %r{/\* Begin XCRemoteSwiftPackageReference section \*/.*?/\* End XCRemoteSwiftPackageReference section \*/\n}m,
    ""
  )
  text = text.gsub(
    %r{/\* Begin XCSwiftPackageProductDependency section \*/.*?/\* End XCSwiftPackageProductDependency section \*/\n}m,
    ""
  )
  text = text.each_line.reject do |line|
    PACKAGE_IDS.any? { |identifier| line.include?(identifier) }
  end.join
  fail("remote package reference remained in disposable Sparkle project") if
    text.include?("XCRemoteSwiftPackageReference") ||
      text.include?("repositoryURL =")
  text
end

environment_method = <<~OBJC

  static NSDictionary<NSString *, NSString *> *DevIslandDisposableEnvironment(void)
  {
      return @{
          @"PATH": @"/usr/bin:/bin:/usr/sbin:/sbin",
          @"HOME": #{objective_c_string(home)},
          @"CFFIXED_USER_HOME": #{objective_c_string(home)},
          @"TMPDIR": #{objective_c_string("#{temporary_directory}/")},
          @"__CFPREFERENCES_AVOID_DAEMON": @"1",
      };
  }
OBJC

launcher_relative = "InstallerLauncher/SUInstallerLauncher.m"
rewrite(
  File.join(source_root, launcher_relative),
  EXPECTED_HASHES.fetch(launcher_relative),
  disposable_root
) do |text|
  text = replace_once(
    text,
    "#import <SystemConfiguration/SystemConfiguration.h>\n",
    "#import <SystemConfiguration/SystemConfiguration.h>\n#{environment_method}",
    "disposable environment method"
  )
  progress_mach_services =
    "        jobDictionary[@\"MachServices\"] = @{SPUStatusInfoServiceNameForBundleIdentifier(hostBundleIdentifier) : @YES};\n"
  text = replace_once(
    text,
    progress_mach_services,
    "#{progress_mach_services}        jobDictionary[@\"EnvironmentVariables\"] = DevIslandDisposableEnvironment();\n",
    "progress launch environment"
  )
  installer_dictionary =
    "        NSDictionary *jobDictionary = @{@\"Label\" : label, @\"ProgramArguments\" : arguments, @\"EnableTransactions\" : @NO, @\"RunAtLoad\" : @YES, @\"Nice\" : @0, @\"ProcessType\": @\"Interactive\", @\"LaunchOnlyOnce\": @YES, @\"MachServices\" : @{SPUInstallerServiceNameForBundleIdentifier(hostBundleIdentifier) : @YES, SPUProgressAgentServiceNameForBundleIdentifier(hostBundleIdentifier) : @YES}};\n"
  isolated_installer_dictionary = installer_dictionary.sub(
    "}};\n",
    "}, @\"EnvironmentVariables\" : DevIslandDisposableEnvironment()};\n"
  )
  text = replace_once(
    text,
    installer_dictionary,
    isolated_installer_dictionary,
    "installer launch environment"
  )
  isolated_user_home = <<~OBJC.lines.map { |line| "        #{line}" }.join
    NSString *userName = @"dev-island-disposable";
    NSString *homeDirectory = #{objective_c_string(home)};
  OBJC
  user_home_pattern =
    /^        NSString \*userName;\n^        NSString \*homeDirectory;\n^        if \(!rootUser\) \{.*?^        \}\n(?=^        \n^        \/\/ It may be tempting)/m
  replace_regex_once(
    text,
    user_home_pattern,
    isolated_user_home,
    "installer user home"
  )
end

cache_relative = "Sparkle/SPULocalCacheDirectory.m"
rewrite(
  File.join(source_root, cache_relative),
  EXPECTED_HASHES.fetch(cache_relative),
  disposable_root
) do |text|
  cache_lookup =
    "    NSURL *cacheURL = [[NSFileManager defaultManager] URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:NULL];\n"
  replace_once(
    text,
    cache_lookup,
    "    NSURL *cacheURL = [NSURL fileURLWithPath:#{objective_c_string(cache_root)} isDirectory:YES];\n",
    "cache root"
  )
end

puts "Sparkle disposable source preparation: PASS"
puts "Source revision overlay: offline project + private cache/home + launch-job environment"
