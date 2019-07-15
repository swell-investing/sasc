import { isArray, isEmpty, isObject, get, map, mapValues, omitBy } from 'lodash';
import canonicalJsonStringify from 'canonical-json';

export function makeResourceIndex(initialResources = null) {
  const emptyIndex = {};

  if (initialResources) {
    return indexAddQueryResults(emptyIndex, {}, map(initialResources, 'id'));
  } else {
    return emptyIndex;
  }
}

export function indexAddQueryResults(index, queryParams, ids) {
  const key = queryKey(queryParams);
  const entry = updateEntry(get(index, key), ids);
  return { ...(index || {}), [key]: entry };
}

export function indexSetError(index, queryParams) {
  const key = queryKey(queryParams);
  const entry = updateEntry(get(index, key), null, true);
  return { ...(index || {}), [key]: entry };
}

export function isQueryKnownInIndex(index, queryParams) {
  return !!get(index, queryKey(queryParams), false);
}

export function isQueryErroredInIndex(index, queryParams) {
  return get(index, [queryKey(queryParams), 'error'], false);
}

export function indexGetQueryResults(index, queryParams) {
  const entry = get(index, queryKey(queryParams));
  return idsIfPresent(entry);
}

function queryKey(queryParams) {
  return canonicalJsonStringify(removeEmptyValues(queryParams));
}

// Delete empty object values, so e.g. `{ filters: {} }` is simplified to `{}`
function removeEmptyValues(arg) {
  if (isObject(arg)) {
    const filteredObj = omitBy(arg, (value) => isObject(value) && isEmpty(value));
    return mapValues(filteredObj, removeEmptyValues);
  } else if (isArray(arg)) {
    // We don't delete empty array values, only object values
    return arg.map(removeEmptyValues);
  } else {
    return arg;
  }
}

function updateEntry(priorEntry, ids, error = false) {
  const now = Date.now();

  if (!priorEntry) { priorEntry = { entryCreatedAt: now }; }

  return {
    ...priorEntry,
    error,
    ids,
    entryUpdatedAt: now,
  };
}

function idsIfPresent(maybeEntry) {
  return (maybeEntry && !maybeEntry.error && maybeEntry.ids) ? maybeEntry.ids : null;
}
