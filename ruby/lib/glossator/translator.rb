module Glossator
  class Translator
    attr_reader :target_version, :latest_version

    def initialize(target_version)
      @target_version = semver(target_version)
      if version_not_supported?
        raise Glossator::Errors::UnsupportedVersionError, "Version #{@target_version} is not supported"
      end
    end

    def translate(mode, data)
      raise ArgumentError, "data must be Hash" unless data.is_a?(Hash)

      mutated_data = data.deep_dup

      case mode
      when :request_up then request_up(mutated_data)
      when :response_down then response_down(mutated_data)
      else raise ArgumentError, "Unknown translation mode #{mode.inspect}"
      end

      assert_jsonish_symbol_keys!(mutated_data, data)
      mutated_data
    end

    protected

    def request_up(data)
      # Do nothing by default
    end

    def response_down(data)
      # Do nothing by default
    end

    def version_not_supported?
      false # Assume all versions are supported by default
    end

    def version_below?(v)
      target_version < semver(v)
    end

    private

    def semver(value)
      return value if value.is_a?(Semantic::Version)
      Semantic::Version.new(value)
    end

    def assert_jsonish_symbol_keys!(new_data, old_data, path = [])
      new_data.each do |key, value|
        unless old_data.is_a?(Hash) && old_data.key?(key)
          assert_jsonish_symbol_key!(key, path)
        end

        if value.is_a?(Hash)
          assert_jsonish_symbol_keys!(value, old_data[key], path + [key])
        end
      end
    end

    def assert_jsonish_symbol_key!(key, path)
      unless key.is_a?(Symbol)
        raise Glossator::Errors::BadKeyConversionError, "Non-symbol key #{key.inspect} (in: #{path.inspect})"
      end

      if /[-_]/ =~ key.to_s
        raise Glossator::Errors::BadKeyConversionError, "Non-camelCase key #{key.inspect} (in: #{path.inspect})"
      end
    end
  end
end
