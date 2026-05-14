# frozen_string_literal: true

require "socket"
require_relative "../analysis"
require_relative "../audio"
require_relative "../config"

module Vizcore
  module CLISupport
    # Environment preflight checks for local Vizcore development and live use.
    class Doctor
      REQUIRED_RUBY = Gem::Requirement.new(">= 3.2.0")

      Check = Struct.new(:name, :status, :message, keyword_init: true) do
        def ok?
          status == :ok
        end

        def failure?
          status == :fail
        end
      end

      Report = Struct.new(:checks, keyword_init: true) do
        def failure?
          checks.any?(&:failure?)
        end
      end

      def initialize(
        ruby_version: RUBY_VERSION,
        portaudio_available: -> { Vizcore::Audio::PortAudioFFI.available? },
        audio_devices: -> { Vizcore::Audio::PortAudioFFI.input_devices },
        midi_devices: -> { Vizcore::Audio::MidiInput.available_devices },
        fftw_available: -> { Vizcore::Analysis::FFTProcessor.fftw_available? },
        command_available: method(:command_available?),
        port_available: method(:port_available?)
      )
        @ruby_version = ruby_version
        @portaudio_available = portaudio_available
        @audio_devices = audio_devices
        @midi_devices = midi_devices
        @fftw_available = fftw_available
        @command_available = command_available
        @port_available = port_available
      end

      def call
        Report.new(
          checks: [
            ruby_check,
            frontend_check,
            portaudio_check,
            audio_devices_check,
            midi_check,
            fftw_check,
            ffmpeg_check,
            port_check
          ]
        )
      end

      private

      attr_reader :ruby_version

      def ruby_check
        version = Gem::Version.new(ruby_version)
        return ok("Ruby", "#{ruby_version} satisfies #{REQUIRED_RUBY}") if REQUIRED_RUBY.satisfied_by?(version)

        fail_check("Ruby", "#{ruby_version} is too old; Vizcore requires #{REQUIRED_RUBY}")
      end

      def frontend_check
        index_path = Vizcore.frontend_root.join("index.html")
        src_path = Vizcore.frontend_root.join("src")
        return ok("Frontend assets", "browser runtime assets found") if index_path.file? && src_path.directory?

        fail_check("Frontend assets", "missing browser runtime assets under #{Vizcore.frontend_root}")
      end

      def portaudio_check
        return ok("PortAudio", "native audio input bridge is available") if @portaudio_available.call

        warn("PortAudio", "native audio input unavailable; use --audio-source dummy or install PortAudio for mic input")
      rescue StandardError => e
        warn("PortAudio", "availability check failed: #{e.message}")
      end

      def audio_devices_check
        devices = Array(@audio_devices.call)
        return ok("Audio devices", "#{devices.length} input device(s) detected") unless devices.empty?

        warn("Audio devices", "no native input devices detected; mic input may fall back to silence")
      rescue StandardError => e
        warn("Audio devices", "device scan failed: #{e.message}")
      end

      def midi_check
        devices = Array(@midi_devices.call)
        return ok("MIDI", "#{devices.length} MIDI input device(s) detected") unless devices.empty?

        warn("MIDI", "no MIDI input devices detected; install unimidi and connect a controller to use midi_map")
      rescue StandardError => e
        warn("MIDI", "device scan failed: #{e.message}")
      end

      def fftw_check
        return ok("FFTW3", "native FFT backend is available") if @fftw_available.call

        warn("FFTW3", "native FFT backend unavailable; pure Ruby FFT fallback will be used")
      rescue StandardError => e
        warn("FFTW3", "availability check failed: #{e.message}")
      end

      def ffmpeg_check
        return ok("ffmpeg", "compressed audio decoding is available") if @command_available.call("ffmpeg")

        warn("ffmpeg", "not found on PATH; WAV input still works, MP3/FLAC file input will not")
      end

      def port_check
        return ok("Default port", "#{Config::DEFAULT_HOST}:#{Config::DEFAULT_PORT} is available") if @port_available.call(Config::DEFAULT_HOST, Config::DEFAULT_PORT)

        warn("Default port", "#{Config::DEFAULT_HOST}:#{Config::DEFAULT_PORT} is already in use")
      rescue StandardError => e
        warn("Default port", "availability check failed: #{e.message}")
      end

      def ok(name, message)
        Check.new(name: name, status: :ok, message: message)
      end

      def warn(name, message)
        Check.new(name: name, status: :warn, message: message)
      end

      def fail_check(name, message)
        Check.new(name: name, status: :fail, message: message)
      end

      def command_available?(command)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
          path = File.join(directory, command)
          File.file?(path) && File.executable?(path)
        end
      end

      def port_available?(host, port)
        server = TCPServer.new(host, port)
        true
      rescue Errno::EADDRINUSE
        false
      ensure
        server&.close
      end
    end
  end
end
