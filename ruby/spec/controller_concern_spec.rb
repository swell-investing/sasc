require "rails_helper"

RSpec.describe Api::SASCBaseController, type: :controller do
  Job = Struct.new(:id, :title) do
    def self.find(_id)
    end
  end

  Person = Struct.new(:id, :name, :nick_name, :updated_at, :job, :buddies) do
    class << self
      delegate :pluck, :flat_map, :map, :to_a, to: :each

      def approved_by_mr_t
        each.select { |p| p.nick_name[0] == 'T' }
      end

      def pitied_by_mr_t
        each.reject { |p| p.nick_name[0] == 'T' }
      end

      def with_job_title(arg)
        each.select { |p| p.job.title == arg }
      end

      # rubocop:disable RSpec/InstanceVariable
      def each
        unless @the_rock
          @the_rock = new("1", "Dwayne Johnson", "The Rock", Time.zone.local(2016, 1, 1), Job.new(10, "Actor"))
          @teddy = new("2", "Theodore Roosevelt", "Teddy", Time.zone.local(2017, 1, 1), Job.new(20, "Politician"))
          @amazing_grace = new("3", "Grace Hopper", "Amazing", Time.zone.local(2018, 1, 1), Job.new(30, "Engineer"))

          @the_rock.buddies = [@teddy, @amazing_grace]
          @teddy.buddies = [@the_rock]
          @amazing_grace.buddies = [@the_rock]
        end

        [@the_rock, @teddy, @amazing_grace].each
      end

      def reset!
        @the_rock = nil
        @teddy = nil
        @amazing_grace = nil
      end
      # rubocop:enable RSpec/InstanceVariable

      def find(id)
        each.to_a.find { |rec| rec.id.to_s == id } || raise(ActiveRecord::RecordNotFound)
      end

      def where(filters)
        result = each.select do |person|
          filters.all? do |key, values|
            values = Array(values)

            case key
            when :id then values.include?(person.id.to_s)
            else raise "Unexpected key #{key}"
            end
          end
        end

        #redefine find like a find query
        result.define_singleton_method(:find) do |*args|
          self.to_a.dup.find { |item| item.id == args.first }
        end

        result
      end
    end

    def self.build
    end

    def save!
    end

    def destroy!
    end
  end

  after { Person.reset! }

  class JobResourceTranslator < Glossator::Translator
    def version_not_supported?
      version_below? "3.0.0"
    end
  end

  class JobResource < SASC::Resource
    res_version_translation JobResourceTranslator

    res_attribute :title, :string
  end

  class AnnouncementService
    def shout(record, excitement)
      words = record.name.split(" ")
      words.insert(1, "\"#{record.nick_name}\"")
      announced_name = words.join(" ")
      exclamations = "!" * excitement

      "Here comes #{announced_name}#{exclamations}"
    end
  end

  class PersonResourceTranslator < Glossator::Translator
    def initialize(*args)
      super
      target_version_unsupported! if version_below? "2.1.0"
    end
  end

  class LegendResourceTranslator < Glossator::Translator
    def version_not_supported?
      version_below? "2.1.0"
    end
  end

  class LegendResource < SASC::Resource
    res_version_translation LegendResourceTranslator

    res_creatable
    res_updatable
    res_destroyable

    res_attribute :name, :string, settable_for: [:create]
    res_attribute :nick_name, :string, settable_for: [:create, :update]

    res_has_many_relationship :buddies, LegendResource
    res_has_one_relationship :job, JobResource, settable_for: [:create, :update], settable_target_scope: Job
  end

  class AnnounceLegendActionTranslator < Glossator::Translator
    def version_not_supported?
      version_below? "2.1.0"
    end

    def request_up(arguments)
      double_excitement(arguments) if version_below? "3.0.0"
    end

    def response_down(result)
      remove_person(result) if version_below? "3.0.0"
    end

    private

    def double_excitement(arguments)
      arguments[:excitement] *= 2 if arguments.key?(:excitement)
    end

    def remove_person(result)
      result.delete(:personAnnounced)
    end
  end

  class AnnounceAllLegendsActionTranslator < Glossator::Translator
    def version_not_supported?
      version_below? "2.1.0"
    end

    def request_up(arguments)
      double_excitement(arguments) if version_below? "3.0.0"
    end

    def response_down(result)
      flatten_announcements_list(result) if version_below? "3.0.0"
    end

    private

    def double_excitement(arguments)
      arguments[:excitement] *= 2 if arguments.key?(:excitement)
    end

    def flatten_announcements_list(result)
      result[:loudAnnouncements] = result[:loudAnnouncements].join(" ; ") if result.key?(:loudAnnouncements)
    end
  end

  let(:versions) do
    {
      "1.0.0".to_version => { description: "Initial version" },
      "2.0.0".to_version => { description: "Another version" },
      "2.0.1".to_version => { description: "Another version" },
      "2.1.0".to_version => { description: "Another version" },
      "2.1.1".to_version => { description: "Another version" },
      "3.0.0".to_version => { description: "Another version" },
      "3.0.1".to_version => { description: "Another version" },
    }
  end

  LegendController = Class.new(Api::SASCBaseController) do
    def sasc_resource_class
      LegendResource
    end

    def model_scope
      Person
    end

    def default_inclusions
      { buddies: LegendResource, "buddies.buddies": LegendResource, job: JobResource }
    end

    def announcement_service
      @announcement_service ||= AnnouncementService.new
    end
  end

  controller(LegendController) do
    def create
      sasc_create
    end

    def update
      sasc_update
    end

    def destroy
      sasc_destroy
    end

    sasc_action(
      :announce,
      :individual,
      arguments: { excitement: :integer },
      result: { announcement: :string, person_announced: LegendResource },
      version_translator: AnnounceLegendActionTranslator
    ) do |resource, arguments|
      announcement = announcement_service.shout(resource.record, arguments[:excitement])
      { announcement: announcement, person_announced: resource }
    end

    sasc_action(
      :announce_everyone,
      :collection,
      arguments: { excitement: :integer },
      result: { loud_announcements: :array },
      version_translator: AnnounceAllLegendsActionTranslator
    ) do |arguments|
      announcements = model_scope.map { |rec| announcement_service.shout(rec, arguments[:excitement]) }
      { loud_announcements: announcements }
    end

    sasc_action(
      :broken_individual_action,
      :individual,
      result: { computed_value: :integer }
    ) do |_resource, _arguments|
      {} # Missing the required return value
    end

    sasc_action(
      :broken_collection_action,
      :collection,
      result: { computed_value: :integer }
    ) do |_arguments|
      { computed_value: 5, truthiness: 0.7 } # An extra, unexpected return value
    end
  end

  let(:user) { create(:user) }

  before do
    allow(SASC::Versioning).to receive(:versions).and_return(versions)
    allow(SASC::Versioning).to receive(:latest_version).and_return(versions.keys.sort.last)

    sign_in user

    allow_any_instance_of(AnnouncementService).to receive(:shout).and_call_original

    routes.draw do
      resources :legend, only: [:show, :index, :create, :update, :destroy] do
        collection do
          post 'actions/announce-everyone' => :announce_everyone
          post 'actions/broken-collection-action' => :broken_collection_action
        end
        member do
          post 'actions/announce' => :announce
          post 'actions/broken-individual-action' => :broken_individual_action
        end
      end
    end
  end

  let(:requested_api_version) { "3.0.0" }
  let(:expected_api_version) { requested_api_version }
  let(:base_request_headers) do
    {
      "Accept" => "*/*",
      "x-sasc" => "1.0.0",
      "x-sasc-api-version" => requested_api_version,
      "x-sasc-client" => "some-client 7.8.9 12345678",
    }
  end
  let(:request_headers) { base_request_headers }

  before do
    request_headers.each { |header, value| request.headers[header] = value }
  end

  shared_examples "responds with necessary SASC headers" do |options = {}|
    context "response headers" do
      subject { response.headers.to_h }

      unless options[:response_content] == false
        it { is_expected.to match a_hash_including("Content-Type" => match(%r{^application/json})) }
      end

      it { is_expected.to match a_hash_including("x-sasc" => "1.0.0") }
      it { is_expected.to match a_hash_including("x-sasc-api-version" => expected_api_version) }
    end
  end

  shared_examples "correctly responds to varied request headers" do |options = {}|
    subject { response }

    context "requesting an API version that's too old" do
      let(:requested_api_version) { "1.0.0" }

      it { is_expected.to be_bad_request }
      include_examples "responds with necessary SASC headers"

      it "gets an error in the response body" do
        expect(json).to be_sasc_error(code: "__INCOMPATIBLE_API_VERSION__")
      end
    end

    context "requesting an API version that's not known" do
      let(:requested_api_version) { "99.0.0" }
      let(:expected_api_version) { "3.0.1" }

      it { is_expected.to be_bad_request }
      include_examples "responds with necessary SASC headers"

      it "gets an error in the response body" do
        expect(json).to be_sasc_error(code: "__UNKNOWN_API_VERSION__")
      end
    end

    context "forgetting the x-sasc-api-version header" do
      let(:request_headers) { base_request_headers.except("x-sasc-api-version") }
      let(:expected_api_version) { "3.0.1" }

      it { is_expected.to be_bad_request }
      include_examples "responds with necessary SASC headers"

      it "gets an error in the response body" do
        expect(json).to be_sasc_error(code: "__BAD_HEADER__", source: { header: "x-sasc-api-version" })
      end
    end

    context "specifying an invalid semver in the x-sasc-api-version header" do
      let(:request_headers) { base_request_headers.merge("x-sasc-api-version" => "tuesday") }
      let(:expected_api_version) { "3.0.1" }

      it { is_expected.to be_bad_request }
      include_examples "responds with necessary SASC headers"

      it "gets an error in the response body" do
        expect(json).to be_sasc_error(code: "__BAD_HEADER__", source: { header: "x-sasc-api-version" })
      end
    end

    context "forgetting the Accept header" do
      let(:request_headers) { base_request_headers.except("Accept") }

      it { is_expected.to have_http_status 406 }

      include_examples "responds with necessary SASC headers"

      it "gets an error in the response body" do
        expect(json).to be_sasc_error(code: "__BAD_ACCEPT_HEADER__", source: { header: "Accept" })
      end
    end

    context "specifying an invalid Accept header" do
      let(:request_headers) { base_request_headers.merge("Accept" => "image/jpeg") }

      it { is_expected.to have_http_status 406 }

      include_examples "responds with necessary SASC headers"

      it "gets an error in the response body" do
        expect(json).to be_sasc_error(code: "__BAD_ACCEPT_HEADER__", source: { header: "Accept" })
      end
    end

    context "specifying a catch-all Accept header" do
      let(:request_headers) { base_request_headers.merge("Accept" => "*/*") }

      include_examples "responds with necessary SASC headers", options

      if options[:response_content] == false
        it { is_expected.to have_http_status 204 }
      else
        expected_status = options[:expected_status] || 200
        it { is_expected.to have_http_status expected_status }

        it "gets no errors in the response body" do
          expect(json_if_present).not_to have_key(:errors)
        end
      end
    end
  end

  shared_examples "a valid SASC endpoint" do |options = {}|
    options[:response_content] = true unless options.key?(:response_content)

    if options[:response_content] == false
      it { is_expected.to be_no_content, "unexpected response status #{response.status}" }
    else
      expected_status = options[:expected_status] || 200
      it { is_expected.to have_http_status(expected_status), "unexpected response #{response.status}:\n#{json_if_present.pretty_inspect}" }
    end

    it "correctly provides resource context" do
      expect(controller.send(:context)).to eq(api_version: "3.0.0".to_version,
                                              current_user: user,
                                              client_name: "some-client",
                                              client_version: "7.8.9".to_version,
                                              client_build_timestamp: 12_345_678)
    end

    include_examples "responds with necessary SASC headers", options
    include_examples "correctly responds to varied request headers", options
  end

  shared_examples "GET on collection with no included resources configured" do
    let(:params) { {} }
    before { get :index, params: params }

    it_behaves_like "a valid SASC endpoint"

    let(:expected_response_data) do
      [
        {
          id: "1",
          type: "legends",
          attributes: {
            name: "Dwayne Johnson",
            nickName: "The Rock",
          },
          relationships: {
            buddies: {
              data: [
                { type: "legends", id: "2" },
                { type: "legends", id: "3" },
              ],
            },
            job: {
              data: {
                type: "jobs",
                id: "10",
              },
            },
          },
        },
        {
          id: "2",
          type: "legends",
          attributes: {
            name: "Theodore Roosevelt",
            nickName: "Teddy",
          },
          relationships: {
            buddies: {
              data: [
                { type: "legends", id: "1" },
              ],
            },
            job: {
              data: {
                type: "jobs",
                id: "20",
              },
            },
          },
        },
        {
          id: "3",
          type: "legends",
          attributes: {
            name: "Grace Hopper",
            nickName: "Amazing",
          },
          relationships: {
            buddies: {
              data: [
                { type: "legends", id: "1" },
              ],
            },
            job: {
              data: {
                type: "jobs",
                id: "30",
              },
            },
          },
        },
      ]
    end

    let(:expected_response_included) do
      {
        jobs: [
          {
            id: "10",
            type: "jobs",
            attributes: {
              title: "Actor",
            },
            relationships: {},
          },
          {
            id: "20",
            type: "jobs",
            attributes: {
              title: "Politician",
            },
            relationships: {},
          },
          {
            id: "30",
            type: "jobs",
            attributes: {
              title: "Engineer",
            },
            relationships: {},
          },
        ],
      }
    end

    it "gets the primary resources and included resources in the response body" do
      expect(json_if_present).to eq(data: expected_response_data, included: expected_response_included)
    end

    context "with an id filter" do
      let(:params) { { "filter[id]" => JSON.dump(%w(1 3)) } }

      it "gets only the resources with the requested ids" do
        expect(json_if_present[:data]).to eq(expected_response_data.reject { |d| d[:id] == "2" })
      end
    end

    context "with an invalid id filter value" do
      let(:params) { { "filter[id]" => JSON.dump(abc: 123) } }

      it "errors out" do
        expect(json).to be_sasc_error(code: "__INVALID_QUERY_PARAMETER_VALUE__",
                                      source: { parameter: "filter[id]" })
      end
    end

    context "using a custom filter" do
      let(:params) { { "filter[nickNameStartsWithT]" => "true" } }

      it "gets only the resources that match the filter" do
        filtered_response_data = expected_response_data.select do |d|
          d[:attributes][:nickName].starts_with?("T")
        end
        expect(filtered_response_data.size).to eq(2)
        expect(json_if_present[:data]).to eq(filtered_response_data)
      end

      context 'with a different value' do
        let(:params) { { "filter[nickNameStartsWithT]" => "false" } }

        it "gets only the resources that match the reverse filter value" do
          filtered_response_data = expected_response_data.reject do |d|
            d[:attributes][:nickName].starts_with?("T")
          end
          expect(filtered_response_data.size).to eq(1)
          expect(json_if_present[:data]).to eq(filtered_response_data)
        end
      end

      context 'with value of the wrong type' do
        let(:params) { { "filter[nickNameStartsWithT]" => "37" } }

        it "return an InvalidQueryParameterValue error" do
          expect(json_if_present).to be_sasc_error(
            title: "Schema mismatch on query parameter",
            code: "__INVALID_QUERY_PARAMETER_VALUE__",
            source: { parameter: "filter[nickNameStartsWithT]" }
          )
        end
      end

      context 'with a filter that accepts a string' do
        let(:params) { { "filter[jobTitle]" => '"Actor"' } }

        it "returns only records that pass all filters" do
          expect(json_if_present[:data]).to eq([expected_response_data.first])
        end
      end

      context 'when forgetting to double-quote a string query parameter' do
        let(:params) { { "filter[jobTitle]" => 'Actor' } }

        it "returns a helpful error" do
          expect(json_if_present).to be_sasc_error(
            title: "Invalid JSON. Hint: double quote string query parameters ala filter[foo]=\"bar\"",
            code: "__INVALID_QUERY_PARAMETER_VALUE__",
            source: { parameter: "filter[jobTitle]" }
          )
        end
      end
    end

    context "with an unknown filter" do
      let(:params) { { "filter[badField]" => JSON.dump("abc123") } }

      it "errors out" do
        expect(json).to be_sasc_error(code: "__UNKNOWN_QUERY_PARAMETER__",
                                      source: { parameter: "filter[badField]" })
      end
    end

    context "with a filter containing invalid JSON" do
      let(:params) { { "filter[id]" => '"wat' } }

      it "errors out" do
        expect(json).to be_sasc_error(code: "__INVALID_QUERY_PARAMETER_VALUE__",
                                      source: { parameter: "filter[id]" })
      end
    end

    context "with a weirdly nested filter containing invalid JSON" do
      let(:params) { { "filter[badField][reallyBad]" => '"wat' } }

      it "errors out" do
        expect(json).to be_sasc_error(code: "__INVALID_QUERY_PARAMETER_VALUE__",
                                      source: { parameter: "filter[badField][reallyBad]" })
      end
    end
  end

  shared_examples "GET on individual resource with included resources configured" do
    let(:id) { 2 }
    before { get :show, params: { id: id } }

    it_behaves_like "a valid SASC endpoint"

    let(:expected_response_data) do
      {
        id: "2",
        type: "legends",
        attributes: {
          "name": "Theodore Roosevelt",
          nickName: "Teddy",
        },
        relationships: {
          buddies: {
            data: [
              { type: "legends", id: "1" },
            ],
          },
          job: {
            data: {
              type: "jobs",
              id: "20",
            },
          },
        },
      }
    end

    let(:expected_response_included) do
      {
        legends: [
          {
            id: "1",
            type: "legends",
            attributes: {
              name: "Dwayne Johnson",
              nickName: "The Rock",
            },
            relationships: {
              buddies: {
                data: [
                  { type: "legends", id: "2" },
                  { type: "legends", id: "3" },
                ],
              },
              job: {
                data: {
                  type: "jobs",
                  id: "10",
                },
              },
            },
          },
          {
            id: "3",
            type: "legends",
            attributes: {
              name: "Grace Hopper",
              nickName: "Amazing",
            },
            relationships: {
              buddies: {
                data: [
                  { type: "legends", id: "1" },
                ],
              },
              job: {
                data: {
                  type: "jobs",
                  id: "30",
                },
              },
            },
          },
        ],
        jobs: [
          {
            id: "20",
            type: "jobs",
            attributes: {
              title: "Politician",
            },
            relationships: {},
          },
        ],
      }
    end

    it "gets the primary resource and included resources in the response body" do
      expect(json_if_present).to eq(data: expected_response_data, included: expected_response_included)
    end

    context "with an invalid id" do
      let(:id) { 55 }

      it "returns an error" do
        expect(response).to be_not_found
        expect(json).to be_sasc_error(code: "__BAD_INDIVIDUAL_RESOURCE_URL_ID__")
      end
    end

    context "requesting an older API version" do
      let(:requested_api_version) { "2.1.0" }

      it "returns the requested API version in the headers" do
        expect(subject.headers.to_h).to match a_hash_including("x-sasc-api-version" => "2.1.0")
      end
    end
  end

  shared_examples "GET with gzip support" do
    context "when request Accept-Encoding includes gzip" do
      let(:content_encoding_header) { "foo, gzip, bar" }

      it "gzips the response" do
        allow(Statsd).to receive(:increment)
        request.headers["Accept-Encoding"] = content_encoding_header

        get :index

        expect(response.headers["Content-Encoding"]).to eq("gzip")

        decompressed_body = ActiveSupport::Gzip.decompress(response.body)
        expect(JSON.load(decompressed_body)).to have_key("data")
        expect(Statsd).to have_received(:increment).with("LegendController.content-encoding.gzip")
      end
    end

    context "when request Accept-Encoding does not explicitly include gzip" do
      let(:content_encoding_header) { "foo, bar, *" }

      it "does not gzip the response" do
        get :index

        expect(response.headers.to_h).not_to have_key("Content-Encoding")
        expect(JSON.load(response.body)).to have_key("data")
      end
    end
  end

  context "POST on individual resource action" do
    let(:id) { 2 }
    let(:action_arguments) { { excitement: 4 } }
    before { post :announce, params: { id: id }, body: { arguments: action_arguments }.to_json, as: :json }

    it_behaves_like "a valid SASC endpoint"

    it "calls the announcement service" do
      expect(controller.announcement_service).to have_received(:shout).with(Person.find("2"), 4)
    end

    it "returns results" do
      expect(json_if_present).to eq(result: {
                                      announcement: "Here comes Theodore \"Teddy\" Roosevelt!!!!",
                                      personAnnounced: {
                                        id: "2",
                                        type: "legends",
                                        attributes: {
                                          name: "Theodore Roosevelt",
                                          nickName: "Teddy",
                                        },
                                        relationships: {
                                          buddies: {
                                            data: [
                                              { type: "legends", id: "1" },
                                            ],
                                          },
                                          job: {
                                            data: {
                                              type: "jobs",
                                              id: "20",
                                            },
                                          },
                                        },
                                      },
                                    })
    end

    context "with an invalid arguments object" do
      let(:action_arguments) { 1234 }

      it "returns an error" do
        expect(response).to be_bad_request
        expect(json).to be_sasc_error(code: "__INVALID_REQUEST_DOCUMENT_CONTENT__",
                                      source: { pointer: "/arguments" })
      end
    end

    context "with extra unknown arguments" do
      let(:action_arguments) { { excitement: 4, intensity: 7 } }

      it "returns an error" do
        expect(response).to be_bad_request
        expect(json).to be_sasc_error(code: "__UNKNOWN_ACTION_ARGUMENT__",
                                      source: { pointer: "/arguments/intensity" })
      end
    end

    context "without a required argument" do
      let(:action_arguments) { { foo: "bar" } }

      it "returns an error" do
        expect(response).to be_bad_request
        expect(json).to be_sasc_error(code: "__MISSING_REQUIRED_ACTION_ARGUMENT__",
                                      source: { pointer: "/arguments/excitement" })
      end
    end

    context "on an invalid resource" do
      let(:id) { 55 }

      it "returns an error" do
        expect(response).to be_not_found
        expect(json).to be_sasc_error(code: "__BAD_INDIVIDUAL_RESOURCE_URL_ID__")
      end
    end

    context "using an older API version" do
      let(:requested_api_version) { "2.1.0" }

      it "translates the arguments and results" do
        # Used AnnounceLegendActionTranslator to double excitement and remove person result
        expect(json_if_present).to eq(result: {
                                        announcement: "Here comes Theodore \"Teddy\" Roosevelt!!!!!!!!",
                                      })
      end
    end
  end

  context "POST on resource collection action" do
    let(:action_arguments) { { excitement: 2 } }
    before { post :announce_everyone, body: { arguments: action_arguments }.to_json, as: :json }

    it_behaves_like "a valid SASC endpoint"

    it "calls the announcement service" do
      expect(controller.announcement_service).to have_received(:shout).exactly(3).times
      expect(controller.announcement_service).to have_received(:shout).with(Person.find("1"), 2)
      expect(controller.announcement_service).to have_received(:shout).with(Person.find("2"), 2)
      expect(controller.announcement_service).to have_received(:shout).with(Person.find("3"), 2)
    end

    it "returns results" do
      expect(json_if_present).to eq(result: {
                                      loudAnnouncements: [
                                        "Here comes Dwayne \"The Rock\" Johnson!!",
                                        "Here comes Theodore \"Teddy\" Roosevelt!!",
                                        "Here comes Grace \"Amazing\" Hopper!!",
                                      ],
                                    })
    end

    context "with an invalid arguments object" do
      let(:action_arguments) { 1234 }

      it "returns an error" do
        expect(response).to be_bad_request
        expect(json).to be_sasc_error(code: "__INVALID_REQUEST_DOCUMENT_CONTENT__",
                                      source: { pointer: "/arguments" })
      end
    end

    context "with extra unknown arguments" do
      let(:action_arguments) { { excitement: 4, intensity: 7 } }

      it "returns an error" do
        expect(response).to be_bad_request
        expect(json).to be_sasc_error(code: "__UNKNOWN_ACTION_ARGUMENT__",
                                      source: { pointer: "/arguments/intensity" })
      end
    end

    context "without a required argument" do
      let(:action_arguments) { { foo: "bar" } }

      it "returns an error" do
        expect(response).to be_bad_request
        expect(json).to be_sasc_error(code: "__MISSING_REQUIRED_ACTION_ARGUMENT__",
                                      source: { pointer: "/arguments/excitement" })
      end
    end

    context "using an older API version" do
      let(:requested_api_version) { "2.1.0" }

      it "translates the arguments and results" do
        # Used AnnounceAllLegendsActionTranslator to double excitement and flatten result
        expect(json_if_present).to eq(result: {
                                        loudAnnouncements:
                                          "Here comes Dwayne \"The Rock\" Johnson!!!! ; " \
                                          "Here comes Theodore \"Teddy\" Roosevelt!!!! ; " \
                                          "Here comes Grace \"Amazing\" Hopper!!!!",
                                      })
      end
    end
  end

  context "POST on an action which does not return a necessary value" do
    it "returns an error" do
      post :broken_individual_action, params: { id: 2 }, body: { arguments: {} }.to_json, as: :json
      expect(response).to have_http_status 500
      expect(json).to be_sasc_error(code: "RUNTIME_ERROR", title: "Missing result key :computed_value")
    end
  end

  context "POST on an action which returns an unknown value" do
    it "returns an error" do
      post :broken_collection_action, body: { arguments: {} }.to_json, as: :json
      expect(response).to have_http_status 500
      expect(json).to be_sasc_error(code: "RUNTIME_ERROR", title: "Unknown result key :truthiness")
    end
  end

  context "POST to create a resource" do
    let(:job_50) { Job.new(50, "Writer") }
    let(:new_person) { Person.new(nil, nil, nil, nil, nil, []) }

    before do
      allow(Person).to receive(:build).and_return(new_person)
      allow(Job).to receive(:find).with("50").and_return(job_50)
      allow(Job).to receive(:find).with("51").and_raise(ActiveRecord::RecordNotFound)
      allow(new_person).to receive(:id=).and_call_original
      allow(new_person).to receive(:name=).and_call_original
      allow(new_person).to receive(:nick_name=).and_call_original
      allow(new_person).to receive(:job=).and_call_original
      allow(new_person).to receive(:save!) { new_person.id = 99 }
    end

    let(:new_resource_attributes) { { name: "Charles Dodgson", nickName: "Carroll" } }
    let(:new_resource_relationships) { { job: { data: { id: "50", type: "jobs" } } } }
    let(:new_resource) do
      {
        type: "legends",
        attributes: new_resource_attributes,
        relationships: new_resource_relationships,
      }
    end
    before { post :create, body: { data: new_resource }.to_json, as: :json }

    it_behaves_like "a valid SASC endpoint", expected_status: 201

    it "creates a new record with the given fields and saves it" do
      expect(Person).to have_received(:build).with(no_args)
      expect(new_person).to have_received(:id=).with(nil)
      expect(new_person).to have_received(:name=).with("Charles Dodgson")
      expect(new_person).to have_received(:nick_name=).with("Carroll")
      expect(Job).to have_received(:find).with("50")
      expect(new_person).to have_received(:job=).with(job_50)
      expect(new_person).to have_received(:save!)

      expect(response).to be_created
      expect(json_if_present[:data]).to eq(
        id: "99",
        type: "legends",
        attributes: {
          name: "Charles Dodgson",
          nickName: "Carroll",
        },
        relationships: {
          buddies: { data: [] },
          job: { data: { type: "jobs", id: "50" } },
        }
      )
    end

    describe "with an unknown attribute" do
      let(:new_resource_attributes) { { name: "Charles Dodgson", nickName: "Carroll", favColor: "green" } }

      it "errors out" do
        expect(new_person).not_to have_received(:save!)

        expect(json).to be_sasc_error(code: "__UNKNOWN_FIELD__",
                                      source: { pointer: "/data/attributes/favColor" })
      end
    end

    describe "with an unknown relationship" do
      let(:new_resource_relationships) { { shoe: { data: { id: "2", type: "shoe" } } } }

      it "errors out" do
        expect(new_person).not_to have_received(:save!)

        expect(json).to be_sasc_error(code: "__UNKNOWN_FIELD__",
                                      source: { pointer: "/data/relationships/shoe" })
      end
    end

    describe "with a missing target record" do
      let(:new_resource_relationships) { { job: { data: { id: "51", type: "jobs" } } } }

      it "errors out" do
        expect(new_person).not_to have_received(:save!)

        expect(json).to be_sasc_error(code: "__INVALID_FIELD_VALUE__",
                                      source: { pointer: "/data/relationships/job/data/id" })
      end
    end

    describe "with a relationship that is not settable on create" do
      let(:new_resource_relationships) { { buddies: { data: [] } } }

      it "errors out" do
        expect(new_person).not_to have_received(:save!)

        expect(json).to be_sasc_error(code: "__PERMISSION_DENIED__",
                                      source: { pointer: "/data/relationships/buddies" })
      end
    end

    describe "with a belongs_to relationship set to null" do
      let(:new_resource_relationships) { { job: { data: nil } } }

      it "creates a new record with association set to nil" do
        expect(new_person).to have_received(:job=).with(nil)
      end
    end
  end

  context "PATCH to update a resource" do
    let(:job_50) { Job.new(50, "Writer") }
    let(:the_rock) { Person.find("1") }

    before do
      allow(Job).to receive(:find).and_return(job_50)
      allow(the_rock).to receive(:name=).and_call_original
      allow(the_rock).to receive(:nick_name=).and_call_original
      allow(the_rock).to receive(:job=).and_call_original
      allow(the_rock).to receive(:save!)
    end

    let(:updated_resource_attributes) { { nickName: "The Boulder" } }
    let(:updated_resource_relationships) { { job: { data: { id: "50", type: "jobs" } } } }
    let(:updated_resource) do
      {
        id: "1",
        type: "legends",
        attributes: updated_resource_attributes,
        relationships: updated_resource_relationships,
      }
    end

    before { patch :update, params: { id: 1 }, body: { data: updated_resource }.to_json, as: :json }

    it_behaves_like "a valid SASC endpoint"

    it "updates the record with the given fields and saves it" do
      expect(the_rock).not_to have_received(:name=)
      expect(the_rock).to have_received(:nick_name=).with("The Boulder")
      expect(Job).to have_received(:find).with("50")
      expect(the_rock).to have_received(:job=).with(job_50)
      expect(the_rock).to have_received(:save!)

      expect(json_if_present[:data]).to eq(
        id: "1",
        type: "legends",
        attributes: {
          name: "Dwayne Johnson",
          nickName: "The Boulder",
        },
        relationships: {
          buddies: { data: [
            { type: "legends", id: "2" },
            { type: "legends", id: "3" },
          ], },
          job: { data: { type: "jobs", id: "50" } },
        }
      )
    end

    describe "with an unknown attribute" do
      let(:updated_resource_attributes) { { favColor: "green" } }

      it "errors out" do
        expect(the_rock).not_to have_received(:save!)

        expect(json).to be_sasc_error(code: "__UNKNOWN_FIELD__",
                                      source: { pointer: "/data/attributes/favColor" })
      end
    end

    describe "with an attribute that is not settable on update" do
      let(:updated_resource_attributes) { { name: "Fred Rogers" } }

      it "errors out" do
        expect(the_rock).not_to have_received(:save!)

        expect(json).to be_sasc_error(code: "__PERMISSION_DENIED__",
                                      source: { pointer: "/data/attributes/name" })
      end
    end

    describe "with an unknown relationship" do
      let(:updated_resource_relationships) { { shoe: { data: { id: "2", type: "shoe" } } } }

      it "errors out" do
        expect(the_rock).not_to have_received(:save!)

        expect(json).to be_sasc_error(code: "__UNKNOWN_FIELD__",
                                      source: { pointer: "/data/relationships/shoe" })
      end
    end

    describe "with a relationship that is not settable on update" do
      let(:updated_resource_relationships) { { buddies: { data: [] } } }

      it "errors out" do
        expect(the_rock).not_to have_received(:save!)

        expect(json).to be_sasc_error(code: "__PERMISSION_DENIED__",
                                      source: { pointer: "/data/relationships/buddies" })
      end
    end
  end

  context "DELETE to destroy a resource" do
    let(:the_rock) { Person.find("1") }

    before do
      allow(the_rock).to receive(:destroy!)
    end

    before { delete :destroy, params: { id: 1 }, as: :json }

    it_behaves_like "a valid SASC endpoint", response_content: false

    it "destroys the record" do
      expect(the_rock).to have_received(:destroy!)
      expect(response).to be_no_content
    end
  end

  context "without caching" do
    Object.send(:remove_const, :LegendController)

    LegendController = Class.new(Api::SASCBaseController) do
      def resource_class
        LegendResource
      end

      def model_scope
        Person
      end

      def default_inclusions
        { buddies: LegendResource, "buddies.buddies": LegendResource, job: JobResource }
      end
    end

    controller(LegendController) do
      def create
        sasc_create
      end

      def update
        sasc_update
      end

      def destroy
        sasc_destroy
      end
      # /api/legends?filter[nickNameStartsWithT]=false
      sasc_filter(:nick_name_starts_with_t, :boolean, description: 'get all celebs who have earned the approval of Mr T') do |scope, arg|
        if arg == true
          scope.approved_by_mr_t
        else
          scope.pitied_by_mr_t
        end
      end

      # /api/legends?filter[jobTitle]="Therapist"
      sasc_filter(:job_title, :string, description: 'find celebrities by job title') do |scope, arg|
        scope.with_job_title(arg)
      end
    end

    it_behaves_like "GET on individual resource with included resources configured"
    it_behaves_like "GET on collection with no included resources configured"
  end

  context "with caching" do
    Object.send(:remove_const, :LegendController)

    LegendController = Class.new(Api::SASCBaseController) do
      def sasc_resource_class
        PersonResource
      end

      def model_scope
        Person
      end

      def default_inclusions
        { buddies: LegendResource, "buddies.buddies": LegendResource, job: JobResource }
      end
    end

    # HACK: because rspec is relying on the anonymous controller, but
    # we need a non-anonymous controller
    controller(LegendController) do
      # /api/legends?filter[nickNameStartsWithT]=false
      sasc_filter(:nick_name_starts_with_t, :boolean, description: 'celebs approved by Mr T') do |scope, arg|
        if arg == true
          scope.approved_by_mr_t
        else
          scope.pitied_by_mr_t
        end
      end

      # /api/legends?filter[jobTitle]="Therapist"
      sasc_filter(:job_title, :string, description: 'celebs sorted by job title') do |scope, arg|
        scope.with_job_title(arg)
      end
    end

    let!(:store) { instance_double(ActiveSupport::Cache::MemoryStore) }

    before do
      controller.class.enable_sasc_caching store: store, expires_in: 2.hours
      allow(ActiveSupport::JSON).to receive(:encode).and_call_original
    end

    context "with an empty cache" do
      before do
        allow(UpdateCacheWorker).to receive(:perform_async)
        allow(Rails).to receive(:cache).and_return(store)
        allow(store).to receive(:read).and_return(nil)
        allow(store).to receive(:write)
        allow(Person).to receive(:map).and_call_original
        allow(Person).to receive(:find).and_call_original
      end

      it_behaves_like "GET on individual resource with included resources configured"
      it_behaves_like "GET on collection with no included resources configured"
      it_behaves_like "GET with gzip support"

      describe "doing index requests" do
        it "populates the cache" do
          get :index

          expected_cache_key = 'sasc_resp/LegendController/index/3.0.0/1,2,3/2018-01-01 00:00:00 UTC/buddies,buddies.buddies,job'
          expect(store).to have_received(:read).with(expected_cache_key)
          expect(store).to have_received(:write).with(
            expected_cache_key,
            satisfy { |value| ActiveSupport::Gzip.decompress(value) == response.body },
            expires_in: 2.hours
          )
          expect(response.body).not_to be nil
        end

        it "performs_async the next cache population" do
          expected_cache_key = 'sasc_resp/LegendController/index/3.0.0/1,2,3/2018-01-01 00:00:00 UTC/buddies,buddies.buddies,job'
          allow(store).to(
            receive(:read).with("#{expected_cache_key}_expires_at").and_return(1.hour.from_now)
          )

          get :index

          expect(UpdateCacheWorker).to have_received(:perform_async).with(
            anything,
            anything,
            anything,
            anything,
            anything,
            anything
          )
        end
      end

      describe "doing show requests" do
        it "populates the cache" do
          expected_cache_key = 'sasc_resp/LegendController/show/3.0.0/2/2017-01-01 00:00:00 UTC/buddies,buddies.buddies,job'

          get :show, params: { id: 2 }

          expect(store).to have_received(:read).with(expected_cache_key)
          expect(store).to have_received(:write).with(
            expected_cache_key,
            satisfy { |value| ActiveSupport::Gzip.decompress(value) == response.body },
            expires_in: 2.hours
          )

          expect(parse_json(response.body)).to(
            eq(data: {
                 id: "2",
                 type: "legends",
                 attributes: {
                   "name": "Theodore Roosevelt",
                   nickName: "Teddy",
                 },
                 relationships: {
                   buddies: {
                     data: [
                       { type: "legends", id: "1" },
                     ],
                   },
                   job: {
                     data: {
                       type: "jobs",
                       id: "20",
                     },
                   },
                 },
               },
               included: {
                 legends: [
                   {
                     id: "1",
                     type: "legends",
                     attributes: {
                       name: "Dwayne Johnson",
                       nickName: "The Rock",
                     },
                     relationships: {
                       buddies: {
                         data: [
                           {
                             type: "legends",
                             id: "2",
                           },
                           {
                             type: "legends",
                             id: "3",
                           },
                         ],
                       },
                       job: {
                         data: {
                           type: "jobs",
                           id: "10",
                         },
                       },
                     },
                   },
                   {
                     id: "3",
                     type: "legends",
                     attributes: {
                       name: "Grace Hopper",
                       nickName: "Amazing",
                     },
                     relationships: {
                       buddies: {
                         data: [
                           { type: "legends", id: "1" },
                         ],
                       },
                       job: {
                         data: {
                           type: "jobs",
                           id: "30",
                         },
                       },
                     },
                   },
                 ],
                 jobs: [
                   {
                     id: "20",
                     type: "jobs",
                     attributes: {
                       title: "Politician",
                     },
                     relationships: {},
                   },
                 ],
               })
          )
        end

        it "perform_async the next cache population" do
          expected_cache_key = 'sasc_resp/LegendController/show/3.0.0/2/2017-01-01 00:00:00 UTC/buddies,buddies.buddies,job'
          allow(store).to(
            receive(:read).with("#{expected_cache_key}_expires_at")
              .and_return(1.hour.from_now)
          )

          get :show, params: { id: 2 }

          expect(UpdateCacheWorker).to have_received(:perform_async).with(
            anything,
            anything,
            anything,
            anything,
            anything,
            anything
          )
        end
      end
    end

    context "with a populated cache" do
      before do
        allow(UpdateCacheWorker).to receive(:perform_async)
        allow(store).to receive(:read).and_return ActiveSupport::Gzip.compress('{"data": "foo"}')
        allow(store).to(
          receive(:read).with(match(/.+_expires_at/))
            .and_return(2.hours.from_now)
        )
        # Not allowing store.write here, controller should not write when cache already populated
        allow(Person).to receive(:map).and_call_original
        allow(Person).to receive(:find).and_call_original
      end

      it_behaves_like "GET with gzip support"

      describe "doing index requests" do
        it "uses the cache" do
          expected_cache_key = 'sasc_resp/LegendController/index/3.0.0/1,2,3/2018-01-01 00:00:00 UTC/buddies,buddies.buddies,job'
          allow(store).to(
            receive(:read).with("#{expected_cache_key}_expires_at")
              .and_return(1.hour.from_now)
          )

          get :index

          expect(JSON.load(response.body)).to eq("data" => "foo")
          expect(store).to have_received(:read).with(expected_cache_key)
          expect(Person).not_to have_received(:map)
        end

        it "performs the next cache population if we are over the midpoint of the ttl" do
          expected_cache_key = 'sasc_resp/LegendController/index/3.0.0/1,2,3/2018-01-01 00:00:00 UTC/buddies,buddies.buddies,job'
          allow(store).to(
            receive(:read).with("#{expected_cache_key}_expires_at")
              .and_return(1.hour.from_now)
          )

          get :index

          expect(UpdateCacheWorker).to have_received(:perform_async).with(
            anything,
            anything,
            anything,
            anything,
            anything,
            anything
          )
        end

        it "does not perform_async the next cache population if we are not over the midpoint of the ttl" do
          expected_cache_key = 'sasc_resp/LegendController/index/3.0.0/1,2,3/2018-01-01 00:00:00 UTC/buddies,buddies.buddies,job'
          allow(store).to(
            receive(:read).with("#{expected_cache_key}_expires_at")
              .and_return(2.hours.from_now)
          )

          get :index

          expect(UpdateCacheWorker).not_to have_received(:perform_async)
        end
      end

      describe "doing show requests" do
        it "uses the cache" do
          expected_cache_key = 'sasc_resp/LegendController/show/3.0.0/2/2017-01-01 00:00:00 UTC/buddies,buddies.buddies,job'
          allow(store).to(
            receive(:read).with("#{expected_cache_key}_expires_at")
              .and_return(1.hour.from_now)
          )

          get :show, params: { id: 2 }

          expect(JSON.load(response.body)).to eq("data" => "foo")
          expect(store).to have_received(:read).with(expected_cache_key)
          expect(Person).not_to have_received(:find)
        end

        it "perform_async the next cache population" do
          expected_cache_key = 'sasc_resp/LegendController/show/3.0.0/2/2017-01-01 00:00:00 UTC/buddies,buddies.buddies,job'
          allow(store).to(
            receive(:read).with("#{expected_cache_key}_expires_at")
              .and_return(1.hour.from_now)
          )

          get :show, params: { id: 2 }

          expect(UpdateCacheWorker).to have_received(:perform_async).with(
            anything,
            anything,
            anything,
            anything,
            anything,
            anything
          )
        end
      end
    end
  end

  describe "class methods for async functionality" do
    Object.send(:remove_const, :LegendController)

    LegendController = Class.new(Api::SASCBaseController) do
      def resource_class
        PersonResource
      end

      def model_scope
        Person
      end

      def default_inclusions
        { buddies: LegendResource, "buddies.buddies": LegendResource, job: JobResource }
      end
    end

    # HACK: because rspec is relying on the anonymous controller, but
    # we need a non-anonymous controller
    controller(LegendController) do
      # /api/legends?filter[nickNameStartsWithT]=false
      sasc_filter(:nick_name_starts_with_t, :boolean, description: 'celebs approved by Mr T') do |scope, arg|
        if arg == true
          scope.approved_by_mr_t
        else
          scope.pitied_by_mr_t
        end
      end

      # /api/legends?filter[jobTitle]="Therapist"
      sasc_filter(:job_title, :string, description: 'celebs sorted by job title') do |scope, arg|
        scope.with_job_title(arg)
      end
    end

    it "prepares the index data" do
      legion_controller = LegendController.new

      actual = legion_controller.prepare_index_data(
        legion_controller.model_scope.where(id: "2"),
        legion_controller.default_inclusions,
        LegendResource,
        {}
      )

      expect(ActiveSupport::JSON.encode(actual)).to eq(ActiveSupport::JSON.encode(
                                                         data: [{
                                                           id: "2",
                                                           type: "legends",
                                                           attributes: {
                                                             "name": "Theodore Roosevelt",
                                                             nickName: "Teddy",
                                                           },
                                                           relationships: {
                                                             buddies: {
                                                               data: [
                                                                 { type: "legends", id: "1" },
                                                               ],
                                                             },
                                                             job: {
                                                               data: {
                                                                 type: "jobs",
                                                                 id: "20",
                                                               },
                                                             },
                                                           },
                                                         },],
                                                         included: {
                                                           legends: [
                                                             {
                                                               id: "1",
                                                               type: "legends",
                                                               attributes: {
                                                                 name: "Dwayne Johnson",
                                                                 nickName: "The Rock",
                                                               },
                                                               relationships: {
                                                                 buddies: {
                                                                   data: [
                                                                     {
                                                                       type: "legends",
                                                                       id: "2",
                                                                     },
                                                                     {
                                                                       type: "legends",
                                                                       id: "3",
                                                                     },
                                                                   ],
                                                                 },
                                                                 job: {
                                                                   data: {
                                                                     type: "jobs",
                                                                     id: "10",
                                                                   },
                                                                 },
                                                               },
                                                             },
                                                             {
                                                               id: "3",
                                                               type: "legends",
                                                               attributes: {
                                                                 name: "Grace Hopper",
                                                                 nickName: "Amazing",
                                                               },
                                                               relationships: {
                                                                 buddies: {
                                                                   data: [
                                                                     { type: "legends", id: "1" },
                                                                   ],
                                                                 },
                                                                 job: {
                                                                   data: {
                                                                     type: "jobs",
                                                                     id: "30",
                                                                   },
                                                                 },
                                                               },
                                                             },
                                                           ],
                                                           jobs: [
                                                             {
                                                               id: "20",
                                                               type: "jobs",
                                                               attributes: {
                                                                 title: "Politician",
                                                               },
                                                               relationships: {},
                                                             },
                                                           ],
                                                         }
      ))
    end

    it "prepares the show data" do
      legion_controller = LegendController.new

      actual = legion_controller.prepare_show_data(
        legion_controller.model_scope.find("2"),
        legion_controller.default_inclusions,
        LegendResource,
        {}
      )

      expect(ActiveSupport::JSON.encode(actual)).to eq(ActiveSupport::JSON.encode(
                                                         data: {
                                                           id: "2",
                                                           type: "legends",
                                                           attributes: {
                                                             "name": "Theodore Roosevelt",
                                                             nickName: "Teddy",
                                                           },
                                                           relationships: {
                                                             buddies: {
                                                               data: [
                                                                 { type: "legends", id: "1" },
                                                               ],
                                                             },
                                                             job: {
                                                               data: {
                                                                 type: "jobs",
                                                                 id: "20",
                                                               },
                                                             },
                                                           },
                                                         },
                                                         included: {
                                                           legends: [
                                                             {
                                                               id: "1",
                                                               type: "legends",
                                                               attributes: {
                                                                 name: "Dwayne Johnson",
                                                                 nickName: "The Rock",
                                                               },
                                                               relationships: {
                                                                 buddies: {
                                                                   data: [
                                                                     {
                                                                       type: "legends",
                                                                       id: "2",
                                                                     },
                                                                     {
                                                                       type: "legends",
                                                                       id: "3",
                                                                     },
                                                                   ],
                                                                 },
                                                                 job: {
                                                                   data: {
                                                                     type: "jobs",
                                                                     id: "10",
                                                                   },
                                                                 },
                                                               },
                                                             },
                                                             {
                                                               id: "3",

                                                               type: "legends",
                                                               attributes: {
                                                                 name: "Grace Hopper",
                                                                 nickName: "Amazing",
                                                               },
                                                               relationships: {
                                                                 buddies: {
                                                                   data: [
                                                                     { type: "legends", id: "1" },
                                                                   ],
                                                                 },
                                                                 job: {
                                                                   data: {
                                                                     type: "jobs",
                                                                     id: "30",
                                                                   },
                                                                 },
                                                               },
                                                             },
                                                           ],
                                                           jobs: [
                                                             {
                                                               id: "20",
                                                               type: "jobs",
                                                               attributes: {
                                                                 title: "Politician",
                                                               },
                                                               relationships: {},
                                                             },
                                                           ],
                                                         }
      ))
    end
  end
end
