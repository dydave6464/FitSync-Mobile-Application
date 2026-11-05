'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');
const { manilaDay } = require('../src/lib/manila-day');
const { insertRecognition, insertFailed } = require('../src/db/photo-recognitions');

const FS_FOOD = { externalId: 'fs-1', name: 'Mango Shake', servingDesc: '1 glass', kcal: 250, proteinG: 4, carbsG: 50, fatG: 3.5 };

test('POST /nutrition/recognitions/:id/log', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  let fatsecretDown = false;
  const fatsecret = {
    async search() { return []; },
    async get(id) {
      if (fatsecretDown) throw new Error('down');
      return id === FS_FOOD.externalId ? { ...FS_FOOD } : null;
    },
  };
  const app = buildTestApp({ pool, fatsecret });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const food = async (name, servingDesc, kcal, p, c, f) => (await pool.query(
    "INSERT INTO foods (name, category, serving_desc, calories, protein_g, carbs_g, fat_g) VALUES (?, 'filipino', ?, ?, ?, ?, ?)",
    [name, servingDesc, kcal, p, c, f],
  ))[0].insertId;
  const RICE = await food('White rice', '1 cup (160 g)', 206, 3.4, 47.5, 0.3);
  const GARLIC = await food('Garlic fried rice (sinangag)', '1 cup (160 g)', 299, 4.2, 56.3, 6.4);
  const ADOBO = await food('Chicken adobo', '1 serving (150 g)', 320, 28, 4, 21);

  let seq = 0;
  const freshUser = async ({ pro = true } = {}) => {
    seq += 1;
    const email = `plog${seq}@example.com`;
    const reg = await request(app).post('/api/v1/auth/register').send({ email, password: 's3cret-pass', fullName: 'L' }).expect(201);
    const userId = reg.body.data.user.userId;
    await markEmailVerified(pool, userId);
    if (pro) await pool.query('UPDATE users SET is_premium = 1 WHERE user_id = ?', [userId]);
    const login = await request(app).post('/api/v1/auth/login').send({ email, password: 's3cret-pass' }).expect(200);
    const auth = { Authorization: `Bearer ${login.body.data.token}` };
    return {
      userId,
      log: (id, body) => request(app).post(`/api/v1/nutrition/recognitions/${id}/log`).set(auth).send(body),
      logEntry: (body) => request(app).post('/api/v1/nutrition/entries').set(auth).send(body),
      day: () => request(app).get('/api/v1/nutrition/day').set(auth),
    };
  };
  /// Rice (alternative: garlic rice), adobo, and an unlisted atchara.
  const photo = (u) => insertRecognition(pool, u.userId, [
    { foodId: RICE, name: 'White rice', confidence: 0.9, servings: 1.5, alternativeFoodIds: [GARLIC] },
    { foodId: ADOBO, name: 'Chicken adobo', confidence: 0.8, servings: 1, alternativeFoodIds: [] },
    { foodId: null, name: 'Atchara (pickled papaya)', confidence: 0.4, servings: null, alternativeFoodIds: [] },
  ]);
  const logsOf = async (userId) => (await pool.query('SELECT logged_via FROM meal_logs WHERE user_id = ?', [userId]))[0];
  const loggedAt = async (id) => (await pool.query('SELECT logged_at FROM photo_recognitions WHERE recognition_id = ?', [id]))[0][0].logged_at;
  const body = (items, extra = {}) => ({ date: manilaDay(), mealType: 'lunch', items, ...extra });

  await t.test('signed out is 401; a free account is 403 PRO_REQUIRED', async () => {
    await request(app).post('/api/v1/nutrition/recognitions/1/log').send({}).expect(401);
    const free = await freshUser({ pro: false });
    assert.equal((await free.log(1, body([])).expect(403)).body.error.code, 'PRO_REQUIRED');
  });

  await t.test('logs swapped, kept and added items as photo entries, and records each outcome', async () => {
    const u = await freshUser();
    const { recognitionId, itemIds } = await photo(u);
    const res = await u.log(recognitionId, body([
      { itemId: itemIds[0], servings: 1.5, food: { source: 'local', id: GARLIC } },
      { itemId: itemIds[1], servings: 2, food: { source: 'local', id: ADOBO } },
      { itemId: null, servings: 1, food: { source: 'manual', name: 'Atchara', proteinG: 0.5, carbsG: 10, fatG: 0 } },
    ])).expect(201);
    const { entries } = res.body.data;
    assert.deepEqual(entries.map((e) => [e.name, e.servings, e.kcal, e.mealType, e.source]), [
      ['Garlic fried rice (sinangag)', 1.5, 449, 'lunch', 'local'],
      ['Chicken adobo', 2, 640, 'lunch', 'local'],
      ['Atchara', 1, 42, 'lunch', 'manual'],
    ]);
    assert.deepEqual((await logsOf(u.userId)).map((r) => r.logged_via), ['photo', 'photo', 'photo']);
    const [items] = await pool.query(
      'SELECT outcome, logged_food_id, meal_log_id FROM photo_recognition_items WHERE recognition_id = ? ORDER BY item_order',
      [recognitionId],
    );
    assert.deepEqual(items.map((r) => [r.outcome, r.logged_food_id, r.meal_log_id]), [
      ['swapped', GARLIC, entries[0].id], ['kept', ADOBO, entries[1].id], ['removed', null, null],
    ]);
    assert.ok(await loggedAt(recognitionId));
    assert.equal((await u.day().expect(200)).body.data.day.meals.lunch.length, 3);
  });

  await t.test("an added item picked from Recents keeps its logged entry's kcal", async () => {
    const u = await freshUser();
    const SPIRIT = await food('Gin', '1 shot (40 ml)', 97, 0, 0, 0);
    const gin = { source: 'manual', name: 'Gin', servingDesc: '1 glass', proteinG: 0, carbsG: 0, fatG: 0 };
    const logged = (await u.logEntry({ mealType: 'dinner', servings: 1, food: { ...gin, basedOnFoodId: SPIRIT } }).expect(201)).body.data.entry;
    const { recognitionId } = await photo(u);
    const { entries } = (await u.log(recognitionId, body([
      { itemId: null, servings: 2, food: { ...gin, basedOnEntryId: logged.id } },
    ])).expect(201)).body.data;
    assert.deepEqual(entries.map((e) => [e.name, e.kcal, e.source]), [['Gin', 194, 'manual']]);
  });

  await t.test("another user's entry is no basis in Snap a meal either", async () => {
    const owner = await freshUser();
    const u = await freshUser();
    const theirs = (await owner.logEntry({
      mealType: 'dinner', servings: 1, food: { source: 'manual', name: 'Turon', proteinG: 2, carbsG: 34, fatG: 6 },
    }).expect(201)).body.data.entry;
    await pool.query('UPDATE meal_logs SET calories = 500 WHERE meal_log_id = ?', [theirs.id]);
    const { recognitionId } = await photo(u);
    const { entries } = (await u.log(recognitionId, body([
      { itemId: null, servings: 1, food: { source: 'manual', name: 'Turon', proteinG: 2, carbsG: 34, fatG: 6, basedOnEntryId: theirs.id } },
    ])).expect(201)).body.data;
    assert.equal(entries[0].kcal, 198);
  });

  await t.test('a photo is logged once: the second time is 409 ALREADY_LOGGED', async () => {
    const u = await freshUser();
    const { recognitionId, itemIds } = await photo(u);
    const items = [{ itemId: itemIds[0], servings: 1, food: { source: 'local', id: RICE } }];
    await u.log(recognitionId, body(items)).expect(201);
    assert.equal((await u.log(recognitionId, body(items)).expect(409)).body.error.code, 'ALREADY_LOGGED');
    assert.equal((await logsOf(u.userId)).length, 1);
  });

  await t.test('two logs of one photo at the same moment: one is logged, the other is 409', async () => {
    const u = await freshUser();
    const { recognitionId, itemIds } = await photo(u);
    const items = [{ itemId: itemIds[0], servings: 1, food: { source: 'local', id: RICE } }];
    const results = await Promise.all([u.log(recognitionId, body(items)), u.log(recognitionId, body(items))]);
    assert.deepEqual(results.map((r) => r.status).sort(), [201, 409]);
    assert.equal((await logsOf(u.userId)).length, 1);
  });

  await t.test('an unknown photo, another user\'s, or a failed attempt is 404 RECOGNITION_NOT_FOUND', async () => {
    const u = await freshUser();
    const other = await freshUser();
    const theirs = await photo(other);
    await insertFailed(pool, u.userId);
    const [[failed]] = await pool.query("SELECT MAX(recognition_id) AS id FROM photo_recognitions WHERE user_id = ? AND status = 'failed'", [u.userId]);
    const items = [{ itemId: null, servings: 1, food: { source: 'local', id: RICE } }];
    for (const id of [999999, theirs.recognitionId, failed.id, 'abc']) {
      assert.equal((await u.log(id, body(items)).expect(404)).body.error.code, 'RECOGNITION_NOT_FOUND');
    }
    assert.equal((await logsOf(u.userId)).length, 0);
  });

  await t.test('anything invalid is refused before anything is logged', async () => {
    const u = await freshUser();
    const { recognitionId, itemIds } = await photo(u);
    const other = await photo(u);
    const ok = { itemId: itemIds[0], servings: 1, food: { source: 'local', id: RICE } };
    const cases = [
      [body([ok], { date: '2999-01-01' }), 400, 'INVALID_DATE'],
      [body([ok], { mealType: 'brunch' }), 400, 'INVALID_NUTRITION_FIELD'],
      [body([]), 400, 'INVALID_NUTRITION_FIELD'],
      [body(Array(21).fill({ ...ok, itemId: null })), 400, 'INVALID_NUTRITION_FIELD'],
      [body([{ ...ok, servings: 0.25 }]), 400, 'INVALID_NUTRITION_FIELD'],
      [body([{ ...ok, itemId: 'x' }]), 400, 'INVALID_NUTRITION_FIELD'],
      [body([ok, { ...ok, servings: 2 }]), 400, 'INVALID_NUTRITION_FIELD'],
      [body([{ ...ok, itemId: other.itemIds[0] }]), 400, 'INVALID_NUTRITION_FIELD'],
      [body([ok, { itemId: null, servings: 1, food: { source: 'other' } }]), 400, 'INVALID_NUTRITION_FIELD'],
      [body([ok, { itemId: null, servings: 1, food: { source: 'local', id: 999999 } }]), 404, 'FOOD_NOT_FOUND'],
      [body([ok, { itemId: null, servings: 1, food: { source: 'manual', name: 'X', proteinG: 1, carbsG: 0, fatG: 0, basedOnEntryId: '7' } }]), 400, 'INVALID_NUTRITION_FIELD'],
    ];
    for (const [b, status, code] of cases) {
      const res = await u.log(recognitionId, b).expect(status);
      assert.equal(res.body.error.code, code, JSON.stringify(b).slice(0, 120));
    }
    assert.equal((await logsOf(u.userId)).length, 0);
    assert.equal(await loggedAt(recognitionId), null);
  });

  await t.test('all or nothing: FatSecret down for one item logs none of them; it logs once FatSecret is back', async () => {
    const u = await freshUser();
    const { recognitionId, itemIds } = await photo(u);
    const items = [
      { itemId: itemIds[0], servings: 1, food: { source: 'local', id: RICE } },
      { itemId: null, servings: 1, food: { source: 'fatsecret', externalId: 'fs-1' } },
    ];
    fatsecretDown = true;
    try {
      assert.equal((await u.log(recognitionId, body(items)).expect(502)).body.error.code, 'FATSECRET_UNAVAILABLE');
    } finally {
      fatsecretDown = false;
    }
    assert.equal((await logsOf(u.userId)).length, 0);
    assert.equal(await loggedAt(recognitionId), null);
    const { entries } = (await u.log(recognitionId, body(items)).expect(201)).body.data;
    assert.deepEqual(entries.map((e) => [e.name, e.source]), [['White rice', 'local'], ['Mango Shake', 'fatsecret']]);
    assert.deepEqual((await logsOf(u.userId)).map((r) => r.logged_via), ['photo', 'photo']);
  });
});
