#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

require "cgi"
require "digest"
require "open3"
require "optparse"

# Verifies a Hyper VPN DMG and its contained application bundle.
module HyperVpnDmgVerification
  # Raised when a downloaded DMG fails verification.
  class VerificationError < StandardError; end

  # Executes system commands and captures their output.
  class CommandRunner
    Result = Struct.new(:stdout, :stderr, :success?, keyword_init: true)

    def call(*command)
      stdout, stderr, status = Open3.capture3(*command)
      Result.new(stdout: stdout, stderr: stderr, success?: status.success?)
    end
  end

  # Validates checksum, metadata, architecture, signature, and notarization.
  class DmgVerifier
    APP_NAME = "Hyper VPN.app"

    def initialize(dmg:, version:, sha256:, runner: CommandRunner.new)
      @dmg = File.expand_path(dmg)
      @version = version
      @sha256 = sha256.downcase
      @runner = runner
    end

    def verify!
      validate_inputs!
      verify_checksum!

      mount_point = attach!
      begin
        verify_app!(File.join(mount_point, APP_NAME))
      ensure
        detach!(mount_point)
      end

      true
    end

    private

    def validate_inputs!
      raise VerificationError, "DMG not found: #{@dmg}" unless File.file?(@dmg)
      raise VerificationError, "version must not be empty" if @version.empty?
      return if @sha256.match?(/\A[0-9a-f]{64}\z/)

      raise VerificationError, "SHA-256 must be 64 hexadecimal characters"
    end

    def verify_checksum!
      actual = Digest::SHA256.file(@dmg).hexdigest
      return if actual == @sha256

      raise VerificationError, "SHA-256 mismatch: expected #{@sha256}, got #{actual}"
    end

    def attach!
      result = run!("hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen", "-plist", @dmg)
      match = result.stdout.match(%r{<key>mount-point</key>\s*<string>(.*?)</string>}m)
      raise VerificationError, "hdiutil did not report a mount point" unless match

      CGI.unescapeHTML(match[1])
    end

    def verify_app!(app)
      raise VerificationError, "#{APP_NAME} is missing from the DMG" unless File.directory?(app)

      info_plist = File.join(app, "Contents", "Info.plist")
      raise VerificationError, "Info.plist is missing" unless File.file?(info_plist)

      actual_version = plist_value(info_plist, "CFBundleShortVersionString")
      if actual_version != @version
        warning = "app bundle version #{actual_version.inspect} differs from release version #{@version.inspect}"
        warn "verify-dmg: #{warning}"
      end

      executable_name = plist_value(info_plist, "CFBundleExecutable")
      raise VerificationError, "CFBundleExecutable is empty" if executable_name.empty?

      executable = File.join(app, "Contents", "MacOS", executable_name)
      raise VerificationError, "main executable is missing: #{executable_name}" unless File.file?(executable)

      architectures = run!("lipo", "-archs", executable).stdout.split
      unless architectures.include?("arm64")
        raise VerificationError,
              "main executable does not contain arm64: #{architectures.join(" ")}"
      end

      run!("codesign", "--verify", "--deep", "--strict", "--verbose=2", app)
      assessment = run!("spctl", "--assess", "--type", "execute", "--verbose=2", app)
      assessment_output = [assessment.stdout, assessment.stderr].join("\n")
      return if assessment_output.include?("source=Notarized Developer ID")

      raise VerificationError, "app is not a notarized Developer ID application"
    end

    def plist_value(plist, key)
      run!("/usr/libexec/PlistBuddy", "-c", "Print :#{key}", plist).stdout.strip
    end

    def detach!(mount_point)
      result = @runner.call("hdiutil", "detach", mount_point)
      return if result.success?

      force = @runner.call("hdiutil", "detach", "-force", mount_point)
      return if force.success?

      raise VerificationError, "failed to detach #{mount_point}: #{force.stderr.strip}"
    end

    def run!(*command)
      result = @runner.call(*command)
      return result if result.success?

      detail = result.stderr.to_s.strip
      detail = result.stdout.to_s.strip if detail.empty?
      message = command.first.to_s
      message = "#{message} failed: #{detail}" unless detail.empty?
      raise VerificationError, message
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: verify-dmg.rb --dmg PATH --version VERSION --sha256 SHA256"
    opts.on("--dmg PATH", "Downloaded DMG") { |value| options[:dmg] = value }
    opts.on("--version VERSION", "Expected app version") { |value| options[:version] = value }
    opts.on("--sha256 SHA256", "Expected SHA-256") { |value| options[:sha256] = value }
  end

  begin
    parser.parse!
    missing = [:dmg, :version, :sha256].reject { |key| options[key] }
    raise OptionParser::MissingArgument, missing.join(", ") unless missing.empty?

    HyperVpnDmgVerification::DmgVerifier.new(**options).verify!
    puts "DMG verification passed for Hyper VPN #{options[:version]}"
  rescue OptionParser::ParseError, HyperVpnDmgVerification::VerificationError => e
    warn "verify-dmg: #{e.message}"
    exit 1
  end
end
