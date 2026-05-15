# frozen_string_literal: true

require "fileutils"
require_relative "../analysis"
require_relative "../audio"
require_relative "../dsl"
require_relative "snapshot_renderer"

module Vizcore
  module Renderer
    # Builds one analyzed scene frame and writes a PNG preview.
    class Snapshot
      def initialize(config:, width: SnapshotRenderer::DEFAULT_WIDTH, height: SnapshotRenderer::DEFAULT_HEIGHT)
        @config = config
        @width = width
        @height = height
        @shader_source_resolver = Vizcore::DSL::ShaderSourceResolver.new
      end

      # @param out [String, Pathname]
      # @return [Hash] snapshot metadata
      def write(out:)
        output_path = Pathname.new(out.to_s).expand_path
        definition = resolve_shader_sources(Vizcore::DSL::Engine.load_file(@config.scene_file.to_s))
        scene = first_scene(definition)
        audio = analyze_audio
        layers = Vizcore::DSL::MappingResolver.new.resolve_layers(scene_layers: scene[:layers], audio: audio)
        png = SnapshotRenderer.new(width: @width, height: @height).render(
          scene: { name: scene[:name], layers: layers },
          audio: audio
        )

        FileUtils.mkdir_p(output_path.dirname)
        File.binwrite(output_path, png)
        { path: output_path, scene: scene[:name].to_s, width: @width, height: @height }
      end

      private

      def resolve_shader_sources(definition)
        @shader_source_resolver.resolve(definition: definition, scene_file: @config.scene_file.to_s)
      end

      def first_scene(definition)
        scene = Array(definition[:scenes]).first
        return scene if scene

        { name: @config.scene_file.basename(".rb").to_sym, layers: [] }
      end

      def analyze_audio
        input_manager = Vizcore::Audio::InputManager.new(
          source: @config.audio_source,
          file_path: @config.audio_file&.to_s,
          audio_device: @config.audio_device
        )
        input_manager.start
        samples = input_manager.capture_frame
        pipeline = Vizcore::Analysis::Pipeline.new(
          sample_rate: input_manager.sample_rate,
          fft_size: supported_fft_size(input_manager.frame_size),
          noise_gate: @config.noise_gate
        )
        pipeline.call(samples)
      ensure
        input_manager&.stop
      end

      def supported_fft_size(size)
        value = Integer(size)
        return value if value.positive? && (value & (value - 1)).zero?

        1024
      rescue StandardError
        1024
      end
    end
  end
end
