#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "optparse"
require "pathname"
require "tempfile"
require "uri"
require "rubygems/version"

API_URL = "https://hypervpn.app/v1/public/app/latest?platform=macos"
ROOT = Pathname(__dir__).parent
DEFAULT_CASK = ROOT.join("Casks/hyper-vpn.rb")

class UpdateError < StandardError; end

def parse_options
  options = {
    api_url: ENV.fetch("HYPER_VPN_API_URL", API_URL),
    metadata_file: ENV["HYPER_VPN_METADATA_FILE"],
    cask: DEFAULT_CASK.to_s,
    github_output: ENV["GITHUB_OUTPUT"],
  }

  OptionParser.new do |parser|
    parser.banner = "Usage: scripts/update-cask.rb [options]"
    parser.on("--api-url URL", "Latest-version API URL") { |value| options[:api_url] = value }
    parser.on("--metadata-file PATH", "Read API JSON from a local file") { |value| options[:metadata_file] = value }
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
    unless response.is_a?(Net::HTTPSuccess)
      raise UpdateError, "latest-version API returned HTTP #{response.code}"
    end

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
  unless metadata.is_a?(Hash) && metadata["code"] == 200
    raise UpdateError, "latest-version API response code must be 200"
  end

  data = metadata["data"]
  raise UpdateError, "response data must be an object" unless data.is_a?(Hash)
  raise UpdateError, "platform must be macos" unless data["platform"] == "macos"

  version = data["version_name"]
  unless version.is_a?(String) && version.match?(/\A\d+(?:\.\d+)*\z/)
    raise UpdateError, "version_name must be a numeric dotted version"
  end

  sha = data["sha256"]
  unless sha.is_a?(String) && sha.match?(/\A[0-9a-f]{64}\z/i)
    raise UpdateError, "sha256 must contain exactly 64 hexadecimal characters"
  end
  sha = sha.downcase

  file_name = data["file_name"]
  expected_file_name = "Hyper VPN_#{version}_arm64.dmg"
  unless file_name == expected_file_name
    raise UpdateError, "file_name must be #{expected_file_name.inspect}"
  end

  url = data["download_url"]
  begin
    uri = URI.parse(url.to_s)
  rescue URI::InvalidURIError => e
    raise UpdateError, "invalid download_url: #{e.message}"
  end
  unless uri.is_a?(URI::HTTPS) && uri.host == "dl.hypervpn.app" && uri.port == 443 && !uri.userinfo
    raise UpdateError, "download_url must use https://dl.hypervpn.app/"
  end
  if uri.query || uri.fragment || URI.decode_www_form_component(File.basename(uri.path)) != file_name
    raise UpdateError, "download_url filename must match file_name"
  end

  cask_url = url.sub(/#{Regexp.escape(version)}(?=_arm64\.dmg\z)/, '#{version}')
  raise UpdateError, "download_url does not contain versioned arm64 filename" if cask_url == url

  { version: version, sha: sha, url: url, cask_url: cask_url }
end

def current_release(cask)
  version = cask[/^\s*version\s+"([^"]+)"\s*$/, 1]
  sha = cask[/^\s*sha256\s+"([0-9a-fA-F]{64})"\s*$/, 1]
  url = cask[/^\s*url\s+"([^"]+)"\s*$/, 1]
  raise UpdateError, "cask must contain one literal version, sha256, and url" unless version && sha && url

  expanded_url = url.gsub('#{version}', version)
  { version: version, sha: sha.downcase, url: expanded_url, cask_url: url }
end

def replace_once!(contents, pattern, replacement, field)
  matches = contents.scan(pattern)
  raise UpdateError, "expected exactly one #{field} declaration in cask" unless matches.length == 1

  contents.sub(pattern, replacement)
end

def atomic_update(path, release)
  original = File.read(path)
  updated = replace_once!(original, /^(\s*)version\s+"[^"]+"\s*$/, "\\1version \"#{release[:version]}\"", "version")
  updated = replace_once!(updated, /^(\s*)sha256\s+"[0-9a-fA-F]{64}"\s*$/, "\\1sha256 \"#{release[:sha]}\"", "sha256")
  updated = replace_once!(updated, /^(\s*)url\s+"[^"]+"\s*$/, "\\1url \"#{release[:cask_url]}\"", "url")

  path = Pathname(path)
  Tempfile.create([".#{path.basename}", ".tmp"], path.dirname) do |file|
    file.binmode
    file.write(updated)
    file.flush
    file.fsync
    File.chmod(File.stat(path).mode, file.path)
    File.rename(file.path, path)
  end
end

def emit_outputs(values, github_output)
  lines = values.map { |key, value| "#{key}=#{value}" }.join("\n") + "\n"
  print lines
  File.open(github_output, "a") { |file| file.write(lines) } if github_output && !github_output.empty?
end

def run
  options = parse_options
  cask_contents = File.read(options[:cask])
  current = current_release(cask_contents)
  release = validated_release(fetch_metadata(options))
  comparison = Gem::Version.new(release[:version]) <=> Gem::Version.new(current[:version])

  if comparison.negative?
    raise UpdateError, "refusing downgrade from #{current[:version]} to #{release[:version]}"
  end

  if comparison.zero?
    if release[:sha] != current[:sha] || release[:url] != current[:url]
      raise UpdateError, "version #{release[:version]} was repackaged; refusing to overwrite the cask"
    end

    emit_outputs({ updated: false, version: release[:version], url: release[:url], sha: release[:sha] }, options[:github_output])
    return
  end

  atomic_update(options[:cask], release)
  emit_outputs({ updated: true, version: release[:version], url: release[:url], sha: release[:sha] }, options[:github_output])
rescue UpdateError, Errno::ENOENT, Errno::EACCES => e
  warn "update-cask: #{e.message}"
  exit 1
end

run if $PROGRAM_NAME == __FILE__
