import { camelCase } from 'lodash';

// Can't use lodash's snake case function because it gets confused by numerals and other edge cases, since
// it's meant to convert from camel case to snake case. But since we only care about dasherized input (resource
// type names), we can do it much more simply.
function upperSnakeCase(name) { return name.replace(/-/g, "_").toUpperCase(); }

export const shortActionTypeName = upperSnakeCase;

export function fullActionTypeName(resourceType, subName) {
  return upperSnakeCase(`RSRC_${resourceType}_${subName}`);
}

// Exporting this because lodash's camelCase sometimes has weird edge cases, and we may want to use
// a different inflector at some point in the future.
export const camelCaseName = camelCase;
