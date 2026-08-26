'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const buildRoutes = require('../src/routes');

test('buildRoutes can be called with no arguments', () => {
  assert.doesNotThrow(() => buildRoutes());
});
