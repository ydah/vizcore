# frozen_string_literal: true

require "ffi"

module Vizcore
  module Analysis
    module FFTWFFI
      extend FFI::Library

      LIBRARY_NAMES = %w[
        fftw3
        libfftw3.so.3
        libfftw3.so
        libfftw3-3
        libfftw3.dylib
        libfftw3.3.dylib
        fftw3-3.dll
        libfftw3-3.dll
      ].freeze

      ESTIMATE = 64

      class << self
        def available?
          attach_bindings!
          true
        rescue LoadError, FFI::NotFoundError
          false
        end

        private

        def attach_bindings!
          return if @bindings_attached

          ffi_lib LIBRARY_NAMES
          attach_function :fftw_plan_dft_r2c_1d, %i[int pointer pointer uint], :pointer
          attach_function :fftw_execute, [:pointer], :void
          attach_function :fftw_destroy_plan, [:pointer], :void

          @bindings_attached = true
        end
      end
    end
  end
end
