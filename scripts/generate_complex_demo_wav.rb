# frozen_string_literal: true

SAMPLE_RATE = 22_050
DURATION_SECONDS = 16.0
BPM = 120.0
OUTPUT_PATH = File.expand_path("../examples/assets/complex_demo_loop.wav", __dir__)

class ComplexDemoWavGenerator
  def initialize(sample_rate:, duration_seconds:, bpm:, random_seed: 42)
    @sample_rate = Integer(sample_rate)
    @duration_seconds = Float(duration_seconds)
    @bpm = Float(bpm)
    @rng = Random.new(random_seed)
    @samples = Array.new((@sample_rate * @duration_seconds).to_i, 0.0)
  end

  def generate
    build_arrangement
    normalize!(target_peak: 0.9)
    @samples
  end

  private

  def build_arrangement
    beat = 60.0 / @bpm
    bar = beat * 4.0

    add_pad_chords(bar: bar)
    add_bassline(step: beat / 2.0)
    add_drums(beat: beat, bar: bar)
    add_arp(step: beat / 4.0, bar: bar)
    add_risers(bar: bar)
  end

  def add_pad_chords(bar:)
    chords = [
      [55.0, 65.41, 82.41],
      [49.0, 61.74, 73.42],
      [65.41, 77.78, 98.0],
      [43.65, 55.0, 65.41]
    ]

    4.times do |bar_index|
      start_time = bar_index * bar
      chord = chords[bar_index % chords.length]
      2.times do |repeat_index|
        chord_start = start_time + repeat_index * (bar / 2.0)
        chord.each_with_index do |freq, tone_index|
          add_tone(
            chord_start,
            bar / 2.0,
            amplitude: 0.07 - tone_index * 0.008,
            wave: :sine
          ) do |time_in_note, progress|
            detune = (tone_index - 1) * 0.15
            tremolo = 0.85 + 0.15 * Math.sin(time_in_note * 2.2 + tone_index)
            [freq + detune, tremolo * (1.0 - progress * 0.05)]
          end
        end
      end
    end
  end

  def add_bassline(step:)
    pattern = [55.0, 55.0, 65.41, 55.0, 82.41, 73.42, 65.41, 61.74]

    steps = (@duration_seconds / step).to_i
    steps.times do |index|
      time = index * step
      section = (time / 4.0).floor
      note = pattern[index % pattern.length]
      note *= 0.5 if section == 1 && index.odd?
      note *= 2.0 if section >= 2 && (index % 8).zero?

      add_tone(time, step * 0.92, amplitude: 0.18, wave: :saw) do |time_in_note, progress|
        wobble = 1.0 + 0.008 * Math.sin(time_in_note * 5.5)
        env = 1.0 - progress * 0.55
        [note * wobble, env]
      end

      add_tone(time, step * 0.92, amplitude: 0.08, wave: :sine) do |_time_in_note, progress|
        [note, 1.0 - progress * 0.7]
      end
    end
  end

  def add_drums(beat:, bar:)
    beats = (@duration_seconds / beat).to_i
    beats.times do |beat_index|
      time = beat_index * beat
      bar_index = (time / bar).floor
      beat_in_bar = beat_index % 4

      kick_amp = bar_index.zero? ? 0.45 : 0.7
      add_kick(time, amplitude: kick_amp)
      add_kick(time + beat * 0.75, amplitude: 0.22) if bar_index >= 2 && beat_in_bar == 3

      next unless beat_in_bar == 1 || beat_in_bar == 3

      add_snare(time, amplitude: bar_index >= 2 ? 0.55 : 0.45)
    end

    hats_step = beat / 2.0
    hats = (@duration_seconds / hats_step).to_i
    hats.times do |index|
      time = index * hats_step
      open_hat = (index % 4) == 3
      add_hat(time, amplitude: open_hat ? 0.18 : 0.11, duration: open_hat ? 0.08 : 0.03)
    end
  end

  def add_arp(step:, bar:)
    notes = [220.0, 261.63, 329.63, 392.0, 523.25, 392.0, 329.63, 261.63]
    steps = (@duration_seconds / step).to_i
    steps.times do |index|
      time = index * step
      next if time < bar # leave first bar cleaner

      section = (time / bar).floor
      note = notes[(index + section) % notes.length]
      note *= 0.5 if section == 2 && (index % 8) >= 4

      add_tone(time, step * 0.75, amplitude: 0.07 + section * 0.015, wave: :triangle) do |time_in_note, progress|
        vibrato = 1.0 + 0.01 * Math.sin(time_in_note * 14.0)
        gate = progress < 0.6 ? 1.0 : (1.0 - (progress - 0.6) / 0.4)
        [note * vibrato, gate]
      end
    end
  end

  def add_risers(bar:)
    [bar * 1.5, bar * 3.5].each do |start_time|
      add_tone(start_time, 0.9, amplitude: 0.12, wave: :sine) do |time_in_note, progress|
        freq = 280.0 + 880.0 * progress
        shimmer = 0.7 + 0.3 * Math.sin(time_in_note * 40.0)
        [freq, shimmer * progress]
      end
    end
  end

  def add_kick(start_time, amplitude:)
    add_event(start_time, 0.2) do |time_in_note, progress|
      pitch = 130.0 - 95.0 * progress
      env = Math.exp(-7.0 * progress)
      body = Math.sin(2.0 * Math::PI * pitch * time_in_note) * env
      click = Math.sin(2.0 * Math::PI * 1800.0 * time_in_note) * Math.exp(-70.0 * progress)
      (body * 0.95 + click * 0.12) * amplitude
    end
  end

  def add_snare(start_time, amplitude:)
    add_event(start_time, 0.18) do |time_in_note, progress|
      noise = ((@rng.rand * 2.0) - 1.0) * (Math.sin(time_in_note * 8_000.0).positive? ? 1.0 : -1.0)
      tone = Math.sin(2.0 * Math::PI * 190.0 * time_in_note)
      env = Math.exp(-18.0 * progress)
      (noise * 0.6 + tone * 0.35) * env * amplitude
    end
  end

  def add_hat(start_time, amplitude:, duration:)
    add_event(start_time, duration) do |time_in_note, progress|
      noise = (@rng.rand * 2.0) - 1.0
      metallic = Math.sin(2.0 * Math::PI * 7000.0 * time_in_note) + Math.sin(2.0 * Math::PI * 9200.0 * time_in_note)
      env = Math.exp(-28.0 * progress)
      ((noise * 0.35) + (metallic * 0.25)) * env * amplitude
    end
  end

  def add_tone(start_time, duration, amplitude:, wave:)
    add_event(start_time, duration) do |time_in_note, progress|
      frequency, extra_env = yield(time_in_note, progress)
      env = adsr_like(progress)
      oscillator(wave, frequency, time_in_note) * amplitude * env * extra_env.to_f
    end
  end

  def add_event(start_time, duration)
    return if duration <= 0.0

    start_index = (start_time * @sample_rate).floor
    end_index = [((start_time + duration) * @sample_rate).ceil, @samples.length].min
    return if end_index <= 0 || start_index >= @samples.length

    start_index = 0 if start_index.negative?
    (start_index...end_index).each do |index|
      time_in_note = (index - start_index) / @sample_rate.to_f
      progress = time_in_note / duration.to_f
      @samples[index] += yield(time_in_note, progress)
    end
  end

  def oscillator(type, frequency, time_in_note)
    phase = 2.0 * Math::PI * frequency.to_f * time_in_note
    case type
    when :sine
      Math.sin(phase)
    when :triangle
      (2.0 / Math::PI) * Math.asin(Math.sin(phase))
    when :saw
      frac = ((frequency.to_f * time_in_note) % 1.0)
      (2.0 * frac) - 1.0
    else
      0.0
    end
  end

  def adsr_like(progress)
    if progress < 0.03
      progress / 0.03
    elsif progress > 0.9
      [0.0, 1.0 - (progress - 0.9) / 0.1].max
    else
      1.0
    end
  end

  def normalize!(target_peak:)
    peak = @samples.map(&:abs).max.to_f
    return if peak <= 0.0

    gain = target_peak / peak
    @samples.map! { |sample| sample * gain }
  end
end

def write_wav_mono_16(path, samples, sample_rate)
  pcm = samples.map do |sample|
    value = [[sample.to_f, -1.0].max, 1.0].min
    (value * 32_767.0).round
  end.pack("s<*")

  channels = 1
  bits_per_sample = 16
  byte_rate = sample_rate * channels * (bits_per_sample / 8)
  block_align = channels * (bits_per_sample / 8)
  data_size = pcm.bytesize
  riff_size = 36 + data_size

  FileUtils.mkdir_p(File.dirname(path))
  File.binwrite(
    path,
    +"RIFF" +
      [riff_size].pack("V") +
      "WAVE" +
      "fmt " +
      [16, 1, channels, sample_rate, byte_rate, block_align, bits_per_sample].pack("VvvVVvv") +
      "data" +
      [data_size].pack("V") +
      pcm
  )
end

require "fileutils"

generator = ComplexDemoWavGenerator.new(
  sample_rate: SAMPLE_RATE,
  duration_seconds: DURATION_SECONDS,
  bpm: BPM
)
samples = generator.generate
write_wav_mono_16(OUTPUT_PATH, samples, SAMPLE_RATE)

warn "Generated #{OUTPUT_PATH}"
