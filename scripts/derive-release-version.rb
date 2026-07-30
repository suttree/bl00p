#!/usr/bin/env ruby
# frozen_string_literal: true

unless (5..6).cover?(ARGV.length)
  warn(
    "Usage: #{$PROGRAM_NAME} BASE_VERSION RUN_NUMBER BUILD_NUMBER " \
    "PREVIOUS_BUILD_NUMBER RELEASE_SHA [EXISTING_TAG_SHA]"
  )
  exit 64
end

base_version, run_number_text, build_number_text, previous_build_text,
  release_sha, existing_tag_sha = ARGV

match = /\A(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\z/.match(base_version)
abort "Invalid base version: #{base_version}" unless match

def numeric_argument(name, value, allow_zero: false)
  abort "Invalid #{name}: #{value}" unless /\A(0|[1-9]\d*)\z/.match?(value)

  number = Integer(value, 10)
  abort "#{name} must be positive" if allow_zero ? number.negative? : !number.positive?

  number
end

run_number = numeric_argument("run number", run_number_text)
build_number = numeric_argument("build number", build_number_text)
previous_build = numeric_argument(
  "previous build number",
  previous_build_text,
  allow_zero: true
)

unless /\A[0-9a-f]{40}\z/.match?(release_sha)
  abort "Invalid release commit: #{release_sha}"
end

if existing_tag_sha && !existing_tag_sha.empty?
  unless /\A[0-9a-f]{40}\z/.match?(existing_tag_sha)
    abort "Invalid existing tag commit: #{existing_tag_sha}"
  end
  if existing_tag_sha != release_sha
    abort(
      "Release tag already belongs to #{existing_tag_sha}, " \
      "not #{release_sha}"
    )
  end
end

if build_number < previous_build
  abort(
    "Build number #{build_number} must not be less than " \
    "previous build #{previous_build}"
  )
end

if build_number == previous_build && existing_tag_sha != release_sha
  abort(
    "Build number #{build_number} may only be reused when retrying " \
    "the same tagged release"
  )
end

major, minor, patch = match.captures.map { |component| Integer(component, 10) }
version = [major, minor, patch + run_number].join(".")

puts "version=#{version}"
puts "tag=v#{version}"
puts "build=#{build_number}"
