import { omit } from 'lodash';
import { combineReducers } from 'redux';

import testAllActionChanges from '../../support/testAllActionChanges';
import { safeSelect } from '../../support/resources';

import makeResourceSelectors from 'lib/resourceLib/resourceSelectors';
import makeResourceActionGroup from 'lib/resourceLib/resourceActions';
import makeResourceReducer from 'lib/resourceLib/resourceReducers';

describe("makeResourceReducer", () => {
  const rex = { type: "dogs", id: "1", name: "Rex", carrying: "stick" };
  const spot = { type: "dogs", id: "2", name: "Spot", carrying: "ball" };
  const spot2 = { type: "dogs", id: "2", name: "Spot", carrying: "slobbery ball" };
  const phineas = { type: "dogs", id: "3", name: "Phineas the Third", carrying: "shoe" };
  const stranger = { type: "dogs", id: "4", name: "Stranger", carrying: "mysterious object" };

  const options = {
    fetchCollection: true,
    fetchIndividual: true,
    create: true,
    update: true,
    destroy: true,
    customSascActions: {
      'bark': { kind: 'individual' },
      'rename': { kind: 'individual', invalidation: true },
      'run-iditarod': { kind: 'collection' },
    },
  };

  const dogActions = makeResourceActionGroup('dogs', options);
  const dogSelectors = makeResourceSelectors('dogs', dogActions, options);
  const dogReducer = makeResourceReducer(dogActions, options);
  const reducer = combineReducers({ resources: combineReducers({ dogs: dogReducer }) });

  function buildStateFromActions(actions) {
    return actions.reduce(reducer, {});
  }

  it('sets empty cache after invalidation action', () => {
    const initialState = { resources: { dogs: { cache: '1234' } } };
    const newState = reducer(initialState, dogActions.invalidateCache(true));
    expect(newState.resources.dogs.cache).toEqual({});
  });

  describe("updating cache after fetches", () => {
    const threeDogs = [spot, rex, phineas];
    const threeDogsWithSpot2 = [spot2, rex, phineas];
    const fourDogsWithSpot2 = [spot2, rex, phineas, stranger];

    const testSelectors = {
      getAll: safeSelect((state) => dogSelectors.getMany(state)),
      getSpot: safeSelect((state) => dogSelectors.getOne(state, "2")),
      getStranger: safeSelect((state) => dogSelectors.getOne(state, "4")),
      isIndexErrored: dogSelectors.isCollectionErrored,
      isSpotErrored: (state) => dogSelectors.isResourceErrored(state, "2"),
      isFetching: dogSelectors.isFetching,
    };

    const fetchAllAction = dogActions.fetchCollection({});
    const fetchSpotAndStrangerAction = dogActions.fetchCollection({ filters: { id: ["2", "4"] } });
    const fetchSpotAction = dogActions.fetchIndividual({ id: "2" });
    const fetchStrangerAction = dogActions.fetchIndividual({ id: "4" });

    const testActions = {
      fetchAll: fetchAllAction,
      fetchSpotAndStranger: fetchSpotAndStrangerAction,
      fetchSpot: fetchSpotAction,
      fetchStranger: fetchStrangerAction,

      // After requesting Spot and Stranger by ids, got back both
      fetchSpotAndStrangerSucceeded: dogActions.fetchCollectionSucceeded([spot, stranger], {
        originalAction: fetchSpotAndStrangerAction,
      }),

      // After requesting Spot and Stranger by ids, only got Stranger
      fetchSpotAndStrangerPartialSuccess: dogActions.fetchCollectionSucceeded([stranger], {
        originalAction: fetchSpotAndStrangerAction,
      }),

      fetchThreeSucceeded: dogActions.fetchCollectionSucceeded(threeDogs, { originalAction: fetchAllAction }),
      fetchSpotSucceeded: dogActions.fetchIndividualSucceeded(spot, { originalAction: fetchSpotAction }),
      fetchSpotSucceededWithSpot2: dogActions.fetchIndividualSucceeded(spot2, { originalAction: fetchSpotAction }),
      fetchStrangerSucceeded: dogActions.fetchIndividualSucceeded(stranger, { originalAction: fetchStrangerAction }),

      gotIncludedResources: dogActions.includedResourcesReceived(fourDogsWithSpot2),

      fetchAllInitiated: dogActions.fetchCollectionInitiated({ originalAction: fetchAllAction }),
      fetchSpotAndStrangerInitiated: dogActions.fetchCollectionInitiated({ originalAction: fetchSpotAndStrangerAction }),
      fetchSpotInitiated: dogActions.fetchIndividualInitiated({ originalAction: fetchSpotAction }),

      fetchAllFailed: dogActions.fetchCollectionFailed("Ack!", { originalAction: fetchAllAction }, true),
      fetchSpotAndStrangerFailed: dogActions.fetchCollectionFailed("Oh no!", { originalAction: fetchSpotAndStrangerAction }, true),
      fetchSpotFailed: dogActions.fetchIndividualFailed("Urgh!", { originalAction: fetchSpotAction }, true),
      fetchStrangerFailed: dogActions.fetchIndividualFailed("Wat.", { originalAction: fetchStrangerAction }, true),
    };

    describe("from an empty state", () => {
      const state = {};

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: {
          getAll: [],
          getSpot: null,
          getStranger: null,
          isIndexErrored: false,
          isSpotErrored: false,
          isFetching: false,
        },

        fetchThreeSucceeded: { getAll: threeDogs, getSpot: spot },
        fetchSpotAndStrangerSucceeded: { getSpot: spot, getStranger: stranger },
        fetchSpotAndStrangerPartialSuccess: { getStranger: stranger },
        fetchSpotSucceeded: { getSpot: spot },
        fetchSpotSucceededWithSpot2: { getSpot: spot2 },
        fetchStrangerSucceeded: { getStranger: stranger },

        gotIncludedResources: { getSpot: spot2, getStranger: stranger },

        fetchAllInitiated: { isFetching: true },
        fetchSpotAndStrangerInitiated: { isFetching: true },
        fetchSpotInitiated: { isFetching: true },

        fetchAllFailed: { isIndexErrored: true },
        fetchSpotFailed: { isSpotErrored: true },
        fetchSpotAndStrangerFailed: {},
      });
    });

    describe("from a state after collection fetching begins", () => {
      const state = buildStateFromActions([
        dogActions.fetchCollectionInitiated({ originalAction: fetchAllAction }),
      ]);

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: {
          getAll: [],
          getSpot: null,
          getStranger: null,
          isIndexErrored: false,
          isSpotErrored: false,
          isFetching: true,
        },

        fetchThreeSucceeded: { getAll: threeDogs, getSpot: spot, isFetching: false },
        fetchSpotAndStrangerSucceeded: { getSpot: spot, getStranger: stranger, isFetching: false },
        fetchSpotAndStrangerPartialSuccess: { getStranger: stranger, isFetching: false },
        fetchSpotSucceeded: { getSpot: spot, isFetching: false },
        fetchSpotSucceededWithSpot2: { getSpot: spot2, isFetching: false },
        fetchStrangerSucceeded: { getStranger: stranger, isFetching: false },

        gotIncludedResources: { getSpot: spot2, getStranger: stranger },

        fetchAllFailed: { isIndexErrored: true, isFetching: false },
        fetchSpotAndStrangerFailed: { isFetching: false },
        fetchSpotFailed: { isSpotErrored: true, isFetching: false  },
        fetchStrangerFailed: { isFetching: false },
      });
    });

    describe("from a state with cached resources and index", () => {
      const state = buildStateFromActions([
        dogActions.fetchCollectionSucceeded(threeDogs, { originalAction: fetchAllAction }),
      ]);

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: {
          getAll: threeDogs,
          getSpot: spot,
          getStranger: null,
          isIndexErrored: false,
          isSpotErrored: false,
          isFetching: false,
        },

        fetchSpotAndStrangerSucceeded: { getStranger: stranger },
        fetchSpotAndStrangerPartialSuccess: { getStranger: stranger },
        fetchSpotSucceededWithSpot2: { getAll: threeDogsWithSpot2, getSpot: spot2 },
        fetchStrangerSucceeded: { getStranger: stranger },

        gotIncludedResources: { getAll: threeDogsWithSpot2, getStranger: stranger, getSpot: spot2 },

        fetchAllInitiated: { isFetching: true },
        fetchSpotAndStrangerInitiated: { isFetching: true },
        fetchSpotInitiated: { isFetching: true },

        fetchAllFailed: { getAll: [], isIndexErrored: true },
        // In the two scenarios below, the index is errored because it references Spot and Spot is errored
        fetchSpotFailed: { getAll: [], isIndexErrored: true, isSpotErrored: true, getSpot: null },
      });
    });

    describe("from a state refetching cached resources", () => {
      const state = buildStateFromActions([
        dogActions.fetchCollectionSucceeded(threeDogsWithSpot2, { originalAction: fetchAllAction }),
        dogActions.fetchCollectionInitiated({ originalAction: fetchAllAction }),
      ]);

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: {
          getAll: threeDogsWithSpot2,
          getSpot: spot2,
          getStranger: null,
          isIndexErrored: false,
          isSpotErrored: false,
          isFetching: true,
        },

        fetchThreeSucceeded: { getAll: threeDogs, getSpot: spot, isFetching: false },
        fetchSpotAndStrangerSucceeded: { getAll: threeDogs, getSpot: spot, getStranger: stranger, isFetching: false },
        fetchSpotAndStrangerPartialSuccess: { getStranger: stranger, isFetching: false },
        fetchSpotSucceeded: { getAll: threeDogs, getSpot: spot, isFetching: false },
        fetchSpotSucceededWithSpot2: { isFetching: false },
        fetchStrangerSucceeded: { getStranger: stranger, isFetching: false },

        gotIncludedResources: { getStranger: stranger },

        fetchAllFailed: { getAll: [], isIndexErrored: true, isFetching: false },
        fetchStrangerFailed: { isFetching: false },
        // In the two scenarios below, the index is errored because it references Spot and Spot is errored
        fetchSpotAndStrangerFailed: { isFetching: false  },
        fetchSpotFailed: { getAll: [], isIndexErrored: true, isSpotErrored: true, getSpot: null, isFetching: false },
      });
    });

    describe("from a state with a cached resource but no index", () => {
      const state = buildStateFromActions([
        dogActions.fetchIndividualSucceeded(spot, { originalAction: fetchSpotAction }),
      ]);

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: {
          getAll: [],
          getSpot: spot,
          getStranger: null,
          isIndexErrored: false,
          isSpotErrored: false,
          isFetching: false,
        },

        fetchThreeSucceeded: { getAll: threeDogs },
        fetchSpotAndStrangerSucceeded: { getStranger: stranger },
        fetchSpotAndStrangerPartialSuccess: { getStranger: stranger },
        fetchSpotSucceededWithSpot2: { getSpot: spot2 },
        fetchStrangerSucceeded: { getStranger: stranger },

        gotIncludedResources: { getStranger: stranger, getSpot: spot2 },

        fetchAllInitiated: { isFetching: true },
        fetchSpotAndStrangerInitiated: { isFetching: true },
        fetchSpotInitiated: { isFetching: true },

        fetchAllFailed: { isIndexErrored: true },
        fetchSpotFailed: { isSpotErrored: true, getSpot: null },
      });
    });

    describe("from a state with cached resources but no index", () => {
      const state = buildStateFromActions([
        dogActions.fetchCollectionSucceeded([spot, stranger], { originalAction: fetchSpotAndStrangerAction }),
      ]);

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: {
          getAll: [],
          getSpot: spot,
          getStranger: stranger,
          isIndexErrored: false,
          isSpotErrored: false,
          isFetching: false,
        },

        fetchThreeSucceeded: { getAll: threeDogs },
        fetchSpotSucceededWithSpot2: { getSpot: spot2 },

        gotIncludedResources: { getSpot: spot2 },

        fetchAllInitiated: { isFetching: true },
        fetchSpotAndStrangerInitiated: { isFetching: true },
        fetchSpotInitiated: { isFetching: true },

        fetchAllFailed: { isIndexErrored: true },
        fetchSpotFailed: { isSpotErrored: true, getSpot: null },
        fetchStrangerFailed: { getStranger: null },
      });
    });
  });

  describe("creating resources", () => {
    const testSelectors = {
      getIndexed: safeSelect(dogSelectors.getMany),
      getSpot: safeSelect((state) => dogSelectors.getOne(state, "2")),
      getSpotCreationStatus: (state) => dogSelectors.getCreationStatus(state, 'my-name-is-spot'),
      getSpotCreationResult: (state) => dogSelectors.getCreationResult(state, 'my-name-is-spot'),
    };

    const createSpotAction = dogActions.create(omit(spot, 'id'), { pid: 'my-name-is-spot' });
    const createPhinAction = dogActions.create(omit(phineas, 'id'), { pid: 'my-name-is-phineas' });

    const testActions = {
      createSpot: createSpotAction,
      createPhin: createPhinAction,

      createSpotInitiated: dogActions.createInitiated({ originalAction: createSpotAction, initiated: true }),
      createSpotSucceeded: dogActions.createSucceeded(spot, { originalAction: createSpotAction, initiated: true }),
      createAltSpotSucceeded: dogActions.createSucceeded(spot2, { originalAction: createSpotAction, initiated: true }),
      createSpotFailed: dogActions.createFailed("Oops", { originalAction: createSpotAction, initiated: true }),
      createSpotFailedEarly: dogActions.createFailed("Oops", { originalAction: createSpotAction, initiated: false }),

      createPhinInitiated: dogActions.createInitiated({ originalAction: createPhinAction, initiated: true }),
      createPhinSucceeded: dogActions.createSucceeded(phineas, { originalAction: createPhinAction, initiated: true }),
      createPhinFailed: dogActions.createFailed("Oops", { originalAction: createPhinAction, initiated: true }),
      createPhinFailedEarly: dogActions.createFailed("Oops", { originalAction: createPhinAction, initiated: false }),
    };

    describe("from an empty state", () => {
      const state = {};

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getIndexed: [], getSpot: null, getSpotCreationStatus: 'unstarted', getSpotCreationResult: null },
        createSpotInitiated: { getSpotCreationStatus: 'running' },
        createSpotFailed: { getSpotCreationStatus: 'errored' },
        createSpotSucceeded: { getSpotCreationStatus: 'completed', getSpot: spot, getSpotCreationResult: spot },
        createAltSpotSucceeded: { getSpotCreationStatus: 'completed', getSpot: spot2, getSpotCreationResult: spot2 },
      });
    });

    describe("from a state after creation begins", () => {
      const state = buildStateFromActions([
        dogActions.createInitiated({ originalAction: createSpotAction, initiated: true, getSpotCreationResult: null }),
      ]);

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getIndexed: [], getSpot: null, getSpotCreationStatus: 'running' },
        createSpotFailed: { getSpotCreationStatus: 'errored' },
        createSpotSucceeded: { getSpotCreationStatus: 'completed', getSpot: spot, getSpotCreationResult: spot },
        createAltSpotSucceeded: { getSpotCreationStatus: 'completed', getSpot: spot2, getSpotCreationResult: spot2 },
      });
    });

    describe("from a state after creation has completed", () => {
      const state = buildStateFromActions([
        dogActions.createSucceeded(spot, { originalAction: createSpotAction, initiated: true }),
      ]);

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getIndexed: [], getSpot: spot, getSpotCreationStatus: 'completed', getSpotCreationResult: spot },
        createSpotInitiated: { getSpotCreationStatus: 'running', getSpotCreationResult: null },
        createSpotFailed: { getSpotCreationStatus: 'errored', getSpotCreationResult: null },
        createAltSpotSucceeded: { getSpot: spot2, getSpotCreationResult: spot2 },
      });
    });

    describe("from a state with cached resources and index", () => {
      const dogs = [spot, rex, phineas];
      const state = buildStateFromActions([
        dogActions.fetchCollectionSucceeded(dogs),
      ]);

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getIndexed: dogs, getSpot: spot, getSpotCreationStatus: 'unstarted', getSpotCreationResult: null },
        createSpotInitiated: { getSpotCreationStatus: 'running' },
        createSpotFailed: { getSpotCreationStatus: 'errored' },
        createSpotSucceeded: { getIndexed: [], getSpotCreationStatus: 'completed', getSpotCreationResult: spot },
        createAltSpotSucceeded: { getIndexed: [], getSpotCreationStatus: 'completed', getSpot: spot2, getSpotCreationResult: spot2 },
        createPhinSucceeded: { getIndexed: [] },
      });
    });

    describe("from a state with a cached resource but no index", () => {
      const state = buildStateFromActions([
        dogActions.fetchIndividualSucceeded(spot),
      ]);

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getIndexed: [], getSpot: spot, getSpotCreationStatus: 'unstarted', getSpotCreationResult: null },
        createSpotInitiated: { getSpotCreationStatus: 'running' },
        createSpotFailed: { getSpotCreationStatus: 'errored' },
        createSpotSucceeded: { getSpotCreationStatus: 'completed', getSpotCreationResult: spot },
        createAltSpotSucceeded: { getSpotCreationStatus: 'completed', getSpot: spot2, getSpotCreationResult: spot2 },
      });
    });
  });

  describe("updating resources", () => {
    const testSelectors = {
      getIndexed: safeSelect(dogSelectors.getMany),
      getSpot: safeSelect((state) => dogSelectors.getOne(state, "2")),
      getSpotUpdateStatus: (state) => dogSelectors.getUpdateStatus(state, 'updating-spot'),
    };

    const updateSpotAction = dogActions.update(spot, { pid: 'updating-spot' });
    const updatePhinAction = dogActions.update(phineas, { pid: 'updating-phineas' });

    const testActions = {
      updateSpot: updateSpotAction,
      updatePhin: updatePhinAction,

      updateSpotInitiated: dogActions.updateInitiated({ originalAction: updateSpotAction, initiated: true }),
      updateSpotSucceeded: dogActions.updateSucceeded(spot, { originalAction: updateSpotAction, initiated: true }),
      updateAltSpotSucceeded: dogActions.updateSucceeded(spot2, { originalAction: updateSpotAction, initiated: true }),
      updateSpotFailed: dogActions.updateFailed("Oops", { originalAction: updateSpotAction, initiated: true }),
      updateSpotFailedEarly: dogActions.updateFailed("Oops", { originalAction: updateSpotAction, initiated: false }),

      updatePhinInitiated: dogActions.updateInitiated({ originalAction: updatePhinAction, initiated: true }),
      updatePhinSucceeded: dogActions.updateSucceeded(phineas, { originalAction: updatePhinAction, initiated: true }),
      updatePhinFailed: dogActions.updateFailed("Oops", { originalAction: updatePhinAction, initiated: true }),
      updatePhinFailedEarly: dogActions.updateFailed("Oops", { originalAction: updatePhinAction, initiated: false }),
    };

    describe("from an empty state", () => {
      const state = {};

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getIndexed: [], getSpot: null, getSpotUpdateStatus: 'unstarted' },
        updateSpotInitiated: { getSpotUpdateStatus: 'running' },
        updateSpotFailed: { getSpotUpdateStatus: 'errored' },
        updateSpotSucceeded: { getSpotUpdateStatus: 'completed', getSpot: spot },
        updateAltSpotSucceeded: { getSpotUpdateStatus: 'completed', getSpot: spot2 },
      });
    });

    describe("from a state after update begins", () => {
      const state = buildStateFromActions([
        dogActions.updateInitiated({ originalAction: updateSpotAction, initiated: true }),
      ]);

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getIndexed: [], getSpot: null, getSpotUpdateStatus: 'running' },
        updateSpotFailed: { getSpotUpdateStatus: 'errored' },
        updateSpotSucceeded: { getSpotUpdateStatus: 'completed', getSpot: spot },
        updateAltSpotSucceeded: { getSpotUpdateStatus: 'completed', getSpot: spot2 },
      });
    });

    describe("from a state after update has completed", () => {
      const state = buildStateFromActions([
        dogActions.updateSucceeded(spot, { originalAction: updateSpotAction, initiated: true }),
      ]);

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getIndexed: [], getSpot: spot, getSpotUpdateStatus: 'completed' },
        updateSpotInitiated: { getSpotUpdateStatus: 'running' },
        updateSpotFailed: { getSpotUpdateStatus: 'errored' },
        updateAltSpotSucceeded: { getSpot: spot2 },
      });
    });

    describe("from a state with cached resources and index", () => {
      const state = buildStateFromActions([
        dogActions.fetchCollectionSucceeded([spot, rex, phineas]),
      ]);

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getIndexed: [spot, rex, phineas], getSpot: spot, getSpotUpdateStatus: 'unstarted' },
        updateSpotInitiated: { getSpotUpdateStatus: 'running' },
        updateSpotFailed: { getSpotUpdateStatus: 'errored' },
        updateSpotSucceeded: { getIndexed: [], getSpotUpdateStatus: 'completed' },
        updateAltSpotSucceeded: { getIndexed: [], getSpotUpdateStatus: 'completed', getSpot: spot2 },
        updatePhinSucceeded: { getIndexed: [] },
      });
    });

    describe("from a state with a cached resource but no index", () => {
      const state = buildStateFromActions([
        dogActions.fetchIndividualSucceeded(spot),
      ]);

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getIndexed: [], getSpot: spot, getSpotUpdateStatus: 'unstarted' },
        updateSpotInitiated: { getSpotUpdateStatus: 'running' },
        updateSpotFailed: { getSpotUpdateStatus: 'errored' },
        updateSpotSucceeded: { getSpotUpdateStatus: 'completed' },
        updateAltSpotSucceeded: { getSpotUpdateStatus: 'completed', getSpot: spot2 },
      });
    });
  });

  describe("destroying resources", () => {
    const testSelectors = {
      getIndexed: safeSelect(dogSelectors.getMany),
      getSpot: safeSelect((state) => dogSelectors.getOne(state, "2")),
      getSpotDestroyStatus: (state) => dogSelectors.getDestroyStatus(state, 'deleting-spot'),
      getPhin: safeSelect((state) => dogSelectors.getOne(state, "3")),
    };

    const destroySpotAction = dogActions.destroy({ id: spot.id }, { pid: 'deleting-spot' });
    const destroyPhinAction = dogActions.destroy({ id: phineas.id }, { pid: 'deleting-phineas' });

    const testActions = {
      destroySpot: destroySpotAction,
      destroyPhin: destroyPhinAction,

      destroySpotInitiated: dogActions.destroyInitiated({ originalAction: destroySpotAction, initiated: true }),
      destroySpotSucceeded: dogActions.destroySucceeded({ id: spot.id }, { originalAction: destroySpotAction, initiated: true }),
      destroySpotFailed: dogActions.destroyFailed("Oops", { originalAction: destroySpotAction, initiated: true }),
      destroySpotFailedEarly: dogActions.destroyFailed("Oops", { originalAction: destroySpotAction, initiated: false }),

      destroyPhinInitiated: dogActions.destroyInitiated({ originalAction: destroyPhinAction, initiated: true }),
      destroyPhinSucceeded: dogActions.destroySucceeded({ id: phineas.id }, { originalAction: destroyPhinAction, initiated: true }),
      destroyPhinFailed: dogActions.destroyFailed("Oops", { originalAction: destroyPhinAction, initiated: true }),
      destroyPhinFailedEarly: dogActions.destroyFailed("Oops", { originalAction: destroyPhinAction, initiated: false }),
    };

    describe("from an empty state", () => {
      const state = {};

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getIndexed: [], getSpot: null, getSpotDestroyStatus: 'unstarted', getPhin: null },
        destroySpotInitiated: { getSpotDestroyStatus: 'running' },
        destroySpotFailed: { getSpotDestroyStatus: 'errored' },
        destroySpotSucceeded: { getSpotDestroyStatus: 'completed' },
      });
    });

    describe("from a state after destroy begins", () => {
      const state = buildStateFromActions([
        dogActions.destroyInitiated({ originalAction: destroySpotAction, initiated: true }),
      ]);

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getIndexed: [], getSpot: null, getSpotDestroyStatus: 'running', getPhin: null },
        destroySpotFailed: { getSpotDestroyStatus: 'errored' },
        destroySpotSucceeded: { getSpotDestroyStatus: 'completed' },
      });
    });

    describe("from a state after destroy has completed", () => {
      const state = buildStateFromActions([
        dogActions.destroySucceeded(spot.id, { originalAction: destroySpotAction, initiated: true }),
      ]);

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getIndexed: [], getSpot: null, getSpotDestroyStatus: 'completed', getPhin: null },
        destroySpotInitiated: { getSpotDestroyStatus: 'running' },
        destroySpotFailed: { getSpotDestroyStatus: 'errored' },
      });
    });

    describe("from a state with cached resources and index", () => {
      const state = buildStateFromActions([
        dogActions.fetchCollectionSucceeded([spot, rex, phineas]),
      ]);

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getIndexed: [spot, rex, phineas], getSpot: spot, getSpotDestroyStatus: 'unstarted', getPhin: phineas },
        destroySpotInitiated: { getSpotDestroyStatus: 'running' },
        destroySpotFailed: { getSpotDestroyStatus: 'errored' },
        destroySpotSucceeded: { getIndexed: [], getSpot: null, getSpotDestroyStatus: 'completed' },
        destroyPhinSucceeded: { getIndexed: [], getPhin: null },
      });
    });

    describe("from a state with a cached resource but no index", () => {
      const state = buildStateFromActions([
        dogActions.fetchIndividualSucceeded(spot),
      ]);

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getIndexed: [], getSpot: spot, getSpotDestroyStatus: 'unstarted', getPhin: null },
        destroySpotInitiated: { getSpotDestroyStatus: 'running' },
        destroySpotFailed: { getSpotDestroyStatus: 'errored' },
        destroySpotSucceeded: { getSpotDestroyStatus: 'completed', getSpot: null },
      });
    });
  });

  describe("individual custom sasc actions", () => {
    const testSelectors = {
      getSpotBarkStatus: (state) => dogSelectors.getBarkStatus(state, 'pid1'),
      getSpotBarkResult: (state) => dogSelectors.getBarkResult(state, 'pid1'),
      getIndexed: safeSelect(dogSelectors.getMany),
      getSpot: safeSelect((state) => dogSelectors.getOne(state, "2")),
    };

    const barkSpotAction = dogActions.bark({ id: spot.id, arguments: { query: "who's a good boy?" } }, { pid: 'pid1' });
    const barkPhinAction = dogActions.bark({ id: phineas.id, arguments: { query: "who's a good boy?" } }, { pid: 'pid2' });

    const testActions = {
      barkSpot: barkSpotAction,
      barkPhin: barkPhinAction,

      barkSpotInitiated: dogActions.barkInitiated({ originalAction: barkSpotAction, initiated: true }),
      barkSpotSucceeded: dogActions.barkSucceeded({ tail: "wag" }, { originalAction: barkSpotAction, initiated: true }),
      barkSpotFailed: dogActions.barkFailed("Oops", { originalAction: barkSpotAction, initiated: true }),
      barkSpotFailedEarly: dogActions.barkFailed("Oops", { originalAction: barkSpotAction, initiated: false }),

      barkPhinInitiated: dogActions.barkInitiated({ originalAction: barkPhinAction, initiated: true }),
      barkPhinSucceeded: dogActions.barkSucceeded({ tail: "wag" }, { originalAction: barkPhinAction, initiated: true }),
      barkPhinFailed: dogActions.barkFailed("Oops", { originalAction: barkPhinAction, initiated: true }),
      barkPhinFailedEarly: dogActions.barkFailed("Oops", { originalAction: barkPhinAction, initiated: false }),
    };

    describe("from an empty state", () => {
      const state = {};

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getSpotBarkStatus: 'unstarted', getSpotBarkResult: null, getIndexed: [], getSpot: null },
        barkSpotInitiated: { getSpotBarkStatus: 'running' },
        barkSpotFailed: { getSpotBarkStatus: 'errored' },
        barkSpotSucceeded: { getSpotBarkStatus: 'completed', getSpotBarkResult: { tail: "wag" } },
      });
    });

    describe("from a state after bark begins", () => {
      const state = buildStateFromActions([
        dogActions.barkInitiated({ originalAction: barkSpotAction, initiated: true, getSpotBarkResult: null }),
      ]);

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getSpotBarkStatus: 'running', getSpotBarkResult: null, getIndexed: [], getSpot: null },
        barkSpotFailed: { getSpotBarkStatus: 'errored' },
        barkSpotSucceeded: { getSpotBarkStatus: 'completed', getSpotBarkResult: { tail: "wag" } },
      });
    });

    describe("from a state after bark has completed", () => {
      const state = buildStateFromActions([
        dogActions.barkSucceeded({ tail: "very wag" }, { originalAction: barkSpotAction, initiated: true }),
      ]);

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getSpotBarkStatus: 'completed', getSpotBarkResult: { tail: "very wag" }, getIndexed: [], getSpot: null },
        barkSpotInitiated: { getSpotBarkStatus: 'running', getSpotBarkResult: null },
        barkSpotFailed: { getSpotBarkStatus: 'errored', getSpotBarkResult: null },
        barkSpotSucceeded: { getSpotBarkResult: { tail: "wag" } },
      });
    });

    describe("from a state with cached resources and index", () => {
      const state = buildStateFromActions([
        dogActions.fetchCollectionSucceeded([spot, rex, phineas]),
      ]);

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getSpotBarkStatus: 'unstarted', getSpotBarkResult: null, getIndexed: [spot, rex, phineas], getSpot: spot },
        barkSpotInitiated: { getSpotBarkStatus: 'running' },
        barkSpotFailed: { getSpotBarkStatus: 'errored' },
        barkSpotSucceeded: { getSpotBarkStatus: 'completed', getSpotBarkResult: { tail: "wag" } }, // No change to index or cache
      });
    });
  });

  describe("individual custom sasc actions with invalidation enabled", () => {
    const testSelectors = {
      getIndexed: safeSelect(dogSelectors.getMany),
      getSpot: safeSelect((state) => dogSelectors.getOne(state, "2")),
    };

    const renameSpotAction = dogActions.bark({ id: spot.id, arguments: { name: "Dot" } }, { pid: 'pid1' });
    const renamePhinAction = dogActions.bark({ id: phineas.id, arguments: { name: "Gage" } }, { pid: 'pid2' });

    const testActions = {
      renameSpot: renameSpotAction,
      renamePhin: renamePhinAction,

      renameSpotInitiated: dogActions.renameInitiated({ originalAction: renameSpotAction, initiated: true }),
      renameSpotSucceeded: dogActions.renameSucceeded({ renamed: "Dot" }, { originalAction: renameSpotAction, initiated: true, invalidation: true }),
      renameSpotFailed: dogActions.renameFailed("Oops", { originalAction: renameSpotAction, initiated: true }),
      renameSpotFailedEarly: dogActions.renameFailed("Oops", { originalAction: renameSpotAction, initiated: false }),

      renamePhinInitiated: dogActions.renameInitiated({ originalAction: renamePhinAction, initiated: true }),
      renamePhinSucceeded: dogActions.renameSucceeded({ renamed: "Gage" }, { originalAction: renamePhinAction, initiated: true, invalidation: true }),
      renamePhinFailed: dogActions.renameFailed("Oops", { originalAction: renamePhinAction, initiated: true }),
      renamePhinFailedEarly: dogActions.renameFailed("Oops", { originalAction: renamePhinAction, initiated: false }),
    };

    describe("from an empty state", () => {
      const state = {};

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getIndexed: [], getSpot: null },
      });
    });

    describe("from a state with cached resources and index", () => {
      const state = buildStateFromActions([
        dogActions.fetchCollectionSucceeded([spot, rex, phineas]),
      ]);

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getIndexed: [spot, rex, phineas], getSpot: spot },
        renameSpotSucceeded: { getIndexed: [], getSpot: null },
        renamePhinSucceeded: { getIndexed: [], getSpot: null },
      });
    });
  });

  describe("collection custom sasc actions", () => {
    const testSelectors = {
      getNorthRunStatus: (state) => dogSelectors.getRunIditarodStatus(state, 'pid1'),
      getNorthRunResult: (state) => dogSelectors.getRunIditarodResult(state, 'pid1'),
    };

    const runNorthAction = dogActions.runIditarod({ arguments: { direction: "north" } }, { pid: 'pid1' });
    const runSouthAction = dogActions.runIditarod({ arguments: { direction: "south" } }, { pid: 'pid2' });

    const testActions = {
      runNorth: runNorthAction,
      runSouth: runSouthAction,

      runNorthInitiated: dogActions.runIditarodInitiated({ originalAction: runNorthAction, initiated: true }),
      runNorthSucceeded: dogActions.runIditarodSucceeded({ tails: "wag" }, { originalAction: runNorthAction, initiated: true }),
      runNorthFailed: dogActions.runIditarodFailed("Oops", { originalAction: runNorthAction, initiated: true }),
      runNorthFailedEarly: dogActions.runIditarodFailed("Oops", { originalAction: runNorthAction, initiated: false }),

      runSouthInitiated: dogActions.runIditarodInitiated({ originalAction: runSouthAction, initiated: true }),
      runSouthSucceeded: dogActions.runIditarodSucceeded({ tails: "wag" }, { originalAction: runSouthAction, initiated: true }),
      runSouthFailed: dogActions.runIditarodFailed("Oops", { originalAction: runSouthAction, initiated: true }),
      runSouthFailedEarly: dogActions.runIditarodFailed("Oops", { originalAction: runSouthAction, initiated: false }),
    };

    describe("from an empty state", () => {
      const state = {};

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getNorthRunStatus: 'unstarted', getNorthRunResult: null },
        runNorthInitiated: { getNorthRunStatus: 'running' },
        runNorthFailed: { getNorthRunStatus: 'errored' },
        runNorthSucceeded: { getNorthRunStatus: 'completed', getNorthRunResult: { tails: "wag" } },
      });
    });

    describe("from a state after runIditarod begins", () => {
      const state = buildStateFromActions([
        dogActions.runIditarodInitiated({ originalAction: runNorthAction, initiated: true, getNorthRunResult: null }),
      ]);

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getNorthRunStatus: 'running', getNorthRunResult: null },
        runNorthFailed: { getNorthRunStatus: 'errored' },
        runNorthSucceeded: { getNorthRunStatus: 'completed', getNorthRunResult: { tails: "wag" } },
      });
    });

    describe("from a state after runIditarod has completed", () => {
      const state = buildStateFromActions([
        dogActions.runIditarodSucceeded({ tails: "very wag" }, { originalAction: runNorthAction, initiated: true }),
      ]);

      testAllActionChanges(reducer, state, testActions, testSelectors, {
        noAction: { getNorthRunStatus: 'completed', getNorthRunResult: { tails: "very wag" } },
        runNorthInitiated: { getNorthRunStatus: 'running', getNorthRunResult: null },
        runNorthFailed: { getNorthRunStatus: 'errored', getNorthRunResult: null },
        runNorthSucceeded: { getNorthRunResult: { tails: "wag" } },
      });
    });
  });
});
