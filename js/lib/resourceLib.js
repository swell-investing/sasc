import { difference, flatMap, keys, some, values } from 'lodash';
import { combineReducers } from 'redux';
import { camelCaseName } from 'lib/resourceLib/resourceNames';
import makeResourceHttpClient from 'lib/resourceLib/resourceHttpClient';
import makeResourceSelectors from 'lib/resourceLib/resourceSelectors';
import makeResourceSagas from 'lib/resourceLib/resourceSagas';
import makeResourceReducer from 'lib/resourceLib/resourceReducers';
import makeResourceActionGroup from 'lib/resourceLib/resourceActions';

export {
  CacheMissException,
  cacheMissOverrideDefault,
  isValidCacheMissException,
  selectorWithDefault,
} from 'lib/resourceLib/resourceSelectors';

//.## ResourceDefinitions
//. When setting up new resource type on the client, the first step is to define your resource in `client/assets/javascripts/resources.js`. This
//. will automatically plug the resource into the Redux lifecycle, and generate the various resource-specific selectors
//. and actions you can use in your own components and sagas.
//.
//. ```javascript
//. const config = new ResourceDefinitions();
//. ```

const DEFAULT_OPTIONS = {
  fetchCollection: true,
  fetchIndividual: true,
  create: false,
  update: false,
  destroy: false,
  customSascActions: {},
  invalidatesCachedTypes: {},
  namespace: undefined,
};

export const STATUS_UNSTARTED = 'unstarted';
export const STATUS_RUNNING = 'running';
export const STATUS_ERRORED = 'errored';
export const STATUS_COMPLETED = 'completed';

export const DEFAULT_PID = 'default-pid';

function isBadName(name) {
  return !name.match(/^[a-z0-9-]+$/);
}

export class ResourceDefinitions {
  constructor(apiVersion) {
    this.apiVersion = apiVersion;

    this.resourceTypes = {};

    this.clients = {};
    this.actionGroups = {};
    this.reducers = {};
    this.sagas = {};
    this.selectors = {};
  }

  //% define(resourceType, options)
  //. Configures a new resource type.
  //.
  //. * `resourceType`: The name of the resource, as a dash-separated lowercase plural string, e.g. `'dog-kennels'`
  //. * `options`: Config options for the resource. Any unspecified options will take on their default value.
  //.
  //. These are the `options` keys you can provide:
  //.
  //. * `fetchCollection`: Flag which enables the `getMany` selectors. (default: `true`)
  //. * `fetchIndividual`: Flag which enables the `getOne` selectors. (default: `true`)
  //. * `create`: Flag with enables the `create` action. (default: `false`)
  //. * `update`: Flag with enables the `update` action. (default: `false`)
  //. * `destroy`: Flag with enables the `destroy` action. (default: `false`)
  //. * `customSascActions`: Object describing custom SASC actions. Keys are dash-separated lowercase strings,
  //. e.g. `run-iditarod`, and value is an object describing the action:
  //.   * `kind`: The type of SASC action. Must be `'individual'` or `'collection'`
  //.   * `invalidation`: Flag which indicates that this action can cause changes in the resource(s), which means that
  //.   cached resource data will need to be refetched after running the action. (default: `false`)
  //.
  //. Returns an array of two objects. The first object has the newly generated [selectors](#resourceselectors), and the
  //. second has the new [actions](#resourceactions).
  //.
  //. In general, you should have only one instance of `ResourceDefinitions`, and you should centralize all your calls
  //. to `define` in one `resources.js` file.
  //.
  //. ```javascript
  //. export const [goodDogSelectors, goodDogActions] = config.define('good-dogs', {
  //.   create: true,
  //.   customSascActions: {
  //.     'eat-doggie-biscuit': { kind: 'individual', invalidation: true },
  //.     'run-iditarod': { kind: 'collection' },
  //.   },
  //. });
  //. ```
  define(resourceType, options = {}) {
    const extraneousOptions = difference(keys(options), keys(DEFAULT_OPTIONS));
    if (extraneousOptions.length) {
      throw new Error(`'${resourceType}' includes extraneous option keys: ${extraneousOptions}`);
    }
    options = { ...DEFAULT_OPTIONS, ...options };

    if (isBadName(resourceType)) {
      throw new Error(`'${resourceType}' is not a valid resource type. Use dash-separated lowercase, e.g 'dog-kennels'`);
    }

    if (some(keys(options.customSascActions), isBadName)) {
      throw new Error(`Custom SASC actions must have dash-separated lowercase names, e.g. 'run-iditarod'`);
    }

    if (options.customSascActions.create) { throw new Error("You cannot name a custom SASC action 'create'"); }
    if (options.customSascActions.update) { throw new Error("You cannot name a custom SASC action 'update'"); }
    if (options.customSascActions.destroy) { throw new Error("You cannot name a custom SASC action 'destroy'"); }

    const client = makeResourceHttpClient(resourceType, this.apiVersion, options);
    this.clients[resourceType] = client;

    const actionGroup = makeResourceActionGroup(resourceType, options);
    this.actionGroups[resourceType] = actionGroup;

    const resourceSelectors = makeResourceSelectors(resourceType, actionGroup, options);
    this.selectors[resourceType] = resourceSelectors;

    const resourceSagas = makeResourceSagas(this, resourceType, client, actionGroup, resourceSelectors, options);
    this.sagas[resourceType] = resourceSagas;

    const resourceReducer = makeResourceReducer(actionGroup, options);
    this.reducers[camelCaseName(resourceType)] = resourceReducer;

    return [resourceSelectors, actionGroup];
  }

  resourceHttpClient(resourceType) {
    return this.clients[resourceType];
  }

  resourceActionGroup(resourceType) {
    return this.actionGroups[resourceType];
  }

  resourceSelectors(resourceType) {
    return this.selectors[resourceType];
  }

  resourceSagas(resourceType) {
    return this.sagas[resourceType];
  }

  getReducers() {
    return { resources: combineReducers(this.reducers) };
  }

  getSagas() {
    return flatMap(this.sagas, values);
  }
}
