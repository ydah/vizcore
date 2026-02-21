# frozen_string_literal: true

require "pathname"

module Vizcore
  class Config
    DEFAULT_HOST = "127.0.0.1"
    DEFAULT_PORT = 4567

    attr_reader :host, :port, :scene_file

    def initialize(scene_file:, host: DEFAULT_HOST, port: DEFAULT_PORT)
      @scene_file = Pathname.new(scene_file).expand_path if scene_file
      @host = host
      @port = Integer(port)
    end

    def scene_exists?
      scene_file && scene_file.file?
    end
  end
end
