# frozen_string_literal: true

require "json"
require "pathname"
require "rack"
require_relative "websocket_handler"

module Vizcore
  module Server
    # Rack app serving frontend assets, health endpoint, and WebSocket upgrade.
    class RackApp
      AUDIO_FILE_PATH = "/audio-file"
      RUNTIME_PATH = "/runtime"

      # @param frontend_root [Pathname]
      # @param websocket_path [String]
      # @param audio_source [Symbol, String, nil]
      # @param audio_file [String, Pathname, nil]
      def initialize(frontend_root:, websocket_path: "/ws", audio_source: nil, audio_file: nil)
        @frontend_root = frontend_root.expand_path
        @websocket_path = websocket_path
        @audio_source = audio_source&.to_sym
        @audio_file = audio_file ? Pathname.new(audio_file).expand_path : nil
      end

      # @param env [Hash]
      # @return [Array(Integer, Hash, Array<String>)]
      def call(env)
        request = Rack::Request.new(env)

        return WebSocketHandler.call(env) if request.path_info == @websocket_path
        return health_response if request.path_info == "/health"
        return runtime_response if request.path_info == RUNTIME_PATH
        return audio_file_response if request.path_info == AUDIO_FILE_PATH

        serve_static(request.path_info)
      end

      private

      def health_response
        body = JSON.generate(status: "ok", websocket_clients: WebSocketHandler.connection_count)
        [200, json_headers.merge("content-length" => body.bytesize.to_s), [body]]
      end

      def runtime_response
        payload = {
          status: "ok",
          audio_source: (@audio_source || :unknown).to_s,
          audio_file_name: nil,
          audio_file_url: nil
        }

        if audio_file_available?
          payload[:audio_file_name] = @audio_file.basename.to_s
          payload[:audio_file_url] = AUDIO_FILE_PATH
        end

        body = JSON.generate(payload)
        [200, json_headers.merge("content-length" => body.bytesize.to_s), [body]]
      end

      def audio_file_response
        return not_found_response unless audio_file_available?

        body = File.binread(@audio_file)
        headers = {
          "content-type" => Rack::Mime.mime_type(@audio_file.extname, "application/octet-stream"),
          "content-length" => body.bytesize.to_s,
          "cache-control" => "no-store, max-age=0, must-revalidate",
          "accept-ranges" => "bytes"
        }
        [200, headers, [body]]
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
          "cache-control" => "no-store, max-age=0, must-revalidate"
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

      def audio_file_available?
        @audio_source == :file && @audio_file && @audio_file.file?
      end
    end
  end
end
