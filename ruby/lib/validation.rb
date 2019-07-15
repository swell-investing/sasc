module SASC
  module Validation
    # TODO: It seems that this doesn't correctly validate the `items` specification in arrays
    # for example, { type: :array, items: { type: :yippie } } seems to work just fine
    def self.valid?(schema, value)
      canon_schema = canonicalize_schema(schema)
      schema_obj = JSONSchemer.schema(canon_schema)
      schema_obj.valid?(desymbolize(value))
    end

    def self.desymbolize(value)
      case value
      when Hash then value.map { |k, v| [k.to_s, desymbolize(v)] }.to_h
      when Array then value.map { |i| desymbolize(i) }
      when Symbol then value.to_s
      when String, Numeric, TrueClass, FalseClass, NilClass then value
      else raise ArgumentError.new("Non-JSONable value #{value.inspect}")
      end
    end

    def self.canonicalize_schema(schema)
      case schema
      when Hash
        schema = desymbolize(schema)
        case schema["type"]
        when "object" then canonicalize_object_schema(schema)
        when "array" then canonicalize_array_schema(schema)
        else schema
        end
      when String, Symbol
        { "type" => schema.to_s }
      else
        raise ArgumentError.new("Invalid schema definition")
      end
    end

    def self.canonicalize_object_schema(schema)
      schema["additionalProperties"] = false unless schema.key?("additionalProperties")
      schema["properties"].transform_values! { |prop| canonicalize_schema(prop) }

      schema
    end

    def self.canonicalize_array_schema(schema)
      case schema["items"]
      when Hash
        schema["items"].transform_values! { |prop| canonicalize_schema(prop) }
      when Array
        schema["additionalItems"] = false unless schema.key?("additionalItems")
        schema["items"].map! { |prop| canonicalize_schema(prop) }
      end

      schema
    end
  end
end
