module SASC
  class Field
    RESERVED_KEYS = Set.new(%w(data type id attributes relationships included meta arguments result))
    POSSIBLE_SETTABLE_FOR = Set.new(%i(create update))

    attr_reader :hidden, :ruby_name, :json_name

    def initialize(ruby_name, json_name: nil, lookup: nil, settable_for: [], hidden: false)
      @ruby_name = ruby_name.to_sym
      @json_name = json_name&.to_s || ruby_name.to_s.downcase.camelize(:lower)
      @settable_for = Set.new(Array(settable_for))
      @hidden = hidden

      raise "JSON key #{@json_name} is reserved by SASC" if RESERVED_KEYS.include?(@json_name)
      raise "settable_for can only contain :create and/or :update" unless (@settable_for - POSSIBLE_SETTABLE_FOR).empty?

      define_lookup_method(lookup)
    end

    def as_json_from_resource(_resource)
      raise NotImplementedError
    end

    def settable_for?(mode)
      @settable_for.include?(mode)
    end

    def hidden?
      hidden
    end

    private

    def define_lookup_method(lookup)
      lookup_impl = case lookup
                    when Proc then -> (resource) { lookup.call(resource) }
                    when Symbol then -> (resource) { resource.record.public_send(lookup) }
                    when NilClass then  -> (resource) { resource.record.public_send(ruby_name) }
                    else raise "Invalid value for lookup: #{lookup.inspect}"
                    end
      define_singleton_method :lookup_from_resource, lookup_impl
    end
  end
end
