# frozen_string_literal: true

require "tmpdir"
require "vizcore/config"
require "vizcore/renderer/render_sequence"

RSpec.describe Vizcore::Renderer::RenderSequence do
  FakeStatus = Struct.new(:success?)

  it "writes a PNG image sequence for a scene" do
    Dir.mktmpdir("vizcore-render-sequence") do |dir|
      config = Vizcore::Config.new(
        scene_file: Vizcore.root.join("examples", "basic.rb").to_s,
        audio_source: :dummy
      )

      result = described_class.new(config: config, frames: 3, fps: 15, width: 160, height: 90).write(out: dir)
      frames = Dir[File.join(dir, "frame_*.png")].sort

      expect(result).to include(path: Pathname.new(dir).expand_path, frames: 3, fps: 15.0, width: 160, height: 90, scene: "basic")
      expect(frames.map { |path| File.basename(path) }).to eq(%w[frame_00001.png frame_00002.png frame_00003.png])
      expect(File.binread(frames.first, 8)).to eq(Vizcore::Renderer::PngWriter::SIGNATURE)
    end
  end

  it "writes a selected frame range and preserves existing frames when resuming" do
    Dir.mktmpdir("vizcore-render-range") do |dir|
      config = Vizcore::Config.new(
        scene_file: Vizcore.root.join("examples", "basic.rb").to_s,
        audio_source: :dummy
      )
      existing = File.join(dir, "frame_00002.png")
      File.binwrite(existing, "keep")

      result = described_class.new(
        config: config,
        frames: 5,
        fps: 15,
        from_frame: 2,
        to_frame: 3,
        resume: true,
        width: 160,
        height: 90
      ).write(out: dir)
      frames = Dir[File.join(dir, "frame_*.png")].sort

      expect(result).to include(frames: 2, total_frames: 5, from_frame: 2, to_frame: 3)
      expect(frames.map { |path| File.basename(path) }).to eq(%w[frame_00002.png frame_00003.png])
      expect(File.binread(existing)).to eq("keep")
      expect(File.binread(File.join(dir, "frame_00003.png"), 8)).to eq(Vizcore::Renderer::PngWriter::SIGNATURE)
    end
  end

  it "derives frame count from duration" do
    Dir.mktmpdir("vizcore-render-duration") do |dir|
      config = Vizcore::Config.new(
        scene_file: Vizcore.root.join("examples", "basic.rb").to_s,
        audio_source: :dummy
      )

      result = described_class.new(config: config, duration: 0.2, fps: 10, width: 160, height: 90).write(out: dir)

      expect(result).to include(frames: 2, total_frames: 2, from_frame: 1, to_frame: 2)
      expect(Dir[File.join(dir, "frame_*.png")].length).to eq(2)
    end
  end

  it "writes an MP4 video through ffmpeg" do
    Dir.mktmpdir("vizcore-render-mp4") do |dir|
      config = Vizcore::Config.new(
        scene_file: Vizcore.root.join("examples", "basic.rb").to_s,
        audio_source: :dummy
      )
      out = File.join(dir, "movie.mp4")
      command_runner = Class.new do
        attr_reader :command

        def capture3(*command)
          @command = command
          File.binwrite(command.last, "fake-mp4")
          ["", "", FakeStatus.new(true)]
        end
      end.new

      result = described_class.new(
        config: config,
        frames: 2,
        fps: 24,
        width: 160,
        height: 90,
        video_codec: "libx264",
        video_bitrate: "4M",
        video_crf: "18",
        pixel_format: "yuv444p",
        command_runner: command_runner,
        ffmpeg_checker: -> { true }
      ).write(out: out)

      expect(result).to include(path: Pathname.new(out).expand_path, format: :mp4, frames: 2, fps: 24.0, width: 160, height: 90, scene: "basic")
      expect(File.binread(out)).to eq("fake-mp4")
      expect(command_runner.command).to include("ffmpeg", "-framerate", "24")
      expect(command_runner.command).to include("-c:v", "libx264", "-b:v", "4M", "-crf", "18")
      expect(command_runner.command).to include("-pix_fmt", "yuv444p")
    end
  end

  it "requires ffmpeg for MP4 output" do
    config = Vizcore::Config.new(
      scene_file: Vizcore.root.join("examples", "basic.rb").to_s,
      audio_source: :dummy
    )

    expect do
      described_class.new(config: config, frames: 1, ffmpeg_checker: -> { false }).write(out: "movie.mp4")
    end.to raise_error(ArgumentError, /ffmpeg is required/)
  end

  it "rejects unsupported direct video output paths" do
    config = Vizcore::Config.new(
      scene_file: Vizcore.root.join("examples", "basic.rb").to_s,
      audio_source: :dummy
    )

    expect do
      described_class.new(config: config, frames: 1).write(out: "movie.webm")
    end.to raise_error(ArgumentError, /Only .mp4/)
  end
end
