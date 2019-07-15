import { some, partial, omit } from 'lodash';
import React from 'react';
import { connect } from 'react-redux';
import PropTypes from 'prop-types';
import { isValidCacheMissException } from 'lib/resourceLib';

class DelayedActions {
  constructor() {
    this.delayedDispatchers = [];
    this.delayedActions = [];
  }

  delayedDispatcher(dispatch) {
    return (action) => {
      // Deduplicate dispatch to any given action within a cycle.
      if (!some(this.delayedActions, action)) {
        this.delayedActions.push(action);
        this.delayedDispatchers.push(partial(dispatch, action));
      }
    };
  }

  flush() {
    for (const delayed of this.delayedDispatchers) { delayed(); }
    this.delayedDispatchers = [];
    this.delayedActions = [];
  }
}

//.## Connecting components
//. When you use resource selectors through the regular `mapStateToProps` function as passed to react-redux's `connect`
//. wrapper, you'll run into trouble with fetching resources. Resource selectors will throw `CacheMissException`s when a
//. server request needs to be made. Without anything to catch and handle them, the exceptions will just rise all the
//. way up and cause an error.
//.
//. So instead of using `connect`, you should use `safeConnect` or `WithResources`. The `safeConnect` wrapper has the
//. same API as `connect`, so it is the simplest way to solve the problem. However, `WithResources` provides more
//. control over how your component renders while resources are loading.

//% WithResources(WrappedComponent, mapSelectorsToProps, mapDispatchToProps = null, options = {})
//. Connects a component to the state, requesting any missing resources requested by selectors.
//.
//. You may want to check out [the documentation for react-redux connect](https://bit.ly/1SdzxK3) as reference for
//. the behavior of this function.
//.
//. * `WrappedComponent`: A React component function or class
//. * `mapSelectorsToProps`: A function that uses a given `select` to request data from the store and supply props. It
//.                          will be called with two arguments: the `select` function, and `ownProps`
//. * `mapDispatchToProps`: A function that maps action dispatchers to props, just the same as the second argument to
//.                         react-redux `connect`
//. * `options`: An object with additional options:
//.   * `mergeProps`: A optional function that will be used to merge ownProps, selectorProps, and dispatchProps,
//.                   just the same as the optional third argument to react-redux `connect`
//.   * `connectOptions`: Additional options, exactly like the options object that `connect` takes as its optional
//.                       fourth argument
//.
//. Of the arguments to `WithResources`, all are exactly equivalent to `connect` arguments, except one:
//. `mapSelectorsToProps`. It is analagous to the `connect` argument `mapStateToProps`, but instead of being given
//. `state`, it is given a `select` function. The `select` function takes a selector as its first argument, calls
//. that selector with `state`, and returns the result. Any additional arguments to `select` are sent as further
//. arguments to the selector:
//.
//. ```javascript
//. // This function for connect...
//. function mapStateToProps(state) {
//.   return {
//.     foo: someSelector(state),
//.     bar: anotherSelector(state, "baz")
//.   };
//. }
//.
//. // Is equivalent to this function for WithResources
//. function mapSelectorsToProps(select) {
//.   return {
//.     foo: select(someSelector),
//.     bar: select(anotherSelector, "baz")
//.   };
//. }
//. ```
//.
//. The reason for all this roundabout is to allow `CacheMissException`s thrown by selectors to be intercepted
//. and correctly handled. If a `CacheMissException` is thrown from the selector, then `select` will issue a request
//. to the server in the background and then return the `default` value from CacheMissException (typically `null`
//. or `[]`, depending on the selector). Later, when the server responds, the cache will be updated and the component
//. will re-build its props, and this time the selector should successfully complete and return the data.
//.
//. A convenience prop `isLoadingResources` is provided as well. It will be `true` when any selector in the most
//. recent call to your `mapSelectorsToProps` threw a `CacheMissException`, i.e. whenever any resource for your
//. component is still being loaded.
//.
//. ```javascript
//. import { WithResources } from 'components/shared/WithResources';
//. import { dogSelectors, dogActions } from 'resources';
//.
//. function MyComponent({ isLoadingResources, dog, bark }) {
//.   if (isLoadingResources) { return <div class="loading">Please wait...</div>; }
//.
//.   return <div>
//.     <p>The dog is named {dog.name}</p>
//.     <button onClick={bark({id: dog.id})}>Bark!</button>
//.   </div>;
//. }
//.
//. function mapSelectorsToProps(select, ownProps) {
//.   return {
//.     dog: dogSelectors.getOne("82")
//.   };
//. }
//.
//. function mapDispatchToProps(dispatch) {
//.   return {
//.     dog: dogActions.bark // "bark" must have been configured by `define` as a custom individual SASC action
//.   };
//. }
//.
//. export default WithResources(MyComponent, mapSelectorsToProps, mapDispatchToProps);
//. ```
export default function WithResources(WrappedComponent, mapSelectorsToProps, wrappedMapDispatchToProps=null, options={}) {
  const connectOptions = options.connectOptions || {};

  const delayedActions = new DelayedActions();
  const deferredActions = new DelayedActions();

  const component = class extends React.Component {
    constructor(props) {
      super(props);
    }
    componentWillMount() {
      delayedActions.flush();
    }
    componentWillUpdate() {
      delayedActions.flush();
      deferredActions.flush();
    }
    componentDidMount() {
      delayedActions.flush();
      deferredActions.flush();
    }
    render() {
      return <WrappedComponent {...this.props.wrappedProps } />;
    }
  };

  function mapStateToProps(state) {
    return { state: state };
  }

  function mapDispatchToProps(dispatch) {
    const delayedDispatch = delayedActions.delayedDispatcher(dispatch);
    const deferredDispatch = deferredActions.delayedDispatcher(dispatch);
    const wrappedDispatchProps = wrappedMapDispatchToProps ? wrappedMapDispatchToProps(dispatch) : {};

    return { wrappedDispatchProps, delayedDispatch, deferredDispatch };
  }

  function mergeProps({ state }, dispatchProps, ownProps) {
    let isLoadingResources = false;
    const handleException = (ex) => {
      if (!isValidCacheMissException(ex)) { throw ex; }
      isLoadingResources = true;
      dispatchProps.delayedDispatch(ex.action);
    };

    const select = (selector, ...args) => {
      try {
        return selector(state, ... args);
      } catch (ex) {
        handleException(ex);
        return ex.default;
      }
    };

    let selectorProps = {};
    try {
      selectorProps = mapSelectorsToProps ? mapSelectorsToProps(select, ownProps) : {};
    } catch (ex) {
      handleException(ex);
    }

    if (options.callSelectorsDeferred) {
      const handleExceptionDeferred = (ex) => {
        if (!isValidCacheMissException(ex)) { throw ex; }
        dispatchProps.deferredDispatch(ex.action);
      };

      const deferredSelect = (selector, ...args) => {
        try {
          return selector(state, ... args);
        } catch (ex) {
          handleExceptionDeferred(ex);
          return ex.default;
        }
      };

      try {
        options.callSelectorsDeferred(deferredSelect, { ...ownProps, ...selectorProps });
      } catch (ex) {
        handleExceptionDeferred(ex);
      }
    }

    let wrappedProps;
    if (options.mergeProps) {
      wrappedProps = options.mergeProps(ownProps, selectorProps, dispatchProps.wrappedDispatchProps);
    } else {
      wrappedProps = { ...ownProps, ...selectorProps, ...dispatchProps.wrappedDispatchProps };
    }
    wrappedProps = { ...wrappedProps, isLoadingResources };

    return { wrappedProps, ...dispatchProps };
  }

  component.propTypes = {
    resources: PropTypes.arrayOf(
      PropTypes.shape({
        id: PropTypes.string.isRequired,
        type: PropTypes.string.isRequired,
      }).isRequired
    ),
  };

  let connectedComponent = connect(mapStateToProps, mapDispatchToProps, mergeProps, connectOptions)(component);

  const wrappedComponentName = WrappedComponent.displayName
  || WrappedComponent.name
  || 'Component';

  connectedComponent.displayName = `WithResources(${wrappedComponentName})`;

  return connectedComponent;
}

function convertToSelectorMapper(mapStateToProps) {
  if (!mapStateToProps) { return null; }

  return (select, ownProps) => {
    const state = select((state) => state);
    return mapStateToProps(state, ownProps);
  };
}

export function NullIfLoading(Component) {
  const wrapped = (props) => {
    if (props.isLoadingResources) return null;
    return (<Component { ...omit(props, 'isLoadingResources') } />);
  };

  wrapped.displayName = Component.displayName || Component.name || 'Component';

  return wrapped;
}

//% safeConnect(mapStateToProps, mapDispatchToProps, mergeProps, connectOptions)
//. This is an adapter on `WithResources`, providing an API identical to the one from [react-redux
//. connect](https://bit.ly/1SdzxK3).
//.
//. This is a quick way to convert a non-SASC component to SASC; just replace `connect` with `safeConnect` and
//. everything should just work. However, unlike `WithResources`, you do not have fine control over how your component
//. renders while resources are being loaded.
//.
//. If any selector in `mapStateToProps` raises a `CacheMissException`, then the entire component will render as `null`.
//. When the resource has finished loading and been inserted into the cache, `mapStateToProps` will be called
//. again to give it another try.
export function safeConnect(mapStateToProps, mapDispatchToProps, mergeProps, connectOptions) {
  return (Component) => {
    const wrapped = WithResources(
      NullIfLoading(Component),
      convertToSelectorMapper(mapStateToProps),
      mapDispatchToProps,
      { mergeProps, connectOptions }
    );

    wrapped.displayName = wrapped.displayName.replace("WithResources", "Connect");

    return wrapped;
  };
}
