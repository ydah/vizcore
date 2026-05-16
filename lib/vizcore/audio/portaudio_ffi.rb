# frozen_string_literal: true

module Vizcore
  module Audio
    # PortAudio FFI bridge for microphone stream access and device discovery.
    module PortAudioFFI
      # Runtime wrapper for an opened PortAudio input stream.
      class Stream
        PA_INPUT_OVERFLOWED = -9981

        # @param mod [Module] ffi-bound PortAudio module
        # @param pointer [FFI::Pointer] native stream pointer
        # @param channels [Integer] input channel count
        def initialize(mod:, pointer:, channels:)
          @mod = mod
          @pointer = pointer
          @channels = channels
          @started = false
          @closed = false
        end

        # @return [Boolean] true when stream start succeeded
        def start
          return true if @started
          return false if @closed

          result = @mod.Pa_StartStream(@pointer)
          return false unless ok?(result)

          @started = true
          true
        end

        # @param frame_size [Integer]
        # @return [Array<Float>] mono samples or silence on failure
        def read(frame_size)
          frames = Integer(frame_size)
          return Array.new(frames, 0.0) unless @started

          buffer = ffi_module::MemoryPointer.new(:float, frames * @channels)
          result = @mod.Pa_ReadStream(@pointer, buffer, frames)
          return Array.new(frames, 0.0) unless readable_result?(result)

          samples = buffer.read_array_of_float(frames * @channels)
          return samples if @channels == 1

          downmix(samples, frames)
        rescue StandardError
          Array.new(frames, 0.0)
        end

        # @return [Boolean] true when stop call succeeded
        def stop
          return true if @closed || !@started

          result = @mod.Pa_StopStream(@pointer)
          @started = false if ok?(result)
          ok?(result)
        rescue StandardError
          false
        end

        # @return [void]
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

        def readable_result?(result)
          ok?(result) || result == self.class.pa_input_overflowed
        end

        def ffi_module
          self.class.ffi_module
        end

        class << self
          # @return [Module] loaded ffi module
          def ffi_module
            require "ffi"
            FFI
          end

          # @return [Integer]
          def pa_no_error
            0
          end

          # PortAudio returns this when input data was dropped before this read,
          # but the current read buffer can still contain usable samples.
          def pa_input_overflowed
            PA_INPUT_OVERFLOWED
          end
        end
      end

      extend self

      # Default mono channel count.
      DEFAULT_CHANNELS = 1
      # PortAudio no-error status code.
      PA_NO_ERROR = 0
      # PortAudio float sample format code.
      PA_FLOAT_32 = 0x0000_0001
      # PortAudio stream flags.
      PA_NO_FLAGS = 0

      # @return [Boolean] true when PortAudio native library can be loaded
      def available?
        !ffi_module.nil?
      end

      # @return [Array<Hash>] available input device descriptors
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

      # @param sample_rate [Float]
      # @param channels [Integer]
      # @param frames_per_buffer [Integer]
      # @return [Vizcore::Audio::PortAudioFFI::Stream, nil]
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

      # @param device [String, Integer] PortAudio device index or case-insensitive name fragment
      # @param sample_rate [Float]
      # @param channels [Integer]
      # @param frames_per_buffer [Integer]
      # @return [Vizcore::Audio::PortAudioFFI::Stream, nil]
      def open_input_stream(device:, sample_rate:, channels: DEFAULT_CHANNELS, frames_per_buffer: 1024)
        mod = ffi_module
        return nil unless mod
        return nil unless ok?(mod.Pa_Initialize)

        device_info = resolve_input_device(mod, device)
        return terminate_with_nil(mod) unless device_info

        device_index, info = device_info
        actual_channels = [Integer(channels), info[:maxInputChannels]].min
        input_params = mod::StreamParameters.new
        input_params[:device] = device_index
        input_params[:channelCount] = actual_channels
        input_params[:sampleFormat] = PA_FLOAT_32
        input_params[:suggestedLatency] = info[:defaultLowInputLatency].to_f
        input_params[:hostApiSpecificStreamInfo] = nil

        stream_ptr_ptr = ffi::MemoryPointer.new(:pointer)
        result = mod.Pa_OpenStream(
          stream_ptr_ptr,
          input_params.to_ptr,
          nil,
          Float(sample_rate),
          Integer(frames_per_buffer),
          PA_NO_FLAGS,
          nil,
          nil
        )
        return terminate_with_nil(mod) unless ok?(result)

        stream_pointer = stream_ptr_ptr.read_pointer
        return terminate_with_nil(mod) if stream_pointer.null?

        Stream.new(mod: mod, pointer: stream_pointer, channels: actual_channels)
      rescue StandardError
        mod&.Pa_Terminate
        nil
      end

      # @param stream [Vizcore::Audio::PortAudioFFI::Stream, nil]
      # @return [nil]
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

      def resolve_input_device(mod, device)
        if integer_string?(device)
          index = Integer(device)
          pointer = mod.Pa_GetDeviceInfo(index)
          return nil if pointer.null?

          info = mod::DeviceInfo.new(pointer)
          return nil unless info[:maxInputChannels].positive?

          return [index, info]
        end

        find_input_device_by_name(mod, device.to_s)
      end

      def find_input_device_by_name(mod, query)
        normalized_query = query.downcase
        count = mod.Pa_GetDeviceCount
        return nil if count <= 0

        count.times do |index|
          pointer = mod.Pa_GetDeviceInfo(index)
          next if pointer.null?

          info = mod::DeviceInfo.new(pointer)
          next unless info[:maxInputChannels].positive?

          name = info[:name].read_string
          return [index, info] if name.downcase.include?(normalized_query)
        end

        nil
      end

      def integer_string?(value)
        value.to_s.match?(/\A\d+\z/)
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

        stream_parameters = Class.new(ffi::Struct)
        stream_parameters.layout :device, :int,
                                 :channelCount, :int,
                                 :sampleFormat, :ulong,
                                 :suggestedLatency, :double,
                                 :hostApiSpecificStreamInfo, :pointer
        mod.const_set(:StreamParameters, stream_parameters)

        mod.attach_function :Pa_Initialize, [], :int
        mod.attach_function :Pa_Terminate, [], :int
        mod.attach_function :Pa_GetDeviceCount, [], :int
        mod.attach_function :Pa_GetDeviceInfo, [:int], :pointer
        mod.attach_function :Pa_OpenDefaultStream, [:pointer, :int, :int, :ulong, :double, :ulong, :pointer, :pointer], :int
        mod.attach_function :Pa_OpenStream, [:pointer, :pointer, :pointer, :double, :ulong, :ulong, :pointer, :pointer], :int
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
