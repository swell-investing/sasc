import { delay } from 'redux-saga';
import { all, race, put, fork, take, call, select } from 'redux-saga/effects';
import { browserHistory } from 'react-router';
import { get, startsWith, endsWith } from 'lodash';
import { buffers, channel } from "redux-saga";

import { isValidCacheMissException } from 'lib/resourceLib';
import { DEFAULT_PID } from 'lib/resourceLib';

//.## Saga helpers

export function * takeFirst(pattern, saga, ...args) {
  const listening = true;
  const task = yield fork(function * () {
    while(listening) {
      const action = yield take(pattern);
      yield call(saga, ...args.concat(action));
    }
  });
  return task;
}

// Based on https://medium.freecodecamp.org/how-to-use-a-concurrent-task-queue-in-your-redux-sagas-39e598c4fcae
export function * takeSequentially(pattern, saga, ...args) {
  const workerChannel = yield call(channel, buffers.expanding());

  // create a worker "thread"
  yield fork(function * () {
    while (true) {
      const action = yield take(workerChannel);
      yield call(saga, ...args.concat(action));
    }
  });

  while (true) {
    const action = yield take(pattern);
    yield fork(function * () { yield put(workerChannel, action); });
  }
}

export function * leadingThrottle(timeout, pattern, saga, ...args) {
  const listening = true;
  while (listening) {
    const action = yield take(pattern);

    yield fork(saga, ...args.concat(action));

    yield call(delay, timeout);
  }
}

export function redirectIfServerError(apiError, history = browserHistory) {
  if (500 <= apiError.status && apiError.status <= 599) {
    history.push('/500');
  }
}

//% runResourceProcess(action)
//. Given an action that would start a resourceLib process, dispatches the action and waits for the process to finish.
//.
//. * `action`: A process-starting action, e.g. `resActions.create(...)`
//.
//. This is an effect generator. Use this in your sagas with `yield diligentSelect(selector, ...args)`.  When yielded to
//. redux-saga, the effect returns the process success action's `payload`.  If the process fails, the failure action
//. will be thrown as an exception.
//.
//. ```javascript
//. import { runResourceProcess } from 'sagas/helpers';
//. import { dogActions } from 'resources';
//.
//. function * createPuppySaga(_action) {
//.   const creationAction = userActions.create({type: 'dogs', name: 'Buddy'});
//.   const result = yield runResourceProcess(creationAction);
//.   const newPuppyId = result.id;
//. }
//. ```
//.
//. You can also use `runResourceProcess` with a fetch action, but only if the action has the `ignoreCache` option
//. enabled. This will force resources to be refetched, ignoring any cached values.
//.
//. ```javascript
//. import { runResourceProcess } from 'sagas/helpers';
//. import { dogSelectors } from 'resources';
//.
//. function * announcePuppySaga(_action) {
//.   const fetchAction = userActions.fetchIndividual({ ignoreCache: true, id: "123" });
//.   const result = yield runResourceProcess(fetchAction);
//.   yield put({ type: "PUPPY_INFO", payload: `Our latest reports indicate a cute puppy named ${result.name}` });
//. }
//. ```
//.
//. If you don't want to enable `ignoreCache`, then you should use `diligentSelect` instead of `runResourceProcess`.
export function runResourceProcess(action) {
  if (!startsWith(action.type, "RSRC_")) { throw new Error("Invalid process action, use e.g. resActions.create()"); }
  if (endsWith(action.type, "_INITIATED")) { throw new Error("Use e.g. resActions.create(), not createInitiated()"); }
  if (action.type.includes("_FETCH_") && !get(action, ['payload', 'ignoreCache'])) {
    throw new Error("Fetch actions must have ignoreCache to use runResourceProcess");
  }

  return call(runResourceProcessGenerator, action);
}

function * runResourceProcessGenerator(action) {
  const pid = get(action, ['meta', 'pid'], DEFAULT_PID);
  const isFetching = action.type.includes("_FETCH_");

  const isProcessCompletedFn = (suffix) => {
    const expectedType = action.type + "_" + suffix;

    if (isFetching) {
      return (checkedAction) => (
        checkedAction.type == expectedType &&
        get(checkedAction, ['meta', 'originalAction']) == action
      );
    } else {
      return (checkedAction) => (
        checkedAction.type == expectedType &&
        get(checkedAction, ['meta', 'originalAction', 'meta', 'pid'], DEFAULT_PID) == pid
      );
    }
  };

  // This pattern prevents a quickly-resolving process from emitting its final action before we set up our take
  const [takenAction, _] = yield all([
    race({
      result: take(isProcessCompletedFn("SUCCEEDED")),
      failure: take(isProcessCompletedFn("FAILED")),
    }),
    put(action),
  ]);

  if(takenAction.result) {
    return takenAction.result.payload;
  } else {
    throw takenAction.failure;
  }
}

//% diligentSelect(selector, ...args)
//. An effect similar to react-redux's `select`, but which fetches missing SASC resources as necessary before retuning.
//.
//. * `selector`: The selector function to be called
//. * `...args`: Any other arguments to pass to the selector, after the state
//.
//. This is an effect generator. Use this in your sagas with `yield diligentSelect(selector, ...args)`. When yielded to
//. redux-saga, the effect returns the result from the selector.
//.
//. `diligentSelect` knows that it needs to fetch a missing resource if the selector throws a `CacheMissException`.
//. This could even happen several times in a row, e.g. if you are running a custom selector that uses several
//. different types of resources to calculate its result. However, after 10 `CacheMissException`s in a row,
//. `diligentSelect` will assume something has gone wrong and rethrow the final `CacheMissException`.
//.
//. To refetch a resource even if it is already cached, use `runResourceProcess` on a fetch action with `ignoreCache`.
//. See the `runResourceProcess` documentation above for an example.
//.
//. ```javascript
//. import { diligentSelect } from 'sagas/helpers';
//. import { dogSelectors } from 'resources';
//.
//. function * getCorgiSaga(_action) {
//.   const shortDog = yield diligentSelect(dogSelectors.getOneBy, 'breed', 'Welsh Corgi');
//. }
//. ```
export function diligentSelect(...args) {
  return call(diligentSelectionGenerator, ...args);
}

function * diligentSelectionGenerator(selector, ...selectorArgs) {
  for (let i = 0; i < 10; ++i) {
    try {
      return yield select(selector, ...selectorArgs);
    } catch (ex) {
      if (!isValidCacheMissException(ex)) { throw ex; }

      yield all([
        race({
          success: take(ex.action.type + "_SUCCEEDED"),
          failure: take(ex.action.type + "_FAILED"),
          timeout: delay((i+1) * 500),
        }),
        put(ex.action),
      ]);
    }
  }

  throw new Error("Unable to resolve selector in a reasonable number of attempts");
}
