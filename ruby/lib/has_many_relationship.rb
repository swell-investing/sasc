module SASC
  class HasManyRelationship < Relationship
    def as_json_from_resource(resource)
      lookup_from_resource(resource).map { |related| relationship_data_json(related) }
    end

    def plural?
      true
    end

    # Mutation is not currently supported for has_many relationships. It could be tricky to get right, so we
    # should wait until we have an actual need before implementing.
  end
end
