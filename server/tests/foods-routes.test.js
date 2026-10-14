'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');
const { silentLogger } = require('./helpers/test-app');

test('food search and recents', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  let mode = 'ok';
  let getMode = 'ok';
  const fatsecret = {
    timeoutMs: 50,
    async search(q) {
      if (mode === 'down') throw new Error('down');
      if (mode === 'slow') return new Promise(() => {}); // never answers
      // Fails just after the route stops waiting, as the real client's own
      // abort timer does when FatSecret is slow.
      if (mode === 'late') return new Promise((_, reject) => { setTimeout(() => reject(new Error('aborted')), 80); });
      return [{ externalId: 'fs-9', name: `FatSecret ${q}`, servingDesc: '1 cup', kcal: 200, proteinG: 10, carbsG: 20, fatG: 8 }];
    },
    async get(externalId) {
      if (getMode === 'down') throw new Error('down');
      if (externalId === 'fs-9') {
        return { externalId: 'fs-9', name: 'FatSecret chicken thigh', servingDesc: '1 thigh', kcal: 107, proteinG: 12, carbsG: 2, fatG: 6 };
      }
      return null;
    },
  };
  const warnings = [];
  const logger = silentLogger();
  logger.warn = (_fields, msg) => { warnings.push(msg); };
  const app = buildTestApp({ pool, fatsecret, logger });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const insert = (name) => pool.query(
    "INSERT INTO foods (name, category, serving_desc, calories, protein_g, carbs_g, fat_g) VALUES (?, 'filipino', '1 cup', 300, 20, 10, 15)",
    [name],
  ).then(([r]) => r.insertId);
  const pork = await insert('Pork adobo');
  const chicken = await insert('Chicken adobo');
  await insert('Adobong kangkong');
  await insert('100% juice');
  const copy = await insert('Adobo copy from FatSecret');
  await pool.query("INSERT INTO food_sources (food_id, provider, external_id) VALUES (?, 'fatsecret', 'fs-old')", [copy]);

  const [reg] = [await request(app).post('/api/v1/auth/register')
    .send({ email: 'f1@example.com', password: 's3cret-pass', fullName: 'F' }).expect(201)];
  await markEmailVerified(pool, reg.body.data.user.userId);
  const login = await request(app).post('/api/v1/auth/login')
    .send({ email: 'f1@example.com', password: 's3cret-pass' }).expect(200);
  const auth = { Authorization: `Bearer ${login.body.data.token}` };
  const search = (q) => request(app).get('/api/v1/foods/search').query({ q }).set(auth);

  await t.test('requires sign-in', async () => {
    await request(app).get('/api/v1/foods/search?q=adobo').expect(401);
    await request(app).get('/api/v1/foods/recent').expect(401);
  });

  await t.test('own foods first (prefix matches first, no FatSecret copies), then FatSecret', async () => {
    const { foods, fatsecretUnavailable } = (await search('adobo').expect(200)).body.data;
    assert.equal(fatsecretUnavailable, false);
    assert.deepEqual(foods.map((f) => f.name), ['Adobong kangkong', 'Chicken adobo', 'Pork adobo', 'FatSecret adobo']);
    assert.deepEqual(foods[1], {
      id: chicken, source: 'local', externalId: null, name: 'Chicken adobo', servingDesc: '1 cup',
      kcal: 300, proteinG: 20, carbsG: 10, fatG: 15,
    });
    assert.deepEqual(foods[3], {
      id: null, source: 'fatsecret', externalId: 'fs-9', name: 'FatSecret adobo', servingDesc: '1 cup',
      kcal: 200, proteinG: 10, carbsG: 20, fatG: 8,
    });
  });

  await t.test('LIKE wildcards are literal', async () => {
    const { foods } = (await search('0%').expect(200)).body.data;
    assert.deepEqual(foods.filter((f) => f.source === 'local').map((f) => f.name), ['100% juice']);
  });

  await t.test('FatSecret down or slow -> own foods plus the flag, still 200', async () => {
    for (const m of ['down', 'slow']) {
      mode = m;
      const { foods, fatsecretUnavailable } = (await search('adobo').expect(200)).body.data;
      assert.equal(fatsecretUnavailable, true, m);
      assert.ok(foods.every((f) => f.source === 'local'), m);
    }
    mode = 'ok';
  });

  await t.test('a timed-out search is not logged as a failure, even when it fails late', async () => {
    const failures = () => warnings.filter((m) => m === 'FatSecret food search failed');
    warnings.length = 0;
    mode = 'late';
    assert.equal((await search('adobo').expect(200)).body.data.fatsecretUnavailable, true);
    await new Promise((resolve) => { setTimeout(resolve, 150); });
    assert.deepEqual(failures(), []);
    mode = 'down';
    await search('adobo').expect(200);
    assert.equal(failures().length, 1, 'a real failure still is');
    mode = 'ok';
  });

  await t.test('no FatSecret service (stub mode in production): own foods + flag, FatSecret log -> 502', async () => {
    const off = buildTestApp({ pool, fatsecret: null });
    const { foods, fatsecretUnavailable } = (await request(off).get('/api/v1/foods/search')
      .query({ q: 'adobo' }).set(auth).expect(200)).body.data;
    assert.equal(fatsecretUnavailable, true);
    assert.ok(foods.length > 0 && foods.every((f) => f.source === 'local'));
    const res = await request(off).post('/api/v1/nutrition/entries').set(auth)
      .send({ mealType: 'lunch', servings: 1, food: { source: 'fatsecret', externalId: 'stub-1' } }).expect(502);
    assert.equal(res.body.error.code, 'FATSECRET_UNAVAILABLE');
  });

  await t.test('q must be 2 to 60 characters', async () => {
    for (const q of ['a', ' a ', 'x'.repeat(61)]) {
      const res = await search(q).expect(400);
      assert.equal(res.body.error.code, 'INVALID_FOOD_QUERY');
    }
    await request(app).get('/api/v1/foods/search').set(auth).expect(400);
  });

  await t.test('GET /foods/fatsecret/:externalId: the same detail the log sheet will show', async () => {
    await request(app).get('/api/v1/foods/fatsecret/fs-9').expect(401);

    const ok = await request(app).get('/api/v1/foods/fatsecret/fs-9').set(auth).expect(200);
    assert.deepEqual(ok.body.data.food, {
      id: null, source: 'fatsecret', externalId: 'fs-9', name: 'FatSecret chicken thigh', servingDesc: '1 thigh',
      kcal: 107, proteinG: 12, carbsG: 2, fatG: 6,
    });

    const missing = await request(app).get('/api/v1/foods/fatsecret/fs-missing').set(auth).expect(404);
    assert.equal(missing.body.error.code, 'FOOD_NOT_FOUND');

    warnings.length = 0;
    getMode = 'down';
    const down = await request(app).get('/api/v1/foods/fatsecret/fs-9').set(auth).expect(502);
    assert.equal(down.body.error.code, 'FATSECRET_UNAVAILABLE');
    // The error handler also logs the 502 itself; the route's own line must be there too.
    assert.ok(warnings.includes('FatSecret food lookup failed'), JSON.stringify(warnings));
    getMode = 'ok';

    const long = await request(app).get(`/api/v1/foods/fatsecret/${'x'.repeat(65)}`).set(auth).expect(400);
    assert.equal(long.body.error.code, 'INVALID_FOOD_QUERY');
  });

  await t.test('recents: distinct, newest first, per serving', async () => {
    const log = (food, servings = 1) => request(app).post('/api/v1/nutrition/entries').set(auth)
      .send({ mealType: 'lunch', servings, food }).expect(201);
    await log({ source: 'local', id: pork });
    await log({ source: 'manual', name: 'Turon', proteinG: 2, carbsG: 34, fatG: 6 }, 2);
    await log({ source: 'local', id: chicken });
    await log({ source: 'local', id: pork }, 3);
    const { foods } = (await request(app).get('/api/v1/foods/recent').set(auth).expect(200)).body.data;
    assert.deepEqual(foods.map((f) => f.name), ['Pork adobo', 'Chicken adobo', 'Turon']);
    assert.equal(foods[0].kcal, 300, 'a catalogue food reads its own per-serving numbers');
    assert.deepEqual(foods[2], {
      id: null, source: 'manual', externalId: null, name: 'Turon', servingDesc: null,
      kcal: 198, proteinG: 2, carbsG: 34, fatG: 6,
    });
  });
});
