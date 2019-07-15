require 'rails_helper'

RSpec.describe SASC::Resource do
  # rubocop:disable RSpec/VerifiedDoubles

  it "derives a sasc type name from the class name using rails English pluralization" do
    resource_class = define_resource_class("CoolPersonResource")
    expect(resource_class.type_name).to eq("cool-people")
  end

  it "converts numeric ids to strings" do
    resource_class = define_resource_class("PersonResource")

    resource = resource_class.new(double("Person", id: 100))

    expect(resource.id).to eq("100")
  end

  it "defaults to current API version if unspecified in context" do
    fake_sasc_api_versions("1.0.0", "2.0.0", "2.1.3")
    resource_class = define_resource_class("PersonResource")

    resource = resource_class.new(double("Person"))

    expect(resource.context[:api_version]).to eq Semantic::Version.new("2.1.3")
  end

  describe "version conversion" do
    it "supports upgrading JSON input and downgrading JSON output with removal of fields" do
      fake_sasc_api_versions("1.0.0", "2.0.0")

      # Suppose that there was a :zipcode attribute in 1.0.0, but it was removed in 2.0.0
      translator_class = define_translator_class("PersonResourceTranslator") do
        def request_up(data)
          remove_zipcode(data) if version_below?("2.0.0")
        end

        def response_down(data)
          add_blank_zipcode(data) if version_below?("2.0.0")
        end

        private

        def add_blank_zipcode(data)
          data.deep_merge!(attributes: { zipcode: nil })
        end

        def remove_zipcode(data)
          data[:attributes]&.delete(:zipcode)
        end
      end

      resource_class = define_resource_class("PersonResource") do
        res_version_translation translator_class
        res_updatable
        res_attribute :name, :string, settable_for: [:update]
      end

      # A serialization at version 1.0.0 gets a nil zipcode attribute
      person = mock_active_record("Person", id: 1, name: "John Doe")
      v1_resource = resource_class.new(person, api_version: "1.0.0".to_version)
      expect(v1_resource.as_json).to eq(
        id: "1",
        type: "people",
        attributes: {
          name: "John Doe",
          zipcode: nil,
        },
        relationships: {}
      )

      # An update at version 1.0.0 can supply a zipcode, but the zipcode is not sent to the record
      person = mock_active_record("Person", id: 1, name: "John Doe")
      v1_resource = resource_class.new(person, api_version: "1.0.0".to_version)
      v1_resource.update_with_sasc_data!(
        id: "1",
        type: "people",
        attributes: { name: "Joe Schmoe", zipcode: 123 }
      )
      expect(person).to have_received(:name=).with("Joe Schmoe")
      # The person mock does not have a zipcode attribute, so if the resource incorrectly tries to set zipcode
      # on person above, then an error will be raised.

      # A serialization at version 2.0.0 has no zipcode attribute
      person = mock_active_record("Person", id: 1, name: "John Doe")
      v2_resource = resource_class.new(person, api_version: "2.0.0".to_version)
      expect(v2_resource.as_json).to eq(
        id: "1",
        type: "people",
        attributes: {
          name: "John Doe",
        },
        relationships: {}
      )

      # An update at version 2.0.0 does not need to give a zipcode, and gets an error if it tries
      person = mock_active_record("Person", id: 1, name: "John Doe")
      v2_resource = resource_class.new(person, api_version: "2.0.0".to_version)
      v2_resource.update_with_sasc_data!(id: "1", type: "people", attributes: { name: "Alice Eve" })
      expect(person).to have_received(:name=).with("Alice Eve")
      expect {
        v2_resource.update_with_sasc_data!(
          id: "1",
          type: "people",
          attributes: { name: "Alice Eve", zipcode: 123 }
        )
      }.to raise_error(SASC::Errors::UnknownField)
    end

    it "supports upgrading JSON input and downgrading JSON output with renamed fields" do
      fake_sasc_api_versions("1.0.0", "2.0.0")

      # Suppose that the attribute `full_name` in 1.0.0 was shortened to just `name` in 2.0.0
      translator_class = define_translator_class("PersonResourceTranslator") do
        def request_up(data)
          rename_full_name_to_name(data) if version_below?("2.0.0")
        end

        def response_down(data)
          rename_name_to_full_name(data) if version_below?("2.0.0")
        end

        private

        def rename_name_to_full_name(data)
          data[:attributes][:fullName] = data[:attributes].delete(:name) if data[:attributes]&.key?(:name)
        end

        def rename_full_name_to_name(data)
          data[:attributes][:name] = data[:attributes].delete(:fullName) if data[:attributes]&.key?(:fullName)
        end
      end

      resource_class = define_resource_class("PersonResource") do
        res_version_translation translator_class
        res_updatable
        res_attribute :name, :string, settable_for: [:update]
      end

      # A serialization at version 1.0.0 gets a fullName attribute
      person = mock_active_record("Person", id: 1, name: "John Doe")
      v1_resource = resource_class.new(person, api_version: "1.0.0".to_version)
      expect(v1_resource.as_json).to eq(
        id: "1",
        type: "people",
        attributes: { fullName: "John Doe" },
        relationships: {}
      )

      # A serialization at version 2.0.0 gets a name attribute
      person = mock_active_record("Person", id: 1, name: "John Doe")
      v2_resource = resource_class.new(person, api_version: "2.0.0".to_version)
      expect(v2_resource.as_json).to eq(
        id: "1",
        type: "people",
        attributes: { name: "John Doe" },
        relationships: {}
      )

      # An update at version 1.0.0 can supply a fullName, and it becomes the record's name
      person = mock_active_record("Person", id: 1, name: "John Doe")
      v1_resource = resource_class.new(person, api_version: "1.0.0".to_version)
      v1_resource.update_with_sasc_data!(id: "1", type: "people", attributes: { fullName: "Joe Schmoe" })
      expect(person).to have_received(:name=).with("Joe Schmoe")

      # An update at version 2.0.0 does not have to supply a fullName, and gets an error if it tries
      person = mock_active_record("Person", id: 1, name: "John Doe")
      v2_resource = resource_class.new(person, api_version: "2.0.0".to_version)
      v2_resource.update_with_sasc_data!(id: "1", type: "people", attributes: { name: "Alice Eve" })
      expect(person).to have_received(:name=).with("Alice Eve")
      expect {
        v2_resource.update_with_sasc_data!(id: "1", type: "people", attributes: { fullName: "Alice Eve" })
      }.to raise_error(SASC::Errors::UnknownField)
    end
  end

  it "returns a SASC resource object when calling #as_json" do
    person_resource_class = define_resource_class("PersonResource")

    resource_class = define_resource_class("ProtagonistResource") do
      def lookup_initials
        [record.given_name, record.surname].map(&:first).join
      end

      def lookup_best_friend
        record.friends.first
      end

      res_attribute :initials, :string, lookup: ->(resource) { resource.lookup_initials }
      res_attribute :personal_name, :string, lookup: :given_name
      res_attribute :surname, :string, json_name: "familyName"

      res_has_many_relationship :friends, person_resource_class, json_name: "pals"
      res_has_one_relationship :best_friend, person_resource_class, lookup: ->(resource) { resource.lookup_best_friend }
      res_has_one_relationship :maternal_parent, person_resource_class, lookup: :mother
    end

    person_resource = resource_class.new(
      double("Protagonist", id: 100, given_name: "Ursula", surname: "LeGuin",
                            friends: [double("Person", id: 200), double("Person", id: 300), double("Person", id: 400)],
                            mother: double("Person", id: 99))
    )

    expect(person_resource.as_json).to eq(
      id: "100",
      type: "protagonists",
      attributes: {
        personalName: "Ursula",
        familyName: "LeGuin",
        initials: "UL",
      },
      relationships: {
        pals: {
          data: [
            { type: "people", id: "200" },
            { type: "people", id: "300" },
            { type: "people", id: "400" },
          ],
        },
        bestFriend: {
          data: { type: "people", id: "200" },
        },
        maternalParent: {
          data: { type: "people", id: "99" },
        },
      }
    )
  end

  it "returns nil for empty has one relationships" do
    parent_resource_class = define_resource_class("ParentResource")
    person_resource_class = define_resource_class("PersonResource") do
      res_has_one_relationship :maternal_parent, parent_resource_class, lookup: :mother
    end
    person_resource = person_resource_class.new(double("Person", id: 123, mother: nil))

    expect(person_resource.as_json[:relationships][:maternalParent][:data]).to be_nil
  end

  it "returns empty array for empty has_many relationship" do
    friend_resource_class = define_resource_class("FriendResource")
    person_resource_class = define_resource_class("PersonResource") do
      res_has_many_relationship :friends, friend_resource_class
    end
    person_resource = person_resource_class.new(double("Person", id: 123, friends: []))

    expect(person_resource.as_json[:relationships][:friends][:data]).to eq([])
  end

  it "raises UnknownField on create with a non-existant attribute" do
    person_resource_class = define_resource_class("PersonResource") do
      res_creatable
      res_attribute :name, :string, settable_for: [:create]
    end
    rec = double("Person", "name=": true, "save!": true)

    expect {
      person_resource_class.create_with_sasc_data!(rec, { type: "people", attributes: { name: "Joe", foo: "bar" } }, {})
    }.to raise_error(SASC::Errors::UnknownField) { |err| expect(err.pointer).to eq("/data/attributes/foo") }
  end

  it "raises UnknownField on update with a non-existant attribute" do
    person_resource_class = define_resource_class("PersonResource") do
      res_updatable
      res_attribute :name, :string, settable_for: [:update]
    end
    rec = double("Person", "id": 1234, "name=": true, "update!": true, "save!": true)
    resource = person_resource_class.new(rec, {})

    expect {
      resource.update_with_sasc_data!(id: "1234", type: "people", attributes: { name: "Joe", foo: "bar" })
    }.to raise_error(SASC::Errors::UnknownField) { |err| expect(err.pointer).to eq("/data/attributes/foo") }
  end

  describe "validation error handling" do
    def object_with_validation_errors(attribute, detail: "", error_msg: "")
      errors = instance_double(ActiveModel::Errors)
      allow(errors).to receive(:keys).and_return([attribute])
      allow(errors).to receive(:details).and_return(attribute => [{ error: detail }])
      allow(errors).to receive(:full_messages).and_return([error_msg])
      allow(errors).to receive(:full_messages_for).and_return(errors.full_messages)

      record_class = double("MyRecordClass")
      allow(record_class).to receive(:i18n_scope).and_return(:activerecord)
      double("MyRecord", class: record_class, errors: errors, id: 1234)
    end

    def invalid_active_record(invalid_attribute:, err_msg:, err_detail: "")
      record = object_with_validation_errors(invalid_attribute, detail: err_detail, error_msg: err_msg)
      allow(record).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(record))
      record
    end

    def invalid_active_model(invalid_attribute:, err_msg:, err_detail: "")
      record = object_with_validation_errors(invalid_attribute, detail: err_detail, error_msg: err_msg)
      allow(record).to receive(:save!).and_raise(ActiveModel::ValidationError.new(record))
      record
    end

    # An ActiveRecord that raises RecordInvalid even though it has no validation errors
    #rubocop:disable AbcSize
    def mysteriously_invalid_active_record
      errors = instance_double(ActiveModel::Errors)
      allow(errors).to receive(:keys).and_return([])
      allow(errors).to receive(:details).and_return({})
      allow(errors).to receive(:full_messages).and_return([])
      allow(errors).to receive(:full_messages_for).and_return([])

      record_class = double("MyRecordClass")
      allow(record_class).to receive(:i18n_scope).and_return(:activerecord)
      record = double("MyRecord", class: record_class, errors: errors, id: 1234)

      allow(record).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(record))
      record
    end

    it "raises InvalidFieldValue when there is an invalid record on create" do
      person_resource_class = define_resource_class("PersonResource") do
        res_creatable
        res_attribute :surname, :string, json_name: "familyName"
      end

      person = invalid_active_record invalid_attribute: :surname, err_msg:  "This data is totally absurd"

      expect { person_resource_class.create_with_sasc_data!(person, { type: "people" }, {}) }
        .to raise_error(SASC::Errors::BatchError) do |batch_err|
        expect(batch_err.errors.length).to be 1
        err = batch_err.errors.first
        expect(err.subcode).to be_nil
        expect(err.detail).to eq("This data is totally absurd")
        expect(err.pointer).to eq("/data/attributes/familyName")
      end
    end

    it "raises InvalidFieldValue when there is an invalid record on update" do
      resource_class = define_resource_class("PersonResource") do
        res_updatable
        res_attribute :surname, :string, json_name: "familyName"
      end

      person = invalid_active_record invalid_attribute: :surname, err_msg:  "This data is totally absurd"

      person_resource = resource_class.new(person, {})

      expect { person_resource.update_with_sasc_data!(id: person.id.to_s, type: "people") }
        .to raise_error(SASC::Errors::BatchError) do |batch_err|
        expect(batch_err.errors.length).to be 1
        err = batch_err.errors.first
        expect(err.subcode).to be_nil
        expect(err.detail).to eq("This data is totally absurd")
        expect(err.pointer).to eq("/data/attributes/familyName")
      end
    end

    it "raises InvalidFieldValue with a subcode when a validation error has a symbol in error detail on create" do
      resource_class = define_resource_class("PersonResource") do
        res_creatable
        res_attribute :surname, :string, json_name: "familyName"
      end

      person = invalid_active_record invalid_attribute: :surname,
                                     err_msg: "This data is totally absurd",
                                     err_detail: :absurdity_error_level_three

      expect { resource_class.create_with_sasc_data!(person, { type: "people" }, {}) }
        .to raise_error(SASC::Errors::BatchError) do |batch_err|
        expect(batch_err.errors.length).to be 1
        err = batch_err.errors.first
        expect(err.subcode).to eq("ABSURDITY_ERROR_LEVEL_THREE")
        expect(err.detail).to eq("This data is totally absurd")
        expect(err.pointer).to eq("/data/attributes/familyName")
      end
    end

    it "raises InvalidFieldValue with a subcode when a validation error has a symbol in error detail on update" do
      resource_class = define_resource_class("PersonResource") do
        res_updatable
        res_attribute :surname, :string, json_name: "familyName"
      end

      person = invalid_active_record invalid_attribute: :surname,
                                     err_msg: "This data is totally absurd",
                                     err_detail: :absurdity_error_level_three

      person_resource = resource_class.new(person, {})

      expect { person_resource.update_with_sasc_data!(id: "1234", type: "people") }
        .to raise_error(SASC::Errors::BatchError) do |batch_err|
        expect(batch_err.errors.length).to be 1
        err = batch_err.errors.first
        expect(err.subcode).to eq("ABSURDITY_ERROR_LEVEL_THREE")
        expect(err.detail).to eq("This data is totally absurd")
        expect(err.pointer).to eq("/data/attributes/familyName")
      end
    end

    it "raises InvalidFieldValue with ActiveModel validation error is raised on create" do
      resource_class = define_resource_class("PersonResource") do
        res_creatable
        res_attribute :surname, :string, json_name: "familyName"
      end

      person = invalid_active_model invalid_attribute: :surname, err_msg: "This data is totally absurd"

      expect { resource_class.create_with_sasc_data!(person, { type: "people" }, {}) }
        .to raise_error(SASC::Errors::BatchError) do |batch_err|
        expect(batch_err.errors.length).to be 1
        err = batch_err.errors.first
        expect(err.subcode).to be_nil
        expect(err.detail).to eq("This data is totally absurd")
        expect(err.pointer).to eq("/data/attributes/familyName")
      end
    end

    it "raises InvalidFieldValue when ActiveModel validation error is raised on update" do
      resource_class = define_resource_class("PersonResource") do
        res_updatable
        res_attribute :surname, :string, json_name: "familyName"
      end

      person = invalid_active_model invalid_attribute: :surname, err_msg: "This data is totally absurd"

      person_resource = resource_class.new(person, {})

      expect { person_resource.update_with_sasc_data!(id: "1234", type: "people") }
        .to raise_error(SASC::Errors::BatchError) do |batch_err|
        expect(batch_err.errors.length).to be 1
        err = batch_err.errors.first
        expect(err.subcode).to be_nil
        expect(err.detail).to eq("This data is totally absurd")
        expect(err.pointer).to eq("/data/attributes/familyName")
      end
    end

    it "raises generic InvalidFieldValue when a validation error is raised on create without any invalid fields" do
      person_resource_class = define_resource_class("PersonResource") do
        res_creatable
        res_attribute :surname, :string, json_name: "familyName"
      end

      person = mysteriously_invalid_active_record

      expect { person_resource_class.create_with_sasc_data!(person, { type: "people" }, {}) }
        .to raise_error(SASC::Errors::BatchError) do |batch_err|
        expect(batch_err.errors.length).to be 1
        err = batch_err.errors.first
        expect(err.subcode).to be_nil
        expect(err.title).to eq "Resource is not valid"
        expect(err.pointer).to be_nil
      end
    end

    it "raises generic InvalidFieldValue when a validation error is raised on update without any invalid fields" do
      resource_class = define_resource_class("PersonResource") do
        res_updatable
        res_attribute :surname, :string, json_name: "familyName"
      end

      person = mysteriously_invalid_active_record

      person_resource = resource_class.new(person, {})

      expect { person_resource.update_with_sasc_data!(id: person.id.to_s, type: "people") }
        .to raise_error(SASC::Errors::BatchError) do |batch_err|
        expect(batch_err.errors.length).to be 1
        err = batch_err.errors.first
        expect(err.subcode).to be_nil
        expect(err.title).to eq "Resource is not valid"
        expect(err.pointer).to be_nil
      end
    end
  end

  it "raises error when attempting to create a resource without a type" do
    resource_class = define_resource_class("PersonResource") { res_creatable }
    expect { resource_class.create_with_sasc_data!(double("Person"), {}, {}) }
      .to raise_error(SASC::Errors::InvalidRequestDocumentContent) do |err|
      expect(err.pointer).to eq("/data/type")
    end
  end

  it "raises error when attempting to update a resource without a type" do
    resource_class = define_resource_class("PersonResource") { res_updatable }
    person_resource = resource_class.new(double("Person", id: 1234))
    expect { person_resource.update_with_sasc_data!(id: "1234") }
      .to raise_error(SASC::Errors::InvalidRequestDocumentContent) do |err|
      expect(err.pointer).to eq("/data/type")
    end
  end

  it "raises error when attempting to create a resource with the wrong type" do
    resource_class = define_resource_class("PersonResource") { res_creatable }
    expect { resource_class.create_with_sasc_data!(double("Person"), { type: "penguins" }, {}) }
      .to raise_error(SASC::Errors::InvalidRequestDocumentContent) do |err|
      expect(err.pointer).to eq("/data/type")
    end
  end

  it "raises error when attempting to update a resource with the wrong type" do
    resource_class = define_resource_class("PersonResource") { res_updatable }
    person_resource = resource_class.new(double("Person", id: 1234))
    expect { person_resource.update_with_sasc_data!(id: "1234", type: "penguins") }
      .to raise_error(SASC::Errors::InvalidRequestDocumentContent) do |err|
      expect(err.pointer).to eq("/data/type")
    end
  end

  it "sets attribute to null in create" do
    resource_class = define_resource_class("PersonResource") do
      res_creatable
      res_attribute :middle_name, :string, settable_for: [:create]
    end

    person = double("Person", "save!": true, "middle_name=": true)

    resource_class.create_with_sasc_data!(person, { type: "people", attributes: { middleName: nil } }, {})

    expect(person).to have_received(:middle_name=).with(nil)
    expect(person).to have_received(:save!)
  end

  it "sets attribute to null in update" do
    resource_class = define_resource_class("PersonResource") do
      res_updatable
      res_attribute :middle_name, :string, settable_for: [:update]
    end

    person = double("Person", id: 1234, "save!": true, "middle_name=": true)

    resource_class.new(person).update_with_sasc_data!(id: "1234", type: "people", attributes: { middleName: nil })

    expect(person).to have_received(:middle_name=).with(nil)
    expect(person).to have_received(:save!)
  end

  it "raises PermissionDenied when setting non-settable attribute in create" do
    resource_class = define_resource_class("PersonResource") do
      res_creatable
      res_attribute :name, :string, settable_for: [:update]
    end

    expect {
      resource_class.create_with_sasc_data!(double("Person"),
                                            { type: "people", attributes: { name: "Joe" } }, {})
    }
      .to raise_error(SASC::Errors::PermissionDenied) { |err| expect(err.pointer).to eq("/data/attributes/name") }
  end

  it "raises PermissionDenied when setting non-settable attribute in update" do
    resource_class = define_resource_class("PersonResource") do
      res_updatable
      res_attribute :name, :string, settable_for: [:create]
    end

    resource = resource_class.new(double("Person", id: 1234))

    expect { resource.update_with_sasc_data!(id: "1234", type: "people", attributes: { name: "Joe" }) }
      .to raise_error(SASC::Errors::PermissionDenied) do |err|
      expect(err.pointer).to eq("/data/attributes/name")
    end
  end

  it "raises error when setting non-existent relationship in create" do
    resource_class = define_resource_class("PersonResource") do
      res_creatable
    end

    hash = { type: "people", relationships: { unicorn: { data: { type: "unicorns", id: "42" } } } }

    expect { resource_class.create_with_sasc_data!(double("Person"), hash, {}) }
      .to raise_error(SASC::Errors::UnknownField) do |err|
      expect(err.pointer).to eq("/data/relationships/unicorn")
    end
  end

  it "raises error when setting non-existent relationship in update" do
    resource_class = define_resource_class("PersonResource") do
      res_updatable
    end

    hash = { id: "37", type: "people", relationships: { unicorn: { data: { type: "unicorns", id: "42" } } } }
    expect { resource_class.new(double("Person", id: 37)).update_with_sasc_data!(hash) }
      .to raise_error(SASC::Errors::UnknownField) do |err|
      expect(err.pointer).to eq("/data/relationships/unicorn")
    end
  end

  it "raises error when setting non-settable relationship in create" do
    dentist_resource_class = define_resource_class("DentistResource")
    resource_class = define_resource_class("PersonResource") do
      res_creatable
      res_has_one_relationship :dentist, dentist_resource_class
    end

    hash = { type: "people", relationships: { dentist: { data: { type: "dentists", id: "42" } } } }
    expect { resource_class.create_with_sasc_data!(double("Person"), hash, {}) }
      .to raise_error(SASC::Errors::PermissionDenied) do |err|
      expect(err.pointer).to eq("/data/relationships/dentist")
    end
  end

  it "raises error when setting non-settable relationship in update" do
    dentist_resource_class = define_resource_class("DentistResource")
    resource_class = define_resource_class("PersonResource") do
      res_updatable
      res_has_one_relationship :dentist, dentist_resource_class
    end

    hash = { id: "37", type: "people", relationships: { dentist: { data: { type: "dentists", id: "42" } } } }
    expect { resource_class.new(double("Person", id: 37)).update_with_sasc_data!(hash) }
      .to raise_error(SASC::Errors::PermissionDenied) do |err|
      expect(err.pointer).to eq("/data/relationships/dentist")
    end
  end

  it "raises error when setting invalid relationship in create" do
    dentist_resource_class = define_resource_class("DentistResource")
    dentist_scope = double("Scope")
    resource_class = define_resource_class("PersonResource") do
      res_creatable
      res_has_one_relationship :dentist, dentist_resource_class, settable_for: [:create], settable_target_scope: dentist_scope
    end

    expect {
      resource_class.create_with_sasc_data!(
        double("Person"),
        # The client is providing an array of dentists, but it's not a has-many relationship
        { type: "people", relationships: { dentist: { data: [{ type: "dentists", id: "42" }] } } },
        {}
      )
    }
      .to raise_error(SASC::Errors::InvalidFieldValue) { |err| expect(err.pointer).to eq("/data/relationships/dentist/data") }
  end

  it "raises error when setting invalid relationship in update" do
    dentist_resource_class = define_resource_class("DentistResource")
    dentist_scope = double("Scope")
    resource_class = define_resource_class("PersonResource") do
      res_updatable
      res_has_one_relationship :dentist, dentist_resource_class, settable_for: [:update], settable_target_scope: dentist_scope
    end

    expect {
      resource_class.new(double("Person", id: 37)).update_with_sasc_data!(
        # The client is providing an array of dentists, but it's not a has-many relationship
        id: "37", type: "people", relationships: { dentist: { data: [{ type: "dentists", id: "42" }] } }
      )
    }
      .to raise_error(SASC::Errors::InvalidFieldValue) { |err| expect(err.pointer).to eq("/data/relationships/dentist/data") }
  end

  it "raises error when setting relationship with missing id in create" do
    dentist_resource_class = define_resource_class("DentistResource")
    dentist_scope = double("Scope")
    resource_class = define_resource_class("PersonResource") do
      res_creatable
      res_has_one_relationship :dentist, dentist_resource_class, settable_for: [:create], settable_target_scope: dentist_scope
    end

    expect {
      resource_class.create_with_sasc_data!(
        double("Person"),
        { type: "people", relationships: { dentist: { data: { type: "dentists" } } } },
        {}
      )
    }
      .to raise_error(SASC::Errors::InvalidFieldValue) { |err| expect(err.pointer).to eq("/data/relationships/dentist/data/id") }
  end

  it "raises error when setting relationship with missing id in update" do
    dentist_resource_class = define_resource_class("DentistResource")
    dentist_scope = double("Scope")
    resource_class = define_resource_class("PersonResource") do
      res_updatable
      res_has_one_relationship :dentist, dentist_resource_class, settable_for: [:update], settable_target_scope: dentist_scope
    end

    expect {
      resource_class.new(double("Person", id: 37)).update_with_sasc_data!(
        id: "37", type: "people", relationships: { dentist: { data: { type: "dentists" } } }
      )
    }
      .to raise_error(SASC::Errors::InvalidFieldValue) { |err| expect(err.pointer).to eq("/data/relationships/dentist/data/id") }
  end

  it "raises error when setting relationship with wrong type in create" do
    dentist_resource_class = define_resource_class("DentistResource")
    dentist_scope = double("Scope")
    resource_class = define_resource_class("PersonResource") do
      res_creatable
      res_has_one_relationship :dentist, dentist_resource_class, settable_for: [:create], settable_target_scope: dentist_scope
    end

    expect {
      resource_class.create_with_sasc_data!(double("Person"),
                                            { type: "people", relationships: { dentist: { data: { id: "1234", type: "podiatrists" } } } }, {})
    }
      .to raise_error(SASC::Errors::InvalidFieldValue) { |err| expect(err.pointer).to eq("/data/relationships/dentist/data/type") }
  end

  it "raises error when setting relationship with wrong type in update" do
    dentist_resource_class = define_resource_class("DentistResource")
    dentist_scope = double("Scope")
    resource_class = define_resource_class("PersonResource") do
      res_updatable
      res_has_one_relationship :dentist, dentist_resource_class, settable_for: [:update], settable_target_scope: dentist_scope
    end

    expect {
      resource_class.new(double("Person", id: 37)).update_with_sasc_data!(
        id: "37", type: "people", relationships: { dentist: { data: { id: "1234", type: "podiatrists" } } }
      )
    }
      .to raise_error(SASC::Errors::InvalidFieldValue) { |err| expect(err.pointer).to eq("/data/relationships/dentist/data/type") }
  end

  # TODO: test custom implementation of create/update/destroy functions

  it "creates with sasc data" do
    dentist_resource_class = define_resource_class("DentistResource")
    dentist = double("Dentist")
    dentist_scope = double("Scope", find: dentist)

    resource_class = define_resource_class("PersonResource") do
      res_creatable
      res_attribute :name, :string, settable_for: [:create]
      res_has_one_relationship :dentist, dentist_resource_class, settable_for: [:create],
                                                                 settable_target_scope: dentist_scope
    end

    person = double("Person")
    allow(person).to receive(:name=)
    allow(person).to receive(:dentist=)
    allow(person).to receive(:save!)

    resource_class.create_with_sasc_data!(
      person,
      { type: "people",
        relationships: { dentist: { data: { id: "1234", type: "dentists" } } },
        attributes: { name: "Robert" }, },
      {}
    )

    expect(person).to have_received(:name=).with("Robert")
    expect(person).to have_received(:dentist=).with(dentist)
    expect(dentist_scope).to have_received(:find).with("1234")
    expect(person).to have_received(:save!)
  end

  it "updates with sasc data" do
    dentist_resource_class = define_resource_class("DentistResource")
    dentist = double("Dentist")
    dentist_scope = double("Scope", find: dentist)

    resource_class = define_resource_class("PersonResource") do
      res_updatable
      res_attribute :name, :string, settable_for: [:update]
      res_has_one_relationship :dentist, dentist_resource_class, settable_for: [:update],
                                                                 settable_target_scope: dentist_scope
    end

    person = double("Person")
    allow(person).to receive(:name=)
    allow(person).to receive(:id).and_return(1234)
    allow(person).to receive(:dentist=)
    allow(person).to receive(:save!)

    resource_class.new(person).update_with_sasc_data!(
      type: "people",
      id: "1234",
      relationships: { dentist: { data: { id: "1234", type: "dentists" } } },
      attributes: { name: "Robert" }
    )

    expect(person).to have_received(:name=).with("Robert")
    expect(person).to have_received(:dentist=).with(dentist)
    expect(dentist_scope).to have_received(:find).with("1234")
    expect(person).to have_received(:save!)
  end

  it "raises invalid request document content when creating with id" do
    resource_class = define_resource_class("PersonResource") { res_creatable }

    expect { resource_class.create_with_sasc_data!(double("Person"), { type: "people", id: "1234" }, {}) }
      .to raise_error(SASC::Errors::InvalidRequestDocumentContent) do |err|
      expect(err.pointer).to eq("/data/id")
    end
  end

  it "raises invalid request document content when updating without id" do
    resource_class = define_resource_class("PersonResource") { res_updatable }

    expect { resource_class.new(double("Person")).update_with_sasc_data!(type: "people") }
      .to raise_error(SASC::Errors::InvalidRequestDocumentContent) do |err|
      expect(err.pointer).to eq("/data/id")
    end
  end

  it "raises invalid request document content when updating with wrong id" do
    resource_class = define_resource_class("PersonResource") { res_updatable }

    expect { resource_class.new(double("Person", id: "1234")).update_with_sasc_data!(type: "people", id: "1235") }
      .to raise_error(SASC::Errors::InvalidRequestDocumentContent) do |err|
      expect(err.pointer).to eq("/data/id")
    end
  end

  it "destroys a resource" do
    resource_class = define_resource_class("PersonResource") { res_destroyable }
    person = double("Person")
    allow(person).to receive(:destroy!)

    resource_class.new(person).destroy!

    expect(person).to have_received(:destroy!)
  end

  it "can deeply camelize attributes" do
    resource_class = define_resource_class("PersonResource") do
      res_attribute :friends, :array, deep_camelize_keys: true
      res_attribute :fun_facts, :object, deep_camelize_keys: true
    end

    person_record = mock_active_record(
      "Person",
      id: 1,
      friends: [{ name: "Bob", likes_to_eat: [{ favorite: "Burgers", second_favorite: "Bread" },
                                              { hates: "anchovies" },], },
                { name: "Ben", likes_to_eat: [{ favorite: "Salads", second_favorite: "Cheese" },
                                              { hates: "Coffee" },], },],
      fun_facts: { facts: [{ first_fact: "factoid1", other_facts: [{ second_fact: "factoid2" }] }] }
    )

    expect(resource_class.new(person_record).as_json).to eq(
      id: "1",
      type: "people",
      attributes: {
        friends: [{ name: "Bob", likesToEat: [{ favorite: "Burgers", secondFavorite: "Bread" },
                                              { hates: "anchovies" },], },
                  { name: "Ben", likesToEat: [{ favorite: "Salads", secondFavorite: "Cheese" },
                                              { hates: "Coffee" },], },],
        funFacts: { facts: [{ firstFact: "factoid1", otherFacts: [{ secondFact: "factoid2" }] }] },
      },
      relationships: {}
    )
  end

  describe "using real active record" do
    before do
      # Before creating end any open transactions
      reset_db_conn
      create_db
    end

    after do
      drop_db
    end

    it "actually creates an active record" do
      with_db do |conn|
        # given
        pet_class = define_pet_model(conn)
        person_class = define_person_model_with_pet(conn, pet_class)

        pet_resource_class = define_resource_class("PetResource")
        person_resource_class = define_resource_class("PersonResource") do
          res_attribute :name, :string, settable_for: [:create]
          res_creatable
          res_has_one_relationship :pet, pet_resource_class,
                                   settable_for: [:create],
                                   settable_target_scope: pet_class.all
        end

        pet = pet_class.create!

        # when
        person_resource_class.create_with_sasc_data!(
          person_class.new,
          { type: "people",
            attributes: { name: "Ben" },
            relationships: { pet: { data: { type: "pets", id: pet.id.to_s } } }, }, {}
        )

        # then
        expect(person_class.first.name).to eq("Ben")
        expect(person_class.first.pet).to eq(pet)
      end
    end

    it "actually updates an active record" do
      with_db do |conn|
        # given
        pet_class = define_pet_model(conn)
        person_class = define_person_model_with_pet(conn, pet_class)

        pet_resource_class = define_resource_class("PetResource")
        person_resource_class = define_resource_class("PersonResource") do
          res_attribute :name, :string, settable_for: [:update]
          res_updatable
          res_has_one_relationship :pet, pet_resource_class,
                                   settable_for: [:update],
                                   settable_target_scope: pet_class.all
        end

        person = person_class.create(name: "Ben", pet: pet_class.create!)

        dog = pet_class.create!

        # when
        person_resource_class.new(person, {}).update_with_sasc_data!(
          type: "people",
          id: person.id.to_s,
          attributes: { name: "David" },
          relationships: { pet: { data: { type: "pets", id: dog.id.to_s } } }
        )

        # then
        expect(person_class.first.name).to eq("David")
        expect(person_class.first.pet).to eq(dog)
      end
    end

    it "actually destroys an active record" do
      with_db do |conn|
        # given
        pet_class = define_pet_model(conn)

        pet_resource_class = define_resource_class("PetResource") do
          res_destroyable
        end

        pet = pet_class.create!

        # when
        pet_resource_class.new(pet, {}).destroy!

        # then
        expect(pet_class.find_by(id: pet.id)).to be nil
      end
    end

    def with_db
      conn = connect_to_db
      begin
        yield(conn)
      ensure
        reset_db_conn
      end
    end

    def connect_to_db
      ActiveRecord::Base.establish_connection(adapter: "postgresql", database: "test_resource_spec")
      ActiveRecord::Base.connection
    end

    def create_db
      ActiveRecord::Base.connection.create_database("test_resource_spec")
    end

    def drop_db
      ActiveRecord::Base.connection.drop_database("test_resource_spec")
    end

    def reset_db_conn
      ActiveRecord::Base.establish_connection
    end

    def define_pet_model(conn)
      create_table(conn, :pets)
      define_active_record_class("Pet")
    end

    def define_person_model_with_pet(conn, pet_class)
      create_table(conn, :people) do |t|
        t.column :name, :string, limit: 60
        t.column :pet_id, :int
      end
      define_active_record_class("Person") do
        belongs_to :pet, anonymous_class: pet_class
      end
    end
  end

  def mock_active_record(class_name, **kwargs)
    record = double(class_name)

    kwargs.each do |key, val|
      allow(record).to receive(key).and_return(val)
      allow(record).to receive(:"#{key}=")
    end
    allow(record).to receive(:save!)
    allow(record).to receive(:update!)

    record
  end

  def define_resource_class(class_name, &block)
    define_anonymous_class(SASC::Resource, class_name, &block)
  end

  def define_translator_class(class_name, &block)
    define_anonymous_class(Glossator::Translator, class_name, &block)
  end

  def fake_sasc_api_versions(*versions)
    version_map = versions.map { |v| [v.to_version, { description: "Foo" }] }.to_h
    allow(SASC::Versioning).to receive(:versions).and_return(version_map)
    allow(SASC::Versioning).to receive(:latest_version).and_return(version_map.keys.sort.last)
  end
end
