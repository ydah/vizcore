# frozen_string_literal: true

require "vizcore/dsl/engine"
require "vizcore/dsl/mapping_resolver"
require "vizcore/dsl/shader_source_resolver"
require "vizcore/dsl/transition_controller"
require "vizcore/renderer/scene_serializer"

RSpec.describe "example scenes" do
  let(:resolver) { Vizcore::DSL::ShaderSourceResolver.new }
  let(:mapping_resolver) { Vizcore::DSL::MappingResolver.new }
  let(:serializer) { Vizcore::Renderer::SceneSerializer.new }

  let(:audio) do
    {
      amplitude: 0.65,
      bands: { sub: 0.2, low: 0.6, mid: 0.4, high: 0.3 },
      fft: Array.new(32, 0.05),
      beat: true,
      beat_count: 42,
      bpm: 124.0
    }
  end

  {
    "examples/basic.rb" => { expected_scene: "basic" },
    "examples/intro_drop.rb" => { expected_scene: "intro" },
    "examples/midi_scene_switch.rb" => { expected_scene: "warmup" },
    "examples/custom_shader.rb" => { expected_scene: "shader_art", expect_glsl_source: true }
  }.each do |path, expectation|
    it "loads and serializes #{path}" do
      definition = Vizcore::DSL::Engine.load_file(path)
      resolved_definition = resolver.resolve(definition: definition, scene_file: path)
      scene = Array(resolved_definition[:scenes]).first

      expect(scene).to be_a(Hash)
      expect(scene[:name].to_s).to eq(expectation[:expected_scene])
      expect(Array(scene[:layers])).not_to be_empty

      resolved_layers = mapping_resolver.resolve_layers(scene_layers: scene[:layers], audio: audio)
      frame = serializer.audio_frame(
        timestamp: 1.0,
        audio: audio,
        scene_name: scene[:name],
        scene_layers: resolved_layers
      )

      expect(frame.dig(:scene, :layers)).not_to be_empty
      expect(frame.dig(:scene, :layers, 0, :name)).to be_a(String)

      if path == "examples/intro_drop.rb"
        transition_controller = Vizcore::DSL::TransitionController.new(
          scenes: resolved_definition[:scenes],
          transitions: resolved_definition[:transitions]
        )
        transition = transition_controller.next_transition(
          scene_name: :intro,
          audio: audio.merge(beat: false, beat_count: 0),
          frame_count: 360
        )
        expect(transition).not_to be_nil
        expect(transition[:to]).to eq(:drop)
      end

      next unless expectation[:expect_glsl_source]

      shader_layer = frame.fetch(:scene).fetch(:layers).find { |layer| layer[:glsl] }
      expect(shader_layer).not_to be_nil
      expect(shader_layer[:glsl_source]).to be_a(String)
      expect(shader_layer[:glsl_source]).not_to be_empty
    end
  end
end
