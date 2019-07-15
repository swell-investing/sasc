#.## SASCConcern
#. Controllers which provide SASC resources should include SASCConcern. Many features are automatically
#. provided with sensible defaults. The only thing you always must manually provide is the `model_scope` method. For
#. example, here is a complete controller that provides `index` and `show` for the resource class `DogKennelResource`
#. and the ActiveRecord class `DogKennel`:
#.
#. ```ruby
#. class DogKennelsController
#    include SASCConcern
#
#.   def model_scope
#.     DogKennel.all
#.   end
#. end
#. ```
#.
#. To add more functionality beyond `index` and `show`, or to override the default behavior, see the method definitons
#. below.
#.
#. **NOTE:** When creating a new controller, don't forget that you also need to create routes! And remember that
#. the Rails routing DSL defaults to underscore-separated paths, which are not valid for SASC. You will need to
#. provide a `path` argument to the route for multi-word resource types:
#.
#. ```ruby
#.  namespace :api
#.    resources :dog_kennels, path: '/dog-kennels', only: [:index, :show]
#.  end
#. ```
module SASC
  module ControllerConcern
    extend ActiveSupport::Concern

    included do
      include ControllerHelpers

      before_action :resolve_api_version
      before_action :ensure_protocol_version_correct
      before_action :parse_client_header
      before_action :ensure_client_version_not_deprecated
      before_action :ensure_json_response_acceptable
      before_action :set_sasc_response_headers

      rescue_from SASC::Errors::BaseError do |error|
        render_sasc_error error
      end

      rescue_from SASC::Errors::BatchError do |error|
        render_sasc_errors error
      end

      rescue_from ActionController::ParameterMissing do |error|
        render_sasc_error SASC::Errors::InvalidRequestDocumentContent.new(
          "Required parameter is missing",
          pointer: "/#{error.param}"
        )
      end

      rescue_from ActiveRecord::RecordNotFound do
        render_sasc_error SASC::Errors::BadIndividualResourceUrlId.new("No record with that id is available")
      end

      rescue_from Glossator::Errors::UnsupportedVersionError do |error|
        render_unsupported_api_version(error)
      end

      rescue_from ServiceError do |service_error|
        render_sasc_error SASC::Errors::InternalError.new(service_error)
      end

      # Overrides the ApplicationController method
      def last_ditch_error_response(error)
        render_sasc_error SASC::Errors::InternalError.new(error)
      end

      def render_unsupported_api_version(err = nil)
        err ||= "Version is not supported"
        render_sasc_error SASC::Errors::IncompatibleApiVersion.new(err.to_s)
      end

      def self.sasc_actions
        @sasc_actions ||= {}
      end

      # key: action
      # value: :all or regex to match against path
      def self.sasc_ignored_path_matchers
        @sasc_ignored_path_matchers ||= {}
      end

      # TODO: Handle FolioApi::Error and API::XigniteApi::Error SASCily.
      # TODO: Also, other types of ActiveRecord exception might escape
      # from custom actions, and should be handled appropriately.

      #% SASCConcern.sasc_action(name, kind, arguments: {}, result: {}) do...
      #. Define a custom SASC action, i.e. an RPC-ish action that doesn't fit in the CRUD model
      #.
      #. * `name`: The name of the action, an underscore-separated symbol
      #. * `kind`: Must be `:individual` or `:collection`. Use `:individual` if the action operates on a specific resource
      #.           by id, otherwise use `:collection`
      #. * `arguments`: A hash describing required argument keys in the request from the client. Map each key to a JSON
      #.                type, e.g.  `:object` or `:string`
      #. * `result`: A hash describing result keys for the response. Map each key to a JSON type, e.g. `:object` or
      #.              `:string`, or to a resource class, e.g. 'UserResource'
      #. * `block`: Implementation of the action itself
      #.
      #. Specify all names (e.g. of actions, arguments, and results) as underscore-separated symbols. They will
      #. automatically be converted to and from camel case whenever JSON is generated or parsed.
      #.
      #. When the server receives a request for a collection action, the block will be called with a hash containing the
      #. arguments. Within the block, perform whatever operation is needed, and then end with a results hash.
      #.
      #. ```ruby
      #.  class DogKennelsController
      #     include SASCConcern
      #
      #.    sasc_action :run_iditarod, :collection,
      #.                arguments: { route: :string },
      #.                result: { days_elapsed: :integer } do |arguments|
      #.      days = musher_service.run("iditarod", arguments[:route])
      #.      { days_elapsed: days }
      #.    end
      #.
      #.    private
      #.
      #.    def musher_service
      #.      @musher_service ||= MusherService.new
      #.    end
      #.  end
      #. ```
      #.
      #. Both `arguments` and `result` are optional; many actions don't require any arguments, or don't need to report
      #. anything back to the client beyond the simple fact of success. Note that if you don't specify any result keys,
      #. you still *must* end with a results hash (which in this case would be empty):
      #.
      #. ```ruby
      #.  sasc_action :run_standard_iditarod, :collection do
      #.    musher_service.run("iditarod", DEFAULT_ROUTE)
      #.    {}
      #. end
      #. ```
      #.
      #. For `:individual` requests, your block will also be passed the target resource object:
      #.
      #. ```ruby
      #.  sasc_action :bark, :individual, arguments: { loudness: :integer } do |resource, arguments|
      #.    resource.record.make_noise(arguments[:loudness])
      #.    {}
      #.  end
      #. ```
      def self.sasc_action(name, kind, **kwargs, &block)
        raise "Method name #{name.inspect} already taken" if respond_to?(name)
        raise "Must supply block to sasc_action" unless block

        sasc_actions[name.to_sym] = action = SASC::Action.new(name, kind, **kwargs)

        define_method name do
          ruby_arguments = action.unjsonify_arguments(action_arguments, @api_version)

          ruby_result = if action.individual?
                          res = resourcify(fetch_individual_record)
                          SASC::Errors.with_validation_error_reporting(res) do
                            instance_exec(res, ruby_arguments, &block)
                          end
                        else
                          instance_exec(ruby_arguments, &block)
                        end

          render json: { result: action.jsonify_result(ruby_result, @api_version) }
        end
      end

      def self.sasc_filters
        @sasc_filters ||= {}
      end

      #% Api::SASCBaseController.sasc_filter(name, type, description:, &block)
      #. Configures a filter for index results based on the return value of the passed-in block
      #.
      #. * `name`: An underscored symbol. This will become camel-cased when it is used as a URL parameter
      #.           to request a limited scope of records from the client.
      #. * `type`: A symbol or a hash (containing a JSON schema document) describing the JSON type of the query value
      #. * `description`: A string documenting what the filter does
      #. * `block`: A proc that takes two arguments - a scope and a query value - and returns a new scope
      #.
      #. ```ruby
      #. class DogsController < SASCBaseController
      #.   sasc_filter(:minimum_goodness, :integer, description: "Requires good dogs") do |scope, arg|
      #.     scope.where('goodness >= ?', arg)
      #.   end
      #. end
      #. ```
      #.
      #. A URL to request dogs that are good enough using this filter would look like:
      #. `/api/dogs?filter[minimumGoodness]=3`
      #.
      #. Inside the block you can also use custom scopes defined on the model.
      #.
      #. ```ruby
      #. class Dog < ActiveRecordBase
      #.   def self.good_dogs
      #.     where(loves_walks: true).where(bitey: false)
      #.   end
      #.
      #.   def self.bad_dogs
      #.     where(bitey: true)
      #.   end
      #. end
      #.
      #. class DogsController < SASCBaseController
      #.   sasc_filter(:is_good, :boolean, description: "Limits dogs by goodosity") do |scope, arg|
      #.     if arg
      #.       scope.good_dogs
      #.     else
      #.       scope.bad_dogs
      #.     end
      #.   end
      #. end
      #. ```
      #.
      #. A URL to request only the good dogs using this filter would look like:
      #. `/api/dogs?filter[isGood]=true`
      def self.sasc_filter(name, type, description:, &block)
        raise ArgumentError.new('block required for filter') unless block
        raise ArgumentError.new('description required for filter') unless description.present?
        sasc_filters[name] = { type: type, description: description, block: block }
      end

      def self.sasc_caching_config
        @sasc_caching_config ||= {}
      end

      #% SASCConcern.enable_sasc_caching(store: Rails.cache, key: :updated_at, expires_in: 30.minutes)
      #. Configures the controller to use gzipped cached responses to speed up `index` and `show` requests.
      #.
      #. * `store`: An ActiveSupport::Cache::Store. If not specified, uses the default Rails cache.
      #. * `key`: A value on the record that increases every time it is changed. Defaults to `updated_at`.
      #. * `expires_in`: How long between when an entry is cached and when it is automatically dropped. Defaults to
      #.    30 minutes.
      #.
      #.
      #. ```ruby
      #. class DogsController
      #    include SASCConcern
      #
      #.   enable_sasc_caching
      #.
      #.   def model_scope
      #.     # If this were changed to e.g. Dog.where(owner: current_user), then
      #.     # you would have to disable caching!
      #.     Dog.all
      #.   end
      #. end
      #. ```
      #.
      #. Caching improves response times, but creates a risk that you will serve stale data unless you are careful about
      #. making sure the caching system notices when output should change. Caching should only be enabled if *all* these
      #. conditions are true:
      #.
      #. * The session (e.g. whether or not the user is logged in) has no effect on each resource's output. In particular,
      #.   if the resource uses the `current_user` from context to change its JSON output, then you cannot safely enable
      #.   caching. **Otherwise the results of one user's request might be shown to another user.**
      #. * The model must have an `updated_at` field, or something similar, which must be guaranteed to rise every
      #.   time the model changes.
      #. * For every relationship described by the resource, any change to the related model (including creation and
      #.   destruction) must also increase the `updated_at` value of the source model.
      #.
      #. For example, if `DogResource` `res_has_many_relationship :bones`, then whenever a `Dog`'s `Bone` is changed, the
      #. `updated_at` of the `Dog` must be increased. If the `Bone` model `belongs_to :dog`, then you can use the `touch`
      #. option on `belongs_to` to accomplish this automatically:
      #.
      #. ```ruby
      #. class Bone < ActiveRecord::Base
      #.   belongs_to :dog, touch: true
      #. end
      #.
      #. class Dog < ActiveRecord::Base
      #.   has_many :bones
      #. end
      #.
      #. class DogResource < SASC::Resource
      #.   res_has_many_relationship :bones, BoneResource
      #. end
      #. ```
      #.
      #. For other ActiveRecord relationships, you may need to use ActiveRecord lifecycle callbacks:
      #.
      #. ```ruby
      #. class WaterBowl < ActiveRecord::Base
      #.   has_many :dogs
      #.
      #.   after_save :touch_dogs
      #.   after_destroy :touch_dogs
      #.   after_touch :touch_dogs
      #.   def touch_dogs
      #.     dogs.each(&:touch)
      #.   end
      #. end
      #.
      #. class Dog < ActiveRecord::Base
      #.   belongs_to :water_bowl
      #. end
      #.
      #. class DogResource < SASC::Resource
      #.   res_has_one_relationship :bowl, WaterBowl
      #. end
      #. ```
      def self.enable_sasc_caching(store: Rails.cache, key: :updated_at, expires_in: 30.minutes)
        sasc_caching_config[:store] = store
        sasc_caching_config[:key] = key
        sasc_caching_config[:expires_in] = expires_in
      end
    end

    # Overrides the ApplicationController method
    def last_ditch_error_response(error)
      render_sasc_error SASC::Errors::InternalError.new(error)
    end

    #% SASCConcern#index
    #. A default `index` method.
    #.
    #. The default SASCConcern provides an `index` method which does nothing but call `sasc_index`. You may want
    #. to override this and provide your own `index` method if you want to customize its behavior:
    #.
    #. ```ruby
    #. class DogsController
    #    include SASCConcern
    #
    #.   def index
    #.     throw "Wat!" unless current_user.can_index_dogs?
    #.     sasc_index
    #.     Rails.logger.warning "Somebody indexed dogs!"
    #.   end
    #. end
    #. ```
    #.
    #. Or if you want to disable it entirely:
    #.
    #. ```ruby
    #. class DogsController
    #    include SASCConcern
    #
    #.   def index
    #.     raise NotImplementedError
    #.   end
    #. end
    #. ```
    def index
      sasc_index
    end

    #% SASCConcern#show
    #. A default `show` method.
    #.
    #. The default SASCConcern provides an `show` method which does nothing but call `sasc_show`. You may want
    #. to override this and provide your own `show` method if you want to customize its behavior or disable it. See
    #. the examples above for `index`.
    def show
      sasc_show
    end

    #% SASCConcern#sasc_resource_class
    #. Returns SASC::Resource class that this controller handles.
    #.
    #. SASCConcern provides a default implementation of this method which infers the resource class name based
    #. on the controller name, e.g. `DogsController` is inferred to have a `resource_class` named `DogResource`. If
    #. your resource naming situation is more unusual, you may want to override this method:
    #.
    #. ```ruby
    #. class CorgiController
    #    include SASCConcern
    #
    #.   def sasc_resource_class
    #.     DogResource
    #.   end
    #.
    #.   def model_scope
    #.     Dog.where(ground_clearance: "low")
    #.   end
    #. end
    #. ```
    def sasc_resource_class
      @derived_resource_class ||= derive_resource_class
    end

    #% SASCConcern#model_scope
    #. Returns an ActiveRecord scope for records that this controller can access.
    #.
    #. All controllers must provide an implementation of this method if they derive from `SASCConcern`.
    #.
    #. Every method in `SASCConcern` goes through this scope whenever attempting to read or write the model, so
    #. it's a convenient place to set up security rules, e.g. based on `current_user`. For example, to allow non-admin
    #. users to only access their own dogs:
    #.
    #. ```ruby
    #. class DogsController
    #    include SASCConcern
    #
    #.   def model_scope
    #.     current_user.admin? ? Dog.all : Dog.where(owner: current_user)
    #.   end
    #. end
    #. ```
    #.
    #. To handle situations where the user has no accessible records, use the `ActiveRecord::Base.none` method:
    #.
    #. ```ruby
    #. class DogsController
    #    include SASCConcern
    #
    #.   def model_scope
    #.     return Dog.none if current_user.nil? || current_user.cat_person?
    #.     current_user.admin? ? Dog.all : Dog.where(owner: current_user)
    #.   end
    #. end
    #. ```
    def model_scope
      raise NotImplementedError
    end

    #% SASCConcern#default_inclusions
    #. Returns a hash mapping included relationship names to resource classes.
    #.
    #. When a related resource is "included", that means that it will be sent in responses along with the main
    #. resources that were directly requested:
    #.
    #. ```ruby
    #. class DogsController
    #    include SASCConcern
    #
    #.   def model_scope
    #.     Dog.all
    #.   end
    #.
    #.   # Responses for dogs will now also include complete records for related bones and chew toys
    #.   def default_inclusions
    #.     { bones: BoneResource, chew_toys: ChewToyResource }
    #.   end
    #. end
    #. ```
    #.
    #. You can include indirectly related resources by specifying relationship names separated by dots. For example,
    #. suppose dogs have many owners, and owners have many hats, and each hat has a brim. To include every owner
    #. for each rendered dog, and every hat owned by those owners, and the brims of each of those hats:
    #.
    #. ```ruby
    #. def default_inclusions
    #.   { "owners": OwnerResource, "owners.hats": HatResource, "owners.hats.brim": BrimResource }
    #. end
    #. ```
    def default_inclusions
      {}
    end

    #% SASCConcern#context
    #. Returns a hash of information to be passed to Resource instances from the controller
    #.
    #. This is useful for providing Resource-specific services and session data.
    #.
    #. The default implementation returns a hash with these keys:
    #. * `current_user`: The currently logged-in User, or `nil` if no-one is logged in
    #. * `client_name`: The name string from the `X-SASC-Client` header in the request
    #. * `client_version`: The semver from the `X-SASC-Client` header in the rquest
    #. * `client_build_timestamp`: The integer timestamp from the `X-SASC-Client` header in the request
    #.
    #. To add additional keys, e.g. with services that the resource needs, override this method:
    #.
    #. ```ruby
    #. class DogsController
    #    include SASCConcern
    #
    #.   def context
    #.     super.merge({
    #.       my_service: my_service
    #.     })
    #.   end
    #.
    #.   private
    #.
    #.   def my_service
    #.     @my_service ||= MyService.new
    #.   end
    #. end
    #. ```
    def context
      {
        api_version: @api_version,
        current_user: current_user,
        client_name: @client_name,
        client_version: @client_version,
        client_build_timestamp: @client_build_timestamp,
      }.compact
    end

    # The methods below are only public for use in logging requests

    def query_params
      @query_params ||= parse_query_param(request.query_parameters)
      @query_params
    end

    # can be called by sidekiq (see UpdateCacheWorker)
    def prepare_index_data(
          records,
          inclusions,
          resource_class,
          resource_context
    )
      {
        data: records.map { |r| resource_class.new(r, resource_context) },
        included: load_included_resources(records, inclusions, resource_context),
      }.compact
    end

    # can be called by sidekiq (see UpdateCacheWorker)
    def prepare_show_data(
          record,
          inclusions,
          resource_class,
          resource_context
    )
      {
        data: resource_class.new(record, resource_context),
        included: load_included_resources([record], inclusions, resource_context),
      }.compact
    end

    def caching_report
      @caching_report ||= nil
    end

    protected

    #% SASCConcern#sasc_index()
    #. Renders a collection of resources based on the request params
    #.
    #. This method calls `fetch_index_records` to scope its response; see its documentation for details.
    def sasc_index
      records = fetch_index_records
      inclusions = default_inclusions
      cache_key = build_cache_key(:index, records, inclusions: inclusions)

      if cache_key.present?
        render_with_caching(cache_key, records.pluck(:id).uniq)
      else
        render(body: ActiveSupport::JSON.encode(
          prepare_index_data(
            records,
            inclusions,
            sasc_resource_class,
            context
          )
        ))
      end
    end

    #% SASCConcern#sasc_show()
    #. Renders a resource based on the request params
    #.
    #. This method calls `fetch_individual_record` to find the requested resource; see its documentation for details.
    def sasc_show
      inclusions = default_inclusions
      cache_key = build_cache_key(:show, params.require(:id), inclusions: inclusions)

      if cache_key.present?
        render_with_caching(cache_key, params.require(:id))
      else
        render(body: ActiveSupport::JSON.encode(
          prepare_show_data(
            model_scope.find(params.require(:id)),
            inclusions,
            sasc_resource_class,
            context
          )
        ))
      end
    end

    #% SASCConcern#sasc_create()
    #. Creates a new resource based on the request params
    #.
    #. Once a Resource class has been configured to allow creation with `res_creatable`, your controller's `create`
    #. action can simply be a one-line call to `sasc_create`. Here is a complete controller that supports creating new
    #. instances of Dog:
    #.
    #. ```ruby
    #. class DogsController
    #    include SASCConcern
    #
    #.   def model_scope
    #.     Dog.all
    #.   end
    #.
    #.   def create
    #.     sasc_create
    #.   end
    #. end
    #.
    #. class DogResource < SASC::Resource
    #.   res_creatable
    #. end
    #. ```
    #.
    #. Don't forget to also add `:create` to the list of permitted actions on the route:
    #.
    #. ```ruby
    #.  namespace :api
    #.    resources :dogs, path: '/dogs', only: [:index, :show, :create]
    #.  end
    #. ```
    #.
    #. This method calls `build_record` to initialize the new resource; see its documentation for details.
    def sasc_create
      inclusions = default_inclusions
      record = build_record
      record.id = nil # Avoid issue where a model_scope filtering on an id will set that id on build
      @individual_record = record
      resource = sasc_resource_class.create_with_sasc_data!(record, params.require(:data).to_unsafe_hash, context)
      included_resources = load_included_resources([record], inclusions, context)
      render status: :created, json: { data: resource, included: included_resources }.compact
      resource
    end

    #% SASCConcern#sasc_update()
    #. Updates a resource based on the request params
    #.
    #. Once a Resource class has been configured to allow updates with `res_updatable`, your controller's `update`
    #. action can simply be a one-line call to `sasc_update`. Here is a complete controller that supports updating
    #. instances of Dog:
    #.
    #. ```ruby
    #. class DogsController
    #    include SASCConcern
    #
    #.   def model_scope
    #.     Dog.all
    #.   end
    #.
    #.   def update
    #.     sasc_update
    #.   end
    #. end
    #.
    #. class DogResource < SASC::Resource
    #.   res_updatable
    #. end
    #. ```
    #.
    #. Don't forget to also add `:update` to the list of permitted actions on the route:
    #.
    #. ```ruby
    #.  namespace :api
    #.    resources :dogs, path: '/dogs', only: [:index, :show, :update]
    #.  end
    #. ```
    #.
    #. This method calls `fetch_individual_record` to find the requested resource; see its documentation for details.
    def sasc_update
      inclusions = default_inclusions
      record = fetch_individual_record
      resource = resourcify(record)
      resource.update_with_sasc_data!(params.require(:data).to_unsafe_hash)
      included_resources = load_included_resources([record], inclusions, context)
      render json: { data: resource, included: included_resources }.compact
      resource
    end

    #% SASCConcern#sasc_destroy
    #. Destroys a resource based on the request params
    #.
    #. Once a Resource class has been configured to allow destruction with `res_destroyable`, your controller's
    #. `destroy` action can simply be a one-line call to `sasc_destroy`. Here is a complete controller that supports
    #. destroying instances of Dog:
    #.
    #. ```ruby
    #. class DogsController
    #    include SASCConcern
    #
    #.   def model_scope
    #.     Dog.all
    #.   end
    #.
    #.   def destroy
    #.     sasc_destroy
    #.   end
    #. end
    #.
    #. class DogResource < SASC::Resource
    #.   res_destroyable
    #. end
    #. ```
    #.
    #. Don't forget to also add `:destroy` to the list of permitted actions on the route:
    #.
    #. ```ruby
    #.  namespace :api
    #.    resources :dogs, path: '/dogs', only: [:index, :show, :destroy]
    #.  end
    #. ```
    #.
    #. This method calls `fetch_individual_record` to find the requested resource; see its documentation for details.
    def sasc_destroy
      record = fetch_individual_record
      resource = resourcify(record)
      resource.destroy!
      head :no_content
      resource
    end

    #% SASCConcern#fetch_index_records
    #. Returns a scope of records based on the request params
    #.
    #. This is the method used by `sasc_index` to obtain the set of records to render. You may wish to override this
    #. method to customize its behavior, e.g. to add a default sort order.
    #.
    #. ```ruby
    #. class DogsController
    #    include SASCConcern
    #
    #.   def model_scope
    #.     Dog.all
    #.   end
    #.
    #.   def fetch_index_records
    #.     # Friendliest dogs are first
    #.     return model_scope.order(friendliness: :desc)
    #.   end
    #. end
    #. ```
    def fetch_index_records
      scope = model_scope
      scope = filtered_scope(scope, query_params[:filter]) if query_params.key?(:filter)
      scope
    end

    #% SASCConcern#fetch_individual_record
    #. Returns a single requested record based on the request params
    #.
    #. This is the method used by `sasc_show`, `sasc_update`, `sasc_destroy`, and custom `:individual`
    #. SASC actions to fetch the record to operate on. You can override it to customize the behavior of these methods:
    #.
    #. ```ruby
    #. class DogsController
    #.   include SASCConcern
    #
    #.   def model_scope
    #.     Dog.all
    #.   end
    #.
    #.   def fetch_individual_record
    #.     # Doesn't matter which dog you wanted to pet, the bossiest dog always shoulders through to the front
    #.     return model_scope.order(bossiness: :desc).first
    #.   end
    #. end
    #. ```
    #.
    #. Should return `nil` if there isn't a good way to pick one record from the params (e.g. an index request).
    def fetch_individual_record
      # FIXME: We should raise an error instead of returning nil if the id param is missing
      return nil unless params.key?(:id) || @individual_record
      @individual_record ||= model_scope.find(params.require(:id))
    end

    #% SASCConcern#build_record
    #. Returns a new empty record to use as a base for `sasc_create`.
    #.
    #. By default, it just calls `model_scope.build`. You can override this method to customize the behavior of
    #. `sasc_create`.
    def build_record
      model_scope.build
    end

    private

    def cache_store
      self.class.sasc_caching_config[:store]
    end

    def supported_client_versions
      {
        'swell-ios' => Semantic::Version.new(ENV['MIN_IOS_CLIENT_VERSION']),
      }
    end

    def resourcify(record)
      sasc_resource_class.new(record, context)
    end

    def build_cache_key(method, src, inclusions: {})
      return nil unless self.class.sasc_caching_config.key?(:store)

      src_scope = src.is_a?(String) ? model_scope.where(id: src) : src

      ids = []
      max_updated_at = nil
      src_scope.pluck(:id, self.class.sasc_caching_config[:key]).each do |id, updated_at|
        ids << id unless ids.include?(id)
        max_updated_at = updated_at if max_updated_at.nil? || updated_at > max_updated_at
      end

      inc_ids = inclusions.keys.join(",")
      ["sasc_resp", self.class.name, method.to_s, @api_version, ids.join(","), max_updated_at, inc_ids].join("/")
    end

    def render_with_caching(cache_key, id_or_ids)
      expires_in = self.class.sasc_caching_config[:expires_in]
      gzipped_body = cache_store.read(cache_key)

      if gzipped_body.nil?
        @caching_report = :miss
        Statsd.increment("#{self.class.name.split('::').last}.cache_miss")
        gzipped_body = UpdateCacheWorker.new.perform(
          cache_key,
          id_or_ids,
          self.class.name,
          derive_resource_class.to_s,
          expires_in,
          context
        )
      else
        @caching_report = :hit
        Statsd.increment("#{self.class.name.split('::').last}.cache_hit")
      end

      # TODO: Remove this check once we're sure we don't need it anymore
      unless ENV['DISABLE_BACKGROUND_CACHING'] == 'true'
        if (expires_at = cache_store.read("#{cache_key}_expires_at")) &&
          expires_at <= (expires_in / 2).seconds.from_now
          UpdateCacheWorker.perform_async(
            cache_key,
            id_or_ids,
            self.class.name,
            derive_resource_class.to_s,
            expires_in,
            context
          )
        end
      end

      render_with_gzip_encoding(gzipped_body)
    end

    def render_without_caching
      json = yield
      render body: ActiveSupport::JSON.encode(json)
    end

    def render_with_gzip_encoding(gzipped_body)
      if gzip_response_ok?
        response.headers["Content-Encoding"] = "gzip"
        Statsd.increment("#{self.class.name.split('::').last}.content-encoding.gzip")
        send_data gzipped_body, type: :json
      else
        uncompressed_body = ActiveSupport::Gzip.decompress(gzipped_body) if uncompressed_body.nil?
        render body: uncompressed_body
      end
    end

    def gzip_response_ok?
      (request.headers["Accept-Encoding"] || "").split(/\s*,\s*/).include?("gzip")
    end

    def derive_resource_class
      (self.class.name.sub(/Controller$/, '').demodulize.singularize + "Resource").constantize
    end

    def filtered_scope(scope, filter_param)
      filter_param.reduce(scope) do |acc, (key, value)|
        begin
          case key
          when :id then id_filtered_scope(acc, value)
          else custom_filtered_scope(acc, key, value)
          end
        rescue SASC::Errors::BaseError => e
          e.parameter = "filter[#{key}]" if e.parameter.blank?
          raise
        end
      end
    end

    def id_filtered_scope(scope, ids)
      assert_valid_query_parameter!({ type: :array, items: { type: :string } }, ids)
      scope.where(id: ids)
    end

    def custom_filtered_scope(scope, key, value)
      ruby_key = key.to_s.underscore.to_sym
      filter = self.class.sasc_filters[ruby_key]
      raise SASC::Errors::UnknownQueryParameter.new("No such filter") unless filter
      assert_valid_query_parameter!(filter[:type], value)
      instance_exec(scope, value, &filter[:block])
    end

    def assert_valid_query_parameter!(schema, value)
      unless SASC::Validation.valid?(schema, value)
        raise SASC::Errors::InvalidQueryParameterValue.new("Schema mismatch on query parameter")
      end
    end

    def get_required_header(name)
      unless request.headers[name].present?
        raise SASC::Errors::BadHeader.new("Missing required header", header: name)
      end

      request.headers[name]
    end

    def resolve_api_version
      header = get_required_header("x-sasc-api-version")

      begin
        @api_version = header.to_version
      rescue ArgumentError
        raise SASC::Errors::BadHeader.new("Header does not contain a valid semver", header: "x-sasc-api-version")
      end

      unless SASC::Versioning.versions.key?(@api_version)
        raise SASC::Errors::UnknownApiVersion.new(
          "Requested API version is not recognized",
          detail: "The server has no configuration to provide API version '#{@api_version}'"
        )
      end
    rescue
      @api_version = SASC::Versioning.latest_version
      raise
    end

    def ensure_protocol_version_correct
      unless get_required_header("X-SASC") == "1.0.0"
        raise SASC::Errors::BadHeader.new("Unrecognized protocol version, should be '1.0.0'", header: "X-SASC")
      end
    end

    def parse_client_header
      match = /\A([a-z0-9-]+) (\S+) (\d+)\z/.match(get_required_header("X-SASC-Client"))
      raise SASC::Errors::BadHeader.new("Header format is invalid", header: "X-SASC-Client") unless match

      @client_name = match[1]

      begin
        @client_version = match[2].to_version
      rescue ArgumentError
        raise SASC::Errors::BadHeader.new("Client version is not a valid semver", header: "X-SASC-Client")
      end

      @client_build_timestamp = match[3].to_i
    end

    def ensure_client_version_not_deprecated
      minimum_version = supported_client_versions[@client_name]
      unless minimum_version.nil? || @client_version >= minimum_version
        raise SASC::Errors::DeprecatedClientVersion.new(
          "#{@client_name} version #{@client_version} has been deprecated"
        )
      end
    end

    def load_included_resources(records, inclusions, resource_context)
      included_resources = inclusions.reduce(Set.new) do |acc, (method_path, included_resource_class)|
        included_records = follow_inclusion_path(records, method_path) - records.to_a

        acc.union(included_records.map { |rec| included_resource_class.new(rec, resource_context) })
      end

      included_resources.empty? ? nil : included_resources.group_by { |res| res.class.type_name }
    end

    def path_methods(method_path)
      method_path.to_s.split(".").map(&:to_sym)
    end

    def follow_inclusion_path(records, method_path)
      included_records = path_methods(method_path).reduce(records) do |acc, method|
        acc.flat_map(&method)
      end

      included_records.compact
    end

    def ensure_json_response_acceptable
      accepted_types = request.headers["Accept"].to_s.split(",").map(&:strip).map { |str| str.sub(/;q=.+\z/, '') }
      unless accepted_types.any? { |type| type == "*/*" || type == "application/json" }
        raise SASC::Errors::BadAcceptHeader.new("The request Accept header must permit application/json")
      end
    end

    def parse_query_param(param)
      if param.is_a?(String)
        JSON.load(param)
      elsif param.is_a?(Hash)
        param.map { |k, v|
          begin
            [k.to_sym, parse_query_param(v)]
          rescue SASC::Errors::InvalidQueryParameterValue => e
            # Re-raise the same error, but prepending this additional step on the JSON path to the failed parameter
            raise SASC::Errors::InvalidQueryParameterValue.new(e.title, parameter: [k] + (e.parameter || []))
          end
        }.to_h
      end
    rescue JSON::JSONError
      raise SASC::Errors::InvalidQueryParameterValue.new(
        "Invalid JSON. Hint: double quote string query parameters ala filter[foo]=\"bar\""
      )
    end

    def action_arguments
      arguments = params['arguments']
      if arguments.nil?
        raise SASC::Errors::InvalidRequestDocumentContent.new("Arguments must be provided", pointer: "/arguments")
      end
      unless arguments.is_a?(ActionController::Parameters)
        raise SASC::Errors::InvalidRequestDocumentContent.new("Arguments must be an object", pointer: "/arguments")
      end
      arguments.to_unsafe_hash
    end
  end
end
