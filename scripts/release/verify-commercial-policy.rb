#!/usr/bin/env ruby

require "json"
require "time"
require "uri"

MAXIMUM_POLICY_BYTES = 131_072

class DuplicateCommercialPolicyKey < StandardError; end

class CommercialPolicyObject < Hash
  def []=(key, value)
    raise DuplicateCommercialPolicyKey if key?(key)
    super
  end
end

def fail!(message)
  warn "error: #{message}"
  exit 1
end

def usage!
  warn "Usage: verify-commercial-policy.rb --policy FILE [--require-approved]"
  exit 64
end

policy_path = nil
require_approved = false
arguments = ARGV.dup
until arguments.empty?
  argument = arguments.shift
  case argument
  when "--policy"
    usage! if policy_path || arguments.empty?
    policy_path = arguments.shift
  when "--require-approved"
    usage! if require_approved
    require_approved = true
  else
    usage!
  end
end
usage! unless policy_path

def stable_metadata?(before, after)
  %i[dev ino uid mode nlink size mtime ctime].all? do |field|
    before.public_send(field) == after.public_send(field)
  end
end

def read_commercial_policy(path)
  expanded_path = File.expand_path(path)
  parent_path = File.dirname(expanded_path)
  parent_before = File.lstat(parent_path)
  unless parent_before.directory? && !parent_before.symlink? &&
         parent_before.uid == Process.uid &&
         (parent_before.mode & 0o022).zero?
    fail!("commercial policy parent directory is unsafe")
  end

  flags = File::RDONLY | File::NOFOLLOW | File::NONBLOCK
  File.open(expanded_path, flags) do |file|
    file.binmode
    before = file.stat
    fail!("commercial policy record must be a regular file") unless before.file?
    fail!("commercial policy record owner is unsafe") unless before.uid == Process.uid
    fail!("commercial policy record must have exactly one hard link") unless before.nlink == 1
    fail!("commercial policy record permissions are unsafe") unless (before.mode & 0o022).zero?
    unless before.size.between?(1, MAXIMUM_POLICY_BYTES)
      fail!("commercial policy record size is invalid")
    end

    bytes = file.read(MAXIMUM_POLICY_BYTES + 1)
    after = file.stat
    fail!("commercial policy record changed during inspection") unless stable_metadata?(before, after)
    unless bytes.bytesize == before.size
      fail!("commercial policy record read was incomplete")
    end

    begin
      path_after = File.lstat(expanded_path)
    rescue SystemCallError
      fail!("commercial policy path changed during inspection")
    end
    unless path_after.file? && !path_after.symlink? && stable_metadata?(after, path_after)
      fail!("commercial policy path changed during inspection")
    end

    begin
      parent_after = File.lstat(parent_path)
    rescue SystemCallError
      fail!("commercial policy parent directory changed during inspection")
    end
    unless parent_after.directory? && !parent_after.symlink? &&
           stable_metadata?(parent_before, parent_after)
      fail!("commercial policy parent directory changed during inspection")
    end
    bytes
  end
rescue Errno::ENOENT
  fail!("commercial policy record is missing")
rescue Errno::ELOOP
  fail!("commercial policy record must not be a symbolic link")
rescue SystemCallError
  fail!("commercial policy record could not be opened safely")
end

policy_bytes = read_commercial_policy(policy_path)
begin
  policy = JSON.parse(
    policy_bytes,
    object_class: CommercialPolicyObject,
    create_additions: false
  )
rescue DuplicateCommercialPolicyKey
  fail!("commercial policy record contains a duplicate JSON key")
rescue JSON::ParserError
  fail!("commercial policy record is not valid JSON")
end

def exact_object!(value, keys, label)
  fail!("#{label} must be an object") unless value.is_a?(Hash)
  fail!("#{label} has unknown or missing fields") unless value.keys.sort == keys.sort
end

def optional_enum!(value, values, label)
  return if value.nil?
  fail!("#{label} is invalid") unless value.is_a?(String) && values.include?(value)
end

def optional_text!(value, label, maximum: 254)
  return if value.nil?
  valid = value.is_a?(String) && value.bytesize.between?(1, maximum) &&
    !value.match?(/[\x00-\x1f\x7f]/)
  fail!("#{label} is invalid") unless valid
end

def optional_integer!(value, label, minimum:, maximum:)
  return if value.nil?
  fail!("#{label} is invalid") unless value.is_a?(Integer) && value.between?(minimum, maximum)
end

def optional_origin!(value, label)
  return if value.nil?
  fail!("#{label} is invalid") unless value.is_a?(String)
  begin
    uri = URI.parse(value)
  rescue URI::InvalidURIError
    fail!("#{label} is invalid")
  end
  valid = uri.scheme == "https" && !uri.host.to_s.empty? && uri.userinfo.nil? &&
    uri.query.nil? && uri.fragment.nil? && ["", "/"].include?(uri.path)
  fail!("#{label} must be a credential-free HTTPS origin") unless valid
end

root_keys = %w[access approval decisionState legal lifecycle offer provider schemaVersion seller]
exact_object!(policy, root_keys, "commercial policy record")
fail!("commercial policy schema is unsupported") unless policy["schemaVersion"] == 1
state = policy["decisionState"]
fail!("commercial policy decision state is invalid") unless %w[required approved].include?(state)

approval = policy["approval"]
seller = policy["seller"]
provider = policy["provider"]
offer = policy["offer"]
access = policy["access"]
lifecycle = policy["lifecycle"]
legal = policy["legal"]

exact_object!(approval, %w[legalReviewReference reviewedAt reviewedBy], "commercial policy approval")
exact_object!(seller, %w[jurisdiction legalName model supportContact], "commercial policy seller")
exact_object!(provider, %w[activationOrigin checkoutOrigin dataResidency id retentionDays webhookOrigin], "commercial policy provider")
exact_object!(offer, %w[currency includedUpdateMonths licenseModel priceMinorUnits supportPolicy trialDays trialMode trialStart updatePolicy], "commercial policy offer")
exact_object!(access, %w[deviceIdentity deviceLimit offlineGraceDays recoveryPolicy reinstallPolicy transferPolicy], "commercial policy access")
exact_object!(lifecycle, %w[cancellationPolicy chargebackEffect refundDays refundEffect], "commercial policy lifecycle")
exact_object!(legal, %w[mitRelationship privacyVersion salesRegions termsVersion], "commercial policy legal")

optional_text!(approval["reviewedBy"], "commercial policy reviewer", maximum: 160)
optional_text!(approval["legalReviewReference"], "commercial policy legal review reference", maximum: 200)
unless approval["reviewedAt"].nil?
  begin
    parsed_time = Time.iso8601(approval["reviewedAt"])
    fail!("commercial policy review timestamp must be UTC") unless parsed_time.utc_offset.zero? && approval["reviewedAt"].end_with?("Z")
  rescue ArgumentError, TypeError
    fail!("commercial policy review timestamp is invalid")
  end
end

optional_enum!(seller["model"], %w[merchant-of-record direct-seller], "commercial seller model")
optional_text!(seller["legalName"], "commercial seller legal name", maximum: 160)
optional_text!(seller["jurisdiction"], "commercial seller jurisdiction", maximum: 80)
optional_text!(seller["supportContact"], "commercial support contact")

unless provider["id"].nil?
  valid_provider_id = provider["id"].is_a?(String) && provider["id"].match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/) && provider["id"].bytesize <= 64
  fail!("commercial provider ID is invalid") unless valid_provider_id
end
optional_origin!(provider["checkoutOrigin"], "commercial checkout origin")
optional_origin!(provider["webhookOrigin"], "commercial webhook origin")
optional_origin!(provider["activationOrigin"], "commercial activation origin")
optional_text!(provider["dataResidency"], "commercial provider data residency", maximum: 120)
optional_integer!(provider["retentionDays"], "commercial provider retention days", minimum: 0, maximum: 3_650)

optional_enum!(offer["licenseModel"], %w[one-time subscription], "commercial license model")
optional_integer!(offer["priceMinorUnits"], "commercial price", minimum: 1, maximum: 100_000_000)
unless offer["currency"].nil?
  fail!("commercial currency is invalid") unless offer["currency"].is_a?(String) && offer["currency"].match?(/\A[A-Z]{3}\z/)
end
optional_enum!(offer["trialMode"], %w[none time-limited], "commercial trial mode")
optional_integer!(offer["trialDays"], "commercial trial days", minimum: 1, maximum: 90)
optional_enum!(offer["trialStart"], %w[first-launch checkout activation], "commercial trial start")
optional_enum!(offer["updatePolicy"], %w[perpetual time-limited active-subscription], "commercial update policy")
optional_integer!(offer["includedUpdateMonths"], "commercial included update months", minimum: 1, maximum: 120)
optional_enum!(offer["supportPolicy"], %w[none best-effort time-limited active-subscription], "commercial support policy")

optional_integer!(access["deviceLimit"], "commercial device limit", minimum: 1, maximum: 20)
optional_enum!(access["deviceIdentity"], %w[none random-install-id account-record], "commercial device identity")
optional_enum!(access["transferPolicy"], %w[self-service support-assisted not-supported], "commercial transfer policy")
optional_enum!(access["reinstallPolicy"], %w[restore-existing new-activation support-assisted], "commercial reinstall policy")
optional_integer!(access["offlineGraceDays"], "commercial offline grace", minimum: 0, maximum: 365)
optional_enum!(access["recoveryPolicy"], %w[none email-verified provider-account support-assisted], "commercial recovery policy")

optional_integer!(lifecycle["refundDays"], "commercial refund window", minimum: 0, maximum: 180)
optional_enum!(lifecycle["cancellationPolicy"], %w[not-applicable end-of-term immediate], "commercial cancellation policy")
optional_enum!(lifecycle["refundEffect"], %w[immediate end-of-grace paid-through-date], "commercial refund effect")
optional_enum!(lifecycle["chargebackEffect"], %w[immediate end-of-grace paid-through-date], "commercial chargeback effect")

sales_regions = legal["salesRegions"]
unless sales_regions.is_a?(Array) && sales_regions.length <= 64 &&
       sales_regions.all? { |region| region.is_a?(String) && region.match?(/\A[A-Z]{2}\z/) } &&
       sales_regions == sales_regions.sort && sales_regions.uniq.length == sales_regions.length
  fail!("commercial sales regions must be a sorted unique ISO alpha-2 array")
end
optional_text!(legal["termsVersion"], "commercial terms version", maximum: 64)
optional_text!(legal["privacyVersion"], "commercial privacy version", maximum: 64)
optional_enum!(legal["mitRelationship"], %w[mit-distribution open-core separate-proprietary-service], "commercial MIT relationship")

if offer["trialMode"] == "none" && (!offer["trialDays"].nil? || !offer["trialStart"].nil?)
  fail!("commercial no-trial policy must not carry trial timing")
elsif offer["trialMode"] == "time-limited" && (offer["trialDays"].nil? || offer["trialStart"].nil?)
  fail!("commercial time-limited trial requires duration and start policy")
end

if %w[perpetual active-subscription].include?(offer["updatePolicy"]) && !offer["includedUpdateMonths"].nil?
  fail!("commercial update policy carries an incompatible month limit")
elsif offer["updatePolicy"] == "time-limited" && offer["includedUpdateMonths"].nil?
  fail!("commercial time-limited updates require a month limit")
end

sections = [approval, seller, provider, offer, access, lifecycle]
missing = sections.sum { |section| section.values.count(&:nil?) }
missing += legal.values_at("termsVersion", "privacyVersion", "mitRelationship").count(&:nil?)
missing += 1 if sales_regions.empty?

if state == "required"
  unless approval.values.all?(&:nil?)
    fail!("unapproved commercial policy must not carry approval evidence")
  end
elsif missing.positive?
  fail!("approved commercial policy is incomplete")
end

if require_approved && state != "approved"
  fail!("commercial launch blocked by unapproved policy record")
end

puts "Commercial policy record: PASS (state=#{state}, missing=#{missing})"
