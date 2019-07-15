import makeResourceSelectors from 'lib/resourceLib/resourceSelectors';
import makeResourceActionGroup from 'lib/resourceLib/resourceActions';
import makeResourceReducer from 'lib/resourceLib/resourceReducers';

import { buildResourceState } from '../../support/resources';
import testAllActionChanges from '../../support/testAllActionChanges';

describe("resourceLib test utilities", () => {
  describe("buildResourceState", () => {
    const options = { fetchIndividual: true, fetchCollection: true };
    const actions = makeResourceActionGroup('cats', options);
    const reducer = makeResourceReducer(actions, options);
    const selectors = makeResourceSelectors('cats', actions, options);

    const origState = { foo: "bar" };
    let updatedState;

    const cats = [
      { id: "1", type: "cats", breed: "Tabby" },
      { id: "2", type: "cats", breed: "Maine Coon" },
      { id: "3", type: "cats", breed: "Siamese" },
    ];

    beforeEach(() => {
      spyOn(Date, 'now').and.callFake(() => { return new Date(2017, 8, 1); } ); // needs to be before the next line even though only tested in the last test in this block
      updatedState = { ...origState, ...buildResourceState(cats) };
    });

    it("adds a resources key to the state", () => {
      expect(updatedState.resources).toBeTruthy();
    });

    it("makes resources available to getMany", () => {
      expect(selectors.getMany(updatedState)).toEqual(cats);
    });

    it("makes resources available to getOne", () => {
      expect(selectors.getOne(updatedState, "2")).toEqual(cats[1]);
    });

    it("creates the same state as the real reducer", () => {
      const action = actions.fetchCollectionSucceeded(cats, { originalAction: actions.fetchCollection({}) });
      const reducedResState = { cats: reducer({}, action) };
      expect(updatedState).toEqual({ ...origState, resources: reducedResState });
    });
  });

  describe("testAllActionChanges", () => {
    const origState = {
      a: "apple",
      b: "banana",
    };

    const testSelectors = {
      getA: jest.fn().mockImplementation((state) => state.a),
      getB: jest.fn().mockImplementation((state) => state.b),
    };

    const testActions = {
      almondize: { type: "changeA", payload: "almond" },
      brazilify: { type: "changeB", payload: "brazil nut" },
      anotherAction: { type: "fortytwo" },
    };

    const testReducer = jest.fn().mockImplementation((state, action) => {
      switch(action.type) {
      case "changeA": return { ...state, a: action.payload };
      case "changeB": return { ...state, b: action.payload };
      default: return state;
      }
    });

    testAllActionChanges(testReducer, origState, testActions, testSelectors, {
      noAction: { getA: "apple", getB: "banana" },
      almondize: { getA: "almond" },
      brazilify: { getB: "brazil nut" },
      anotherAction: {},
    });

    it("created tests which exercised the reducer and selectors", () => {
      expect(testSelectors.getA.mock.calls).toEqual([
        [{ a: "apple", b: "banana" }],
        [{ a: "almond", b: "banana" }],
        [{ a: "apple", b: "brazil nut" }],
        [{ a: "apple", b: "banana" }],
      ]);
      expect(testSelectors.getB.mock.calls).toEqual([
        [{ a: "apple", b: "banana" }],
        [{ a: "almond", b: "banana" }],
        [{ a: "apple", b: "brazil nut" }],
        [{ a: "apple", b: "banana" }],
      ]);
      expect(testReducer.mock.calls).toEqual([
        [origState, testActions.almondize],
        [origState, testActions.brazilify],
        [origState, testActions.anotherAction],
      ]);
    });
  });
});
