# frozen_string_literal: true

require "socket"
require_relative "osc_message"

module Vizcore
  module Sync
    # Receives OSC UDP messages on a background thread.
    class OscReceiver
      DEFAULT_HOST = "127.0.0.1"
      MAX_PACKET_SIZE = 65_536

      # @param port [Integer]
      # @param host [String]
      # @param handler [#call]
      # @param error_reporter [#call, nil]
      def initialize(port:, host: DEFAULT_HOST, handler:, error_reporter: nil)
        @host = host.to_s
        @port = Integer(port)
        @handler = handler
        @error_reporter = error_reporter
        @socket = nil
        @thread = nil
        @running = false
      end

      # @return [Vizcore::Sync::OscReceiver]
      def start
        return self if @thread&.alive?

        @socket = UDPSocket.new
        @socket.bind(@host, @port)
        @running = true
        @thread = Thread.new { receive_loop }
        self
      end

      # @return [nil]
      def stop
        @running = false
        @socket&.close
        @thread&.join(1)
        nil
      rescue StandardError
        nil
      ensure
        @socket = nil
        @thread = nil
      end

      private

      def receive_loop
        while @running
          begin
            data, = @socket.recvfrom(MAX_PACKET_SIZE)
            message = OscMessage.parse(data)
            @handler.call(message) if message
          rescue IOError, SystemCallError
            break unless @running
          rescue StandardError => e
            @error_reporter&.call("OSC message ignored: #{e.message}")
          end
        end
      end
    end
  end
end
