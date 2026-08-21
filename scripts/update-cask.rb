#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

require "json"
require "net/http"
require "optparse"
require "tempfile"
require "uri"
require "rubygems/version"

# Fetches, validates, and applies Hyper VPN cask release metadata.
module HyperVpnCaskUpdater
  API_URL = "https://hypervpn.app/v1/public/app/latest?platform=macos"
  ROOT = File.expand_path("..", __dir__).freeze
  DEFAULT_CASK = File.join(ROOT, "Casks/hyper-vpn.rb").freeze
  VERSION_INTERPOLATION = "\#{version}"
  ARTIFACT_VARIANTS = %w[arm64 universal].freeze

  # Raised when upstream metadata or the local cask is invalid.
  class UpdateError < StandardError; end

  module_function

  def parse_options
    options = {
      api_url:       ENV.fetch("HYPER_VPN_API_URL", API_URL),
      metadata_file: ENV.fetch("HYPER_VPN_METADATA_FILE", nil),
      cask:          DEFAULT_CASK,
      github_output: ENV.fetch("GITHUB_OUTPUT", nil),
    }

    OptionParser.new do |parser|
      parser.banner = "Usage: scripts/update-cask.rb [options]"
      parser.on("--api-url URL", "Latest-version API URL") { |value| options[:api_url] = value }
      parser.on("--metadata-file PATH", "Read API JSON from a local file") do |value|
        options[:metadata_file] = value
      end
      parser.on("--cask PATH", "Cask file to update") { |value| options[:cask] = value }
      parser.on("--github-output PATH", "Append outputs to a GitHub Actions output file") do |value|
        options[:github_output] = value
      end
    end.parse!

    options
  end

  def fetch_metadata(options)
    body = if options[:metadata_file]
      File.read(options[:metadata_file])
    else
      uri = URI.parse(options[:api_url])
      raise UpdateError, "API URL must use HTTPS" unless uri.is_a?(URI::HTTPS)

      response = Net::HTTP.get_response(uri)
      raise UpdateError, "latest-version API returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response.body
    end

    JSON.parse(body)
  rescue Errno::ENOENT => e
    raise UpdateError, e.message
  rescue JSON::ParserError => e
    raise UpdateError, "latest-version API returned invalid JSON: #{e.message}"
  rescue URI::InvalidURIError => e
    raise UpdateError, "invalid API URL: #{e.message}"
  end

  def validated_release(metadata)
    raise UpdateError, "latest-version API response must be an object" unless metadata.is_a?(Hash)
    raise UpdateError, "latest-version API response code must be 200" if metadata["code"] != 200

    data = metadata["data"]
    raise UpdateError, "response data must be an object" unless data.is_a?(Hash)
    raise UpdateError, "platform must be macos" if data["platform"] != "macos"

    version = data["version_name"]
    raise UpdateError, "version_name must be a string" unless version.is_a?(String)
    raise UpdateError, "version_name must be a numeric dotted version" unless version.match?(/\A\d+(?:\.\d+)*\z/)

    sha = data["sha256"]
    raise UpdateError, "sha256 must be a string" unless sha.is_a?(String)
    unless sha.match?(/\A[0-9a-f]{64}\z/i)
      raise UpdateError, "sha256 must contain exactly 64 hexadecimal characters"
    end

    sha = sha.downcase

    file_name = data["file_name"]
    expected_file_names = ARTIFACT_VARIANTS.map { |variant| "Hyper VPN_#{version}_#{variant}.dmg" }
    unless expected_file_names.include?(file_name)
      raise UpdateError, "file_name must be one of #{expected_file_names.map(&:inspect).join(", ")}"
    end

    url = data["download_url"]
    uri = parse_download_uri(url)
    valid_uri = uri.is_a?(URI::HTTPS) && uri.host == "dl.hypervpn.app" && uri.port == 443 && !uri.userinfo
    raise UpdateError, "download_url must use https://dl.hypervpn.app/" unless valid_uri

    decoded_name = URI.decode_www_form_component(File.basename(uri.path))
    valid_filename = uri.query.nil? && uri.fragment.nil? && decoded_name == file_name
    raise UpdateError, "download_url filename must match file_name" unless valid_filename

    variant_pattern = Regexp.union(ARTIFACT_VARIANTS)
    cask_url = url.sub(/#{Regexp.escape(version)}(?=_(?:#{variant_pattern})\.dmg\z)/, VERSION_INTERPOLATION)
    if cask_url == url
      raise UpdateError, "download_url does not contain a supported versioned filename"
    end

    { version: version, sha: sha, url: url, cask_url: cask_url }
  end

  def parse_download_uri(url)
    URI.parse(url.to_s)
  rescue URI::InvalidURIError => e
    raise UpdateError, "invalid download_url: #{e.message}"
  end

  def current_release(cask)
    version = cask[/^[ \t]*version\s+"([^"]+)"[ \t]*$/, 1]
    sha = cask[/^[ \t]*sha256\s+"([0-9a-fA-F]{64})"[ \t]*$/, 1]
    url = cask[/^[ \t]*url\s+"([^"]+)"[ \t]*$/, 1]
    if [version, sha, url].any?(&:nil?)
      raise UpdateError, "cask must contain one literal version, sha256, and url"
    end

    expanded_url = url.gsub(VERSION_INTERPOLATION, version)
    { version: version, sha: sha.downcase, url: expanded_url, cask_url: url }
  end

  def replace_once!(contents, pattern, replacement, field)
    matches = contents.scan(pattern)
    if matches.length != 1
      raise UpdateError, "expected exactly one #{field} declaration in cask"
    end

    contents.sub(pattern, replacement)
  end

  def atomic_update(path, release)
    original = File.read(path)
    version_pattern = /^([ \t]*)version\s+"[^"]+"[ \t]*$/
    updated = replace_once!(original, version_pattern, "\\1version \"#{release[:version]}\"", "version")
    sha_pattern = /^([ \t]*)sha256\s+"[0-9a-fA-F]{64}"[ \t]*$/
    updated = replace_once!(updated, sha_pattern, "\\1sha256 \"#{release[:sha]}\"", "sha256")
    updated = replace_once!(updated, /^(  )url\s+"[^"]+"[ \t]*$/, "\\1url \"#{release[:cask_url]}\"", "url")

    expanded_path = File.expand_path(path)
    directory = File.dirname(expanded_path)
    basename = File.basename(expanded_path)
    Tempfile.create([".#{basename}", ".tmp"], directory) do |file|
      file.binmode
      file.write(updated)
      file.flush
      file.fsync
      File.chmod(File.stat(expanded_path).mode, file.path)
      File.rename(file.path, expanded_path)
    end
  end

  def emit_outputs(values, github_output)
    lines = "#{values.map { |key, value| "#{key}=#{value}" }.join("\n")}\n"
    print lines
    return if github_output.to_s.empty?

    File.open(github_output, "a") { |file| file.write(lines) }
  end

  def run
    options = parse_options
    current = current_release(File.read(options[:cask]))
    release = validated_release(fetch_metadata(options))
    comparison = Gem::Version.new(release[:version]) <=> Gem::Version.new(current[:version])

    if comparison.negative?
      raise UpdateError, "refusing downgrade from #{current[:version]} to #{release[:version]}"
    end

    updated = !comparison.zero?
    if updated
      atomic_update(options[:cask], release)
    elsif release[:sha] != current[:sha] || release[:url] != current[:url]
      raise UpdateError, "version #{release[:version]} was repackaged; refusing to overwrite the cask"
    end

    output = { updated: updated, version: release[:version], url: release[:url], sha: release[:sha] }
    emit_outputs(output, options[:github_output])
  rescue UpdateError, Errno::ENOENT, Errno::EACCES => e
    warn "update-cask: #{e.message}"
    exit 1
  end
end

HyperVpnCaskUpdater.run if $PROGRAM_NAME == __FILE__
