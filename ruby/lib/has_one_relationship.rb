module SASC
  class HasOneRelationship < Relationship
    def initialize(ruby_name, resource_type, assign: nil, transient_assign: nil, **kwargs)
      super(ruby_name, resource_type, **kwargs)

      assign_impl = with_rel_to_record_conversion(build_assign_impl(assign, transient_assign))
      define_singleton_method :assign_in_resource, assign_impl
    end

    def as_json_from_resource(resource)
      related = lookup_from_resource(resource)
      related.nil? ? nil : relationship_data_json(related)
    end

    def plural?
      false
    end

    private

    def with_rel_to_record_conversion(prc)
      lambda do |resource, value|
        record = settable_lookup(value, resource)
        prc.call(resource, record)
      end
    end

    def build_assign_impl(assign, transient_assign)
      if transient_assign
        raise "Cannot specify both assign and transient_assign" unless assign.nil?
        build_transient_assign_impl(transient_assign)
      else
        case assign
        when Proc then -> (resource, record) { assign.call(resource, record) }
        when Symbol then -> (resource, record) { resource.record.send(assign, record) }
        when NilClass then -> (resource, record) { resource.record.send(:"#{ruby_name}=", record) }
        else raise "Invalid value for assign: #{assign.inspect}"
        end
      end
    end

    def build_transient_assign_impl(transient_assign)
      case transient_assign
      when Proc then lambda do |resource, record|
        resource.transient_fields[ruby_name] = transient_assign.call(record)
      end
      when true then lambda do |resource, record|
        resource.transient_fields[ruby_name] = record
      end
      else
        raise "Invalid value for transient_assign: #{transient_assign.inspect}"
      end
    end
  end
end
