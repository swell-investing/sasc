import makeResourceHttpClient from 'lib/resourceLib/resourceHttpClient';
import api from 'api';

jest.mock('api', () => ({
  get: jest.fn(),
  post: jest.fn(),
  patch: jest.fn(),
  del: jest.fn(),
}));

describe("makeResourceHttpClient", () => {
  beforeEach(() => {
    for (const key of ['get', 'post', 'patch', 'del']) {
      api[key].mockClear();
    }
  });

  const client = makeResourceHttpClient('dogs', '3.2.1', {
    fetchIndividual: true,
    fetchCollection: true,
    create: true,
    update: true,
    destroy: true,
    customSascActions: {
      'bark': { kind: 'individual' },
      'run-iditarod': { kind: 'collection' },
    },
  });

  const expectedHeaders = {
    'x-sasc': '1.0.0',
    'x-sasc-api-version': '3.2.1',
    'x-sasc-client': `swell-web 1.0.0 ${BUILD_TIMESTAMP}`,
  };

  describe('getIndividual', () => {
    const subject = client.getIndividual;

    it('makes a GET request for a resource with a given id', () => {
      subject(35);
      expect(api.get.mock.calls.length).toEqual(1);
      expect(api.get).toBeCalledWith('/api/dogs/35', { headers: expectedHeaders });
    });
  });

  describe('getCollection', () => {
    const subject = client.getCollection;

    it('makes a GET request for a collection', () => {
      subject();
      expect(api.get.mock.calls.length).toEqual(1);
      expect(api.get).toBeCalledWith('/api/dogs', { query: {}, headers: expectedHeaders });
    });

    it('makes a GET request for a filtered collection', () => {
      subject({ filters: { color: "red", age: 3 } });
      expect(api.get.mock.calls.length).toEqual(1);
      expect(api.get).toBeCalledWith( '/api/dogs', {
        query: { "filter[color]": '"red"', "filter[age]": "3" },
        headers: expectedHeaders,
      });
    });
  });

  describe('create', () => {
    const data = { type: 'dogs', attributes: { name: 'Ozy' } };
    const subject = client.create;

    it('makes a POST request with data for a new resource', () => {
      subject(data);
      expect(api.post.mock.calls.length).toEqual(1);
      expect(api.post).toBeCalledWith('/api/dogs', { data }, { headers: expectedHeaders, useSascTransform: true });
    });
  });

  describe('update', () => {
    const data = { id: "3", type: 'dogs', attributes: { name: 'Ozy' } };
    const subject = client.update;

    it('makes a PATCH request with updated data for the resource the given id', () => {
      subject(data);
      expect(api.patch.mock.calls.length).toEqual(1);
      expect(api.patch).toBeCalledWith('/api/dogs/3', { data }, { headers: expectedHeaders, useSascTransform: true });
    });
  });

  describe('destroy', () => {
    const subject = client.destroy;

    it('makes a DELETE request on the resource at the given id', () => {
      subject("5");
      expect(api.del.mock.calls.length).toEqual(1);
      expect(api.del).toBeCalledWith('/api/dogs/5', { headers: expectedHeaders });
    });
  });

  describe('individual action requester', () => {
    const subject = client.bark;

    it('makes a POST request to the named action with arguments on the given resource', () => {
      subject("81", { foo: "bar" });
      expect(api.post.mock.calls.length).toEqual(1);
      expect(api.post).toBeCalledWith(
        '/api/dogs/81/action/bark',
        { arguments: { foo: "bar" } },
        { headers: expectedHeaders, useSascTransform: true }
      );
    });
  });

  describe('collection action requester', () => {
    const subject = client.runIditarod;

    it('makes a POST request to the named action with arguments', () => {
      subject({ foo: "bar" });
      expect(api.post.mock.calls.length).toEqual(1);
      expect(api.post).toBeCalledWith(
        '/api/dogs/action/run-iditarod',
        { arguments: { foo: "bar" } },
        { headers: expectedHeaders, useSascTransform: true }
      );
    });
  });
});
