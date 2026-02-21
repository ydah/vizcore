# frozen_string_literal: true

module Vizcore
  module Audio
    module PortAudioFFI
      class Stream
        def initialize(mod:, pointer:, channels:)
          @mod = mod
          @pointer = pointer
          @channels = channels
          @started = false
          @closed = false
        end

        def start
          return true if @started
          return false if @closed

          result = @mod.Pa_StartStream(@pointer)
          return false unless ok?(result)

          @started = true
          true
        end

        def read(frame_size)
          frames = Integer(frame_size)
          return Array.new(frames, 0.0) unless @started

          buffer = ffi_module::MemoryPointer.new(:float, frames * @channels)
          result = @mod.Pa_ReadStream(@pointer, buffer, frames)
          return Array.new(frames, 0.0) unless ok?(result)

          samples = buffer.read_array_of_float(frames * @channels)
          return samples if @channels == 1

          downmix(samples, frames)
        rescue StandardError
          Array.new(frames, 0.0)
        end

        def stop
          return true if @closed || !@started

          result = @mod.Pa_StopStream(@pointer)
          @started = false if ok?(result)
          ok?(result)
        rescue StandardError
          false
        end

        def close
          return if @closed

          stop
          @mod.Pa_CloseStream(@pointer) unless @pointer.nil? || @pointer.null?
          @closed = true
        rescue StandardError
          @closed = true
        end

        private

        def downmix(samples, frames)
          Array.new(frames) do |frame|
            offset = frame * @channels
            chunk = samples[offset, @channels]
            chunk.sum / @channels.to_f
          end
        end

        def ok?(result)
          result == self.class.pa_no_error
        end

        def ffi_module
          self.class.ffi_module
        end

        class << self
          def ffi_module
            require "ffi"
            FFI
          end

          def pa_no_error
            0
          end
        end
      end

      extend self

      DEFAULT_CHANNELS = 1
      PA_NO_ERROR = 0
      PA_FLOAT_32 = 0x0000_0001

      def available?
        !ffi_module.nil?
      end

      def input_devices
        mod = ffi_module
        return [] unless mod
        return [] unless ok?(mod.Pa_Initialize)

        count = mod.Pa_GetDeviceCount
        return [] if count <= 0

        count.times.filter_map do |index|
          pointer = mod.Pa_GetDeviceInfo(index)
          next if pointer.null?

          info = mod::DeviceInfo.new(pointer)
          next unless info[:maxInputChannels].positive?

          {
            index: index,
            name: info[:name].read_string,
            max_input_channels: info[:maxInputChannels],
            default_sample_rate: info[:defaultSampleRate].to_f
          }
        end
      ensure
        mod&.Pa_Terminate
      end

      def open_default_input_stream(sample_rate:, channels: DEFAULT_CHANNELS, frames_per_buffer: 1024)
        mod = ffi_module
        return nil unless mod
        return nil unless ok?(mod.Pa_Initialize)

        stream_ptr_ptr = ffi::MemoryPointer.new(:pointer)

        result = mod.Pa_OpenDefaultStream(
          stream_ptr_ptr,
          Integer(channels),
          0,
          PA_FLOAT_32,
          Float(sample_rate),
          Integer(frames_per_buffer),
          nil,
          nil
        )
        return terminate_with_nil(mod) unless ok?(result)

        stream_pointer = stream_ptr_ptr.read_pointer
        return terminate_with_nil(mod) if stream_pointer.null?

        Stream.new(mod: mod, pointer: stream_pointer, channels: Integer(channels))
      rescue StandardError
        mod&.Pa_Terminate
        nil
      end

      def close_stream(stream)
        stream&.close
        ffi_module&.Pa_Terminate
      rescue StandardError
        nil
      end

      private

      def terminate_with_nil(mod)
        mod.Pa_Terminate
        nil
      end

      def ffi
        @ffi ||= begin
          require "ffi"
          FFI
        end
      end

      def ok?(result)
        result == PA_NO_ERROR
      end

      def ffi_module
        return @ffi_module if defined?(@ffi_module)

        @ffi_module = build_ffi_module
      end

      def build_ffi_module
        mod = Module.new
        mod.extend(ffi::Library)
        mod.ffi_lib("portaudio")

        device_info = Class.new(ffi::Struct)
        device_info.layout :structVersion, :int,
                           :name, :pointer,
                           :hostApi, :int,
                           :maxInputChannels, :int,
                           :maxOutputChannels, :int,
                           :defaultLowInputLatency, :double,
                           :defaultLowOutputLatency, :double,
                           :defaultHighInputLatency, :double,
                           :defaultHighOutputLatency, :double,
                           :defaultSampleRate, :double
        mod.const_set(:DeviceInfo, device_info)

        mod.attach_function :Pa_Initialize, [], :int
        mod.attach_function :Pa_Terminate, [], :int
        mod.attach_function :Pa_GetDeviceCount, [], :int
        mod.attach_function :Pa_GetDeviceInfo, [:int], :pointer
        mod.attach_function :Pa_OpenDefaultStream, [:pointer, :int, :int, :ulong, :double, :ulong, :pointer, :pointer], :int
        mod.attach_function :Pa_StartStream, [:pointer], :int
        mod.attach_function :Pa_StopStream, [:pointer], :int
        mod.attach_function :Pa_CloseStream, [:pointer], :int
        mod.attach_function :Pa_ReadStream, [:pointer, :pointer, :ulong], :int
        mod
      rescue LoadError, ffi::NotFoundError, StandardError
        nil
      end
    end
  end
end
