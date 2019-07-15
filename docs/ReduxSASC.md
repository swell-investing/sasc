# SASC on the client side with Redux

You access SASC resources in React+Redux using resourceLib. This document details all the tools which that library provides.

You might also be interested in:

* [The formal definition of SASC as a protocol](SwellAPIStandardConvention.md)
* [The server-side Rails SASC library reference](RailsSASC.md)
* [The SASCification guide](SASCificationGuide.md)

## Table of Contents

<!-- All text below this point can be regenerated from the source comments by yarn run docs -->
<!-- DO NOT EDIT THE TEXT BELOW MANUALLY, YOUR CHANGES WILL BE LOST! -->

<!-- toc -->

- [ResourceDefinitions](#resourcedefinitions)
  * [`define(resourceType, options)`](#define%28resourceType%2C%20options%29)
- [Resource actions](#resource-actions)
    + [Unpacked resources](#unpacked-resources)
    + [Pids](#pids)
  * [`fetchCollection({ filters, ignoreCache })`](#fetchCollection%28%7B%20filters%2C%20ignoreCache%20%7D%29)
  * [`fetchIndividual({ id, ignoreCache })`](#fetchIndividual%28%7B%20id%2C%20ignoreCache%20%7D%29)
  * [`resourceFetched(payload)`](#resourceFetched%28payload%29)
  * [`create(payload, meta)`](#create%28payload%2C%20meta%29)
  * [`update(payload, meta)`](#update%28payload%2C%20meta%29)
  * [`destroy({ id }, meta)`](#destroy%28%7B%20id%20%7D%2C%20meta%29)
  * [`yourCustomAction({ id, arguments }, meta)`](#yourCustomAction%28%7B%20id%2C%20arguments%20%7D%2C%20meta%29)
- [Resource selectors](#resource-selectors)
  * [`CacheMissException`](#CacheMissException)
  * [`getMany(state, filters = {})`](#getMany%28state%2C%20filters%20%3D%20%7B%7D%29)
  * [`getOne(state, id)`](#getOne%28state%2C%20id%29)
  * [`getOneBy(state, attribute, value)`](#getOneBy%28state%2C%20attribute%2C%20value%29)
  * [`getManyFromRelationship(state, origin, relationship)`](#getManyFromRelationship%28state%2C%20origin%2C%20relationship%29)
  * [`getOneFromRelationship(state, origin, relationship)`](#getOneFromRelationship%28state%2C%20origin%2C%20relationship%29)
  * [`getSomeActionStatus(state, pid = default)`](#getSomeActionStatus%28state%2C%20pid%20%3D%20default%29)
  * [`isSomeActionRunning(state, pid = default)`](#isSomeActionRunning%28state%2C%20pid%20%3D%20default%29)
  * [`isSomeActionDone(state, pid = default)`](#isSomeActionDone%28state%2C%20pid%20%3D%20default%29)
  * [`getSomeActionResult(state, pid = default)`](#getSomeActionResult%28state%2C%20pid%20%3D%20default%29)
  * [`isResourceErrored(state, id)`](#isResourceErrored%28state%2C%20id%29)
  * [`isResourceKnown(state, id)`](#isResourceKnown%28state%2C%20id%29)
  * [`isCollectionErrored(state, filters = {})`](#isCollectionErrored%28state%2C%20filters%20%3D%20%7B%7D%29)
  * [`isCollectionKnown(state, filters = {})`](#isCollectionKnown%28state%2C%20filters%20%3D%20%7B%7D%29)
  * [`isFetching(state)`](#isFetching%28state%29)
- [Selector helpers](#selector-helpers)
  * [`cacheMissOverrideDefault(def, fn)`](#cacheMissOverrideDefault%28def%2C%20fn%29)
  * [`selectorWithDefault(def, selector)`](#selectorWithDefault%28def%2C%20selector%29)
- [Connecting components](#connecting-components)
  * [`WithResources(WrappedComponent, mapSelectorsToProps, mapDispatchToProps = null, options = {})`](#WithResources%28WrappedComponent%2C%20mapSelectorsToProps%2C%20mapDispatchToProps%20%3D%20null%2C%20options%20%3D%20%7B%7D%29)
  * [`safeConnect(mapStateToProps, mapDispatchToProps, mergeProps, connectOptions)`](#safeConnect%28mapStateToProps%2C%20mapDispatchToProps%2C%20mergeProps%2C%20connectOptions%29)
- [Saga helpers](#saga-helpers)
  * [`runResourceProcess(action)`](#runResourceProcess%28action%29)
  * [`diligentSelect(selector, ...args)`](#diligentSelect%28selector%2C%20...args%29)
- [Test helpers](#test-helpers)
  * [`buildResourceState(resources, defaultSequences = {})`](#buildResourceState%28resources%2C%20defaultSequences%20%3D%20%7B%7D%29)
  * [`trapSelect(selectorFn)`](#trapSelect%28selectorFn%29)
  * [`safeSelect(selectorFn)`](#safeSelect%28selectorFn%29)

<!-- tocstop -->

<!--transcribe-->

## ResourceDefinitions
When setting up new resource type on the client, the first step is to define your resource in `client/assets/javascripts/resources.js`. This
will automatically plug the resource into the Redux lifecycle, and generate the various resource-specific selectors
and actions you can use in your own components and sagas.

```javascript
const config = new ResourceDefinitions();
```

### <a name="define(resourceType, options)" href="../client/assets/javascripts/lib/resourceLib.js#L60">`define(resourceType, options)`</a>
Configures a new resource type.

* `resourceType`: The name of the resource, as a dash-separated lowercase plural string, e.g. `'dog-kennels'`
* `options`: Config options for the resource. Any unspecified options will take on their default value.

These are the `options` keys you can provide:

* `fetchCollection`: Flag which enables the `getMany` selectors. (default: `true`)
* `fetchIndividual`: Flag which enables the `getOne` selectors. (default: `true`)
* `create`: Flag with enables the `create` action. (default: `false`)
* `update`: Flag with enables the `update` action. (default: `false`)
* `destroy`: Flag with enables the `destroy` action. (default: `false`)
* `customSascActions`: Object describing custom SASC actions. Keys are dash-separated lowercase strings,
e.g. `run-iditarod`, and value is an object describing the action:
  * `kind`: The type of SASC action. Must be `'individual'` or `'collection'`
  * `invalidation`: Flag which indicates that this action can cause changes in the resource(s), which means that
  cached resource data will need to be refetched after running the action. (default: `false`)

Returns an array of two objects. The first object has the newly generated [selectors](#resourceselectors), and the
second has the new [actions](#resourceactions).

In general, you should have only one instance of `ResourceDefinitions`, and you should centralize all your calls
to `define` in one `resources.js` file.

```javascript
export const [goodDogSelectors, goodDogActions] = config.define('good-dogs', {
  create: true,
  customSascActions: {
    'eat-doggie-biscuit': { kind: 'individual', invalidation: true },
    'run-iditarod': { kind: 'collection' },
  },
});
```

## Resource actions
When you define a new resource, a set of actions are automatically generated. Many of them are used internally
by the resourceLib sagas, but some are intended to be dispatched from your own components and sagas.

#### Unpacked resources

All resource objects included in these actions are *unpacked*, which means that the contents of the `attributes`
object are lifted up to the root level. For example, this means that when creating a resource, you will send
`{ type: 'people', name: 'Person McUser' }`, not `{ type: 'people', attributes: { name: 'Person McUser' } }`.
Note that relationships are not unpacked; they are left nested in the `relationships` object.

#### Pids

CUD actions and custom SASC actions can be created with a `pid` in the `meta` object. The `pid` is a string used to
uniquely track the process of seeing the action through to its final result. For any given resource type and action
type, no more than one process can run at the same time with the same `pid`. When not explicitly supplied, a
constant default `pid` is used.

You don't have to worry about `pid`s unless you want to start multiple similar actions at the same time, which is
unusual.

### <a name="fetchCollection({ filters, ignoreCache })" href="../client/assets/javascripts/lib/resourceLib/resourceActions.js#L49">`fetchCollection({ filters, ignoreCache })`</a>
Dispatch this to request resources from the index route on the server API.

**NOTE**: You probably want to use [selectors](#resourceselectors) instead of dispatching this action
yourself.  That way, you won't unnecessarily re-request the resource if it is already cached. From components,
use `WithResources` or `safeConnect`. From sagas, use `diligentSelect`.

* `filters`: An object describing filters in the request, e.g. `{ id: [1,5,7] }`. (default: `{}`)
* `ignoreCache`: If true, the request will go through even if the result is already in the cache. (default:
`false`)

 ```javascript
 import { dogActions } from 'resources';
 import { runResourceProcess } from 'sagas/helpers';

 function * forceReloadDogsSaga() {
   yield runResourceProcess(dogActions.fetchCollection({ ignoreCache: true }));
 }
 ```

### <a name="fetchIndividual({ id, ignoreCache })" href="../client/assets/javascripts/lib/resourceLib/resourceActions.js#L74">`fetchIndividual({ id, ignoreCache })`</a>
Dispatch this to request a single resource from the show route on the server API.

**NOTE**: You probably want to use [selectors](#resourceselectors) instead of dispatching this action
yourself.  That way, you won't unnecessarily re-request the resource if it is already cached. From components,
use `WithResources` or `safeConnect`. From sagas, use `diligentSelect`.

* `id`: The id of the resource to fetch.
* `ignoreCache`: If true, the request will go through even if the result is already in the cache. (default:
`false`)

 ```javascript
 import { dogActions } from 'resources';
 import { runResourceProcess } from 'sagas/helpers';

 function * forceReloadFirstDogSaga() {
   yield runResourceProcess(dogActions.fetchIndividual({ id: "1", ignoreCache: true }));
 }
 ```

### <a name="resourceFetched(payload)" href="../client/assets/javascripts/lib/resourceLib/resourceActions.js#L101">`resourceFetched(payload)`</a>
This action is dispatched for each resource received from the server.

* `payload`: The resource that was fetched.

You may find it useful to listen for these actions to do follow-up behaviors, such as re-requesting a
resource which you expect to change to a new state soon.

```javascript
import { delay } from 'redux-saga';
import { call, put, takeEvery } from 'redux-saga/effects';
import { dogActions } from 'resources';

export default function * () {
  yield takeEvery(dogActions.resourceFetched.pattern, pollDog);
}

// Keep re-fetching the dog until they stop barking
export function * pollDog({ payload }) {
  if (payload.status == "barking") {
    yield call(delay, 5000);
    // When this fetch completes, it will trigger another resourceFetched action
    yield put(accountActions.fetchIndividual({ ignoreCache: true, id: payload.id }));
  }
}
```

### <a name="create(payload, meta)" href="../client/assets/javascripts/lib/resourceLib/resourceActions.js#L130">`create(payload, meta)`</a>
Dispatch this to create a resource via a POST request to the server.

* `payload`: The unpacked resource to create. This must have a `type`, but must *NOT* have an `id`.
* `meta`: Optional. An object with a `pid` to use for this creation process. See above regarding `pid`
strings.

```javascript
function DogCreationButton(create) {
  const onClick = () => createDog({ type: 'dogs', name: 'Buddy', age: 0 });
  return <a onClick={onClick}>Create a puppy!</a>;
}

function mapDispatchToProps(dispatch) {
  const actionCreators = { createDog: dogActions.create };
  return bindActionCreators(actionCreators, dispatch);
}

export default WithResources(DogCreationButton, null, mapDispatchToProps);
```

### <a name="update(payload, meta)" href="../client/assets/javascripts/lib/resourceLib/resourceActions.js#L156">`update(payload, meta)`</a>
Dispatch this to update a resource via a PATCH request to the server.

* `payload`: Fields to change on the resource. This *MUST* have `type` and `id`. Fields you don't specify will
keep their current value.
* `meta`: Optional. An object with a `pid` to use for this update process. See above regarding `pid`
strings.

```javascript
function DogRenameButton(create) {
  const onClick = () => updateDog({ type: 'dogs', id: '33', name: 'Maximus Prime' });
  return <a onClick={onClick}>Rename the dog!</a>;
}

function mapDispatchToProps(dispatch) {
  const actionCreators = { updateDog: dogActions.update };
  return bindActionCreators(actionCreators, dispatch);
}

export default WithResources(DogRenameButton, null, mapDispatchToProps);
```

### <a name="destroy({ id }, meta)" href="../client/assets/javascripts/lib/resourceLib/resourceActions.js#L183">`destroy({ id }, meta)`</a>
Dispatch this to destroy a resource via a DELETE request to the server.

* `id`: The `id` of the resource to destroy.
* `meta`: Optional. An object with a `pid` to use for this destroy process. See above regarding `pid`
strings.

```javascript
import { diligentSelect, runResourceProcess } from 'sagas/helpers';
import { bananaActions, bananaSelectors } from 'resources';

function * eatBananaIfRipeSaga(action) {
  const bananas = yield diligentSelect(bananaSelectors.getMany);
  const firstBanana = bananas[0];
  if (firstBanana.ripeness > 3) {
    console.log("This banana looks pretty good");
    const deletionAction = bananaActions.destroy({ id: firstBanana.id });
    yield runResourceProcess(deletionAction);
    console.log("Yum yum! Banana is gone now.");
  }
}
```

### <a name="yourCustomAction({ id, arguments }, meta)" href="../client/assets/javascripts/lib/resourceLib/resourceActions.js#L210">`yourCustomAction({ id, arguments }, meta)`</a>
Dispatch this to POST a custom SASC action.

The function name is a camel-cased version of the custom action name you provided to `define`. For example, a
custom SASC action named `run-iditarod` would have an action creation function called `runIditarod`.

* `id`: For `kind: 'individual'` actions, the id of the target resource must be given.
* `arguments`: Some SASC custom actions require arguments. You can supply arguments by providing an object
here.
* `meta`: Optional. An object with a `pid` to use for this process. See above regarding `pid` strings.

```javascript
import { runResourceProcess } from 'sagas/helpers';
import { dogActions } from 'resources';

function * adventureSaga(action) {
  const iditarodAction = dogActions.runIditarod({ arguments: { route: "northern" }});
  const result = yield runResourceProcess(iditarodAction);
  console.log("It took " + result.daysElapsed + " days, but it was worth it!");
}
```

## Resource selectors
When you define a new resource, a set of selectors are automatically generated. These selectors will attempt to find
requested resources in the local cache, and will throw a CacheMissException if they're not found there. To avoid
having to deal with these exceptions yourself, you should use `WithResources` instead of `connect` in your
components, and `diligentSelect` instead of `select` in your sagas.

Keep in mind that you may need to use `WithResources` and `diligentSelect` even if you're not directly calling
a resource selector, because the selector you call might be calling resource selectors on its own. There's no harm
in using `WithResources` or `diligentSelect` even if you don't need to.

### <a name="CacheMissException" href="../client/assets/javascripts/lib/resourceLib/resourceSelectors.js#L29">`CacheMissException`</a>
An exception class representing missing resource(s) which need to be fetched from the server.

You will probably not need to interact this exception class yourself. The best approach is usually to let
`WithResources` and `diligentSelect` worry about catching and correctly responding to these.

CacheMissException instances have these properties:

* `action`: An action that, when dispatched, will request the missing resources from the server
* `default`: A value that will serve as a placeholder for the selector result until the resource is loaded
* `description`: A textual explanation of the exception

### <a name="getMany(state, filters = {})" href="../client/assets/javascripts/lib/resourceLib/resourceSelectors.js#L59">`getMany(state, filters = {})`</a>
Selector for a collection of resources.

* `state`: The Redux state
* `filters`: SASC filters on the request, e.g. `{ id: ["2", "8", "47"] }`

On missing resource, throws a `CacheMissException` with `default` set to an empty array `[]`;

```javascript
import { dogSelectors } from 'resources';

function mapSelectorsToProps(select) {
  return {
    allDogs: select(dogSelectors.getMany),
    primeDogs: select(dogSelectors.getMany, { id: ["2", "3", "5", "7", "11"] }),
  };
}
```

### <a name="getOne(state, id)" href="../client/assets/javascripts/lib/resourceLib/resourceSelectors.js#L120">`getOne(state, id)`</a>
Selector for getting a single resource by id.

* `state`: The Redux state
* `id`: The id of the resource to fetch

On missing resource, throws a `CacheMissException` with `default` set to `null`;

```javascript
import { dogSelectors } from 'resources';

function mapSelectorsToProps(select) {
  return {
    dogOne: select(dogSelectors.getOne, "1");
  };
}
```

### <a name="getOneBy(state, attribute, value)" href="../client/assets/javascripts/lib/resourceLib/resourceSelectors.js#L141">`getOneBy(state, attribute, value)`</a>
Selector for getting a single resource by a particular attribute value.

* `state`: The Redux state
* `attribute`: The attribute to search on, e.g. `'name'`
* `value`: The value to look for in the given attribute, e.g. `'Ada Lovelace'`

Note that if more than one resource has the correct attribute value, there's no particular guarantee about
which one you'll get. In general, this selector should be used for unique attributes.

```javascript
import { dogSelectors } from 'resources';

function mapSelectorsToProps(select) {
  return {
    bigDog: select(dogSelectors.getOneBy, 'size', 'large');
  };
}
```

### <a name="getManyFromRelationship(state, origin, relationship)" href="../client/assets/javascripts/lib/resourceLib/resourceSelectors.js#L192">`getManyFromRelationship(state, origin, relationship)`</a>
Selector for getting a collection of resources related to a given resource.

This will look up the target resources through the `relationships` property on the `origin` resource.

* `state`: The Redux state
* `origin`: A resource object, e.g. the result of `getOne`.
* `relationship`: The name of the relationship on `origin` to traverse.

```javascript
import { dogSelectors, humanSelectors } from 'resources';

function mapSelectorsToProps(select) {
  const dog = select(dogSelectors.getOneBy, "name", "Shadow");
  return {
    owners: select(humanSelectors.getManyFromRelationship, dog, 'owners');
  };
}
```

### <a name="getOneFromRelationship(state, origin, relationship)" href="../client/assets/javascripts/lib/resourceLib/resourceSelectors.js#L221">`getOneFromRelationship(state, origin, relationship)`</a>
Selector for getting a single resource related to a given resource.

This will look up the target resource through the `relationships` property on the `origin` resource.

* `state`: The Redux state
* `origin`: A resource object, e.g. the result of `getOne`.
* `relationship`: The name of the relationship on `origin` to traverse.

```javascript
import { dogSelectors, tagSelectors } from 'resources';

function mapSelectorsToProps(select) {
  const dog = select(dogSelectors.getOneBy, "name", "Shadow");
  return {
    nametag: select(tagSelectors.getOneFromRelationship, dog, 'collarTag');
  };
}
```

### <a name="getSomeActionStatus(state, pid = default)" href="../client/assets/javascripts/lib/resourceLib/resourceSelectors.js#L249">`getSomeActionStatus(state, pid = default)`</a>
Returns the current status of a process.

* For checking a create process, call `getCreationStatus`
* For checking an update process, call `getUpdateStatus`
* For checking a destroy process, call `getDestroyStatus`
* For checking a custom action, call `getActionNameStatus`, e.g. for `upload-file` call `getUploadFileStatus`

The possible statuses it can return can be imported from `resourceLib`, and they are:
`STATUS_UNSTARTED`
`STATUS_RUNNING`
`STATUS_ERRORED`
`STATUS_COMPLETED`

The `pid` argument is optional. See the [Pids section](#pids) for details about when and why you might want to use
it.

```javascript
import { dogSelectors } from 'resources';
import { STATUS_UNSTARTED, STATUS_RUNNING, STATUS_ERRORED, STATUS_COMPLETED } from 'lib/resourceLib';

function mapSelectorsToProps(select) {
  switch(select(dogSelectors.getRunIditarodStatus)) {
    case STATUS_UNSTARTED: return { msg: "The race is about to start!" };
    case STATUS_RUNNING: return { msg: "They're flying across the ice!" };
    case STATUS_ERRORED: return { msg: "Oh no, they've gotten tangled up!" };
    case STATUS_COMPLETED: return { msg: "And now it's time to announce the winner!" };
  }
}
```

### <a name="isSomeActionRunning(state, pid = default)" href="../client/assets/javascripts/lib/resourceLib/resourceSelectors.js#L283">`isSomeActionRunning(state, pid = default)`</a>
Returns a boolean indicating whether a process is currently running or not.

* For checking a create process, call `isCreating`
* For checking an update process, call `isUpdating`
* For checking a destroy process, call `isDestroying`
* For checking a custom action, call `isActionNameRunning`, e.g. for `upload-file` call `isUploadFileRunning`

Internally, all this does is check if `getProcessStatus` returns `resourceLib.STATUS_RUNNING`.

The `pid` argument is optional. See the [Pids section](#pids) for details about when and why you might want to use
it.

```javascript
import { dogSelectors } from 'resources';

function mapSelectorsToProps(select) {
  return {
    showSpinner: select(dogSelectors.isUpdateRunning)
  };
}
```

### <a name="isSomeActionDone(state, pid = default)" href="../client/assets/javascripts/lib/resourceLib/resourceSelectors.js#L310">`isSomeActionDone(state, pid = default)`</a>
Returns a boolean indicating whether a process has completed successfully or not.

* For checking a create process, call `isDoneCreating`
* For checking an update process, call `isDoneUpdating`
* For checking a destroy process, call `isDoneDestroying`
* For checking a custom action, call `isActionNameDone`, e.g. for `upload-file` call `isUploadFileDone`

Internally, all this does is check if `getProcessStatus` returns `resourceLib.STATUS_COMPLETED`.

The `pid` argument is optional. See the [Pids section](#pids) for details about when and why you might want to use
it.

### <a name="getSomeActionResult(state, pid = default)" href="../client/assets/javascripts/lib/resourceLib/resourceSelectors.js#L326">`getSomeActionResult(state, pid = default)`</a>
Returns the final result of a completed process.

* For a creation result, call `getCreationResult`
* For the result of a custom action, call `getActionNameResult`, e.g. for `upload-file` call `getUploadFileResult`

The `pid` argument is optional. See the [Pids section](#pids) for details about when and why you might want to use
it.

```javascript
import { dogSelectors } from 'resources';

function mapSelectorsToProps(select) {
  const busy = select(dogSelectors.isCreating);
  const newDog = busy ? null : select(dogSelectors.creationResult);
  return {
    status: newDog ? `Created dog! ID is ${id}` : (busy ? "Creating dog..." : "Couldn't create dog!")
  };
}
```

### <a name="isResourceErrored(state, id)" href="../client/assets/javascripts/lib/resourceLib/resourceSelectors.js#L385">`isResourceErrored(state, id)`</a>
Returns a boolean indicating whether the most recent attempt to fetch the given resource failed.

* `state`: The Redux state
* `id`: The id of the resource to check

This selector is mostly for internal use; normal application logic is usually better off not using it.

### <a name="isResourceKnown(state, id)" href="../client/assets/javascripts/lib/resourceLib/resourceSelectors.js#L397">`isResourceKnown(state, id)`</a>
Returns a boolean indicating whether we have up-to-date information about the resource in the cache.

Note that a resource is `known` if it is `errored`, because we have the error result cached.

* `state`: The Redux state
* `id`: The id of the resource to check

This selector is mostly for internal use; normal application logic is usually better off not using it.

### <a name="isCollectionErrored(state, filters = {})" href="../client/assets/javascripts/lib/resourceLib/resourceSelectors.js#L411">`isCollectionErrored(state, filters = {})`</a>
Returns a boolean indicating whether the most recent attempt to fetch a collection of resources failed.

* `state`: The Redux state
* `filters`: The filters for the query to check.

This selector is mostly for internal use; normal application logic is usually better off not using it.

### <a name="isCollectionKnown(state, filters = {})" href="../client/assets/javascripts/lib/resourceLib/resourceSelectors.js#L432">`isCollectionKnown(state, filters = {})`</a>
Returns a boolean indicating whether we have up-to-date information about the results of a collection query.

Note that a resource is `known` if it is `errored`, because we have the error result cached.

* `state`: The Redux state
* `filters`: The filters for the query to check.

This selector is mostly for internal use; normal application logic is usually better off not using it.

### <a name="isFetching(state)" href="../client/assets/javascripts/lib/resourceLib/resourceSelectors.js#L459">`isFetching(state)`</a>
Returns a boolean indicating whether any resources are currently being fetched.

* `state`: The Redux state

## Selector helpers

### <a name="cacheMissOverrideDefault(def, fn)" href="../client/assets/javascripts/lib/resourceLib/resourceSelectors.js#L511">`cacheMissOverrideDefault(def, fn)`</a>
Captures `CacheMissException`s and changes their `default` value before re-throwing.

* `def`: The new `default` value to set
* `fn`: The function to run

When called, `cacheMissOverrideDefault` will immediately call `fn` with no parameters, and return `fn`'s return
value if it doesn't throw.

This is likely to useful when you are writing a selector that calls resource selectors to gather
data for a calculation. You can provide a `def` with a type that sensibly matches the type your selector's caller
expects to get, rather than whatever type the internally called selectors return.

```javascript
import { maxBy } from 'lodash';
import { cacheMissOverrideDefault } from `lib/resourceLib`;
import { dogSelectors } from 'resources';

export function selectBiggestDog(state) {
  const allDogs = cacheMissOverrideDefault(null, () => dogSelectors.getMany(state));
  return maxBy(allDogs, 'size');
}
```

### <a name="selectorWithDefault(def, selector)" href="../client/assets/javascripts/lib/resourceLib/resourceSelectors.js#L548">`selectorWithDefault(def, selector)`</a>
A convenience wrapper for the most common use case of `cacheMissOverrideDefault`.

* `def`: The new `default` value to set
* `selector`: The function to wrap

When called, `selectorWith` will return a new function that forwards its arguments to the given `selector`, and
changes the `default` of any `CacheMisException` to `def` before re-throwing it. Using `selectorWithDefault` to
wrap your selector function is often simpler than using `cacheMissOverrideDefault` around every inner selector
call.

The example below is equivalent to the example given above for `cacheMissOverrideDefault`.

```javascript
import { maxBy } from 'lodash';
import { selectorWithDefault } from `lib/resourceLib`;
import { dogSelectors } from 'resources';

export const selectBiggestDog = selectorWithDefault(null, (state) => {
  const allDogs = dogSelectors.getMany(state);
  return maxBy(allDogs, 'size');
});
```

## Connecting components
When you use resource selectors through the regular `mapStateToProps` function as passed to react-redux's `connect`
wrapper, you'll run into trouble with fetching resources. Resource selectors will throw `CacheMissException`s when a
server request needs to be made. Without anything to catch and handle them, the exceptions will just rise all the
way up and cause an error.

So instead of using `connect`, you should use `safeConnect` or `WithResources`. The `safeConnect` wrapper has the
same API as `connect`, so it is the simplest way to solve the problem. However, `WithResources` provides more
control over how your component renders while resources are loading.

### <a name="WithResources(WrappedComponent, mapSelectorsToProps, mapDispatchToProps = null, options = {})" href="../client/assets/javascripts/components/shared/WithResources.jsx#L40">`WithResources(WrappedComponent, mapSelectorsToProps, mapDispatchToProps = null, options = {})`</a>
Connects a component to the state, requesting any missing resources requested by selectors.

You may want to check out [the documentation for react-redux connect](https://bit.ly/1SdzxK3) as reference for
the behavior of this function.

* `WrappedComponent`: A React component function or class
* `mapSelectorsToProps`: A function that uses a given `select` to request data from the store and supply props. It
                         will be called with two arguments: the `select` function, and `ownProps`
* `mapDispatchToProps`: A function that maps action dispatchers to props, just the same as the second argument to
                        react-redux `connect`
* `options`: An object with additional options:
  * `mergeProps`: A optional function that will be used to merge ownProps, selectorProps, and dispatchProps,
                  just the same as the optional third argument to react-redux `connect`
  * `connectOptions`: Additional options, exactly like the options object that `connect` takes as its optional
                      fourth argument

Of the arguments to `WithResources`, all are exactly equivalent to `connect` arguments, except one:
`mapSelectorsToProps`. It is analagous to the `connect` argument `mapStateToProps`, but instead of being given
`state`, it is given a `select` function. The `select` function takes a selector as its first argument, calls
that selector with `state`, and returns the result. Any additional arguments to `select` are sent as further
arguments to the selector:

```javascript
// This function for connect...
function mapStateToProps(state) {
  return {
    foo: someSelector(state),
    bar: anotherSelector(state, "baz")
  };
}

// Is equivalent to this function for WithResources
function mapSelectorsToProps(select) {
  return {
    foo: select(someSelector),
    bar: select(anotherSelector, "baz")
  };
}
```

The reason for all this roundabout is to allow `CacheMissException`s thrown by selectors to be intercepted
and correctly handled. If a `CacheMissException` is thrown from the selector, then `select` will issue a request
to the server in the background and then return the `default` value from CacheMissException (typically `null`
or `[]`, depending on the selector). Later, when the server responds, the cache will be updated and the component
will re-build its props, and this time the selector should successfully complete and return the data.

A convenience prop `isLoadingResources` is provided as well. It will be `true` when any selector in the most
recent call to your `mapSelectorsToProps` threw a `CacheMissException`, i.e. whenever any resource for your
component is still being loaded.

```javascript
import { WithResources } from 'components/shared/WithResources';
import { dogSelectors, dogActions } from 'resources';

function MyComponent({ isLoadingResources, dog, bark }) {
  if (isLoadingResources) { return <div class="loading">Please wait...</div>; }

  return <div>
    <p>The dog is named {dog.name}</p>
    <button onClick={bark({id: dog.id})}>Bark!</button>
  </div>;
}

function mapSelectorsToProps(select, ownProps) {
  return {
    dog: dogSelectors.getOne("82")
  };
}

function mapDispatchToProps(dispatch) {
  return {
    dog: dogActions.bark // "bark" must have been configured by `define` as a custom individual SASC action
  };
}

export default WithResources(MyComponent, mapSelectorsToProps, mapDispatchToProps);
```

### <a name="safeConnect(mapStateToProps, mapDispatchToProps, mergeProps, connectOptions)" href="../client/assets/javascripts/components/shared/WithResources.jsx#L253">`safeConnect(mapStateToProps, mapDispatchToProps, mergeProps, connectOptions)`</a>
This is an adapter on `WithResources`, providing an API identical to the one from [react-redux
connect](https://bit.ly/1SdzxK3).

This is a quick way to convert a non-SASC component to SASC; just replace `connect` with `safeConnect` and
everything should just work. However, unlike `WithResources`, you do not have fine control over how your component
renders while resources are being loaded.

If any selector in `mapStateToProps` raises a `CacheMissException`, then the entire component will render as `null`.
When the resource has finished loading and been inserted into the cache, `mapStateToProps` will be called
again to give it another try.

## Saga helpers

### <a name="runResourceProcess(action)" href="../client/assets/javascripts/sagas/helpers.js#L58">`runResourceProcess(action)`</a>
Given an action that would start a resourceLib process, dispatches the action and waits for the process to finish.

* `action`: A process-starting action, e.g. `resActions.create(...)`

This is an effect generator. Use this in your sagas with `yield diligentSelect(selector, ...args)`.  When yielded to
redux-saga, the effect returns the process success action's `payload`.  If the process fails, the failure action
will be thrown as an exception.

```javascript
import { runResourceProcess } from 'sagas/helpers';
import { dogActions } from 'resources';

function * createPuppySaga(_action) {
  const creationAction = userActions.create({type: 'dogs', name: 'Buddy'});
  const result = yield runResourceProcess(creationAction);
  const newPuppyId = result.id;
}
```

You can also use `runResourceProcess` with a fetch action, but only if the action has the `ignoreCache` option
enabled. This will force resources to be refetched, ignoring any cached values.

```javascript
import { runResourceProcess } from 'sagas/helpers';
import { dogSelectors } from 'resources';

function * announcePuppySaga(_action) {
  const fetchAction = userActions.fetchIndividual({ ignoreCache: true, id: "123" });
  const result = yield runResourceProcess(fetchAction);
  yield put({ type: "PUPPY_INFO", payload: `Our latest reports indicate a cute puppy named ${result.name}` });
}
```

If you don't want to enable `ignoreCache`, then you should use `diligentSelect` instead of `runResourceProcess`.

### <a name="diligentSelect(selector, ...args)" href="../client/assets/javascripts/sagas/helpers.js#L139">`diligentSelect(selector, ...args)`</a>
An effect similar to react-redux's `select`, but which fetches missing SASC resources as necessary before retuning.

* `selector`: The selector function to be called
* `...args`: Any other arguments to pass to the selector, after the state

This is an effect generator. Use this in your sagas with `yield diligentSelect(selector, ...args)`. When yielded to
redux-saga, the effect returns the result from the selector.

`diligentSelect` knows that it needs to fetch a missing resource if the selector throws a `CacheMissException`.
This could even happen several times in a row, e.g. if you are running a custom selector that uses several
different types of resources to calculate its result. However, after 10 `CacheMissException`s in a row,
`diligentSelect` will assume something has gone wrong and rethrow the final `CacheMissException`.

To refetch a resource even if it is already cached, use `runResourceProcess` on a fetch action with `ignoreCache`.
See the `runResourceProcess` documentation above for an example.

```javascript
import { diligentSelect } from 'sagas/helpers';
import { dogSelectors } from 'resources';

function * getCorgiSaga(_action) {
  const shortDog = yield diligentSelect(dogSelectors.getOneBy, 'breed', 'Welsh Corgi');
}
```

## Test helpers
You may find these functions useful when writing tests, particularly selector tests.

### <a name="buildResourceState(resources, defaultSequences = {})" href="../spec/javascripts/support/resources.js#L11">`buildResourceState(resources, defaultSequences = {})`</a>
Creates a Redux state with pre-cached resources, as though they had been fetched with a collection GET request.

* `resources`: A list of resource objects, each of which must have at least `id` and `type` fields

```javascript
import { buildResourceState } from 'support/resources';
import { dogSelectors } from 'resources';

const state = buildResourceState([
  { id: '1', type: 'dogs', name: 'Spot' },
  { id: '2', type: 'cats', name: 'Whiskers' }
]);

const theDog = dogSelectors.getOne(state, '1');
```

### <a name="trapSelect(selectorFn)" href="../spec/javascripts/support/resources.js#L53">`trapSelect(selectorFn)`</a>
Wraps a selector, catching and returning any `CacheMissException`s it throws

* `selectorFn`: A selector function

```javascript
import { trapSelect } from 'support/resources';
import { dogSelectors } from 'resources';

const emptyState = {};
const trappedGetOne = trapSelect(dogSelectors.getOne);
const ex = trappedGetOne(emptyState, "123"); // ex is a CacheMissException with a request for /api/dogs/123
```

### <a name="safeSelect(selectorFn)" href="../spec/javascripts/support/resources.js#L80">`safeSelect(selectorFn)`</a>
Wraps a selector, catching and returning the `default` value of any `CacheMissException`s it throws

* `selectorFn`: A selector function

```javascript
import { trapSelect } from 'support/resources';
import { dogSelectors } from 'resources';

const emptyState = {};
const trappedGetOne = trapSelect(dogSelectors.getOne);
const value = trappedGetOne(emptyState, "123"); // value is null, since that's the default for getOne misses
```

<!--/transcribe-->
