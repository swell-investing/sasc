module SASC
  class Relationship < Field
    include SASC::Errors

    attr_reader :related_resource_type, :settable_target_scope

    def initialize(ruby_name, resource_type, settable_target_scope: nil, **kwargs)
      super(ruby_name, **kwargs)

      raise "Invalid related resource_type #{resource_type.inspect}" unless resource_type.respond_to?(:type_name)

      @related_resource_type = resource_type
      @settable_target_scope = settable_target_scope
    end

    def plural?
      raise NotImplementedError
    end

    protected

    def settable_lookup(rel, resource)
      raise "Setting #{related_resource_type} #{ruby_name} needs settable_target_scope" unless settable_target_scope

      pointer_base = "/data/relationships/#{json_name}"
      rel_id = get_rel_id(rel, pointer_base)

      return nil if rel_id.nil?

      scope = settable_target_scope
      scope = scope.call(resource) if scope.respond_to?(:call)

      begin
        return scope.find(rel_id)
      rescue ActiveRecord::RecordNotFound
        raise InvalidFieldValue.new(
          "No related record with that id was available",
          pointer: "#{pointer_base}/data/id"
        )
      end
    end

    # FIXME: This unnecessarily fetches associated records just to get their id
    def relationship_data_json(record)
      return nil if record.nil?
      { type: related_resource_type.type_name, id: record.id.to_s }
    end

    private

    def get_rel_id(rel, pointer_base)
      raise InvalidFieldValue.new("The relationship must be an object", pointer: pointer_base) unless rel.is_a?(Hash)

      return nil if rel[:data].nil?
      unless rel[:data].is_a?(Hash)
        raise InvalidFieldValue.new("Relation data must be an object", pointer: "#{pointer_base}/data")
      end

      unless rel[:data][:id].is_a?(String)
        raise InvalidFieldValue.new("Relation id must be a string", pointer: "#{pointer_base}/data/id")
      end

      assert_valid_rel_type(rel, pointer_base)

      rel[:data][:id]
    end

    def assert_valid_rel_type(rel, pointer_base)
      unless rel[:data][:type] == related_resource_type.type_name
        raise InvalidFieldValue.new(
          "Relationship type must match expected resource type",
          detail: "Expected type '#{related_resource_type.type_name}'",
          pointer: "#{pointer_base}/data/type"
        )
      end
    end
  end
end
