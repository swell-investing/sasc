import { compact, get, map } from 'lodash';

import { makeResourceIndex, indexAddQueryResults, indexSetError } from 'lib/resourceLib/resourceIndex';
import {
  makeResourceCache,
  cacheAddResource,
  cacheAddResources,
  cacheRemoveResource,
  cacheSetError,
} from 'lib/resourceLib/resourceCache';
import { makeResourceProcesses, processesUpdate } from 'lib/resourceLib/resourceProcesses';
import { camelCaseName } from 'lib/resourceLib/resourceNames';
import { STATUS_RUNNING, STATUS_COMPLETED, STATUS_ERRORED } from 'lib/resourceLib';

export default function makeResourceReducer(actionGroup, options) {
  const { fetchCollection, fetchIndividual, create, update, destroy, customSascActions } = options;

  function stateCache(state) {
    if (state && state.cache) { return state.cache; }
    return makeResourceCache();
  }

  function stateIndex(state) {
    if (state && state.index) { return state.index; }
    return makeResourceIndex();
  }

  function stateProcesses(state) {
    if (state && state.processes) { return state.processes; }
    return makeResourceProcesses();
  }

  // TODO: When we receive an updated resource, we should invalidate index sequences which contain that resource id,
  // on the grounds that the ordering might have changed

  function fetchIndividualActionsReducer(state, action) {
    // NOTE: These actions do not change the index
    switch(action.type) {
    case actionGroup.fetchIndividualInitiated.actionType:
      return {
        ...state,
        fetching: true,
      };
    case actionGroup.fetchIndividualSucceeded.actionType:
      return {
        ...state,
        cache: cacheAddResource(stateCache(state), action.payload),
        fetching: false,
      };
    case actionGroup.fetchIndividualFailed.actionType:
      return {
        ...state,
        cache: cacheSetError(stateCache(state), action.meta.originalAction.payload.id),
        fetching: false,
      };
    default:
      return state;
    }
  }

  function fetchCollectionActionsReducer(state, action) {
    const cache = stateCache(state);
    const index = stateIndex(state);
    const params = get(action, ['meta', 'originalAction', 'payload'], {});

    switch(action.type) {
    case actionGroup.fetchCollectionInitiated.actionType:
      return {
        ...state,
        fetching: true,
      };
    case actionGroup.fetchCollectionSucceeded.actionType: {
      const gotIds = map(action.payload, 'id');

      return {
        ...state,
        cache: cacheAddResources(cache, action.payload),
        index: indexAddQueryResults(index, params, gotIds),
        fetching: false,
      };
    }
    case actionGroup.fetchCollectionFailed.actionType: {
      return {
        ...state,
        index: indexSetError(index, params),
        fetching: false,
      };
    }
    default:
      return state;
    }
  }

  function includedActionsReducer(state, action) {
    switch(action.type) {
    case actionGroup.includedResourcesReceived.actionType:
      return {
        ...state,
        cache: cacheAddResources(stateCache(state), action.payload),
      };
    default:
      return state;
    }
  }

  function invalidationActionsReducer(state, action) {
    switch(action.type) {
    case actionGroup.invalidateCache.actionType:
      return { ...state, cache: {}, index: {} };
    default:
      return state;
    }
  }

  function createActionsReducer(state, action) {
    switch(action.type) {
    case actionGroup.createInitiated.actionType:
      return {
        ...state,
        processes: processesUpdate(state.processes, 'create', action, STATUS_RUNNING),
      };
    case actionGroup.createSucceeded.actionType:
      return {
        ...state,
        index: {}, // This is very aggressive, but better to be safe than to risk holding on to invalid data
        cache: cacheAddResource(stateCache(state), action.payload),
        processes: processesUpdate(state.processes, 'create', action, STATUS_COMPLETED, { result: action.payload }),
      };
    case actionGroup.createFailed.actionType:
      return {
        ...state,
        processes: processesUpdate(state.processes, 'create', action, STATUS_ERRORED),
      };
    default:
      return state;
    }
  }

  function updateActionsReducer(state, action) {
    switch(action.type) {
    case actionGroup.updateInitiated.actionType:
      return {
        ...state,
        processes: processesUpdate(state.processes, 'update', action, STATUS_RUNNING),
      };
    case actionGroup.updateSucceeded.actionType:
      return {
        ...state,
        index: {}, // This is very aggressive, but better to be safe than to risk holding on to invalid data
        cache: cacheAddResource(stateCache(state), action.payload),
        processes: processesUpdate(state.processes, 'update', action, STATUS_COMPLETED),
      };
    case actionGroup.updateFailed.actionType:
      return {
        ...state,
        processes: processesUpdate(state.processes, 'update', action, STATUS_ERRORED),
      };
    default:
      return state;
    }
  }

  function destroyActionsReducer(state, action) {
    switch(action.type) {
    case actionGroup.destroyInitiated.actionType:
      return {
        ...state,
        processes: processesUpdate(state.processes, 'destroy', action, STATUS_RUNNING),
      };
    case actionGroup.destroySucceeded.actionType:
      return {
        ...state,
        index: {}, // This is very aggressive, but better to be safe than to risk holding on to invalid data
        cache: cacheRemoveResource(stateCache(state), action.payload.id),
        processes: processesUpdate(state.processes, 'destroy', action, STATUS_COMPLETED),
      };
    case actionGroup.destroyFailed.actionType:
      return {
        ...state,
        processes: processesUpdate(state.processes, 'destroy', action, STATUS_ERRORED),
      };
    default:
      return state;
    }
  }

  function makeSascActionReducer(name, _config) {
    const initiatedAction = actionGroup[`${name}Initiated`];
    const succeededAction = actionGroup[`${name}Succeeded`];
    const failedAction = actionGroup[`${name}Failed`];

    return (state, action) => {
      const cache = stateCache(state);
      const index = stateIndex(state);
      const processes = stateProcesses(state);

      switch(action.type) {
      case initiatedAction.actionType:
        return {
          ...state,
          processes: processesUpdate(processes, name, action, STATUS_RUNNING),
        };
      case succeededAction.actionType:
        return {
          ...state,
          cache: action.meta.invalidation ? {} : cache,
          index: action.meta.invalidation ? {} : index,
          processes: processesUpdate(processes, name, action, STATUS_COMPLETED, { result: action.payload }),
        };
      case failedAction.actionType:
        return {
          ...state,
          processes: processesUpdate(processes, name, action, STATUS_ERRORED),
        };
      default:
        return state;
      }
    };
  }

  function makeCustomSascActionReducers() {
    return map(customSascActions, (config, name) => {
      name = camelCaseName(name);
      return makeSascActionReducer(name, config);
    });
  }

  const reducers = compact([
    fetchCollection ? fetchCollectionActionsReducer : null,
    fetchIndividual ? fetchIndividualActionsReducer : null,
    includedActionsReducer,
    invalidationActionsReducer,
    create ? createActionsReducer : null,
    update ? updateActionsReducer : null,
    destroy ? destroyActionsReducer : null,
    ...makeCustomSascActionReducers(),
  ]);

  // This is the final return value, a single reducer that runs each above enabled mini-reducer in sequence
  return function(state = { fetching: false }, action) {
    return reducers.reduce((prevState, reducer) => reducer(prevState, action), state);
  };
}
