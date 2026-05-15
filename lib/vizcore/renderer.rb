# frozen_string_literal: true

module Vizcore
  # Renderer-side frame scheduling and scene serialization.
  module Renderer
  end
end

require_relative "renderer/frame_scheduler"
require_relative "renderer/png_writer"
require_relative "renderer/scene_serializer"
require_relative "renderer/snapshot"
require_relative "renderer/snapshot_renderer"
