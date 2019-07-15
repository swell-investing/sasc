import { compact, flatten, map, merge } from 'lodash';
import { actionGroup } from 'utils/actions';
import { shortActionTypeName, fullActionTypeName, camelCaseName } from 'lib/resourceLib/resourceNames';

//.## Resource actions
//. When you define a new resource, a set of actions are automatically generated. Many of them are used internally
//. by the resourceLib sagas, but some are intended to be dispatched from your own components and sagas.
//.
//. #### Unpacked resources
//.
//. All resource objects included in these actions are *unpacked*, which means that the contents of the `attributes`
//. object are lifted up to the root level. For example, this means that when creating a resource, you will send
//. `{ type: 'people', name: 'Person McUser' }`, not `{ type: 'people', attributes: { name: 'Person McUser' } }`.
//. Note that relationships are not unpacked; they are left nested in the `relationships` object.
//.
//. #### Pids
//.
//. CUD actions and custom SASC actions can be created with a `pid` in the `meta` object. The `pid` is a string used to
//. uniquely track the process of seeing the action through to its final result. For any given resource type and action
//. type, no more than one process can run at the same time with the same `pid`. When not explicitly supplied, a
//. constant default `pid` is used.
//.
//. You don't have to worry about `pid`s unless you want to start multiple similar actions at the same time, which is
//. unusual.

export default function makeResourceActionGroup(resourceType, options) {
  const { fetchCollection, fetchIndividual, create, update, destroy, customSascActions } = options;

  // See actionGroup definition in utils/actions.js for details.
  function actionSpec(name, creatorFnSpec) {
    const creatorSpec = { [camelCaseName(name)]: creatorFnSpec };

    return { [name]: [fullActionTypeName(resourceType, name), creatorSpec] };
  }

  function makeSascActionSpecs(config, name) {
    name = shortActionTypeName(name);

    return [
      actionSpec(name, ["payload", "meta"]),
      actionSpec(`${name}_INITIATED`, ["meta"]),
      actionSpec(`${name}_SUCCEEDED`, ["payload", "meta"]),
      actionSpec(`${name}_FAILED`, ["payload", "meta", "error"]),
    ];
  }

  const actionSpecs = flatten(compact([
    fetchCollection && [
      //% fetchCollection({ filters, ignoreCache })
      //. Dispatch this to request resources from the index route on the server API.
      //.
      //. **NOTE**: You probably want to use [selectors](#resourceselectors) instead of dispatching this action
      //. yourself.  That way, you won't unnecessarily re-request the resource if it is already cached. From components,
      //. use `WithResources` or `safeConnect`. From sagas, use `diligentSelect`.
      //.
      //. * `filters`: An object describing filters in the request, e.g. `{ id: [1,5,7] }`. (default: `{}`)
      //. * `ignoreCache`: If true, the request will go through even if the result is already in the cache. (default:
      //. `false`)
      //.
      //.  ```javascript
      //.  import { dogActions } from 'resources';
      //.  import { runResourceProcess } from 'sagas/helpers';
      //.
      //.  function * forceReloadDogsSaga() {
      //.    yield runResourceProcess(dogActions.fetchCollection({ ignoreCache: true }));
      //.  }
      //.  ```
      actionSpec("FETCH_COLLECTION", ["payload"]),
      actionSpec("FETCH_COLLECTION_INITIATED", ["meta"]),
      actionSpec("FETCH_COLLECTION_SUCCEEDED", ["payload", "meta"]),
      actionSpec("FETCH_COLLECTION_FAILED", ["payload", "meta", "error"])],

    fetchIndividual && [
      //% fetchIndividual({ id, ignoreCache })
      //. Dispatch this to request a single resource from the show route on the server API.
      //.
      //. **NOTE**: You probably want to use [selectors](#resourceselectors) instead of dispatching this action
      //. yourself.  That way, you won't unnecessarily re-request the resource if it is already cached. From components,
      //. use `WithResources` or `safeConnect`. From sagas, use `diligentSelect`.
      //.
      //. * `id`: The id of the resource to fetch.
      //. * `ignoreCache`: If true, the request will go through even if the result is already in the cache. (default:
      //. `false`)
      //.
      //.  ```javascript
      //.  import { dogActions } from 'resources';
      //.  import { runResourceProcess } from 'sagas/helpers';
      //.
      //.  function * forceReloadFirstDogSaga() {
      //.    yield runResourceProcess(dogActions.fetchIndividual({ id: "1", ignoreCache: true }));
      //.  }
      //.  ```
      actionSpec("FETCH_INDIVIDUAL", ["payload"]),
      actionSpec("FETCH_INDIVIDUAL_INITIATED", ["meta"]),
      actionSpec("FETCH_INDIVIDUAL_SUCCEEDED", ["payload", "meta"]),
      actionSpec("FETCH_INDIVIDUAL_FAILED", ["payload", "meta", "error"])],

    [
      actionSpec("INCLUDED_RESOURCES_RECEIVED", ["payload"]),
      actionSpec("INVALIDATE_CACHE", ["payload"]),
      //% resourceFetched(payload)
      //. This action is dispatched for each resource received from the server.
      //.
      //. * `payload`: The resource that was fetched.
      //.
      //. You may find it useful to listen for these actions to do follow-up behaviors, such as re-requesting a
      //. resource which you expect to change to a new state soon.
      //.
      //. ```javascript
      //. import { delay } from 'redux-saga';
      //. import { call, put, takeEvery } from 'redux-saga/effects';
      //. import { dogActions } from 'resources';
      //.
      //. export default function * () {
      //.   yield takeEvery(dogActions.resourceFetched.pattern, pollDog);
      //. }
      //.
      //. // Keep re-fetching the dog until they stop barking
      //. export function * pollDog({ payload }) {
      //.   if (payload.status == "barking") {
      //.     yield call(delay, 5000);
      //.     // When this fetch completes, it will trigger another resourceFetched action
      //.     yield put(accountActions.fetchIndividual({ ignoreCache: true, id: payload.id }));
      //.   }
      //. }
      //. ```
      actionSpec("RESOURCE_FETCHED", ["payload"])],

    create && [
      //% create(payload, meta)
      //. Dispatch this to create a resource via a POST request to the server.
      //.
      //. * `payload`: The unpacked resource to create. This must have a `type`, but must *NOT* have an `id`.
      //. * `meta`: Optional. An object with a `pid` to use for this creation process. See above regarding `pid`
      //. strings.
      //.
      //. ```javascript
      //. function DogCreationButton(create) {
      //.   const onClick = () => createDog({ type: 'dogs', name: 'Buddy', age: 0 });
      //.   return <a onClick={onClick}>Create a puppy!</a>;
      //. }
      //.
      //. function mapDispatchToProps(dispatch) {
      //.   const actionCreators = { createDog: dogActions.create };
      //.   return bindActionCreators(actionCreators, dispatch);
      //. }
      //.
      //. export default WithResources(DogCreationButton, null, mapDispatchToProps);
      //. ```
      actionSpec("CREATE", ["payload", "meta"]),
      actionSpec("CREATE_INITIATED", ["meta"]),
      actionSpec("CREATE_SUCCEEDED", ["payload", "meta"]),
      actionSpec("CREATE_FAILED", ["payload", "meta", "error"])],

    update && [
      //% update(payload, meta)
      //. Dispatch this to update a resource via a PATCH request to the server.
      //.
      //. * `payload`: Fields to change on the resource. This *MUST* have `type` and `id`. Fields you don't specify will
      //. keep their current value.
      //. * `meta`: Optional. An object with a `pid` to use for this update process. See above regarding `pid`
      //. strings.
      //.
      //. ```javascript
      //. function DogRenameButton(create) {
      //.   const onClick = () => updateDog({ type: 'dogs', id: '33', name: 'Maximus Prime' });
      //.   return <a onClick={onClick}>Rename the dog!</a>;
      //. }
      //.
      //. function mapDispatchToProps(dispatch) {
      //.   const actionCreators = { updateDog: dogActions.update };
      //.   return bindActionCreators(actionCreators, dispatch);
      //. }
      //.
      //. export default WithResources(DogRenameButton, null, mapDispatchToProps);
      //. ```
      actionSpec("UPDATE", ["payload", "meta"]),
      actionSpec("UPDATE_INITIATED", ["meta"]),
      actionSpec("UPDATE_SUCCEEDED", ["payload", "meta"]),
      actionSpec("UPDATE_FAILED", ["payload", "meta", "error"])],

    destroy && [
      //% destroy({ id }, meta)
      //. Dispatch this to destroy a resource via a DELETE request to the server.
      //.
      //. * `id`: The `id` of the resource to destroy.
      //. * `meta`: Optional. An object with a `pid` to use for this destroy process. See above regarding `pid`
      //. strings.
      //.
      //. ```javascript
      //. import { diligentSelect, runResourceProcess } from 'sagas/helpers';
      //. import { bananaActions, bananaSelectors } from 'resources';
      //.
      //. function * eatBananaIfRipeSaga(action) {
      //.   const bananas = yield diligentSelect(bananaSelectors.getMany);
      //.   const firstBanana = bananas[0];
      //.   if (firstBanana.ripeness > 3) {
      //.     console.log("This banana looks pretty good");
      //.     const deletionAction = bananaActions.destroy({ id: firstBanana.id });
      //.     yield runResourceProcess(deletionAction);
      //.     console.log("Yum yum! Banana is gone now.");
      //.   }
      //. }
      //. ```
      actionSpec("DESTROY", ["payload", "meta"]),
      actionSpec("DESTROY_INITIATED", ["meta"]),
      actionSpec("DESTROY_SUCCEEDED", ["payload", "meta"]),
      actionSpec("DESTROY_FAILED", ["payload", "meta", "error"])],

    //% yourCustomAction({ id, arguments }, meta)
    //. Dispatch this to POST a custom SASC action.
    //.
    //. The function name is a camel-cased version of the custom action name you provided to `define`. For example, a
    //. custom SASC action named `run-iditarod` would have an action creation function called `runIditarod`.
    //.
    //. * `id`: For `kind: 'individual'` actions, the id of the target resource must be given.
    //. * `arguments`: Some SASC custom actions require arguments. You can supply arguments by providing an object
    //. here.
    //. * `meta`: Optional. An object with a `pid` to use for this process. See above regarding `pid` strings.
    //.
    //. ```javascript
    //. import { runResourceProcess } from 'sagas/helpers';
    //. import { dogActions } from 'resources';
    //.
    //. function * adventureSaga(action) {
    //.   const iditarodAction = dogActions.runIditarod({ arguments: { route: "northern" }});
    //.   const result = yield runResourceProcess(iditarodAction);
    //.   console.log("It took " + result.daysElapsed + " days, but it was worth it!");
    //. }
    //. ```
    ...map(customSascActions, makeSascActionSpecs),
  ])).reduce(merge);

  return actionGroup(actionSpecs);
}
