# frozen_string_literal: true

require_relative "../layer_catalog"

module Vizcore
  module CLISupport
    # Produces a generated reference for the Ruby DSL entrypoints.
    class DslReference
      Entry = Struct.new(:syntax, :description, keyword_init: true)

      TOP_LEVEL = [
        Entry.new(syntax: "audio :mic, **options", description: "Register an audio input definition."),
        Entry.new(syntax: "midi :controller, **options", description: "Register a MIDI input definition."),
        Entry.new(syntax: "audio_normalize mode: :adaptive", description: "Configure analysis-level normalization."),
        Entry.new(syntax: "bpm 128 / bpm_lock true", description: "Set and optionally lock the analysis BPM."),
        Entry.new(syntax: "tap_tempo key: :space", description: "Enable browser tap tempo events."),
        Entry.new(syntax: "set :global_intensity, 0.8", description: "Set a runtime global exposed to shaders."),
        Entry.new(syntax: "style :name { ... } / theme :name { ... }", description: "Define reusable layer params or scene defaults."),
        Entry.new(syntax: "scene :name, extends: :base { ... }", description: "Define a scene and optional inherited layers."),
        Entry.new(syntax: "section :intro, bars: 8 { ... }", description: "Define beat-counted scenes and generated transitions."),
        Entry.new(syntax: "timeline { at beats(0), scene: :intro }", description: "Define ordered scene markers."),
        Entry.new(syntax: "transition from: :intro, to: :drop { ... }", description: "Define explicit scene transitions."),
        Entry.new(syntax: "midi_map note: 36 { ... }", description: "Map MIDI events to runtime actions."),
        Entry.new(syntax: "key \"d\" { switch_scene :drop }", description: "Map browser keyboard shortcuts to runtime actions.")
      ].freeze

      SCENE = [
        Entry.new(syntax: "use_theme :name", description: "Apply scene-wide layer defaults."),
        Entry.new(syntax: "layer :name { ... }", description: "Append a render layer to the scene.")
      ].freeze

      LAYER = [
        Entry.new(syntax: "type :particle_field", description: "Set the layer renderer type."),
        Entry.new(syntax: "shader :neon_grid / shader \"shaders/liquid.frag\"", description: "Use a built-in or custom fragment shader."),
        Entry.new(syntax: "glsl \"shaders/liquid.frag\"", description: "Load a custom fragment shader file."),
        Entry.new(syntax: "palette \"#ff0055\", \"#00ffff\"", description: "Set ordered colors for supported layer renderers."),
        Entry.new(syntax: "blend :add / effect :bloom / vj_effect :mirror", description: "Set compositing and browser effects."),
        Entry.new(syntax: "param :wobble, default: 0.3, range: 0.0..2.0", description: "Declare numeric shader parameter metadata."),
        Entry.new(syntax: "map amplitude, to: :speed, range: 0.0..2.0", description: "Map audio features to layer params."),
        Entry.new(syntax: "react_to bass { change :size }", description: "Group mappings by source.")
      ].freeze

      SOURCES = %w[
        amplitude frequency_band(:low) sub low bass mid high treble fft_spectrum
        onset onset(:high) kick snare hihat beat? beat beat_confidence beat_pulse beat_count bpm
      ].freeze

      TRANSFORMS = %w[
        gain range min max curve deadzone smooth(attack:,release:)
      ].freeze

      # @return [Array<String>]
      def lines
        [
          "# Vizcore Ruby DSL Reference",
          "",
          "## Top-level DSL",
          *entry_lines(TOP_LEVEL),
          "",
          "## Scene DSL",
          *entry_lines(SCENE),
          "",
          "## Layer DSL",
          *entry_lines(LAYER),
          "",
          "Mapping sources: #{SOURCES.join(', ')}",
          "Mapping transforms: #{TRANSFORMS.join(', ')}",
          "",
          "## Built-in Layer Capabilities",
          *capability_lines
        ]
      end

      private

      def entry_lines(entries)
        entries.map { |entry| "- `#{entry.syntax}` - #{entry.description}" }
      end

      def capability_lines
        Vizcore::LayerCatalog.capabilities.map do |capability|
          aliases = capability.aliases.empty? ? "" : " (aliases: #{capability.aliases.join(', ')})"
          params = capability.params.keys.join(", ")
          mappable = capability.mappable_params.empty? ? "(none)" : capability.mappable_params.join(", ")
          "- `#{capability.type}`#{aliases}: params #{params}; mappable #{mappable}"
        end
      end
    end
  end
end
