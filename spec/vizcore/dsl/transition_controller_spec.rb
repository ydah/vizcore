# frozen_string_literal: true

require "vizcore/dsl/transition_controller"

RSpec.describe Vizcore::DSL::TransitionController do
  describe "#next_transition" do
    it "returns transition payload when trigger condition matches" do
      controller = described_class.new(
        scenes: [
          { name: :intro, layers: [{ name: :a }] },
          { name: :drop, layers: [{ name: :b, type: :shader }] }
        ],
        transitions: [
          {
            from: :intro,
            to: :drop,
            trigger: proc { beat_count >= 64 && frequency_band(:low) > 0.5 },
            effect: { name: :crossfade, options: { duration: 2.0 } }
          }
        ]
      )

      no_change = controller.next_transition(
        scene_name: :intro,
        audio: { beat_count: 63, bands: { low: 0.8 } }
      )
      changed = controller.next_transition(
        scene_name: :intro,
        audio: { beat_count: 64, bands: { low: 0.8 } }
      )

      expect(no_change).to be_nil
      expect(changed).to include(
        from: :intro,
        to: :drop,
        effect: { name: :crossfade, options: { duration: 2.0 } }
      )
      expect(changed.dig(:scene, :name)).to eq(:drop)
    end

    it "returns nil when target scene does not exist" do
      controller = described_class.new(
        scenes: [{ name: :intro, layers: [] }],
        transitions: [{ from: :intro, to: :missing, trigger: proc { true } }]
      )

      expect(controller.next_transition(scene_name: :intro, audio: {})).to be_nil
    end

    it "exposes frame_count to transition trigger context" do
      controller = described_class.new(
        scenes: [
          { name: :intro, layers: [] },
          { name: :drop, layers: [] }
        ],
        transitions: [
          {
            from: :intro,
            to: :drop,
            trigger: proc { frame_count >= 3 }
          }
        ]
      )

      expect(controller.next_transition(scene_name: :intro, audio: {}, frame_count: 2)).to be_nil
      expect(controller.next_transition(scene_name: :intro, audio: {}, frame_count: 3)).to include(
        from: :intro,
        to: :drop
      )
    end

    it "exposes scene-local seconds to transition trigger context" do
      controller = described_class.new(
        scenes: [
          { name: :intro, layers: [] },
          { name: :drop, layers: [] }
        ],
        transitions: [
          {
            from: :intro,
            to: :drop,
            trigger: proc { seconds >= 1.5 }
          }
        ]
      )

      expect(controller.next_transition(scene_name: :intro, audio: {}, frame_count: 89)).to be_nil
      expect(controller.next_transition(scene_name: :intro, audio: {}, frame_count: 90)).to include(
        from: :intro,
        to: :drop
      )
    end

    it "exposes beat_pulse to transition trigger context" do
      controller = described_class.new(
        scenes: [
          { name: :intro, layers: [] },
          { name: :drop, layers: [] }
        ],
        transitions: [
          {
            from: :intro,
            to: :drop,
            trigger: proc { beat_pulse > 0.75 }
          }
        ]
      )

      expect(controller.next_transition(scene_name: :intro, audio: { beat_pulse: 0.5 })).to be_nil
      expect(controller.next_transition(scene_name: :intro, audio: { beat_pulse: 0.8 })).to include(
        from: :intro,
        to: :drop
      )
    end

    it "exposes beat_confidence to transition trigger context" do
      controller = described_class.new(
        scenes: [
          { name: :intro, layers: [] },
          { name: :drop, layers: [] }
        ],
        transitions: [
          {
            from: :intro,
            to: :drop,
            trigger: proc { beat_confidence > 0.8 }
          }
        ]
      )

      expect(controller.next_transition(scene_name: :intro, audio: { beat_confidence: 0.5 })).to be_nil
      expect(controller.next_transition(scene_name: :intro, audio: { beat_confidence: 0.9 })).to include(
        from: :intro,
        to: :drop
      )
    end

    it "exposes onset values to transition trigger context" do
      controller = described_class.new(
        scenes: [
          { name: :intro, layers: [] },
          { name: :drop, layers: [] }
        ],
        transitions: [
          {
            from: :intro,
            to: :drop,
            trigger: proc { onset > 0.3 && onset(:high) > 0.2 }
          }
        ]
      )

      expect(controller.next_transition(scene_name: :intro, audio: { onset: 0.4, onsets: { high: 0.1 } })).to be_nil
      expect(controller.next_transition(scene_name: :intro, audio: { onset: 0.4, onsets: { high: 0.25 } })).to include(
        from: :intro,
        to: :drop
      )
    end

    it "exposes simple drum confidence to transition trigger context" do
      controller = described_class.new(
        scenes: [
          { name: :intro, layers: [] },
          { name: :drop, layers: [] }
        ],
        transitions: [
          {
            from: :intro,
            to: :drop,
            trigger: proc { kick > 0.5 || snare > 0.5 || hihat > 0.5 }
          }
        ]
      )

      expect(controller.next_transition(scene_name: :intro, audio: { drums: { kick: 0.2 } })).to be_nil
      expect(controller.next_transition(scene_name: :intro, audio: { drums: { kick: 0.8 } })).to include(
        from: :intro,
        to: :drop
      )
    end

    it "exposes beat as an alias for beat? in transition triggers" do
      controller = described_class.new(
        scenes: [
          { name: :intro, layers: [] },
          { name: :drop, layers: [] }
        ],
        transitions: [
          {
            from: :intro,
            to: :drop,
            trigger: proc { beat }
          }
        ]
      )

      expect(controller.next_transition(scene_name: :intro, audio: { beat: false })).to be_nil
      expect(controller.next_transition(scene_name: :intro, audio: { beat: true })).to include(
        from: :intro,
        to: :drop
      )
    end

    it "exposes musical frequency band aliases to transition triggers" do
      controller = described_class.new(
        scenes: [
          { name: :intro, layers: [] },
          { name: :drop, layers: [] }
        ],
        transitions: [
          {
            from: :intro,
            to: :drop,
            trigger: proc { bass > 0.7 && treble > 0.2 }
          }
        ]
      )

      expect(
        controller.next_transition(
          scene_name: :intro,
          audio: { bands: { low: 0.8, high: 0.1 } }
        )
      ).to be_nil
      expect(
        controller.next_transition(
          scene_name: :intro,
          audio: { bands: { low: 0.8, high: 0.3 } }
        )
      ).to include(from: :intro, to: :drop)
    end
  end
end
