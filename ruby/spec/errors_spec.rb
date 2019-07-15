require "rails_helper"

RSpec.describe SASC::Errors do
  describe SASC::Errors::BatchError do
    describe "#http_status_code" do
      it "returns :internal_server_error if any sub-errors have that http status code" do
        batch = SASC::Errors::BatchError.new([
                                               SASC::Errors::InvalidFieldValue.new,
                                               SASC::Errors::InternalError.new(RuntimeError.new("ACK")),
                                               SASC::Errors::BadAcceptHeader.new,
                                             ])
        expect(batch.http_status_code).to eq :internal_server_error
      end

      it "returns :bad_request if sub-errors have heterogenous 400-level status codes" do
        batch = SASC::Errors::BatchError.new([
                                               SASC::Errors::InvalidFieldValue.new,
                                               SASC::Errors::BadAcceptHeader.new,
                                             ])
        expect(batch.http_status_code).to eq :bad_request
      end

      it "returns sub-errors' status code if they all have the same status code" do
        batch = SASC::Errors::BatchError.new([
                                               SASC::Errors::InvalidFieldValue.new,
                                               SASC::Errors::UnknownQueryParameter.new,
                                             ])
        expect(batch.http_status_code).to eq :bad_request
      end
    end

    describe "#as_json" do
      it "returns an array of the nested errors' json objects" do
        e1 = SASC::Errors::InvalidFieldValue.new("Oh no!")
        e2 = SASC::Errors::UnknownQueryParameter.new("No way!")
        batch = SASC::Errors::BatchError.new([e1, e2])
        expect(batch.as_json).to eq([e1.as_json, e2.as_json])
      end

      it "deeply flattens nested BatchErrors" do
        e1 = SASC::Errors::InvalidFieldValue.new("Oh no!")
        e2 = SASC::Errors::UnknownQueryParameter.new("No way!")
        e3 = SASC::Errors::BatchError.new([
                                            SASC::Errors::InvalidFieldValue.new("Ack!"),
                                            SASC::Errors::BadAcceptHeader.new("Urgh!"),
                                          ])
        batch = SASC::Errors::BatchError.new([e1, e2, e3])
        expect(batch.as_json).to eq([e1.as_json, e2.as_json, e3.as_json].flatten)
      end
    end
  end

  describe "#with_validation_error_reporting" do
    let(:record_class) { class_double(ActiveRecord::Base, i18n_scope: nil) }
    let(:resource_class) { class_double(SASC::Resource, attributes: [attribute1, attribute2]) }
    let(:attribute1) { instance_double(SASC::Attribute, ruby_name: :surname, json_name: "familyName") }
    let(:attribute2) { instance_double(SASC::Attribute, ruby_name: :zipcode, json_name: "zipcode") }

    let(:errors) do
      instance_double(ActiveModel::Errors,
                      keys: [:surname],
                      details: { surname: [{ error: error_detail }] },
                      full_messages: ["This data is totally absurd"],
                      full_messages_for: ["This data is totally absurd"])
    end
    let(:error_detail) { "Some unimportant string" }

    let(:record) { instance_double(ActiveRecord::Base, class: record_class, save!: true, errors: errors) }
    let(:resource) { instance_double(SASC::Resource, class: resource_class, record: record) }

    subject { described_class.with_validation_error_reporting(resource) { record.save! } }

    describe "when nothing goes wrong" do
      it "runs the block" do
        expect(record).to receive(:save!)
        subject
      end
    end

    describe "when it raises a non-validation error" do
      let(:err) { RuntimeError.new("Wat") }
      before { allow(record).to receive(:save!).and_raise(err) }

      it "allows the exception to raise through" do
        expect { subject }.to raise_error(err)
      end
    end

    describe "when it raises a validation error" do
      let(:exception) { error_class.new(record) }

      before do
        allow(record).to receive(:errors).and_return(errors)
        allow(record).to receive(:save!).and_raise(exception)
      end

      describe "from ActiveRecord" do
        let(:error_class) { ActiveRecord::RecordInvalid }

        it do
          is_expected_block.to raise_error(SASC::Errors::BatchError) do |batch_error|
            expect(batch_error.errors.length).to eq 1
            err = batch_error.errors.first

            expect(err.subcode).to be_nil
            expect(err.detail).to eq("This data is totally absurd")
            expect(err.pointer).to eq("/data/attributes/familyName")
          end
        end

        context "when a symbol is given in the validation error details" do
          let(:error_detail) { :absurdity_error_level_three }

          it do
            is_expected_block.to raise_error(SASC::Errors::BatchError) do |batch_error|
              expect(batch_error.errors.length).to eq 1
              err = batch_error.errors.first

              expect(err.subcode).to eq("ABSURDITY_ERROR_LEVEL_THREE")
              expect(err.detail).to eq("This data is totally absurd")
              expect(err.pointer).to eq("/data/attributes/familyName")
            end
          end
        end

        context "when there are multiple validation errors" do
          let(:errors) do
            errors = instance_double(ActiveModel::Errors,
                                     keys: [:surname, :zipcode],
                                     details: { surname: [{ error: error_detail }], zipcode: [{ error: "is bad" }] },
                                     full_messages: ["This data is totally absurd", "The zipcode is terrible"])
            allow(errors).to receive(:full_messages_for) do |attr|
              case attr
              when :surname then ["This data is totally absurd"]
              when :zipcode then ["The zipcode is terrible"]
              else raise "WAT"
              end
            end
            errors
          end

          it do
            is_expected_block.to raise_error(SASC::Errors::BatchError) do |batch_error|
              expect(batch_error.errors.length).to eq 2

              err1 = batch_error.errors.first
              expect(err1.subcode).to be_nil
              expect(err1.detail).to eq("This data is totally absurd")
              expect(err1.pointer).to eq("/data/attributes/familyName")

              err2 = batch_error.errors.second
              expect(err2.subcode).to be_nil
              expect(err2.detail).to eq("The zipcode is terrible")
              expect(err2.pointer).to eq("/data/attributes/zipcode")
            end
          end
        end

        context "with an unexpected record" do
          let(:other_record) { instance_double(record_class) }
          before { allow(resource).to receive(:record).and_return(other_record) }

          it "has no pointer attribute" do
            is_expected_block.to raise_error(SASC::Errors::BatchError) do |batch_error|
              expect(batch_error.errors.length).to eq 1
              err = batch_error.errors.first

              expect(err.detail).to eq("This data is totally absurd")
              expect(err.pointer).to be_nil
            end
          end
        end

        context "with a record that has no invalid attributes" do
          let(:errors) do
            instance_double(ActiveModel::Errors,
                            keys: [],
                            details: {},
                            full_messages: [],
                            full_messages_for: [])
          end

          it "contains a generic error" do
            is_expected_block.to raise_error(SASC::Errors::BatchError) do |batch_error|
              expect(batch_error.errors.length).to eq 1
              err = batch_error.errors.first

              expect(err).to be_instance_of(SASC::Errors::InvalidFieldValue)
              expect(err.title).to eq("Resource is not valid")
              expect(err.pointer).to be_nil
            end
          end
        end
      end

      describe "from ActiveModel" do
        let(:error_class) { ActiveModel::ValidationError }
        before { allow(exception).to receive(:model).and_return(record) }
        it do
          is_expected_block.to raise_error(SASC::Errors::BatchError) do |batch_error|
            expect(batch_error.errors.length).to eq 1
            err = batch_error.errors.first

            expect(err.subcode).to be_nil
            expect(err.detail).to eq("This data is totally absurd")
            expect(err.pointer).to eq("/data/attributes/familyName")
          end
        end
      end
    end
  end
end
