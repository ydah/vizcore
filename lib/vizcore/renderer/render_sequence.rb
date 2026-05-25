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
        duration: nil,
        from_frame: 1,
        to_frame: nil,
        resume: false,
        seed: nil,
        transparent: false,
        video_codec: nil,
        video_bitrate: nil,
        video_crf: nil,
        pixel_format: "yuv420p",
        progress_reporter: nil,
        command_runner: Open3,
        ffmpeg_checker: nil
      )
        @config = config
        @fps = normalize_frame_rate(fps)
        @frames = normalize_frame_count(duration ? (Float(duration) * @fps).ceil : frames)
        @from_frame = normalize_frame_index(from_frame, "from-frame")
        @to_frame = normalize_optional_frame_index(to_frame, "to-frame")
        @to_frame = @frames if @to_frame.nil?
        raise ArgumentError, "to-frame must be greater than or equal to from-frame" if @to_frame < @from_frame
        raise ArgumentError, "from-frame must be within rendered frame count" if @from_frame > @frames

        @to_frame = [@to_frame, @frames].min
        @output_frames = @to_frame - @from_frame + 1
        @resume = !!resume
        @seed = normalize_seed(seed)
        @transparent = !!transparent
        @video_codec = optional_string(video_codec, "video codec")
        @video_bitrate = optional_string(video_bitrate, "video bitrate")
        @video_crf = optional_string(video_crf, "video crf")
        @pixel_format = optional_string(pixel_format, "pixel format") || "yuv420p"
        @progress_reporter = progress_reporter
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
          metadata = render_frames(frame_dir, preserve_frame_numbers: false)
          encode_mp4(frame_dir: frame_dir, output_file: output_file)
        end
        metadata.merge(path: output_file, format: :mp4)
      end

      def render_frames(output_dir, preserve_frame_numbers: true)
        source = SceneFrameSource.new(config: @config, frame_rate: @fps, seed: @seed)
        source.start
        renderer = SnapshotRenderer.new(width: @width, height: @height, transparent: @transparent)
        scene_name = nil

        @frames.times do |index|
          frame_number = index + 1
          break if frame_number > @to_frame

          frame = source.capture
          scene_name ||= frame.fetch(:scene_name)
          next if frame_number < @from_frame || frame_number > @to_frame
          output_frame_number = preserve_frame_numbers ? frame_number : frame_number - @from_frame + 1
          next if @resume && frame_path(output_dir, output_frame_number).file?

          File.binwrite(
            frame_path(output_dir, output_frame_number),
            renderer.render(scene: frame.fetch(:scene), audio: frame.fetch(:audio))
          )
          emit_progress(frame_number: frame_number, output_frame_number: output_frame_number)
        end

        {
          frames: @output_frames,
          total_frames: @frames,
          from_frame: @from_frame,
          to_frame: @to_frame,
          fps: @fps,
          width: renderer.width,
          height: renderer.height,
          transparent: @transparent,
          scene: scene_name
        }
      ensure
        source&.stop
      end

      def video_output?(path)
        %w[.mp4 .mov .webm].include?(path.extname.downcase)
      end

      def frame_path(output_dir, frame_number)
        output_dir.join(format("frame_%05d.png", frame_number))
      end

      def encode_mp4(frame_dir:, output_file:)
        stdout, stderr, status = @command_runner.capture3(*ffmpeg_command(frame_dir: frame_dir, output_file: output_file))
        return if status.success?

        detail = stderr.to_s.strip.empty? ? stdout.to_s.strip : stderr.to_s.strip
        message = detail.empty? ? "ffmpeg failed with non-zero status" : "ffmpeg failed: #{detail}"
        raise ArgumentError, message
      end

      def ffmpeg_command(frame_dir:, output_file:)
        command = [
          "ffmpeg",
          "-y",
          "-framerate",
          format_frame_rate,
          "-i",
          frame_dir.join("frame_%05d.png").to_s,
          "-vf",
          "format=#{@pixel_format}",
          "-pix_fmt",
          @pixel_format
        ]
        command.concat(["-c:v", @video_codec]) if @video_codec
        command.concat(["-b:v", @video_bitrate]) if @video_bitrate
        command.concat(["-crf", @video_crf]) if @video_crf
        command << output_file.to_s
        command
      end

      def ffmpeg_available?
        system("ffmpeg", "-version", out: File::NULL, err: File::NULL)
      end

      def emit_progress(frame_number:, output_frame_number:)
        return unless @progress_reporter.respond_to?(:call)

        @progress_reporter.call(
          frame: frame_number,
          output_frame: output_frame_number,
          from_frame: @from_frame,
          to_frame: @to_frame,
          total_frames: @frames,
          output_frames: @output_frames,
          percent: ((frame_number - @from_frame + 1).to_f / @output_frames * 100).clamp(0.0, 100.0)
        )
      rescue StandardError
        nil
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

      def normalize_frame_index(value, name)
        index = Integer(value)
        raise ArgumentError, "#{name} must be positive" unless index.positive?

        index
      rescue ArgumentError, TypeError
        raise ArgumentError, "#{name} must be a positive integer"
      end

      def normalize_optional_frame_index(value, name)
        return nil if value.nil?

        normalize_frame_index(value, name)
      end

      def normalize_frame_rate(value)
        rate = Float(value)
        raise ArgumentError, "fps must be positive" unless rate.positive?

        rate
      rescue ArgumentError, TypeError
        raise ArgumentError, "fps must be a positive number"
      end

      def normalize_seed(value)
        return nil if value.nil?

        Integer(value)
      rescue ArgumentError, TypeError
        raise ArgumentError, "seed must be an integer"
      end

      def optional_string(value, name)
        return nil if value.nil?

        normalized = value.to_s.strip
        raise ArgumentError, "#{name} must not be empty" if normalized.empty?

        normalized
      end
    end
  end
end
