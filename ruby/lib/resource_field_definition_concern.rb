module SASC
  module ResourceFieldDefinitionConcern
    extend ActiveSupport::Concern

    class_methods do
      #% SASC::Resource.res_attribute(ruby_name, json_type, **kwargs)
      #. Configures an attribute of the resource
      #.
      #. * `ruby_name` The name of the attribute as an underscored symbol
      #. * `json_type` The JSON type of the value, e.g. `:string`, `:integer`, or `:array`
      #. * `settable_for:` An array containing `:update` and/or `:create`, indicating whether the attribute can be
      #.   modified during update and/or create actions. Defaults to permitting neither.
      #. ```ruby
      #. class DogResource < SASC::Resource
      #.   res_attribute :created_at, :string # Read-only
      #.   res_attribute :name, :string, settable_for: [:create, :update]  # Can be set on create and changed on update
      #.   res_attribute :breed, :string, settable_for: [:create] # Can be set on create but never changed after that
      #. end
      #. ```
      #. * `lookup:` If specified, configures how the value of the attribute can be read from the record. By
      #.   default, it tries to call a method on the record with the same name as the attribute. If you specify
      #.   a symbol here, it names a different method on the record to call. If you specify
      #.   a proc here, it will be passed the resource instance and should return the attribute value.
      #. ```ruby
      #. class DogResource < SASC::Resource
      #.   res_attribute :name, :string  # Calls `resource.record.name`
      #.   res_attribute :age, :integer, lookup: :age_in_years  # Calls `resource.record.age_in_years`
      #.   res_attribute :loud, :boolean, lookup: -> (res) { res.record.barkiness > 5 }
      #. end
      #. ```
      #. * `assign:` If specified, configures how the new value of the attribute can be written to the record. By
      #.   default, it tries to call a setter method on the record with the same name as the attribute, e.g.
      #.   setting an attribute named `foo` would attempt to call `:foo=' on the record. If you specify
      #.   a symbol here, it names a different method on the record to call with the new value. If you specify
      #.   a proc here, it will be passed the resource instance and the new value.
      #. ```ruby
      #. class DogResource < SASC::Resource
      #.   # An association that's presented by the API as though it were a regular attribute
      #.   res_attribute :favorite_toy_name, :string, :settable_for: [:create, :update],
      #.                 lookup: (res) -> { res.record.favorite_toy&.name },
      #.                 assign: (res, name) -> { res.record.favorite_toy = Toy.find_by(name: name) }
      #. end
      #. ```
      #. * `transient_assign:` If specified, setting the attribute will not cause any change to the record itself,
      #.   but instead the new value will be saved in `transient_fields` for later processing in `res_creatable`
      #.   and/or `res_updatable` blocks. You can specify `true` here to put the value directly in `transient_fields`,
      #.   or specify a proc to transform the value before it is put into `transient_fields`.
      #. ```ruby
      #. class DogResource < SASC::Resource
      #.   res_attribute :new_puppies, :string, :settable_for: [:update],
      #.                 hidden: true, transient_assign: true
      #.
      #.   res_updatable do |res|
      #.     if res.transient_fields.has_key?(:new_puppies)
      #.       res.transient_fields[:new_puppies].each do |puppy_name|
      #.         res.record.puppies.create!(name: puppy_name)
      #.       end
      #.     end
      #.
      #.     res.record.save!
      #.   end
      #. end
      #. ```
      #. * `hidden:` If specified as `true`, prevents the attribute from being rendered at all. This is useful for
      #.   write-only attributes and when `transient_assign` is set.
      #.
      #. Note that `id` is handled specially; you should *not* create an `id` attribute.
      def res_attribute(ruby_name, json_type, **kwargs)
        field = Attribute.new(ruby_name, json_type, **kwargs)
        assert_available_field_name! field
        self.attributes << field
      end

      #% SASC::Resource.res_has_one_relationship(ruby_name, resource_type, **kwargs)
      #. Configures a singular relationship on the resource
      #.
      #. * `ruby_name` The name of the relationship as an underscored symbol
      #. * `resource_type` The Resource class of the target resource
      #. * `settable_for:` An array containing `:update` and/or `:create`, indicating whether the relationship can be
      #.   modified during update and/or create actions. Defaults to permitting neither.
      #. ```ruby
      #. class DogResource < SASC::Resource
      #.    # Read-only
      #.   res_has_one_relationship :breed, DogBreedResource
      #.
      #.   # Can be set on create and changed on update
      #.   res_has_one_relationship :owner, UserResource, settable_target_scope: User.all,
      #.                            settable_for: [:create, :update]
      #.
      #.   # Can be set on create but never changed after that
      #.   res_has_one_relationship :mother, DogResource, settable_target_scope: Dog.all,
      #.                            settable_for: [:create]
      #. end
      #. ```
      #. * `settable_target_scope:` When setting a new value to this relationship, this scope is used to look up the
      #.   target resource by id. You must specify `settable_target_scope` if you specify `settable_for`. To allow
      #.   any target record, you can specify the target ActiveRecord class here. Or, you can specify a proc, which
      #.   is passed the resource and should return an ActiveRecord scope.
      #. ```ruby
      #. class DogResource < SASC::Resource
      #.   res_has_one_relationship :owner, UserResource, settable_for: [:create, :update],
      #.                            settable_target_scope: User.where(likes_dogs: true)
      #.
      #.   res_has_one_relationship :mother, DogResource, settable_for: [:create],
      #.                            settable_target_scope: (res) -> { Dog.possible_parents_for(res.record) }
      #. end
      #. ```
      #. * `lookup:` If specified, configures how the associated record can be found. By
      #.   default, it tries to call a method on the source record with the same name as the relationship. If you
      #.   specify a symbol here, it names a different method on the record to call. If you specify a proc here, it will
      #.   be passed the resource instance and should return the target record instance.
      #. ```ruby
      #. class DogResource < SASC::Resource
      #.   res_has_one_relationship :mother, DogResource # Calls `resource.record.mother`
      #.   res_has_one_relationship :father, DogResource, lookup: :dad  # Calls `resource.record.dad`
      #.   res_has_one_relationship :youngest_sibling, DogResource,
      #.                            lookup: -> (res) { res.record.siblings.order_by(:age).first }
      #. end
      #. ```
      #. * `assign:` If specified, configures how the new value of the relationship can be written to the record. By
      #.   default, it tries to call a setter method on the record with the same name as the relationship, e.g.
      #.   setting a relationship named `foo` would attempt to call `:foo=' on the record. If you specify
      #.   a symbol here, it names a different method on the record to call with the new value. If you specify
      #.   a proc here, it will be passed the resource instance and the new value.
      #. ```ruby
      #. class DogResource < SASC::Resource
      #.   # An association called `human` on the model, but the API presents it as `owner` for both reads and writes
      #.   res_has_one_relationship :owner, UserResource, settable_for: [:create, :update],
      #.                            settable_target_scope: User.all,
      #.                            lookup: :human, assign: :human=
      #.
      #.   res_has_one_relationship :food, FoodResource, settable_for: [:create, :update],
      #.                            settable_target_scope: Food.all,
      #.                            assign: (res, food) -> { res.context[:food_store].buy_for_dog(res.record, food) }
      #. end
      #. ```
      #. * `transient_assign:` If specified, setting the relationship will not cause any change to the record itself,
      #.   but instead the new value will be saved in `transient_fields` for later processing in `res_creatable`
      #.   and/or `res_updatable` blocks. You can specify `true` here to put the value directly in `transient_fields`,
      #.   or specify a proc to transform the value before it is put into `transient_fields`.
      #. ```ruby
      #. class DogResource < SASC::Resource
      #.   res_has_one_relationship :tennis_ball, TennisBall, :settable_for: [:update],
      #.                            hidden: true, transient_assign: true
      #.
      #.   res_updatable do |res|
      #.     if res.transient_fields.has_key?(:tennis_ball)
      #.       if res.record.object_held_in_mouth.present?
      #.         res.record.drop_it_drop_it_drop_it_okay_good_boy!
      #.       end
      #.       res.record.fetch(res.transient_fields[:tennis_ball])
      #.     end
      #.
      #.     res.record.save!
      #.   end
      #. end
      #. ```
      #. * `hidden:` If specified as `true`, prevents the relationship from being rendered at all. This is useful for
      #.   write-only relationships and for relationships with `transient_assign` set.
      def res_has_one_relationship(ruby_name, resource_type, **kwargs)
        field = HasOneRelationship.new(ruby_name, resource_type, **kwargs)
        assert_available_field_name! field
        self.relationships << field
      end

      #% SASC::Resource.res_has_many_relationship(ruby_name, resource_type, **kwargs)
      #. Configures a plural relationship on the resource
      #.
      #. Supports all the same arguments as `res_has_one_relationship` above, except that assignment is not (currently)
      #. supported, so you cannot provide `settable_for`, `settable_target_scope`, `assign`, or
      #. `transient_assign`.
      #.
      #. ```ruby
      #. class DogResource < SASC::Resource
      #.   res_has_many_relationship :chew_toys, ChewToyResource
      #. end
      #. ```
      def res_has_many_relationship(ruby_name, resource_type, **kwargs)
        field = HasManyRelationship.new(ruby_name, resource_type, **kwargs)
        assert_available_field_name! field
        self.relationships << field
      end
    end

    private

    class_methods do
      def assert_available_field_name!(proposed_field)
        { attributes: self.attributes, relationships: self.relationships }.each do |kind, fields|
          fields.each do |field|
            if field.json_name == proposed_field.json_name
              raise "Cannot add field '#{proposed_field.json_name}', name is already taken in #{kind} of this Resource"
            end
          end
        end
      end
    end

    included do
      private_class_method :assert_available_field_name!
    end
  end
end
