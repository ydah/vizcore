# frozen_string_literal: true

module Vizcore
  module Audio
    module PortAudioFFI
      extend self

      def available?
        !ffi_module.nil?
      end

      def input_devices
        mod = ffi_module
        return [] unless mod

        mod.Pa_Initialize
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

      private

      def ffi_module
        return @ffi_module if defined?(@ffi_module)

        @ffi_module = build_ffi_module
      end

      def build_ffi_module
        require "ffi"

        mod = Module.new
        mod.extend(FFI::Library)
        mod.ffi_lib("portaudio")

        device_info = Class.new(FFI::Struct)
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
        mod
      rescue LoadError, FFI::NotFoundError, StandardError
        nil
      end
    end
  end
end
