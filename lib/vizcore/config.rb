# frozen_string_literal: true

require "pathname"

module Vizcore
  # Runtime configuration for CLI/server startup.
  class Config
    DEFAULT_HOST = "127.0.0.1"
    DEFAULT_PORT = 4567
    DEFAULT_AUDIO_SOURCE = :mic
    SUPPORTED_AUDIO_SOURCES = %i[mic file dummy].freeze

    attr_reader :host, :port, :scene_file, :audio_source, :audio_file

    # @param scene_file [String, Pathname] scene DSL file path
    # @param host [String] bind host
    # @param port [Integer] bind port
    # @param audio_source [Symbol, String] one of `:mic`, `:file`, `:dummy`
    # @param audio_file [String, Pathname, nil] file path used with `audio_source=:file`
    def initialize(scene_file:, host: DEFAULT_HOST, port: DEFAULT_PORT, audio_source: DEFAULT_AUDIO_SOURCE, audio_file: nil)
      @scene_file = Pathname.new(scene_file).expand_path if scene_file
      @host = host
      @port = Integer(port)
      @audio_source = normalize_audio_source(audio_source)
      @audio_file = audio_file ? Pathname.new(audio_file).expand_path : nil
    end

    # @return [Boolean] true when the configured scene file exists.
    def scene_exists?
      scene_file && scene_file.file?
    end

    private

    def normalize_audio_source(value)
      source = value.to_sym
      return source if SUPPORTED_AUDIO_SOURCES.include?(source)

      raise ArgumentError, "Unsupported audio source: #{value}. Use one of: #{SUPPORTED_AUDIO_SOURCES.join(', ')}"
    end
  end
end
