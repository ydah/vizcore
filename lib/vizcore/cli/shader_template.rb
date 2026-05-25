# frozen_string_literal: true

require "fileutils"
require "pathname"

module Vizcore
  module CLISupport
    # Writes starter GLSL ES fragment shaders for custom shader layers.
    class ShaderTemplate
      TEMPLATE = <<~GLSL
        #version 300 es
        precision highp float;

        uniform vec2 u_resolution;
        uniform float u_time;
        uniform float u_amplitude;
        uniform float u_bass;
        uniform float u_mid;
        uniform float u_high;
        uniform float u_bass_peak;
        uniform float u_mid_peak;
        uniform float u_high_peak;
        uniform float u_beat;
        uniform float u_beat_pulse;
        uniform float u_beat_phase;
        uniform float u_bar_phase;
        uniform float u_onset;
        uniform float u_kick;
        uniform float u_bpm;
        uniform float u_fft[32];
        uniform float u_fft_size;

        out vec4 outColor;

        void main() {
          vec2 uv = gl_FragCoord.xy / u_resolution.xy;
          float wave = 0.5 + 0.5 * sin((uv.x + u_time * 0.12 + u_bar_phase * 0.2) * 12.0 + u_bass * 4.0);
          vec3 color = mix(vec3(0.02, 0.06, 0.12), vec3(0.1, 0.75, 0.95), wave);
          color += vec3(0.95, 0.16, 0.32) * (u_beat_pulse * 0.35 + u_onset * 0.2 + u_kick * 0.25 + u_high_peak * 0.2);
          color *= 0.35 + u_amplitude * 1.8;
          outColor = vec4(color, 1.0);
        }
      GLSL

      # @param name [String]
      # @return [String]
      def self.default_path(name)
        "shaders/#{safe_name(name)}.frag"
      end

      # @param name [String]
      # @return [String]
      def self.safe_name(name)
        raw_name = name.to_s.strip.sub(/\.frag\z/i, "")
        safe = raw_name.gsub(/[^a-zA-Z0-9_-]+/, "_").gsub(/\A_+|_+\z/, "")
        raise ArgumentError, "shader name is required" if safe.empty?

        safe
      end

      # @param path [String, Pathname]
      # @return [Pathname]
      def write(path)
        destination = Pathname(path)
        raise ArgumentError, "Shader file already exists: #{destination}" if destination.exist?

        FileUtils.mkdir_p(destination.dirname)
        destination.write(TEMPLATE)
        destination
      end
    end
  end
end
