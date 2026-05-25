# frozen_string_literal: true

require_relative "config"

module Vizcore
  # Rack/WebSocket server runtime namespace.
  module Server
    # Start a Vizcore server from Ruby code.
    #
    # @param config [Vizcore::Config, Hash, nil] runtime config or Config keyword options
    # @param output [#puts] stream used by the runner
    # @param options [Hash] Config keyword options when `config` is nil
    # @return [void]
    def self.start(config = nil, output: $stdout, **options)
      runtime_config = start_config(config, options)
      Runner.new(runtime_config, output: output).run
    end

    def self.start_config(config, options)
      return Config.new(**options) if config.nil?
      return config if config.is_a?(Config) && options.empty?
      return Config.new(**config.merge(options)) if config.is_a?(Hash)

      raise ArgumentError, "server start requires a Vizcore::Config or config options"
    end
    private_class_method :start_config
  end
end

require_relative "server/frame_broadcaster"
require_relative "server/gallery_page"
require_relative "server/gallery_app"
require_relative "server/gallery_runner"
require_relative "server/rack_app"
require_relative "server/scene_dependency_watcher"
require_relative "server/runner"
require_relative "server/websocket_handler"
