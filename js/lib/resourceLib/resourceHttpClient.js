import { fromPairs, map, mapValues, mapKeys, pickBy } from 'lodash';
import { get, post, patch, del } from 'api';

import { camelCaseName } from 'lib/resourceLib/resourceNames';

export default function makeResourceHttpClient(resourceType, apiVersion, options) {
  const namespace = options.namespace ? `${options.namespace}/` : '';
  const baseRoute = `/api/${namespace}${resourceType}`;
  const idRoute = (id) => `${baseRoute}/${id}`;
  const collectionActionRoute = (act) => `${baseRoute}/action/${act}`;
  const individualActionRoute = (id, act) => `${idRoute(id)}/action/${act}`;

  const headers = {
    "x-sasc": "1.0.0",
    "x-sasc-api-version": apiVersion,
    "x-sasc-client": `swell-web 1.0.0 ${BUILD_TIMESTAMP}`,
  };

  function getIndividual(id) {
    return get(idRoute(id), { headers });
  }

  function getCollection({ filters } = {}) {
    const query = fromPairs(map(filters || {}, (v, k) => ["filter[" + k + "]", JSON.stringify(v)] ));
    return get(baseRoute, { query, headers });
  }

  function create(data) {
    return post(baseRoute, { data }, { headers, useSascTransform: true });
  }

  function update(data) {
    const id = data.id;
    if (!id) { throw "Update data must include id"; }
    return patch(idRoute(id), { data }, { headers, useSascTransform: true });
  }

  function destroy(id) {
    return del(idRoute(id), { headers });
  }

  function makeIndividualActionFn(name, config) {
    return (id, args = {}) => request(config.method,
      individualActionRoute(id, name),
      { arguments: args },
      { headers }
    );
  }

  function makeCollectionActionFn(name, config) {
    return (args = {}) => request(config.method,
      collectionActionRoute(name),
      { arguments: args },
      { headers }
    );
  }

  function makeCustomSascActionFns() {
    const fns = mapValues(options.customSascActions, (config, name) => {
      switch (config.kind) {
      case "individual":
        return makeIndividualActionFn(name, config);
      case "collection":
        return makeCollectionActionFn(name, config);
      default:
        throw new Error("Custom SASC action kind must be 'individual' or 'collection'");
      }
    });

    return mapKeys(fns, (_fn, name) => camelCaseName(name));
  }

  function request(method, route, data, headers) {
    switch (method) {
    case "delete": return del(route, headers);
    case "post": return post(route, data, { ...headers, useSascTransform: true });
    case "put": return patch(route, data, { ...headers, useSascTransform: true });
    default: return post(route, data, { ...headers, useSascTransform: true });
    }
  }

  return pickBy({
    getIndividual: options.fetchIndividual && getIndividual,
    getCollection: options.fetchCollection && getCollection,
    create: options.create && create,
    update: options.update && update,
    destroy: options.destroy && destroy,
    ...makeCustomSascActionFns(),
  });
}
