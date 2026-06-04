# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"
require "set"
require "time"
require_relative "input_manager"

module Vizcore
  module Audio
    # Records labeled voice samples for tuning the experimental kana guesser.
    class KanaSampleRecorder
      VERSION = "vizcore.kana_samples.v1"
      DEFAULT_LABELS = %w[あ い う え お ん].freeze
      DEFAULT_TAKES = 3
      DEFAULT_DURATION = 1.2
      DEFAULT_OUTPUT_DIR = "kana_samples"
      DEFAULT_LEAD_IN = 0.25
      DEFAULT_MIN_RMS = 0.001
      CLIP_WARNING_RATIO = 0.01

      Result = Struct.new(:output_dir, :manifest_path, :samples, :total_samples, keyword_init: true)

      def initialize(
        labels: DEFAULT_LABELS,
        takes: DEFAULT_TAKES,
        duration: DEFAULT_DURATION,
        output_dir: DEFAULT_OUTPUT_DIR,
        source: :mic,
        file_path: nil,
        audio_device: nil,
        sample_rate: InputManager::DEFAULT_SAMPLE_RATE,
        lead_in: DEFAULT_LEAD_IN,
        min_rms: DEFAULT_MIN_RMS,
        allow_silent: false,
        input_manager_factory: nil,
        sleeper: ->(seconds) { sleep(seconds) },
        clock: -> { Time.now },
        before_sample: nil,
        after_sample: nil
      )
        @labels = normalize_labels(labels)
        @takes = positive_integer(takes, "takes")
        @duration = positive_float(duration, "duration")
        @output_dir = Pathname.new(output_dir.to_s).expand_path
        @source = normalize_source(source)
        @file_path = file_path
        @audio_device = audio_device
        @sample_rate = positive_integer(sample_rate, "sample_rate")
        @lead_in = non_negative_float(lead_in, "lead_in")
        @min_rms = non_negative_float(min_rms, "min_rms")
        @allow_silent = !!allow_silent
        @input_manager_factory = input_manager_factory || method(:build_input_manager)
        @sleeper = sleeper
        @clock = clock
        @before_sample = before_sample
        @after_sample = after_sample
      end

      # @return [Result] collection metadata for the newly recorded samples
      def call
        manager = nil
        FileUtils.mkdir_p(audio_dir)

        manifest = load_manifest
        samples = Array(manifest["samples"]).map { |entry| normalize_existing_sample(entry) }
        new_samples = []
        used_ids, used_paths = sample_reference_sets(samples)
        next_number = next_sample_number(samples)

        manager = @input_manager_factory.call(
          source: @source,
          file_path: @file_path,
          audio_device: @audio_device,
          sample_rate: @sample_rate
        )
        manager.start
        @labels.each do |label|
          @takes.times do |take_index|
            sample_id = next_available_sample_id(next_number, used_ids: used_ids, used_paths: used_paths)
            sample = record_sample(manager, id: sample_id, label: label, take: take_index + 1)
            samples << sample
            new_samples << sample
            used_ids << sample.fetch("id")
            used_paths << sample.fetch("path")
            next_number = sample_number(sample_id).to_i + 1
          end
        end

        write_manifest(manifest, manager: manager, samples: samples)
        Result.new(output_dir: @output_dir, manifest_path: manifest_path, samples: new_samples, total_samples: samples.length)
      ensure
        manager&.stop
      end

      private

      def build_input_manager(source:, file_path:, audio_device:, sample_rate:)
        InputManager.new(source: source, file_path: file_path, audio_device: audio_device, sample_rate: sample_rate)
      end

      def record_sample(manager, id:, label:, take:)
        path = sample_path(id)
        ensure_sample_file_available!(path)
        notify_before_sample(id: id, label: label, take: take)
        @sleeper.call(@lead_in) if @lead_in.positive?

        samples = capture_samples(manager)
        sample = sample_payload(
          id: id,
          label: label,
          take: take,
          path: relative_sample_path(id),
          samples: samples,
          sample_rate: manager.sample_rate
        )
        validate_sample_signal!(sample)
        write_wav(path, samples, sample_rate: manager.sample_rate)

        @after_sample&.call(sample)
        sample
      end

      def notify_before_sample(id:, label:, take:)
        @before_sample&.call(
          id: id,
          label: label,
          take: take,
          total_takes: @takes,
          duration: @duration
        )
      end

      def capture_samples(manager)
        target_count = [(@duration * manager.sample_rate).round, 1].max
        samples = []
        while samples.length < target_count
          count = [manager.frame_size, target_count - samples.length].min
          samples.concat(manager.capture_frame(count))
          sleep_for_realtime_capture(count, sample_rate: manager.sample_rate)
        end
        samples.first(target_count).map { |sample| numeric_sample(sample) }
      end

      def sleep_for_realtime_capture(count, sample_rate:)
        return unless @source == :mic

        @sleeper.call(count.to_f / sample_rate.to_f)
      end

      def write_wav(path, samples, sample_rate:)
        require "wavefile"

        FileUtils.mkdir_p(path.dirname)
        format = WaveFile::Format.new(:mono, :float, sample_rate)
        buffer = WaveFile::Buffer.new(samples, format)
        WaveFile::Writer.new(path.to_s, format) { |writer| writer.write(buffer) }
      rescue LoadError => e
        raise ArgumentError, "wavefile gem is required to write WAV samples: #{e.message}"
      end

      def sample_payload(id:, label:, take:, path:, samples:, sample_rate:)
        rms_value = rms(samples)
        peak_value = peak(samples)
        clip_ratio_value = clip_ratio(samples)
        payload = {
          "id" => id,
          "label" => label,
          "take" => take,
          "path" => path,
          "duration" => round_metric(samples.length.to_f / sample_rate.to_f),
          "sample_rate" => sample_rate,
          "sample_count" => samples.length,
          "rms" => round_metric(rms_value),
          "peak" => round_metric(peak_value),
          "clip_ratio" => round_metric(clip_ratio_value)
        }
        warnings = sample_warnings(rms: rms_value, peak: peak_value, clip_ratio: clip_ratio_value)
        payload["warnings"] = warnings unless warnings.empty?
        payload
      end

      def load_manifest
        return default_manifest unless manifest_path.file?

        payload = JSON.parse(manifest_path.read)
        if payload.is_a?(Hash) && payload.fetch("version", nil) == VERSION && payload.fetch("samples", nil).is_a?(Array)
          validate_manifest_samples!(payload.fetch("samples"))
          return payload
        end

        raise ArgumentError, "Unsupported kana sample manifest: #{manifest_path}"
      rescue JSON::ParserError => e
        raise ArgumentError, "Invalid kana sample manifest #{manifest_path}: #{e.message}"
      end

      def default_manifest
        {
          "version" => VERSION,
          "metadata" => {
            "created_at" => timestamp,
            "labels" => @labels,
            "wav_format" => "float32"
          },
          "samples" => []
        }
      end

      def write_manifest(existing_manifest, manager:, samples:)
        metadata = existing_manifest.fetch("metadata", {}).merge(
          "updated_at" => timestamp,
          "labels" => @labels,
          "source" => @source.to_s,
          "sample_rate" => manager.sample_rate,
          "duration" => @duration,
          "takes" => @takes,
          "min_rms" => @min_rms,
          "allow_silent" => @allow_silent,
          "audio_device" => @audio_device,
          "audio_file" => @file_path
        )
        payload = {
          "version" => VERSION,
          "metadata" => metadata,
          "samples" => samples
        }
        manifest_path.write("#{JSON.pretty_generate(payload)}\n")
      end

      def normalize_existing_sample(entry)
        return entry if entry.is_a?(Hash)

        raise ArgumentError, "Unsupported kana sample entry in #{manifest_path}"
      end

      def validate_manifest_samples!(samples)
        duplicate_ids = duplicate_values(samples.filter_map { |entry| manifest_field(entry, "id") })
        duplicate_paths = duplicate_values(samples.filter_map { |entry| manifest_field(entry, "path") })
        return if duplicate_ids.empty? && duplicate_paths.empty?

        details = [
          duplicate_detail("duplicate sample ids", duplicate_ids),
          duplicate_detail("duplicate sample paths", duplicate_paths)
        ].compact.join("; ")
        raise ArgumentError,
              "Kana sample manifest has #{details}: #{manifest_path}. " \
              "Use a fresh --out directory or repair the manifest before collecting more samples."
      end

      def next_sample_number(samples)
        sample_numbers = samples.filter_map { |entry| sample_number(entry["id"]) }
        file_numbers = Dir[audio_dir.join("sample_*.wav").to_s].filter_map do |path|
          sample_number(File.basename(path, ".wav"))
        end
        [sample_numbers, file_numbers, [0]].flatten.max + 1
      end

      def next_available_sample_id(start_number, used_ids:, used_paths:)
        number = start_number
        loop do
          id = format("sample_%04d", number)
          return id if sample_slot_available?(id, used_ids: used_ids, used_paths: used_paths)

          number += 1
        end
      end

      def sample_slot_available?(id, used_ids:, used_paths:)
        !used_ids.include?(id) &&
          !used_paths.include?(relative_sample_path(id)) &&
          !sample_path(id).exist?
      end

      def sample_reference_sets(samples)
        [
          samples.filter_map { |entry| manifest_field(entry, "id") }.to_set,
          samples.filter_map { |entry| manifest_field(entry, "path") }.to_set
        ]
      end

      def ensure_sample_file_available!(path)
        return unless path.exist?

        raise ArgumentError, "Kana sample audio already exists and will not be overwritten: #{path}"
      end

      def manifest_field(entry, field)
        return nil unless entry.is_a?(Hash)

        value = entry[field]
        value = value.to_s.strip unless value.nil?
        value.to_s.empty? ? nil : value.to_s
      end

      def duplicate_values(values)
        values.group_by(&:itself).filter_map { |value, entries| value if entries.length > 1 }
      end

      def duplicate_detail(label, values)
        return nil if values.empty?

        shown = values.first(6).join(", ")
        suffix = values.length > 6 ? ", ..." : ""
        "#{label}: #{shown}#{suffix}"
      end

      def sample_number(id)
        match = id.to_s.match(/\Asample_(\d+)\z/)
        match && Integer(match[1])
      rescue ArgumentError
        nil
      end

      def audio_dir
        @output_dir.join("audio")
      end

      def manifest_path
        @output_dir.join("manifest.json")
      end

      def sample_path(id)
        @output_dir.join(relative_sample_path(id))
      end

      def relative_sample_path(id)
        File.join("audio", "#{id}.wav")
      end

      def timestamp
        @clock.call.utc.iso8601
      end

      def rms(samples)
        return 0.0 if samples.empty?

        Math.sqrt(samples.sum { |sample| sample * sample } / samples.length.to_f)
      end

      def peak(samples)
        samples.map(&:abs).max.to_f
      end

      def clip_ratio(samples)
        return 0.0 if samples.empty?

        threshold = peak(samples) <= 1.5 ? 0.98 : 32_000.0
        samples.count { |sample| sample.abs >= threshold } / samples.length.to_f
      end

      def sample_warnings(rms:, peak:, clip_ratio:)
        warnings = []
        warnings << "near_silence" if rms <= @min_rms || peak <= 0.0
        warnings << "clipped" if clip_ratio >= CLIP_WARNING_RATIO
        warnings
      end

      def validate_sample_signal!(sample)
        return if @allow_silent
        return unless Array(sample["warnings"]).include?("near_silence")

        raise ArgumentError,
              "Kana sample input is near silence for label=#{sample.fetch('label')} take=#{sample.fetch('take')} " \
              "(rms=#{sample.fetch('rms')}, peak=#{sample.fetch('peak')}). " \
              "Check microphone permission/input level, or pass --audio-device and --sample-rate from `vizcore devices audio`. " \
              "Use --allow-silent only when intentionally collecting silence."
      end

      def round_metric(value)
        value.to_f.finite? ? value.to_f.round(6) : 0.0
      end

      def numeric_sample(value)
        sample = Float(value)
        sample.finite? ? sample : 0.0
      rescue ArgumentError, TypeError
        0.0
      end

      def normalize_labels(value)
        labels = Array(value).flat_map { |entry| entry.to_s.split(",") }
                             .map(&:strip)
                             .reject(&:empty?)
        raise ArgumentError, "labels must include at least one kana label" if labels.empty?

        labels
      end

      def normalize_source(value)
        source = value.to_s.strip
        source = "mic" if source.empty?
        return source.to_sym if %w[mic file dummy].include?(source)

        raise ArgumentError, "unsupported audio source: #{value}"
      end

      def positive_integer(value, label)
        integer = Integer(value)
        raise ArgumentError, "#{label} must be positive" unless integer.positive?

        integer
      rescue ArgumentError, TypeError
        raise ArgumentError, "#{label} must be positive"
      end

      def positive_float(value, label)
        numeric = Float(value)
        raise ArgumentError, "#{label} must be positive" unless numeric.positive?

        numeric
      rescue ArgumentError, TypeError
        raise ArgumentError, "#{label} must be positive"
      end

      def non_negative_float(value, label)
        numeric = Float(value)
        raise ArgumentError, "#{label} must be non-negative" if numeric.negative?

        numeric
      rescue ArgumentError, TypeError
        raise ArgumentError, "#{label} must be non-negative"
      end
    end
  end
end
