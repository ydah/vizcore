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
  end
end
