import { groupBy, map, mapKeys, mapValues } from 'lodash';

import { makeResourceCache } from 'lib/resourceLib/resourceCache';
import { makeResourceIndex, indexAddQueryResults } from 'lib/resourceLib/resourceIndex';
import { camelCaseName } from 'lib/resourceLib/resourceNames';
import { CacheMissException } from 'lib/resourceLib/resourceSelectors';

//.## Test helpers
//. You may find these functions useful when writing tests, particularly selector tests.

//% buildResourceState(resources, defaultSequences = {})
//. Creates a Redux state with pre-cached resources, as though they had been fetched with a collection GET request.
//.
//. * `resources`: A list of resource objects, each of which must have at least `id` and `type` fields
//.
//. ```javascript
//. import { buildResourceState } from 'support/resources';
//. import { dogSelectors } from 'resources';
//.
//. const state = buildResourceState([
//.   { id: '1', type: 'dogs', name: 'Spot' },
//.   { id: '2', type: 'cats', name: 'Whiskers' }
//. ]);
//.
//. const theDog = dogSelectors.getOne(state, '1');
//. ```
export function buildResourceState(resources, defaultSequences = {}) {
  const resourcesByStateKey = groupBy(resources, (res) => {
    if (!res.type) {
      throw "Missing type key on resource in buildResourceState";
    } else if (!res.id) {
      throw "Missing id key on resource in buildResourceState";
    } else {
      return camelCaseName(res.type);
    }
  });

  const sequences = {
    ...mapValues(resourcesByStateKey, (rs) => map(rs, 'id')),
    ...mapKeys(defaultSequences, (_v, k) => camelCaseName(k)),
  };

  const resourcesState = mapValues(sequences, (ids, resourceType) => {
    const rs = resourcesByStateKey[resourceType] || null;
    const index = indexAddQueryResults(makeResourceIndex(), {}, ids);
    const cache = makeResourceCache(rs);
    return { fetching: false, index, cache };
  });

  return { resources: resourcesState };
}

//% trapSelect(selectorFn)
//. Wraps a selector, catching and returning any `CacheMissException`s it throws
//.
//. * `selectorFn`: A selector function
//.
//. ```javascript
//. import { trapSelect } from 'support/resources';
//. import { dogSelectors } from 'resources';
//.
//. const emptyState = {};
//. const trappedGetOne = trapSelect(dogSelectors.getOne);
//. const ex = trappedGetOne(emptyState, "123"); // ex is a CacheMissException with a request for /api/dogs/123
//. ```
export function trapSelect(selectorFn) {
  return (state, ...args) => {
    try {
      return selectorFn(state, ...args);
    } catch (ex) {
      if (ex instanceof CacheMissException) {
        return ex;
      } else {
        throw ex;
      }
    }
  };
}

//% safeSelect(selectorFn)
//. Wraps a selector, catching and returning the `default` value of any `CacheMissException`s it throws
//.
//. * `selectorFn`: A selector function
//.
//. ```javascript
//. import { trapSelect } from 'support/resources';
//. import { dogSelectors } from 'resources';
//.
//. const emptyState = {};
//. const trappedGetOne = trapSelect(dogSelectors.getOne);
//. const value = trappedGetOne(emptyState, "123"); // value is null, since that's the default for getOne misses
//. ```
export function safeSelect(selectorFn) {
  const trapper = trapSelect(selectorFn);
  return (state, ...args) => {
    const value = trapper(state, ...args);
    return (value instanceof CacheMissException) ? value.default : value;
  };
}
