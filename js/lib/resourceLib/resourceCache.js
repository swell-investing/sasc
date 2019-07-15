import { find, get, omit, reduce } from 'lodash';

export function makeResourceCache(initialResources = []) {
  const emptyCache = {};

  return cacheAddResources(emptyCache, initialResources);
}

export function cacheAddResource(cache, resourceObject) {
  const resourceKey = resourceObject['id'];
  const entry = updateEntry(cache[resourceKey], resourceObject);
  return { ...cache, [resourceKey]: entry };
}

export function cacheAddResources(cache, resourceObjects) {
  return reduce(resourceObjects, cacheAddResource, cache);
}

export function cacheRemoveResource(cache, id) {
  return omit(cache, id);
}

export function cacheSetError(cache, id) {
  const entry = updateEntry(cache[id], null, true);
  return { ...cache, [id]: entry };
}

export function cacheSetErrors(cache, ids) {
  return reduce(ids, cacheSetError, cache);
}

export function isResourceKnownInCache(cache, id) {
  return !!get(cache, id, false);
}

export function isResourceErroredInCache(cache, id) {
  return get(cache, [id, 'error'], false);
}

export function cacheGetOneResourceById(cache, id) {
  return resourceIfPresent(get(cache, id));
}

export function cacheGetOneResourceBy(cache, attribute, value) {
  if (attribute === "id") {
    return cacheGetOneResourceById(cache, value);
  } else {
    return resourceIfPresent(find(cache, (entry) => {
      if (!entry.resource) { return false; }
      return entry.resource[attribute] == value;
    }));
  }
}

export function cacheLookup(cache, ids) {
  const performLookup = ([hitObjects, missIds, errorIds], nextKey) => {
    if (isResourceErroredInCache(cache, nextKey)) {
      return [hitObjects, missIds, [...errorIds, nextKey]];
    }

    const res = cacheGetOneResourceById(cache, nextKey);
    return res ?
          [[...hitObjects, res], missIds, errorIds] :
          [hitObjects, [...missIds, nextKey], errorIds];
  };

  return ids.reduce(performLookup, [[], [], []]);
}

function resourceIfPresent(maybeEntry) {
  return (maybeEntry && !maybeEntry.error && maybeEntry.resource) ? maybeEntry.resource : null;
}

function updateEntry(priorEntry, resourceObject, error = false) {
  const now = Date.now();

  if (!priorEntry) { priorEntry = { entryCreatedAt: now }; }

  return {
    ...priorEntry,
    error,
    resource: resourceObject,
    entryUpdatedAt: now,
  };
}
