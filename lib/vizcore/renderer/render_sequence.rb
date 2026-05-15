# frozen_string_literal: true

require "fileutils"
require "open3"
require "pathname"
require "tmpdir"
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
        height: SnapshotRenderer::DEFAULT_HEIGHT,
        command_runner: Open3,
        ffmpeg_checker: nil
      )
        @config = config
        @frames = normalize_frame_count(frames)
        @fps = normalize_frame_rate(fps)
        @width = width
        @height = height
        @command_runner = command_runner
        @ffmpeg_checker = ffmpeg_checker || method(:ffmpeg_available?)
      end

      # @param out [String, Pathname] output directory for PNG frames, or `.mp4`
      # @return [Hash] render metadata
      def write(out:)
        output_path = Pathname.new(out.to_s).expand_path
        return write_video(output_path) if video_output?(output_path)

        write_frames(output_path)
      end

      private

      def write_frames(output_dir)
        FileUtils.mkdir_p(output_dir)
        render_frames(output_dir).merge(path: output_dir, format: :png_sequence)
      end

      def write_video(output_file)
        raise ArgumentError, "Only .mp4 video output is supported" unless output_file.extname.downcase == ".mp4"
        raise ArgumentError, "ffmpeg is required for MP4 output" unless @ffmpeg_checker.call

        FileUtils.mkdir_p(output_file.dirname)
        metadata = nil
        Dir.mktmpdir("vizcore-render-frames") do |dir|
          frame_dir = Pathname.new(dir)
          metadata = render_frames(frame_dir)
          encode_mp4(frame_dir: frame_dir, output_file: output_file)
        end
        metadata.merge(path: output_file, format: :mp4)
      end

      def render_frames(output_dir)
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
          frames: @frames,
          fps: @fps,
          width: renderer.width,
          height: renderer.height,
          scene: scene_name
        }
      ensure
        source&.stop
      end

      def video_output?(path)
        %w[.mp4 .mov .webm].include?(path.extname.downcase)
      end

      def frame_path(output_dir, index)
        output_dir.join(format("frame_%05d.png", index + 1))
      end

      def encode_mp4(frame_dir:, output_file:)
        stdout, stderr, status = @command_runner.capture3(*ffmpeg_command(frame_dir: frame_dir, output_file: output_file))
        return if status.success?

        detail = stderr.to_s.strip.empty? ? stdout.to_s.strip : stderr.to_s.strip
        message = detail.empty? ? "ffmpeg failed with non-zero status" : "ffmpeg failed: #{detail}"
        raise ArgumentError, message
      end

      def ffmpeg_command(frame_dir:, output_file:)
        [
          "ffmpeg",
          "-y",
          "-framerate",
          format_frame_rate,
          "-i",
          frame_dir.join("frame_%05d.png").to_s,
          "-vf",
          "format=yuv420p",
          "-pix_fmt",
          "yuv420p",
          output_file.to_s
        ]
      end

      def ffmpeg_available?
        system("ffmpeg", "-version", out: File::NULL, err: File::NULL)
      end

      def format_frame_rate
        return @fps.to_i.to_s if @fps == @fps.to_i

        @fps.to_s
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
