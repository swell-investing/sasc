module SASC
  module ResourceMutationConcern
    extend ActiveSupport::Concern
    include SASC::Errors

    class_methods do
      #% SASC::Resource.res_creatable
      #. Allows creation of the resource.
      #.
      #. You will also need to add a `create` method to the corresponding controller and set up routing.
      #.
      #. By default, new resources are saved by calling `resource.record.save!`. You can customize this behavior
      #. by providing a block to `res_creatable`, which is passed a resource with all fields already assigned:
      #.
      #. ```ruby
      #. def DogResource < SASC::Resource
      #.   res_attribute :name, :string, settable_for: [:create]
      #.   res_attribute :nickname, :string, settable_for: [:create]
      #.
      #.   res_creatable do |resource|
      #.     resource.record.nickname ||= resource.record.name
      #.     resource.record.save!
      #.   end
      #. end
      #. ```
      def res_creatable(&block)
        @save_created_resource_fn = block || -> (resource) { resource.record.save! }
      end

      #% SASC::Resource.res_updatable
      #. Allows updating the resource.
      #.
      #. You will also need to add an `update` method to the corresponding controller and set up routing.
      #.
      #. By default, updated resources are saved by calling `resource.record.save!`. You can customize this behavior
      #. by providing a block to `res_updatable`, which is passed a resource with all changed fields already assigned:
      #.
      #. ```ruby
      #. def DogResource < SASC::Resource
      #.   res_attribute :name, :string, settable_for: [:update]
      #.   res_attribute :nickname, :string, settable_for: [:update]
      #.
      #.   res_updatable do |resource|
      #.     if resource.record.name_changed? && !resource.record.nickname_changed?
      #.       resource.record.nickname = resource.record.name
      #.     end
      #.     resource.record.save!
      #.   end
      #. end
      #. ```
      def res_updatable(&block)
        @save_updated_resource_fn = block || -> (resource) { resource.record.save! }
      end

      #% SASC::Resource.res_destroyable
      #. Allows destroying the resource.
      #.
      #. You will also need to add a `destroy` method to the corresponding controller and set up routing.
      #.
      #. By default, resources are destroyed by calling `resource.record.destroy!`. You can customize this behavior
      #. by providing a block to `res_destroyable`, which is passed the resource:
      #.
      #. ```ruby
      #. def BeachBallResource < SASC::Resource
      #.   res_destroyable do |resource|
      #.     if resource.record.inflated?
      #.       resource.record.pop!
      #.     end
      #.     resource.record.destroy!
      #.   end
      #. end
      #. ```
      def res_destroyable(&block)
        @destroy_resource_fn = block || -> (resource) { resource.record.destroy! }
      end

      def create_with_sasc_data!(base_record, data, context)
        raise PermissionDenied.new("Forbidden to create this resource") unless @save_created_resource_fn
        raise InvalidRequestDocumentContent.new("The data must be an object", pointer: "/data") unless data.is_a?(Hash)
        raise InvalidRequestDocumentContent.new("Cannot set id on create", pointer: "/data/id") if data[:id].present?

        resource = self.new(base_record, context)
        resource.clear_transient_fields
        resource.send(:assign_fields, data, :create) # Have to use send because it is a private method

        SASC::Errors.with_validation_error_reporting(resource) { @save_created_resource_fn.call(resource) }
        resource.clear_transient_fields

        resource
      end
    end

    def update_with_sasc_data!(data)
      save_fn = self.class.instance_variable_get(:@save_updated_resource_fn)
      raise PermissionDenied.new("Forbidden to update this resource") unless save_fn
      raise InvalidRequestDocumentContent.new("The data must be an object", pointer: "/data") unless data.is_a?(Hash)
      raise InvalidRequestDocumentContent.new("Must give string id", pointer: "/data/id") unless data[:id].is_a?(String)
      raise InvalidRequestDocumentContent.new("Wrong id for resource", pointer: "/data/id") unless data[:id] == self.id

      clear_transient_fields
      assign_fields(data, :update)
      SASC::Errors.with_validation_error_reporting(self) { save_fn.call(self) }
      clear_transient_fields

      self
    end

    def destroy!
      destroy_fn = self.class.instance_variable_get(:@destroy_resource_fn)
      raise PermissionDenied.new("Forbidden to destroy this resource") unless destroy_fn
      destroy_fn.call(self)
    end

    def clear_transient_fields
      self.transient_fields = OpenStruct.new
    end

    #% transient_fields
    #. Returns a hash of transient fields set during assignment
    #.
    #. This method is only useful within `res_creatable` and `res_updatable` blocks, and is always cleared after
    #. those blocks complete.
    #.
    #. ```ruby
    #. class DogResource < SASC::Resource
    #.   res_attribute :color_code, :string, settable_for: [:create], transient_assign: true
    #.
    #.   res_creatable do |resource|
    #.     color = Color.find_by(code: resource.transient_fields[:color_code])
    #.     resource.record.color = color
    #.     resource.record.save!
    #.   end
    #. end
    #. ```
    attr_accessor :transient_fields

    private

    def assign_fields(data, mode)
      data = translator.translate(:request_up, data)

      unless data[:type] == self.class.type_name
        raise InvalidRequestDocumentContent.new(
          "Type of input resource must match the route",
          detail: "Expected type '#{self.class.type_name}'",
          pointer: "/data/type"
        )
      end

      assign_attributes(data.fetch(:attributes, {}), mode)
      assign_relationships(data.fetch(:relationships, {}), mode)
    end

    def assign_attributes(data_attributes, mode)
      unless data_attributes.is_a?(Hash)
        raise InvalidRequestDocumentContent.new("The attributes must be an object", pointer: "/data/attributes")
      end

      data_attributes.each do |json_name, value|
        attribute = self.class.attributes.find { |attr| attr.json_name.to_s == json_name.to_s }
        pointer = "/data/attributes/#{json_name}"

        raise UnknownField.new("No such attribute", pointer: pointer) unless attribute
        raise PermissionDenied.new("Cannot #{mode} attribute", pointer: pointer) unless attribute.settable_for?(mode)

        attribute.assign_in_resource(self, value)
      end
    end

    def assign_relationships(data_relationships, mode)
      unless data_relationships.is_a?(Hash)
        raise InvalidRequestDocumentContent.new("The relationships must be an object", pointer: "/data/relationships")
      end

      data_relationships.each do |json_name, value|
        relationship = self.class.relationships.find { |attr| attr.json_name.to_s == json_name.to_s }
        pointer = "/data/relationships/#{json_name}"

        raise UnknownField.new("No such relationship", pointer: pointer) unless relationship
        raise PermissionDenied.new("Cannot #{mode} relation", pointer: pointer) unless relationship.settable_for?(mode)

        relationship.assign_in_resource(self, value)
      end
    end
  end
end
