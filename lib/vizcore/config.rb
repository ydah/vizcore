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
    # Default scene file hot reload behavior.
    DEFAULT_RELOAD = true
    # Supported CLI audio source values.
    SUPPORTED_AUDIO_SOURCES = %i[mic file dummy].freeze

    attr_reader :host, :port, :scene_file, :audio_source, :audio_file, :audio_device, :feature_file, :control_preset, :plugin_assets, :noise_gate, :bpm, :osc_port, :projector_mode

    # @param scene_file [String, Pathname] scene DSL file path
    # @param host [String] bind host
    # @param port [Integer] bind port
    # @param audio_source [Symbol, String] one of `:mic`, `:file`, `:dummy`
    # @param audio_file [String, Pathname, nil] file path used with `audio_source=:file`
    # @param audio_device [String, Integer, nil] input device index/name used with `audio_source=:mic`
    # @param feature_file [String, Pathname, nil] recorded feature JSON used instead of live analysis
    # @param control_preset [String, Pathname, nil] browser control preset JSON
    # @param plugin_assets [Array<String, Pathname>] browser plugin renderer files to serve
    # @param noise_gate [Numeric] RMS threshold below which live input is treated as silence
    # @param bpm [Numeric, nil] fixed BPM value used when BPM lock is enabled
    # @param bpm_lock [Boolean] true when the analysis output BPM should stay fixed
    # @param osc_port [Integer, nil] UDP port for OSC control sync
    # @param reload [Boolean] true when scene file changes should be reloaded while running
    # @param projector_mode [Boolean] true when the browser should hide operator UI by default
    def initialize(
      scene_file:,
      host: DEFAULT_HOST,
      port: DEFAULT_PORT,
      audio_source: DEFAULT_AUDIO_SOURCE,
      audio_file: nil,
      audio_device: nil,
      feature_file: nil,
      control_preset: nil,
      plugin_assets: [],
      noise_gate: DEFAULT_NOISE_GATE,
      bpm: nil,
      bpm_lock: false,
      osc_port: nil,
      reload: DEFAULT_RELOAD,
      projector_mode: false
    )
      @scene_file = Pathname.new(scene_file).expand_path if scene_file
      @host = host
      @port = Integer(port)
      @audio_source = normalize_audio_source(audio_source)
      @audio_file = audio_file ? Pathname.new(audio_file).expand_path : nil
      @audio_device = normalize_audio_device(audio_device)
      @feature_file = feature_file ? Pathname.new(feature_file).expand_path : nil
      @control_preset = control_preset ? Pathname.new(control_preset).expand_path : nil
      @plugin_assets = normalize_plugin_assets(plugin_assets)
      @noise_gate = normalize_noise_gate(noise_gate)
      @bpm = normalize_bpm(bpm)
      @bpm_lock = !!bpm_lock
      @osc_port = normalize_optional_port(osc_port)
      @reload = !!reload
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

    # @return [Boolean] true when scene hot reload is enabled.
    def reload?
      @reload
    end

    # @return [Boolean] true when BPM output should use the fixed BPM value.
    def bpm_lock?
      @bpm_lock
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

    def normalize_bpm(value)
      return nil if value.nil?

      numeric = Float(value)
      raise ArgumentError, "BPM must be positive" unless numeric.positive?

      numeric
    rescue ArgumentError, TypeError
      raise ArgumentError, "BPM must be a positive number"
    end

    def normalize_optional_port(value)
      return nil if value.nil?

      port_value = Integer(value)
      raise ArgumentError, "OSC port must be between 1 and 65535" unless port_value.between?(1, 65_535)

      port_value
    rescue ArgumentError, TypeError
      raise ArgumentError, "OSC port must be between 1 and 65535"
    end

    def normalize_plugin_assets(values)
      Array(values).filter_map do |value|
        raw_value = value.to_s.strip
        next if raw_value.empty?

        value.is_a?(Pathname) ? value.expand_path : Pathname.new(raw_value).expand_path
      end
    end
  end
end
