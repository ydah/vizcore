# frozen_string_literal: true

require "rubygems/package"
require "stringio"
require "zlib"

module Release
  class GemContentsVerifier
    REQUIRED_FILES = %w[
      README.md
      GETTING_STARTED.md
      LICENSE.txt
      exe/vizcore
      lib/vizcore.rb
      frontend/index.html
    ].freeze

    FORBIDDEN_PREFIXES = %w[
      spec/
      .github/
      frontend/test/
    ].freeze

    def initialize(gem_path = nil, io: $stdout)
      @gem_path = gem_path || latest_gem
      @io = io
    end

    def run
      raise "No built gem file found (expected vizcore-*.gem)" unless @gem_path

      files = packaged_files(@gem_path)
      missing = REQUIRED_FILES.reject { |path| files.include?(path) }
      forbidden = files.select do |path|
        FORBIDDEN_PREFIXES.any? { |prefix| path.start_with?(prefix) }
      end

      if missing.any? || forbidden.any?
        raise <<~MSG
          Gem content verification failed for #{@gem_path}
          Missing required files:
            #{missing.empty? ? "(none)" : missing.join("\n  ")}
          Forbidden packaged files:
            #{forbidden.empty? ? "(none)" : forbidden.join("\n  ")}
        MSG
      end

      @io.puts("Gem content verification passed: #{@gem_path}")
      @io.puts("Packaged files: #{files.length}")
    end

    private

    def latest_gem
      Dir.glob("vizcore-*.gem").max_by { |path| File.mtime(path) }
    end

    def packaged_files(gem_path)
      data_tar_gz = nil
      File.open(gem_path, "rb") do |file|
        Gem::Package::TarReader.new(file) do |tar|
          tar.each do |entry|
            next unless entry.file?
            next unless entry.full_name == "data.tar.gz"

            data_tar_gz = entry.read
            break
          end
        end
      end

      raise "data.tar.gz not found in #{gem_path}" unless data_tar_gz

      files = []
      Zlib::GzipReader.wrap(StringIO.new(data_tar_gz)) do |gz|
        Gem::Package::TarReader.new(gz) do |data_tar|
          data_tar.each do |entry|
            files << entry.full_name if entry.file?
          end
        end
      end

      files.sort
    end
  end
end

Release::GemContentsVerifier.new(ARGV[0]).run
