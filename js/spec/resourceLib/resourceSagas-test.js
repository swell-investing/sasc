import { find, filter } from 'lodash';
import SagaTester from 'redux-saga-tester';

import makeResourceActionGroup from 'lib/resourceLib/resourceActions';
import makeResourceSelectors from 'lib/resourceLib/resourceSelectors';
import makeResourceSagas from 'lib/resourceLib/resourceSagas';
import { cacheSetError } from 'lib/resourceLib/resourceCache';
import { indexSetError } from 'lib/resourceLib/resourceIndex';
import { buildResourceState } from '../../support/resources';

describe("makeResourceSagas", () => {
  // In order to test that the sagas correctly handled included resources, we have to mock out the mechanism that
  // the sagas use to look up the action group for each included resource type and generate inclusion actions. The
  // actual content of our fake inclusion actions doesn't matter, we just need to check that the saga is calling
  // the right action generator with the right arguments and dispatching whatever it generates.
  const mockInclusionActionCreator = jest.fn().mockImplementation((data) => ({ type: "INCLUSION_WAT", payload: data }));
  const mockInvalidationActionCreator = jest.fn().mockImplementation((_data) => ({ type: 'INVALIDATION_WAT' }));
  const mockActionGroup = {
    includedResourcesReceived: mockInclusionActionCreator,
    invalidateCache: mockInvalidationActionCreator,
  };
  const mockActionGroupLookup = jest.fn().mockReturnValue(mockActionGroup);
  const mockResDef = { resourceActionGroup: mockActionGroupLookup };
  const options = {
    fetchCollection: true,
    fetchIndividual: true,
    create: true,
    update: true,
    destroy: true,
    customSascActions: {
      'bark': { kind: 'individual', invalidation: (result) => result.changedStuff },
      'run-iditarod': { kind: 'collection', invalidation: true },
    },
    invalidatesCachedTypes: { cats: true },
  };

  let actionGroup, selectors, sagas, client;

  beforeEach(() => {
    client = {
      getIndividual: jest.fn(),
      getCollection: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      destroy: jest.fn(),
      bark: jest.fn(),
      runIditarod: jest.fn(),
    };

    actionGroup = makeResourceActionGroup('dogs', options);
    selectors = makeResourceSelectors('dogs', actionGroup, options);
    sagas = makeResourceSagas(mockResDef, 'dogs', client, actionGroup, selectors, options);
  });

  describe('fetchIndividualSaga', () => {
    let saga, originalAction;
    beforeEach(() => {
      saga = sagas.fetchIndividualSaga;
      originalAction = actionGroup.fetchIndividual({ id: "1" });
    });

    it('fetches a resource', async () => {
      client.getIndividual.mockReturnValueOnce({
        data: { type: "dogs", id: "1", attributes: { name: "Rex", carrying: "stick" } },
      });

      const initialState = buildResourceState([{ id: "2", type: "dogs" }]);
      const sagaTester = new SagaTester({ initialState });
      sagaTester.start(saga);

      sagaTester.dispatch(originalAction);
      await sagaTester.waitFor('RSRC_DOGS_RESOURCE_FETCHED');

      expect(client.getIndividual.mock.calls.length).toEqual(1);
      expect(client.getIndividual).toBeCalledWith("1");

      expect(sagaTester.numCalled('RSRC_DOGS_FETCH_INDIVIDUAL_INITIATED')).toEqual(1);
      expect(sagaTester.numCalled('RSRC_DOGS_RESOURCE_FETCHED')).toEqual(1);

      expect(
        filter(sagaTester.getCalledActions(), { type: 'RSRC_DOGS_FETCH_INDIVIDUAL_SUCCEEDED' })
      ).toEqual([{
        type: 'RSRC_DOGS_FETCH_INDIVIDUAL_SUCCEEDED',
        payload: { type: "dogs", id: "1", name: "Rex", carrying: "stick" },
        meta: { originalAction },
      }]);

      expect(
        filter(sagaTester.getCalledActions(), { type: 'RSRC_DOGS_RESOURCE_FETCHED' })
      ).toEqual([{
        type: 'RSRC_DOGS_RESOURCE_FETCHED',
        payload: { type: "dogs", id: "1", name: "Rex", carrying: "stick", relationships: undefined },
      }]);
    });

    it('dispatches actions for included resources', async () => {
      client.getIndividual.mockReturnValueOnce({
        data: { type: "dogs", id: "1", attributes: { name: "Rex", carrying: "stick" } },
        included: {
          turtles: [
            { type: "turtles", id: "3", attributes: { name: "Leonardo", carrying: "shuriken" } },
          ],
        },
      });

      const initialState = buildResourceState([{ id: "2", type: "dogs" }]);
      const sagaTester = new SagaTester({ initialState });
      sagaTester.start(saga);

      sagaTester.dispatch(originalAction);
      await sagaTester.waitFor('RSRC_DOGS_FETCH_INDIVIDUAL_SUCCEEDED');

      expect(client.getIndividual.mock.calls.length).toEqual(1);
      expect(client.getIndividual).toBeCalledWith("1");

      expect(mockActionGroupLookup).toBeCalledWith("turtles");
      expect(sagaTester.numCalled('INCLUSION_WAT')).toEqual(1);
      expect(find(sagaTester.getCalledActions(), { type: 'INCLUSION_WAT' })).toEqual({
        type: "INCLUSION_WAT",
        payload: [{ type: "turtles", id: "3", name: "Leonardo", carrying: "shuriken" }],
      });
    });

    it('handles errors', async () => {
      client.getIndividual.mockImplementationOnce(() => {
        throw new Error("Something went wrong");
      });

      const initialState = buildResourceState([{ id: "2", type: "dogs" }]);
      const sagaTester = new SagaTester({ initialState });
      sagaTester.start(saga);

      sagaTester.dispatch(originalAction);
      await sagaTester.waitFor('RSRC_DOGS_FETCH_INDIVIDUAL_FAILED');

      expect(client.getIndividual.mock.calls.length).toEqual(1);
      expect(client.getIndividual).toBeCalledWith("1");

      expect(sagaTester.numCalled('RSRC_DOGS_FETCH_INDIVIDUAL_INITIATED')).toEqual(1);
      expect(sagaTester.getLatestCalledAction()).toEqual({
        type: 'RSRC_DOGS_FETCH_INDIVIDUAL_FAILED',
        error: true,
        payload: new Error("Something went wrong"),
        meta: { originalAction },
      });
    });

    it('returns early if already fetching', async () => {
      const initialState = { resources: { dogs: { fetching: true } } };
      const sagaTester = new SagaTester( { initialState });
      const sagaPromise = sagaTester.start(saga);

      sagaTester.dispatch(originalAction);

      await sagaPromise;

      expect(client.getIndividual).not.toBeCalled();
      expect(sagaTester.numCalled('RSRC_DOGS_FETCH_INDIVIDUAL_INITIATED')).toEqual(0);
    });

    it('returns early if already cached', async () => {
      const initialState = buildResourceState([{ id: "1", type: "dogs" }]);
      const sagaTester = new SagaTester({ initialState });
      const sagaPromise = sagaTester.start(saga);

      sagaTester.dispatch(originalAction);

      await sagaPromise;

      expect(client.getIndividual).not.toBeCalled();
      expect(sagaTester.numCalled('RSRC_DOGS_FETCH_INDIVIDUAL_INITIATED')).toEqual(0);
    });

    it('returns early if already known to be in error state', async () => {
      const emptyCache = {};
      const failedResourcedId = "1";
      const errorCache = cacheSetError(emptyCache, failedResourcedId);

      const initialState = { resources: { dogs: { cache: errorCache } } };
      const sagaTester = new SagaTester({ initialState });
      const sagaPromise = sagaTester.start(saga);

      sagaTester.dispatch(originalAction);

      await sagaPromise;

      expect(client.getIndividual).not.toBeCalled();
      expect(sagaTester.numCalled('RSRC_DOGS_FETCH_INDIVIDUAL_INITIATED')).toEqual(0);
    });

    it('continues even if already cached if the action asks to ignoreCache', async () => {
      const initialState = buildResourceState([{ id: "1", type: "dogs" }]);
      const sagaTester = new SagaTester({ initialState });
      const sagaPromise = sagaTester.start(saga);

      const ignoreCacheAction = actionGroup.fetchIndividual({ id: "1", ignoreCache: true });

      sagaTester.dispatch(ignoreCacheAction);

      await sagaPromise;

      expect(client.getIndividual).toBeCalled();
      expect(sagaTester.numCalled('RSRC_DOGS_FETCH_INDIVIDUAL_INITIATED')).toEqual(1);
    });

    it('continues even if already fetching if the action asks to ignoreCache', async () => {
      const initialState = { resources: { dogs: { fetching: true } } };
      const sagaTester = new SagaTester({ initialState });
      const sagaPromise = sagaTester.start(saga);

      const ignoreCacheAction = actionGroup.fetchIndividual({ id: "1", ignoreCache: true });

      sagaTester.dispatch(ignoreCacheAction);

      await sagaPromise;

      expect(client.getIndividual).toBeCalled();
      expect(sagaTester.numCalled('RSRC_DOGS_FETCH_INDIVIDUAL_INITIATED')).toEqual(1);
    });
  });

  describe('fetchCollectionSaga', () => {
    let saga, originalAction;
    beforeEach(() => {
      saga = sagas.fetchCollectionSaga;
      originalAction = actionGroup.fetchCollection({});
    });

    it('fetches a collection', async () => {
      client.getCollection.mockReturnValueOnce({
        data: [
          { type: "dogs", id: "1", attributes: { name: "Rex", carrying: "stick" } },
          { type: "dogs", id: "2", attributes: { name: "Majestic", carrying: "ball" } },
          { type: "dogs", id: "3", attributes: { name: "Phineas the Third", carrying: "shoe" } },
        ],
      });

      const sagaTester = new SagaTester({});
      sagaTester.start(saga);

      sagaTester.dispatch(originalAction);
      await sagaTester.waitFor('RSRC_DOGS_FETCH_COLLECTION_SUCCEEDED');

      expect(client.getCollection.mock.calls.length).toEqual(1);
      expect(client.getCollection).toBeCalledWith({ filters: {} });

      expect(sagaTester.numCalled('RSRC_DOGS_FETCH_COLLECTION_INITIATED')).toEqual(1);
      expect(sagaTester.numCalled('RSRC_DOGS_RESOURCE_FETCHED')).toEqual(3);

      expect(
        filter(sagaTester.getCalledActions(), { type: 'RSRC_DOGS_FETCH_COLLECTION_SUCCEEDED' })
      ).toEqual([{
        type: 'RSRC_DOGS_FETCH_COLLECTION_SUCCEEDED',
        payload: [
          { type: "dogs", id: "1", name: "Rex", carrying: "stick" },
          { type: "dogs", id: "2", name: "Majestic", carrying: "ball" },
          { type: "dogs", id: "3", name: "Phineas the Third", carrying: "shoe" },
        ],
        meta: { originalAction },
      }]);

      expect(
        filter(sagaTester.getCalledActions(), { type: 'RSRC_DOGS_RESOURCE_FETCHED' })
      ).toEqual([
        { type: 'RSRC_DOGS_RESOURCE_FETCHED',
          payload: { type: "dogs", id: "1", name: "Rex", carrying: "stick" } },
        { type: 'RSRC_DOGS_RESOURCE_FETCHED',
          payload: { type: "dogs", id: "2", name: "Majestic", carrying: "ball" } },
        { type: 'RSRC_DOGS_RESOURCE_FETCHED',
          payload: { type: "dogs", id: "3", name: "Phineas the Third", carrying: "shoe" } },
      ]);
    });

    it('dispatches actions for included resources', async () => {
      client.getCollection.mockReturnValueOnce({
        data: [
          { type: "dogs", id: "1", attributes: { name: "Rex", carrying: "stick" } },
          { type: "dogs", id: "2", attributes: { name: "Majestic", carrying: "ball" } },
          { type: "dogs", id: "3", attributes: { name: "Phineas the Third", carrying: "shoe" } },
        ],
        included: {
          turtles: [
            { type: "turtles", id: "3", attributes: { name: "Leonardo", carrying: "shuriken" } },
          ],
        },
      });

      const sagaTester = new SagaTester({});
      sagaTester.start(saga);

      sagaTester.dispatch(originalAction);
      await sagaTester.waitFor('RSRC_DOGS_FETCH_COLLECTION_SUCCEEDED');

      expect(client.getCollection.mock.calls.length).toEqual(1);
      expect(client.getCollection).toBeCalledWith({ filters: {} });

      expect(mockActionGroupLookup).toBeCalledWith("turtles");
      expect(sagaTester.numCalled('INCLUSION_WAT')).toEqual(1);
      expect(find(sagaTester.getCalledActions(), { type: 'INCLUSION_WAT' })).toEqual({
        type: "INCLUSION_WAT",
        payload: [{ type: "turtles", id: "3", name: "Leonardo", carrying: "shuriken" }],
      });
    });

    it('handles errors', async () => {
      client.getCollection.mockImplementationOnce(() => {
        throw new Error("Something went wrong");
      });

      const sagaTester = new SagaTester({});
      sagaTester.start(saga);

      sagaTester.dispatch(originalAction);
      await sagaTester.waitFor('RSRC_DOGS_FETCH_COLLECTION_FAILED');

      expect(client.getCollection.mock.calls.length).toEqual(1);
      expect(client.getCollection).toBeCalledWith({ filters: {} });

      expect(sagaTester.numCalled('RSRC_DOGS_FETCH_COLLECTION_INITIATED')).toEqual(1);
      expect(sagaTester.getLatestCalledAction()).toEqual({
        type: 'RSRC_DOGS_FETCH_COLLECTION_FAILED',
        error: true,
        payload: new Error("Something went wrong"),
        meta: { originalAction },
      });
    });

    it('returns early if already fetching', async () => {
      const initialState = { resources: { dogs: { fetching: true } } };
      const sagaTester = new SagaTester( { initialState });
      const sagaPromise = sagaTester.start(saga);

      sagaTester.dispatch(originalAction);

      await sagaPromise;

      expect(client.getCollection).not.toBeCalled();
      expect(sagaTester.numCalled('RSRC_DOGS_FETCH_COLLECTION_INITIATED')).toEqual(0);
    });

    it('returns early if already cached', async () => {
      const initialState = buildResourceState([{ id: "1", type: "dogs" }]);
      const sagaTester = new SagaTester({ initialState });
      const sagaPromise = sagaTester.start(saga);

      sagaTester.dispatch(originalAction);

      await sagaPromise;

      expect(client.getCollection).not.toBeCalled();
      expect(sagaTester.numCalled('RSRC_DOGS_FETCH_COLLECTION_INITIATED')).toEqual(0);
    });

    it('continues even if already fetching if the action asks to ignoreCache', async () => {
      const initialState = { resources: { dogs: { fetching: true } } };
      const sagaTester = new SagaTester({ initialState });
      const sagaPromise = sagaTester.start(saga);

      const ignoreCacheAction = actionGroup.fetchCollection({ ignoreCache: true });

      sagaTester.dispatch(ignoreCacheAction);

      await sagaPromise;

      expect(client.getCollection).toBeCalled();
      expect(sagaTester.numCalled('RSRC_DOGS_FETCH_COLLECTION_INITIATED')).toEqual(1);
    });

    it('continues even if already cached if the action asks to ignoreCache', async () => {
      const initialState = buildResourceState([{ id: "1", type: "dogs" }]);
      const sagaTester = new SagaTester({ initialState });
      const sagaPromise = sagaTester.start(saga);

      const ignoreCacheAction = actionGroup.fetchCollection({ ignoreCache: true });

      sagaTester.dispatch(ignoreCacheAction);

      await sagaPromise;

      expect(client.getCollection).toBeCalled();
      expect(sagaTester.numCalled('RSRC_DOGS_FETCH_COLLECTION_INITIATED')).toEqual(1);
    });

    it('returns early if index is already known to be in error state', async () => {
      const emptyIndex = {};
      const failedQueryParams = {};
      const errorIndex = indexSetError(emptyIndex, failedQueryParams);

      const initialState = { resources: { dogs: { index: errorIndex } } };
      const sagaTester = new SagaTester({ initialState });
      const sagaPromise = sagaTester.start(saga);

      sagaTester.dispatch(originalAction);

      await sagaPromise;

      expect(client.getCollection).not.toBeCalled();
      expect(sagaTester.numCalled('RSRC_DOGS_FETCH_COLLECTION_INITIATED')).toEqual(0);
    });
  });

  describe('createSaga', () => {
    let saga, originalAction;
    beforeEach(() => {
      saga = sagas.createSaga;

      originalAction = actionGroup.create(
        { type: "dogs", name: "Rover", carrying: "Martian soil" },
        { pid: "my-new-dog" }
      );
    });

    it('creates a new dog resource through the http client', async () => {
      client.create.mockReturnValueOnce({
        data: {
          type: "dogs",
          id: "99",
          attributes: {
            name: "Rover",
            carrying: "Martian soil",
          },
        },
      });

      const sagaTester = new SagaTester({});
      sagaTester.start(saga);

      sagaTester.dispatch(originalAction);
      await sagaTester.waitFor('INVALIDATION_WAT');
      await sagaTester.waitFor('RSRC_DOGS_CREATE_SUCCEEDED');

      expect(client.create.mock.calls.length).toEqual(1);
      expect(client.create).toBeCalledWith({
        type: "dogs",
        attributes: {
          name: "Rover",
          carrying: "Martian soil",
        },
      });

      expect(sagaTester.numCalled('RSRC_DOGS_CREATE_INITIATED')).toEqual(1);
      expect(sagaTester.getLatestCalledAction()).toEqual({
        type: 'RSRC_DOGS_CREATE_SUCCEEDED',
        meta: { originalAction, initiated: true },
        payload: { type: "dogs", id: "99", name: "Rover", carrying: "Martian soil" },
      });
    });

    it('defaults to "default-pid" if there is no pid in the action meta', async () => {
      const sagaTester = new SagaTester({});
      sagaTester.start(saga);

      const pidlessAction = { ...originalAction, meta: {} };
      sagaTester.dispatch(pidlessAction);
      await sagaTester.waitFor('RSRC_DOGS_CREATE_INITIATED');

      expect(find(sagaTester.getCalledActions(), { type: 'RSRC_DOGS_CREATE_INITIATED' })).toEqual({
        type: "RSRC_DOGS_CREATE_INITIATED",
        meta: { originalAction: { ...pidlessAction, meta: { pid: "default-pid" } }, initiated: true },
      });
    });

    it('fails if pid is already taken by another create', async () => {
      const initialState = { resources: { dogs: { processes: { create: {
        "my-new-dog": { status: "running" },
      } } } } };
      const sagaTester = new SagaTester({ initialState });
      sagaTester.start(saga);

      sagaTester.dispatch(originalAction);
      await sagaTester.waitFor('RSRC_DOGS_CREATE_FAILED');

      expect(client.create).not.toBeCalled();

      expect(sagaTester.numCalled('RSRC_DOGS_CREATE_INITIATED')).toEqual(0);
      expect(sagaTester.getLatestCalledAction()).toEqual({
        type: 'RSRC_DOGS_CREATE_FAILED',
        error: true,
        payload: new Error("Already running create with pid my-new-dog"),
        meta: { originalAction, initiated: false },
      });
    });

    it('handles errors', async () => {
      client.create.mockImplementationOnce(() => {
        throw new Error("Something went wrong");
      });

      const sagaTester = new SagaTester({});
      sagaTester.start(saga);

      sagaTester.dispatch(originalAction);
      await sagaTester.waitFor('RSRC_DOGS_CREATE_FAILED');

      expect(client.create.mock.calls.length).toEqual(1);

      expect(sagaTester.numCalled('RSRC_DOGS_CREATE_INITIATED')).toEqual(1);
      expect(sagaTester.getLatestCalledAction()).toEqual({
        type: 'RSRC_DOGS_CREATE_FAILED',
        error: true,
        payload: new Error("Something went wrong"),
        meta: { originalAction, initiated: true },
      });
    });
  });

  describe('updateSaga', () => {
    let saga, originalAction;
    beforeEach(() => {
      saga = sagas.updateSaga;
      originalAction = actionGroup.update(
        { type: "dogs", id: "99", name: "Rover", carrying: "Martian soil" },
        { pid: "foo" }
      );
    });

    it('updates a resource through the http client', async () => {
      client.update.mockReturnValueOnce({
        data: {
          type: "dogs",
          id: "99",
          attributes: {
            name: "Rover",
            carrying: "Martian soil",
          },
        },
      });

      const sagaTester = new SagaTester({ });
      sagaTester.start(saga);

      sagaTester.dispatch(originalAction);
      await sagaTester.waitFor('INVALIDATION_WAT');
      await sagaTester.waitFor('RSRC_DOGS_UPDATE_SUCCEEDED');

      expect(client.update.mock.calls.length).toEqual(1);
      expect(client.update).toBeCalledWith({
        id: "99",
        type: "dogs",
        attributes: {
          name: "Rover",
          carrying: "Martian soil",
        },
      });

      expect(sagaTester.numCalled('RSRC_DOGS_UPDATE_INITIATED')).toEqual(1);
      expect(sagaTester.getLatestCalledAction()).toEqual({
        type: 'RSRC_DOGS_UPDATE_SUCCEEDED',
        payload: { type: "dogs", id: "99", name: "Rover", carrying: "Martian soil" },
        meta: { originalAction, initiated: true },
      });
    });

    it('handles errors', async () => {
      client.update.mockImplementationOnce(() => {
        throw new Error("Something went wrong");
      });

      const sagaTester = new SagaTester({});
      sagaTester.start(saga);

      sagaTester.dispatch(originalAction);
      await sagaTester.waitFor('RSRC_DOGS_UPDATE_FAILED');

      expect(client.update.mock.calls.length).toEqual(1);

      expect(sagaTester.numCalled('RSRC_DOGS_UPDATE_INITIATED')).toEqual(1);
      expect(sagaTester.getLatestCalledAction()).toEqual({
        type: 'RSRC_DOGS_UPDATE_FAILED',
        error: true,
        payload: new Error("Something went wrong"),
        meta: { originalAction, initiated: true },
      });
    });

    it('defaults to "default-pid" if there is no pid in the action meta', async () => {
      const sagaTester = new SagaTester({});
      sagaTester.start(saga);

      const pidlessAction = { ...originalAction, meta: {} };
      sagaTester.dispatch(pidlessAction);
      await sagaTester.waitFor('RSRC_DOGS_UPDATE_INITIATED');

      expect(find(sagaTester.getCalledActions(), { type: 'RSRC_DOGS_UPDATE_INITIATED' })).toEqual({
        type: "RSRC_DOGS_UPDATE_INITIATED",
        meta: { originalAction: { ...pidlessAction, meta: { pid: "default-pid" } }, initiated: true },
      });
    });

    it('fails if pid is already taken by another update', async () => {
      const initialState = { resources: { dogs: { processes: { update: {
        "foo": { status: "running" },
      } } } } };
      const sagaTester = new SagaTester({ initialState });
      sagaTester.start(saga);

      sagaTester.dispatch(originalAction);
      await sagaTester.waitFor('RSRC_DOGS_UPDATE_FAILED');

      expect(client.update).not.toBeCalled();

      expect(sagaTester.numCalled('RSRC_DOGS_UPDATE_INITIATED')).toEqual(0);
      expect(sagaTester.getLatestCalledAction()).toEqual({
        type: 'RSRC_DOGS_UPDATE_FAILED',
        error: true,
        payload: new Error("Already running update with pid foo"),
        meta: { originalAction, initiated: false },
      });
    });
  });

  describe('destroySaga', () => {
    let saga, originalAction;
    beforeEach(() => {
      saga = sagas.destroySaga;
      originalAction = actionGroup.destroy({ id: "99" }, { pid: "foo" });
    });

    it('destroys a resource through the http client', async () => {
      client.destroy.mockReturnValueOnce(null);

      const sagaTester = new SagaTester({ });
      sagaTester.start(saga);

      sagaTester.dispatch(originalAction);
      await sagaTester.waitFor('INVALIDATION_WAT');
      await sagaTester.waitFor('RSRC_DOGS_DESTROY_SUCCEEDED');

      expect(client.destroy).toBeCalledWith("99");

      expect(sagaTester.numCalled('RSRC_DOGS_DESTROY_INITIATED')).toEqual(1);
      expect(sagaTester.getLatestCalledAction()).toEqual({
        type: 'RSRC_DOGS_DESTROY_SUCCEEDED',
        payload: { id: "99" },
        meta: { originalAction, initiated: true },
      });
    });

    it('handles errors', async () => {
      client.destroy.mockImplementationOnce(() => {
        throw new Error("Something went wrong");
      });

      const sagaTester = new SagaTester({});
      sagaTester.start(saga);

      sagaTester.dispatch(originalAction);
      await sagaTester.waitFor('RSRC_DOGS_DESTROY_FAILED');

      expect(client.destroy).toBeCalledWith("99");

      expect(sagaTester.numCalled('RSRC_DOGS_DESTROY_INITIATED')).toEqual(1);
      expect(sagaTester.getLatestCalledAction()).toEqual({
        type: 'RSRC_DOGS_DESTROY_FAILED',
        error: true,
        payload: new Error("Something went wrong"),
        meta: { originalAction, initiated: true },
      });
    });

    it('defaults to "default-pid" if there is no pid in the action meta', async () => {
      const sagaTester = new SagaTester({});
      sagaTester.start(saga);

      const pidlessAction = { ...originalAction, meta: {} };
      sagaTester.dispatch(pidlessAction);
      await sagaTester.waitFor('RSRC_DOGS_DESTROY_INITIATED');

      expect(find(sagaTester.getCalledActions(), { type: 'RSRC_DOGS_DESTROY_INITIATED' })).toEqual({
        type: "RSRC_DOGS_DESTROY_INITIATED",
        meta: { originalAction: { ...pidlessAction, meta: { pid: "default-pid" } }, initiated: true },
      });
    });

    it('fails if pid is already taken by another destroy', async () => {
      const initialState = { resources: { dogs: { processes: { destroy: {
        "foo": { status: "running" },
      } } } } };
      const sagaTester = new SagaTester({ initialState });
      sagaTester.start(saga);

      sagaTester.dispatch(originalAction);
      await sagaTester.waitFor('RSRC_DOGS_DESTROY_FAILED');

      expect(client.destroy).not.toBeCalled();

      expect(sagaTester.numCalled('RSRC_DOGS_DESTROY_INITIATED')).toEqual(0);
      expect(sagaTester.getLatestCalledAction()).toEqual({
        type: 'RSRC_DOGS_DESTROY_FAILED',
        error: true,
        payload: new Error("Already running destroy with pid foo"),
        meta: { originalAction, initiated: false },
      });
    });
  });

  describe('individual SASC action saga', () => {
    let saga, originalAction;
    beforeEach(() => {
      saga = sagas.barkSaga;
      originalAction = actionGroup.bark(
        { id: "99", arguments: { throwing: "stick" } },
        { pid: "playing_fetch" }
      );
    });

    it('sends a request through the client to run the SASC action', async () => {
      client.bark.mockReturnValueOnce({ result: { noise: "woof" } });

      // Already running this action with another pid should not prevent this action from initiating the request.
      const initialState = { resources: { dogs: { processes: { bark: {
        "playing_tug_of_war": { status: "running" },
      } } } } };
      const sagaTester = new SagaTester({ initialState });
      sagaTester.start(saga);

      sagaTester.dispatch(originalAction);
      await sagaTester.waitFor('RSRC_DOGS_BARK_SUCCEEDED');

      expect(client.bark).toBeCalledWith("99", { throwing: "stick" });

      expect(sagaTester.numCalled('RSRC_DOGS_BARK_INITIATED')).toEqual(1);
      expect(sagaTester.getLatestCalledAction()).toEqual({
        type: 'RSRC_DOGS_BARK_SUCCEEDED',
        payload: { noise: "woof" },
        meta: { originalAction, initiated: true, invalidation: false },
      });
    });

    it('sets the invalidation flag to true when a custom invalidation function returns true', async () => {
      client.bark.mockReturnValueOnce({ result: { noise: "woof", changedStuff: true } });

      const sagaTester = new SagaTester({});
      sagaTester.start(saga);

      sagaTester.dispatch(originalAction);
      await sagaTester.waitFor('RSRC_DOGS_BARK_SUCCEEDED');

      expect(client.bark).toBeCalledWith("99", { throwing: "stick" });

      expect(sagaTester.numCalled('RSRC_DOGS_BARK_INITIATED')).toEqual(1);
      expect(sagaTester.getLatestCalledAction()).toEqual({
        type: 'RSRC_DOGS_BARK_SUCCEEDED',
        payload: { noise: "woof", changedStuff: true },
        meta: { originalAction, initiated: true, invalidation: true },
      });
    });

    it('handles errors', async () => {
      client.bark.mockImplementationOnce(() => {
        throw new Error("Something went wrong");
      });

      const sagaTester = new SagaTester({});
      sagaTester.start(saga);

      sagaTester.dispatch(originalAction);
      await sagaTester.waitFor('RSRC_DOGS_BARK_FAILED');

      expect(client.bark).toBeCalledWith("99", { throwing: "stick" });

      expect(sagaTester.numCalled('RSRC_DOGS_BARK_INITIATED')).toEqual(1);
      expect(sagaTester.getLatestCalledAction()).toEqual({
        type: 'RSRC_DOGS_BARK_FAILED',
        error: true,
        payload: new Error("Something went wrong"),
        meta: { originalAction, initiated: true },
      });
    });

    it('defaults to "default-pid" if there is no pid in the action meta', async () => {
      const sagaTester = new SagaTester({});
      sagaTester.start(saga);

      const pidlessAction = { ...originalAction, meta: {} };
      sagaTester.dispatch(pidlessAction);
      await sagaTester.waitFor('RSRC_DOGS_BARK_INITIATED');

      expect(find(sagaTester.getCalledActions(), { type: 'RSRC_DOGS_BARK_INITIATED' })).toEqual({
        type: "RSRC_DOGS_BARK_INITIATED",
        meta: { originalAction: { ...pidlessAction, meta: { pid: "default-pid" } }, initiated: true },
      });
    });

    it('fails if pid is already running', async () => {
      const initialState = { resources: { dogs: { processes: { bark: {
        "playing_fetch": { status: "running" },
      } } } } };
      const sagaTester = new SagaTester({ initialState });

      sagaTester.start(saga);

      sagaTester.dispatch(originalAction);
      await sagaTester.waitFor('RSRC_DOGS_BARK_FAILED');

      expect(client.bark).not.toBeCalled();

      expect(sagaTester.numCalled('RSRC_DOGS_BARK_INITIATED')).toEqual(0);
      expect(sagaTester.getLatestCalledAction()).toEqual({
        type: 'RSRC_DOGS_BARK_FAILED',
        error: true,
        payload: new Error("Already running bark with pid playing_fetch"),
        meta: { originalAction, initiated: false },
      });
    });
  });

  describe('collection SASC action saga', () => {
    let saga, originalAction;
    beforeEach(() => {
      saga = sagas.runIditarodSaga;
      originalAction = actionGroup.runIditarod(
        { arguments: { command: "mush" } },
        { pid: "balto" }
      );
    });

    it('sends a request through the client to run the SASC action', async () => {
      client.runIditarod.mockReturnValueOnce({ result: { destination: "Nome, Alaska" } });

      // Already running this action with another pid should not prevent this action from initiating the request.
      const initialState = { resources: { dogs: { processes: { runIditarod: {
        "togo": { status: "running" },
      } } } } };
      const sagaTester = new SagaTester({ initialState });
      sagaTester.start(saga);

      sagaTester.dispatch(originalAction);
      await sagaTester.waitFor('RSRC_DOGS_RUN_IDITAROD_SUCCEEDED');

      expect(client.runIditarod).toBeCalledWith({ command: "mush" });

      expect(sagaTester.numCalled('RSRC_DOGS_RUN_IDITAROD_INITIATED')).toEqual(1);
      expect(sagaTester.getLatestCalledAction()).toEqual({
        type: 'RSRC_DOGS_RUN_IDITAROD_SUCCEEDED',
        payload: { destination: "Nome, Alaska" },
        meta: { originalAction, initiated: true, invalidation: true },
      });
    });

    it('handles errors', async () => {
      client.runIditarod.mockImplementationOnce(() => {
        throw new Error("Something went wrong");
      });

      const sagaTester = new SagaTester({});
      sagaTester.start(saga);

      sagaTester.dispatch(originalAction);
      await sagaTester.waitFor('RSRC_DOGS_RUN_IDITAROD_FAILED');

      expect(client.runIditarod).toBeCalledWith({ command: "mush" });

      expect(sagaTester.numCalled('RSRC_DOGS_RUN_IDITAROD_INITIATED')).toEqual(1);
      expect(sagaTester.getLatestCalledAction()).toEqual({
        type: 'RSRC_DOGS_RUN_IDITAROD_FAILED',
        error: true,
        payload: new Error("Something went wrong"),
        meta: { originalAction, initiated: true },
      });
    });

    it('defaults to "default-pid" if there is no pid in the action meta', async () => {
      const sagaTester = new SagaTester({});
      sagaTester.start(saga);

      const pidlessAction = { ...originalAction, meta: {} };
      sagaTester.dispatch(pidlessAction);
      await sagaTester.waitFor('RSRC_DOGS_RUN_IDITAROD_INITIATED');

      expect(find(sagaTester.getCalledActions(), { type: 'RSRC_DOGS_RUN_IDITAROD_INITIATED' })).toEqual({
        type: "RSRC_DOGS_RUN_IDITAROD_INITIATED",
        meta: { originalAction: { ...pidlessAction, meta: { pid: "default-pid" } }, initiated: true },
      });
    });

    it('fails if pid is already running', async () => {
      const initialState = { resources: { dogs: { processes: { runIditarod: {
        "balto": { status: "running" },
      } } } } };
      const sagaTester = new SagaTester({ initialState });

      sagaTester.start(saga);

      sagaTester.dispatch(originalAction);
      await sagaTester.waitFor('RSRC_DOGS_RUN_IDITAROD_FAILED');

      expect(client.bark).not.toBeCalled();

      expect(sagaTester.numCalled('RSRC_DOGS_RUN_IDITAROD_INITIATED')).toEqual(0);
      expect(sagaTester.getLatestCalledAction()).toEqual({
        type: 'RSRC_DOGS_RUN_IDITAROD_FAILED',
        error: true,
        payload: new Error("Already running runIditarod with pid balto"),
        meta: { originalAction, initiated: false },
      });
    });
  });
});
