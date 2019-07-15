import { mapValues } from 'lodash';

import { buildResourceState, trapSelect } from '../../support/resources';

import makeResourceActionGroup from 'lib/resourceLib/resourceActions';
import makeResourceSelectors, { CacheMissException, cacheMissOverrideDefault } from 'lib/resourceLib/resourceSelectors';
import { indexAddQueryResults, indexSetError } from 'lib/resourceLib/resourceIndex';
import { makeResourceCache, cacheSetError, cacheSetErrors } from 'lib/resourceLib/resourceCache';

describe("cacheMissOverrideDefault", () => {
  it('passes through the return value if no CacheMissException was raised', () => {
    expect(cacheMissOverrideDefault("foo", () => "bar")).toEqual("bar");
  });

  it('allows exceptions other than CacheMissException to pass through', () => {
    expect(() => cacheMissOverrideDefault("foo", () => { throw new Error("wat"); })).toThrow(new Error("wat"));
  });

  it('overrides the default value on CacheMissExceptions raised', () => {
    const origEx = new CacheMissException({ action: { type: "BAZ" }, default: "narf", description: "Oh no!" });
    const newEx = trapSelect(cacheMissOverrideDefault)("foo", () => { throw origEx; });
    expect(newEx).toBeInstanceOf(CacheMissException);
    expect(newEx.action).toBe(origEx.action);
    expect(newEx.description).toBe(origEx.description);
    expect(newEx.default).toEqual("foo");
    expect(origEx.default).toEqual("narf"); // Didn't modify the original exception object
  });

  it('calls function to generate default value if first argument is a function', () => {
    const origEx = new CacheMissException({ action: { type: "BAZ" }, default: "narf", description: "Oh no!" });
    const newEx = trapSelect(cacheMissOverrideDefault)(() => "foo", () => { throw origEx; });
    expect(newEx.default).toEqual("foo");
  });
});

describe("makeResourceSelectors", () => {
  const options = {
    fetchCollection: true,
    fetchIndividual: true,
    create: true,
    update: true,
    destroy: true,
    customSascActions: {
      'tackle': { kind: 'individual' },
      'collect-badges': { kind: 'collection' },
    },
  };
  const actionGroup = makeResourceActionGroup('pokemon', options);
  const selectors = makeResourceSelectors('pokemon', actionGroup, options);
  const trappedSelectors = mapValues(selectors, trapSelect);

  const emptyState = {};
  const emptyCache = {};
  const emptyIndex = {};
  const emptyParams = {};

  const charizard = { id: "6", type: "pokemon", name: "Charizard", pokeType: "Fire" };
  const pikachu = { id: "25", type: "pokemon", name: "Pikachu", pokeType: "Electric" };
  const breloom = { id: "286", type: "pokemon", name: "Breloom", pokeType: "Grass" };

  describe('isResourceKnown selector', () => {
    it('returns false when there is no cache', () => {
      expect(selectors.isResourceKnown(emptyState, "6")).toBe(false);
    });

    it('returns true if the resource is present in the cache', () => {
      const state = buildResourceState([pikachu, charizard, breloom]);
      expect(selectors.isResourceKnown(state, "6")).toBe(true);
    });

    it('returns true if the resource is errored', () => {
      const cache = cacheSetError(emptyCache, "6");
      const state = { resources: { pokemon: { cache } } };
      expect(selectors.isResourceKnown(state, "6")).toBe(true);
    });

    it('returns false if the resource is not present in the cache', () => {
      const state = buildResourceState([pikachu, breloom]);
      expect(selectors.isResourceKnown(state, "6")).toBe(false);
    });
  });

  describe('isResourceErrored selector', () => {
    it('returns false when there is no cache', () => {
      expect(selectors.isResourceErrored(emptyState, "6")).toBe(false);
    });

    it('returns false if the resource is present in the cache', () => {
      const state = buildResourceState([pikachu, charizard, breloom]);
      expect(selectors.isResourceErrored(state, "6")).toBe(false);
    });

    it('returns false if the resource is not present in the cache', () => {
      const state = buildResourceState([pikachu, breloom]);
      expect(selectors.isResourceErrored(state, "6")).toBe(false);
    });

    it('returns true if the resource is errored', () => {
      const cache = cacheSetError(emptyCache, "6");
      const state = { resources: { pokemon: { cache } } };
      expect(selectors.isResourceErrored(state, "6")).toBe(true);
    });
  });

  describe('isCollectionKnown selector', () => {
    function mkState(resources, index, errorIds = []) {
      const cache = cacheSetErrors(makeResourceCache(resources), errorIds);
      return { resources: { pokemon: { index, cache } } };
    }

    describe('when no parameters are passed', () => {
      function subject(state) { return selectors.isCollectionKnown(state); }

      it('returns false if there is no index', () => {
        expect(subject(emptyState)).toBe(false);
      });

      it('returns false if the index does not have a sequence for empty params', () => {
        const index = indexAddQueryResults(emptyIndex, { foo: "bar" }, ["6", "286", "25"]);
        const state = mkState(index);
        expect(subject(state)).toBe(false);
      });

      it('returns true if the index has a sequence for empty params and the resources are cached', () => {
        const index = indexAddQueryResults(emptyIndex, emptyParams, ["6", "286", "25"]);
        const state = mkState([pikachu, charizard, breloom], index);
        expect(subject(state)).toBe(true);
      });

      it('returns false if the index has a sequence for empty params but some resources are not cached', () => {
        const index = indexAddQueryResults(emptyIndex, emptyParams, ["6", "286", "25"]);
        const state = mkState([pikachu, breloom], index);
        expect(subject(state)).toBe(false);
      });

      it('returns true if the index has a matching sequence but some resources are errored', () => {
        const index = indexAddQueryResults(emptyIndex, emptyParams, ["6", "286", "25"]);
        const state = mkState([pikachu, breloom], index, "6");
        expect(subject(state)).toBe(true);
      });

      it('returns true if the index has an error for the sequence', () => {
        const index = indexSetError(emptyIndex, emptyParams);
        const state = mkState([], index);
        expect(subject(state)).toBe(true);
      });
    });

    describe('when parameters are passed', () => {
      const filters = { a: "b", x: "z" };
      const params = { filters };

      function subject(state) { return selectors.isCollectionKnown(state, filters); }

      it('returns false if there is no index', () => {
        expect(subject(emptyIndex)).toBe(false);
      });

      it('returns false if the index does not have a matching sequence', () => {
        const index = indexAddQueryResults(emptyIndex, emptyParams, ["6", "286", "25"]);
        const state = mkState(index);
        expect(subject(state)).toBe(false);
      });

      it('returns true if the index has a matching sequence and the resources are cached', () => {
        const index = indexAddQueryResults(emptyIndex, params, ["6", "286", "25"]);
        const state = mkState([pikachu, charizard, breloom], index);
        expect(subject(state)).toBe(true);
      });

      it('returns false if the index has a matching sequence but some resources are not cached', () => {
        const index = indexAddQueryResults(emptyIndex, params, ["6", "286", "25"]);
        const state = mkState([pikachu, breloom], index);
        expect(subject(state)).toBe(false);
      });

      it('returns true if the index has a matching sequence but some resources are errored', () => {
        const index = indexAddQueryResults(emptyIndex, params, ["6", "286", "25"]);
        const state = mkState([pikachu, breloom], index, "6");
        expect(subject(state)).toBe(true);
      });

      it('returns true if the index has an error for the sequence', () => {
        const index = indexSetError(emptyIndex, params);
        const state = mkState([], index);
        expect(subject(state)).toBe(true);
      });
    });
  });

  describe('isCollectionErrored selector', () => {
    function mkState(resources, index, errorIds = []) {
      const cache = cacheSetErrors(makeResourceCache(resources), errorIds);
      return { resources: { pokemon: { index, cache } } };
    }

    describe('when no parameters are passed', () => {
      const params = {};

      function subject(state) { return selectors.isCollectionErrored(state); }

      it('returns false if there is no index', () => {
        expect(subject(emptyState)).toBe(false);
      });

      it('returns false if the index does not have a sequence for empty params', () => {
        const index = indexAddQueryResults(emptyIndex, { foo: "bar" }, ["6", "286", "25"]);
        const state = mkState(index);
        expect(subject(state)).toBe(false);
      });

      it('returns false if the index has a sequence for empty params and the resources are cached', () => {
        const index = indexAddQueryResults(emptyIndex, params, ["6", "286", "25"]);
        const state = mkState([pikachu, charizard, breloom], index);
        expect(subject(state)).toBe(false);
      });

      it('returns false if the index has a sequence for empty params but some resources are not cached', () => {
        const index = indexAddQueryResults(emptyIndex, params, ["6", "286", "25"]);
        const state = mkState([pikachu, breloom], index);
        expect(subject(state)).toBe(false);
      });

      it('returns true if the index has a matching sequence but some resources are errored', () => {
        const index = indexAddQueryResults(emptyIndex, params, ["6", "286", "25"]);
        const state = mkState([pikachu, breloom], index, "6");
        expect(subject(state)).toBe(true);
      });

      it('returns true if the index has an error for the sequence', () => {
        const index = indexSetError(emptyIndex, params);
        const state = mkState([], index);
        expect(subject(state)).toBe(true);
      });
    });

    describe('when parameters are passed', () => {
      const filters = { a: "b", x: "z" };
      const params = { filters };

      function subject(state) { return selectors.isCollectionErrored(state, filters); }

      it('returns false if there is no index', () => {
        expect(subject(emptyState)).toBe(false);
      });

      it('returns false if the index does not have a matching sequence', () => {
        const index = indexAddQueryResults(emptyIndex, emptyParams, ["6", "286", "25"]);
        const state = mkState(index);
        expect(subject(state)).toBe(false);
      });

      it('returns false if the index has a matching sequence and the resources are cached', () => {
        const index = indexAddQueryResults(emptyIndex, params, ["6", "286", "25"]);
        const state = mkState([pikachu, charizard, breloom], index);
        expect(subject(state)).toBe(false);
      });

      it('returns false if the index has a matching sequence but some resources are not cached', () => {
        const index = indexAddQueryResults(emptyIndex, params, ["6", "286", "25"]);
        const state = mkState([pikachu, breloom], index);
        expect(subject(state)).toBe(false);
      });

      it('returns true if the index has a matching sequence but some resources are errored', () => {
        const index = indexAddQueryResults(emptyIndex, params, ["6", "286", "25"]);
        const state = mkState([pikachu, breloom], index, "6");
        expect(subject(state)).toBe(true);
      });

      it('returns true if the index has an error for the sequence', () => {
        const index = indexSetError(emptyIndex, params);
        const state = mkState([], index);
        expect(subject(state)).toBe(true);
      });
    });
  });

  describe('isFetching selector', () => {
    function mkState(flag) { return { resources: { pokemon: { fetching: flag } } }; }

    it('returns true if fetching flag is set to true', () => {
      expect(selectors.isFetching(mkState(true))).toBe(true);
    });

    it('returns false if fetching flag is set to false', () => {
      expect(selectors.isFetching(mkState(false))).toBe(false);
    });

    it('returns false if fetching flag is not set', () => {
      expect(selectors.isFetching(emptyIndex)).toBe(false);
    });
  });

  describe('creation status selectors', () => {
    function mkState(status) {
      return { resources: { pokemon: { processes: { create: {
        "unrelated-pid": { status: "running" },
        "this-pid": { status },
      } } } } };
    }

    describe('isCreating selector', () => {
      it('returns true if status is running', () => {
        expect(selectors.isCreating(mkState('running'), 'this-pid')).toBe(true);
      });

      it('returns false if status is unstarted', () => {
        expect(selectors.isCreating(mkState('unstarted'), 'this-pid')).toBe(false);
      });

      it('returns false if status is errored', () => {
        expect(selectors.isCreating(mkState('errored'), 'this-pid')).toBe(false);
      });

      it('returns false if status is completed', () => {
        expect(selectors.isCreating(mkState('completed'), 'this-pid')).toBe(false);
      });

      it('returns false if status is not set', () => {
        expect(selectors.isCreating(emptyIndex, 'this-pid')).toBe(false);
      });
    });

    describe('isDoneCreating selector', () => {
      it('returns false if status is running', () => {
        expect(selectors.isDoneCreating(mkState('running'), 'this-pid')).toBe(false);
      });

      it('returns false if status is unstarted', () => {
        expect(selectors.isDoneCreating(mkState('unstarted'), 'this-pid')).toBe(false);
      });

      it('returns false if status is errored', () => {
        expect(selectors.isDoneCreating(mkState('errored'), 'this-pid')).toBe(false);
      });

      it('returns true if status is completed', () => {
        expect(selectors.isDoneCreating(mkState('completed'), 'this-pid')).toBe(true);
      });

      it('returns false if status is not set', () => {
        expect(selectors.isDoneCreating(emptyIndex, 'this-pid')).toBe(false);
      });
    });

    describe('getCreationStatus selector', () => {
      it('returns "running" if status is running', () => {
        expect(selectors.getCreationStatus(mkState('running'), 'this-pid')).toBe("running");
      });

      it('returns "unstarted" if status is unstarted', () => {
        expect(selectors.getCreationStatus(mkState('unstarted'), 'this-pid')).toBe("unstarted");
      });

      it('returns "errored" if status is errored', () => {
        expect(selectors.getCreationStatus(mkState('errored'), 'this-pid')).toBe("errored");
      });

      it('returns "completed" if status is completed', () => {
        expect(selectors.getCreationStatus(mkState('completed'), 'this-pid')).toBe("completed");
      });

      it('returns "unstarted" if status is not set', () => {
        expect(selectors.getCreationStatus(emptyIndex, 'this-pid')).toBe("unstarted");
      });
    });

    describe('getCreationResult selector', () => {
      it('returns the latest result if available', () => {
        const state = { resources: { pokemon: { processes: { create: {
          "this-pid": { status: "completed", result: { id: "5", name: "Magneton" } },
        } } } } };

        expect(selectors.getCreationResult(state, 'this-pid')).toEqual({ id: "5", name: "Magneton" });
      });

      it('returns null if result is not available', () => {
        expect(selectors.getCreationResult(emptyState, 'this-pid')).toEqual(null);
      });
    });
  });

  describe('update status selectors', () => {
    function mkState(status) {
      return { resources: { pokemon: { processes: { update: {
        "unrelated-pid": { status: "running" },
        "this-pid": { status },
      } } } } };
    }

    describe('isUpdating selector', () => {
      it('returns true if status is running', () => {
        expect(selectors.isUpdating(mkState('running'), 'this-pid')).toBe(true);
      });

      it('returns false if status is unstarted', () => {
        expect(selectors.isUpdating(mkState('unstarted'), 'this-pid')).toBe(false);
      });

      it('returns false if status is errored', () => {
        expect(selectors.isUpdating(mkState('errored'), 'this-pid')).toBe(false);
      });

      it('returns false if status is completed', () => {
        expect(selectors.isUpdating(mkState('completed'), 'this-pid')).toBe(false);
      });

      it('returns false if status is not set', () => {
        expect(selectors.isUpdating(emptyIndex, 'this-pid')).toBe(false);
      });
    });

    describe('isDoneUpdating selector', () => {
      it('returns false if status is running', () => {
        expect(selectors.isDoneUpdating(mkState('running'), 'this-pid')).toBe(false);
      });

      it('returns false if status is unstarted', () => {
        expect(selectors.isDoneUpdating(mkState('unstarted'), 'this-pid')).toBe(false);
      });

      it('returns false if status is errored', () => {
        expect(selectors.isDoneUpdating(mkState('errored'), 'this-pid')).toBe(false);
      });

      it('returns true if status is completed', () => {
        expect(selectors.isDoneUpdating(mkState('completed'), 'this-pid')).toBe(true);
      });

      it('returns false if status is not set', () => {
        expect(selectors.isDoneUpdating(emptyIndex, 'this-pid')).toBe(false);
      });
    });

    describe('getUpdateStatus selector', () => {
      it('returns "running" if status is running', () => {
        expect(selectors.getUpdateStatus(mkState('running'), 'this-pid')).toBe("running");
      });

      it('returns "unstarted" if status is unstarted', () => {
        expect(selectors.getUpdateStatus(mkState('unstarted'), 'this-pid')).toBe("unstarted");
      });

      it('returns "errored" if status is errored', () => {
        expect(selectors.getUpdateStatus(mkState('errored'), 'this-pid')).toBe("errored");
      });

      it('returns "completed" if status is completed', () => {
        expect(selectors.getUpdateStatus(mkState('completed'), 'this-pid')).toBe("completed");
      });

      it('returns "unstarted" if status is not set', () => {
        expect(selectors.getUpdateStatus(emptyIndex, 'this-pid')).toBe("unstarted");
      });
    });
  });

  describe('destroy status selectors', () => {
    function mkState(status) {
      return { resources: { pokemon: { processes: { destroy: {
        "unrelated-pid": { status: "running" },
        "this-pid": { status },
      } } } } };
    }

    describe('isDestroying selector', () => {
      it('returns true if status is running', () => {
        expect(selectors.isDestroying(mkState('running'), 'this-pid')).toBe(true);
      });

      it('returns false if status is unstarted', () => {
        expect(selectors.isDestroying(mkState('unstarted'), 'this-pid')).toBe(false);
      });

      it('returns false if status is errored', () => {
        expect(selectors.isDestroying(mkState('errored'), 'this-pid')).toBe(false);
      });

      it('returns false if status is completed', () => {
        expect(selectors.isDestroying(mkState('completed'), 'this-pid')).toBe(false);
      });

      it('returns false if status is not set', () => {
        expect(selectors.isDestroying(emptyIndex, 'this-pid')).toBe(false);
      });
    });

    describe('isDoneDestroying selector', () => {
      it('returns false if status is running', () => {
        expect(selectors.isDoneDestroying(mkState('running'), 'this-pid')).toBe(false);
      });

      it('returns false if status is unstarted', () => {
        expect(selectors.isDoneDestroying(mkState('unstarted'), 'this-pid')).toBe(false);
      });

      it('returns false if status is errored', () => {
        expect(selectors.isDoneDestroying(mkState('errored'), 'this-pid')).toBe(false);
      });

      it('returns true if status is completed', () => {
        expect(selectors.isDoneDestroying(mkState('completed'), 'this-pid')).toBe(true);
      });

      it('returns false if status is not set', () => {
        expect(selectors.isDoneDestroying(emptyIndex, 'this-pid')).toBe(false);
      });
    });

    describe('getDestroyStatus selector', () => {
      it('returns "running" if status is running', () => {
        expect(selectors.getDestroyStatus(mkState('running'), 'this-pid')).toBe("running");
      });

      it('returns "unstarted" if status is unstarted', () => {
        expect(selectors.getDestroyStatus(mkState('unstarted'), 'this-pid')).toBe("unstarted");
      });

      it('returns "errored" if status is errored', () => {
        expect(selectors.getDestroyStatus(mkState('errored'), 'this-pid')).toBe("errored");
      });

      it('returns "completed" if status is completed', () => {
        expect(selectors.getDestroyStatus(mkState('completed'), 'this-pid')).toBe("completed");
      });

      it('returns "unstarted" if status is not set', () => {
        expect(selectors.getDestroyStatus(emptyIndex, 'this-pid')).toBe("unstarted");
      });
    });
  });

  describe('individual SASC actions', () => {
    describe('status selectors', () => {
      function mkState(status) {
        return { resources: { pokemon: { processes: { tackle: {
          "unrelated-pid": { status: "running" },
          "this-pid": { status },
        } } } } };
      }

      describe('isXRunning selector', () => {
        it('returns true if status is running', () => {
          expect(selectors.isTackleRunning(mkState('running'), 'this-pid')).toBe(true);
        });

        it('returns false if status is unstarted', () => {
          expect(selectors.isTackleRunning(mkState('unstarted'), 'this-pid')).toBe(false);
        });

        it('returns false if status is errored', () => {
          expect(selectors.isTackleRunning(mkState('errored'), 'this-pid')).toBe(false);
        });

        it('returns false if status is completed', () => {
          expect(selectors.isTackleRunning(mkState('completed'), 'this-pid')).toBe(false);
        });

        it('returns false if status is not set', () => {
          expect(selectors.isTackleRunning(emptyIndex, 'this-pid')).toBe(false);
        });
      });

      describe('isXDone selector', () => {
        it('returns false if status is running', () => {
          expect(selectors.isTackleDone(mkState('running'), 'this-pid')).toBe(false);
        });

        it('returns false if status is unstarted', () => {
          expect(selectors.isTackleDone(mkState('unstarted'), 'this-pid')).toBe(false);
        });

        it('returns false if status is errored', () => {
          expect(selectors.isTackleDone(mkState('errored'), 'this-pid')).toBe(false);
        });

        it('returns true if status is completed', () => {
          expect(selectors.isTackleDone(mkState('completed'), 'this-pid')).toBe(true);
        });

        it('returns false if status is not set', () => {
          expect(selectors.isTackleDone(emptyIndex, 'this-pid')).toBe(false);
        });
      });

      describe('getXStatus selector', () => {
        it('returns "running" if status is running', () => {
          expect(selectors.getTackleStatus(mkState('running'), 'this-pid')).toBe("running");
        });

        it('returns "unstarted" if status is unstarted', () => {
          expect(selectors.getTackleStatus(mkState('unstarted'), 'this-pid')).toBe("unstarted");
        });

        it('returns "errored" if status is errored', () => {
          expect(selectors.getTackleStatus(mkState('errored'), 'this-pid')).toBe("errored");
        });

        it('returns "completed" if status is completed', () => {
          expect(selectors.getTackleStatus(mkState('completed'), 'this-pid')).toBe("completed");
        });

        it('returns "unstarted" if status is not set', () => {
          expect(selectors.getTackleStatus(emptyIndex, 'this-pid')).toBe("unstarted");
        });
      });
    });

    describe('getXResult selector', () => {
      it('returns the latest result if available', () => {
        const state = { resources: { pokemon: { processes: { tackle: {
          "this-pid": { status: "completed", result: { a: 123, b: 456 } },
        } } } } };

        expect(selectors.getTackleResult(state, 'this-pid')).toEqual({ a: 123, b: 456 });
      });

      it('returns null if result is not available', () => {
        expect(selectors.getTackleResult(emptyState, 'this-pid')).toEqual(null);
      });
    });
  });

  describe('collection SASC actions', () => {
    describe('status selectors', () => {
      function mkState(status) {
        return { resources: { pokemon: { processes: { collectBadges: {
          "unrelated-pid": { status: "running" },
          "this-pid": { status },
        } } } } };
      }

      describe('isXRunning selector', () => {
        it('returns true if status is running', () => {
          expect(selectors.isCollectBadgesRunning(mkState('running'), 'this-pid')).toBe(true);
        });

        it('returns false if status is unstarted', () => {
          expect(selectors.isCollectBadgesRunning(mkState('unstarted'), 'this-pid')).toBe(false);
        });

        it('returns false if status is errored', () => {
          expect(selectors.isCollectBadgesRunning(mkState('errored'), 'this-pid')).toBe(false);
        });

        it('returns false if status is completed', () => {
          expect(selectors.isCollectBadgesRunning(mkState('completed'), 'this-pid')).toBe(false);
        });

        it('returns false if status is not set', () => {
          expect(selectors.isCollectBadgesRunning(emptyIndex, 'this-pid')).toBe(false);
        });
      });

      describe('isXDone selector', () => {
        it('returns false if status is running', () => {
          expect(selectors.isCollectBadgesDone(mkState('running'), 'this-pid')).toBe(false);
        });

        it('returns false if status is unstarted', () => {
          expect(selectors.isCollectBadgesDone(mkState('unstarted'), 'this-pid')).toBe(false);
        });

        it('returns false if status is errored', () => {
          expect(selectors.isCollectBadgesDone(mkState('errored'), 'this-pid')).toBe(false);
        });

        it('returns true if status is completed', () => {
          expect(selectors.isCollectBadgesDone(mkState('completed'), 'this-pid')).toBe(true);
        });

        it('returns false if status is not set', () => {
          expect(selectors.isCollectBadgesDone(emptyIndex, 'this-pid')).toBe(false);
        });
      });

      describe('getXStatus selector', () => {
        it('returns "running" if status is running', () => {
          expect(selectors.getCollectBadgesStatus(mkState('running'), 'this-pid')).toBe("running");
        });

        it('returns "unstarted" if status is unstarted', () => {
          expect(selectors.getCollectBadgesStatus(mkState('unstarted'), 'this-pid')).toBe("unstarted");
        });

        it('returns "errored" if status is errored', () => {
          expect(selectors.getCollectBadgesStatus(mkState('errored'), 'this-pid')).toBe("errored");
        });

        it('returns "completed" if status is completed', () => {
          expect(selectors.getCollectBadgesStatus(mkState('completed'), 'this-pid')).toBe("completed");
        });

        it('returns "unstarted" if status is not set', () => {
          expect(selectors.getCollectBadgesStatus(emptyIndex, 'this-pid')).toBe("unstarted");
        });
      });
    });

    describe('getXResult selector', () => {
      it('returns the latest result if available', () => {
        const state = { resources: { pokemon: { processes: { collectBadges: {
          "this-pid": { status: "completed", result: { a: 123, b: 456 } },
        } } } } };

        expect(selectors.getCollectBadgesResult(state, 'this-pid')).toEqual({ a: 123, b: 456 });
      });

      it('returns null if result is not available', () => {
        expect(selectors.getCollectBadgesResult(emptyState, 'this-pid')).toEqual(null);
      });
    });
  });

  describe('resource retrieval', () => {
    const resources = [pikachu, charizard, breloom];

    const loadedState = buildResourceState(resources);

    const errorCache = cacheSetError(loadedState.resources.pokemon.cache, "99");
    const cacheErrorState = { resources: { pokemon: { ...loadedState.resources.pokemon, cache: errorCache } } };

    describe('getMany selector with no filter', () => {
      it('retrieves resources if index is present', () => {
        const results = selectors.getMany(loadedState);
        expect(results).toEqual(resources);
      });

      it('on missing index, throws a CacheMissException to fetch with no filters', () => {
        const ex = trappedSelectors.getMany(emptyState);
        expect(ex).toBeInstanceOf(CacheMissException);
        expect(ex.action).toEqual(actionGroup.fetchCollection(emptyParams));
        expect(ex.default).toEqual([]);
      });
    });

    describe('getMany selector with ids filter', () => {
      it('retrieves resources in id filter order if it gets a total hit', () => {
        const results = selectors.getMany(loadedState, { id: ["286", "6"] });
        expect(results).toEqual([breloom, charizard]);
      });

      it('on empty cache, throws a CacheMissException to fetch all given ids', () => {
        const ex = trappedSelectors.getMany(emptyState, { id: ["6", "286"] });
        expect(ex).toBeInstanceOf(CacheMissException);
        expect(ex.action).toEqual(actionGroup.fetchCollection({ filters: { id: ["6", "286"] } }));
        expect(ex.default).toEqual([]);
      });

      it('with total miss on cache, throws a CacheMissException to fetch all given ids', () => {
        const ex = trappedSelectors.getMany(loadedState, { id: ["9", "123"] });
        expect(ex).toBeInstanceOf(CacheMissException);
        expect(ex.action).toEqual(actionGroup.fetchCollection({ filters: { id: ["9", "123"] } }));
        expect(ex.default).toEqual([]);
      });

      it('with partial match on cache, throws a CacheMissException to fetch only missing non-errored ids', () => {
        const ex = trappedSelectors.getMany(loadedState, { id: ["6", "7", "25", "123"] });
        expect(ex).toBeInstanceOf(CacheMissException);
        expect(ex.action).toEqual(actionGroup.fetchCollection({ filters: { id: ["7", "123"] } }));
        expect(ex.default).toEqual([]);
      });

      it('with any errors in match on cache, returns an empty array', () => {
        const results = trappedSelectors.getMany(cacheErrorState, { id: ["6", "99", "7", "25", "123"] });
        expect(results).toEqual([]);
      });
    });

    describe('getManyFromRelationship', () => {
      it('retrieves resources of correct type in correct order based on has-many relationship', () => {
        const originResource = {
          type: 'trainer',
          id: '1',
          relationships: { pets: { data: [
            { type: 'pokemon', id: '25' },
            { type: 'cats', id: '2' },
            { type: 'pokemon', id: '6' },
          ] } },
        };
        const results = selectors.getManyFromRelationship(loadedState, originResource, 'pets');
        expect(results).toEqual([pikachu, charizard]);
      });

      it('retrieves resource based on a has-one relationship', () => {
        const originResource = {
          type: 'trainer',
          id: '1',
          relationships: { pet: { data: { type: 'pokemon', id: '6' } } },
        };
        const results = selectors.getManyFromRelationship(loadedState, originResource, 'pet');
        expect(results).toEqual([charizard]);
      });

      it('with partial match on cache throws a CacheMissException to fetch only missing ids', () => {
        const originResource = {
          type: 'trainer',
          id: '1',
          relationships: { pets: { data: [
            { type: 'pokemon', id: '6' },
            { type: 'cats', id: '2' },
            { type: 'pokemon', id: '99' },
          ] } },
        };
        const ex = trappedSelectors.getManyFromRelationship(loadedState, originResource, 'pets');
        expect(ex).toBeInstanceOf(CacheMissException);
        expect(ex.action).toEqual(actionGroup.fetchCollection({ filters: { id: ["99"] } }));
        expect(ex.default).toEqual([]);
      });
    });

    // TODO Test getOneFromRelationship

    describe('getOneBy', () => {
      it('retrieves resources based on non-id attribute', () => {
        const result = selectors.getOneBy(loadedState, "pokeType", "Electric");
        expect(result).toEqual(pikachu);
      });

      it('retrieves resources based on id with stringification', () => {
        const result = selectors.getOneBy(loadedState, "id", "286");
        expect(result).toEqual(breloom);
      });

      it('on cache miss for non-id attributes throws a CacheMissException to fetch all resources', () => {
        const ex = trappedSelectors.getOneBy(loadedState, "pokeType", "Dragon");
        expect(ex).toBeInstanceOf(CacheMissException);
        expect(ex.action).toEqual(actionGroup.fetchCollection(emptyParams));
        expect(ex.default).toBe(null);
      });

      it('on cache miss for id throws a CacheMissException to fetch a single resource', () => {
        const ex = trappedSelectors.getOneBy(loadedState, "id", "55");
        expect(ex).toBeInstanceOf(CacheMissException);
        expect(ex.action).toEqual(actionGroup.fetchIndividual({ id: "55" }));
        expect(ex.default).toBe(null);
      });

      it('returns null if resource is errored on lookup for id', () => {
        const result = selectors.getOneBy(cacheErrorState, "id", "99");
        expect(result).toBe(null);
      });
    });

    describe('getOne', () => {
      it('retrieves resources based on id with stringification', () => {
        const result = selectors.getOne(loadedState, "286");
        expect(result).toEqual(breloom);
      });

      it('on cache miss throws a CacheMissException to fetch a single resource', () => {
        const ex = trappedSelectors.getOne(loadedState, "55");
        expect(ex).toBeInstanceOf(CacheMissException);
        expect(ex.action).toEqual(actionGroup.fetchIndividual({ id: "55" }));
        expect(ex.default).toEqual(null);
      });

      it('returns null if resource is errored', () => {
        const result = selectors.getOne(cacheErrorState, "99");
        expect(result).toBe(null);
      });
    });
  });
});
