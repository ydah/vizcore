# frozen_string_literal: true

module Vizcore
  # Small recursive copier for plain payload hashes/arrays passed between DSL, server, and renderer.
  module DeepCopy
    module_function

    # @param value [Object]
    # @return [Object]
    def copy(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, entry), output| output[key] = copy(entry) }
      when Array
        value.map { |entry| copy(entry) }
      else
        value
      end
    end
  end
end
