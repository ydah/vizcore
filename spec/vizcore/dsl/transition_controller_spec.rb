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

    it "uses explicit elapsed seconds when supplied" do
      controller = described_class.new(
        scenes: [
          { name: :intro, layers: [] },
          { name: :drop, layers: [] }
        ],
        transitions: [
          {
            from: :intro,
            to: :drop,
            trigger: proc { seconds >= 2.5 }
          }
        ]
      )

      expect(
        controller.next_transition(scene_name: :intro, audio: {}, frame_count: 999, elapsed_seconds: 2.4)
      ).to be_nil
      expect(
        controller.next_transition(scene_name: :intro, audio: {}, frame_count: 1, elapsed_seconds: 2.5)
      ).to include(from: :intro, to: :drop)
    end

    it "reports trigger errors without raising" do
      reports = []
      controller = described_class.new(
        scenes: [
          { name: :intro, layers: [] },
          { name: :drop, layers: [] }
        ],
        transitions: [
          {
            from: :intro,
            to: :drop,
            trigger: proc { raise "bad trigger" }
          }
        ],
        error_reporter: ->(message) { reports << message }
      )

      expect(controller.next_transition(scene_name: :intro, audio: {})).to be_nil
      expect(reports.join("\n")).to include("transition trigger failed: intro -> drop")
      expect(reports.join("\n")).to include("bad trigger")
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

    it "exposes musical timing sources to transition trigger context" do
      controller = described_class.new(
        scenes: [
          { name: :intro, layers: [] },
          { name: :drop, layers: [] }
        ],
        transitions: [
          {
            from: :intro,
            to: :drop,
            trigger: proc {
              beat_phase > 0.2 &&
                beat_4 &&
                !beat_8 &&
                triplet &&
                bar_phase > 0.5 &&
                bar_count >= 2 &&
                phrase_count >= 1
            }
          }
        ]
      )

      expect(
        controller.next_transition(
          scene_name: :intro,
          audio: {
            beat_phase: 0.25,
            beat_4: true,
            beat_8: false,
            beat_triplet: true,
            bar_phase: 0.75,
            bar_count: 2,
            phrase_count: 1
          }
        )
      ).to include(from: :intro, to: :drop)
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

    it "exposes extended audio features to transition triggers" do
      controller = described_class.new(
        scenes: [
          { name: :intro, layers: [] },
          { name: :drop, layers: [] }
        ],
        transitions: [
          {
            from: :intro,
            to: :drop,
            trigger: proc {
              peak > 0.8 &&
                bpm_confidence > 0.5 &&
                spectral_centroid > 1_000.0 &&
                spectral_rolloff > 4_000.0 &&
                spectral_flatness > 0.2 &&
                spectral_flux > 0.1 &&
                zero_crossing_rate > 0.01
            }
          }
        ]
      )

      expect(
        controller.next_transition(
          scene_name: :intro,
          audio: {
            peak: 0.9,
            bpm_confidence: 0.7,
            spectral_centroid: 1_200.0,
            spectral_rolloff: 4_500.0,
            spectral_flatness: 0.3,
            spectral_flux: 0.2,
            zero_crossing_rate: 0.02
          }
        )
      ).to include(from: :intro, to: :drop)
    end
  end
end
