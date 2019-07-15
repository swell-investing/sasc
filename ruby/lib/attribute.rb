module SASC
  class Attribute < Field
    VALID_JSON_TYPES = %i(string integer float boolean object array).freeze
    attr_reader :deep_camelize_keys, :json_type

    # rubocop:disable Metrics/ParameterLists
    def initialize(ruby_name, json_type, assign: nil, transient_assign: nil, deep_camelize_keys: false, **kwargs)
      super(ruby_name, **kwargs)

      @deep_camelize_keys = deep_camelize_keys
      @json_type = json_type.to_sym
      assert_json_type_valid! @json_type

      define_singleton_method :assign_in_resource, build_assign_impl(assign, transient_assign)
    end
    # rubocop:enable Metrics/ParameterLists

    def as_json_from_resource(resource)
      attribute_value = lookup_from_resource(resource)
      deep_camelize_keys ? camelize_keys(attribute_value) : attribute_value
    end

    private

    def assert_json_type_valid!(type)
      raise "Invalid json_type #{type.inspect}" unless VALID_JSON_TYPES.include?(type)
    end

    def build_assign_impl(assign, transient_assign)
      if transient_assign
        raise "Cannot specify both assign and transient_assign" unless assign.nil?
        build_transient_assign_impl(transient_assign)
      else
        case assign
        when Proc then -> (resource, value) { assign.call(resource, value) }
        when Symbol then -> (resource, value) { resource.record.send(assign, value) }
        when NilClass then  -> (resource, value) { resource.record.send(:"#{ruby_name}=", value) }
        else raise "Invalid value for assign: #{assign.inspect}"
        end
      end
    end

    def build_transient_assign_impl(transient_assign)
      case transient_assign
      when Proc
        -> (resource, value) { resource.transient_fields[ruby_name] = transient_assign.call(value) }
      when true
        -> (resource, value) { resource.transient_fields[ruby_name] = value }
      else
        raise "Invalid value for transient_assign: #{transient_assign.inspect}"
      end
    end

    def camelize_keys(item)
      if item.respond_to?(:each_pair)
        item.to_h.reduce({}) do |acc, (key, val)|
          acc.merge(key.to_s.camelize(:lower).to_sym => camelize_keys(val))
        end
      elsif item.respond_to?(:map)
        item.map { |i| camelize_keys(i) }
      else
        item
      end
    end
  end
end
