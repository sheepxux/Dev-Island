#!/usr/bin/env ruby

require "digest"
require "json"
require "optparse"
require "rexml/document"
require "rexml/xpath"
require "tempfile"
require "time"
require "tmpdir"

module AnimationHitchSummary
  extend self

  class ValidationError < StandardError; end

  MAX_XML_BYTES = 16 * 1_024 * 1_024
  MAX_LOG_BYTES = 2 * 1_024 * 1_024
  MAX_ROWS = 250_000
  THRESHOLDS_MS = [33.0, 50.0, 100.0].freeze
  RESOLVED_LEAD_SECONDS = 0.20
  RESOLVED_TAIL_SECONDS = 1.00
  STARTUP_TAIL_SECONDS = 0.50
  RECORDING_TAIL_SECONDS = 2.50
  LEGACY_ALIGNMENT_UNCERTAINTY_SECONDS = 0.25

  SCENARIO_KINDS = {
    "decision-approval" => "permission",
    "decision-question" => "question",
    "decision-plan-review" => "planReview",
  }.freeze

  TABLE_COLUMNS = {
    "hitches" => %w[start duration process is-system swap-id label display narrative-description],
    "hitches-updates" => %w[start duration process display swap-id surface-id frame-color containment-level label],
    "potential-hangs" => %w[start duration hang-type thread process],
  }.freeze

  Row = Struct.new(:values) do
    def raw(name)
      values.fetch(name).fetch(:raw)
    end

    def formatted(name)
      values.fetch(name).fetch(:formatted)
    end

    def start_seconds
      raw("start").to_i / 1_000_000_000.0
    end

    def duration_ms
      raw("duration").to_i / 1_000_000.0
    end
  end

  def reject(message)
    raise ValidationError, message
  end

  def read_stable_regular_file(path, label:, maximum_bytes:)
    reject("#{label} path must be absolute") unless path.is_a?(String) && path.start_with?("/")
    reject("#{label} path must be canonical") unless File.expand_path(path) == path

    before = File.lstat(path)
    reject("#{label} must be a regular non-symlink file") unless before.file? && !before.symlink?
    reject("#{label} exceeds the size boundary") if before.size > maximum_bytes

    bytes = File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |input|
      opened = input.stat
      reject("#{label} identity changed before read") unless same_file?(before, opened)
      contents = input.pread(opened.size, 0)
      after = input.stat
      reject("#{label} changed during read") unless contents.bytesize == opened.size && same_file?(opened, after)
      contents
    end
    rebound = File.lstat(path)
    reject("#{label} path changed after read") unless same_file?(before, rebound) && !rebound.symlink?
    reject("#{label} contains a NUL byte") if bytes.include?("\0")
    text = bytes.dup.force_encoding(Encoding::UTF_8)
    reject("#{label} is not valid UTF-8") unless text.valid_encoding?
    [text, Digest::SHA256.hexdigest(bytes)]
  rescue Errno::ENOENT, Errno::ELOOP, Errno::ENOTDIR => error
    reject("#{label} cannot be opened: #{error.class}")
  end

  def same_file?(left, right)
    left.dev == right.dev && left.ino == right.ino &&
      left.uid == right.uid && left.mode == right.mode &&
      left.nlink == right.nlink && left.size == right.size &&
      left.mtime == right.mtime && left.ctime == right.ctime
  end

  def parse_xml(text, label)
    reject("#{label} contains a forbidden DTD or entity declaration") if
      text.match?(/<!DOCTYPE|<!ENTITY/i)
    document = REXML::Document.new(text)
    reject("#{label} has no document element") unless document.root
    document
  rescue REXML::ParseException
    reject("#{label} is malformed XML")
  end

  def parse_toc(path)
    text, sha256 = read_stable_regular_file(path, label: "trace TOC", maximum_bytes: MAX_XML_BYTES)
    document = parse_xml(text, "trace TOC")
    start_nodes = REXML::XPath.match(document, "//start-date")
    duration_nodes = REXML::XPath.match(document, "//info//duration")
    reject("trace TOC must contain exactly one start date") unless start_nodes.length == 1
    reject("trace TOC must contain exactly one recording duration") unless duration_nodes.length == 1
    start_time = Time.iso8601(start_nodes.first.text.to_s)
    duration = strict_decimal(duration_nodes.first.text, "trace duration")
    reject("trace duration is outside the supported boundary") unless duration.positive? && duration <= 86_400
    { start_time: start_time, duration: duration, sha256: sha256 }
  rescue ArgumentError
    reject("trace TOC contains an invalid start date")
  end

  def parse_table(path, schema_name)
    expected_columns = TABLE_COLUMNS.fetch(schema_name)
    text, sha256 = read_stable_regular_file(
      path,
      label: "#{schema_name} export",
      maximum_bytes: MAX_XML_BYTES
    )
    document = parse_xml(text, "#{schema_name} export")
    schemas = REXML::XPath.match(document, "//schema")
    reject("#{schema_name} export must contain one schema") unless schemas.length == 1
    schema = schemas.first
    reject("unexpected table schema #{schema.attributes['name'].inspect}") unless
      schema.attributes["name"] == schema_name
    columns = schema.elements.to_a("col").map { |column| column.elements["mnemonic"]&.text.to_s }
    reject("#{schema_name} export column contract changed") unless columns == expected_columns

    ids = {}
    REXML::XPath.each(document, "//*[@id]") do |element|
      identifier = element.attributes["id"].to_s
      reject("#{schema_name} export contains an invalid element ID") unless identifier.match?(/\A[1-9][0-9]*\z/)
      reject("#{schema_name} export contains a duplicate element ID") if ids.key?(identifier)
      ids[identifier] = element
    end

    row_elements = REXML::XPath.match(document, "//row")
    reject("#{schema_name} export exceeds the row boundary") if row_elements.length > MAX_ROWS
    rows = row_elements.map.with_index do |row, index|
      cells = row.elements.to_a
      reject("#{schema_name} row #{index + 1} has the wrong column count") unless cells.length == columns.length
      values = columns.zip(cells).to_h do |column, cell|
        resolved = resolve_reference(cell, ids, schema_name)
        [column, {
          raw: resolved.text.to_s,
          formatted: resolved.attributes["fmt"].to_s.empty? ? resolved.text.to_s : resolved.attributes["fmt"].to_s,
          type: resolved.name,
        }]
      end
      validate_timing(values, schema_name, index)
      Row.new(values)
    end
    { rows: rows, sha256: sha256 }
  end

  def resolve_reference(element, ids, schema_name)
    reference = element.attributes["ref"]
    return element unless reference
    reject("#{schema_name} export contains a mixed ID/reference cell") if element.attributes["id"]
    resolved = ids[reference.to_s]
    reject("#{schema_name} export contains an unresolved reference") unless resolved
    reject("#{schema_name} export reference changes the cell type") unless resolved.name == element.name
    resolved
  end

  def validate_timing(values, schema_name, index)
    start = strict_integer(values.fetch("start").fetch(:raw), "#{schema_name} row #{index + 1} start")
    duration = strict_integer(values.fetch("duration").fetch(:raw), "#{schema_name} row #{index + 1} duration")
    reject("#{schema_name} row #{index + 1} has a negative start") if start.negative?
    reject("#{schema_name} row #{index + 1} has an invalid duration") unless duration.positive?
    reject("#{schema_name} row #{index + 1} exceeds the duration boundary") if duration > 86_400_000_000_000
  end

  def strict_integer(value, label)
    text = value.to_s
    reject("#{label} is not an integer") unless text.match?(/\A-?(?:0|[1-9][0-9]*)\z/)
    Integer(text, 10)
  end

  def strict_decimal(value, label)
    text = value.to_s
    reject("#{label} is not a bounded decimal") unless text.match?(/\A(?:0|[1-9][0-9]*)(?:\.[0-9]{1,12})?\z/)
    Float(text)
  end

  def parse_action_log(path, scenario, trace_start, trace_duration)
    expected_kind = SCENARIO_KINDS.fetch(scenario) { reject("unsupported decision scenario") }
    text, sha256 = read_stable_regular_file(path, label: "App action log", maximum_bytes: MAX_LOG_BYTES)
    marker_pattern = /^DEV_ISLAND_PERFORMANCE_ACTION phase=(queued|resolved) kind=([A-Za-z]+)(?: result=([A-Za-z]+))? uptime=([0-9]+(?:\.[0-9]+)?)(?: wallUnix=([0-9]+(?:\.[0-9]+)?))?$/
    markers = []
    text.to_enum(:scan, marker_pattern).each do
      match = Regexp.last_match
      markers << {
        phase: match[1], kind: match[2], result: match[3],
        uptime: strict_decimal(match[4], "action marker uptime"),
        wall_unix: match[5] && strict_decimal(match[5], "action marker wall time"),
        end_offset: match.end(0),
      }
    end
    reject("App action log must contain exactly one queued and one resolved marker") unless
      markers.map { |marker| marker[:phase] } == %w[queued resolved]
    queued, resolved = markers
    reject("App action marker kind does not match the scenario") unless
      queued[:kind] == expected_kind && resolved[:kind] == expected_kind
    reject("queued action marker must not contain a result") if queued[:result]
    reject("resolved action marker has no result") unless resolved[:result]
    uptime_delta = resolved[:uptime] - queued[:uptime]
    reject("action marker uptime order is invalid") unless uptime_delta.positive? && uptime_delta <= 120

    alignment = if queued[:wall_unix] && resolved[:wall_unix]
      wall_delta = resolved[:wall_unix] - queued[:wall_unix]
      reject("action wall-clock and monotonic deltas disagree") if (wall_delta - uptime_delta).abs > 0.050
      {
        method: "wall_unix",
        uncertainty_ms: 1.0,
        queued_seconds: queued[:wall_unix] - trace_start.to_f,
        resolved_seconds: resolved[:wall_unix] - trace_start.to_f,
      }
    elsif !queued[:wall_unix] && !resolved[:wall_unix]
      subsequent = text.byteslice(queued[:end_offset]..)&.match(
        /^([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{1,9}[+-][0-9]{4})/
      )
      reject("legacy action log has no timestamp anchor after the queued marker") unless subsequent
      anchor = Time.strptime(subsequent[1], "%Y-%m-%d %H:%M:%S.%N%z")
      queued_seconds = anchor - trace_start
      {
        method: "subsequent_log_timestamp_plus_uptime_delta",
        uncertainty_ms: LEGACY_ALIGNMENT_UNCERTAINTY_SECONDS * 1_000,
        queued_seconds: queued_seconds,
        resolved_seconds: queued_seconds + uptime_delta,
      }
    else
      reject("action markers must either both include wallUnix or both omit it")
    end

    lower_bound = -alignment[:uncertainty_ms] / 1_000.0
    upper_bound = trace_duration + alignment[:uncertainty_ms] / 1_000.0
    reject("queued action marker falls outside the trace") unless alignment[:queued_seconds].between?(lower_bound, upper_bound)
    reject("resolved action marker falls outside the trace") unless alignment[:resolved_seconds].between?(lower_bound, upper_bound)
    alignment.merge(
      kind: expected_kind,
      result: resolved[:result],
      uptime_delta_seconds: uptime_delta,
      sha256: sha256
    )
  rescue ArgumentError
    reject("legacy action log contains an invalid timestamp anchor")
  end

  def duration_statistics(rows)
    durations = rows.map(&:duration_ms)
    statistics = { "count" => rows.length }
    THRESHOLDS_MS.each do |threshold|
      statistics["over_#{threshold.to_i}ms"] = durations.count { |duration| duration > threshold }
    end
    statistics["maximum_ms"] = durations.empty? ? nil : durations.max.round(3)
    statistics
  end

  def summarize_region(hitches, updates, hangs)
    app_frames, render_gpu_only = hitches.partition do |row|
      row.formatted("narrative-description").include?("app update")
    end
    app_updates = updates.select do |row|
      row.formatted("frame-color") == "Red" && row.raw("containment-level") == "1"
    end.uniq { |row| row.raw("swap-id") }
    root_updates = updates.select { |row| row.raw("containment-level") == "0" }
    {
      "display_frame_lifetimes" => duration_statistics(hitches),
      "app_attributed_frame_lifetimes" => duration_statistics(app_frames),
      "render_gpu_only_frame_lifetimes" => duration_statistics(render_gpu_only),
      "app_update_events" => duration_statistics(app_updates),
      "root_update_rows" => duration_statistics(root_updates),
      "potential_hangs" => duration_statistics(hangs),
    }
  end

  def rows_in_window(rows, range)
    rows.select { |row| row.start_seconds >= range.begin && row.start_seconds <= range.end }
  end

  def build_summary(options)
    scenario = options.fetch(:scenario)
    toc = parse_toc(options.fetch(:toc))
    hitches = parse_table(options.fetch(:hitches), "hitches")
    updates = parse_table(options.fetch(:updates), "hitches-updates")
    hangs = parse_table(options.fetch(:potential_hangs), "potential-hangs")
    action = parse_action_log(
      options.fetch(:app_log), scenario, toc[:start_time], toc[:duration]
    )

    recording_range = 0.0..toc[:duration]
    recording_hitches = rows_in_window(hitches[:rows], recording_range)
    recording_updates = rows_in_window(updates[:rows], recording_range)
    recording_hangs = rows_in_window(hangs[:rows], recording_range)
    uncertainty = action[:uncertainty_ms] / 1_000.0
    startup_range = 0.0..[
      action[:queued_seconds] + STARTUP_TAIL_SECONDS + uncertainty,
      toc[:duration],
    ].min
    resolved_range = [
      action[:resolved_seconds] - RESOLVED_LEAD_SECONDS - uncertainty,
      0.0,
    ].max..[
      action[:resolved_seconds] + RESOLVED_TAIL_SECONDS + uncertainty,
      toc[:duration],
    ].min
    recording_tail_range = [toc[:duration] - RECORDING_TAIL_SECONDS, 0.0].max..toc[:duration]
    steady_hitches = recording_hitches.reject do |row|
      startup_range.cover?(row.start_seconds) || resolved_range.cover?(row.start_seconds) ||
        recording_tail_range.cover?(row.start_seconds)
    end
    steady_updates = recording_updates.reject do |row|
      startup_range.cover?(row.start_seconds) || resolved_range.cover?(row.start_seconds) ||
        recording_tail_range.cover?(row.start_seconds)
    end
    steady_hangs = recording_hangs.reject do |row|
      startup_range.cover?(row.start_seconds) || resolved_range.cover?(row.start_seconds) ||
        recording_tail_range.cover?(row.start_seconds)
    end

    {
      "schema_version" => 1,
      "scenario" => scenario,
      "action" => {
        "kind" => action[:kind],
        "result" => action[:result],
        "queued_seconds" => action[:queued_seconds].round(6),
        "resolved_seconds" => action[:resolved_seconds].round(6),
        "uptime_delta_seconds" => action[:uptime_delta_seconds].round(6),
        "alignment_method" => action[:method],
        "alignment_uncertainty_ms" => action[:uncertainty_ms],
      },
      "trace" => {
        "start_date" => toc[:start_time].iso8601(3),
        "duration_seconds" => toc[:duration],
        "out_of_recording_rows" => {
          "hitches" => hitches[:rows].length - recording_hitches.length,
          "updates" => updates[:rows].length - recording_updates.length,
          "potential_hangs" => hangs[:rows].length - recording_hangs.length,
        },
      },
      "windows" => {
        "startup" => [startup_range.begin.round(6), startup_range.end.round(6)],
        "resolved" => [resolved_range.begin.round(6), resolved_range.end.round(6)],
        "recording_tail" => [recording_tail_range.begin.round(6), recording_tail_range.end.round(6)],
      },
      "recording" => summarize_region(recording_hitches, recording_updates, recording_hangs),
      "startup" => summarize_region(
        rows_in_window(recording_hitches, startup_range),
        rows_in_window(recording_updates, startup_range),
        rows_in_window(recording_hangs, startup_range)
      ),
      "resolved" => summarize_region(
        rows_in_window(recording_hitches, resolved_range),
        rows_in_window(recording_updates, resolved_range),
        rows_in_window(recording_hangs, resolved_range)
      ),
      "recording_tail" => summarize_region(
        rows_in_window(recording_hitches, recording_tail_range),
        rows_in_window(recording_updates, recording_tail_range),
        rows_in_window(recording_hangs, recording_tail_range)
      ),
      "steady" => summarize_region(steady_hitches, steady_updates, steady_hangs),
      "evidence_sha256" => {
        "toc" => toc[:sha256],
        "hitches" => hitches[:sha256],
        "updates" => updates[:sha256],
        "potential_hangs" => hangs[:sha256],
        "app_log" => action[:sha256],
      },
    }
  end

  def write_summary(path, summary)
    reject("summary output path must be absolute and canonical") unless
      path.is_a?(String) && path.start_with?("/") && File.expand_path(path) == path
    parent = File.dirname(path)
    parent_stat = File.lstat(parent)
    reject("summary output parent must be a regular directory") unless
      parent_stat.directory? && !parent_stat.symlink?
    reject("summary output parent has an unsafe owner") unless parent_stat.uid == Process.uid
    bytes = JSON.pretty_generate(summary) + "\n"
    File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |output|
      output.write(bytes)
      output.flush
      output.fsync
    end
  rescue Errno::EEXIST, Errno::ELOOP, Errno::ENOENT, Errno::ENOTDIR => error
    reject("summary output cannot be created: #{error.class}")
  end

  def table_xml(schema, columns, rows)
    schema_xml = columns.map do |column|
      "<col><mnemonic>#{column}</mnemonic><name>#{column}</name><engineering-type>string</engineering-type></col>"
    end.join
    rows_xml = rows.map do |row|
      "<row>#{row.map { |name, raw, formatted| "<#{name}#{formatted ? " fmt=\"#{formatted}\"" : ""}>#{raw}</#{name}>" }.join}</row>"
    end.join
    "<?xml version=\"1.0\"?><trace-query-result><node><schema name=\"#{schema}\">#{schema_xml}</schema>#{rows_xml}</node></trace-query-result>"
  end

  def fixture_row(columns, start_ns:, duration_ns:, attributes: {})
    columns.map do |column|
      value = attributes.fetch(column) do
        case column
        when "start" then start_ns.to_s
        when "duration" then duration_ns.to_s
        when "containment-level" then "0"
        when "frame-color" then "Green"
        when "narrative-description" then "Potentially expensive render, Potentially expensive GPU work"
        when "swap-id" then "1"
        else "fixture"
        end
      end
      [column == "start" ? "start-time" : column == "duration" ? "duration" : "string", value, value]
    end
  end

  def run_self_test
    cases = 0
    Dir.mktmpdir("dev-island-animation-hitches") do |directory|
      start = Time.utc(2026, 8, 31, 10, 0, 0)
      toc_path = File.join(directory, "toc.xml")
      hitches_path = File.join(directory, "hitches.xml")
      updates_path = File.join(directory, "updates.xml")
      hangs_path = File.join(directory, "hangs.xml")
      log_path = File.join(directory, "app.log")
      File.write(toc_path, "<trace-toc><run><info><start-date>#{start.iso8601(3)}</start-date><duration>10.0</duration></info></run></trace-toc>")
      File.write(hitches_path, table_xml(
        "hitches", TABLE_COLUMNS.fetch("hitches"), [
          fixture_row(TABLE_COLUMNS.fetch("hitches"), start_ns: 3_000_000_000, duration_ns: 120_000_000,
            attributes: { "narrative-description" => "Potentially expensive app update(s), Potentially expensive render" }),
          fixture_row(TABLE_COLUMNS.fetch("hitches"), start_ns: 11_000_000_000, duration_ns: 200_000_000),
        ]
      ))
      File.write(updates_path, table_xml(
        "hitches-updates", TABLE_COLUMNS.fetch("hitches-updates"), [
          fixture_row(TABLE_COLUMNS.fetch("hitches-updates"), start_ns: 3_010_000_000, duration_ns: 80_000_000,
            attributes: { "frame-color" => "Red", "containment-level" => "1", "swap-id" => "7" }),
        ]
      ))
      File.write(hangs_path, table_xml(
        "potential-hangs", TABLE_COLUMNS.fetch("potential-hangs"), [
          fixture_row(TABLE_COLUMNS.fetch("potential-hangs"), start_ns: 3_020_000_000, duration_ns: 60_000_000),
        ]
      ))
      File.write(log_path, [
        "DEV_ISLAND_PERFORMANCE_ACTION phase=queued kind=permission uptime=100.0 wallUnix=#{start.to_f + 1.0}",
        "DEV_ISLAND_PERFORMANCE_ACTION phase=resolved kind=permission result=deny uptime=102.0 wallUnix=#{start.to_f + 3.0}",
      ].join("\n") + "\n")
      options = {
        scenario: "decision-approval", toc: toc_path, hitches: hitches_path,
        updates: updates_path, potential_hangs: hangs_path, app_log: log_path,
      }
      summary = build_summary(options)
      reject("self-test summary lost the resolved app frame") unless
        summary.dig("resolved", "app_attributed_frame_lifetimes", "over_100ms") == 1
      reject("self-test summary counted an out-of-recording frame") unless
        summary.dig("trace", "out_of_recording_rows", "hitches") == 1
      reject("self-test summary lost the app update event") unless
        summary.dig("resolved", "app_update_events", "over_50ms") == 1
      cases += 1

      legacy_log = File.join(directory, "legacy.log")
      File.write(legacy_log, [
        "DEV_ISLAND_PERFORMANCE_ACTION phase=queued kind=permission uptime=200.0",
        "2026-08-31 10:00:01.100000+0000 IslandApp fixture",
        "DEV_ISLAND_PERFORMANCE_ACTION phase=resolved kind=permission result=deny uptime=202.0",
      ].join("\n") + "\n")
      legacy = build_summary(options.merge(app_log: legacy_log))
      reject("legacy alignment fallback changed") unless
        legacy.dig("action", "alignment_method") == "subsequent_log_timestamp_plus_uptime_delta"
      cases += 1

      attacks = []
      attacks << lambda do
        poisoned = File.join(directory, "doctype.xml")
        File.write(poisoned, '<!DOCTYPE x [<!ENTITY y "z">]><trace-toc/>')
        parse_toc(poisoned)
      end
      attacks << lambda do
        link = File.join(directory, "toc-link.xml")
        File.symlink(toc_path, link)
        parse_toc(link)
      end
      attacks << lambda do
        duplicate_log = File.join(directory, "duplicate.log")
        File.write(duplicate_log, File.read(log_path) + File.readlines(log_path).first)
        build_summary(options.merge(app_log: duplicate_log))
      end
      attacks << lambda do
        wrong_schema = File.join(directory, "wrong-schema.xml")
        File.write(wrong_schema, File.read(hitches_path).sub('name="hitches"', 'name="hitches-v2"'))
        parse_table(wrong_schema, "hitches")
      end
      attacks << lambda do
        unresolved = File.join(directory, "unresolved.xml")
        body = File.read(hitches_path).sub(/<start-time[^>]*>[^<]+<\/start-time>/, '<start-time ref="999"/>')
        File.write(unresolved, body)
        parse_table(unresolved, "hitches")
      end
      attacks << lambda do
        negative = File.join(directory, "negative.xml")
        File.write(negative, File.read(hitches_path).sub('120000000</duration>', '-1</duration>'))
        parse_table(negative, "hitches")
      end
      attacks << lambda do
        drift = File.join(directory, "drift.log")
        File.write(drift, File.read(log_path).sub("wallUnix=#{start.to_f + 3.0}", "wallUnix=#{start.to_f + 4.0}"))
        build_summary(options.merge(app_log: drift))
      end
      attacks.each do |attack|
        begin
          attack.call
          reject("self-test attack fixture was accepted")
        rescue ValidationError
          cases += 1
        end
      end
    end
    puts "Animation hitch summarizer fixtures: PASS (#{cases} cases)"
  end
end

if ARGV == ["--self-test"]
  AnimationHitchSummary.run_self_test
  exit 0
end

options = {}
parser = OptionParser.new do |arguments|
  arguments.banner = "Usage: summarize-animation-hitches.rb --scenario NAME --toc FILE --hitches FILE --updates FILE --potential-hangs FILE --app-log FILE"
  arguments.on("--scenario NAME") { |value| options[:scenario] = value }
  arguments.on("--toc FILE") { |value| options[:toc] = File.expand_path(value) }
  arguments.on("--hitches FILE") { |value| options[:hitches] = File.expand_path(value) }
  arguments.on("--updates FILE") { |value| options[:updates] = File.expand_path(value) }
  arguments.on("--potential-hangs FILE") { |value| options[:potential_hangs] = File.expand_path(value) }
  arguments.on("--app-log FILE") { |value| options[:app_log] = File.expand_path(value) }
  arguments.on("--output FILE") { |value| options[:output] = File.expand_path(value) }
end

begin
  parser.parse!(ARGV)
  AnimationHitchSummary.reject("unexpected positional arguments") unless ARGV.empty?
  required = %i[scenario toc hitches updates potential_hangs app_log]
  missing = required.reject { |key| options.key?(key) }
  AnimationHitchSummary.reject("missing required options: #{missing.join(', ')}") unless missing.empty?
  summary = AnimationHitchSummary.build_summary(options)
  if options[:output]
    AnimationHitchSummary.write_summary(options[:output], summary)
  else
    puts JSON.pretty_generate(summary)
  end
rescue AnimationHitchSummary::ValidationError, OptionParser::ParseError => error
  warn "error: #{error.message}"
  exit 1
end
