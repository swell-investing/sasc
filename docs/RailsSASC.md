# SASC on the server side with Rails

You implement SASC resources in Rails with two pieces:

* Controllers which derive from [Api::SASCBaseController](#apisascbasecontroller)
* Resource classes which derive from [SASC::Resource](#sascresource)

This document details all the tools that these classes provide you.

You might also be interested in:

* [The formal definition of SASC as a protocol](SwellAPIStandardConvention.md)
* [The client-side Redux resourceLib reference](ReduxSASC.md)
* [The SASCification guide](SASCificationGuide.md)

## Table of Contents

<!-- All text below this point can be regenerated from the source comments by yarn run docs -->
<!-- DO NOT EDIT THE TEXT BELOW MANUALLY, YOUR CHANGES WILL BE LOST! -->

<!-- toc -->

- [Api::SASCBaseController](#apisascbasecontroller)
  * [`Api::SASCBaseController.sasc_action(name, kind, arguments: {}, result: {}) do...`](#Api%3A%3ASASCBaseController.sasc_action%28name%2C%20kind%2C%20arguments%3A%20%7B%7D%2C%20result%3A%20%7B%7D%29%20do...)
  * [`Api::SASCBaseController.sasc_filter(name, type, description:, &block)`](#Api%3A%3ASASCBaseController.sasc_filter%28name%2C%20type%2C%20description%3A%2C%20%26amp%3Bblock%29)
  * [`Api::SASCBaseController.enable_sasc_caching(store: Rails.cache, key: :updated_at, expires_in: 30.minutes)`](#Api%3A%3ASASCBaseController.enable_sasc_caching%28store%3A%20Rails.cache%2C%20key%3A%20%3Aupdated_at%2C%20expires_in%3A%2030.minutes%29)
  * [`Api::SASCBaseController#index`](#Api%3A%3ASASCBaseController%23index)
  * [`Api::SASCBaseController#show`](#Api%3A%3ASASCBaseController%23show)
  * [`Api::SASCBaseController#resource_class`](#Api%3A%3ASASCBaseController%23resource_class)
  * [`Api::SASCBaseController#model_scope`](#Api%3A%3ASASCBaseController%23model_scope)
  * [`Api::SASCBaseController#default_inclusions`](#Api%3A%3ASASCBaseController%23default_inclusions)
  * [`Api::SASCBaseController#context`](#Api%3A%3ASASCBaseController%23context)
  * [`Api::SASCBaseController#sasc_index()`](#Api%3A%3ASASCBaseController%23sasc_index%28%29)
  * [`Api::SASCBaseController#sasc_show()`](#Api%3A%3ASASCBaseController%23sasc_show%28%29)
  * [`Api::SASCBaseController#sasc_create()`](#Api%3A%3ASASCBaseController%23sasc_create%28%29)
  * [`Api::SASCBaseController#sasc_update()`](#Api%3A%3ASASCBaseController%23sasc_update%28%29)
  * [`Api::SASCBaseController#sasc_destroy`](#Api%3A%3ASASCBaseController%23sasc_destroy)
  * [`Api::SASCBaseController#fetch_index_records`](#Api%3A%3ASASCBaseController%23fetch_index_records)
  * [`Api::SASCBaseController#fetch_individual_record`](#Api%3A%3ASASCBaseController%23fetch_individual_record)
  * [`Api::SASCBaseController#build_record`](#Api%3A%3ASASCBaseController%23build_record)
- [SASC::Errors](#sascerrors)
  * [`SASC::Errors::with_validation_error_reporting`](#SASC%3A%3AErrors%3A%3Awith_validation_error_reporting)
  * [`SASC::Errors::BaseError`](#SASC%3A%3AErrors%3A%3ABaseError)
  * [`SASC::Errors::ReservedError`](#SASC%3A%3AErrors%3A%3AReservedError)
  * [`SASC::Errors::InternalError`](#SASC%3A%3AErrors%3A%3AInternalError)
- [SASC::Resource](#sascresource)
  * [`SASC::Resource.type_name`](#SASC%3A%3AResource.type_name)
  * [`SASC::Resource.res_decoration(decoration: :decorate)`](#SASC%3A%3AResource.res_decoration%28decoration%3A%20%3Adecorate%29)
  * [`SASC::Resource.res_version_translation(translator_class)`](#SASC%3A%3AResource.res_version_translation%28translator_class%29)
  * [`SASC::Resource.new(record, context = {})`](#SASC%3A%3AResource.new%28record%2C%20context%20%3D%20%7B%7D%29)
  * [`SASC::Resource.record`](#SASC%3A%3AResource.record)
  * [`SASC::Resource.context`](#SASC%3A%3AResource.context)
  * [`SASC::Resource.id`](#SASC%3A%3AResource.id)
  * [`SASC::Resource.res_attribute(ruby_name, json_type, **kwargs)`](#SASC%3A%3AResource.res_attribute%28ruby_name%2C%20json_type%2C%20**kwargs%29)
  * [`SASC::Resource.res_has_one_relationship(ruby_name, resource_type, **kwargs)`](#SASC%3A%3AResource.res_has_one_relationship%28ruby_name%2C%20resource_type%2C%20**kwargs%29)
  * [`SASC::Resource.res_has_many_relationship(ruby_name, resource_type, **kwargs)`](#SASC%3A%3AResource.res_has_many_relationship%28ruby_name%2C%20resource_type%2C%20**kwargs%29)
  * [`SASC::Resource.res_creatable`](#SASC%3A%3AResource.res_creatable)
  * [`SASC::Resource.res_updatable`](#SASC%3A%3AResource.res_updatable)
  * [`SASC::Resource.res_destroyable`](#SASC%3A%3AResource.res_destroyable)
  * [`transient_fields`](#transient_fields)
- [SASC::Versioning](#sascversioning)
  * [`SASC::Versioning.versions`](#SASC%3A%3AVersioning.versions)
  * [`SASC::Versioning.latest_version`](#SASC%3A%3AVersioning.latest_version)
  * [`SASC::Versioning.create_translator`](#SASC%3A%3AVersioning.create_translator)
- [SASCHelpers](#saschelpers)
  * [`set_sasc_request_headers`](#set_sasc_request_headers)
  * [`be_sasc_error`](#be_sasc_error)

<!-- tocstop -->

<!--transcribe-->

## Api::SASCBaseController
Controllers which provide SASC resources should derive from SASCBaseController. Many features are automatically
provided with sensible defaults. The only thing you always must manually provide is the `model_scope` method. For
example, here is a complete controller that provides `index` and `show` for the resource class `DogKennelResource`
and the ActiveRecord class `DogKennel`:

```ruby
class DogKennelsController < SASCBaseController
  def model_scope
    DogKennel.all
  end
end
```

To add more functionality beyond `index` and `show`, or to override the default behavior, see the method definitons
below.

**NOTE:** When creating a new controller, don't forget that you also need to create routes! And remember that
the Rails routing DSL defaults to underscore-separated paths, which are not valid for SASC. You will need to
provide a `path` argument to the route for multi-word resource types:

```ruby
 namespace :api
   resources :dog_kennels, path: '/dog-kennels', only: [:index, :show]
 end
```

### <a name="Api::SASCBaseController.sasc_action(name, kind, arguments: {}, result: {}) do..." href="../app/controllers/api/sasc_base_controller.rb#L74">`Api::SASCBaseController.sasc_action(name, kind, arguments: {}, result: {}) do...`</a>
Define a custom SASC action, i.e. an RPC-ish action that doesn't fit in the CRUD model

* `name`: The name of the action, an underscore-separated symbol
* `kind`: Must be `:individual` or `:collection`. Use `:individual` if the action operates on a specific resource
          by id, otherwise use `:collection`
* `arguments`: A hash describing required argument keys in the request from the client. Map each key to a JSON
               type, e.g.  `:object` or `:string`
* `results`: A hash describing result keys for the response. Map each key to a JSON type, e.g. `:object` or
             `:string`, or to a resource class, e.g. 'UserResource'
* `block`: Implementation of the action itself

Specify all names (e.g. of actions, arguments, and results) as underscore-separated symbols. They will
automatically be converted to and from camel case whenever JSON is generated or parsed.

When the server receives a request for a collection action, the block will be called with a hash containing the
arguments. Within the block, perform whatever operation is needed, and then end with a results hash.

```ruby
 class DogKennelsController < SASCBaseController
   sasc_action :run_iditarod, :collection,
               arguments: { route: :string },
               result: { days_elapsed: :integer } do |arguments|
     days = musher_service.run("iditarod", arguments[:route])
     { days_elapsed: days }
   end

   private

   def musher_service
     @musher_service ||= MusherService.new
   end
 end
```

Both `arguments` and `result` are optional; many actions don't require any arguments, or don't need to report
anything back to the client beyond the simple fact of success. Note that if you don't specify any result keys,
you still *must* end with a results hash (which in this case would be empty):

```ruby
 sasc_action :run_standard_iditarod, :collection do
   musher_service.run("iditarod", DEFAULT_ROUTE)
   {}
end
```

For `:individual` requests, your block will also be passed the target resource object:

```ruby
 sasc_action :bark, :individual, arguments: { loudness: :integer } do |resource, arguments|
   resource.record.make_noise(arguments[:loudness])
   {}
 end
```

### <a name="Api::SASCBaseController.sasc_filter(name, type, description:, &amp;block)" href="../app/controllers/api/sasc_base_controller.rb#L154">`Api::SASCBaseController.sasc_filter(name, type, description:, &block)`</a>
Configures a filter for index results based on the return value of the passed-in block

* `name`: An underscored symbol. This will become camel-cased when it is used as a URL parameter
          to request a limited scope of records from the client.
* `type`: A symbol or a hash (containing a JSON schema document) describing the JSON type of the query value
* `description`: A string documenting what the filter does
* `block`: A proc that takes two arguments - a scope and a query value - and returns a new scope

```ruby
class DogsController < SASCBaseController
  sasc_filter(:minimum_goodness, :integer, description: "Requires good dogs") do |scope, arg|
    scope.where('goodness >= ?', arg)
  end
end
```

A URL to request dogs that are good enough using this filter would look like:
`/api/dogs?filter[minimumGoodness]=3`

Inside the block you can also use custom scopes defined on the model.

```ruby
class Dog < ActiveRecordBase
  def self.good_dogs
    where(loves_walks: true).where(bitey: false)
  end

  def self.bad_dogs
    where(bitey: true)
  end
end

class DogsController < SASCBaseController
  sasc_filter(:is_good, :boolean, description: "Limits dogs by goodosity") do |scope, arg|
    if arg
      scope.good_dogs
    else
      scope.bad_dogs
    end
  end
end
```

A URL to request only the good dogs using this filter would look like:
`/api/dogs?filter[isGood]=true`

### <a name="Api::SASCBaseController.enable_sasc_caching(store: Rails.cache, key: :updated_at, expires_in: 30.minutes)" href="../app/controllers/api/sasc_base_controller.rb#L210">`Api::SASCBaseController.enable_sasc_caching(store: Rails.cache, key: :updated_at, expires_in: 30.minutes)`</a>
Configures the controller to use gzipped cached responses to speed up `index` and `show` requests.

* `store`: An ActiveSupport::Cache::Store. If not specified, uses the default Rails cache.
* `key`: A value on the record that increases every time it is changed. Defaults to `updated_at`.
* `expires_in`: How long between when an entry is cached and when it is automatically dropped. Defaults to
   30 minutes.

```ruby
class DogsController < SASCBaseController
  enable_sasc_caching

  def model_scope
    # If this were changed to e.g. Dog.where(owner: current_user), then
    # you would have to disable caching!
    Dog.all
  end
end
```

Caching improves response times, but creates a risk that you will serve stale data unless you are careful about
making sure the caching system notices when output should change. Caching should only be enabled if *all* these
conditions are true:

* The session (e.g. whether or not the user is logged in) has no effect on each resource's output. In particular,
  if the resource uses the `current_user` from context to change its JSON output, then you cannot safely enable
  caching. **Otherwise the results of one user's request might be shown to another user.**
* The model must have an `updated_at` field, or something similar, which must be guaranteed to rise every
  time the model changes.
* For every relationship described by the resource, any change to the related model (including creation and
  destruction) must also increase the `updated_at` value of the source model.

For example, if `DogResource` `res_has_many_relationship :bones`, then whenever a `Dog`'s `Bone` is changed, the
`updated_at` of the `Dog` must be increased. If the `Bone` model `belongs_to :dog`, then you can use the `touch`
option on `belongs_to` to accomplish this automatically:

```ruby
class Bone < ActiveRecord::Base
  belongs_to :dog, touch: true
end

class Dog < ActiveRecord::Base
  has_many :bones
end

class DogResource < SASC::Resource
  res_has_many_relationship :bones, BoneResource
end
```

For other ActiveRecord relationships, you may need to use ActiveRecord lifecycle callbacks:

```ruby
class WaterBowl < ActiveRecord::Base
  has_many :dogs

  after_save :touch_dogs
  after_destroy :touch_dogs
  after_touch :touch_dogs
  def touch_dogs
    dogs.each(&:touch)
  end
end

class Dog < ActiveRecord::Base
  belongs_to :water_bowl
end

class DogResource < SASC::Resource
  res_has_one_relationship :bowl, WaterBowl
end
```

### <a name="Api::SASCBaseController#index" href="../app/controllers/api/sasc_base_controller.rb#L289">`Api::SASCBaseController#index`</a>
A default `index` method.

The default SASCBaseController provides an `index` method which does nothing but call `sasc_index`. You may want
to override this and provide your own `index` method if you want to customize its behavior:

```ruby
class DogsController < SASCBaseController
  def index
    throw "Wat!" unless current_user.can_index_dogs?
    sasc_index
    Rails.logger.warning "Somebody indexed dogs!"
  end
end
```

Or if you want to disable it entirely:

```ruby
class DogsController < SASCBaseController
  def index
    raise NotImplementedError
  end
end
```

### <a name="Api::SASCBaseController#show" href="../app/controllers/api/sasc_base_controller.rb#L318">`Api::SASCBaseController#show`</a>
A default `show` method.

The default SASCBaseController provides an `show` method which does nothing but call `sasc_show`. You may want
to override this and provide your own `show` method if you want to customize its behavior or disable it. See
the examples above for `index`.

### <a name="Api::SASCBaseController#resource_class" href="../app/controllers/api/sasc_base_controller.rb#L328">`Api::SASCBaseController#resource_class`</a>
Returns SASC::Resource class that this controller handles.

SASCBaseController provides a default implementation of this method which infers the resource class name based
on the controller name, e.g. `DogsController` is inferred to have a `resource_class` named `DogResource`. If
your resource naming situation is more unusual, you may want to override this method:

```ruby
class CorgiController < SASCBaseController
  def resource_class
    DogResource
  end

  def model_scope
    Dog.where(ground_clearance: "low")
  end
end
```

### <a name="Api::SASCBaseController#model_scope" href="../app/controllers/api/sasc_base_controller.rb#L350">`Api::SASCBaseController#model_scope`</a>
Returns an ActiveRecord scope for records that this controller can access.

All controllers must provide an implementation of this method if they derive from `SASCBaseController`.

Every method in `SASCBaseController` goes through this scope whenever attempting to read or write the model, so
it's a convenient place to set up security rules, e.g. based on `current_user`. For example, to allow non-admin
users to only access their own dogs:

```ruby
class DogsController < SASCBaseController
  def model_scope
    current_user.admin? ? Dog.all : Dog.where(owner: current_user)
  end
end
```

To handle situations where the user has no accessible records, use the `ActiveRecord::Base.none` method:

```ruby
class DogsController < SASCBaseController
  def model_scope
    return Dog.none if current_user.nil? || current_user.cat_person?
    current_user.admin? ? Dog.all : Dog.where(owner: current_user)
  end
end
```

### <a name="Api::SASCBaseController#default_inclusions" href="../app/controllers/api/sasc_base_controller.rb#L381">`Api::SASCBaseController#default_inclusions`</a>
Returns a hash mapping included relationship names to resource classes.

When a related resource is "included", that means that it will be sent in responses along with the main
resources that were directly requested:

```ruby
class DogsController < SASCBaseController
  def model_scope
    Dog.all
  end

  # Responses for dogs will now also include complete records for related bones and chew toys
  def default_inclusions
    { bones: BoneResource, chew_toys: ChewToyResource }
  end
end
```

You can include indirectly related resources by specifying relationship names separated by dots. For example,
suppose dogs have many owners, and owners have many hats, and each hat has a brim. To include every owner
for each rendered dog, and every hat owned by those owners, and the brims of each of those hats:

```ruby
def default_inclusions
  { "owners": OwnerResource, "owners.hats": HatResource, "owners.hats.brim": BrimResource }
end
```

### <a name="Api::SASCBaseController#context" href="../app/controllers/api/sasc_base_controller.rb#L413">`Api::SASCBaseController#context`</a>
Returns a hash of information to be passed to Resource instances from the controller

This is useful for providing Resource-specific services and session data.

The default implementation returns a hash with these keys:
* `current_user`: The currently logged-in User, or `nil` if no-one is logged in
* `client_name`: The name string from the `X-SASC-Client` header in the request
* `client_version`: The semver from the `X-SASC-Client` header in the rquest
* `client_build_timestamp`: The integer timestamp from the `X-SASC-Client` header in the request

To add additional keys, e.g. with services that the resource needs, override this method:

```ruby
class DogsController < SASCBaseController
  def context
    super.merge({
      my_service: my_service
    })
  end

  private

  def my_service
    @my_service ||= MyService.new
  end
end
```

### <a name="Api::SASCBaseController#sasc_index()" href="../app/controllers/api/sasc_base_controller.rb#L464">`Api::SASCBaseController#sasc_index()`</a>
Renders a collection of resources based on the request params

This method calls `fetch_index_records` to scope its response; see its documentation for details.

### <a name="Api::SASCBaseController#sasc_show()" href="../app/controllers/api/sasc_base_controller.rb#L480">`Api::SASCBaseController#sasc_show()`</a>
Renders a resource based on the request params

This method calls `fetch_individual_record` to find the requested resource; see its documentation for details.

### <a name="Api::SASCBaseController#sasc_create()" href="../app/controllers/api/sasc_base_controller.rb#L495">`Api::SASCBaseController#sasc_create()`</a>
Creates a new resource based on the request params

Once a Resource class has been configured to allow creation with `res_creatable`, your controller's `create`
action can simply be a one-line call to `sasc_create`. Here is a complete controller that supports creating new
instances of Dog:

```ruby
class DogsController < SASCBaseController
  def model_scope
    Dog.all
  end

  def create
    sasc_create
  end
end

class DogResource < SASC::Resource
  res_creatable
end
```

Don't forget to also add `:create` to the list of permitted actions on the route:

```ruby
 namespace :api
   resources :dogs, path: '/dogs', only: [:index, :show, :create]
 end
```

This method calls `build_record` to initialize the new resource; see its documentation for details.

### <a name="Api::SASCBaseController#sasc_update()" href="../app/controllers/api/sasc_base_controller.rb#L538">`Api::SASCBaseController#sasc_update()`</a>
Updates a resource based on the request params

Once a Resource class has been configured to allow updates with `res_updatable`, your controller's `update`
action can simply be a one-line call to `sasc_update`. Here is a complete controller that supports updating
instances of Dog:

```ruby
class DogsController < SASCBaseController
  def model_scope
    Dog.all
  end

  def update
    sasc_update
  end
end

class DogResource < SASC::Resource
  res_updatable
end
```

Don't forget to also add `:update` to the list of permitted actions on the route:

```ruby
 namespace :api
   resources :dogs, path: '/dogs', only: [:index, :show, :update]
 end
```

This method calls `fetch_individual_record` to find the requested resource; see its documentation for details.

### <a name="Api::SASCBaseController#sasc_destroy" href="../app/controllers/api/sasc_base_controller.rb#L580">`Api::SASCBaseController#sasc_destroy`</a>
Destroys a resource based on the request params

Once a Resource class has been configured to allow destruction with `res_destroyable`, your controller's
`destroy` action can simply be a one-line call to `sasc_destroy`. Here is a complete controller that supports
destroying instances of Dog:

```ruby
class DogsController < SASCBaseController
  def model_scope
    Dog.all
  end

  def destroy
    sasc_destroy
  end
end

class DogResource < SASC::Resource
  res_destroyable
end
```

Don't forget to also add `:destroy` to the list of permitted actions on the route:

```ruby
 namespace :api
   resources :dogs, path: '/dogs', only: [:index, :show, :destroy]
 end
```

This method calls `fetch_individual_record` to find the requested resource; see its documentation for details.

### <a name="Api::SASCBaseController#fetch_index_records" href="../app/controllers/api/sasc_base_controller.rb#L620">`Api::SASCBaseController#fetch_index_records`</a>
Returns a scope of records based on the request params

This is the method used by `sasc_index` to obtain the set of records to render. You may wish to override this
method to customize its behavior, e.g. to add a default sort order.

```ruby
class DogsController < SASCBaseController
  def model_scope
    Dog.all
  end

  def fetch_index_records
    # Friendliest dogs are first
    return model_scope.order(friendliness: :desc)
  end
end
```

### <a name="Api::SASCBaseController#fetch_individual_record" href="../app/controllers/api/sasc_base_controller.rb#L644">`Api::SASCBaseController#fetch_individual_record`</a>
Returns a single requested record based on the request params

This is the method used by `sasc_show`, `sasc_update`, `sasc_destroy`, and custom `:individual`
SASC actions to fetch the record to operate on. You can override it to customize the behavior of these methods:

```ruby
class DogsController < SASCBaseController
  def model_scope
    Dog.all
  end

  def fetch_individual_record
    # Doesn't matter which dog you wanted to pet, the bossiest dog always shoulders through to the front
    return model_scope.order(bossiness: :desc).first
  end
end
```

Should return `nil` if there isn't a good way to pick one record from the params (e.g. an index request).

### <a name="Api::SASCBaseController#build_record" href="../app/controllers/api/sasc_base_controller.rb#L670">`Api::SASCBaseController#build_record`</a>
Returns a new empty record to use as a base for `sasc_create`.

By default, it just calls `model_scope.build`. You can override this method to customize the behavior of
`sasc_create`.

## SASC::Errors
Errors in SASC are represented as exceptions which derive from `SASC::BaseError`. See its description below for
details about its features and how to derive new error clasess.

### <a name="SASC::Errors::with_validation_error_reporting" href="../lib/sasc/errors.rb#L6">`SASC::Errors::with_validation_error_reporting`</a>
Runs the given block, converting any matching ActiveRecord validation error raised into a SASC error

* `resource`: The resource instance with a record that we are expecting to potentially be invalid

If the block raises a validation error (i.e. ActiveRecord::RecordInvalid or ActiveModel::ValidationError) then
the error will be re-raised as a SASC InvalidFieldValue error. The error will have the `pointer` field set
if there is a matching attribute on the resource and the error record is the given resource's record.

### <a name="SASC::Errors::BaseError" href="../lib/sasc/errors.rb#L48">`SASC::Errors::BaseError`</a>
The base class for all SASC errors.

When deriving your own custom error class, you don't need to specify anything other than the class name; the
error will automatically render using your class name as the error code. For example, to create a new error
class with `EVERYTHING_IS_NOT_FINE` as the SASC error code:

```ruby
class EverythingIsNotFine < SASC::Errors::BaseError
end
```

By default, errors that derive from `BaseError` are rendered with an HTTP status code of `400: Bad Request`. To
customize this, override the `http_status_code` method:

```ruby
class EverythingIsNotFine < SASC::Errors::BaseError
  def http_status_code
    :internal_server_error
  end
end
```

SASC errors have the following attributes, which correspond with the optional fields for error objects as
described in the spec:

* `title`
* `subcode`
* `detail`
* `pointer`
* `parameter`
* `header`
* `meta`

To set these as you construct a SASC error, call the initializer with the title as the first argument and any
additional fields as named arguments:

```ruby
raise EverythingIsNotFine.new("The room is literally on fire!", detail: "Except for my coffee, which is cold")
```

Errors also have a `uuid` property, which is randomly generated on demand unless you specifically set a
uuid yourself:

```ruby
err = EverythingIsNotFine.new("Fiery fire!")
err.uuid = self.request_uuid
raise err
```

### <a name="SASC::Errors::ReservedError" href="../lib/sasc/errors.rb#L188">`SASC::Errors::ReservedError`</a>
A subclass of `BaseError` which is used for all the standard error types defined in the SASC spec.

You should not derive your own domain-specific errors from this class, but instead from `BaseError` itself.

The following ReservedError classes are available, all with the same constructor conventions as `BaseError`. You
can raise these errors yourself in the appropriate situations. See the SASC protocol definition for details.

* `SASC::Errors::InvalidFieldValue`
* `SASC::Errors::UnknownField`
* `SASC::Errors::InvalidQueryParameterValue`
* `SASC::Errors::UnknownQueryParameter`
* `SASC::Errors::MissingRequiredActionArgument`
* `SASC::Errors::InvalidActionArgumentValue`
* `SASC::Errors::UnknownActionArgument`
* `SASC::Errors::InvalidRequestDocumentContent`
* `SASC::Errors::BadIndividualResourceUrlId`
* `SASC::Errors::PermissionDenied`
* `SASC::Errors::IncompatibleApiVersion`
* `SASC::Errors::UnknownApiVersion`
* `SASC::Errors::Unauthorized`
* `SASC::Errors::BadHeader`

### <a name="SASC::Errors::InternalError" href="../lib/sasc/errors.rb#L287">`SASC::Errors::InternalError`</a>
A subclass of `BaseError` which conveniently wraps non-SASC exceptions

Its constructor takes an instance of any exception, followed by the other arguments that the `BaseError`
constructor takes:

```ruby
def my_method
  foo
rescue FooError => e
  raise SASC::Errors::InternalError(e, "Bar!", detail: "Baz narf")
end
```

When rendered, an `InternalError`'s HTTP status is 500, and its `code` is based on the class name of the wrapped
error. For example, the `InternalError` in the example above would have the SASC error code `FOO_ERROR`.

The error passed to `InternalError` during construction can be accessed by calling the `wrapped_error` method.

## SASC::Resource
Subclass SASC::Resource to describe how a model is serialized to/from SASC-compliant JSON

Instances of SASC::Resource wrap a `record`, an instance of the corresponding model class. Most operations on a
Resource instance involve computation and/or mutation of the wrapped record.

When Resources are serialized or deserialized, their data is converted to/from SASC JSON attributes and
relationships. Attributes contain actual data from the record, while relationships indicate the type and ID of
other resources associated with this one.

### <a name="SASC::Resource.type_name" href="../lib/sasc/resource.rb#L16">`SASC::Resource.type_name`</a>
Returns the SASC type name of this resource, a dash-separated plural lowercase string

The default implementation derives the resource name from the class name:

```ruby
class DogKennelResource < SASC::Resource
end

DogKennelResource.type_name # => "dog-kennels"
```

You may wish to customize this:

```ruby
class DogKennelResource < SASC::Resource
  def self.type_name
    "dog-residences"
  end
end
```

### <a name="SASC::Resource.res_decoration(decoration: :decorate)" href="../lib/sasc/resource.rb#L49">`SASC::Resource.res_decoration(decoration: :decorate)`</a>
Configure record decoration

When enabled, the decorator is automatically applied before the record is accessed in any way.

* `decoration`: How the record is decorated. Can be a proc which accepts the record and returns a decorated
  record, or a symbol which names a decoration method on the record.

If you're using a Draper decorator, then you don't need to specify any parameter, and the `decorate` method
will automatically be used.

```ruby
class DogDecorator < Draper::Decorator
end

class DogResource < SASC::Resource
  res_decoration
end
```

### <a name="SASC::Resource.res_version_translation(translator_class)" href="../lib/sasc/resource.rb#L76">`SASC::Resource.res_version_translation(translator_class)`</a>
Configure support for older API versions with a translator

When enabled, the translator is used for mutation and serialization if `context[:api_version]`
is below the current version.

* `translator_class`: A class deriving from Glossator::Translator

### <a name="SASC::Resource.new(record, context = {})" href="../lib/sasc/resource.rb#L87">`SASC::Resource.new(record, context = {})`</a>
Construct an instance of the Resource class around a given record

* `record`: The record object to wrap
* `context`: A hash containing services and meta-information which is not part of the record itself

Subclasses of `SASC::Resource` must have compatible constructors in order to be properly compatible with
`SASCBaseController`.

### <a name="SASC::Resource.record" href="../lib/sasc/resource.rb#L106">`SASC::Resource.record`</a>
Returns the wrapped record, decorating it first if `res_decoration` has been configured

### <a name="SASC::Resource.context" href="../lib/sasc/resource.rb#L115">`SASC::Resource.context`</a>
Returns the `context` hash passed in during construction

### <a name="SASC::Resource.id" href="../lib/sasc/resource.rb#L121">`SASC::Resource.id`</a>
Returns the id of the resource.

The id must be a string to be compliant with SASC.

The default implementation calls the `id` method on the `record`, but you can override this method to customize
this behavior.

### <a name="SASC::Resource.res_attribute(ruby_name, json_type, **kwargs)" href="../lib/sasc/resource_field_definition_concern.rb#L6">`SASC::Resource.res_attribute(ruby_name, json_type, **kwargs)`</a>
Configures an attribute of the resource

* `ruby_name` The name of the attribute as an underscored symbol
* `json_type` The JSON type of the value, e.g. `:string`, `:integer`, or `:array`
* `settable_for:` An array containing `:update` and/or `:create`, indicating whether the attribute can be
  modified during update and/or create actions. Defaults to permitting neither.
```ruby
class DogResource < SASC::Resource
  res_attribute :created_at, :string # Read-only
  res_attribute :name, :string, settable_for: [:create, :update]  # Can be set on create and changed on update
  res_attribute :breed, :string, settable_for: [:create] # Can be set on create but never changed after that
end
```
* `lookup:` If specified, configures how the value of the attribute can be read from the record. By
  default, it tries to call a method on the record with the same name as the attribute. If you specify
  a symbol here, it names a different method on the record to call. If you specify
  a proc here, it will be passed the resource instance and should return the attribute value.
```ruby
class DogResource < SASC::Resource
  res_attribute :name, :string  # Calls `resource.record.name`
  res_attribute :age, :integer, lookup: :age_in_years  # Calls `resource.record.age_in_years`
  res_attribute :loud, :boolean, lookup: -> (res) { res.record.barkiness > 5 }
end
```
* `assign:` If specified, configures how the new value of the attribute can be written to the record. By
  default, it tries to call a setter method on the record with the same name as the attribute, e.g.
  setting an attribute named `foo` would attempt to call `:foo=' on the record. If you specify
  a symbol here, it names a different method on the record to call with the new value. If you specify
  a proc here, it will be passed the resource instance and the new value.
```ruby
class DogResource < SASC::Resource
  # An association that's presented by the API as though it were a regular attribute
  res_attribute :favorite_toy_name, :string, :settable_for: [:create, :update],
                lookup: (res) -> { res.record.favorite_toy&.name },
                assign: (res, name) -> { res.record.favorite_toy = Toy.find_by(name: name) }
end
```
* `transient_assign:` If specified, setting the attribute will not cause any change to the record itself,
  but instead the new value will be saved in `transient_fields` for later processing in `res_creatable`
  and/or `res_updatable` blocks. You can specify `true` here to put the value directly in `transient_fields`,
  or specify a proc to transform the value before it is put into `transient_fields`.
```ruby
class DogResource < SASC::Resource
  res_attribute :new_puppies, :string, :settable_for: [:update],
                hidden: true, transient_assign: true

  res_updatable do |res|
    if res.transient_fields.has_key?(:new_puppies)
      res.transient_fields[:new_puppies].each do |puppy_name|
        res.record.puppies.create!(name: puppy_name)
      end
    end

    res.record.save!
  end
end
```
* `hidden:` If specified as `true`, prevents the attribute from being rendered at all. This is useful for
  write-only attributes and when `transient_assign` is set.

Note that `id` is handled specially; you should *not* create an `id` attribute.

### <a name="SASC::Resource.res_has_one_relationship(ruby_name, resource_type, **kwargs)" href="../lib/sasc/resource_field_definition_concern.rb#L74">`SASC::Resource.res_has_one_relationship(ruby_name, resource_type, **kwargs)`</a>
Configures a singular relationship on the resource

* `ruby_name` The name of the relationship as an underscored symbol
* `resource_type` The Resource class of the target resource
* `settable_for:` An array containing `:update` and/or `:create`, indicating whether the relationship can be
  modified during update and/or create actions. Defaults to permitting neither.
```ruby
class DogResource < SASC::Resource
   # Read-only
  res_has_one_relationship :breed, DogBreedResource

  # Can be set on create and changed on update
  res_has_one_relationship :owner, UserResource, settable_target_scope: User.all,
                           settable_for: [:create, :update]

  # Can be set on create but never changed after that
  res_has_one_relationship :mother, DogResource, settable_target_scope: Dog.all,
                           settable_for: [:create]
end
```
* `settable_target_scope:` When setting a new value to this relationship, this scope is used to look up the
  target resource by id. You must specify `settable_target_scope` if you specify `settable_for`. To allow
  any target record, you can specify the target ActiveRecord class here. Or, you can specify a proc, which
  is passed the resource and should return an ActiveRecord scope.
```ruby
class DogResource < SASC::Resource
  res_has_one_relationship :owner, UserResource, settable_for: [:create, :update],
                           settable_target_scope: User.where(likes_dogs: true)

  res_has_one_relationship :mother, DogResource, settable_for: [:create],
                           settable_target_scope: (res) -> { Dog.possible_parents_for(res.record) }
end
```
* `lookup:` If specified, configures how the associated record can be found. By
  default, it tries to call a method on the source record with the same name as the relationship. If you
  specify a symbol here, it names a different method on the record to call. If you specify a proc here, it will
  be passed the resource instance and should return the target record instance.
```ruby
class DogResource < SASC::Resource
  res_has_one_relationship :mother, DogResource # Calls `resource.record.mother`
  res_has_one_relationship :father, DogResource, lookup: :dad  # Calls `resource.record.dad`
  res_has_one_relationship :youngest_sibling, DogResource,
                           lookup: -> (res) { res.record.siblings.order_by(:age).first }
end
```
* `assign:` If specified, configures how the new value of the relationship can be written to the record. By
  default, it tries to call a setter method on the record with the same name as the relationship, e.g.
  setting a relationship named `foo` would attempt to call `:foo=' on the record. If you specify
  a symbol here, it names a different method on the record to call with the new value. If you specify
  a proc here, it will be passed the resource instance and the new value.
```ruby
class DogResource < SASC::Resource
  # An association called `human` on the model, but the API presents it as `owner` for both reads and writes
  res_has_one_relationship :owner, UserResource, settable_for: [:create, :update],
                           settable_target_scope: User.all,
                           lookup: :human, assign: :human=

  res_has_one_relationship :food, FoodResource, settable_for: [:create, :update],
                           settable_target_scope: Food.all,
                           assign: (res, food) -> { res.context[:food_store].buy_for_dog(res.record, food) }
end
```
* `transient_assign:` If specified, setting the relationship will not cause any change to the record itself,
  but instead the new value will be saved in `transient_fields` for later processing in `res_creatable`
  and/or `res_updatable` blocks. You can specify `true` here to put the value directly in `transient_fields`,
  or specify a proc to transform the value before it is put into `transient_fields`.
```ruby
class DogResource < SASC::Resource
  res_has_one_relationship :tennis_ball, TennisBall, :settable_for: [:update],
                           hidden: true, transient_assign: true

  res_updatable do |res|
    if res.transient_fields.has_key?(:tennis_ball)
      if res.record.object_held_in_mouth.present?
        res.record.drop_it_drop_it_drop_it_okay_good_boy!
      end
      res.record.fetch(res.transient_fields[:tennis_ball])
    end

    res.record.save!
  end
end
```
* `hidden:` If specified as `true`, prevents the relationship from being rendered at all. This is useful for
  write-only relationships and for relationships with `transient_assign` set.

### <a name="SASC::Resource.res_has_many_relationship(ruby_name, resource_type, **kwargs)" href="../lib/sasc/resource_field_definition_concern.rb#L166">`SASC::Resource.res_has_many_relationship(ruby_name, resource_type, **kwargs)`</a>
Configures a plural relationship on the resource

Supports all the same arguments as `res_has_one_relationship` above, except that assignment is not (currently)
supported, so you cannot provide `settable_for`, `settable_target_scope`, `assign`, or
`transient_assign`.

```ruby
class DogResource < SASC::Resource
  res_has_many_relationship :chew_toys, ChewToyResource
end
```

### <a name="SASC::Resource.res_creatable" href="../lib/sasc/resource_mutation_concern.rb#L7">`SASC::Resource.res_creatable`</a>
Allows creation of the resource.

You will also need to add a `create` method to the corresponding controller and set up routing.

By default, new resources are saved by calling `resource.record.save!`. You can customize this behavior
by providing a block to `res_creatable`, which is passed a resource with all fields already assigned:

```ruby
def DogResource < SASC::Resource
  res_attribute :name, :string, settable_for: [:create]
  res_attribute :nickname, :string, settable_for: [:create]

  res_creatable do |resource|
    resource.record.nickname ||= resource.record.name
    resource.record.save!
  end
end
```

### <a name="SASC::Resource.res_updatable" href="../lib/sasc/resource_mutation_concern.rb#L30">`SASC::Resource.res_updatable`</a>
Allows updating the resource.

You will also need to add an `update` method to the corresponding controller and set up routing.

By default, updated resources are saved by calling `resource.record.save!`. You can customize this behavior
by providing a block to `res_updatable`, which is passed a resource with all changed fields already assigned:

```ruby
def DogResource < SASC::Resource
  res_attribute :name, :string, settable_for: [:update]
  res_attribute :nickname, :string, settable_for: [:update]

  res_updatable do |resource|
    if resource.record.name_changed? && !resource.record.nickname_changed?
      resource.record.nickname = resource.record.name
    end
    resource.record.save!
  end
end
```

### <a name="SASC::Resource.res_destroyable" href="../lib/sasc/resource_mutation_concern.rb#L55">`SASC::Resource.res_destroyable`</a>
Allows destroying the resource.

You will also need to add a `destroy` method to the corresponding controller and set up routing.

By default, resources are destroyed by calling `resource.record.destroy!`. You can customize this behavior
by providing a block to `res_destroyable`, which is passed the resource:

```ruby
def BeachBallResource < SASC::Resource
  res_destroyable do |resource|
    if resource.record.inflated?
      resource.record.pop!
    end
    resource.record.destroy!
  end
end
```

### <a name="transient_fields" href="../lib/sasc/resource_mutation_concern.rb#L118">`transient_fields`</a>
Returns a hash of transient fields set during assignment

This method is only useful within `res_creatable` and `res_updatable` blocks, and is always cleared after
those blocks complete.

```ruby
class DogResource < SASC::Resource
  res_attribute :color_code, :string, settable_for: [:create], transient_assign: true

  res_creatable do |resource|
    color = Color.find_by(code: resource.transient_fields[:color_code])
    resource.record.color = color
    resource.record.save!
  end
end
```

## SASC::Versioning
Information about application API versions

### <a name="SASC::Versioning.versions" href="../lib/sasc/versioning.rb#L5">`SASC::Versioning.versions`</a>
Returns a hash describing all available API versions, with Semantic::Version keys

### <a name="SASC::Versioning.latest_version" href="../lib/sasc/versioning.rb#L11">`SASC::Versioning.latest_version`</a>
Returns the most recent version as a Semantic::Version

### <a name="SASC::Versioning.create_translator" href="../lib/sasc/versioning.rb#L17">`SASC::Versioning.create_translator`</a>
Instantiates an appropriate Glossator::Translator

If the given translator class is nil, or if the given target version is equal to the latest
version, then an instance of Glossator::NoOpTranslator is returned. Otherwise, the given
translator class is instantiated with the given target version.

* `translator_class`: A class deriving from Glossator::Translator, or nil
* `target_version`: A Semantic::Version or string with the client's requested API version

## SASCHelpers
These are methods that help with writing tests for SASC controllers.

### <a name="set_sasc_request_headers" href="../spec/support/sasc_helpers.rb#L17">`set_sasc_request_headers`</a>
Set up the necessary headers in `request.headers` for a SASC request

```ruby
RSpec.describe DogsController, type: :controller do
  before do
    set_sasc_request_headers
  end
end
```

### <a name="be_sasc_error" href="../spec/support/sasc_helpers.rb#L32">`be_sasc_error`</a>
An RSpec matcher checking for SASC errors with the given fields in responses

```ruby
RSpec.describe DogsController, type: :controller do
  # ...

  it 'fails with an invalid field value' do
    subject
    expect(response).to be_bad_request
    expect(json).to be_sasc_error(code: '__INVALID_FIELD_VALUE__');
  end
end
```

<!--/transcribe-->
