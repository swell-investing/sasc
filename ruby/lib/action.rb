module SASC
  class Action
    attr_reader :description, :name, :kind

    # rubocop:disable Metrics/ParameterLists
    def initialize(name, kind, arguments: {}, description: nil, result: {}, version_translator: nil)
      @name = name.to_sym

      @kind = kind.to_sym
      assert_kind_valid!(@kind)

      @argument_types = arguments
      @argument_ruby_names = arguments.keys.map { |ruby_name|
        [ruby_name.to_s.downcase.camelize(:lower).to_sym, ruby_name]
      }.to_h

      @description = description || "Run the #{name} action"

      @result_types = result
      @result_json_names = result.keys.map { |ruby_name|
        [ruby_name, ruby_name.to_s.downcase.camelize(:lower).to_sym]
      }.to_h

      @translator_class = version_translator
    end
    # rubocop:enable Metrics/ParameterLists

    def unjsonify_arguments(arguments, api_version)
      unless arguments.is_a?(Hash)
        raise SASC::Errors::InvalidRequestDocumentContent.new(
          "The arguments must be an object",
          pointer: "/arguments"
        )
      end

      arguments = arguments.transform_keys(&:to_sym)
      arguments = translate(arguments, api_version, :request_up)
      arguments = arguments.transform_keys { |key| @argument_ruby_names[key] || key }
      assert_arguments_valid!(arguments)
      arguments
    end

    def jsonify_result(result, api_version)
      assert_result_valid!(result)
      result = result.transform_keys { |key| @result_json_names[key.to_sym] || key.to_sym }
      result = translate(result, api_version, :response_down)
      result
    end

    def individual?
      self.kind == :individual
    end

    def collection?
      self.kind == :collection
    end

    def arguments
      @argument_types.map do |ruby_name, type|
        OpenStruct.new(ruby_name: ruby_name,
                       json_name: @argument_ruby_names.invert[ruby_name],
                       json_type: type)
      end
    end

    def results
      @result_types.map do |ruby_name, type|
        OpenStruct.new(ruby_name: ruby_name,
                       json_name: @result_json_names[ruby_name],
                       json_type: type.is_a?(Class) ? :object : type)
      end
    end

    private

    def translate(data, api_version, mode)
      SASC::Versioning
        .create_translator(@translator_class, api_version)
        .translate(mode, data)
    end

    def assert_kind_valid!(kind)
      unless [:collection, :individual].include?(kind)
        raise "Invalid SASC action kind #{kind.inspect}, must be :collection or :individual"
      end
    end

    def assert_arguments_valid!(arguments)
      @argument_types.each do |arg_name, _arg_type|
        # TODO: Maybe allow some arguments to be optional?
        unless arguments.key?(arg_name)
          pointer = "/arguments/#{@argument_ruby_names.key(arg_name)}"
          raise SASC::Errors::MissingRequiredActionArgument.new("Missing a necessary argument", pointer: pointer)
        end

        # TODO: Validate that arguments are of expected types
      end

      arguments.each_key do |arg_name|
        unless @argument_types.key?(arg_name.to_sym)
          raise SASC::Errors::UnknownActionArgument.new("Argument not recognized", pointer: "/arguments/#{arg_name}")
        end
      end
    end

    def assert_result_valid!(result)
      @result_types.each do |result_key, _result_type|
        # TODO: Maybe allow some results to be optional?
        raise "Missing result key #{result_key.inspect}" unless result.key?(result_key) || result.key?(result_key.to_s)

        # TODO: Validate that results are of expected types
      end

      result.each_key do |result_key|
        unless @result_types.key?(result_key.to_sym)
          raise "Unknown result key #{result_key.inspect}"
        end
      end
    end
  end
end
