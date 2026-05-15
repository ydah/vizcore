# frozen_string_literal: true

require "fileutils"
require "pathname"
require_relative "scene_frame_source"
require_relative "snapshot_renderer"

module Vizcore
  module Renderer
    # Writes a deterministic PNG image sequence from a scene.
    class RenderSequence
      DEFAULT_FRAME_COUNT = 60
      DEFAULT_FRAME_RATE = 30.0

      def initialize(
        config:,
        frames: DEFAULT_FRAME_COUNT,
        fps: DEFAULT_FRAME_RATE,
        width: SnapshotRenderer::DEFAULT_WIDTH,
        height: SnapshotRenderer::DEFAULT_HEIGHT
      )
        @config = config
        @frames = normalize_frame_count(frames)
        @fps = normalize_frame_rate(fps)
        @width = width
        @height = height
      end

      # @param out [String, Pathname] output directory for PNG frames
      # @return [Hash] render metadata
      def write(out:)
        output_dir = output_directory(out)
        FileUtils.mkdir_p(output_dir)

        source = SceneFrameSource.new(config: @config, frame_rate: @fps)
        source.start
        renderer = SnapshotRenderer.new(width: @width, height: @height)
        scene_name = nil

        @frames.times do |index|
          frame = source.capture
          scene_name ||= frame.fetch(:scene_name)
          File.binwrite(
            frame_path(output_dir, index),
            renderer.render(scene: frame.fetch(:scene), audio: frame.fetch(:audio))
          )
        end

        {
          path: output_dir,
          frames: @frames,
          fps: @fps,
          width: renderer.width,
          height: renderer.height,
          scene: scene_name
        }
      ensure
        source&.stop
      end

      private

      def output_directory(out)
        path = Pathname.new(out.to_s).expand_path
        if %w[.mp4 .mov .webm].include?(path.extname.downcase)
          raise ArgumentError, "Video output is not supported yet; use an output directory for PNG frames"
        end

        path
      end

      def frame_path(output_dir, index)
        output_dir.join(format("frame_%05d.png", index + 1))
      end

      def normalize_frame_count(value)
        count = Integer(value)
        raise ArgumentError, "frames must be positive" unless count.positive?

        count
      rescue ArgumentError, TypeError
        raise ArgumentError, "frames must be a positive integer"
      end

      def normalize_frame_rate(value)
        rate = Float(value)
        raise ArgumentError, "fps must be positive" unless rate.positive?

        rate
      rescue ArgumentError, TypeError
        raise ArgumentError, "fps must be a positive number"
      end
    end
  end
end
