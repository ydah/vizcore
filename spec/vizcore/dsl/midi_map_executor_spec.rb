# frozen_string_literal: true

require "vizcore/audio/midi_input"
require "vizcore/dsl/midi_map_executor"

RSpec.describe Vizcore::DSL::MidiMapExecutor do
  def midi_event(type:, data1:, data2: 0)
    Vizcore::Audio::MidiInput::Event.new(
      type: type,
      channel: 0,
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
