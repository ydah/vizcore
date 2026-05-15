# frozen_string_literal: true

require "fileutils"
require "pathname"
require_relative "scene_frame_source"
require_relative "snapshot_renderer"

module Vizcore
  module Renderer
    # Builds one analyzed scene frame and writes a PNG preview.
    class Snapshot
      def initialize(config:, width: SnapshotRenderer::DEFAULT_WIDTH, height: SnapshotRenderer::DEFAULT_HEIGHT)
        @config = config
        @width = width
        @height = height
      end

      # @param out [String, Pathname]
      # @return [Hash] snapshot metadata
      def write(out:)
        output_path = Pathname.new(out.to_s).expand_path
        frame_source = SceneFrameSource.new(config: @config)
        frame_source.start
        frame = frame_source.capture
        png = SnapshotRenderer.new(width: @width, height: @height).render(
          scene: frame.fetch(:scene),
          audio: frame.fetch(:audio)
        )

        FileUtils.mkdir_p(output_path.dirname)
        File.binwrite(output_path, png)
        { path: output_path, scene: frame.fetch(:scene_name), width: @width, height: @height }
      ensure
        frame_source&.stop
      end
    end
  end
end
