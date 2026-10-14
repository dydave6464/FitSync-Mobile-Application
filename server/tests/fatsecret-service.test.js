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
  assert.deepEqual(await fs.get(banana.externalId), { ...banana, fiberG: 3.1 });
  assert.equal(await fs.get('no-such-id'), null);
});

test('like the real search, stub search items have unknown fiber', async () => {
  const fs = createFatsecretService({ mode: 'stub' });
  for (const q of ['banana', 'fried chicken', 'white rice']) {
    const [item] = await fs.search(q);
    assert.ok(Object.hasOwn(item, 'fiberG'), `${q} carries a fiberG key`);
    assert.equal(item.fiberG, null, q);
  }
});

test('the stub get() carries a fiberG for each of its foods', async () => {
  const fs = createFatsecretService({ mode: 'stub' });
  const byName = async (q) => fs.get((await fs.search(q))[0].externalId);
  assert.equal((await byName('banana')).fiberG, 3.1);
  assert.equal((await byName('fried chicken')).fiberG, 0.5);
  assert.equal((await byName('white rice')).fiberG, 0.6);
});

test('http mode needs both credentials', () => {
  assert.throws(() => createFatsecretService({ mode: 'http', clientId: 'a' }), /FATSECRET_CONSUMER_SECRET/);
});

test('an unknown mode is refused', () => {
  assert.throws(() => createFatsecretService({ mode: 'soap' }), /Unsupported FATSECRET_MODE/);
});
