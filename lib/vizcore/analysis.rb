# frozen_string_literal: true

module Vizcore
  # Analysis components used to transform raw audio into visual parameters.
  module Analysis
  end
end

require_relative "analysis/band_splitter"
require_relative "analysis/beat_detector"
require_relative "analysis/bpm_estimator"
require_relative "analysis/fft_processor"
require_relative "analysis/pipeline"
require_relative "analysis/smoother"
