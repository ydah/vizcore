# frozen_string_literal: true

module Vizcore
  module Analysis
    module Experimental
      # Guesses a nearby Japanese hiragana character from short voice-like
      # acoustic windows. This is intentionally heuristic, not ASR.
      class JapaneseHiraganaGuesser
        DEFAULT_OPTIONS = {
          min_confidence: 0.35,
          hold_ms: 220,
          hysteresis: 0.12,
          window_ms: 180,
          onset_window_ms: 70,
          history_ms: 450,
          silence_gate: nil,
          silence_clear_ms: 600,
          candidates: 3,
          dakuten: true,
          handakuten: true,
          small_kana: false,
          unknown_text: "…",
          silence_text: "",
          update: :stable,
          debug: false
        }.freeze

        VOWELS = %i[a i u e o].freeze
        VOWEL_INDEX = VOWELS.each_with_index.to_h.freeze

        KANA_TABLE = {
          nil => { a: "あ", i: "い", u: "う", e: "え", o: "お" },
          k: { a: "か", i: "き", u: "く", e: "け", o: "こ" },
          s: { a: "さ", i: "し", u: "す", e: "せ", o: "そ" },
          t: { a: "た", i: "ち", u: "つ", e: "て", o: "と" },
          n: { a: "な", i: "に", u: "ぬ", e: "ね", o: "の" },
          h: { a: "は", i: "ひ", u: "ふ", e: "へ", o: "ほ" },
          m: { a: "ま", i: "み", u: "む", e: "め", o: "も" },
          y: { a: "や", u: "ゆ", o: "よ" },
          r: { a: "ら", i: "り", u: "る", e: "れ", o: "ろ" },
          w: { a: "わ", o: "を" }
        }.freeze

        DAKUTEN_TABLE = {
          g: { a: "が", i: "ぎ", u: "ぐ", e: "げ", o: "ご" },
          z: { a: "ざ", i: "じ", u: "ず", e: "ぜ", o: "ぞ" },
          d: { a: "だ", i: "ぢ", u: "づ", e: "で", o: "ど" },
          b: { a: "ば", i: "び", u: "ぶ", e: "べ", o: "ぼ" },
          p: { a: "ぱ", i: "ぴ", u: "ぷ", e: "ぺ", o: "ぽ" }
        }.freeze

        DAKUTEN_FALLBACK = {
          g: :k,
          z: :s,
          d: :t,
          b: :h,
          p: :h
        }.freeze

        ROMAN_OVERRIDES = {
          [nil, :a] => "a",
          [nil, :i] => "i",
          [nil, :u] => "u",
          [nil, :e] => "e",
          [nil, :o] => "o",
          [:s, :i] => "shi",
          [:t, :i] => "chi",
          [:t, :u] => "tsu",
          [:h, :u] => "fu",
          [:z, :i] => "ji"
        }.freeze

        UPDATE_MODES = %i[frame candidate stable].freeze
        FEATURE_BAND_KEYS = %i[sub low mid high].freeze
        WINDOW_SCALAR_KEYS = %i[
          amplitude peak spectral_centroid spectral_rolloff spectral_flatness spectral_flux zero_crossing_rate
          peak_frequency low_ratio low_mid_ratio mid_ratio high_ratio f1_frequency f2_frequency f1_norm f2_norm
        ].freeze
        FORMANT_SMOOTH_RADIUS = 5
        SYLLABLE_HINT_MEMORY_MS = 700.0
        SYLLABLE_HINT_MEMORY_DECAY = 0.10

        attr_reader :options

        # @param sample_rate [Integer]
        # @param frame_size [Integer]
        # @param options [Hash]
        def initialize(sample_rate:, frame_size:, **options)
          @sample_rate = positive_integer(sample_rate, fallback: 44_100)
          @frame_size = positive_integer(frame_size, fallback: 1024)
          @options = normalize_options(DEFAULT_OPTIONS.merge(symbolize_hash(options)))
          @sample_buffer = []
          @feature_buffer = []
          @stable_candidate = nil
          @last_candidate_text = nil
          @same_top_candidate_count = 0
          @last_change_at_ms = 0.0
          @last_output_text = @options[:silence_text]
          @silence_started_at_ms = nil
          @attack_features = nil
          @syllable_hint_memory = nil
          @last_syllable_hint_text = nil
          @same_syllable_hint_count = 0
        end

        # @param samples [Array<Numeric>]
        # @param fft [Hash, Array, nil]
        # @param features [Hash]
        # @param timestamp_ms [Numeric]
        # @return [Hash]
        def call(samples:, fft:, features:, timestamp_ms:)
          now = finite_float(timestamp_ms, fallback: 0.0)
          current = extract_features(samples: samples, fft: fft, features: features)
          update_buffers(samples, current, timestamp_ms: now)
          values = aggregate_feature_window(now, fallback: current)
          values.merge!(temporal_features(now, fallback: current))
          values[:timestamp_ms] = now

          return handle_silence(now, values) if silence?(current)

          @silence_started_at_ms = nil
          candidates, debug = score_candidates(values)
          payload = select_payload(candidates, debug: debug, timestamp_ms: now)
          finish_payload(payload)
        rescue StandardError => e
          finish_payload(safe_unknown_result(error: e))
        end

        # @return [void]
        def reset
          @sample_buffer.clear
          @feature_buffer.clear
          @stable_candidate = nil
          @last_candidate_text = nil
          @same_top_candidate_count = 0
          @last_change_at_ms = 0.0
          @last_output_text = @options[:silence_text]
          @silence_started_at_ms = nil
          @attack_features = nil
          @syllable_hint_memory = nil
          @last_syllable_hint_text = nil
          @same_syllable_hint_count = 0
        end

        # @return [Hash]
        def silent_result(timestamp_ms: nil)
          {
            text: @options[:silence_text],
            hiragana: nil,
            roman: nil,
            consonant: nil,
            vowel: nil,
            vowel_index: nil,
            confidence: 0.0,
            vowel_confidence: 0.0,
            consonant_confidence: 0.0,
            stable: false,
            changed: false,
            silence: true,
            age_ms: timestamp_ms ? age_ms(finite_float(timestamp_ms, fallback: 0.0)) : 0,
            candidates: []
          }
        end

        private

        def normalize_options(values)
          output = values.dup
          output[:min_confidence] = unit_float(output[:min_confidence], fallback: DEFAULT_OPTIONS[:min_confidence])
          output[:hold_ms] = non_negative_integer(output[:hold_ms], fallback: DEFAULT_OPTIONS[:hold_ms])
          output[:hysteresis] = unit_float(output[:hysteresis], fallback: DEFAULT_OPTIONS[:hysteresis])
          output[:window_ms] = positive_integer(output[:window_ms], fallback: DEFAULT_OPTIONS[:window_ms])
          output[:onset_window_ms] = positive_integer(output[:onset_window_ms], fallback: DEFAULT_OPTIONS[:onset_window_ms])
          output[:history_ms] = positive_integer(output[:history_ms], fallback: DEFAULT_OPTIONS[:history_ms])
          output[:silence_gate] = optional_unit_float(output[:silence_gate])
          output[:silence_clear_ms] = non_negative_integer(output[:silence_clear_ms], fallback: DEFAULT_OPTIONS[:silence_clear_ms])
          output[:candidates] = positive_integer(output[:candidates], fallback: DEFAULT_OPTIONS[:candidates]).clamp(1, 10)
          output[:dakuten] = !!output[:dakuten]
          output[:handakuten] = !!output[:handakuten]
          output[:small_kana] = !!output[:small_kana]
          output[:unknown_text] = output[:unknown_text].to_s
          output[:silence_text] = output[:silence_text].to_s
          output[:update] = normalize_update_mode(output[:update])
          output[:debug] = !!output[:debug]
          output
        end

        def normalize_update_mode(value)
          mode = value.to_s.strip.to_sym
          UPDATE_MODES.include?(mode) ? mode : DEFAULT_OPTIONS[:update]
        end

        def extract_features(samples:, fft:, features:)
          raw_features = symbolize_hash(features)
          raw_fft = fft_hash(fft)
          magnitudes = numeric_array(raw_fft[:magnitudes] || raw_fft["magnitudes"])
          bands = normalize_bands(raw_features[:bands])
          ratios = spectral_ratios(magnitudes, bands)
          formants = formant_features(magnitudes)
          amplitude = unit_float(raw_features[:amplitude], fallback: rms(samples))
          peak = unit_float(raw_features[:peak], fallback: peak_level(samples))
          centroid = non_negative_float(raw_features[:spectral_centroid], fallback: 0.0)
          rolloff = non_negative_float(raw_features[:spectral_rolloff], fallback: 0.0)
          peak_frequency = non_negative_float(raw_features[:peak_frequency] || raw_fft[:peak_frequency], fallback: 0.0)
          flatness = unit_float(raw_features[:spectral_flatness], fallback: 0.0)
          flux = unit_float(raw_features[:spectral_flux], fallback: 0.0)
          zcr = unit_float(raw_features[:zero_crossing_rate], fallback: zero_crossing_rate(samples))
          onsets = normalize_bands(raw_features[:onsets])

          {
            amplitude: amplitude,
            peak: peak,
            bands: bands,
            onsets: onsets,
            onset: unit_float(raw_features[:onset], fallback: onsets.values.max || 0.0),
            spectral_centroid: centroid,
            spectral_rolloff: rolloff,
            spectral_flatness: flatness,
            spectral_flux: flux,
            zero_crossing_rate: zcr,
            peak_frequency: peak_frequency,
            centroid_norm: normalized_frequency(centroid),
            rolloff_norm: normalized_frequency(rolloff),
            peak_frequency_norm: normalized_frequency(peak_frequency),
            **ratios,
            **formants
          }
        end

        def update_buffers(samples, features, timestamp_ms:)
          @sample_buffer.concat(numeric_array(samples))
          max_samples = (@sample_rate * @options[:history_ms] / 1000.0).ceil
          @sample_buffer.shift(@sample_buffer.length - max_samples) if @sample_buffer.length > max_samples

          @feature_buffer << features.merge(timestamp_ms: timestamp_ms)
          cutoff = timestamp_ms - @options[:history_ms]
          @feature_buffer.shift while @feature_buffer.first && @feature_buffer.first[:timestamp_ms] < cutoff
          update_attack_features(features, timestamp_ms: timestamp_ms)
        end

        def aggregate_feature_window(now, fallback:, window_ms: @options[:window_ms])
          entries = window_entries(now, window_ms)
          entries = entries.reject { |entry| silence?(entry) }
          return fallback.dup if entries.empty?

          output = fallback.dup
          WINDOW_SCALAR_KEYS.each do |key|
            output[key] = weighted_feature_average(entries, key, fallback: fallback[key].to_f)
          end
          output[:bands] = weighted_band_average(entries, :bands, fallback: fallback[:bands])
          output[:onsets] = weighted_band_average(entries, :onsets, fallback: fallback[:onsets])
          output[:onset] = entries.map { |entry| entry[:onset].to_f }.max.to_f.clamp(0.0, 1.0)
          output[:centroid_norm] = normalized_frequency(output[:spectral_centroid])
          output[:rolloff_norm] = normalized_frequency(output[:spectral_rolloff])
          output[:peak_frequency_norm] = normalized_frequency(output[:peak_frequency])
          output
        end

        def temporal_features(now, fallback:)
          onset_cutoff = now - @options[:onset_window_ms]
          recent = @feature_buffer.select { |entry| entry[:timestamp_ms] >= onset_cutoff }
          current = @feature_buffer.last || {}
          previous = @feature_buffer[-2] || {}
          amplitude_delta = [current[:amplitude].to_f - previous[:amplitude].to_f, 0.0].max
          burst = [
            current[:onset].to_f,
            current[:spectral_flux].to_f,
            current.dig(:onsets, :mid).to_f,
            current.dig(:onsets, :high).to_f,
            amplitude_delta
          ].max.to_f.clamp(0.0, 1.0)
          burst = [burst, recent.map { |entry| entry[:onset].to_f }.max.to_f].max

          active = @feature_buffer.reverse.take_while { |entry| !silence?(entry) }
          duration_ms = active.empty? ? 0.0 : now - active.last[:timestamp_ms].to_f
          nasal_features = aggregate_feature_window(now, fallback: fallback, window_ms: [@options[:window_ms], 240].min)
          nasal = nasal_score(nasal_features)

          {
            burst_strength: burst.clamp(0.0, 1.0),
            **attack_feature_payload(now),
            nasal_score: nasal,
            nasal_stability: nasal_stability_score(now),
            voice_duration_ms: duration_ms.clamp(0.0, @options[:history_ms].to_f)
          }
        end

        def update_attack_features(features, timestamp_ms:)
          return if silence?(features)

          strength = attack_strength(features)
          stored = @attack_features
          if stored.nil? || strength > stored[:attack_strength].to_f
            @attack_features = features.merge(attack_strength: strength, timestamp_ms: timestamp_ms)
          end
        end

        def attack_feature_payload(now)
          attack = @attack_features
          return zero_attack_features unless attack

          {
            attack_strength: attack[:attack_strength].to_f.clamp(0.0, 1.0),
            attack_age_ms: (now - attack[:timestamp_ms].to_f).clamp(0.0, @options[:history_ms].to_f),
            attack_centroid_norm: attack[:centroid_norm].to_f,
            attack_high_ratio: attack[:high_ratio].to_f,
            attack_low_ratio: attack[:low_ratio].to_f,
            attack_low_mid_ratio: attack[:low_mid_ratio].to_f,
            attack_mid_ratio: attack[:mid_ratio].to_f,
            attack_flatness: attack[:spectral_flatness].to_f,
            attack_zcr: attack[:zero_crossing_rate].to_f,
            attack_f1_frequency: attack[:f1_frequency].to_f,
            attack_f2_frequency: attack[:f2_frequency].to_f,
            attack_nasal_score: nasal_score(attack)
          }
        end

        def zero_attack_features
          {
            attack_strength: 0.0,
            attack_age_ms: 0.0,
            attack_centroid_norm: 0.0,
            attack_high_ratio: 0.0,
            attack_low_ratio: 0.0,
            attack_low_mid_ratio: 0.0,
            attack_mid_ratio: 0.0,
            attack_flatness: 0.0,
            attack_zcr: 0.0,
            attack_f1_frequency: 0.0,
            attack_f2_frequency: 0.0,
            attack_nasal_score: 0.0
          }
        end

        def attack_strength(features)
          [
            features[:onset].to_f,
            features[:spectral_flux].to_f,
            features.dig(:onsets, :mid).to_f,
            features.dig(:onsets, :high).to_f,
            features[:amplitude].to_f * 0.35
          ].max.to_f.clamp(0.0, 1.0)
        end

        def score_candidates(features)
          vowel_scores = score_vowels(features)
          vowel, = best_score(vowel_scores)
          consonant_scores = score_consonants(features, vowel)
          candidates = build_kana_candidates(vowel_scores, consonant_scores, features)
          debug = debug_payload(features, vowel_scores, consonant_scores)
          [candidates, debug]
        end

        def score_vowels(features)
          centroid = features[:centroid_norm].to_f
          high = features[:high_ratio].to_f
          low_mid = features[:low_mid_ratio].to_f
          mid = features[:mid_ratio].to_f
          low = features[:low_ratio].to_f
          f1 = features[:f1_frequency].to_f
          f2 = features[:f2_frequency].to_f
          return legacy_vowel_scores(features) unless f1.positive? && f2.positive?

          raw = {
            a: weighted_average([
              closeness_hz(f1, 560.0, width: 210.0),
              closeness_hz(f2, 900.0, width: 520.0),
              closeness(centroid, 0.070, width: 0.070),
              1.0 - low,
              high
            ], [0.34, 0.28, 0.14, 0.14, 0.10]),
            i: weighted_average([
              closeness_hz(f1, 280.0, width: 150.0),
              closeness_hz(f2, 3_050.0, width: 720.0),
              closeness(centroid, 0.070, width: 0.070),
              high,
              1.0 - low * 0.35
            ], [0.28, 0.36, 0.10, 0.18, 0.08]),
            u: weighted_average([
              closeness_hz(f1, 285.0, width: 135.0),
              closeness_hz(f2, 900.0, width: 460.0),
              closeness(centroid, 0.040, width: 0.050),
              1.0 - high,
              low
            ], [0.28, 0.30, 0.14, 0.14, 0.14]),
            e: weighted_average([
              closeness_hz(f1, 320.0, width: 170.0),
              closeness_hz(f2, 1_950.0, width: 620.0),
              closeness(centroid, 0.072, width: 0.075),
              mid,
              1.0 - (high - 0.20).abs
            ], [0.24, 0.38, 0.12, 0.12, 0.14]),
            o: weighted_average([
              closeness_hz(f1, 330.0, width: 145.0),
              closeness_hz(f2, 1_050.0, width: 520.0),
              closeness(centroid, 0.043, width: 0.055),
              1.0 - high,
              low_mid
            ], [0.24, 0.30, 0.18, 0.14, 0.14])
          }
          apply_rounded_back_vowel_hint(raw, f1: f1, f2: f2, high: high, low: low)
          apply_open_vowel_floor_hint(raw, f2: f2, centroid: centroid, high: high, low: low)
          apply_low_centroid_o_hint(raw, f1: f1, centroid: centroid, high: high, low: low)
          normalize_score_hash(raw)
        end

        def apply_rounded_back_vowel_hint(raw, f1:, f2:, high:, low:)
          hint = rounded_back_vowel_hint(f1: f1, f2: f2, high: high, low: low)
          raw[:o] = (raw[:o].to_f + hint * 0.42).clamp(0.0, 1.0)
          raw[:u] = (raw[:u].to_f - hint * 0.26).clamp(0.0, 1.0)
          raw
        end

        def rounded_back_vowel_hint(f1:, f2:, high:, low:)
          raised_f1 = ((f1.to_f - 235.0) / 90.0).clamp(0.0, 1.0)
          back_f2 = closeness_hz(f2, 850.0, width: 180.0)
          quiet_high = (1.0 - high.to_f * 0.4).clamp(0.0, 1.0)
          low_support = ((low.to_f - 0.45) / 0.30).clamp(0.0, 1.0)
          (raised_f1 * back_f2 * quiet_high * low_support).clamp(0.0, 1.0)
        end

        def apply_open_vowel_floor_hint(raw, f2:, centroid:, high:, low:)
          hint = open_vowel_floor_hint(f2: f2, centroid: centroid, high: high, low: low)
          raw[:a] = (raw[:a].to_f + hint * 0.58).clamp(0.0, 1.0)
          raw[:u] = (raw[:u].to_f - hint * 0.36).clamp(0.0, 1.0)
          raw[:o] = (raw[:o].to_f - hint * 0.14).clamp(0.0, 1.0)
          raw
        end

        def open_vowel_floor_hint(f2:, centroid:, high:, low:)
          weak_low_floor = ((0.50 - low.to_f) / 0.24).clamp(0.0, 1.0)
          back_f2 = closeness_hz(f2, 850.0, width: 260.0)
          centered_centroid = closeness(centroid, 0.060, width: 0.050)
          quiet_high = (1.0 - high.to_f * 0.6).clamp(0.0, 1.0)
          (weak_low_floor * back_f2 * centered_centroid * quiet_high).clamp(0.0, 1.0)
        end

        def apply_low_centroid_o_hint(raw, f1:, centroid:, high:, low:)
          hint = low_centroid_o_hint(f1: f1, centroid: centroid, high: high, low: low)
          raw[:o] = (raw[:o].to_f + hint * 0.82).clamp(0.0, 1.0)
          raw[:e] = (raw[:e].to_f - hint * 0.34).clamp(0.0, 1.0)
          raw[:u] = (raw[:u].to_f - hint * 0.10).clamp(0.0, 1.0)
          raw
        end

        def low_centroid_o_hint(f1:, centroid:, high:, low:)
          low_support = ((low.to_f - 0.52) / 0.24).clamp(0.0, 1.0)
          rounded_f1 = closeness_hz(f1, 310.0, width: 115.0) * ((f1.to_f - 255.0) / 60.0).clamp(0.0, 1.0)
          low_centroid = closeness(centroid, 0.060, width: 0.018)
          quiet_high = (1.0 - high.to_f * 0.6).clamp(0.0, 1.0)
          (low_support * rounded_f1 * low_centroid * quiet_high).clamp(0.0, 1.0)
        end

        def legacy_vowel_scores(features)
          centroid = features[:centroid_norm].to_f
          peak = features[:peak_frequency].to_f
          high = features[:high_ratio].to_f
          low_mid = features[:low_mid_ratio].to_f
          mid = features[:mid_ratio].to_f
          low = features[:low_ratio].to_f

          normalize_score_hash(
            a: weighted_average([
              closeness(centroid, 0.115, width: 0.10),
              closeness_hz(peak, 850.0, width: 900.0),
              low_mid,
              1.0 - high
            ], [0.34, 0.26, 0.24, 0.16]),
            i: weighted_average([
              closeness(centroid, 0.245, width: 0.14),
              closeness_hz(peak, 2_250.0, width: 1_500.0),
              high,
              1.0 - low
            ], [0.32, 0.30, 0.26, 0.12]),
            u: weighted_average([
              closeness(centroid, 0.065, width: 0.075),
              closeness_hz(peak, 420.0, width: 520.0),
              1.0 - high,
              (low + low_mid) * 0.5
            ], [0.35, 0.30, 0.20, 0.15]),
            e: weighted_average([
              closeness(centroid, 0.170, width: 0.11),
              closeness_hz(peak, 1_450.0, width: 1_100.0),
              mid,
              1.0 - (high - 0.45).abs
            ], [0.35, 0.30, 0.20, 0.15]),
            o: weighted_average([
              closeness(centroid, 0.090, width: 0.075),
              closeness_hz(peak, 620.0, width: 650.0),
              low_mid,
              1.0 - high
            ], [0.34, 0.30, 0.20, 0.16])
          )
        end

        def score_consonants(features, vowel)
          burst = features[:burst_strength].to_f
          high = features[:high_ratio].to_f
          mid = features[:mid_ratio].to_f
          low = features[:low_ratio].to_f
          flatness = features[:spectral_flatness].to_f
          zcr = features[:zero_crossing_rate].to_f
          nasal = features[:nasal_score].to_f
          centroid = features[:centroid_norm].to_f
          no_consonant = (1.0 - (burst * 0.75 + flatness * 0.15 + zcr * 0.10)).clamp(0.0, 1.0)

          raw = {
            nil => no_consonant,
            k: weighted_average([burst, mid, 1.0 - flatness, closeness(centroid, 0.14, width: 0.16)], [0.45, 0.22, 0.18, 0.15]),
            s: weighted_average([high, flatness, zcr, centroid], [0.38, 0.26, 0.22, 0.14]),
            t: weighted_average([burst, high, zcr, flatness], [0.46, 0.24, 0.18, 0.12]),
            n: weighted_average([nasal, 1.0 - high, low + mid * 0.5, 1.0 - zcr], [0.45, 0.20, 0.20, 0.15]),
            h: weighted_average([high, flatness, zcr, burst * 0.5], [0.34, 0.34, 0.18, 0.14]),
            m: weighted_average([nasal, low, 1.0 - high, 1.0 - zcr], [0.48, 0.22, 0.18, 0.12]),
            y: weighted_average([1.0 - burst, %i[a u o].include?(vowel) ? 0.8 : 0.3, mid, 1.0 - flatness], [0.30, 0.28, 0.22, 0.20]),
            r: weighted_average([burst * 0.8, mid, 1.0 - flatness, 1.0 - high * 0.5], [0.35, 0.28, 0.22, 0.15]),
            w: weighted_average([1.0 - high, low + low_mid_ratio(features), %i[a o].include?(vowel) ? 0.85 : 0.2, 1.0 - zcr], [0.26, 0.28, 0.30, 0.16])
          }

          if @options[:dakuten]
            raw[:g] = raw[:k] * 0.86
            raw[:z] = raw[:s] * 0.84
            raw[:d] = raw[:t] * 0.83
            raw[:b] = raw[:h] * 0.78
          end
          raw[:p] = raw[:h] * 0.76 if @options[:handakuten]

          apply_attack_consonant_hints(raw, features, vowel)
          normalize_score_hash(raw)
        end

        def apply_attack_consonant_hints(raw, features, vowel)
          hints = attack_consonant_scores(features, vowel)
          hints.each do |consonant, score|
            raw[consonant] = [raw[consonant].to_f, score].max
          end

          strongest = hints.values.max.to_f
          return raw unless strongest.positive?

          raw[nil] = raw[nil].to_f * (1.0 - strongest * 0.58)
          %i[w y n].each do |consonant|
            raw[consonant] = raw[consonant].to_f * (1.0 - strongest * 0.32) unless hints.key?(consonant)
          end
          raw[:h] = raw[:h].to_f * (1.0 - strongest * 0.35) if hints.key?(:b)
          raw[:k] = raw[:k].to_f * (1.0 - strongest * 0.28) if hints.key?(:g)
          raw
        end

        def attack_consonant_scores(features, vowel)
          strength = features[:attack_strength].to_f.clamp(0.0, 1.0)
          return {} if strength < 0.04

          high = features[:attack_high_ratio].to_f.clamp(0.0, 1.0)
          low = features[:attack_low_ratio].to_f.clamp(0.0, 1.0)
          centroid = features[:attack_centroid_norm].to_f.clamp(0.0, 1.0)
          flatness = features[:attack_flatness].to_f.clamp(0.0, 1.0)
          zcr = features[:attack_zcr].to_f.clamp(0.0, 1.0)
          nasal = features[:attack_nasal_score].to_f.clamp(0.0, 1.0)
          f1 = features[:attack_f1_frequency].to_f
          f2 = features[:attack_f2_frequency].to_f
          scores = {}

          scores[:k] = thresholded_attack_score(k_attack_score(strength, centroid, high, flatness, zcr, vowel), threshold: 0.90)
          scores[:t] = thresholded_attack_score(t_attack_score(strength, low, high, centroid, vowel))
          scores[:m] = thresholded_attack_score(m_attack_score(strength, centroid, high, low, nasal, f1, vowel))
          scores[:r] = thresholded_attack_score(r_attack_score(strength, low, high, zcr, centroid, vowel))
          if @options[:dakuten]
            scores[:g] = thresholded_attack_score(g_attack_score(strength, centroid, high, flatness, zcr, f2, vowel))
            scores[:b] = thresholded_attack_score(b_attack_score(strength, low, high, flatness, f2, vowel))
          end

          scores.compact
        end

        def thresholded_attack_score(score, threshold: 0.56)
          value = score.to_f.clamp(0.0, 1.0)
          value >= threshold ? value : nil
        end

        def k_attack_score(strength, centroid, high, flatness, zcr, vowel)
          return 0.0 unless vowel == :a

          weighted_average([
            strength,
            ((centroid - 0.058) / 0.050).clamp(0.0, 1.0),
            ((zcr - 0.020) / 0.055).clamp(0.0, 1.0),
            ((flatness - 0.055) / 0.120).clamp(0.0, 1.0),
            ((high - 0.12) / 0.22).clamp(0.0, 1.0)
          ], [0.25, 0.25, 0.22, 0.16, 0.12])
        end

        def g_attack_score(strength, centroid, high, flatness, zcr, f2, vowel)
          return 0.0 unless vowel == :i

          weighted_average([
            strength,
            ((centroid - 0.065) / 0.055).clamp(0.0, 1.0),
            ((high - 0.22) / 0.24).clamp(0.0, 1.0),
            ((flatness - 0.075) / 0.110).clamp(0.0, 1.0),
            ((zcr - 0.018) / 0.050).clamp(0.0, 1.0),
            closeness_hz(f2, 2_700.0, width: 850.0)
          ], [0.18, 0.23, 0.17, 0.16, 0.12, 0.14])
        end

        def b_attack_score(strength, low, high, flatness, f2, vowel)
          return 0.0 unless vowel == :i

          weighted_average([
            strength,
            ((low - 0.62) / 0.22).clamp(0.0, 1.0),
            ((0.27 - high) / 0.18).clamp(0.0, 1.0),
            ((flatness - 0.060) / 0.120).clamp(0.0, 1.0),
            closeness_hz(f2, 2_750.0, width: 900.0)
          ], [0.18, 0.30, 0.18, 0.14, 0.20])
        end

        def m_attack_score(strength, centroid, high, low, nasal, f1, vowel)
          return 0.0 unless vowel == :a

          weighted_average([
            strength,
            ((0.064 - centroid) / 0.045).clamp(0.0, 1.0),
            ((0.18 - high) / 0.16).clamp(0.0, 1.0),
            ((low - 0.38) / 0.24).clamp(0.0, 1.0),
            ((nasal - 0.58) / 0.20).clamp(0.0, 1.0),
            closeness_hz(f1, 410.0, width: 190.0)
          ], [0.16, 0.22, 0.16, 0.18, 0.12, 0.16])
        end

        def t_attack_score(strength, low, high, centroid, vowel)
          return 0.0 unless vowel == :u

          weighted_average([
            strength,
            ((0.72 - low) / 0.18).clamp(0.0, 1.0),
            ((high - 0.10) / 0.16).clamp(0.0, 1.0),
            closeness(centroid, 0.048, width: 0.026)
          ], [0.18, 0.38, 0.20, 0.24])
        end

        def r_attack_score(strength, low, high, zcr, centroid, vowel)
          return 0.0 unless vowel == :u

          weighted_average([
            1.0 - strength * 0.45,
            ((low - 0.74) / 0.20).clamp(0.0, 1.0),
            ((0.12 - high) / 0.12).clamp(0.0, 1.0),
            ((0.018 - zcr) / 0.018).clamp(0.0, 1.0),
            closeness(centroid, 0.043, width: 0.026)
          ], [0.12, 0.34, 0.18, 0.16, 0.20])
        end

        def build_kana_candidates(vowel_scores, consonant_scores, features)
          candidates = []
          consonant_scores.each do |consonant, consonant_score|
            table = kana_table_for(consonant)
            next unless table

            vowel_scores.each do |vowel, vowel_score|
              text = table[vowel]
              next unless text

              score = kana_score(consonant, vowel_score, consonant_score, features)
              candidates << candidate_hash(
                text: text,
                consonant: consonant,
                vowel: vowel,
                confidence: score,
                vowel_confidence: vowel_score,
                consonant_confidence: consonant_score
              )
            end
          end

          n_candidate = syllabic_n_candidate(features, vowel_scores)
          candidates << n_candidate if n_candidate
          hint_candidate = syllable_hint_candidate(features, vowel_scores)
          if hint_candidate
            memory = active_syllable_hint_memory(features, vowel_scores)
            if preserve_syllable_hint_memory?(memory, hint_candidate, features)
              candidates << memory
            else
              candidates << remember_syllable_hint(hint_candidate, features)
            end
          else
            @last_syllable_hint_text = nil
            @same_syllable_hint_count = 0
            memory = active_syllable_hint_memory(features, vowel_scores)
            candidates << memory if memory
          end
          candidates.sort_by { |candidate| -candidate[:confidence] }.first(@options[:candidates])
        end

        def remember_syllable_hint(candidate, features)
          text = candidate[:text]
          if text == @last_syllable_hint_text
            @same_syllable_hint_count += 1
          else
            @last_syllable_hint_text = text
            @same_syllable_hint_count = 1
          end
          return candidate if text == "ぎ" && @same_syllable_hint_count < 2
          return candidate if text == "つ" && @same_syllable_hint_count < 2 && candidate[:confidence].to_f < 0.86

          confidence = [candidate[:confidence].to_f, 0.86].max.clamp(0.0, 0.97)
          remembered = candidate.merge(confidence: confidence, score: confidence, hint_timestamp_ms: features[:timestamp_ms].to_f)
          if @syllable_hint_memory.nil? || remembered[:confidence].to_f >= @syllable_hint_memory[:confidence].to_f
            @syllable_hint_memory = remembered
          end
          @syllable_hint_memory
        end

        def preserve_syllable_hint_memory?(memory, candidate, features)
          return false unless memory && memory[:text] == "つ" && candidate[:text] == "る"

          age = features[:timestamp_ms].to_f - memory[:hint_timestamp_ms].to_f
          return false if age > 520.0

          memory[:confidence].to_f >= candidate[:confidence].to_f - 0.10
        end

        def active_syllable_hint_memory(features, vowel_scores)
          memory = @syllable_hint_memory
          return nil unless memory

          age = features[:timestamp_ms].to_f - memory[:hint_timestamp_ms].to_f
          return clear_syllable_hint_memory if age > SYLLABLE_HINT_MEMORY_MS
          return clear_syllable_hint_memory unless syllable_hint_memory_vowel_matches?(memory, vowel_scores, features)

          confidence = (memory[:confidence].to_f - (age / SYLLABLE_HINT_MEMORY_MS) * SYLLABLE_HINT_MEMORY_DECAY).clamp(0.0, 1.0)
          return nil unless confidence >= @options[:min_confidence]

          memory.merge(confidence: confidence, score: confidence)
        end

        def clear_syllable_hint_memory
          @syllable_hint_memory = nil
          nil
        end

        def syllable_hint_memory_vowel_matches?(memory, vowel_scores, features)
          return false if gi_memory_reached_front_vowel?(memory, features)

          memory_vowel = memory[:vowel]&.to_sym
          return true unless memory_vowel && vowel_scores.key?(memory_vowel)

          best_vowel, best_value = best_score(vowel_scores)
          return true if best_vowel == memory_vowel

          margin = case memory[:text]
                   when "ま", "か"
                     0.34
                   when "つ", "る"
                     0.12
                   else
                     0.16
          end
          vowel_scores[memory_vowel].to_f >= best_value - margin
        end

        def gi_memory_reached_front_vowel?(memory, features)
          return false unless memory[:text] == "ぎ"

          features[:f2_frequency].to_f > 3_050.0 && features[:high_ratio].to_f > 0.29
        end

        def syllable_hint_candidate(features, vowel_scores)
          text, payload = syllable_hint_scores(features, vowel_scores).max_by { |_kana, values| values[:score].to_f }
          return nil unless payload && payload[:score].to_f >= payload[:threshold].to_f

          confidence = syllable_hint_confidence(text, payload)
          candidate_hash(
            text: text,
            consonant: payload[:consonant],
            vowel: payload[:vowel],
            confidence: confidence,
            vowel_confidence: vowel_scores[payload[:vowel]].to_f,
            consonant_confidence: payload[:score]
          )
        end

        def syllable_hint_confidence(text, payload)
          score = payload[:score].to_f
          threshold = payload[:threshold].to_f
          base, scale = text == "ま" ? [0.86, 0.90] : [0.78, 0.75]
          (base + (score - threshold) * scale).clamp(0.0, 0.97)
        end

        def syllable_hint_scores(features, vowel_scores)
          {
            "か" => { consonant: :k, vowel: :a, score: ka_hint_score(features, vowel_scores), threshold: 0.80 },
            "ぎ" => { consonant: :g, vowel: :i, score: gi_hint_score(features, vowel_scores), threshold: 0.67 },
            "つ" => { consonant: :t, vowel: :u, score: tsu_hint_score(features, vowel_scores), threshold: 0.70 },
            "び" => { consonant: :b, vowel: :i, score: bi_hint_score(features, vowel_scores), threshold: 0.60 },
            "ま" => { consonant: :m, vowel: :a, score: ma_hint_score(features, vowel_scores), threshold: 0.62 },
            "る" => { consonant: :r, vowel: :u, score: ru_hint_score(features, vowel_scores), threshold: 0.59 }
          }
        end

        def ka_hint_score(features, vowel_scores)
          base = weighted_average([
            vowel_scores[:a].to_f,
            features[:attack_strength].to_f,
            ((features[:attack_centroid_norm].to_f - 0.060) / 0.060).clamp(0.0, 1.0),
            ((features[:attack_zcr].to_f - 0.022) / 0.060).clamp(0.0, 1.0),
            ((features[:attack_flatness].to_f - 0.055) / 0.130).clamp(0.0, 1.0),
            ((0.52 - features[:low_ratio].to_f) / 0.24).clamp(0.0, 1.0)
          ], [0.25, 0.18, 0.20, 0.16, 0.11, 0.10])
          release = ka_release_score(features)
          return base if base >= 0.80 || release < 0.35

          (base + release * 0.30).clamp(0.0, 1.0)
        end

        def ka_release_score(features)
          weighted_average([
            ((features[:high_ratio].to_f - 0.36) / 0.18).clamp(0.0, 1.0),
            ((features[:zero_crossing_rate].to_f - 0.065) / 0.065).clamp(0.0, 1.0),
            ((features[:spectral_flatness].to_f - 0.16) / 0.16).clamp(0.0, 1.0)
          ], [0.34, 0.34, 0.32])
        end

        def gi_hint_score(features, vowel_scores)
          return 0.0 unless @options[:dakuten]

          base = weighted_average([
            vowel_scores[:i].to_f,
            ((features[:f2_frequency].to_f - 2_350.0) / 900.0).clamp(0.0, 1.0),
            ((features[:high_ratio].to_f - 0.15) / 0.18).clamp(0.0, 1.0),
            ((features[:attack_flatness].to_f - 0.070) / 0.120).clamp(0.0, 1.0),
            ((features[:attack_centroid_norm].to_f - 0.060) / 0.055).clamp(0.0, 1.0)
          ], [0.30, 0.24, 0.16, 0.15, 0.15])
          [base, soft_gi_hint_score(features, vowel_scores)].max
        end

        def soft_gi_hint_score(features, vowel_scores)
          f1 = features[:f1_frequency].to_f
          f2 = features[:f2_frequency].to_f
          low = features[:low_ratio].to_f
          high = features[:high_ratio].to_f
          zcr = features[:zero_crossing_rate].to_f
          flatness = features[:spectral_flatness].to_f
          return 0.0 unless f1.positive? && f1 < 205.0
          return 0.0 unless f2.between?(2_420.0, 2_900.0)
          return 0.0 unless low.between?(0.60, 0.79)
          return 0.0 unless high.between?(0.155, 0.285)
          return 0.0 unless zcr <= 0.014

          shape = weighted_average([
            vowel_scores[:i].to_f,
            closeness_hz(f2, 2_700.0, width: 360.0),
            closeness(low, 0.70, width: 0.13),
            closeness(high, 0.21, width: 0.09),
            ((0.014 - zcr) / 0.014).clamp(0.0, 1.0),
            ((flatness - 0.055) / 0.055).clamp(0.0, 1.0)
          ], [0.24, 0.20, 0.16, 0.14, 0.14, 0.12])
          (0.66 + shape * 0.24).clamp(0.0, 0.94)
        end

        def bi_hint_score(features, vowel_scores)
          return 0.0 unless @options[:dakuten]

          base = weighted_average([
            vowel_scores[:i].to_f,
            ((features[:low_ratio].to_f - 0.62) / 0.24).clamp(0.0, 1.0),
            ((0.22 - features[:high_ratio].to_f) / 0.18).clamp(0.0, 1.0),
            closeness_hz(features[:f2_frequency], 2_700.0, width: 900.0),
            ((features[:attack_flatness].to_f - 0.055) / 0.120).clamp(0.0, 1.0)
          ], [0.28, 0.26, 0.18, 0.18, 0.10])
          [base, soft_bi_hint_score(features, vowel_scores)].max
        end

        def soft_bi_hint_score(features, vowel_scores)
          f1 = features[:f1_frequency].to_f
          f2 = features[:f2_frequency].to_f
          low = features[:low_ratio].to_f
          high = features[:high_ratio].to_f
          zcr = features[:zero_crossing_rate].to_f
          flatness = features[:spectral_flatness].to_f
          return 0.0 unless f1.positive? && f1 < 230.0
          return 0.0 unless f2.between?(2_650.0, 3_220.0)
          return 0.0 unless low.between?(0.72, 0.81)
          return 0.0 unless high.between?(0.12, 0.205)
          return 0.0 unless zcr.between?(0.011, 0.024)

          shape = weighted_average([
            [vowel_scores[:i].to_f, 0.52].max,
            closeness_hz(f2, 3_000.0, width: 430.0),
            closeness(low, 0.755, width: 0.075),
            closeness(high, 0.165, width: 0.065),
            closeness(zcr, 0.018, width: 0.009),
            closeness(flatness, 0.060, width: 0.055)
          ], [0.18, 0.18, 0.18, 0.16, 0.18, 0.12])
          (0.62 + shape * 0.28).clamp(0.0, 0.94)
        end

        def ma_hint_score(features, vowel_scores)
          f1 = features[:f1_frequency].to_f
          sustained = if f1 > 330.0
                        weighted_average([
                          vowel_scores[:a].to_f,
                          ((0.17 - features[:high_ratio].to_f) / 0.16).clamp(0.0, 1.0),
                          ((features[:low_ratio].to_f - 0.34) / 0.24).clamp(0.0, 1.0),
                          ((features[:nasal_score].to_f - 0.58) / 0.18).clamp(0.0, 1.0),
                          closeness_hz(f1, 430.0, width: 230.0),
                          closeness_hz(features[:f2_frequency], 840.0, width: 300.0)
                        ], [0.22, 0.16, 0.16, 0.14, 0.17, 0.15])
                      else
                        0.0
                      end

          [sustained, nasal_open_ma_hint_score(features, vowel_scores), rounded_nasal_ma_hint_score(features, vowel_scores)].max
        end

        def rounded_nasal_ma_hint_score(features, vowel_scores)
          f1 = features[:f1_frequency].to_f
          f2 = features[:f2_frequency].to_f
          low = features[:low_ratio].to_f
          high = features[:high_ratio].to_f
          zcr = features[:zero_crossing_rate].to_f
          nasal = features[:nasal_score].to_f
          return 0.0 unless f1.between?(295.0, 385.0)
          return 0.0 unless f2.between?(740.0, 920.0)
          return 0.0 unless low.between?(0.50, 0.67)
          return 0.0 unless high <= 0.105 && zcr <= 0.018 && nasal >= 0.69

          shape = weighted_average([
            [vowel_scores[:a].to_f, vowel_scores[:o].to_f * 0.68].max,
            closeness_hz(f1, 330.0, width: 80.0),
            closeness_hz(f2, 805.0, width: 130.0),
            ((0.67 - low) / 0.17).clamp(0.0, 1.0),
            ((0.105 - high) / 0.105).clamp(0.0, 1.0),
            ((0.018 - zcr) / 0.018).clamp(0.0, 1.0),
            ((nasal - 0.69) / 0.10).clamp(0.0, 1.0)
          ], [0.16, 0.18, 0.18, 0.12, 0.12, 0.10, 0.14])
          shape >= 0.52 ? (shape + 0.18).clamp(0.0, 0.94) : shape
        end

        def nasal_open_ma_hint_score(features, vowel_scores)
          attack_f1 = features[:attack_f1_frequency].to_f
          attack_f2 = features[:attack_f2_frequency].to_f
          current_f1 = features[:f1_frequency].to_f
          current_f2 = features[:f2_frequency].to_f
          return 0.0 unless attack_f1.between?(140.0, 245.0)
          return 0.0 unless attack_f2.between?(760.0, 1_180.0)
          return 0.0 unless current_f1.between?(285.0, 390.0)
          return 0.0 unless current_f2.between?(760.0, 980.0)

          attack_murmur = weighted_average([
            closeness_hz(attack_f1, 190.0, width: 70.0),
            closeness_hz(attack_f2, 960.0, width: 220.0),
            ((features[:attack_low_ratio].to_f - 0.72) / 0.22).clamp(0.0, 1.0),
            ((0.10 - features[:attack_high_ratio].to_f) / 0.10).clamp(0.0, 1.0),
            ((features[:attack_nasal_score].to_f - 0.66) / 0.14).clamp(0.0, 1.0)
          ], [0.24, 0.20, 0.22, 0.18, 0.16])
          current_open = weighted_average([
            [vowel_scores[:a].to_f, vowel_scores[:o].to_f * 0.82].max,
            closeness_hz(current_f1, 330.0, width: 90.0),
            closeness_hz(current_f2, 820.0, width: 180.0),
            closeness(features[:low_ratio].to_f, 0.56, width: 0.22),
            ((0.18 - features[:high_ratio].to_f) / 0.18).clamp(0.0, 1.0)
          ], [0.20, 0.24, 0.20, 0.18, 0.18])
          score = weighted_average([attack_murmur, current_open], [0.52, 0.48])
          score >= 0.62 ? (score + 0.18).clamp(0.0, 1.0) : score
        end

        def tsu_hint_score(features, vowel_scores)
          f1 = features[:f1_frequency].to_f
          f2 = features[:f2_frequency].to_f
          low = features[:low_ratio].to_f
          base = if f1.positive? && f1 < 270.0 && f2.positive? && f2 < 1_500.0 && low < 0.70
                   weighted_average([
                     ((0.68 - low) / 0.35).clamp(0.0, 1.0),
                     ((250.0 - f1) / 230.0).clamp(0.0, 1.0),
                     closeness_hz(f2, 850.0, width: 520.0),
                     ((0.18 - features[:high_ratio].to_f) / 0.18).clamp(0.0, 1.0),
                     ((features[:attack_strength].to_f - 0.04) / 0.26).clamp(0.0, 1.0),
                     [vowel_scores[:u].to_f, vowel_scores[:o].to_f * 0.58].max
                   ], [0.34, 0.24, 0.18, 0.10, 0.06, 0.08])
                 else
                   0.0
                 end
          [base, compact_tsu_hint_score(features), weak_tsu_hint_score(features)].max
        end

        def compact_tsu_hint_score(features)
          f1 = features[:f1_frequency].to_f
          f2 = features[:f2_frequency].to_f
          low = features[:low_ratio].to_f
          high = features[:high_ratio].to_f
          zcr = features[:zero_crossing_rate].to_f
          return 0.0 unless f1 < 270.0
          return 0.0 unless f2.between?(1_000.0, 1_420.0)
          return 0.0 unless low.between?(0.54, 0.69)
          return 0.0 unless high.between?(0.10, 0.24)
          return 0.0 unless zcr > 0.012

          shape = weighted_average([
            ((285.0 - f1) / 120.0).clamp(0.0, 1.0),
            closeness_hz(f2, 1_240.0, width: 380.0),
            closeness(low, 0.62, width: 0.12),
            closeness(high, 0.17, width: 0.10),
            ((zcr - 0.010) / 0.020).clamp(0.0, 1.0),
            ((0.080 - features[:spectral_flatness].to_f) / 0.080).clamp(0.0, 1.0)
          ], [0.18, 0.18, 0.20, 0.16, 0.16, 0.12])
          (0.72 + shape * 0.20).clamp(0.0, 0.94)
        end

        def weak_tsu_hint_score(features)
          [
            weak_back_tsu_hint_score(features),
            weak_front_tsu_hint_score(features),
            noisy_tsu_release_score(features),
            quiet_tsu_onset_score(features)
          ].max
        end

        def noisy_tsu_release_score(features)
          f1 = features[:f1_frequency].to_f
          f2 = features[:f2_frequency].to_f
          low = features[:low_ratio].to_f
          high = features[:high_ratio].to_f
          zcr = features[:zero_crossing_rate].to_f
          flatness = features[:spectral_flatness].to_f
          return 0.0 unless f1.positive? && f1 < 240.0
          return 0.0 unless f2.between?(1_430.0, 1_620.0)
          return 0.0 unless low.between?(0.66, 0.79)
          return 0.0 unless high.between?(0.17, 0.25)
          return 0.0 unless zcr.between?(0.034, 0.070)
          return 0.0 unless flatness.between?(0.085, 0.150)

          shape = weighted_average([
            closeness_hz(f2, 1_505.0, width: 140.0),
            closeness(low, 0.71, width: 0.10),
            closeness(high, 0.21, width: 0.06),
            closeness(zcr, 0.050, width: 0.026),
            closeness(flatness, 0.110, width: 0.045),
            ((features[:burst_strength].to_f - 0.28) / 0.38).clamp(0.0, 1.0)
          ], [0.18, 0.16, 0.18, 0.18, 0.14, 0.16])
          (0.70 + shape * 0.22).clamp(0.0, 0.94)
        end

        def quiet_tsu_onset_score(features)
          f1 = features[:f1_frequency].to_f
          f2 = features[:f2_frequency].to_f
          low = features[:low_ratio].to_f
          high = features[:high_ratio].to_f
          zcr = features[:zero_crossing_rate].to_f
          flatness = features[:spectral_flatness].to_f
          burst = features[:burst_strength].to_f
          return 0.0 unless f1.positive? && f1 < 230.0
          return 0.0 unless low.between?(0.78, 0.88)
          return 0.0 unless high.between?(0.055, 0.100)
          return 0.0 unless zcr.between?(0.0085, 0.016)
          return 0.0 unless flatness.between?(0.025, 0.090)
          return 0.0 unless burst >= 0.72

          compact_front = closeness_hz(f2, 805.0, width: 80.0) * ((burst - 0.88) / 0.08).clamp(0.0, 1.0)
          compact_back = closeness_hz(f2, 1_360.0, width: 170.0) *
                         ((burst - 0.80) / 0.10).clamp(0.0, 1.0) *
                         ((high - 0.058) / 0.040).clamp(0.0, 1.0) *
                         ((zcr - 0.0095) / 0.006).clamp(0.0, 1.0)
          placement = [compact_front, compact_back].max
          return 0.0 unless placement.positive?

          shape = weighted_average([
            placement,
            burst,
            closeness(low, 0.83, width: 0.08),
            closeness(high, 0.072, width: 0.035),
            closeness(zcr, 0.0115, width: 0.006),
            closeness(flatness, 0.048, width: 0.035)
          ], [0.24, 0.20, 0.14, 0.14, 0.14, 0.14])
          (0.70 + shape * 0.22).clamp(0.0, 0.94)
        end

        def weak_back_tsu_hint_score(features)
          f1 = features[:f1_frequency].to_f
          f2 = features[:f2_frequency].to_f
          low = features[:low_ratio].to_f
          high = features[:high_ratio].to_f
          zcr = features[:zero_crossing_rate].to_f
          return 0.0 unless f1.positive? && f1 < 280.0
          return 0.0 unless f2.between?(950.0, 1_700.0)
          return 0.0 unless low.between?(0.64, 0.80)
          return 0.0 unless high.between?(0.075, 0.18)
          return 0.0 unless zcr.between?(0.014, 0.032)

          shape = weighted_average([
            ((285.0 - f1) / 130.0).clamp(0.0, 1.0),
            closeness_hz(f2, 1_320.0, width: 430.0),
            closeness(low, 0.73, width: 0.11),
            closeness(high, 0.12, width: 0.08),
            ((zcr - 0.013) / 0.014).clamp(0.0, 1.0),
            ((0.090 - features[:spectral_flatness].to_f) / 0.090).clamp(0.0, 1.0)
          ], [0.18, 0.18, 0.18, 0.14, 0.20, 0.12])
          (0.66 + shape * 0.24).clamp(0.0, 0.93)
        end

        def weak_front_tsu_hint_score(features)
          f1 = features[:f1_frequency].to_f
          f2 = features[:f2_frequency].to_f
          low = features[:low_ratio].to_f
          high = features[:high_ratio].to_f
          zcr = features[:zero_crossing_rate].to_f
          return 0.0 unless f1.positive? && f1 < 290.0
          return 0.0 unless f2.between?(2_250.0, 2_900.0)
          return 0.0 unless low.between?(0.58, 0.78)
          return 0.0 unless high.between?(0.075, 0.20)
          return 0.0 unless zcr.between?(0.017, 0.036)

          shape = weighted_average([
            ((300.0 - f1) / 150.0).clamp(0.0, 1.0),
            closeness_hz(f2, 2_650.0, width: 520.0),
            closeness(low, 0.72, width: 0.14),
            closeness(high, 0.13, width: 0.09),
            ((zcr - 0.016) / 0.014).clamp(0.0, 1.0),
            ((0.090 - features[:spectral_flatness].to_f) / 0.090).clamp(0.0, 1.0)
          ], [0.18, 0.18, 0.16, 0.14, 0.22, 0.12])
          (0.66 + shape * 0.24).clamp(0.0, 0.93)
        end

        def ru_hint_score(features, vowel_scores)
          f1 = features[:f1_frequency].to_f
          f2 = features[:f2_frequency].to_f
          return 0.0 unless f1.positive? && f2.positive?

          score = weighted_average([
            vowel_scores[:u].to_f,
            ((features[:low_ratio].to_f - 0.70) / 0.20).clamp(0.0, 1.0),
            ((0.10 - features[:high_ratio].to_f) / 0.12).clamp(0.0, 1.0),
            ((230.0 - f1) / 180.0).clamp(0.0, 1.0),
            closeness_hz(f2, 950.0, width: 420.0),
            ((0.020 - features[:zero_crossing_rate].to_f) / 0.020).clamp(0.0, 1.0)
          ], [0.24, 0.24, 0.14, 0.14, 0.14, 0.10])

          [score, weak_ru_hint_score(features, vowel_scores)].max
        end

        def weak_ru_hint_score(features, vowel_scores)
          f1 = features[:f1_frequency].to_f
          f2 = features[:f2_frequency].to_f
          low = features[:low_ratio].to_f
          high = features[:high_ratio].to_f
          zcr = features[:zero_crossing_rate].to_f
          very_back = [very_back_ru_hint_score(features, vowel_scores), quiet_mid_ru_hint_score(features, vowel_scores)].max
          return very_back unless f1.positive? && f1 < 235.0
          return very_back unless f2.between?(900.0, 1_160.0)
          return very_back unless low.between?(0.70, 0.89)
          return very_back unless high <= 0.14 && zcr <= 0.0125

          shape = weighted_average([
            [vowel_scores[:u].to_f, vowel_scores[:o].to_f * 0.72].max,
            closeness_hz(f2, 1_020.0, width: 210.0),
            closeness(low, 0.82, width: 0.13),
            ((0.14 - high) / 0.14).clamp(0.0, 1.0),
            ((0.0125 - zcr) / 0.0125).clamp(0.0, 1.0),
            ((0.080 - features[:spectral_flatness].to_f) / 0.080).clamp(0.0, 1.0)
          ], [0.20, 0.20, 0.18, 0.14, 0.16, 0.12])
          [very_back, (0.66 + shape * 0.24).clamp(0.0, 0.94)].max
        end

        def very_back_ru_hint_score(features, vowel_scores)
          f1 = features[:f1_frequency].to_f
          f2 = features[:f2_frequency].to_f
          low = features[:low_ratio].to_f
          high = features[:high_ratio].to_f
          zcr = features[:zero_crossing_rate].to_f
          burst = features[:burst_strength].to_f
          return 0.0 unless f1.positive? && f1 < 230.0
          return 0.0 unless f2.between?(760.0, 850.0)
          return 0.0 unless low.between?(0.84, 0.92)
          return 0.0 unless high <= 0.065 && zcr <= 0.014
          return 0.0 unless burst <= 0.70

          shape = weighted_average([
            [vowel_scores[:u].to_f, vowel_scores[:o].to_f * 0.72].max,
            closeness_hz(f2, 800.0, width: 70.0),
            closeness(low, 0.875, width: 0.070),
            ((0.065 - high) / 0.065).clamp(0.0, 1.0),
            ((0.014 - zcr) / 0.014).clamp(0.0, 1.0),
            ((0.70 - burst) / 0.70).clamp(0.0, 1.0)
          ], [0.18, 0.20, 0.18, 0.14, 0.14, 0.16])
          (0.66 + shape * 0.24).clamp(0.0, 0.94)
        end

        def quiet_mid_ru_hint_score(features, vowel_scores)
          f1 = features[:f1_frequency].to_f
          f2 = features[:f2_frequency].to_f
          low = features[:low_ratio].to_f
          high = features[:high_ratio].to_f
          zcr = features[:zero_crossing_rate].to_f
          flatness = features[:spectral_flatness].to_f
          burst = features[:burst_strength].to_f
          return 0.0 unless f1.positive? && f1 < 230.0
          return 0.0 unless f2.between?(1_280.0, 1_390.0)
          return 0.0 unless low.between?(0.86, 0.91)
          return 0.0 unless high.between?(0.035, 0.060)
          return 0.0 unless zcr.between?(0.009, 0.0135)
          return 0.0 unless flatness.between?(0.030, 0.052)
          return 0.0 unless burst <= 0.13

          shape = weighted_average([
            [vowel_scores[:u].to_f, vowel_scores[:o].to_f * 0.78].max,
            closeness_hz(f2, 1_345.0, width: 90.0),
            closeness(low, 0.875, width: 0.055),
            closeness(high, 0.049, width: 0.022),
            closeness(zcr, 0.011, width: 0.0045),
            closeness(flatness, 0.040, width: 0.018)
          ], [0.16, 0.18, 0.18, 0.16, 0.16, 0.16])
          (0.66 + shape * 0.24).clamp(0.0, 0.94)
        end

        def kana_table_for(consonant)
          return KANA_TABLE[consonant] if KANA_TABLE.key?(consonant)
          return DAKUTEN_TABLE[consonant] if dakuten_candidate?(consonant)

          fallback = DAKUTEN_FALLBACK[consonant]
          KANA_TABLE[fallback] if fallback
        end

        def dakuten_candidate?(consonant)
          return false if consonant == :p && !@options[:handakuten]
          return false if consonant != :p && !@options[:dakuten]

          DAKUTEN_TABLE.key?(consonant)
        end

        def syllabic_n_candidate(features, vowel_scores)
          nasal = features[:nasal_score].to_f
          stability = features[:nasal_stability].to_f
          nasal_shape = syllabic_n_shape_score(features)
          _vowel, vowel_confidence = best_score(vowel_scores)
          duration = features[:voice_duration_ms].to_f
          duration_score = [duration / 240.0, 1.0].min
          uncertainty = (1.0 - vowel_confidence).clamp(0.0, 1.0)
          high_quiet = (1.0 - features[:high_ratio].to_f).clamp(0.0, 1.0)
          low_zcr = (1.0 - features[:zero_crossing_rate].to_f * 8.0).clamp(0.0, 1.0)
          f2 = features[:f2_frequency].to_f
          if f2.positive?
            return nil if f2 < 1_180.0
            return nil if low_back_vowel_like_n_false_positive?(features)
            return nil if features[:zero_crossing_rate].to_f > 0.013
            return nil if features[:high_ratio].to_f > 0.125
          end
          return nil unless nasal_shape > 0.40 && high_quiet > 0.78 && low_zcr > 0.78 && duration > 110.0

          confidence = (
            nasal_shape * 0.46 +
            high_quiet * 0.18 +
            low_zcr * 0.14 +
            stability * 0.12 +
            duration_score * 0.06 +
            uncertainty * 0.04
          ).clamp(0.0, 1.0)
          return nil unless confidence >= 0.58

          {
            text: "ん",
            hiragana: "ん",
            roman: "n",
            consonant: "n",
            vowel: nil,
            vowel_index: nil,
            confidence: confidence,
            vowel_confidence: vowel_confidence,
            consonant_confidence: nasal,
            score: confidence
          }
        end

        def low_back_vowel_like_n_false_positive?(features)
          f2 = features[:f2_frequency].to_f
          return false unless f2.between?(1_180.0, 1_520.0)

          features[:zero_crossing_rate].to_f > 0.0085 && features[:high_ratio].to_f < 0.085
        end

        def syllabic_n_shape_score(features)
          f1 = features[:f1_frequency].to_f
          f2 = features[:f2_frequency].to_f
          return features[:nasal_score].to_f * 0.75 unless f1.positive? && f2.positive?

          low_f1 = closeness_hz(f1, 170.0, width: 105.0)
          mid_f2 = closeness_hz(f2, 1_450.0, width: 820.0)
          compact_nasal = Math.sqrt((low_f1 * mid_f2).clamp(0.0, 1.0))
          weighted_average([compact_nasal, low_f1, mid_f2], [0.52, 0.24, 0.24])
        end

        def candidate_hash(text:, consonant:, vowel:, confidence:, vowel_confidence:, consonant_confidence:)
          consonant_label = consonant&.to_s
          {
            text: text,
            hiragana: text,
            roman: romanize(consonant, vowel),
            consonant: consonant_label,
            vowel: vowel.to_s,
            vowel_index: VOWEL_INDEX[vowel],
            confidence: confidence.clamp(0.0, 1.0),
            vowel_confidence: vowel_confidence.clamp(0.0, 1.0),
            consonant_confidence: consonant_confidence.clamp(0.0, 1.0),
            score: confidence.clamp(0.0, 1.0)
          }
        end

        def kana_score(consonant, vowel_score, consonant_score, features)
          if consonant.nil?
            (vowel_score * 0.80 + consonant_score * 0.20).clamp(0.0, 1.0)
          else
            temporal = [features[:burst_strength].to_f, features[:attack_strength].to_f * 0.82].max
            effective_consonant = consonant_score * (0.35 + temporal * 0.65)
            (vowel_score * 0.68 + effective_consonant * 0.22 + temporal * 0.10).clamp(0.0, 1.0)
          end
        end

        def select_payload(candidates, debug:, timestamp_ms:)
          top = candidates.first
          return unknown_payload(confidence: 0.0, candidates: [], debug: debug) unless top

          track_top_candidate(top)
          stable_top = @same_top_candidate_count >= 2
          selected, stable = select_candidate(top, candidates, stable_top, timestamp_ms)
          return unknown_payload(confidence: top[:confidence], candidates: candidates, debug: debug) unless selected

          payload_for(selected, stable: stable, candidates: candidates, debug: debug, timestamp_ms: timestamp_ms)
        end

        def track_top_candidate(candidate)
          text = candidate[:text]
          @same_top_candidate_count = text == @last_candidate_text ? @same_top_candidate_count + 1 : 1
          @last_candidate_text = text
        end

        def select_candidate(top, candidates, stable_top, timestamp_ms)
          return [top, stable_top] if @options[:update] == :frame && acceptable?(top)
          return [nil, false] unless acceptable?(top)
          return switch_candidate(top, candidates, timestamp_ms, stable: true) if @options[:update] == :candidate

          if stable_top
            switch_candidate(top, candidates, timestamp_ms, stable: true)
          elsif @stable_candidate
            [@stable_candidate, true]
          else
            [nil, false]
          end
        end

        def switch_candidate(top, candidates, timestamp_ms, stable:)
          return [@stable_candidate, stable] if hold_active?(timestamp_ms)

          if @stable_candidate && @stable_candidate[:text] != top[:text]
            current = candidates.find { |candidate| candidate[:text] == @stable_candidate[:text] } || @stable_candidate
            return [@stable_candidate, stable] unless top[:score].to_f > current[:score].to_f + @options[:hysteresis]
          end

          if @stable_candidate.nil? || @stable_candidate[:text] != top[:text]
            @last_change_at_ms = timestamp_ms
          end
          @stable_candidate = top
          [@stable_candidate, stable]
        end

        def hold_active?(timestamp_ms)
          @stable_candidate && (timestamp_ms - @last_change_at_ms) < @options[:hold_ms]
        end

        def acceptable?(candidate)
          candidate[:confidence].to_f >= @options[:min_confidence]
        end

        def payload_for(candidate, stable:, candidates:, debug:, timestamp_ms:)
          {
            text: candidate[:text],
            hiragana: candidate[:hiragana],
            roman: candidate[:roman],
            consonant: candidate[:consonant],
            vowel: candidate[:vowel],
            vowel_index: candidate[:vowel_index],
            confidence: rounded(candidate[:confidence]),
            vowel_confidence: rounded(candidate[:vowel_confidence]),
            consonant_confidence: rounded(candidate[:consonant_confidence]),
            stable: stable,
            changed: false,
            silence: false,
            age_ms: age_ms(timestamp_ms),
            candidates: public_candidates(candidates)
          }.tap do |payload|
            payload[:debug] = debug if @options[:debug]
          end
        end

        def unknown_payload(confidence:, candidates:, debug:)
          {
            text: @options[:unknown_text],
            hiragana: nil,
            roman: nil,
            consonant: nil,
            vowel: nil,
            vowel_index: nil,
            confidence: rounded(confidence),
            vowel_confidence: 0.0,
            consonant_confidence: 0.0,
            stable: false,
            changed: false,
            silence: false,
            age_ms: 0,
            candidates: public_candidates(candidates)
          }.tap do |payload|
            payload[:debug] = debug if @options[:debug]
          end
        end

        def safe_unknown_result(error:)
          debug = @options[:debug] ? { error: "#{error.class}: #{error.message}" } : nil
          unknown_payload(confidence: 0.0, candidates: [], debug: debug)
        end

        def handle_silence(timestamp_ms, features)
          @silence_started_at_ms ||= timestamp_ms
          if (timestamp_ms - @silence_started_at_ms) >= @options[:silence_clear_ms]
            @stable_candidate = nil
            @same_top_candidate_count = 0
            @last_candidate_text = nil
            @last_change_at_ms = timestamp_ms
            @attack_features = nil
            @syllable_hint_memory = nil
            return finish_payload(silent_result(timestamp_ms: timestamp_ms))
          end

          if @stable_candidate
            return finish_payload(payload_for(@stable_candidate, stable: true, candidates: [@stable_candidate], debug: debug_payload(features, {}, {}), timestamp_ms: timestamp_ms))
          end

          finish_payload(silent_result(timestamp_ms: timestamp_ms))
        end

        def finish_payload(payload)
          return payload if payload[:silence]

          payload[:changed] = payload[:text] != @last_output_text
          @last_output_text = payload[:text]
          payload
        end

        def public_candidates(candidates)
          Array(candidates).map do |candidate|
            {
              text: candidate[:text],
              roman: candidate[:roman],
              confidence: rounded(candidate[:confidence])
            }
          end
        end

        def debug_payload(features, vowel_scores, consonant_scores)
          return nil unless @options[:debug]

          {
            rms: rounded(features[:amplitude]),
            zcr: rounded(features[:zero_crossing_rate]),
            spectral_centroid: rounded(features[:spectral_centroid], digits: 2),
            spectral_flatness: rounded(features[:spectral_flatness]),
            f1_frequency: rounded(features[:f1_frequency], digits: 2),
            f2_frequency: rounded(features[:f2_frequency], digits: 2),
            high_ratio: rounded(features[:high_ratio]),
            low_ratio: rounded(features[:low_ratio]),
            burst_strength: rounded(features[:burst_strength]),
            nasal_score: rounded(features[:nasal_score]),
            nasal_stability: rounded(features[:nasal_stability]),
            vowel_scores: stringify_score_hash(vowel_scores),
            consonant_scores: stringify_score_hash(consonant_scores),
            syllable_hint_scores: stringify_score_hash(syllable_hint_scores(features, vowel_scores).transform_values { |entry| entry[:score] })
          }
        end

        def silence?(features)
          gate = @options[:silence_gate] || 0.01
          peak_gate = [gate * 1.5, 0.02].max
          features[:amplitude].to_f < gate || features[:peak].to_f < peak_gate
        end

        def normalize_bands(value)
          values = symbolize_hash(value)
          {
            sub: unit_float(values[:sub], fallback: 0.0),
            low: unit_float(values[:low], fallback: 0.0),
            mid: unit_float(values[:mid], fallback: 0.0),
            high: unit_float(values[:high], fallback: 0.0)
          }
        end

        def spectral_ratios(magnitudes, bands)
          return ratios_from_bands(bands) if magnitudes.empty?

          total = magnitudes.sum
          return ratios_from_bands(bands) unless total.positive?

          {
            low_ratio: magnitude_ratio(magnitudes, 0.0, 500.0, total),
            low_mid_ratio: magnitude_ratio(magnitudes, 300.0, 1_200.0, total),
            mid_ratio: magnitude_ratio(magnitudes, 800.0, 2_800.0, total),
            high_ratio: magnitude_ratio(magnitudes, 2_800.0, nyquist, total)
          }
        end

        def formant_features(magnitudes)
          return zero_formants if magnitudes.empty?

          envelope = smooth_log_magnitudes(magnitudes)
          f1 = formant_peak(envelope, 200.0, 1_000.0)
          f2 = formant_peak(envelope, 800.0, 3_200.0)
          {
            f1_frequency: f1,
            f2_frequency: f2,
            f1_norm: normalized_frequency(f1),
            f2_norm: normalized_frequency(f2)
          }
        end

        def zero_formants
          {
            f1_frequency: 0.0,
            f2_frequency: 0.0,
            f1_norm: 0.0,
            f2_norm: 0.0
          }
        end

        def smooth_log_magnitudes(magnitudes)
          values = magnitudes.map { |magnitude| Math.log1p(magnitude.to_f.abs) }
          radius = FORMANT_SMOOTH_RADIUS
          Array.new(values.length) do |index|
            first = [index - radius, 0].max
            last = [index + radius, values.length - 1].min
            values[first..last].sum / (last - first + 1).to_f
          end
        end

        def formant_peak(envelope, low_hz, high_hz)
          return 0.0 if envelope.empty?

          first = frequency_bin(low_hz, envelope.length)
          last = frequency_bin(high_hz, envelope.length)
          return 0.0 if first > last

          index = (first..last).max_by { |entry| envelope[entry].to_f }
          bin_frequency(index, envelope.length)
        end

        def ratios_from_bands(bands)
          total = bands.values.sum
          return { low_ratio: 0.0, low_mid_ratio: 0.0, mid_ratio: 0.0, high_ratio: 0.0 } unless total.positive?

          {
            low_ratio: ((bands[:sub] + bands[:low]) / total).clamp(0.0, 1.0),
            low_mid_ratio: ((bands[:low] + bands[:mid] * 0.5) / total).clamp(0.0, 1.0),
            mid_ratio: (bands[:mid] / total).clamp(0.0, 1.0),
            high_ratio: (bands[:high] / total).clamp(0.0, 1.0)
          }
        end

        def magnitude_ratio(magnitudes, low_hz, high_hz, total)
          first = frequency_bin(low_hz, magnitudes.length)
          last = frequency_bin(high_hz, magnitudes.length)
          return 0.0 if first > last

          magnitudes[first..last].sum.fdiv(total).clamp(0.0, 1.0)
        end

        def frequency_bin(frequency, length)
          return 0 if length <= 1

          (frequency.to_f / nyquist * (length - 1)).round.clamp(0, length - 1)
        end

        def bin_frequency(index, length)
          return 0.0 if length <= 1

          index.to_f / (length - 1).to_f * nyquist
        end

        def low_mid_ratio(features)
          features[:low_mid_ratio].to_f.clamp(0.0, 1.0)
        end

        def window_entries(now, window_ms)
          cutoff = now - window_ms.to_f
          @feature_buffer.select { |entry| entry[:timestamp_ms].to_f >= cutoff }
        end

        def weighted_feature_average(entries, key, fallback:)
          total_weight = entries.sum { |entry| feature_weight(entry) }
          return fallback unless total_weight.positive?

          entries.sum { |entry| weighted_feature_value(entry, key) * feature_weight(entry) }.fdiv(total_weight)
        end

        def weighted_band_average(entries, key, fallback:)
          values = normalize_bands(fallback)
          FEATURE_BAND_KEYS.each do |band|
            values[band] = weighted_feature_average(
              entries,
              :"#{key}.#{band}",
              fallback: values[band]
            )
          end
          values
        end

        def weighted_feature_value(entry, key)
          key_name = key.to_s
          return entry.dig(:bands, key_name.split(".", 2).last.to_sym).to_f if key_name.start_with?("bands.")
          return entry.dig(:onsets, key_name.split(".", 2).last.to_sym).to_f if key_name.start_with?("onsets.")

          entry[key].to_f
        end

        def feature_weight(entry)
          (entry[:amplitude].to_f + 0.05).clamp(0.05, 1.05)
        end

        def nasal_stability_score(now)
          entries = window_entries(now, [@options[:window_ms], 240].min).reject { |entry| silence?(entry) }
          return 0.0 if entries.length < 2

          scores = entries.map { |entry| nasal_score(entry) }
          mean = scores.sum / scores.length.to_f
          variance = scores.sum { |score| (score - mean)**2 } / scores.length.to_f
          consistency = (1.0 - Math.sqrt(variance) / 0.35).clamp(0.0, 1.0)
          low_noise = (1.0 - entries.sum { |entry| entry[:spectral_flux].to_f } / entries.length.to_f).clamp(0.0, 1.0)
          (mean * 0.62 + consistency * 0.26 + low_noise * 0.12).clamp(0.0, 1.0)
        end

        def nasal_score(features)
          low = features[:low_ratio].to_f
          low_mid = features[:low_mid_ratio].to_f
          high = features[:high_ratio].to_f
          zcr = features[:zero_crossing_rate].to_f
          flatness = features[:spectral_flatness].to_f
          (low * 0.28 + low_mid * 0.32 + (1.0 - high) * 0.18 + (1.0 - zcr) * 0.14 + (1.0 - flatness) * 0.08).clamp(0.0, 1.0)
        end

        def normalize_score_hash(scores)
          scores.transform_values { |value| value.to_f.clamp(0.0, 1.0) }
        end

        def best_score(scores)
          key, value = scores.max_by { |_candidate, score| score.to_f }
          [key, value.to_f.clamp(0.0, 1.0)]
        end

        def weighted_average(values, weights)
          total_weight = weights.sum.to_f
          return 0.0 unless total_weight.positive?

          values.zip(weights).sum { |value, weight| value.to_f.clamp(0.0, 1.0) * weight.to_f } / total_weight
        end

        def closeness(value, target, width:)
          (1.0 - ((value.to_f - target.to_f).abs / width.to_f)).clamp(0.0, 1.0)
        end

        def closeness_hz(value, target, width:)
          return 0.5 unless value.to_f.positive?

          closeness(value, target, width: width)
        end

        def normalized_frequency(value)
          return 0.0 unless nyquist.positive?

          (value.to_f / nyquist).clamp(0.0, 1.0)
        end

        def romanize(consonant, vowel)
          ROMAN_OVERRIDES.fetch([consonant, vowel]) do
            "#{consonant}#{vowel}"
          end
        end

        def age_ms(timestamp_ms)
          [(timestamp_ms - @last_change_at_ms).round, 0].max
        end

        def rounded(value, digits: 4)
          value.to_f.round(digits)
        end

        def stringify_score_hash(scores)
          scores.each_with_object({}) do |(key, value), output|
            output[key.nil? ? "none" : key.to_s] = rounded(value)
          end
        end

        def rms(samples)
          values = numeric_array(samples)
          return 0.0 if values.empty?

          Math.sqrt(values.sum { |sample| sample * sample } / values.length.to_f).clamp(0.0, 1.0)
        end

        def peak_level(samples)
          numeric_array(samples).map(&:abs).max.to_f.clamp(0.0, 1.0)
        end

        def zero_crossing_rate(samples)
          values = numeric_array(samples)
          return 0.0 if values.length < 2

          crossings = values.each_cons(2).count do |previous, current|
            (previous.negative? && current >= 0.0) || (previous.positive? && current <= 0.0)
          end
          (crossings / (values.length - 1).to_f).clamp(0.0, 1.0)
        end

        def nyquist
          @sample_rate / 2.0
        end

        def numeric_array(values)
          Array(values).filter_map do |value|
            numeric = Float(value)
            numeric if numeric.finite?
          rescue ArgumentError, TypeError
            nil
          end
        end

        def fft_hash(value)
          return value if value.is_a?(Hash)

          { magnitudes: value }
        end

        def symbolize_hash(value)
          Hash(value).each_with_object({}) do |(key, entry), output|
            output[key.to_sym] = entry
          end
        rescue StandardError
          {}
        end

        def finite_float(value, fallback:)
          numeric = Float(value)
          numeric.finite? ? numeric : fallback
        rescue ArgumentError, TypeError
          fallback
        end

        def non_negative_float(value, fallback:)
          numeric = finite_float(value, fallback: fallback)
          numeric.negative? ? fallback : numeric
        end

        def unit_float(value, fallback:)
          finite_float(value, fallback: fallback).clamp(0.0, 1.0)
        end

        def optional_unit_float(value)
          return nil if value.nil?

          unit_float(value, fallback: DEFAULT_OPTIONS[:silence_gate] || 0.01)
        end

        def positive_integer(value, fallback:)
          numeric = Integer(value)
          numeric.positive? ? numeric : fallback
        rescue ArgumentError, TypeError
          fallback
        end

        def non_negative_integer(value, fallback:)
          numeric = Integer(value)
          numeric.negative? ? fallback : numeric
        rescue ArgumentError, TypeError
          fallback
        end
      end
    end
  end
end
