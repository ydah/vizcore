# frozen_string_literal: true

require "vizcore/audio/midi_input"
require "vizcore/dsl/midi_map_executor"

RSpec.describe Vizcore::DSL::MidiMapExecutor do
  def midi_event(type:, data1:, data2: 0, channel: 0)
    Vizcore::Audio::MidiInput::Event.new(
      type: type,
      channel: channel,
      data1: data1,
      data2: data2,
      raw: [0x90, data1, data2],
      timestamp: Time.now.to_f
    )
  end

  it "executes switch_scene for matched note mapping" do
    executor = described_class.new(
      midi_maps: [
        { trigger: { note: 36 }, action: proc { switch_scene :drop } }
      ],
      scenes: [
        { name: :intro, layers: [{ name: :intro_layer }] },
        { name: :drop, layers: [{ name: :drop_layer, type: :shader }] }
      ],
      globals: {}
    )

    actions = executor.handle_event(midi_event(type: :note_on, data1: 36, data2: 110))

    expect(actions).to include(
      hash_including(
        type: :switch_scene,
        scene: hash_including(name: :drop)
      )
    )
  end

  it "executes set for matched control-change mapping and updates globals" do
    executor = described_class.new(
      midi_maps: [
        { trigger: { cc: 1 }, action: proc { |value| set :global_intensity, value / 127.0 } }
      ],
      scenes: [],
      globals: {}
    )

    actions = executor.handle_event(midi_event(type: :control_change, data1: 1, data2: 64))

    expect(actions).to include(
      hash_including(type: :set_global, key: :global_intensity)
    )
    expect(executor.globals[:global_intensity]).to be_within(0.0001).of(64.0 / 127.0)
  end

  it "emits next and previous scene actions" do
    executor = described_class.new(
      midi_maps: [
        { trigger: { note: 37 }, action: proc { next_scene } },
        { trigger: { note: 38 }, action: proc { previous_scene(effect: { name: :crossfade }) } }
      ],
      scenes: [],
      globals: {}
    )

    next_actions = executor.handle_event(midi_event(type: :note_on, data1: 37, data2: 100))
    previous_actions = executor.handle_event(midi_event(type: :note_on, data1: 38, data2: 100))

    expect(next_actions).to eq([{ type: :next_scene, effect: nil }])
    expect(previous_actions).to eq([{ type: :previous_scene, effect: { name: :crossfade } }])
  end

  it "filters mappings by MIDI channel" do
    executor = described_class.new(
      midi_maps: [
        { trigger: { note: 36, channel: 1 }, action: proc { switch_scene :drop } }
      ],
      scenes: [{ name: :drop, layers: [] }],
      globals: {}
    )

    expect(executor.handle_event(midi_event(type: :note_on, data1: 36, data2: 100, channel: 0))).to eq([])
    expect(executor.handle_event(midi_event(type: :note_on, data1: 36, data2: 100, channel: 1))).to include(
      hash_including(type: :switch_scene)
    )
  end

  it "applies CC deadband, smoothing, and relative encoder deltas" do
    values = []
    executor = described_class.new(
      midi_maps: [
        { trigger: { cc: 1, deadband: 2, smooth: 0.5 }, action: proc { |value| values << value } },
        { trigger: { cc: 2, relative: true, deadband: 1 }, action: proc { |value| values << value } }
      ],
      scenes: [],
      globals: {}
    )

    executor.handle_event(midi_event(type: :control_change, data1: 1, data2: 10))
    executor.handle_event(midi_event(type: :control_change, data1: 1, data2: 11))
    executor.handle_event(midi_event(type: :control_change, data1: 1, data2: 20))
    executor.handle_event(midi_event(type: :control_change, data1: 2, data2: 1))
    executor.handle_event(midi_event(type: :control_change, data1: 2, data2: 64))
    executor.handle_event(midi_event(type: :control_change, data1: 2, data2: 68))

    expect(values).to eq([10, 15.0, -60])
  end

  it "supports MIDI CC soft takeover (pickup) before applying values" do
    values = []
    executor = described_class.new(
      midi_maps: [
        { trigger: { cc: 1, pickup: true }, action: proc { |value| values << value } },
        { trigger: { cc: 2 }, action: proc { |value| values << value } }
      ],
      scenes: [],
      globals: {}
    )

    executor.handle_event(midi_event(type: :control_change, data1: 1, data2: 20))
    executor.handle_event(midi_event(type: :control_change, data1: 1, data2: 40))
    executor.handle_event(midi_event(type: :control_change, data1: 1, data2: 21))
    executor.handle_event(midi_event(type: :control_change, data1: 2, data2: 30))

    expect(values).to eq([21, 30])
  end

  it "emits live control actions" do
    executor = described_class.new(
      midi_maps: [
        { trigger: { note: 40 }, action: proc { blackout } },
        { trigger: { note: 41 }, action: proc { freeze(false) } }
      ],
      scenes: [],
      globals: {}
    )

    expect(executor.handle_event(midi_event(type: :note_on, data1: 40, data2: 100))).to eq(
      [{ type: :live_control, control: "blackout", value: true }]
    )
    expect(executor.handle_event(midi_event(type: :note_on, data1: 41, data2: 100))).to eq(
      [{ type: :live_control, control: "freeze", value: false }]
    )
  end

  it "ignores unmatched mappings" do
    executor = described_class.new(
      midi_maps: [{ trigger: { note: 36 }, action: proc { switch_scene :drop } }],
      scenes: [{ name: :drop, layers: [] }],
      globals: {}
    )

    actions = executor.handle_event(midi_event(type: :note_on, data1: 40, data2: 90))
    expect(actions).to eq([])
  end
end
