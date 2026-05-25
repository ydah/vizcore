# frozen_string_literal: true

module Vizcore
  module CLISupport
    # Produces the custom GLSL uniform reference used by CLI and docs.
    class ShaderUniformDocs
      Uniform = Struct.new(:name, :type, :description, keyword_init: true)

      UNIFORMS = [
        Uniform.new(name: "u_resolution", type: "vec2", description: "Canvas size in pixels as width and height."),
        Uniform.new(name: "u_time", type: "float", description: "Renderer time in seconds."),
        Uniform.new(name: "u_amplitude", type: "float", description: "Normalized RMS amplitude, usually 0.0..1.0."),
        Uniform.new(name: "u_bass", type: "float", description: "Low-frequency band level."),
        Uniform.new(name: "u_mid", type: "float", description: "Mid-frequency band level."),
        Uniform.new(name: "u_high", type: "float", description: "High-frequency band level."),
        Uniform.new(name: "u_beat", type: "float", description: "1.0 on detected beat frames, otherwise 0.0."),
        Uniform.new(name: "u_beat_pulse", type: "float", description: "Decaying beat pulse after detection."),
        Uniform.new(name: "u_beat_phase", type: "float", description: "0.0..1.0 phase inside the current beat."),
        Uniform.new(name: "u_bar_phase", type: "float", description: "0.0..1.0 phase inside the current 4-beat bar."),
        Uniform.new(name: "u_bar_count", type: "float", description: "Completed 4-beat bars since analysis start."),
        Uniform.new(name: "u_phrase_count", type: "float", description: "Completed 8-bar phrases since analysis start."),
        Uniform.new(name: "u_beat_2", type: "float", description: "Half-beat subdivision pulse."),
        Uniform.new(name: "u_beat_4", type: "float", description: "Quarter-beat subdivision pulse."),
        Uniform.new(name: "u_beat_8", type: "float", description: "Eighth-beat subdivision pulse."),
        Uniform.new(name: "u_beat_triplet", type: "float", description: "Triplet subdivision pulse."),
        Uniform.new(name: "u_onset", type: "float", description: "Positive amplitude rise since the previous active frame."),
        Uniform.new(name: "u_sub_onset", type: "float", description: "Positive sub-band rise since the previous active frame."),
        Uniform.new(name: "u_low_onset", type: "float", description: "Positive low-band rise since the previous active frame."),
        Uniform.new(name: "u_mid_onset", type: "float", description: "Positive mid-band rise since the previous active frame."),
        Uniform.new(name: "u_high_onset", type: "float", description: "Positive high-band rise since the previous active frame."),
        Uniform.new(name: "u_kick", type: "float", description: "Low-band percussive confidence derived from band level and onset."),
        Uniform.new(name: "u_snare", type: "float", description: "Mid-band percussive confidence derived from band level and onset."),
        Uniform.new(name: "u_hihat", type: "float", description: "High-band percussive confidence derived from band level and onset."),
        Uniform.new(name: "u_bpm", type: "float", description: "Current BPM estimate, or 0.0 when unavailable."),
        Uniform.new(name: "u_fft[32]", type: "float[]", description: "Normalized FFT preview bins."),
        Uniform.new(name: "u_fft_size", type: "float", description: "Number of populated FFT preview bins."),
        Uniform.new(name: "u_visual_gain", type: "float", description: "Browser visual gain control value."),
        Uniform.new(name: "u_bass_boost", type: "float", description: "Browser bass boost control value."),
        Uniform.new(name: "u_wobble_amount", type: "float", description: "Browser wobble amount control value."),
        Uniform.new(name: "u_param_<name>", type: "float", description: "Numeric layer param or mapped DSL target."),
        Uniform.new(name: "u_global_<name>", type: "float", description: "Numeric runtime global from DSL or MIDI set.")
      ].freeze

      # @return [Array<String>]
      def lines
        [
          "# Vizcore Shader Uniforms",
          "",
          "Custom fragment shaders use GLSL ES 3.00 and receive these uniforms:",
          "",
          "| Uniform | Type | Description |",
          "| --- | --- | --- |",
          *UNIFORMS.map { |uniform| "| `#{uniform.name}` | `#{uniform.type}` | #{uniform.description} |" },
          "",
          "Layer params are exposed as `u_param_<name>` after non-word characters are converted to underscores.",
          "For compatibility, a mapped target like `:param_intensity` is also exposed as `u_param_intensity`.",
          "Runtime globals are exposed as `u_global_<name>`; `:global_intensity` becomes `u_global_intensity`."
        ]
      end
    end
  end
end
