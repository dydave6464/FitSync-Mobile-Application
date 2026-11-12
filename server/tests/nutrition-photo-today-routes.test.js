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
const { insertRecognition } = require('../src/db/photo-recognitions');

test('GET /nutrition/recognitions/today', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  let answer = async () => ({ items: [] });
  const vision = { model: 'fake', async recognize(args) { return answer(args); } };
  const app = buildTestApp({ pool, vision });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const food = async (name, servingDesc, kcal) => (await pool.query(
    `INSERT INTO foods (name, category, serving_desc, calories, protein_g, carbs_g, fat_g, fiber_g)
     VALUES (?, 'filipino', ?, ?, 4, 40, 1, 0.5)`,
    [name, servingDesc, kcal],
  ))[0].insertId;
  const RICE = await food('White rice', '1 cup (160 g)', 206);
  const GARLIC = await food('Garlic fried rice (sinangag)', '1 cup (160 g)', 299);
  // A FatSecret copy someone has logged: on the menu, flagged fromFatsecret.
  const [mango] = await pool.query("INSERT INTO foods (name, category, serving_desc, calories) VALUES ('Mango Shake', 'international', '1 glass', 250)");
  await pool.query("INSERT INTO food_sources (food_id, provider, external_id) VALUES (?, 'fatsecret', 'fs-1')", [mango.insertId]);
  const [someone] = await pool.query("INSERT INTO users (email, password_hash, full_name) VALUES ('someone@b.com', 'x', 'S')");
  await pool.query(
    "INSERT INTO meal_logs (user_id, food_id, meal_type, servings, calories, logged_via, log_date) VALUES (?, ?, 'snack', 1, 250, 'search', CURDATE())",
    [someone.insertId, mango.insertId],
  );
  const RICE_MANGO_ATCHARA = async () => ({ items: [
    { menu: 'White rice', name: 'White rice', quantity: 1, unit: 'cup', grams: 240, confidence: 0.95, alternatives: ['Garlic fried rice (sinangag)'] },
    { menu: 'Mango Shake', name: 'Mango Shake', quantity: 1, unit: 'glass', grams: null, confidence: 0.7, alternatives: [] },
    { menu: null, name: 'Atchara (pickled papaya)', quantity: 1, unit: 'tbsp', grams: 15, confidence: 0.4, alternatives: [] },
  ] });

  let seq = 0;
  const freshUser = async ({ pro }) => {
    seq += 1;
    const email = `today${seq}@example.com`;
    const reg = await request(app).post('/api/v1/auth/register').send({ email, password: 's3cret-pass', fullName: 'T' }).expect(201);
    const userId = reg.body.data.user.userId;
    await markEmailVerified(pool, userId);
    if (pro) await pool.query('UPDATE users SET is_premium = 1 WHERE user_id = ?', [userId]);
    const login = await request(app).post('/api/v1/auth/login').send({ email, password: 's3cret-pass' }).expect(200);
    const auth = { Authorization: `Bearer ${login.body.data.token}` };
    return {
      userId,
      today: () => request(app).get('/api/v1/nutrition/recognitions/today').set(auth),
      recognize: () => request(app).post('/api/v1/nutrition/recognize').set(auth)
        .send({ image: Buffer.from([0xff, 0xd8, 0xff, 0xe0]).toString('base64'), mimeType: 'image/jpeg' }),
      log: (id, body) => request(app).post(`/api/v1/nutrition/recognitions/${id}/log`).set(auth).send(body),
    };
  };
  // [n] rows of [status] for [userId], created at [when] (an SQL expression).
  const rows = (userId, n, status, when = 'NOW()') => pool.query(
    `INSERT INTO photo_recognitions (user_id, item_count, status, created_at)
     VALUES ${Array(n).fill(`(?, 0, '${status}', ${when})`).join(', ')}`,
    Array(n).fill(userId),
  );

  await t.test('signed out is 401; a free account is 403 PRO_REQUIRED', async () => {
    const out = await request(app).get('/api/v1/nutrition/recognitions/today').expect(401);
    assert.equal(out.body.error.code, 'UNAUTHENTICATED');
    const u = await freshUser({ pro: false });
    const res = await u.today().expect(403);
    assert.equal(res.body.error.code, 'PRO_REQUIRED');
    assert.equal(res.body.error.message, 'Snap a meal is part of FitSync Pro.');
  });

  await t.test('a new Pro user has the whole allowance and nothing to finish', async () => {
    const u = await freshUser({ pro: true });
    assert.deepEqual((await u.today().expect(200)).body, { data: { limit: 15, remainingToday: 15, unlogged: null } });
  });

  await t.test('only today\'s recognised photos count: not empty or failed ones, not yesterday\'s', async () => {
    const u = await freshUser({ pro: true });
    await rows(u.userId, 3, 'recognised');
    await rows(u.userId, 2, 'empty');
    await rows(u.userId, 4, 'failed');
    // The pool runs at +08:00: CURDATE() - 1 second is late yesterday in Manila.
    await rows(u.userId, 2, 'recognised', 'CURDATE() - INTERVAL 1 SECOND');
    const d = (await u.today().expect(200)).body.data;
    assert.deepEqual([d.limit, d.remainingToday], [15, 12]);
  });

  await t.test('more photos than the limit answers 0, never a negative number', async () => {
    const u = await freshUser({ pro: true });
    await rows(u.userId, 16, 'recognised');
    assert.equal((await u.today().expect(200)).body.data.remainingToday, 0);
  });

  await t.test('today\'s unlogged photo comes back as the recognize answer gave it, with when it was taken', async () => {
    const u = await freshUser({ pro: true });
    answer = RICE_MANGO_ATCHARA;
    const first = (await u.recognize().expect(200)).body.data;
    assert.deepEqual([first.items.length, first.unlisted.length], [2, 1]);
    const [[row]] = await pool.query('SELECT created_at FROM photo_recognitions WHERE recognition_id = ?', [first.recognitionId]);
    const d = (await u.today().expect(200)).body.data;
    assert.equal(d.remainingToday, 14);
    assert.deepEqual(d.unlogged, { ...first, createdAt: row.created_at.toISOString() });
    assert.equal(d.unlogged.items[1].food.fromFatsecret, true, 'a FatSecret copy says so');
    assert.equal(d.unlogged.items[0].food.id, RICE);
    assert.deepEqual(d.unlogged.items[0].alternatives.map((a) => a.id), [GARLIC]);

    // Logged: nothing left to finish.
    await u.log(first.recognitionId, {
      date: manilaDay(), mealType: 'lunch',
      items: [{ itemId: first.items[0].itemId, servings: 1.5, food: { source: 'local', id: RICE } }],
    }).expect(201);
    const after = (await u.today().expect(200)).body.data;
    assert.deepEqual([after.remainingToday, after.unlogged], [14, null]);
  });

  await t.test('an empty photo taken after a recognised one leaves the recognised one to finish', async () => {
    const u = await freshUser({ pro: true });
    answer = RICE_MANGO_ATCHARA;
    const first = (await u.recognize().expect(200)).body.data;
    answer = async () => ({ items: [] });
    await u.recognize().expect(200);
    const d = (await u.today().expect(200)).body.data;
    assert.equal(d.unlogged.recognitionId, first.recognitionId);
    assert.equal(d.unlogged.remainingToday, 14);
  });

  await t.test('a suggested food deleted since comes back unlisted by its name; a deleted alternative is left out', async () => {
    const u = await freshUser({ pro: true });
    const PANCIT = await food('Pancit canton', '1 cup (200 g)', 320);
    const LUMPIA = await food('Lumpiang shanghai', '3 pieces (75 g)', 210);
    const { recognitionId, itemIds } = await insertRecognition(pool, u.userId, [
      { foodId: RICE, name: 'White rice', confidence: null, servings: 2, alternativeFoodIds: [LUMPIA, GARLIC] },
      { foodId: PANCIT, name: 'Pancit canton', confidence: 0.6, servings: 1, alternativeFoodIds: [] },
      { foodId: null, name: 'Atchara (pickled papaya)', confidence: 0.4, servings: null, alternativeFoodIds: [] },
    ]);
    await pool.query('DELETE FROM foods WHERE food_id IN (?, ?)', [PANCIT, LUMPIA]);
    const { unlogged } = (await u.today().expect(200)).body.data;
    assert.equal(unlogged.recognitionId, recognitionId);
    assert.deepEqual(unlogged.items.map((i) => [i.itemId, i.food.id, i.servings, i.confidence, i.alternatives.map((a) => a.id)]), [
      [itemIds[0], RICE, 2, null, [GARLIC]],
    ]);
    assert.deepEqual(unlogged.unlisted, [
      { itemId: itemIds[1], name: 'Pancit canton' },
      { itemId: itemIds[2], name: 'Atchara (pickled papaya)' },
    ]);
  });

  await t.test('when the newest recognised photo is logged, an older unlogged one is not offered', async () => {
    const u = await freshUser({ pro: true });
    const one = [{ foodId: RICE, name: 'White rice', confidence: 0.9, servings: 1, alternativeFoodIds: [] }];
    await insertRecognition(pool, u.userId, one);
    const { recognitionId } = await insertRecognition(pool, u.userId, one);
    await pool.query('UPDATE photo_recognitions SET logged_at = NOW() WHERE recognition_id = ?', [recognitionId]);
    assert.equal((await u.today().expect(200)).body.data.unlogged, null);
  });
});
