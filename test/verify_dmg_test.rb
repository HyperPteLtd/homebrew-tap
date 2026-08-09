# frozen_string_literal: true

require "digest"
require "fileutils"
require "minitest/autorun"
require "tmpdir"
require_relative "../scripts/verify-dmg"

class FakeRunner
  attr_reader :commands

  def initialize(
    mount_point:,
    version: "1.0.0",
    executable: "Hyper VPN",
    architectures: "arm64",
    notarization_source: "Notarized Developer ID",
    failures: {}
  )
    @mount_point = mount_point
    @version = version
    @executable = executable
    @architectures = architectures
    @notarization_source = notarization_source
    @failures = failures
    @commands = []
  end

  def call(*command)
    @commands << command
    key = command_key(command)
    return result("", @failures.fetch(key), false) if @failures.key?(key)

    case key
    when "attach"
      result("<plist><dict><key>mount-point</key><string>#{CGI.escapeHTML(@mount_point)}</string></dict></plist>")
    when "version"
      result("#{@version}\n")
    when "executable"
      result("#{@executable}\n")
    when "lipo"
      result("#{@architectures}\n")
    when "spctl"
      result("", "accepted\nsource=#{@notarization_source}\n")
    else
      result
    end
  end

  private

  def command_key(command)
    return "attach" if command[0..1] == ["hdiutil", "attach"]
    return "detach-force" if command[0..2] == ["hdiutil", "detach", "-force"]
    return "detach" if command[0..1] == ["hdiutil", "detach"]
    return "version" if command.include?("Print :CFBundleShortVersionString")
    return "executable" if command.include?("Print :CFBundleExecutable")

    command.first
  end

  def result(stdout = "", stderr = "", success = true)
    CommandRunner::Result.new(stdout: stdout, stderr: stderr, success?: success)
  end
end

class DmgVerifierTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @dmg = File.join(@tmpdir, "Hyper VPN.dmg")
    File.binwrite(@dmg, "test dmg")
    @sha256 = Digest::SHA256.file(@dmg).hexdigest
    @mount = File.join(@tmpdir, "mounted & volume")
    @app = File.join(@mount, "Hyper VPN.app")
    FileUtils.mkdir_p(File.join(@app, "Contents", "MacOS"))
    FileUtils.touch(File.join(@app, "Contents", "Info.plist"))
    FileUtils.touch(File.join(@app, "Contents", "MacOS", "Hyper VPN"))
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_accepts_matching_signed_notarized_arm64_app
    runner = FakeRunner.new(mount_point: @mount)

    assert verifier(runner).verify!
    assert_includes runner.commands, ["codesign", "--verify", "--deep", "--strict", "--verbose=2", @app]
    assert_includes runner.commands, ["spctl", "--assess", "--type", "execute", "--verbose=2", @app]
    assert_includes runner.commands, ["hdiutil", "detach", @mount]
  end

  def test_rejects_checksum_mismatch_before_mounting
    runner = FakeRunner.new(mount_point: @mount)

    error = assert_raises(VerificationError) { DmgVerifier.new(dmg: @dmg, version: "1.0.0", sha256: "0" * 64, runner: runner).verify! }
    assert_match(/SHA-256 mismatch/, error.message)
    assert_empty runner.commands
  end

  def test_rejects_app_version_that_disagrees_with_metadata_and_detaches
    runner = FakeRunner.new(mount_point: @mount, version: "9.9.9")

    error = assert_raises(VerificationError) { verifier(runner).verify! }
    assert_match(/app version mismatch/, error.message)
    assert_includes runner.commands, ["hdiutil", "detach", @mount]
  end

  def test_rejects_executable_without_arm64_and_detaches
    runner = FakeRunner.new(mount_point: @mount, architectures: "x86_64")

    error = assert_raises(VerificationError) { verifier(runner).verify! }
    assert_match(/does not contain arm64/, error.message)
    assert_includes runner.commands, ["hdiutil", "detach", @mount]
  end

  def test_rejects_codesign_failure_and_detaches
    runner = FakeRunner.new(mount_point: @mount, failures: { "codesign" => "invalid signature" })

    error = assert_raises(VerificationError) { verifier(runner).verify! }
    assert_match(/codesign failed: invalid signature/, error.message)
    assert_includes runner.commands, ["hdiutil", "detach", @mount]
  end

  def test_rejects_successful_assessment_without_notarization_and_detaches
    runner = FakeRunner.new(mount_point: @mount, notarization_source: "Developer ID")

    error = assert_raises(VerificationError) { verifier(runner).verify! }
    assert_match(/not a notarized Developer ID/, error.message)
    assert_includes runner.commands, ["hdiutil", "detach", @mount]
  end

  def test_retries_detach_with_force
    runner = FakeRunner.new(mount_point: @mount, failures: { "detach" => "busy" })

    assert verifier(runner).verify!
    assert_includes runner.commands, ["hdiutil", "detach", "-force", @mount]
  end

  def test_fails_if_normal_and_forced_detach_both_fail
    runner = FakeRunner.new(mount_point: @mount, failures: { "detach" => "busy", "detach-force" => "still busy" })

    error = assert_raises(VerificationError) { verifier(runner).verify! }
    assert_match(/failed to detach/, error.message)
  end

  private

  def verifier(runner)
    DmgVerifier.new(dmg: @dmg, version: "1.0.0", sha256: @sha256, runner: runner)
  end
end
