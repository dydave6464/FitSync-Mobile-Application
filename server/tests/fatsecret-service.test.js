'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createFatsecretService } = require('../src/services/fatsecret');

test('defaults to the stub, which searches a fixed list', async () => {
  const fs = createFatsecretService({});
  const found = await fs.search('banana');
  assert.equal(found.length, 1);
  assert.equal(found[0].name, 'Banana');
  assert.equal(typeof found[0].externalId, 'string');
  assert.deepEqual(await fs.search('nothing like this'), []);
});

test('the stub gets by id, or null', async () => {
  const fs = createFatsecretService({ mode: 'stub' });
  const [banana] = await fs.search('banana');
  assert.deepEqual(await fs.get(banana.externalId), banana);
  assert.equal(await fs.get('no-such-id'), null);
});

test('http mode needs both credentials', () => {
  assert.throws(() => createFatsecretService({ mode: 'http', clientId: 'a' }), /FATSECRET_CONSUMER_SECRET/);
});

test('an unknown mode is refused', () => {
  assert.throws(() => createFatsecretService({ mode: 'soap' }), /Unsupported FATSECRET_MODE/);
});
