module SASC
  #.## SASC::Resource
  #. Subclass SASC::Resource to describe how a model is serialized to/from SASC-compliant JSON
  #.
  #. Instances of SASC::Resource wrap a `record`, an instance of the corresponding model class. Most operations on a
  #. Resource instance involve computation and/or mutation of the wrapped record.
  #.
  #. When Resources are serialized or deserialized, their data is converted to/from SASC JSON attributes and
  #. relationships. Attributes contain actual data from the record, while relationships indicate the type and ID of
  #. other resources associated with this one.
  class Resource
    include ResourceMutationConcern
    include ResourceSerializationConcern
    include ResourceFieldDefinitionConcern

    #% SASC::Resource.type_name
    #. Returns the SASC type name of this resource, a dash-separated plural lowercase string
    #.
    #. The default implementation derives the resource name from the class name:
    #.
    #. ```ruby
    #. class DogKennelResource < SASC::Resource
    #. end
    #.
    #. DogKennelResource.type_name # => "dog-kennels"
    #. ```
    #.
    #. You may wish to customize this:
    #.
    #. ```ruby
    #. class DogKennelResource < SASC::Resource
    #.   def self.type_name
    #.     "dog-residences"
    #.   end
    #. end
    #. ```
    def self.type_name
      @type_name ||= self.name.sub(/Resource$/, '').demodulize.pluralize.underscore.dasherize.downcase
    end

    def self.attributes
      @attributes ||= []
    end

    def self.relationships
      @relationships ||= []
    end

    #% SASC::Resource.res_decoration(decoration: :decorate)
    #. Configure record decoration
    #.
    #. When enabled, the decorator is automatically applied before the record is accessed in any way.
    #.
    #. * `decoration`: How the record is decorated. Can be a proc which accepts the record and returns a decorated
    #.   record, or a symbol which names a decoration method on the record.
    #.
    #. If you're using a Draper decorator, then you don't need to specify any parameter, and the `decorate` method
    #. will automatically be used.
    #.
    #. ```ruby
    #. class DogDecorator < Draper::Decorator
    #. end
    #.
    #. class DogResource < SASC::Resource
    #.   res_decoration
    #. end
    #. ```
    def self.res_decoration(decoration: :decorate)
      @decoration_fn = case decoration
                       when Proc then -> (record) { decoration.call(record) }
                       when Symbol then -> (record) { record.send(decoration) }
                       else raise "Invalid value for decoration: #{decoration.inspect}"
                       end
    end

    #% SASC::Resource.res_version_translation(translator_class)
    #. Configure support for older API versions with a translator
    #.
    #. When enabled, the translator is used for mutation and serialization if `context[:api_version]`
    #. is below the current version.
    #.
    #. * `translator_class`: A class deriving from Glossator::Translator
    def self.res_version_translation(translator_class)
      @translator_class = translator_class
    end

    #% SASC::Resource.new(record, context = {})
    #. Construct an instance of the Resource class around a given record
    #.
    #. * `record`: The record object to wrap
    #. * `context`: A hash containing services and meta-information which is not part of the record itself
    #.
    #. Subclasses of `SASC::Resource` must have compatible constructors in order to be properly compatible with
    #. `SASCBaseController`.
    def initialize(record, context = {})
      context[:api_version] ||= SASC::Versioning.latest_version

      @record = record
      @context = context
      @translator = SASC::Versioning.create_translator(
        self.class.instance_variable_get(:@translator_class),
        context[:api_version]
      )
    end

    #% SASC::Resource.record
    #. Returns the wrapped record, decorating it first if `res_decoration` has been configured
    def record
      return @decorated_record if @decorated_record
      decoration_fn = self.class.instance_variable_get(:@decoration_fn)
      decoration_fn ||= -> (rec) { rec } # Default is no-op decoration
      @decorated_record = decoration_fn.call(@record)
    end

    #% SASC::Resource.context
    #. Returns the `context` hash passed in during construction
    attr_reader :context

    attr_reader :translator

    #% SASC::Resource.id
    #. Returns the id of the resource.
    #.
    #. The id must be a string to be compliant with SASC.
    #.
    #. The default implementation calls the `id` method on the `record`, but you can override this method to customize
    #. this behavior.
    def id
      record.id.to_s
    end

    def eql?(other)
      self.class.type_name == other.class.type_name && self.id == other.id
    end

    def hash
      [self.class.type_name, self.id].hash
    end
  end
end
