# frozen_string_literal: true

require "timeout"
require "vizcore/audio/midi_input"

RSpec.describe Vizcore::Audio::MidiInput do
  class FakeMidiInput
    attr_reader :closed

    def initialize(messages)
      @messages = Queue.new
      messages.each { |message| @messages << message }
      @closed = false
    end

    def gets
      @messages.pop(true)
    rescue ThreadError
      nil
    end

    def close
      @closed = true
    end
  end

  class FakeMidiDevice
    attr_reader :name, :device_id

    def initialize(name:, device_id:, input:)
      @name = name
      @device_id = device_id
      @input = input
    end

    def open
      @input
    end
  end

  def build_backend(devices)
    mod = Module.new
    input_class = Class.new
    input_class.define_singleton_method(:all) { devices }
    mod.const_set(:Input, input_class)
    mod
  end

  it "lists available midi devices from backend" do
    input = FakeMidiInput.new([])
    device = FakeMidiDevice.new(name: "Launchpad", device_id: 11, input: input)

    devices = described_class.available_devices(backend: build_backend([device]))

    expect(devices).to eq([{ id: 11, name: "Launchpad" }])
  end

  it "captures midi events and emits callback" do
    input = FakeMidiInput.new([[0x90, 60, 100], [0xB0, 1, 64]])
    device = FakeMidiDevice.new(name: "Controller", device_id: 3, input: input)
    backend = build_backend([device])
    callback_events = []

    midi = described_class.new(backend: backend)
    midi.start { |event| callback_events << event }

    events = Timeout.timeout(1) do
      loop do
        polled = midi.poll
        break polled if polled.length >= 2
        sleep(0.01)
      end
    end

    expect(events.map(&:type)).to eq(%i[note_on control_change])
    expect(events.map(&:data1)).to eq([60, 1])
    expect(callback_events.map(&:type)).to eq(%i[note_on control_change])
  ensure
    midi&.stop
    expect(input.closed).to eq(true)
  end

  it "supports selecting midi device by name" do
    primary = FakeMidiDevice.new(name: "Primary", device_id: 1, input: FakeMidiInput.new([]))
    target_input = FakeMidiInput.new([[0x90, 64, 127]])
    target = FakeMidiDevice.new(name: "TargetPad", device_id: 2, input: target_input)
    backend = build_backend([primary, target])

    midi = described_class.new(device: "targetpad", backend: backend)
    midi.start

    event = Timeout.timeout(1) do
      loop do
        polled = midi.poll(1)
        break polled.first unless polled.empty?
        sleep(0.01)
      end
    end

    expect(event.type).to eq(:note_on)
    expect(event.data1).to eq(64)
  ensure
    midi&.stop
  end
end
