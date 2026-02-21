# frozen_string_literal: true

require "net/http"
require "socket"
require "uri"
require "puma"
require "vizcore/server/rack_app"
require "vizcore/server/frame_broadcaster"

module E2EServerHelper
  class EmbeddedServer
    READY_TIMEOUT_SECONDS = 5

    attr_reader :host, :port

    def initialize(scene_name:, host: "127.0.0.1", broadcaster_options: {})
      @host = host
      @port = reserve_port
      @scene_name = scene_name
      @broadcaster_options = broadcaster_options
      @server = nil
      @broadcaster = nil
    end

    def start
      app = Vizcore::Server::RackApp.new(frontend_root: Vizcore.frontend_root)
      @server = Puma::Server.new(app, nil, min_threads: 0, max_threads: 4)
      @server.add_tcp_listener(host, port)
      @server.run

      @broadcaster = Vizcore::Server::FrameBroadcaster.new(scene_name: @scene_name, **@broadcaster_options)
      @broadcaster.start

      wait_until_ready!
    end

    def stop
      @broadcaster&.stop
      @server&.stop(true)
    ensure
      @broadcaster = nil
      @server = nil
    end

    def http_url(path = "/")
      URI("http://#{host}:#{port}#{path}")
    end

    def websocket_url(path = "/ws")
      "ws://#{host}:#{port}#{path}"
    end

    private

    def wait_until_ready!
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + READY_TIMEOUT_SECONDS
      loop do
        response = Net::HTTP.get_response(http_url("/health"))
        return if response.is_a?(Net::HTTPSuccess)
        raise "embedded server failed to start within #{READY_TIMEOUT_SECONDS}s" if timeout?(deadline)
        sleep(0.05)
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError
        raise "embedded server failed to start within #{READY_TIMEOUT_SECONDS}s" if timeout?(deadline)
        sleep(0.05)
      end
    end

    def timeout?(deadline)
      Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    end

    def reserve_port
      server = TCPServer.new(host, 0)
      server.addr[1]
    ensure
      server&.close
    end
  end
end
