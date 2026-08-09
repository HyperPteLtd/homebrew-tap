# typed: strict
# frozen_string_literal: true

require "json"
require "fileutils"
require "minitest/autorun"
require "open3"
require "tmpdir"

class UpdateCaskTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/update-cask.rb", __dir__).freeze
  CURRENT_SHA = "0a469127127358239272e01458149d6de0932fda38fea7fa40eb359f01dda19f"
  NEW_SHA = "a" * 64

  def setup
    @directory = Dir.mktmpdir("update-cask-test")
    @cask_path = File.join(@directory, "hyper-vpn.rb")
    @metadata_path = File.join(@directory, "metadata.json")
    File.write(@cask_path, cask("1.0.0", CURRENT_SHA, cask_url(CURRENT_SHA)))
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_same_release_is_idempotent
    original = File.binread(@cask_path)
    write_metadata

    stdout, stderr, status = run_updater

    assert status.success?, stderr
    assert_includes stdout, "updated=false\n"
    assert_equal original, File.binread(@cask_path)
  end

  def test_newer_release_updates_version_sha_and_url
    write_metadata(version: "1.1.0", sha: NEW_SHA)
    output_path = File.join(@directory, "github-output")

    stdout, stderr, status = run_updater("--github-output", output_path)

    assert status.success?, stderr
    assert_includes stdout, "updated=true\n"
    assert_includes stdout, "version=1.1.0\n"
    assert_includes File.read(output_path), "sha=#{NEW_SHA}\n"
    updated = File.read(@cask_path)
    assert_includes updated, 'version "1.1.0"'
    assert_includes updated, "sha256 \"#{NEW_SHA}\""
    assert_includes updated, "url \"#{cask_url(NEW_SHA)}\""

    second_stdout, second_stderr, second_status = run_updater
    assert second_status.success?, second_stderr
    assert_includes second_stdout, "updated=false\n"
  end

  def test_same_version_with_different_artifact_is_rejected
    write_metadata(sha: NEW_SHA)

    _stdout, stderr, status = run_updater

    refute status.success?
    assert_includes stderr, "was repackaged"
  end

  def test_invalid_download_host_is_rejected
    write_metadata(url: "https://example.com/Hyper%20VPN_1.0.0_arm64.dmg")

    _stdout, stderr, status = run_updater

    refute status.success?
    assert_includes stderr, "https://dl.hypervpn.app/"
  end

  def test_invalid_sha_is_rejected
    write_metadata(sha: "not-a-sha")

    _stdout, stderr, status = run_updater

    refute status.success?
    assert_includes stderr, "64 hexadecimal"
  end

  def test_wrong_platform_is_rejected
    write_metadata(platform: "windows")

    _stdout, stderr, status = run_updater

    refute status.success?
    assert_includes stderr, "platform must be macos"
  end

  def test_unsuccessful_api_response_is_rejected
    payload = metadata
    payload["code"] = 500
    File.write(@metadata_path, JSON.generate(payload))

    _stdout, stderr, status = run_updater

    refute status.success?
    assert_includes stderr, "response code must be 200"
  end

  def test_filename_must_contain_exact_version_and_arm64
    write_metadata(file_name: "Hyper VPN_1.0.1_x86_64.dmg")

    _stdout, stderr, status = run_updater

    refute status.success?
    assert_includes stderr, "file_name must be"
  end

  def test_url_filename_must_match_metadata_filename
    write_metadata(url: download_url("9.9.9", CURRENT_SHA))

    _stdout, stderr, status = run_updater

    refute status.success?
    assert_includes stderr, "download_url filename must match"
  end

  def test_malformed_version_is_rejected
    write_metadata(version: "1.1.0-beta")

    _stdout, stderr, status = run_updater

    refute status.success?
    assert_includes stderr, "numeric dotted version"
  end

  def test_downgrade_is_rejected
    write_metadata(version: "0.9.0", sha: NEW_SHA)

    _stdout, stderr, status = run_updater

    refute status.success?
    assert_includes stderr, "refusing downgrade"
  end

  private

  def cask(version, sha, url)
    <<~RUBY
      cask "hyper-vpn" do
        version "#{version}"
        sha256 "#{sha}"

        url "#{url}"
        name "Hyper VPN"
        app "Hyper VPN.app"
      end
    RUBY
  end

  def download_url(version, sha)
    "https://dl.hypervpn.app/ladder/macos/1/#{sha[0, 12]}/Hyper%20VPN_#{version}_arm64.dmg"
  end

  def cask_url(sha)
    "https://dl.hypervpn.app/ladder/macos/1/#{sha[0, 12]}/Hyper%20VPN_\#{version}_arm64.dmg"
  end

  def metadata(version: "1.0.0", sha: CURRENT_SHA, platform: "macos", file_name: nil, url: nil)
    file_name ||= "Hyper VPN_#{version}_arm64.dmg"
    url ||= download_url(version, sha)
    {
      "code" => 200,
      "data" => {
        "platform"     => platform,
        "version_name" => version,
        "sha256"       => sha,
        "file_name"    => file_name,
        "download_url" => url,
      },
    }
  end

  def write_metadata(**overrides)
    File.write(@metadata_path, JSON.generate(metadata(**overrides)))
  end

  def run_updater(*arguments)
    Open3.capture3(
      "ruby", SCRIPT,
      "--metadata-file", @metadata_path,
      "--cask", @cask_path,
      *arguments
    )
  end
end
