import { ResourceDefinitions } from 'lib/resourceLib';
import { keys, size, sortBy } from 'lodash';

describe("ResourceDefinitions", () => {
  function subject() {
    const config = new ResourceDefinitions;

    const [dogSelectors, dogActions] = config.define('dogs', {
      create: true,
      destroy: true,
      update: true,
      customSascActions: {
        'bark': { kind: 'individual' },
        'run-iditarod': { kind: 'collection' },
      },
    });
    const [_s3ObjectSelectors, _s3ObjectActions] = config.define('s3-objects');

    return { config, dogSelectors, dogActions };
  }

  it('creates necessary action groups, sagas, and selectors', () => {
    const { config, dogSelectors, dogActions } = subject();

    expect(size(config.getSagas())).toEqual(9);

    expect(sortBy(keys(config.resourceHttpClient('dogs')))).toEqual([
      'bark',
      'create',
      'destroy',
      'getCollection',
      'getIndividual',
      'runIditarod',
      'update',
    ]);

    expect(sortBy(keys(config.resourceSagas('dogs')))).toEqual([
      'barkSaga',
      'createSaga',
      'destroySaga',
      'fetchCollectionSaga',
      'fetchIndividualSaga',
      'runIditarodSaga',
      'updateSaga',
    ]);

    expect(config.resourceActionGroup('dogs')).toBe(dogActions);
    expect(dogActions.actionCreators).toHaveLength(31);
    expect(dogActions).toMatchObject({
      "FETCH_COLLECTION": "RSRC_DOGS_FETCH_COLLECTION",
      "FETCH_COLLECTION_INITIATED": "RSRC_DOGS_FETCH_COLLECTION_INITIATED",
      "FETCH_COLLECTION_SUCCEEDED": "RSRC_DOGS_FETCH_COLLECTION_SUCCEEDED",
      "FETCH_COLLECTION_FAILED": "RSRC_DOGS_FETCH_COLLECTION_FAILED",
      "FETCH_INDIVIDUAL": "RSRC_DOGS_FETCH_INDIVIDUAL",
      "FETCH_INDIVIDUAL_INITIATED": "RSRC_DOGS_FETCH_INDIVIDUAL_INITIATED",
      "FETCH_INDIVIDUAL_SUCCEEDED": "RSRC_DOGS_FETCH_INDIVIDUAL_SUCCEEDED",
      "FETCH_INDIVIDUAL_FAILED": "RSRC_DOGS_FETCH_INDIVIDUAL_FAILED",
      "INCLUDED_RESOURCES_RECEIVED": "RSRC_DOGS_INCLUDED_RESOURCES_RECEIVED",
      "RESOURCE_FETCHED": "RSRC_DOGS_RESOURCE_FETCHED",
      "INVALIDATE_CACHE": "RSRC_DOGS_INVALIDATE_CACHE",
      "CREATE": "RSRC_DOGS_CREATE",
      "CREATE_INITIATED": "RSRC_DOGS_CREATE_INITIATED",
      "CREATE_FAILED": "RSRC_DOGS_CREATE_FAILED",
      "CREATE_SUCCEEDED": "RSRC_DOGS_CREATE_SUCCEEDED",
      "DESTROY": "RSRC_DOGS_DESTROY",
      "DESTROY_INITIATED": "RSRC_DOGS_DESTROY_INITIATED",
      "DESTROY_FAILED": "RSRC_DOGS_DESTROY_FAILED",
      "DESTROY_SUCCEEDED": "RSRC_DOGS_DESTROY_SUCCEEDED",
      "UPDATE": "RSRC_DOGS_UPDATE",
      "UPDATE_INITIATED": "RSRC_DOGS_UPDATE_INITIATED",
      "UPDATE_FAILED": "RSRC_DOGS_UPDATE_FAILED",
      "UPDATE_SUCCEEDED": "RSRC_DOGS_UPDATE_SUCCEEDED",
      "BARK": "RSRC_DOGS_BARK",
      "BARK_INITIATED": "RSRC_DOGS_BARK_INITIATED",
      "BARK_FAILED": "RSRC_DOGS_BARK_FAILED",
      "BARK_SUCCEEDED": "RSRC_DOGS_BARK_SUCCEEDED",
      "RUN_IDITAROD": "RSRC_DOGS_RUN_IDITAROD",
      "RUN_IDITAROD_INITIATED": "RSRC_DOGS_RUN_IDITAROD_INITIATED",
      "RUN_IDITAROD_FAILED": "RSRC_DOGS_RUN_IDITAROD_FAILED",
      "RUN_IDITAROD_SUCCEEDED": "RSRC_DOGS_RUN_IDITAROD_SUCCEEDED",
    });

    expect(dogSelectors).toBe(config.resourceSelectors('dogs'));
    expect(sortBy(keys(dogSelectors))).toEqual([
      "getBarkResult",
      "getBarkStatus",
      "getCreationResult",
      "getCreationStatus",
      "getDestroyStatus",
      "getMany",
      "getManyFromRelationship",
      "getOne",
      "getOneBy",
      "getOneFromRelationship",
      "getRunIditarodResult",
      "getRunIditarodStatus",
      "getUpdateStatus",
      "isBarkDone",
      "isBarkRunning",
      "isCollectionErrored",
      "isCollectionKnown",
      "isCreating",
      "isDestroying",
      "isDoneCreating",
      "isDoneDestroying",
      "isDoneUpdating",
      "isFetching",
      "isResourceErrored",
      "isResourceKnown",
      "isRunIditarodDone",
      "isRunIditarodRunning",
      "isUpdating",
    ]);
  });

  it('correctly generates action names for resource types with names containing numbers', () => {
    const { config } = subject();
    const s3ObjectsActionGroup = config.resourceActionGroup('s3-objects');
    expect(s3ObjectsActionGroup).toMatchObject({ "FETCH_COLLECTION": "RSRC_S3_OBJECTS_FETCH_COLLECTION" });
  });
});
