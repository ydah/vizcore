# frozen_string_literal: true

require "puma"
require_relative "../config"
require_relative "gallery_app"

module Vizcore
  module Server
    # Starts a small Rack/Puma server for the example gallery.
    class GalleryRunner
      DEFAULT_PORT = Config::DEFAULT_PORT + 1

      # @param host [String]
      # @param port [Integer]
      # @param output [#puts]
      def initialize(host: Config::DEFAULT_HOST, port: DEFAULT_PORT, output: $stdout)
        @host = host
        @port = Integer(port)
        @output = output
      end

      # @return [void]
      def run
        server = Puma::Server.new(GalleryApp.new, nil, min_threads: 0, max_threads: 4)
        server.add_tcp_listener(@host, @port)
        server.run

        @output.puts("Vizcore gallery: http://#{@host}:#{@port}")
        @output.puts("Press Ctrl+C to stop.")
        wait_for_interrupt
      ensure
        server&.stop(true)
      end

      private

      def wait_for_interrupt
        stop_requested = false
        %w[INT TERM].each do |signal_name|
          Signal.trap(signal_name) { stop_requested = true }
        rescue ArgumentError
          nil
        end
        sleep(0.1) until stop_requested
      end
    end
  end
end
