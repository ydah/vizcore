# frozen_string_literal: true

require "pathname"

module Vizcore
  # Runtime configuration for CLI/server startup.
  class Config
    # Default host used by `vizcore start`.
    DEFAULT_HOST = "127.0.0.1"
    # Default HTTP/WebSocket port.
    DEFAULT_PORT = 4567
    # Default audio source.
    DEFAULT_AUDIO_SOURCE = :mic
    # Default RMS noise gate for live audio.
    DEFAULT_NOISE_GATE = 0.01
    # Supported CLI audio source values.
    SUPPORTED_AUDIO_SOURCES = %i[mic file dummy].freeze

    attr_reader :host, :port, :scene_file, :audio_source, :audio_file, :audio_device, :noise_gate, :projector_mode

    # @param scene_file [String, Pathname] scene DSL file path
    # @param host [String] bind host
    # @param port [Integer] bind port
    # @param audio_source [Symbol, String] one of `:mic`, `:file`, `:dummy`
    # @param audio_file [String, Pathname, nil] file path used with `audio_source=:file`
    # @param audio_device [String, Integer, nil] input device index/name used with `audio_source=:mic`
    # @param noise_gate [Numeric] RMS threshold below which live input is treated as silence
    # @param projector_mode [Boolean] true when the browser should hide operator UI by default
    def initialize(
      scene_file:,
      host: DEFAULT_HOST,
      port: DEFAULT_PORT,
      audio_source: DEFAULT_AUDIO_SOURCE,
      audio_file: nil,
      audio_device: nil,
      noise_gate: DEFAULT_NOISE_GATE,
      projector_mode: false
    )
      @scene_file = Pathname.new(scene_file).expand_path if scene_file
      @host = host
      @port = Integer(port)
      @audio_source = normalize_audio_source(audio_source)
      @audio_file = audio_file ? Pathname.new(audio_file).expand_path : nil
      @audio_device = normalize_audio_device(audio_device)
      @noise_gate = normalize_noise_gate(noise_gate)
      @projector_mode = !!projector_mode
    end

    # @return [Boolean] true when the configured scene file exists.
    def scene_exists?
      scene_file && scene_file.file?
    end

    # @return [Boolean] true when browser output should start without operator UI.
    def projector?
      projector_mode
    end

    private

    def normalize_audio_source(value)
      source = value.to_sym
      return source if SUPPORTED_AUDIO_SOURCES.include?(source)

      raise ArgumentError, "Unsupported audio source: #{value}. Use one of: #{SUPPORTED_AUDIO_SOURCES.join(', ')}"
    end

    def normalize_audio_device(value)
      return nil if value.nil?

      normalized = value.to_s.strip
      return nil if normalized.empty?

      normalized
    end

    def normalize_noise_gate(value)
      Float(value).clamp(0.0, 1.0)
    rescue ArgumentError, TypeError
      raise ArgumentError, "Noise gate must be numeric"
    end
  end
end
