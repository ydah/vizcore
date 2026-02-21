# frozen_string_literal: true

module Vizcore
  module Audio
    class MidiInput
      def self.available_devices
        require "unimidi"
        UniMIDI::Input.all.map { |device| { name: device.name } }
      rescue LoadError
        []
      end
    end
  end
end
