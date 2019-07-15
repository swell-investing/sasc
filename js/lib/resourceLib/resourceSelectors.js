import { filter, get, isArray, isEmpty, isFunction, isNull, map, merge, pickBy, size, some, toString } from 'lodash';
import { camelCaseName } from 'lib/resourceLib/resourceNames';
import { isQueryErroredInIndex, isQueryKnownInIndex, indexGetQueryResults } from 'lib/resourceLib/resourceIndex';
import {
  isResourceErroredInCache,
  isResourceKnownInCache,
  cacheLookup,
  cacheGetOneResourceBy,
} from 'lib/resourceLib/resourceCache';
import { STATUS_UNSTARTED, STATUS_RUNNING, STATUS_COMPLETED, DEFAULT_PID } from 'lib/resourceLib';

const SELECTOR_MANY_DEFAULT = [];
const SELECTOR_ONE_DEFAULT = null;

function mkArray(x) {
  return isArray(x) ? x : [x];
}

//.## Resource selectors
//. When you define a new resource, a set of selectors are automatically generated. These selectors will attempt to find
//. requested resources in the local cache, and will throw a CacheMissException if they're not found there. To avoid
//. having to deal with these exceptions yourself, you should use `WithResources` instead of `connect` in your
//. components, and `diligentSelect` instead of `select` in your sagas.
//.
//. Keep in mind that you may need to use `WithResources` and `diligentSelect` even if you're not directly calling
//. a resource selector, because the selector you call might be calling resource selectors on its own. There's no harm
//. in using `WithResources` or `diligentSelect` even if you don't need to.

//% CacheMissException
//. An exception class representing missing resource(s) which need to be fetched from the server.
//.
//. You will probably not need to interact this exception class yourself. The best approach is usually to let
//. `WithResources` and `diligentSelect` worry about catching and correctly responding to these.
//.
//. CacheMissException instances have these properties:
//.
//. * `action`: An action that, when dispatched, will request the missing resources from the server
//. * `default`: A value that will serve as a placeholder for the selector result until the resource is loaded
//. * `description`: A textual explanation of the exception
export class CacheMissException {
  constructor(data) {
    this.action = data.action;
    this.default = data.default;
    this.description = data.description;
  }
}

export default function makeResourceSelectors(resourceType, actionGroup, options) {
  // TODO Use options to determine what kind of CacheMissExceptions we can throw
  const { create, update, destroy, customSascActions } = options;

  const resourceStateKey = camelCaseName(resourceType);

  function resourceState(state) {
    // Not using the third argument of `get` because we want to return {} even if the stored state really is null
    return get(state, ['resources', resourceStateKey]) || {};
  }

  //% getMany(state, filters = {})
  //. Selector for a collection of resources.
  //.
  //. * `state`: The Redux state
  //. * `filters`: SASC filters on the request, e.g. `{ id: ["2", "8", "47"] }`
  //.
  //. On missing resource, throws a `CacheMissException` with `default` set to an empty array `[]`;
  //.
  //. ```javascript
  //. import { dogSelectors } from 'resources';
  //.
  //. function mapSelectorsToProps(select) {
  //.   return {
  //.     allDogs: select(dogSelectors.getMany),
  //.     primeDogs: select(dogSelectors.getMany, { id: ["2", "3", "5", "7", "11"] }),
  //.   };
  //. }
  //. ```
  function getMany(state, filters = {}) {
    const resState = resourceState(state);

    // TODO Support other SASC parameters (e.g. order)
    let params = isEmpty(filters) ? {} : { filters };

    // As a special case, if we are only filtering on ids, then we only need to fetch any resources we are missing.
    const idsOnly = filters.id && size(filters) == 1;

    let ids;
    if (idsOnly) {
      ids = map(mkArray(filters.id), toString);
    } else {
      ids = indexGetQueryResults(resState.index, params);
    }

    if (ids) {
      const [foundResources, missingIds, errorIds] = cacheLookup(resState.cache, ids);

      // If we already got errors attempting to load any of these resources, don't try again.
      // TODO Maybe count number of errors in resource cache and retry up to N times?
      if (!isEmpty(errorIds)) return SELECTOR_MANY_DEFAULT;

      if (isEmpty(missingIds)) return foundResources;

      if (idsOnly) {
        params = { filters: { id: missingIds } };
      }
    }

    if (isQueryErroredInIndex(resState.index, params)) {
      // If we already tried this request and got an error, don't try again
      // TODO Maybe count number of errors and retry up to N times?
      return SELECTOR_MANY_DEFAULT;
    }

    throw new CacheMissException({
      description: `getMany selector (${resourceStateKey}) : value is not cached and must be fetched.`,
      action: actionGroup.fetchCollection(params),
      default: SELECTOR_MANY_DEFAULT,
    });
  }

  //% getOne(state, id)
  //. Selector for getting a single resource by id.
  //.
  //. * `state`: The Redux state
  //. * `id`: The id of the resource to fetch
  //.
  //. On missing resource, throws a `CacheMissException` with `default` set to `null`;
  //.
  //. ```javascript
  //. import { dogSelectors } from 'resources';
  //.
  //. function mapSelectorsToProps(select) {
  //.   return {
  //.     dogOne: select(dogSelectors.getOne, "1");
  //.   };
  //. }
  //. ```
  function getOne(state, id) {
    return getOneBy(state, "id", id);
  }

  //% getOneBy(state, attribute, value)
  //. Selector for getting a single resource by a particular attribute value.
  //.
  //. * `state`: The Redux state
  //. * `attribute`: The attribute to search on, e.g. `'name'`
  //. * `value`: The value to look for in the given attribute, e.g. `'Ada Lovelace'`
  //.
  //. Note that if more than one resource has the correct attribute value, there's no particular guarantee about
  //. which one you'll get. In general, this selector should be used for unique attributes.
  //.
  //. ```javascript
  //. import { dogSelectors } from 'resources';
  //.
  //. function mapSelectorsToProps(select) {
  //.   return {
  //.     bigDog: select(dogSelectors.getOneBy, 'size', 'large');
  //.   };
  //. }
  //. ```
  function getOneBy(state, attribute, value) {
    const cache = resourceState(state).cache || {};

    const foundResource = cacheGetOneResourceBy(cache, attribute, value);
    if (foundResource) return foundResource;

    if (attribute == "id") {
      if (isResourceErroredInCache(cache, value)) {
        // TODO Maybe count number of errors in resource cache and retry up to N times?
        return SELECTOR_ONE_DEFAULT;
      }

      throw new CacheMissException({
        description: `getOneBy selector (${resourceType}, ${attribute}:${value}) : value is not cached and must be fetched.`,
        action: actionGroup.fetchIndividual({ id: value }),
        default: SELECTOR_ONE_DEFAULT,
      });
    }

    if (isQueryKnownInIndex(resourceState(state), {})) {
      return SELECTOR_ONE_DEFAULT;
    } else {
      // TODO: Should it (sometimes?) attempt to filter by non-id attribute? Do we need to configure
      // each resource with the list of filterable attributes?
      throw new CacheMissException({
        description: `getOneBy selector (${resourceType}, ${attribute}:${value}) : value is not cached and must be fetched.`,
        action: actionGroup.fetchCollection({}),
        default: SELECTOR_ONE_DEFAULT,
      });
    }
  }

  //% getManyFromRelationship(state, origin, relationship)
  //. Selector for getting a collection of resources related to a given resource.
  //.
  //. This will look up the target resources through the `relationships` property on the `origin` resource.
  //.
  //. * `state`: The Redux state
  //. * `origin`: A resource object, e.g. the result of `getOne`.
  //. * `relationship`: The name of the relationship on `origin` to traverse.
  //.
  //. ```javascript
  //. import { dogSelectors, humanSelectors } from 'resources';
  //.
  //. function mapSelectorsToProps(select) {
  //.   const dog = select(dogSelectors.getOneBy, "name", "Shadow");
  //.   return {
  //.     owners: select(humanSelectors.getManyFromRelationship, dog, 'owners');
  //.   };
  //. }
  //. ```
  function getManyFromRelationship(state, origin, relationship) {
    // TODO Fail loudly if origin does not exist
    if (!origin) { return SELECTOR_MANY_DEFAULT; }

    const relationshipData = origin.relationships[relationship].data;
    const elementsToFetch = isArray(relationshipData) ? relationshipData : [relationshipData];
    const ids = map(filter(elementsToFetch, { type: resourceType }), "id");
    return getMany(state, { id: ids });
  }

  //% getOneFromRelationship(state, origin, relationship)
  //. Selector for getting a single resource related to a given resource.
  //.
  //. This will look up the target resource through the `relationships` property on the `origin` resource.
  //.
  //. * `state`: The Redux state
  //. * `origin`: A resource object, e.g. the result of `getOne`.
  //. * `relationship`: The name of the relationship on `origin` to traverse.
  //.
  //. ```javascript
  //. import { dogSelectors, tagSelectors } from 'resources';
  //.
  //. function mapSelectorsToProps(select) {
  //.   const dog = select(dogSelectors.getOneBy, "name", "Shadow");
  //.   return {
  //.     nametag: select(tagSelectors.getOneFromRelationship, dog, 'collarTag');
  //.   };
  //. }
  //. ```
  function getOneFromRelationship(state, origin, relationship) {
    // TODO Fail loudly if relationship does not exist
    const relationshipData = get(origin, "relationships." + relationship + ".data");
    if (relationshipData && relationshipData.type == resourceType) {
      return getOneBy(state, "id", relationshipData.id);
    }
    return SELECTOR_ONE_DEFAULT;
  }

  //% getSomeActionStatus(state, pid = default)
  //. Returns the current status of a process.
  //.
  //. * For checking a create process, call `getCreationStatus`
  //. * For checking an update process, call `getUpdateStatus`
  //. * For checking a destroy process, call `getDestroyStatus`
  //. * For checking a custom action, call `getActionNameStatus`, e.g. for `upload-file` call `getUploadFileStatus`
  //.
  //. The possible statuses it can return can be imported from `resourceLib`, and they are:
  //. `STATUS_UNSTARTED`
  //. `STATUS_RUNNING`
  //. `STATUS_ERRORED`
  //. `STATUS_COMPLETED`
  //.
  //. The `pid` argument is optional. See the [Pids section](#pids) for details about when and why you might want to use
  //. it.
  //.
  //. ```javascript
  //. import { dogSelectors } from 'resources';
  //. import { STATUS_UNSTARTED, STATUS_RUNNING, STATUS_ERRORED, STATUS_COMPLETED } from 'lib/resourceLib';
  //.
  //. function mapSelectorsToProps(select) {
  //.   switch(select(dogSelectors.getRunIditarodStatus)) {
  //.     case STATUS_UNSTARTED: return { msg: "The race is about to start!" };
  //.     case STATUS_RUNNING: return { msg: "They're flying across the ice!" };
  //.     case STATUS_ERRORED: return { msg: "Oh no, they've gotten tangled up!" };
  //.     case STATUS_COMPLETED: return { msg: "And now it's time to announce the winner!" };
  //.   }
  //. }
  //. ```
  function getProcessStatus(state, actionName, pid = DEFAULT_PID) {
    return get(resourceState(state), ['processes', actionName, pid, 'status'], STATUS_UNSTARTED);
  }

  //% isSomeActionRunning(state, pid = default)
  //. Returns a boolean indicating whether a process is currently running or not.
  //.
  //. * For checking a create process, call `isCreating`
  //. * For checking an update process, call `isUpdating`
  //. * For checking a destroy process, call `isDestroying`
  //. * For checking a custom action, call `isActionNameRunning`, e.g. for `upload-file` call `isUploadFileRunning`
  //.
  //.
  //. Internally, all this does is check if `getProcessStatus` returns `resourceLib.STATUS_RUNNING`.
  //.
  //. The `pid` argument is optional. See the [Pids section](#pids) for details about when and why you might want to use
  //. it.
  //.
  //. ```javascript
  //. import { dogSelectors } from 'resources';
  //.
  //. function mapSelectorsToProps(select) {
  //.   return {
  //.     showSpinner: select(dogSelectors.isUpdateRunning)
  //.   };
  //. }
  //. ```
  function isProcessRunning(state, actionName, pid = DEFAULT_PID)  {
    return STATUS_RUNNING == getProcessStatus(state, actionName, pid);
  }

  //% isSomeActionDone(state, pid = default)
  //. Returns a boolean indicating whether a process has completed successfully or not.
  //.
  //. * For checking a create process, call `isDoneCreating`
  //. * For checking an update process, call `isDoneUpdating`
  //. * For checking a destroy process, call `isDoneDestroying`
  //. * For checking a custom action, call `isActionNameDone`, e.g. for `upload-file` call `isUploadFileDone`
  //.
  //. Internally, all this does is check if `getProcessStatus` returns `resourceLib.STATUS_COMPLETED`.
  //.
  //. The `pid` argument is optional. See the [Pids section](#pids) for details about when and why you might want to use
  //. it.
  function isProcessDone(state, actionName, pid = DEFAULT_PID) {
    return STATUS_COMPLETED == getProcessStatus(state, actionName, pid);
  }

  //% getSomeActionResult(state, pid = default)
  //. Returns the final result of a completed process.
  //.
  //. * For a creation result, call `getCreationResult`
  //. * For the result of a custom action, call `getActionNameResult`, e.g. for `upload-file` call `getUploadFileResult`
  //.
  //. The `pid` argument is optional. See the [Pids section](#pids) for details about when and why you might want to use
  //. it.
  //.
  //. ```javascript
  //. import { dogSelectors } from 'resources';
  //.
  //. function mapSelectorsToProps(select) {
  //.   const busy = select(dogSelectors.isCreating);
  //.   const newDog = busy ? null : select(dogSelectors.creationResult);
  //.   return {
  //.     status: newDog ? `Created dog! ID is ${id}` : (busy ? "Creating dog..." : "Couldn't create dog!")
  //.   };
  //. }
  //. ```
  function getProcessResult(state, actionName, pid = DEFAULT_PID) {
    return get(resourceState(state), ['processes', actionName, pid, 'result'], null);
  }

  function getCreationStatus(state, pid = DEFAULT_PID) { return getProcessStatus(state, 'create', pid); }

  function isCreating(state, pid = DEFAULT_PID) { return isProcessRunning(state, 'create', pid); }

  function isDoneCreating(state, pid = DEFAULT_PID) { return isProcessDone(state, 'create', pid); }

  function getCreationResult(state, pid = DEFAULT_PID) { return getProcessResult(state, 'create', pid); }

  function getUpdateStatus(state, pid = DEFAULT_PID) { return getProcessStatus(state, 'update', pid); }

  function isUpdating(state, pid = DEFAULT_PID) { return isProcessRunning(state, 'update', pid); }

  function isDoneUpdating(state, pid = DEFAULT_PID) { return isProcessDone(state, 'update', pid); }

  function getDestroyStatus(state, pid = DEFAULT_PID) { return getProcessStatus(state, 'destroy', pid); }

  function isDestroying(state, pid = DEFAULT_PID) { return isProcessRunning(state, 'destroy', pid); }

  function isDoneDestroying(state, pid = DEFAULT_PID) { return isProcessDone(state, 'destroy', pid); }

  function makeCustomSascActionSelectors() {
    const selectorSets = map(customSascActions, (_config, name) => {
      const actionName = camelCaseName(name);

      return {
        [camelCaseName(`get-${name}-result`)]: (state, pid = DEFAULT_PID) => getProcessResult(state, actionName, pid),
        [camelCaseName(`get-${name}-status`)]: (state, pid = DEFAULT_PID) => getProcessStatus(state, actionName, pid),
        [camelCaseName(`is-${name}-running`)]: (state, pid = DEFAULT_PID) => isProcessRunning(state, actionName, pid),
        [camelCaseName(`is-${name}-done`)]: (state, pid = DEFAULT_PID) => isProcessDone(state, actionName, pid),
      };
    });

    return selectorSets.reduce(merge, {});
  }

  //% isResourceErrored(state, id)
  //. Returns a boolean indicating whether the most recent attempt to fetch the given resource failed.
  //.
  //. * `state`: The Redux state
  //. * `id`: The id of the resource to check
  //.
  //. This selector is mostly for internal use; normal application logic is usually better off not using it.
  function isResourceErrored(state, id) {
    const { cache } = resourceState(state);
    return isResourceErroredInCache(cache, toString(id));
  }

  //% isResourceKnown(state, id)
  //. Returns a boolean indicating whether we have up-to-date information about the resource in the cache.
  //.
  //. Note that a resource is `known` if it is `errored`, because we have the error result cached.
  //.
  //. * `state`: The Redux state
  //. * `id`: The id of the resource to check
  //.
  //. This selector is mostly for internal use; normal application logic is usually better off not using it.
  function isResourceKnown(state, id) {
    const { cache } = resourceState(state);
    return isResourceKnownInCache(cache, toString(id));
  }

  //% isCollectionErrored(state, filters = {})
  //. Returns a boolean indicating whether the most recent attempt to fetch a collection of resources failed.
  //.
  //. * `state`: The Redux state
  //. * `filters`: The filters for the query to check.
  //.
  //. This selector is mostly for internal use; normal application logic is usually better off not using it.
  function isCollectionErrored(state, filters = {}) {
    const { index, cache } = resourceState(state);

    // TODO Support other SASC parameters (e.g. order)
    const params = { filters };
    if (isQueryErroredInIndex(index, params)) { return true; }

    const ids = indexGetQueryResults(index, params);
    if (isNull(ids)) { return false; }

    if (!cache) { return false; }
    return some(ids, (id) => isResourceErroredInCache(cache, id));
  }

  //% isCollectionKnown(state, filters = {})
  //. Returns a boolean indicating whether we have up-to-date information about the results of a collection query.
  //.
  //. Note that a resource is `known` if it is `errored`, because we have the error result cached.
  //.
  //. * `state`: The Redux state
  //. * `filters`: The filters for the query to check.
  //.
  //. This selector is mostly for internal use; normal application logic is usually better off not using it.
  function isCollectionKnown(state, filters = {}) {
    const { cache, index } = resourceState(state);

    // TODO Support other SASC parameters (e.g. order)
    const params = { filters };

    if (!isQueryKnownInIndex(index, params)) { return false; }
    if (isQueryErroredInIndex(index, params)) { return true; }

    const ids = indexGetQueryResults(index, params);
    if (isEmpty(ids)) { return true; } // Even if we have no cache, we can have a complete empty result

    if (!cache) { return false; }
    const [_, missingIds, errorIds] = cacheLookup(cache, ids);
    if (!isEmpty(errorIds)) { return true; }
    return isEmpty(missingIds);
  }

  //% isFetching(state)
  //. Returns a boolean indicating whether any resources are currently being fetched.
  //.
  //. * `state`: The Redux state
  function isFetching(state) {
    const found = resourceState(state);
    return found.fetching || false;
  }

  return pickBy({
    isResourceKnown,
    isResourceErrored,
    isCollectionKnown,
    isCollectionErrored,
    isFetching,

    getMany,
    getManyFromRelationship,

    getOne,
    getOneBy,
    getOneFromRelationship,

    ...(create && {
      getCreationStatus,
      isCreating,
      isDoneCreating,
      getCreationResult,
    }),

    ...(update && {
      getUpdateStatus,
      isUpdating,
      isDoneUpdating,
    }),

    ...(destroy && {
      getDestroyStatus,
      isDestroying,
      isDoneDestroying,
    }),

    ...makeCustomSascActionSelectors(),
  });
}

//.## Selector helpers

export function isValidCacheMissException(ex) {
  return (ex instanceof CacheMissException) && ex.action;
}

//% cacheMissOverrideDefault(def, fn)
//. Captures `CacheMissException`s and changes their `default` value before re-throwing.
//.
//. * `def`: The new `default` value to set
//. * `fn`: The function to run
//.
//. When called, `cacheMissOverrideDefault` will immediately call `fn` with no parameters, and return `fn`'s return
//. value if it doesn't throw.
//.
//. This is likely to useful when you are writing a selector that calls resource selectors to gather
//. data for a calculation. You can provide a `def` with a type that sensibly matches the type your selector's caller
//. expects to get, rather than whatever type the internally called selectors return.
//.
//. ```javascript
//. import { maxBy } from 'lodash';
//. import { cacheMissOverrideDefault } from `lib/resourceLib`;
//. import { dogSelectors } from 'resources';
//.
//. export function selectBiggestDog(state) {
//.   const allDogs = cacheMissOverrideDefault(null, () => dogSelectors.getMany(state));
//.   return maxBy(allDogs, 'size');
//. }
//. ```
export function cacheMissOverrideDefault(def, fn) {
  try {
    return fn();
  } catch (ex) {
    if (!isValidCacheMissException(ex)) { throw ex; }
    if (isFunction(def)) { def = def(); }
    throw new CacheMissException({
      action: ex.action,
      description: ex.description,
      default: def,
    });
  }
}

//% selectorWithDefault(def, selector)
//. A convenience wrapper for the most common use case of `cacheMissOverrideDefault`.
//.
//. * `def`: The new `default` value to set
//. * `selector`: The function to wrap
//.
//. When called, `selectorWith` will return a new function that forwards its arguments to the given `selector`, and
//. changes the `default` of any `CacheMisException` to `def` before re-throwing it. Using `selectorWithDefault` to
//. wrap your selector function is often simpler than using `cacheMissOverrideDefault` around every inner selector
//. call.
//.
//. The example below is equivalent to the example given above for `cacheMissOverrideDefault`.
//.
//. ```javascript
//. import { maxBy } from 'lodash';
//. import { selectorWithDefault } from `lib/resourceLib`;
//. import { dogSelectors } from 'resources';
//.
//. export const selectBiggestDog = selectorWithDefault(null, (state) => {
//.   const allDogs = dogSelectors.getMany(state);
//.   return maxBy(allDogs, 'size');
//. });
//. ```
export function selectorWithDefault(def, selector) {
  return (...args) => {
    return cacheMissOverrideDefault(def, () => selector(...args));
  };
}
