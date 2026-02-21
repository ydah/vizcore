# frozen_string_literal: true

require "json"
require "rack"
require_relative "websocket_handler"

module Vizcore
  module Server
    # Rack app serving frontend assets, health endpoint, and WebSocket upgrade.
    class RackApp
      # @param frontend_root [Pathname]
      # @param websocket_path [String]
      def initialize(frontend_root:, websocket_path: "/ws")
        @frontend_root = frontend_root.expand_path
        @websocket_path = websocket_path
      end

      # @param env [Hash]
      # @return [Array(Integer, Hash, Array<String>)]
      def call(env)
        request = Rack::Request.new(env)

        return WebSocketHandler.call(env) if request.path_info == @websocket_path
        return health_response if request.path_info == "/health"

        serve_static(request.path_info)
      end

      private

      def health_response
        body = JSON.generate(status: "ok", websocket_clients: WebSocketHandler.connection_count)
        [200, json_headers.merge("content-length" => body.bytesize.to_s), [body]]
      end

      def serve_static(path_info)
        path = path_info == "/" ? "index.html" : path_info.delete_prefix("/")
        full_path = File.expand_path(path, @frontend_root.to_s)

        return not_found_response unless full_path.start_with?(@frontend_root.to_s)
        return not_found_response unless File.file?(full_path)

        body = File.binread(full_path)
        headers = {
          "content-type" => Rack::Mime.mime_type(File.extname(full_path), "text/plain"),
          "content-length" => body.bytesize.to_s,
          "cache-control" => "no-cache"
        }
        [200, headers, [body]]
      end

      def not_found_response
        [404, text_headers.merge("content-length" => "9"), ["Not Found"]]
      end

      def text_headers
        { "content-type" => "text/plain; charset=utf-8" }
      end

      def json_headers
        { "content-type" => "application/json; charset=utf-8" }
      end
    end
  end
end
