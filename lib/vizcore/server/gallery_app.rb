# frozen_string_literal: true

require "json"
require "pathname"
require "rack"
require_relative "../dsl"
require_relative "gallery_page"

module Vizcore
  module Server
    # Rack app that lists bundled example scenes and their launch commands.
    class GalleryApp
      POSTER_PATH = "/assets/vizcore-poster.png"
      DESCRIPTIONS = {
        "basic.rb" => "Single wireframe cube starter.",
        "intro_drop.rb" => "Beat-triggered intro to drop transition.",
        "file_audio_demo.rb" => "File-audio walkthrough with layered visuals.",
        "complex_audio_showcase.rb" => "Dense multi-scene showcase for audio-reactive layers.",
        "rhythm_geometry.rb" => "Morphing geometric pattern driven by rhythm and bands.",
        "ruby_crystal_show.rb" => "Ruby-themed crystal, particles, and text showcase.",
        "parser_visualizer.rb" => "Parser-themed token, AST, and reduce visual sketch.",
        "live_coding_minimal.rb" => "Tiny live-coding scene with a pulsing blob.",
        "club_intro_drop.rb" => "Intro, build, and drop flow for rhythmic file input.",
        "shader_playground.rb" => "Focused liquid shader scene with mapped params.",
        "audio_inspector.rb" => "Audio feature visualization scene with bars and blob.",
        "readme_demo.rb" => "Minimal beat pulse to ring radius demo.",
        "midi_scene_switch.rb" => "MIDI note and CC driven scene switching.",
        "midi_controller_show.rb" => "MIDI pads switch scenes and knobs drive global shader uniforms.",
        "kansai_rubykaigi_visual.rb" => "Event showcase with ruby crystal, water ripple, and Kyoto-inspired pattern.",
        "custom_shader.rb" => "Custom GLSL fragment shader example.",
        "unyo_liquid.rb" => "Organic liquid wobble scene with FFT blobs and particles."
      }.freeze
      FILE_AUDIO_EXAMPLES = %w[
        file_audio_demo.rb
        complex_audio_showcase.rb
        rhythm_geometry.rb
        ruby_crystal_show.rb
        parser_visualizer.rb
        club_intro_drop.rb
        audio_inspector.rb
        readme_demo.rb
        kansai_rubykaigi_visual.rb
      ].freeze
      ORDER = DESCRIPTIONS.keys.freeze

      # @param examples_root [Pathname, String]
      # @param docs_assets_root [Pathname, String]
      def initialize(
        examples_root: Vizcore.root.join("examples"),
        docs_assets_root: Vizcore.root.join("docs", "assets")
      )
        @examples_root = Pathname.new(examples_root.to_s).expand_path
        @docs_assets_root = Pathname.new(docs_assets_root.to_s).expand_path
      end

      # @param env [Hash]
      # @return [Array(Integer, Hash, Array<String>)]
      def call(env)
        request = Rack::Request.new(env)

        return html_response if request.path_info == "/"
        return json_response if request.path_info == "/examples.json"
        return poster_response if request.path_info == POSTER_PATH
        return health_response if request.path_info == "/health"

        not_found_response
      end

      private

      def html_response
        body = GalleryPage.new(entries: examples, poster_path: POSTER_PATH).render
        response(body, content_type: "text/html; charset=utf-8")
      end

      def json_response
        body = JSON.generate(examples: examples)
        response(body, content_type: "application/json; charset=utf-8")
      end

      def health_response
        body = JSON.generate(status: "ok", examples: examples.length)
        response(body, content_type: "application/json; charset=utf-8")
      end

      def poster_response
        path = @docs_assets_root.join("vizcore-poster.png")
        return not_found_response unless path.file?

        response(File.binread(path), content_type: "image/png")
      end

      def examples
        example_paths.map { |path| example_payload(path) }
      end

      def example_paths
        paths = @examples_root.children.select { |path| path.file? && path.extname == ".rb" }
        paths.sort_by { |path| [ORDER.index(path.basename.to_s) || ORDER.length, path.basename.to_s] }
      rescue Errno::ENOENT
        []
      end

      def example_payload(path)
        definition = Vizcore::DSL::Engine.load_file(path.to_s)
        scenes = Array(definition[:scenes])
        {
          file: display_path(path),
          title: path.basename(".rb").to_s.tr("_", " "),
          description: DESCRIPTIONS.fetch(path.basename.to_s, "Vizcore example scene."),
          scene_names: scenes.map { |scene| scene[:name].to_s },
          layer_count: scenes.sum { |scene| Array(scene[:layers]).length },
          command: launch_command(path),
          audio_source: audio_source_for(path)
        }
      rescue StandardError => e
        {
          file: display_path(path),
          title: path.basename(".rb").to_s.tr("_", " "),
          description: "This example could not be inspected: #{e.message}",
          scene_names: [],
          layer_count: 0,
          command: launch_command(path),
          audio_source: audio_source_for(path)
        }
      end

      def launch_command(path)
        command = "vizcore start #{display_path(path)} --audio-source #{audio_source_for(path)}"
        return command unless audio_source_for(path) == "file"

        "#{command} --audio-file #{display_path(@examples_root.join('assets', 'complex_demo_loop.wav'))}"
      end

      def audio_source_for(path)
        FILE_AUDIO_EXAMPLES.include?(path.basename.to_s) ? "file" : "dummy"
      end

      def display_path(path)
        path = Pathname.new(path.to_s).expand_path
        path.relative_path_from(Vizcore.root).to_s
      rescue ArgumentError
        path.to_s
      end

      def response(body, content_type:)
        [200, { "content-type" => content_type, "content-length" => body.bytesize.to_s, "cache-control" => "no-store" }, [body]]
      end

      def not_found_response
        [404, { "content-type" => "text/plain; charset=utf-8", "content-length" => "9" }, ["Not Found"]]
      end
    end
  end
end
