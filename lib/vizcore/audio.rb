# frozen_string_literal: true

module Vizcore
  # Audio input/runtime namespace.
  module Audio
  end
end

require_relative "audio/base_input"
require_relative "audio/dummy_sine_input"
require_relative "audio/file_input"
require_relative "audio/input_manager"
require_relative "audio/mic_input"
require_relative "audio/midi_input"
require_relative "audio/portaudio_ffi"
require_relative "audio/ring_buffer"
