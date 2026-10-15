'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { create, parseDescription } = require('../src/services/fatsecret/http-client');

function reply(body, status = 200) {
  return { ok: status >= 200 && status < 300, status, json: async () => body };
}

function fakeFetch(routes) {
  const calls = [];
  const impl = async (url, init = {}) => {
    calls.push({ url: String(url), init });
    for (const [match, respond] of routes) if (String(url).includes(match)) return respond(String(url), init);
    throw new Error(`unexpected fetch ${url}`);
  };
  return { impl, calls };
}

const TOKEN = ['oauth.fatsecret.com', () => reply({ access_token: 'tok', expires_in: 86400 })];

test('parseDescription reads serving and numbers', () => {
  assert.deepEqual(
    parseDescription('Per 1 cup - Calories: 466kcal | Fat: 30.71g | Carbs: 5.46g | Protein: 40.60g'),
    { servingDesc: '1 cup', kcal: 466, fatG: 30.71, carbsG: 5.46, proteinG: 40.6 },
  );
  assert.equal(parseDescription('garbage'), null);
});

test('search gets a token with client credentials, then maps results', async () => {
  const { impl, calls } = fakeFetch([TOKEN, ['server.api', () => reply({
    foods: { food: [
      { food_id: '33691', food_name: 'Chicken Adobo', food_type: 'Generic',
        food_description: 'Per 1 cup - Calories: 466kcal | Fat: 30.71g | Carbs: 5.46g | Protein: 40.60g' },
      { food_id: '9', food_name: 'Tuna', food_type: 'Brand', brand_name: 'Century',
        food_description: 'Per 1 can - Calories: 130kcal | Fat: 1.00g | Carbs: 0.00g | Protein: 29.00g' },
      { food_id: '10', food_name: 'Broken', food_description: 'no numbers' },
    ] },
  })]]);
  const client = create({ clientId: 'id', clientSecret: 'secret', fetchImpl: impl });
  const found = await client.search('adobo');

  assert.equal(calls[0].init.method, 'POST');
  assert.equal(calls[0].init.headers.Authorization, `Basic ${Buffer.from('id:secret').toString('base64')}`);
  assert.match(calls[0].init.body, /grant_type=client_credentials/);
  assert.match(calls[0].init.body, /scope=basic/);
  assert.match(calls[1].url, /method=foods\.search/);
  assert.match(calls[1].url, /search_expression=adobo/);
  assert.equal(calls[1].init.headers.Authorization, 'Bearer tok');
  assert.deepEqual(found, [
    { externalId: '33691', name: 'Chicken Adobo', servingDesc: '1 cup', kcal: 466, proteinG: 40.6, carbsG: 5.46, fatG: 30.71, fiberG: null, sugarG: null, sodiumMg: null },
    { externalId: '9', name: 'Tuna (Century)', servingDesc: '1 can', kcal: 130, proteinG: 29, carbsG: 0, fatG: 1, fiberG: null, sugarG: null, sodiumMg: null },
  ]);
});

test('a single result (an object, not an array) and no results both work', async () => {
  let body = { foods: { food: { food_id: '1', food_name: 'Egg',
    food_description: 'Per 1 large - Calories: 78kcal | Fat: 5.30g | Carbs: 0.60g | Protein: 6.30g' } } };
  const { impl } = fakeFetch([TOKEN, ['server.api', () => reply(body)]]);
  const client = create({ clientId: 'id', clientSecret: 's', fetchImpl: impl });
  assert.equal((await client.search('egg')).length, 1);
  body = { foods: { total_results: '0' } };
  assert.deepEqual(await client.search('zzz'), []);
});

test('the token is cached until a minute before it expires', async () => {
  let clock = 0;
  const { impl, calls } = fakeFetch([
    ['oauth.fatsecret.com', () => reply({ access_token: 'tok', expires_in: 120 })],
    ['server.api', () => reply({ foods: {} })],
  ]);
  const client = create({ clientId: 'id', clientSecret: 's', fetchImpl: impl, now: () => clock });
  await client.search('a1');
  await client.search('a2');
  assert.equal(calls.filter((c) => c.url.includes('oauth')).length, 1);
  clock = 61_000; // 59 s left: inside the 60 s margin
  await client.search('a3');
  assert.equal(calls.filter((c) => c.url.includes('oauth')).length, 2);
});

test('get picks the default serving', async () => {
  const { impl, calls } = fakeFetch([TOKEN, ['server.api', () => reply({
    food: { food_id: '33691', food_name: 'Chicken Adobo', servings: { serving: [
      { serving_description: '100 g', calories: '199', protein: '17.4', carbohydrate: '2.3', fat: '13.1' },
      { serving_description: '1 cup', calories: '466', protein: '40.60', carbohydrate: '5.46', fat: '30.71', fiber: '0.30', is_default: '1' },
    ] } },
  })]]);
  const client = create({ clientId: 'id', clientSecret: 's', fetchImpl: impl });
  assert.deepEqual(await client.get('33691'), {
    externalId: '33691', name: 'Chicken Adobo', servingDesc: '1 cup', kcal: 466, proteinG: 40.6, carbsG: 5.46, fatG: 30.71,
    fiberG: 0.3, sugarG: null, sodiumMg: null,
  });
  assert.match(calls[1].url, /method=food\.get\.v2/);
  assert.match(calls[1].url, /food_id=33691/);
});

test('get returns sugarG and sodiumMg from the default serving', async () => {
  const { impl } = fakeFetch([TOKEN, ['server.api', () => reply({
    food: { food_id: '7', food_name: 'Sweet Soda', servings: { serving: {
      serving_description: '1 can', calories: '150', protein: '0', carbohydrate: '39', fat: '0',
      sugar: '1.20', sodium: '345.5', is_default: '1',
    } } },
  })]]);
  const client = create({ clientId: 'id', clientSecret: 's', fetchImpl: impl });
  assert.deepEqual(await client.get('7'), {
    externalId: '7', name: 'Sweet Soda', servingDesc: '1 can', kcal: 150, proteinG: 0, carbsG: 39, fatG: 0,
    fiberG: null, sugarG: 1.2, sodiumMg: 345.5,
  });
});

test('get returns fiberG/sugarG/sodiumMg null when absent or an empty string', async () => {
  const { impl: implAbsent } = fakeFetch([TOKEN, ['server.api', () => reply({
    food: { food_id: '1', food_name: 'No Fiber Field', servings: { serving: {
      serving_description: '1 cup', calories: '100', protein: '1', carbohydrate: '1', fat: '1', is_default: '1',
    } } },
  })]]);
  const clientAbsent = create({ clientId: 'id', clientSecret: 's', fetchImpl: implAbsent });
  const absent = await clientAbsent.get('1');
  assert.equal(absent.fiberG, null);
  assert.equal(absent.sugarG, null);
  assert.equal(absent.sodiumMg, null);

  const { impl: implEmpty } = fakeFetch([TOKEN, ['server.api', () => reply({
    food: { food_id: '2', food_name: 'Empty Fiber', servings: { serving: {
      serving_description: '1 cup', calories: '100', protein: '1', carbohydrate: '1', fat: '1',
      fiber: '', sugar: '', sodium: '', is_default: '1',
    } } },
  })]]);
  const clientEmpty = create({ clientId: 'id', clientSecret: 's', fetchImpl: implEmpty });
  const empty = await clientEmpty.get('2');
  assert.equal(empty.fiberG, null);
  assert.equal(empty.sugarG, null);
  assert.equal(empty.sodiumMg, null);
});

test('an implausible fiber value becomes unknown; the food itself is kept', async () => {
  for (const fiber of ['1000', 'abc', '-1']) {
    const { impl } = fakeFetch([TOKEN, ['server.api', () => reply({
      food: { food_id: '5', food_name: 'Weird Fiber', servings: { serving: {
        serving_description: '1 cup', calories: '100', protein: '1', carbohydrate: '1', fat: '1', fiber, is_default: '1',
      } } },
    })]]);
    const client = create({ clientId: 'id', clientSecret: 's', fetchImpl: impl });
    assert.deepEqual(await client.get('5'), {
      externalId: '5', name: 'Weird Fiber', servingDesc: '1 cup', kcal: 100, proteinG: 1, carbsG: 1, fatG: 1,
      fiberG: null, sugarG: null, sodiumMg: null,
    }, `fiber ${fiber}`);
  }
});

test('an implausible sodium value becomes unknown; the food itself is kept', async () => {
  for (const sodium of ['-1', 'abc']) {
    const { impl } = fakeFetch([TOKEN, ['server.api', () => reply({
      food: { food_id: '6', food_name: 'Weird Sodium', servings: { serving: {
        serving_description: '1 cup', calories: '100', protein: '1', carbohydrate: '1', fat: '1', sodium, is_default: '1',
      } } },
    })]]);
    const client = create({ clientId: 'id', clientSecret: 's', fetchImpl: impl });
    assert.deepEqual(await client.get('6'), {
      externalId: '6', name: 'Weird Sodium', servingDesc: '1 cup', kcal: 100, proteinG: 1, carbsG: 1, fatG: 1,
      fiberG: null, sugarG: null, sodiumMg: null,
    }, `sodium ${sodium}`);
  }
});

test('get answers null for an unknown food', async () => {
  const { impl } = fakeFetch([TOKEN, ['server.api', () => reply({ error: { code: 106, message: 'Invalid ID' } })]]);
  const client = create({ clientId: 'id', clientSecret: 's', fetchImpl: impl });
  assert.equal(await client.get('nope'), null);
});

test('API and HTTP errors throw, naming FatSecret', async () => {
  const { impl } = fakeFetch([TOKEN, ['server.api', () => reply({ error: { code: 21, message: 'Invalid IP address detected' } })]]);
  const client = create({ clientId: 'id', clientSecret: 's', fetchImpl: impl });
  await assert.rejects(client.search('x'), /FatSecret .*21.*Invalid IP/);
  const down = fakeFetch([['oauth.fatsecret.com', () => reply({}, 503)]]);
  const c2 = create({ clientId: 'id', clientSecret: 's', fetchImpl: down.impl });
  await assert.rejects(c2.search('x'), /FatSecret token request failed: 503/);
});

test('an implausible food is dropped rather than stored', async () => {
  const { impl } = fakeFetch([TOKEN, ['server.api', () => reply({ foods: { food: [
    { food_id: '1', food_name: 'Whole cake', food_description: 'Per 1 cake - Calories: 9000kcal | Fat: 1200.00g | Carbs: 900.00g | Protein: 80.00g' },
  ] } })]]);
  const client = create({ clientId: 'id', clientSecret: 's', fetchImpl: impl });
  assert.deepEqual(await client.search('cake'), []);
});
