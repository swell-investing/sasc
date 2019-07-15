import { cloneDeep, get, isFunction, map, mapKeys,
         mapValues, merge, omit, pickBy, toPairs, upperFirst } from 'lodash';
import { call, put, select } from 'redux-saga/effects';
import { camelCaseName } from 'lib/resourceLib/resourceNames';
import { DEFAULT_PID } from 'lib/resourceLib';
import { takeSequentially } from 'sagas/helpers';

export default function makeResourceSagas(resourceDefinitions, resourceType, client, actionGroup, selectors, options) {
  const { fetchCollection, fetchIndividual, create, update, destroy,
          customSascActions, invalidatesCachedTypes } = options;

  function actionWithPid(action) {
    if (get(action, ['meta', 'pid'])) {
      return action;
    } else {
      return merge({}, action, { meta: { pid: DEFAULT_PID } });
    }
  }

  function * emitCacheInvalidations() {
    yield * map(invalidatesCachedTypes, function * (value, key) {
      const targetActionGroup = resourceDefinitions.resourceActionGroup(key);
      yield put(targetActionGroup.invalidateCache(value));
    });
  }

  function makeFetchCollectionSaga() {
    function * fetchCollectionHandler(action) {
      let dispatchMeta = { originalAction: action };

      try {
        const filters = get(action, "payload.filters", {});

        const ignoreCache = get(action, ["payload", "ignoreCache"], false);
        if (!ignoreCache) {
          const isFetching = yield select(selectors.isFetching);
          if (isFetching) return;

          const isKnown = yield select(selectors.isCollectionKnown, filters);
          if (isKnown) return;
        }

        yield put(actionGroup.fetchCollectionInitiated(dispatchMeta));
        const response = yield call(client.getCollection, { filters });
        const unpacked = unpackData(response.data);

        if (response.included) {
          yield includedResourcesHandler(response.included);
        }

        yield put(actionGroup.fetchCollectionSucceeded(unpacked, dispatchMeta));

        yield * unpacked.map(function * (resource) {
          yield put(actionGroup.resourceFetched(resource));
        });
      } catch (e) {
        yield put(actionGroup.fetchCollectionFailed(e, dispatchMeta, true));
      }
    }

    return function * () {
      yield takeSequentially(actionGroup.fetchCollection.pattern, fetchCollectionHandler);
    };
  }

  function makeFetchIndividualSaga() {
    function * fetchIndividualHandler(action) {
      let dispatchMeta = { originalAction: action };

      try {
        const { id } = action.payload;

        const ignoreCache = get(action, ["payload", "ignoreCache"], false);
        if (!ignoreCache) {
          const isFetching = yield select(selectors.isFetching);
          if (isFetching) return;

          const isKnown = yield select(selectors.isResourceKnown, id);
          if (isKnown) return;
        }

        yield put(actionGroup.fetchIndividualInitiated(dispatchMeta));
        const response = yield call(client.getIndividual, id);
        const unpacked = unpackDatum(response.data);

        if (response.included) {
          yield includedResourcesHandler(response.included);
        }

        yield put(actionGroup.fetchIndividualSucceeded(unpacked, dispatchMeta));

        yield put(actionGroup.resourceFetched(unpacked));
      } catch (e) {
        yield put(actionGroup.fetchIndividualFailed(e, dispatchMeta, true));
      }
    }

    return function * () {
      yield takeSequentially(actionGroup.fetchIndividual.pattern, fetchIndividualHandler);
    };
  }

  function makeCreateSaga() {
    function * createHandler(action) {
      action = actionWithPid(action);
      let dispatchMeta = { originalAction: action, initiated: false };

      try {
        const isCreating = yield select(selectors.isCreating, action.meta.pid);
        if (isCreating) { throw new Error(`Already running create with pid ${action.meta.pid}`); }

        if (action.payload.id) { throw new Error('Cannot specify id in resource creation payload'); }

        dispatchMeta.initiated = true;
        yield put(actionGroup.createInitiated(dispatchMeta));

        const packed = packDatum(action.payload);
        const response = yield call(client.create, packed);
        const unpackedResponse = unpackDatum(response.data);

        yield emitCacheInvalidations();
        if (response.included) {
          yield includedResourcesHandler(response.included);
        }
        yield put(actionGroup.createSucceeded(unpackedResponse, dispatchMeta));
      } catch (e) {
        yield put(actionGroup.createFailed(e, dispatchMeta, true));
      }
    }

    return function * () {
      yield takeSequentially(actionGroup.create.pattern, createHandler);
    };
  }

  // TODO: Prevent a given resource from being updated/deleted by more than one process at a time, ignoring pid

  function makeUpdateSaga() {
    function * updateHandler(action) {
      action = actionWithPid(action);
      let dispatchMeta = { originalAction: action, initiated: false };

      try {
        const isUpdating = yield select(selectors.isUpdating, action.meta.pid);
        if (isUpdating) { throw new Error(`Already running update with pid ${action.meta.pid}`); }

        dispatchMeta.initiated = true;
        yield put(actionGroup.updateInitiated(dispatchMeta));

        const packed = packDatum(action.payload);
        const response = yield call(client.update, packed);
        const unpackedResponse = unpackDatum(response.data);

        yield emitCacheInvalidations();
        if (response.included) {
          yield includedResourcesHandler(response.included);
        }
        yield put(actionGroup.updateSucceeded(unpackedResponse, dispatchMeta));
      } catch (e) {
        yield put(actionGroup.updateFailed(e, dispatchMeta, true));
      }
    }

    return function * () {
      yield takeSequentially(actionGroup.update.pattern, updateHandler);
    };
  }

  function makeDestroySaga() {
    function * destroyHandler(action) {
      action = actionWithPid(action);
      let dispatchMeta = { originalAction: action, initiated: false };

      try {
        const { id } = action.payload;
        if (!id) { throw new Error('Need id parameter in payload for resource destroy'); }

        const isDestroying = yield select(selectors.isDestroying, action.meta.pid);
        if (isDestroying) { throw new Error(`Already running destroy with pid ${action.meta.pid}`); }

        dispatchMeta.initiated = true;
        yield put(actionGroup.destroyInitiated(dispatchMeta));

        yield call(client.destroy, id); // Ignore response body, it should be empty anyways

        yield emitCacheInvalidations();
        yield put(actionGroup.destroySucceeded({ id }, dispatchMeta));
      } catch (e) {
        yield put(actionGroup.destroyFailed(e, dispatchMeta, true));
      }
    }

    return function * () {
      yield takeSequentially(actionGroup.destroy.pattern, destroyHandler);
    };
  }

  function makeSascActionSaga(name, isIndividual, { invalidation, invalidateOnFail }) {
    function * handler(action) {
      action = actionWithPid(action);
      let dispatchMeta = { originalAction: action, initiated: false };

      try {
        if (isIndividual) {
          if (!get(action, ["payload", "id"])) { throw new Error("Id is required for individual SASC actions"); }
        }

        const isRunningSelector = selectors[`is${upperFirst(name)}Running`];
        const isRunning = yield select(isRunningSelector, action.meta.pid);
        if (isRunning) { throw new Error(`Already running ${name} with pid ${action.meta.pid}`); }

        dispatchMeta.initiated = true;
        yield put(actionGroup[name + "Initiated"](cloneDeep(dispatchMeta)));

        const args = get(action, 'payload.arguments', {});
        const response = yield (isIndividual ? call(client[name], action.payload.id, args) : call(client[name], args));

        // TODO: Would be a more consistent config API if this always was a function
        const doInvalidation = isFunction(invalidation) ? invalidation(get(response, 'result', {})) : invalidation;
        if (doInvalidation) { yield emitCacheInvalidations(); }
        dispatchMeta.invalidation = Boolean(doInvalidation);

        yield put(actionGroup[name + "Succeeded"](get(response, 'result', {}), dispatchMeta));
      } catch (e) {
        if (invalidateOnFail) { yield emitCacheInvalidations(); }
        yield put(actionGroup[name + "Failed"](e, dispatchMeta, true));
      }
    }

    return function * () {
      yield takeSequentially(actionGroup[name].pattern, handler);
    };
  }

  function makeCustomSascActionSagas() {
    const sagas = mapValues(customSascActions, (config, name) => {
      const internalName = camelCaseName(name);

      switch (config.kind) {
      case "individual":
        return makeSascActionSaga(internalName, true, config);
      case "collection":
        return makeSascActionSaga(internalName, false, config);
      default:
        throw new Error("Custom SASC action kind must be 'individual' or 'collection'");
      }
    });

    return mapKeys(sagas, (_saga, name) => camelCaseName(`${name}-saga`));
  }

  function * includedResourcesHandler(included) {
    try {
      for (const [includedResourceType, items] of toPairs(included)) {
        const includedActionGroup = resourceDefinitions.resourceActionGroup(includedResourceType);

        if (includedActionGroup) yield(put(includedActionGroup.includedResourcesReceived(unpackData(items))));
      }
    } catch (e) {
      yield put({ type: "RSRC_INCLUDED_RESOURCE_HANDLER_FAILED", payload: e, error: true });
    }
  }

  return pickBy({
    fetchCollectionSaga: fetchCollection ? makeFetchCollectionSaga() : null,
    fetchIndividualSaga: fetchIndividual ? makeFetchIndividualSaga() : null,
    createSaga: create ? makeCreateSaga() : null,
    updateSaga: update ? makeUpdateSaga() : null,
    destroySaga: destroy ? makeDestroySaga() : null,
    ...makeCustomSascActionSagas(),
  });
}

function unpackData(data) {
  return data.map(unpackDatum);
}

function unpackDatum(datum={}) {
  const id = datum.id;
  const type = datum.type;
  const attributes = datum.attributes;
  const relationships = datum.relationships;

  return { ...attributes, id, type, relationships };
}

function packDatum(resource) {
  const id = resource.id;
  const type = resource.type;
  const relationships = resource.relationships;
  const attributes = omit(resource, ['id', 'type', 'relationships']);

  return pickBy({ id, type, attributes, relationships });
}
