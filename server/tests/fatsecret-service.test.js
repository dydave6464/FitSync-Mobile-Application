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
  assert.deepEqual(await fs.get(banana.externalId), { ...banana, fiberG: 3.1, sugarG: 14.43, sodiumMg: 1.2 });
  assert.equal(await fs.get('no-such-id'), null);
});

test('like the real search, stub search items have unknown fiber, sugar and sodium', async () => {
  const fs = createFatsecretService({ mode: 'stub' });
  for (const q of ['banana', 'fried chicken', 'white rice']) {
    const [item] = await fs.search(q);
    for (const key of ['fiberG', 'sugarG', 'sodiumMg']) {
      assert.ok(Object.hasOwn(item, key), `${q} carries a ${key} key`);
      assert.equal(item[key], null, `${q} ${key}`);
    }
  }
});

test('the stub get() carries a fiberG, sugarG and sodiumMg for each of its foods', async () => {
  const fs = createFatsecretService({ mode: 'stub' });
  const byName = async (q) => fs.get((await fs.search(q))[0].externalId);
  const banana = await byName('banana');
  assert.equal(banana.fiberG, 3.1);
  assert.equal(banana.sugarG, 14.43);
  assert.equal(banana.sodiumMg, 1.2);
  const friedChicken = await byName('fried chicken');
  assert.equal(friedChicken.fiberG, 0.5);
  assert.equal(friedChicken.sugarG, 0);
  assert.equal(friedChicken.sodiumMg, 386);
  const whiteRice = await byName('white rice');
  assert.equal(whiteRice.fiberG, 0.6);
  assert.equal(whiteRice.sugarG, 0.08);
  assert.equal(whiteRice.sodiumMg, 1.6);
});

test('http mode needs both credentials', () => {
  assert.throws(() => createFatsecretService({ mode: 'http', clientId: 'a' }), /FATSECRET_CONSUMER_SECRET/);
});

test('an unknown mode is refused', () => {
  assert.throws(() => createFatsecretService({ mode: 'soap' }), /Unsupported FATSECRET_MODE/);
});
