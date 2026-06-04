# frozen_string_literal: true

require "vizcore/analysis/experimental/japanese_hiragana_guesser"

RSpec.describe Vizcore::Analysis::Experimental::JapaneseHiraganaGuesser do
  def active_features(overrides = {})
    {
      amplitude: 0.55,
      peak: 0.82,
      bands: { sub: 0.1, low: 0.7, mid: 0.7, high: 0.05 },
      onset: 0.08,
      onsets: { sub: 0.0, low: 0.02, mid: 0.08, high: 0.02 },
      spectral_centroid: 2_500.0,
      spectral_rolloff: 3_500.0,
      spectral_flatness: 0.18,
      spectral_flux: 0.08,
      zero_crossing_rate: 0.06,
      peak_frequency: 850.0
    }.merge(overrides)
  end

  def call_guesser(guesser, features = active_features, timestamp_ms: 0.0)
    guesser.call(
      samples: Array.new(1024, 0.2),
      fft: nil,
      features: features,
      timestamp_ms: timestamp_ms
    )
  end

  def nasal_features(overrides = {})
    active_features(
      {
        amplitude: 0.42,
        peak: 0.7,
        bands: { sub: 0.45, low: 0.65, mid: 0.55, high: 0.05 },
        onset: 0.02,
        onsets: { sub: 0.0, low: 0.01, mid: 0.02, high: 0.0 },
        spectral_centroid: 1_200.0,
        spectral_rolloff: 2_200.0,
        spectral_flatness: 0.08,
        spectral_flux: 0.02,
        zero_crossing_rate: 0.025,
        peak_frequency: 0.0
      }.merge(overrides)
    )
  end

  def formant_features(overrides = {})
    {
      high_ratio: 0.1,
      low_ratio: 0.5,
      low_mid_ratio: 0.5,
      mid_ratio: 0.4,
      centroid_norm: 0.06,
      peak_frequency: 0.0,
      spectral_flatness: 0.05,
      zero_crossing_rate: 0.02
    }.merge(overrides)
  end

  it "returns a silent payload for silent input" do
    guesser = described_class.new(sample_rate: 44_100, frame_size: 1024)

    result = guesser.call(samples: Array.new(1024, 0.0), fft: nil, features: {}, timestamp_ms: 0.0)

    expect(result).to include(
      text: "",
      hiragana: nil,
      confidence: 0.0,
      stable: false,
      changed: false,
      silence: true,
      candidates: []
    )
  end

  it "guesses a vowel-like hiragana from active acoustic features" do
    guesser = described_class.new(sample_rate: 44_100, frame_size: 1024, update: :frame, min_confidence: 0.1)

    result = call_guesser(guesser)

    expect(result[:hiragana]).to be_a(String)
    expect(%w[a i u e o]).to include(result[:vowel])
    expect(result[:confidence]).to be > 0.1
    expect(result[:candidates]).not_to be_empty
  end

  it "uses window_ms to stabilize vowel scoring across recent frames" do
    guesser = described_class.new(sample_rate: 44_100, frame_size: 1024, update: :frame, min_confidence: 0.1, window_ms: 220)

    [0.0, 45.0, 90.0, 135.0].each do |timestamp_ms|
      call_guesser(guesser, active_features(peak_frequency: 850.0, spectral_centroid: 2_400.0), timestamp_ms: timestamp_ms)
    end
    result = call_guesser(
      guesser,
      active_features(
        bands: { sub: 0.0, low: 0.05, mid: 0.35, high: 0.95 },
        peak_frequency: 2_250.0,
        spectral_centroid: 6_000.0,
        spectral_flatness: 0.5,
        zero_crossing_rate: 0.22
      ),
      timestamp_ms: 180.0
    )

    expect(result[:vowel]).to eq("a")
  end

  it "uses unknown_text when confidence is below the configured minimum" do
    guesser = described_class.new(
      sample_rate: 44_100,
      frame_size: 1024,
      update: :frame,
      min_confidence: 0.99,
      unknown_text: "?"
    )

    result = call_guesser(guesser)

    expect(result[:text]).to eq("?")
    expect(result[:hiragana]).to be_nil
    expect(result[:silence]).to eq(false)
  end

  it "orders candidates by confidence" do
    guesser = described_class.new(sample_rate: 44_100, frame_size: 1024, update: :frame, min_confidence: 0.1, candidates: 5)

    result = call_guesser(guesser)
    confidences = result[:candidates].map { |candidate| candidate[:confidence] }

    expect(confidences).to eq(confidences.sort.reverse)
  end

  it "uses formant-like peaks to separate vowel shapes" do
    guesser = described_class.new(sample_rate: 48_000, frame_size: 1024)

    examples = {
      a: formant_features(f1_frequency: 560.0, f2_frequency: 900.0, centroid_norm: 0.07, high_ratio: 0.25, low_ratio: 0.28),
      i: formant_features(f1_frequency: 280.0, f2_frequency: 3_050.0, centroid_norm: 0.07, high_ratio: 0.30, low_ratio: 0.62),
      u: formant_features(f1_frequency: 240.0, f2_frequency: 900.0, centroid_norm: 0.04, high_ratio: 0.09, low_ratio: 0.80),
      e: formant_features(f1_frequency: 320.0, f2_frequency: 1_950.0, centroid_norm: 0.072, high_ratio: 0.18, low_ratio: 0.50, mid_ratio: 0.45),
      o: formant_features(f1_frequency: 305.0, f2_frequency: 850.0, centroid_norm: 0.043, high_ratio: 0.12, low_ratio: 0.70, low_mid_ratio: 0.55)
    }

    examples.each do |vowel, features|
      scores = guesser.send(:score_vowels, features)
      expect(scores.max_by { |_key, value| value }.first).to eq(vowel)
    end

    broad_o_scores = guesser.send(
      :score_vowels,
      formant_features(f1_frequency: 300.0, f2_frequency: 1_600.0, centroid_norm: 0.060, high_ratio: 0.20, low_ratio: 0.59, low_mid_ratio: 0.55)
    )
    expect(broad_o_scores.max_by { |_key, value| value }.first).to eq(:o)
  end

  it "adds a sustained nasal candidate for syllabic n" do
    guesser = described_class.new(sample_rate: 44_100, frame_size: 1024, update: :frame, min_confidence: 0.1, candidates: 10)

    [0.0, 60.0, 120.0, 180.0].each do |timestamp_ms|
      call_guesser(guesser, nasal_features, timestamp_ms: timestamp_ms)
    end
    result = call_guesser(guesser, nasal_features, timestamp_ms: 240.0)

    expect(result[:candidates].map { |candidate| candidate[:text] }).to include("ん")
  end

  it "keeps a syllable hint across following vowel frames" do
    guesser = described_class.new(sample_rate: 48_000, frame_size: 1024, candidates: 10)
    vowel_scores = { a: 0.92, i: 0.1, u: 0.2, e: 0.2, o: 0.3 }
    consonant_scores = { nil => 0.85 }
    attack_features = formant_features(
      f1_frequency: 500.0,
      f2_frequency: 850.0,
      high_ratio: 0.16,
      low_ratio: 0.34,
      centroid_norm: 0.065,
      attack_strength: 1.0,
      attack_centroid_norm: 0.12,
      attack_zcr: 0.08,
      attack_flatness: 0.18
    )

    first = guesser.send(:build_kana_candidates, vowel_scores, consonant_scores, attack_features)
    second = guesser.send(:build_kana_candidates, vowel_scores, consonant_scores, formant_features)

    expect(first.map { |candidate| candidate[:text] }).to include("か")
    expect(second.map { |candidate| candidate[:text] }).to include("か")
  end

  it "uses a noisy release to separate ka from plain open vowels" do
    guesser = described_class.new(sample_rate: 48_000, frame_size: 1024)
    vowel_scores = { a: 0.82, i: 0.1, u: 0.1, e: 0.1, o: 0.2 }
    release_features = formant_features(
      f1_frequency: 610.0,
      f2_frequency: 1_315.0,
      high_ratio: 0.54,
      low_ratio: 0.10,
      zero_crossing_rate: 0.13,
      spectral_flatness: 0.29,
      attack_strength: 0.23,
      attack_centroid_norm: 0.12,
      attack_zcr: 0.13,
      attack_flatness: 0.29
    )

    scores = guesser.send(:syllable_hint_scores, release_features, vowel_scores)

    expect(scores.fetch("か").fetch(:score)).to be >= scores.fetch("か").fetch(:threshold)
  end

  it "detects ma from a nasal murmur moving into an open vowel" do
    guesser = described_class.new(sample_rate: 48_000, frame_size: 1024)
    vowel_scores = { a: 0.48, i: 0.1, u: 0.45, e: 0.2, o: 0.9 }
    features = formant_features(
      f1_frequency: 329.0,
      f2_frequency: 804.0,
      high_ratio: 0.09,
      low_ratio: 0.57,
      attack_f1_frequency: 188.0,
      attack_f2_frequency: 986.0,
      attack_low_ratio: 0.84,
      attack_high_ratio: 0.04,
      attack_nasal_score: 0.71
    )

    scores = guesser.send(:syllable_hint_scores, features, vowel_scores)

    expect(scores.fetch("ま").fetch(:score)).to be >= scores.fetch("ま").fetch(:threshold)
  end

  it "requires repeated soft gi evidence before remembering the hint" do
    guesser = described_class.new(sample_rate: 48_000, frame_size: 1024, candidates: 10)
    vowel_scores = { a: 0.1, i: 0.58, u: 0.3, e: 0.25, o: 0.2 }
    consonant_scores = { nil => 0.82 }
    gi_features = formant_features(
      f1_frequency: 188.0,
      f2_frequency: 2_650.0,
      high_ratio: 0.23,
      low_ratio: 0.70,
      zero_crossing_rate: 0.010,
      spectral_flatness: 0.080
    )
    following_vowel = formant_features(
      f1_frequency: 220.0,
      f2_frequency: 2_000.0,
      high_ratio: 0.12,
      low_ratio: 0.68
    )

    first = guesser.send(:build_kana_candidates, vowel_scores, consonant_scores, gi_features)
    second = guesser.send(:build_kana_candidates, vowel_scores, consonant_scores, following_vowel)
    guesser.reset
    guesser.send(:build_kana_candidates, vowel_scores, consonant_scores, gi_features)
    guesser.send(:build_kana_candidates, vowel_scores, consonant_scores, gi_features)
    remembered = guesser.send(:build_kana_candidates, vowel_scores, consonant_scores, following_vowel)

    expect(first.map { |candidate| candidate[:text] }).to include("ぎ")
    expect(second.map { |candidate| candidate[:text] }).not_to include("ぎ")
    expect(remembered.map { |candidate| candidate[:text] }).to include("ぎ")
  end

  it "detects weak tsu from a quiet high-zcr back vowel shape" do
    guesser = described_class.new(sample_rate: 48_000, frame_size: 1024)
    vowel_scores = { a: 0.1, i: 0.1, u: 0.5, e: 0.2, o: 0.42 }
    features = formant_features(
      f1_frequency: 188.0,
      f2_frequency: 1_315.0,
      low_ratio: 0.73,
      high_ratio: 0.12,
      zero_crossing_rate: 0.019,
      spectral_flatness: 0.045
    )

    scores = guesser.send(:syllable_hint_scores, features, vowel_scores)
    n_candidate = guesser.send(:syllabic_n_candidate, features.merge(nasal_score: 0.70, nasal_stability: 0.72, voice_duration_ms: 220.0), vowel_scores)

    expect(scores.fetch("つ").fetch(:score)).to be >= scores.fetch("つ").fetch(:threshold)
    expect(n_candidate).to be_nil
  end

  it "detects soft gi without promoting a fully fronted i vowel" do
    guesser = described_class.new(sample_rate: 48_000, frame_size: 1024)
    vowel_scores = { a: 0.1, i: 0.58, u: 0.3, e: 0.25, o: 0.2 }
    gi_features = formant_features(
      f1_frequency: 188.0,
      f2_frequency: 2_650.0,
      low_ratio: 0.70,
      high_ratio: 0.23,
      zero_crossing_rate: 0.010,
      spectral_flatness: 0.080
    )
    front_i_features = formant_features(
      f1_frequency: 188.0,
      f2_frequency: 3_190.0,
      low_ratio: 0.60,
      high_ratio: 0.32,
      zero_crossing_rate: 0.014,
      spectral_flatness: 0.075
    )

    scores = guesser.send(:syllable_hint_scores, gi_features, vowel_scores)
    front_scores = guesser.send(:syllable_hint_scores, front_i_features, vowel_scores)

    expect(scores.fetch("ぎ").fetch(:score)).to be >= scores.fetch("ぎ").fetch(:threshold)
    expect(front_scores.fetch("ぎ").fetch(:score)).to be < front_scores.fetch("ぎ").fetch(:threshold)
  end

  it "detects soft bi without promoting a plain front vowel" do
    guesser = described_class.new(sample_rate: 48_000, frame_size: 1024)
    vowel_scores = { a: 0.1, i: 0.58, u: 0.3, e: 0.25, o: 0.2 }
    bi_features = formant_features(
      f1_frequency: 188.0,
      f2_frequency: 3_050.0,
      low_ratio: 0.755,
      high_ratio: 0.170,
      zero_crossing_rate: 0.018,
      spectral_flatness: 0.060
    )
    plain_i_features = formant_features(
      f1_frequency: 188.0,
      f2_frequency: 3_120.0,
      low_ratio: 0.62,
      high_ratio: 0.300,
      zero_crossing_rate: 0.016,
      spectral_flatness: 0.070
    )

    scores = guesser.send(:syllable_hint_scores, bi_features, vowel_scores)
    plain_scores = guesser.send(:syllable_hint_scores, plain_i_features, vowel_scores)

    expect(scores.fetch("び").fetch(:score)).to be >= scores.fetch("び").fetch(:threshold)
    expect(plain_scores.fetch("び").fetch(:score)).to be < plain_scores.fetch("び").fetch(:threshold)
  end

  it "drops remembered gi once the following frame is clearly a front vowel" do
    guesser = described_class.new(sample_rate: 48_000, frame_size: 1024, candidates: 10)
    vowel_scores = { a: 0.1, i: 0.72, u: 0.25, e: 0.25, o: 0.2 }
    gi_candidate = guesser.send(
      :candidate_hash,
      text: "ぎ",
      consonant: :g,
      vowel: :i,
      confidence: 0.90,
      vowel_confidence: 0.72,
      consonant_confidence: 0.80
    )
    guesser.send(:remember_syllable_hint, gi_candidate, timestamp_ms: 0.0)
    guesser.send(:remember_syllable_hint, gi_candidate, timestamp_ms: 20.0)
    front_i_features = formant_features(
      f2_frequency: 3_190.0,
      high_ratio: 0.32,
      timestamp_ms: 40.0
    )

    memory = guesser.send(:active_syllable_hint_memory, front_i_features, vowel_scores)

    expect(memory).to be_nil
  end

  it "detects weak ru from a very low-f1 rounded vowel shape" do
    guesser = described_class.new(sample_rate: 48_000, frame_size: 1024)
    vowel_scores = { a: 0.15, i: 0.2, u: 0.58, e: 0.2, o: 0.5 }
    features = formant_features(
      f1_frequency: 188.0,
      f2_frequency: 1_045.0,
      low_ratio: 0.78,
      high_ratio: 0.09,
      zero_crossing_rate: 0.011,
      spectral_flatness: 0.058
    )

    scores = guesser.send(:syllable_hint_scores, features, vowel_scores)

    expect(scores.fetch("る").fetch(:score)).to be >= scores.fetch("る").fetch(:threshold)
  end

  it "detects quiet low-frequency ru variants" do
    guesser = described_class.new(sample_rate: 48_000, frame_size: 1024)
    vowel_scores = { a: 0.25, i: 0.2, u: 0.62, e: 0.2, o: 0.5 }
    very_back = formant_features(
      f1_frequency: 188.0,
      f2_frequency: 798.0,
      low_ratio: 0.875,
      high_ratio: 0.045,
      zero_crossing_rate: 0.012,
      spectral_flatness: 0.038,
      burst_strength: 0.05
    )
    quiet_mid = formant_features(
      f1_frequency: 188.0,
      f2_frequency: 1_345.0,
      low_ratio: 0.870,
      high_ratio: 0.050,
      zero_crossing_rate: 0.011,
      spectral_flatness: 0.040,
      burst_strength: 0.05
    )

    very_back_scores = guesser.send(:syllable_hint_scores, very_back, vowel_scores)
    quiet_mid_scores = guesser.send(:syllable_hint_scores, quiet_mid, vowel_scores)

    expect(very_back_scores.fetch("る").fetch(:score)).to be >= very_back_scores.fetch("る").fetch(:threshold)
    expect(quiet_mid_scores.fetch("る").fetch(:score)).to be >= quiet_mid_scores.fetch("る").fetch(:threshold)
  end

  it "keeps a strong tsu onset across following ru-like vowel frames" do
    guesser = described_class.new(sample_rate: 48_000, frame_size: 1024, candidates: 10)
    vowel_scores = { a: 0.2, i: 0.2, u: 0.68, e: 0.2, o: 0.50 }
    consonant_scores = { nil => 0.82 }
    tsu_onset = formant_features(
      f1_frequency: 188.0,
      f2_frequency: 798.0,
      low_ratio: 0.825,
      high_ratio: 0.072,
      zero_crossing_rate: 0.010,
      spectral_flatness: 0.034,
      burst_strength: 0.935,
      timestamp_ms: 0.0
    )
    ru_like_vowel = formant_features(
      f1_frequency: 188.0,
      f2_frequency: 1_125.0,
      low_ratio: 0.844,
      high_ratio: 0.062,
      zero_crossing_rate: 0.010,
      spectral_flatness: 0.042,
      burst_strength: 0.354,
      timestamp_ms: 22.0
    )

    first = guesser.send(:build_kana_candidates, vowel_scores, consonant_scores, tsu_onset)
    second = guesser.send(:build_kana_candidates, vowel_scores, consonant_scores, ru_like_vowel)

    expect(first.map { |candidate| candidate[:text] }).to include("つ")
    expect(second.map { |candidate| candidate[:text] }).to include("つ")
  end

  it "does not promote low-f2 back vowels with higher zcr as syllabic n" do
    guesser = described_class.new(sample_rate: 48_000, frame_size: 1024, update: :frame, min_confidence: 0.1, candidates: 10)
    vowel_scores = { a: 0.1, i: 0.2, u: 0.46, e: 0.25, o: 0.48 }
    back_vowel = formant_features(
      f1_frequency: 188.0,
      f2_frequency: 1_360.0,
      low_ratio: 0.870,
      low_mid_ratio: 0.88,
      high_ratio: 0.050,
      zero_crossing_rate: 0.011,
      spectral_flatness: 0.040,
      nasal_score: 0.78,
      nasal_stability: 0.78,
      voice_duration_ms: 220.0
    )
    nasal = back_vowel.merge(zero_crossing_rate: 0.006)

    expect(guesser.send(:syllabic_n_candidate, back_vowel, vowel_scores)).to be_nil
    expect(guesser.send(:syllabic_n_candidate, nasal, vowel_scores)).not_to be_nil
  end

  it "keeps the current display during hold_ms" do
    guesser = described_class.new(
      sample_rate: 44_100,
      frame_size: 1024,
      update: :candidate,
      min_confidence: 0.1,
      hold_ms: 500,
      hysteresis: 0.0
    )

    first = call_guesser(guesser, active_features(peak_frequency: 850.0, spectral_centroid: 2_500.0), timestamp_ms: 0.0)
    second = call_guesser(
      guesser,
      active_features(
        bands: { sub: 0.0, low: 0.05, mid: 0.45, high: 0.9 },
        peak_frequency: 2_250.0,
        spectral_centroid: 5_400.0,
        spectral_flatness: 0.45,
        zero_crossing_rate: 0.18
      ),
      timestamp_ms: 100.0
    )

    expect(second[:text]).to eq(first[:text])
  end

  it "keeps the current display when a new candidate is inside hysteresis" do
    guesser = described_class.new(
      sample_rate: 44_100,
      frame_size: 1024,
      update: :candidate,
      min_confidence: 0.1,
      hold_ms: 0,
      hysteresis: 0.9
    )

    first = call_guesser(guesser, active_features, timestamp_ms: 0.0)
    second = call_guesser(
      guesser,
      active_features(peak_frequency: 1_450.0, spectral_centroid: 3_800.0),
      timestamp_ms: 600.0
    )

    expect(second[:text]).to eq(first[:text])
  end

  it "falls back from dakuten rows when dakuten is disabled" do
    guesser = described_class.new(sample_rate: 44_100, frame_size: 1024, dakuten: false)

    table = guesser.send(:kana_table_for, :g)

    expect(table).to eq(described_class::KANA_TABLE[:k])
  end

  it "includes debug payload when enabled" do
    guesser = described_class.new(sample_rate: 44_100, frame_size: 1024, update: :frame, min_confidence: 0.1, debug: true)

    result = call_guesser(guesser)

    expect(result[:debug]).to include(
      :rms,
      :zcr,
      :spectral_centroid,
      :vowel_scores,
      :consonant_scores
    )
  end

  it "clears buffers and stable state on reset" do
    guesser = described_class.new(sample_rate: 44_100, frame_size: 1024, update: :candidate, min_confidence: 0.1)
    call_guesser(guesser)

    guesser.reset

    expect(guesser.instance_variable_get(:@sample_buffer)).to be_empty
    expect(guesser.instance_variable_get(:@feature_buffer)).to be_empty
    expect(guesser.instance_variable_get(:@stable_candidate)).to be_nil
  end
end
