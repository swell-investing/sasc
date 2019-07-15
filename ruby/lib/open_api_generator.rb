# rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/ClassLength
module SASC
  class OpenApiGenerator
    attr_reader :api_name, :router

    def initialize(api_name, router)
      @api_name = api_name
      @router = router
    end

    def generate
      hash = build_spec
      json = JSON.pretty_generate(sort_keys(hash))

      doc = Openapi3Parser.load(json)
      unless doc.valid?
        shown_errors = "#{[doc.errors.count, 5].min} errors shown of #{doc.errors.count}"
        raise "Invalid OpenApi3 document (#{shown_errors}):\n#{doc.errors.take(5).pretty_inspect}"
      end

      json
    end

    private

    TOP_SORTED_KEYS = [:openapi, :info, :type, :id, :attributes, :relationships].freeze

    def key_ordering_index(key)
      index = TOP_SORTED_KEYS.index(key) || 99
      "#{format('%02u', index)}-#{key}"
    end

    def sort_keys(obj)
      return obj unless obj.is_a?(Hash)

      obj
        .transform_values { |v| sort_keys(v) }
        .sort_by { |k, _v| key_ordering_index(k) }
        .to_h
    end

    def build_spec
      routes = all_routes
      version = SASC::Versioning.latest_version

      {
        openapi: "3.0.0",
        info: {
          title: api_name.to_s,
          version: version,
          description: "**Version #{version}:** #{SASC::Versioning.versions[version]['description']}",
        },
        tags: tags(routes),
        paths: paths(routes),
        components: {
          parameters: common_request_headers(version),
          headers: common_response_headers(version),
          schemas: schemas(routes),
        },
      }
    end

    # rubocop:disable Metrics/CyclomaticComplexity
    # rubocop:disable Metrics/PerceivedComplexity
    def all_routes
      router.routes.map { |route|
        next if route.verb == "PUT"
        next unless route.path.spec.to_s.starts_with?("/api/")
        controller_name = route.defaults[:controller]
        next unless controller_name
        controller = (controller_name.camelize + "Controller").safe_constantize
        next unless controller && controller.included_modules.include?(SASCConcern)
        action = route.defaults[:action].to_sym
        path = route.path.spec.to_s.sub("(.:format)", "").sub(/:(\w+)/, "{\\1}")
        ignored_path = controller&.sasc_ignored_path_matchers[action]
        next if ignored_path && (ignored_path == :all || path.match(Regexp.new(ignored_path)))

        controller_instance = controller.new
        resource_class = controller_instance.sasc_resource_class
        inclusions = controller_instance.default_inclusions
        nouns = resource_class.type_name.tr("-", " ")
        sasc_action = controller&.sasc_actions[action]

        OpenStruct.new(
          action: action,
          controller: controller,
          resource_class: resource_class,
          res_name: resource_class.type_name.underscore,
          inclusions: inclusions,
          http_method: route.verb.downcase.to_sym,
          path: path,
          nouns: nouns,
          noun: nouns.singularize,
          sasc_action: sasc_action
        )
      }.compact
    end
    # rubocop:enable Metrics/CyclomaticComplexity
    # rubocop:enable Metrics/PerceivedComplexity

    def tags(routes)
      routes
        .group_by { |route| route.resource_class.type_name }
        .map { |type_name, _res_routes|
          {
            name: type_name,
            description: "Endpoints for `#{type_name}` resources",
          }
        }.sort_by { |tag_hash| tag_hash[:name] }
    end

    def paths(routes)
      routes.group_by(&:path).transform_values do |path_routes|
        # TODO: Complain if there is an index route but no show route
        # TODO: Complain if there is an underscore in the path
        # TODO: Complain if the path doesn't match the resource type
        path_routes.map { |route| [route.http_method, describe_route(route)] }.to_h
      end
    end

    def describe_route(route)
      operation_id_path = route.path.sub("/api/", "").gsub(/[^A-Za-z0-9]+/, "_").gsub(/_+$/, "")

      # TODO: Complain if the route is enabled but the controller action and/or resource flag is not

      {
        summary: route_summary(route),
        tags: [route.resource_class.type_name],
        operationId: route.http_method.to_s + "_" + operation_id_path,
        parameters: route_parameters(route),
        responses: route_responses(route),
        requestBody: route_request_body(route),
      }.compact
    end

    # rubocop:disable Metrics/CyclomaticComplexity
    def route_summary(route)
      return route.sasc_action&.description if route.sasc_action&.description

      case route.action
      when :index then "Get list of #{route.nouns}"
      when :show then "Get #{route.noun} by id"
      when :create then "Create new #{route.noun}"
      when :update then "Update #{route.noun}"
      when :destroy then "Delete #{route.noun}"
      else "Run the #{route.action} action"
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity

    def route_parameters(route)
      parameters = common_request_header_references

      if route.action == :index
        parameters << {
          name: "filter[id]",
          in: "query",
          description: "A JSON array of string ids, e.g. `[\"1\",\"2\",\"3\"]`." \
                       " Result will exclude records with an id not in the list.",
          schema: { type: :string },
        }

        route.controller.sasc_filters.each do |key, filter|
          parameters << {
            name: "filter[#{key.to_s.camelize(:lower)}]",
            in: "query",
            description: filter[:description],
            schema: {
              "type" => "string",
              "description" => "A JSON value (e.g. strings must be double quoted). Schema is #{filter[:type].to_json}",
            },
          }
        end
      elsif route.sasc_action&.collection? || route.action == :create
        # No additional parameters
      else
        parameters << {
          name: "id",
          in: "path",
          description: "#{route.noun} id",
          required: true,
          schema: { type: :string },
        }
      end

      parameters
    end

    # rubocop:disable Metrics/CyclomaticComplexity
    def route_responses(route)
      return custom_action_responses(route) if route.sasc_action

      case route.action
      when :index then index_responses(route)
      when :show then show_responses(route)
      when :create then create_responses(route)
      when :update then update_responses(route)
      when :destroy then destroy_responses(route)
      else custom_action_responses(route)
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity

    def index_responses(route)
      {
        "200" => {
          description: "A list of #{route.nouns}",
          headers: common_response_header_references,
          content: {
            "application/json" => {
              schema: {
                "$ref" => "#/components/schemas/#{route.res_name}_index",
              },
            },
          },
        },
      }
    end

    def show_responses(route)
      {
        "200" => {
          description: "The #{route.noun} with the given id",
          headers: common_response_header_references,
          content: {
            "application/json" => {
              schema: {
                "$ref" => "#/components/schemas/#{route.res_name}_single",
              },
            },
          },
        },
      }
    end

    def create_responses(route)
      {
        "201" => {
          description: "The newly created #{route.noun}",
          headers: common_response_header_references,
          content: {
            "application/json" => {
              schema: {
                "$ref" => "#/components/schemas/#{route.res_name}_single",
              },
            },
          },
        },
      }
    end

    def update_responses(route)
      {
        "200" => {
          description: "The updated #{route.noun}",
          headers: common_response_header_references,
          content: {
            "application/json" => {
              schema: {
                "$ref" => "#/components/schemas/#{route.res_name}_single",
              },
            },
          },
        },
      }
    end

    def destroy_responses(route)
      {
        "204" => {
          description: "An empty response, indicating that the #{route.noun} was destroyed",
          headers: common_response_header_references,
        },
      }
    end

    def custom_action_responses(route)
      action = route.sasc_action
      raise "#{route.http_method} #{route.path} is not a custom sasc action" if action.nil?

      unless action.individual? == route.path.include?("/{id}/action")
        raise "#{route.http_method} #{route.path} custom sasc action plurality mismatch"
      end

      {
        "200" => {
          description: "The results of the successfully completed #{action.name} action",
          headers: common_response_header_references,
          content: {
            "application/json" => {
              schema: {
                "$ref" => "#/components/schemas/#{route.res_name}_#{action.name}_results",
              },
            },
          },
        },
      }
    end

    def route_request_body(route)
      return nil unless [:post, :patch].include?(route.http_method)

      if route.sasc_action.nil?
        action_name = route.action
        description = case route.action
                      when :create then "The new #{route.noun} to create"
                      when :update then "The updated values for any fields of the #{route.noun}"
                      else raise "Can't figure out #{route.path}"
                      end
      else
        action_name = route.sasc_action.name
        description = "The arguments to the #{route.sasc_action.name} action"
      end

      {
        description: description,
        required: true,
        content: {
          "application/json" => {
            schema: {
              "$ref" => "#/components/schemas/#{route.res_name}_#{action_name}_req",
            },
          },
        },
      }
    end

    def schemas(routes)
      routes
        .group_by(&:path)
        .values
        .map { |path_routes| [request_schema_map(path_routes), response_schema_map(path_routes)] }
        .flatten
        .reduce({}, &:merge)
    end

    def request_schema_map(path_routes)
      h = {}

      create_route = path_routes.find { |route| route.action == :create && route.sasc_action.nil? }
      h[:"#{create_route.res_name}_create_req"] = create_request_schema(create_route) if create_route

      update_route = path_routes.find { |route| route.action == :update && route.sasc_action.nil? }
      h[:"#{update_route.res_name}_update_req"] = update_request_schema(update_route) if update_route

      path_routes.each do |route|
        if route.sasc_action
          h["#{route.res_name}_#{route.sasc_action.name}_req"] = custom_action_request_schema(route)
        end
      end

      h
    end

    def response_schema_map(path_routes)
      h = {}

      # Common parts like this should be the same for all the routes in the list, so
      # we can just use the first one.
      res_name = path_routes.first.res_name
      h[:"#{res_name}_resource"] = resource_response_schema(path_routes.first)
      h[:"#{res_name}_single"] = single_response_schema(path_routes.first)

      index_route = path_routes.find { |route| route.action == :index }
      h[:"#{res_name}_index"] = index_response_schema(index_route) if index_route

      path_routes.each do |route|
        if route.sasc_action
          h["#{route.res_name}_#{route.sasc_action.name}_results"] = custom_action_response_schema(route)
        end
      end

      h
    end

    def resource_response_schema(route)
      {
        type: :object,
        required: [:id, :type, :attributes, :relationships],
        properties: {
          id: { type: :string, example: "123" }, # TODO: Get example id from resource class
          type: { type: :string, enum: [route.resource_class.type_name] },
          attributes: attributes_schema(route, :read),
          relationships: relationships_schema(route, :read),
        },
      }
    end

    def attributes_schema(route, mode)
      response_attributes = route.resource_class.attributes
      response_attributes = if mode == :read
                              response_attributes.reject(&:hidden?)
                            else
                              response_attributes.select { |a| a.settable_for?(mode) }
                            end

      {
        type: :object,
        required: mode == :update ? [] : response_attributes.map(&:json_name).sort,
        properties: response_attributes.map { |attr| field_type_spec_hash(route, attr) }.reduce({}, &:merge),
      }
    end

    def relationships_schema(route, mode)
      response_relationships = route.resource_class.relationships
      response_relationships = if mode == :read
                                 response_relationships.reject(&:hidden?)
                               else
                                 response_relationships.select { |a| a.settable_for?(mode) }
                               end

      {
        type: :object,
        required: mode == :update ? [] : response_relationships.map(&:json_name).sort,
        properties: response_relationships.map { |rel|
          single_rel_schema = {
            type: :object,
            required: [:id, :type],
            nullable: !rel.plural?,
            properties: {
              type: { type: :string, enum: [rel.related_resource_type.type_name] },
              id: { type: :string, example: "123" }, # TODO: Get example id from related resource class
            },
          }

          {
            rel.json_name => {
              type: :object,
              required: [:data],
              properties: {
                data: rel.plural? ? { type: :array, items: single_rel_schema } : single_rel_schema,
              },
            },
          }
        }.reduce({}, &:merge),
      }
    end

    def response_inclusions_schema(inclusions)
      return nil if inclusions.empty?

      inclusion_schemas = inclusions.map do |_key, res_class|
        {
          res_class.type_name => {
            type: :array,
            items: {
              "$ref" => "#/components/schemas/#{res_class.type_name.underscore}_resource",
            },
          },
        }
      end

      {
        type: :object,
        required: [],
        properties: inclusion_schemas.reduce({}, &:merge),
      }
    end

    def index_response_schema(route)
      {
        type: :object,
        required: [:data],
        properties: {
          data: {
            type: :array,
            items: {
              "$ref" => "#/components/schemas/#{route.res_name}_resource",
            },
          },
          included: response_inclusions_schema(route.inclusions),
        }.compact,
      }
    end

    def single_response_schema(route)
      {
        type: :object,
        required: [:data],
        properties: {
          data: {
            "$ref" => "#/components/schemas/#{route.res_name}_resource",
          },
          included: response_inclusions_schema(route.inclusions),
        }.compact,
      }
    end

    def custom_action_response_schema(route)
      sasc_action = route.sasc_action
      results = sasc_action.results

      {
        type: :object,
        required: [:result],
        properties: {
          result: {
            type: :object,
            required: results.map(&:json_name).sort,
            properties: results.map { |r| field_type_spec_hash(route, r) }.reduce({}, &:merge),
          },
        },
      }
    end

    def field_type_spec_hash(_route, field)
      # TODO: If the field's type is a SASC resource class, then $ref the resource schema
      {
        field.json_name => {
          type: field_json_type(field),
          format: field_json_format(field),
          items: field.json_type == :array ? { type: :string } : nil, # TODO
          properties: field.json_type == :object ? {} : nil, # TODO
          required: field.json_type == :object ? [] : nil, # TODO
          example: field_example(field),
        }.compact,
      }
    end

    def field_json_type(field)
      return :number if field.json_type == :float
      field.json_type
    end

    def field_json_format(field)
      return :float if field.json_type == :float
      nil
    end

    def field_example(field)
      return "some string" if field.json_type == :string
      return 1.234 if field.json_type == :float
      nil
    end

    def create_request_schema(route)
      {
        type: :object,
        required: [:data],
        properties: {
          data: {
            type: :object,
            required: [:type, :attributes, :relationships],
            properties: {
              type: { type: :string, enum: [route.resource_class.type_name] },
              attributes: attributes_schema(route, :create),
              relationships: relationships_schema(route, :create),
            },
          },
        },
      }
    end

    def update_request_schema(route)
      {
        type: :object,
        required: [:data],
        properties: {
          data: {
            type: :object,
            required: [:id, :type, :attributes, :relationships],
            properties: {
              id: { type: :string, example: "123" }, # TODO: Get example id from resource class
              type: { type: :string, enum: [route.resource_class.type_name] },
              attributes: attributes_schema(route, :update),
              relationships: relationships_schema(route, :update),
            },
          },
        },
      }
    end

    def custom_action_request_schema(route)
      sasc_action = route.sasc_action
      # TODO: raise error explaining that sasc_actions should be overriden at this point(?)
      arguments = sasc_action.arguments

      {
        type: :object,
        required: [:arguments],
        properties: {
          arguments: {
            type: :object,
            required: arguments.map(&:json_name).sort,
            properties: arguments.map { |arg| field_type_spec_hash(route, arg) }.reduce({}, &:merge),
          },
        },
      }
    end

    def common_request_headers(api_version)
      {
        "x-sasc" => {
          name: "x-sasc",
          in: "header",
          description: "Version of SASC (the protocol, not the Swell API specifically). Must be `1.0.0`",
          required: true,
          schema: {
            type: :string,
            enum: ["1.0.0"],
          },
        },
        "x-sasc-api-version" => {
          name: "x-sasc-api-version",
          in: "header",
          description: "Requested version of the Swell API, in semver format. This spec assumes `#{api_version}`",
          required: true,
          schema: {
            type: :string,
            enum: [api_version.to_s],
          },
        },
        "x-sasc-client" => {
          name: "x-sasc-Client",
          in: "header",
          description: "The name, version, and build timestamp of the requesting client, separated by spaces",
          required: true,
          example: "my-client 2.1.0 12345678",
          schema: {
            type: :string,
            pattern: "^([a-z0-9-]+) (\\S+) (\\d+)$",
          },
        },
      }
    end

    def common_request_header_references
      [
        { "$ref" => "#/components/parameters/x-sasc" },
        { "$ref" => "#/components/parameters/x-sasc-api-version" },
        { "$ref" => "#/components/parameters/x-sasc-client" },
      ]
    end

    def common_response_headers(api_version)
      {
        "x-sasc" => {
          description: "Version of SASC (the protocol, not the Swell API specifically). Fixed as `1.0.0`",
          required: true,
          schema: {
            type: :string,
            enum: ["1.0.0"],
          },
        },
        "x-sasc-api-version" => {
          description: "Version of the Swell API in use, in semver format. This spec assumes `#{api_version}`",
          required: true,
          schema: {
            type: :string,
            enum: [api_version.to_s],
          },
        },
      }
    end

    def common_response_header_references
      {
        "x-sasc" => {
          "$ref" => "#/components/headers/x-sasc",
        },
        "x-sasc-api-version" => {
          "$ref" => "#/components/headers/x-sasc-api-version",
        },
      }
    end
  end
end
