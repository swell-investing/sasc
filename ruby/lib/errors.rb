module SASC
  #.## SASC::Errors
  #. Errors in SASC are represented as exceptions which derive from `SASC::BaseError`. See its description below for
  #. details about its features and how to derive new error clasess.
  module Errors
    #% SASC::Errors::with_validation_error_reporting
    #. Runs the given block, converting any matching ActiveRecord validation error raised into a SASC error
    #.
    #. * `resource`: The resource instance with a record that we are expecting to potentially be invalid
    #.
    #. If the block raises a validation error (i.e. ActiveRecord::RecordInvalid or ActiveModel::ValidationError) then
    #. the error will be re-raised as a SASC InvalidFieldValue error. The error will have the `pointer` field set
    #. if there is a matching attribute on the resource and the error record is the given resource's record.
    def self.with_validation_error_reporting(resource)
      yield
    rescue ActiveRecord::RecordInvalid, ActiveModel::ValidationError => e
      record = e.try(:record) || e.try(:model)

      field_errors = field_errors_from_record(record, resource)
      if field_errors.empty?
        field_errors = [InvalidFieldValue.new("Resource is not valid", detail: e.message)]
      end

      raise BatchError.new(field_errors)
    end

    def self.field_errors_from_record(record, resource)
      record_errors = record.try(:errors) || {}

      record_errors.keys.map do |bad_attr_name|
        attribute = resource.class.attributes.find { |attr| attr.ruby_name == bad_attr_name }

        # TODO: Should not have a pointer attribute unless the HTTP request actually has that JSON path
        InvalidFieldValue.new(
          "Attribute has invalid contents",
          subcode: subcode_from_validation_error_detail(record.errors.details[bad_attr_name]&.first&.fetch(:error)),
          detail: record.errors.full_messages_for(bad_attr_name)&.first,
          pointer: ((record == resource.record && attribute) ? "/data/attributes/#{attribute.json_name}" : nil)
        )
      end
    end

    def self.subcode_from_validation_error_detail(detail)
      detail.is_a?(Symbol) ? detail.to_s.underscore.upcase : nil
    end
    private_class_method :subcode_from_validation_error_detail

    #% SASC::Errors::BaseError
    #. The base class for all SASC errors.
    #.
    #. When deriving your own custom error class, you don't need to specify anything other than the class name; the
    #. error will automatically render using your class name as the error code. For example, to create a new error
    #. class with `EVERYTHING_IS_NOT_FINE` as the SASC error code:
    #.
    #. ```ruby
    #. class EverythingIsNotFine < SASC::Errors::BaseError
    #. end
    #. ```
    #.
    #. By default, errors that derive from `BaseError` are rendered with an HTTP status code of `400: Bad Request`. To
    #. customize this, override the `http_status_code` method:
    #.
    #. ```ruby
    #. class EverythingIsNotFine < SASC::Errors::BaseError
    #.   def http_status_code
    #.     :internal_server_error
    #.   end
    #. end
    #. ```
    #.
    #. SASC errors have the following attributes, which correspond with the optional fields for error objects as
    #. described in the spec:
    #.
    #. * `title`
    #. * `subcode`
    #. * `detail`
    #. * `pointer`
    #. * `parameter`
    #. * `header`
    #. * `meta`
    #.
    #. To set these as you construct a SASC error, call the initializer with the title as the first argument and any
    #. additional fields as named arguments:
    #.
    #. ```ruby
    #. raise EverythingIsNotFine.new("The room is literally on fire!", detail: "Except for my coffee, which is cold")
    #. ```
    #.
    #. Errors also have a `uuid` property, which is randomly generated on demand unless you specifically set a
    #. uuid yourself:
    #.
    #. ```ruby
    #. err = EverythingIsNotFine.new("Fiery fire!")
    #. err.uuid = self.request_uuid
    #. raise err
    #. ```
    class BaseError < RuntimeError
      attr_accessor :title, :subcode, :detail, :pointer, :parameter, :header, :meta
      attr_writer :uuid

      def initialize(title = nil, options = {})
        @title = title
        @subcode = options[:subcode]
        @detail = options[:detail]
        @pointer = options[:pointer]
        @parameter = options[:parameter]
        @header = options[:header]
        @meta = options[:meta]
      end

      def as_json(_options = {})
        error_json_object
      end

      def http_status_code
        :bad_request
      end

      def to_s
        "#{self.class.name}: #{as_json.inspect}"
      end

      def uuid
        @uuid ||= SecureRandom.uuid
      end

      protected

      def error_json_object
        {
          code: sasc_error_code,
          subcode: subcode,
          id: uuid,
          title: title,
          detail: detail,
          source: sasc_error_source,
          meta: meta,
        }.compact
      end

      def sasc_error_code
        self.class.name.demodulize.underscore.upcase
      end

      def sasc_error_source
        source = {
          pointer: @pointer,
          parameter: formatted_parameter,
          header: @header,
        }.compact

        source.empty? ? nil : source
      end

      def formatted_parameter
        case @parameter
        when Array then parameter.first + parameter.drop(1).map { |p| "[#{p}]" }.join("")
        else @parameter
        end
      end
    end

    class BatchError < BaseError
      include Enumerable

      attr_reader :errors

      def initialize(errors)
        raise "Cannot initialize BatchError with no errors" if errors.empty?
        @errors = errors
      end

      def as_json
        @errors.map(&:as_json).flatten
      end

      def each
        return enum_for(:each) unless block_given?
        @errors.each { |error| yield error }
      end

      # These don't make sense to access on the wrapping BatchError itself
      [:title, :subcode, :detail, :pointer, :parameter, :header, :meta, :uuid].each do |method_name|
        define_method(method_name) { raise NotImplementedError }
      end

      def http_status_code
        status_codes = @errors.map(&:http_status_code).uniq
        return :internal_server_error if status_codes.include?(:internal_server_error)
        return :bad_request if status_codes.length > 1
        return status_codes.first if status_codes.length == 1
      end
    end

    #% SASC::Errors::ReservedError
    #. A subclass of `BaseError` which is used for all the standard error types defined in the SASC spec.
    #.
    #. You should not derive your own domain-specific errors from this class, but instead from `BaseError` itself.
    #.
    #. The following ReservedError classes are available, all with the same constructor conventions as `BaseError`. You
    #. can raise these errors yourself in the appropriate situations. See the SASC protocol definition for details.
    #.
    #. * `SASC::Errors::InvalidFieldValue`
    #. * `SASC::Errors::UnknownField`
    #. * `SASC::Errors::InvalidQueryParameterValue`
    #. * `SASC::Errors::UnknownQueryParameter`
    #. * `SASC::Errors::MissingRequiredActionArgument`
    #. * `SASC::Errors::InvalidActionArgumentValue`
    #. * `SASC::Errors::UnknownActionArgument`
    #. * `SASC::Errors::InvalidRequestDocumentContent`
    #. * `SASC::Errors::BadIndividualResourceUrlId`
    #. * `SASC::Errors::PermissionDenied`
    #. * `SASC::Errors::IncompatibleApiVersion`
    #. * `SASC::Errors::UnknownApiVersion`
    #. * `SASC::Errors::Unauthorized`
    #. * `SASC::Errors::BadHeader`
    class ReservedError < BaseError
      def sasc_error_code
        "__#{super}__"
      end
    end

    class InvalidFieldValue < ReservedError
    end

    class UnknownField < ReservedError
    end

    class InvalidQueryParameterValue < ReservedError
    end

    class UnknownQueryParameter < ReservedError
    end

    class MissingRequiredActionArgument < ReservedError
    end

    class InvalidActionArgumentValue < ReservedError
    end

    class UnknownActionArgument < ReservedError
    end

    class InvalidRequestDocumentContent < ReservedError
    end

    class BadIndividualResourceUrlId < ReservedError
      def http_status_code
        :not_found
      end
    end

    class NotFound < ReservedError
      def http_status_code
        :not_found
      end

      def title
        @title ||= "Not Found"
      end
    end

    class PermissionDenied < ReservedError
      def http_status_code
        :forbidden
      end

      def title
        @title ||= "Forbidden"
      end
    end

    class IncompatibleApiVersion < ReservedError
      def initialize(title = nil, **kwargs)
        super title, header: "x-sasc-api-version", **kwargs
      end
    end

    class UnknownApiVersion < ReservedError
      def initialize(title = nil, **kwargs)
        super title, header: "x-sasc-api-version", **kwargs
      end
    end

    class DeprecatedClientVersion < ReservedError
      def http_status_code
        :gone
      end
    end

    class Unauthorized < ReservedError
      def http_status_code
        :unauthorized
      end
    end

    class BadHeader < ReservedError
    end

    class BadAcceptHeader < BadHeader
      def initialize(title = nil, **kwargs)
        super title, header: "Accept", **kwargs
      end

      def http_status_code
        :not_acceptable
      end
    end

    class BadContentTypeHeader < BadHeader
      def initialize(**kwargs)
        super header: "Content-Type", **kwargs
      end

      def http_status_code
        :unsupported_media_type
      end
    end

    #% SASC::Errors::InternalError
    #. A subclass of `BaseError` which conveniently wraps non-SASC exceptions
    #.
    #. Its constructor takes an instance of any exception, followed by the other arguments that the `BaseError`
    #. constructor takes:
    #.
    #. ```ruby
    #. def my_method
    #.   foo
    #. rescue FooError => e
    #.   raise SASC::Errors::InternalError(e, "Bar!", detail: "Baz narf")
    #. end
    #. ```
    #.
    #. When rendered, an `InternalError`'s HTTP status is 500, and its `code` is based on the class name of the wrapped
    #. error. For example, the `InternalError` in the example above would have the SASC error code `FOO_ERROR`.
    #.
    #. The error passed to `InternalError` during construction can be accessed by calling the `wrapped_error` method.
    class InternalError < BaseError
      attr_reader :wrapped_error

      def initialize(wrapped_error, *args, **kwargs)
        @wrapped_error = wrapped_error
        super(wrapped_error.to_s, *args, **kwargs)
      end

      def sasc_error_code
        wrapped_error.class.name.underscore.upcase
      end

      def http_status_code
        :internal_server_error
      end
    end
  end
end
