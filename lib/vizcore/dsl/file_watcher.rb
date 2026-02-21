# frozen_string_literal: true

require "pathname"

module Vizcore
  module DSL
    class FileWatcher
      DEFAULT_POLL_INTERVAL = 0.25

      def initialize(path:, poll_interval: DEFAULT_POLL_INTERVAL, listener_factory: nil, &on_change)
        @path = Pathname.new(path.to_s).expand_path
        @poll_interval = Float(poll_interval)
        @listener_factory = listener_factory
        @on_change = on_change
        @running = false
        @listener = nil
        @thread = nil
      end

      def start
        return if running?

        @running = true
        start_with_listener || start_with_polling
      end

      def stop(timeout: 1.0)
        return unless running?

        @running = false
        @listener&.stop
        @listener = nil

        thread = @thread
        @thread = nil
        return unless thread
        return if thread == Thread.current

        thread.join(timeout)
      end

      def running?
        @running
      end

      private

      def start_with_listener
        factory = @listener_factory || default_listener_factory
        return false unless factory

        file_pattern = /\A#{Regexp.escape(@path.basename.to_s)}\z/
        @listener = factory.call(@path.dirname.to_s, file_pattern) do |modified, added, _removed|
          changed = (Array(modified) + Array(added)).map { |entry| Pathname.new(entry.to_s).expand_path }
          next unless changed.include?(@path)

          @on_change&.call(@path)
        end
        @listener.start
        true
      rescue StandardError
        @listener = nil
        false
      end

      def start_with_polling
        @thread = Thread.new { poll_loop }
      end

      def poll_loop
        last_mtime = file_mtime

        while running?
          sleep(@poll_interval)
          current_mtime = file_mtime
          changed = !current_mtime.nil? && (last_mtime.nil? || current_mtime > last_mtime)
          if changed
            @on_change&.call(@path)
            last_mtime = current_mtime
          end
        end
      end

      def file_mtime
        return nil unless @path.file?

        @path.mtime
      end

      def default_listener_factory
        require "listen"
        ->(directory, pattern, &block) { Listen.to(directory, only: pattern, &block) }
      rescue LoadError
        nil
      end
    end
  end
end
