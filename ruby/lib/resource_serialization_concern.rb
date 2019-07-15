module SASC
  module ResourceSerializationConcern
    extend ActiveSupport::Concern

    def as_json(_options = {})
      json = {
        id: self.id,
        type: self.class.type_name,
        attributes: attributes_json,
        relationships: relationships_json,
      }

      translator.translate(:response_down, json)
    end

    private

    def attributes_json
      pairs = self.class.attributes.reject(&:hidden).map do |attr|
        [
          attr.json_name.to_sym,
          attr.as_json_from_resource(self),
        ]
      end
      pairs.to_h
    end

    def relationships_json
      pairs = self.class.relationships.reject(&:hidden).map do |rel|
        [
          rel.json_name.to_sym,
          { data: rel.as_json_from_resource(self) },
        ]
      end
      pairs.to_h
    end
  end
end
