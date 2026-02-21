# frozen_string_literal: true

require_relative "../lib/vizcore/version"

tag = ENV["RELEASE_TAG"] || ARGV.first
raise "RELEASE_TAG is required (example: v#{Vizcore::VERSION})" if tag.nil? || tag.empty?

normalized = tag.start_with?("v") ? tag[1..] : tag

if normalized != Vizcore::VERSION
  raise "Release tag (#{tag}) does not match Vizcore::VERSION (#{Vizcore::VERSION})"
end

puts "Release tag verified: #{tag} (version #{Vizcore::VERSION})"
