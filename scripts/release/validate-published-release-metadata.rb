#!/usr/bin/env ruby

require "json"

def fail(message)
  warn "error: #{message}"
  exit 1
end

unless ARGV.length == 4 && ARGV[0] == "--json" && ARGV[2] == "--tag"
  warn "Usage: validate-published-release-metadata.rb --json FILE --tag vX.Y.Z"
  exit 64
end

json_path = ARGV[1]
tag = ARGV[3]
tag_match = tag.match(/\Av((?:0|[1-9][0-9]{0,3})\.(?:0|[1-9][0-9]?)\.(?:0|[1-9][0-9]?))\z/)
fail("tag must be v followed by a canonical numeric version") unless tag_match
version = tag_match[1]
repository = "sheepxux/Dev-Island"

begin
  metadata = File.lstat(json_path)
rescue Errno::ENOENT
  fail("GitHub Release metadata file does not exist")
end
fail("GitHub Release metadata must be a regular non-symlink file") unless metadata.file? && !metadata.symlink?
fail("GitHub Release metadata size is invalid") unless metadata.size.between?(1, 2 * 1_024 * 1_024)

begin
  release = JSON.parse(File.binread(json_path))
rescue JSON::ParserError
  fail("GitHub Release API returned malformed JSON")
end
fail("GitHub Release API root must be an object") unless release.is_a?(Hash)

expected = [
  "Dev-Island.dmg",
  "Dev-Island-#{version}.dmg",
  "Dev-Island.zip",
  "Dev-Island-#{version}.zip",
  "Dev-Island.spdx.json",
  "SHA256SUMS",
  "appcast.xml",
  "dev-island.rb",
].sort

fail("GitHub Release tag does not match the requested tag") unless release["tag_name"] == tag
fail("GitHub Release is still a draft") unless release["draft"] == false
fail("GitHub Release is marked as a prerelease") unless release["prerelease"] == false
assets = release["assets"]
fail("GitHub Release asset list is absent") unless assets.is_a?(Array)
fail("GitHub Release contains a malformed asset record") unless assets.all? { |asset| asset.is_a?(Hash) }
names = assets.map { |asset| asset["name"] }
fail("GitHub Release contains a malformed asset name") unless names.all? { |name| name.is_a?(String) && !name.empty? }
duplicates = names.group_by(&:itself).select { |_name, copies| copies.length > 1 }.keys.sort
fail("GitHub Release contains duplicate asset names: #{duplicates.join(" ")}") unless duplicates.empty?
missing = expected - names
extras = names - expected
unless missing.empty?
  fail("published Release #{tag} is legacy or incomplete; missing required assets: #{missing.join(" ")}")
end
fail("published Release #{tag} contains unexpected assets: #{extras.join(" ")}") unless extras.empty?
fail("published Release must contain exactly eight assets") unless assets.length == expected.length
assets.each do |asset|
  name = asset.fetch("name")
  fail("GitHub Release asset did not finish uploading: #{name}") unless asset["state"] == "uploaded"
  fail("GitHub Release asset is empty: #{name}") unless asset["size"].is_a?(Integer) && asset["size"] > 0
  expected_url = "https://github.com/#{repository}/releases/download/#{tag}/#{name}"
  fail("GitHub Release asset URL is not immutable: #{name}") unless asset["browser_download_url"] == expected_url
end

puts "Published Release metadata contract: PASS (#{tag}, #{assets.length} assets)"
