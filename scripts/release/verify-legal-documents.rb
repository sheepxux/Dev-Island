#!/usr/bin/env ruby
# encoding: UTF-8

require "date"
require "fileutils"
require "tmpdir"

MAX_DOCUMENT_BYTES = 512 * 1024
DOCUMENT_NAMES = ["PRIVACY.md", "TERMS.md"].freeze

DocumentSpec = Struct.new(
  :english_title,
  :chinese_title,
  keyword_init: true
)

PRIVACY_SPEC = DocumentSpec.new(
  english_title: "# Dev Island Privacy Notice",
  chinese_title: "# Dev Island 隐私说明"
)
TERMS_SPEC = DocumentSpec.new(
  english_title: "# Dev Island Terms of Use",
  chinese_title: "# Dev Island 使用条款"
)

class LegalDocumentVerificationError < StandardError; end

def reject!(message)
  raise LegalDocumentVerificationError, message
end

def stable_stat?(left, right)
  left.dev == right.dev &&
    left.ino == right.ino &&
    left.mode == right.mode &&
    left.uid == right.uid &&
    left.nlink == right.nlink &&
    left.size == right.size &&
    left.mtime == right.mtime &&
    left.ctime == right.ctime
end

def read_document(path, label)
  before = File.lstat(path)
  reject!("#{label} must not be a symbolic link") if before.symlink?
  reject!("#{label} must be a regular file") unless before.file?
  reject!("#{label} must have exactly one hard link") unless before.nlink == 1
  reject!("#{label} owner is unsafe") unless before.uid == Process.uid
  reject!("#{label} permissions are unsafe") unless (before.mode & 0o022).zero?
  reject!("#{label} size is invalid") unless before.size.between?(1, MAX_DOCUMENT_BYTES)

  flags = File::RDONLY
  flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
  bytes = File.open(path, flags) do |file|
    opened = file.stat
    reject!("#{label} changed before reading") unless stable_stat?(before, opened)
    contents = file.read(MAX_DOCUMENT_BYTES + 1)
    after = file.stat
    reject!("#{label} changed while reading") unless stable_stat?(opened, after)
    reject!("#{label} read was incomplete") unless contents.bytesize == opened.size
    contents
  end

  encoded = bytes.dup.force_encoding(Encoding::UTF_8)
  reject!("#{label} is not valid UTF-8") unless encoded.valid_encoding?
  reject!("#{label} contains a NUL byte") if encoded.include?("\0")
  encoded
rescue Errno::ENOENT
  reject!("#{label} is missing")
rescue Errno::ELOOP
  reject!("#{label} must not be a symbolic link")
rescue Errno::EACCES, Errno::EPERM
  reject!("#{label} could not be opened safely")
end

def parse_english_date(section, label)
  match = section.match(/^Last updated: ([A-Z][a-z]+ [0-9]{1,2}, [0-9]{4})$/)
  reject!("#{label} English review date is missing") unless match
  Date.strptime(match[1], "%B %d, %Y")
rescue Date::Error
  reject!("#{label} English review date is invalid")
end

def parse_chinese_date(section, label)
  match = section.match(/^最后更新：([0-9]{4}) 年 ([0-9]{1,2}) 月 ([0-9]{1,2}) 日$/)
  reject!("#{label} Chinese review date is missing") unless match
  Date.new(match[1].to_i, match[2].to_i, match[3].to_i)
rescue Date::Error
  reject!("#{label} Chinese review date is invalid")
end

def verify_document(contents, spec, label)
  separator = "\n---\n\n"
  sections = contents.split(separator, -1)
  reject!("#{label} must contain one bilingual separator") unless sections.length == 2
  english, chinese = sections

  headings = contents.lines.grep(/^# /).map(&:strip)
  expected_headings = [spec.english_title, spec.chinese_title]
  reject!("#{label} top-level headings are invalid") unless headings == expected_headings
  reject!("#{label} English section is not first") unless english.start_with?("#{spec.english_title}\n")
  reject!("#{label} Chinese section is not second") unless chinese.start_with?("#{spec.chinese_title}\n")
  reject!("#{label} English draft disclosure is missing") unless english.match?(/draft/i)
  reject!("#{label} Chinese draft disclosure is missing") unless chinese.include?("草案")

  english_date = parse_english_date(english, label)
  chinese_date = parse_chinese_date(chinese, label)
  reject!("#{label} bilingual review dates do not match") unless english_date == chinese_date

  ["alsoaxu@gmail.com", "puzhen913@gmail.com"].each do |address|
    reject!("#{label} reviewed contact is missing") unless
      english.include?(address) && chinese.include?(address)
  end

  english_date.iso8601
end

def verify_source_pair(privacy_path, terms_path)
  privacy = read_document(privacy_path, "Privacy source")
  terms = read_document(terms_path, "Terms source")
  {
    "PRIVACY.md" => [privacy, verify_document(privacy, PRIVACY_SPEC, "Privacy source")],
    "TERMS.md" => [terms, verify_document(terms, TERMS_SPEC, "Terms source")],
  }
end

def verify_bundle_directory(bundle_directory)
  metadata = File.lstat(bundle_directory)
  reject!("Legal bundle directory must not be a symbolic link") if metadata.symlink?
  reject!("Legal bundle directory must be a directory") unless metadata.directory?
  reject!("Legal bundle directory owner is unsafe") unless metadata.uid == Process.uid
  reject!("Legal bundle directory permissions are unsafe") unless (metadata.mode & 0o022).zero?
  entries = Dir.children(bundle_directory).sort
  reject!("Legal bundle directory has an unexpected inventory") unless entries == DOCUMENT_NAMES
rescue Errno::ENOENT
  reject!("Legal bundle directory is missing")
end

def verify_bundle(privacy_path, terms_path, bundle_directory)
  sources = verify_source_pair(privacy_path, terms_path)
  verify_bundle_directory(bundle_directory)

  DOCUMENT_NAMES.each do |name|
    bundled = read_document(File.join(bundle_directory, name), "Bundled #{name}")
    verify_document(
      bundled,
      name == "PRIVACY.md" ? PRIVACY_SPEC : TERMS_SPEC,
      "Bundled #{name}"
    )
    reject!("Bundled #{name} differs from its canonical source") unless
      bundled.b == sources.fetch(name).first.b
  end
end

def fixture_privacy
  <<~MARKDOWN
    # Dev Island Privacy Notice

    > Engineering-verified draft for owner and legal review.

    Last updated: August 29, 2026

    Questions: [alsoaxu@gmail.com](mailto:alsoaxu@gmail.com) and [puzhen913@gmail.com](mailto:puzhen913@gmail.com).

    ---

    # Dev Island 隐私说明

    > 这是供产品负责人和法律专业人士审阅的草案。

    最后更新：2026 年 8 月 29 日

    联系：[alsoaxu@gmail.com](mailto:alsoaxu@gmail.com) 与 [puzhen913@gmail.com](mailto:puzhen913@gmail.com)。
  MARKDOWN
end

def fixture_terms
  <<~MARKDOWN
    # Dev Island Terms of Use

    > Engineering and product draft for owner and legal review.

    Last updated: August 26, 2026

    Questions: [alsoaxu@gmail.com](mailto:alsoaxu@gmail.com) and [puzhen913@gmail.com](mailto:puzhen913@gmail.com).

    ---

    # Dev Island 使用条款

    > 这是供产品负责人和法律专业人士审阅的工程草案。

    最后更新：2026 年 8 月 26 日

    联系：[alsoaxu@gmail.com](mailto:alsoaxu@gmail.com) 与 [puzhen913@gmail.com](mailto:puzhen913@gmail.com)。
  MARKDOWN
end


def write_fixture(path, contents)
  File.binwrite(path, contents)
  File.chmod(0o600, path)
end

def with_fixture(root)
  Dir.mktmpdir("case-", root) do |directory|
    privacy = File.join(directory, "PRIVACY.md")
    terms = File.join(directory, "TERMS.md")
    bundle = File.join(directory, "Legal")
    write_fixture(privacy, fixture_privacy)
    write_fixture(terms, fixture_terms)
    Dir.mkdir(bundle, 0o700)
    write_fixture(File.join(bundle, "PRIVACY.md"), fixture_privacy)
    write_fixture(File.join(bundle, "TERMS.md"), fixture_terms)
    yield privacy, terms, bundle
  end
end

def expect_rejected(root, label)
  rejected = false
  with_fixture(root) do |privacy, terms, bundle|
    yield privacy, terms, bundle
    begin
      verify_bundle(privacy, terms, bundle)
    rescue LegalDocumentVerificationError
      rejected = true
    end
  end
  reject!("Unsafe legal-document fixture unexpectedly passed: #{label}") unless rejected
end

def run_self_test
  Dir.mktmpdir("dev-island-legal-documents") do |root|
    File.chmod(0o700, root)
    with_fixture(root) do |privacy, terms, bundle|
      verify_source_pair(privacy, terms)
      verify_bundle(privacy, terms, bundle)
    end

    expect_rejected(root, "source symlink") do |privacy, terms, _bundle|
      File.unlink(privacy)
      File.symlink(terms, privacy)
    end
    expect_rejected(root, "source hard link") do |privacy, _terms, _bundle|
      File.link(privacy, "#{privacy}.extra-link")
    end
    expect_rejected(root, "source writable mode") do |privacy, _terms, _bundle|
      File.chmod(0o620, privacy)
    end
    expect_rejected(root, "source oversized") do |privacy, _terms, _bundle|
      write_fixture(privacy, "x" * (MAX_DOCUMENT_BYTES + 1))
    end
    expect_rejected(root, "source invalid UTF-8") do |privacy, _terms, _bundle|
      write_fixture(privacy, fixture_privacy.b + "\xFF".b)
    end
    expect_rejected(root, "missing Chinese section") do |privacy, _terms, _bundle|
      write_fixture(privacy, fixture_privacy.sub("# Dev Island 隐私说明", "# Missing"))
    end
    expect_rejected(root, "mismatched bilingual dates") do |privacy, _terms, _bundle|
      write_fixture(privacy, fixture_privacy.sub("2026 年 8 月 29 日", "2026 年 8 月 28 日"))
    end
    expect_rejected(root, "duplicate separator") do |privacy, _terms, _bundle|
      write_fixture(privacy, fixture_privacy.sub("\n---\n", "\n---\n\n---\n"))
    end
    expect_rejected(root, "bundle byte drift") do |_privacy, _terms, bundle|
      path = File.join(bundle, "PRIVACY.md")
      write_fixture(path, fixture_privacy.sub("Questions:", "Contact:"))
    end
    expect_rejected(root, "bundle extra entry") do |_privacy, _terms, bundle|
      write_fixture(File.join(bundle, "UNREVIEWED.md"), "unexpected\n")
    end
  end

  puts "Legal document fixtures: PASS (10 negative cases)"
end

begin
  if ARGV == ["--self-test"]
    run_self_test
  elsif ARGV.length == 3 && ARGV.first == "--source"
    sources = verify_source_pair(ARGV[1], ARGV[2])
    puts "Legal documents: PASS (source; privacy=#{sources.fetch("PRIVACY.md").last}; terms=#{sources.fetch("TERMS.md").last})"
  elsif ARGV.length == 4 && ARGV.first == "--bundle"
    verify_bundle(ARGV[1], ARGV[2], ARGV[3])
    puts "Legal documents: PASS (bundle matches canonical sources)"
  else
    warn "usage: #{$PROGRAM_NAME} --source PRIVACY TERMS"
    warn "       #{$PROGRAM_NAME} --bundle PRIVACY TERMS LEGAL_BUNDLE_DIRECTORY"
    warn "       #{$PROGRAM_NAME} --self-test"
    exit 64
  end
rescue LegalDocumentVerificationError => error
  warn "error: #{error.message}"
  exit 1
end
