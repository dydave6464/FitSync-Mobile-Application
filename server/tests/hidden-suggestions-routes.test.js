'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');

test('hidden suggestions', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const food = async (name, kcal, proteinG, carbsG, fatG, serving, { meals = '', rice = false, hidden = false } = {}) => {
    const [r] = await pool.query(
      `INSERT INTO foods (name, category, serving_desc, calories, protein_g, carbs_g, fat_g, suggest_meals,
                          suggest_with_rice, hidden_at)
       VALUES (?, 'filipino', ?, ?, ?, ?, ?, ?, ?, IF(?, NOW(), NULL))`,
      [name, serving, kcal, proteinG, carbsG, fatG, meals, rice, hidden],
    );
    return r.insertId;
  };
  const TINOLA = await food('Tinolang manok', 260, 26, 10, 12, '1 bowl', { meals: 'lunch,dinner', rice: true });
  const BANGUS = await food('Grilled bangus', 206, 35.1, 0, 7.2, '1 piece', { meals: 'lunch,dinner', rice: true });

  let seq = 0;
  const freshUser = async () => {
    seq += 1;
    const email = `hs${seq}@example.com`;
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email, password: 's3cret-pass', fullName: 'H' }).expect(201);
    await markEmailVerified(pool, res.body.data.user.userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email, password: 's3cret-pass' }).expect(200);
    const auth = { Authorization: `Bearer ${login.body.data.token}` };
    return {
      userId: res.body.data.user.userId,
      hidden: () => request(app).get('/api/v1/nutrition/suggestions/hidden').set(auth),
      hide: (id) => request(app).put(`/api/v1/nutrition/suggestions/hidden/${id}`).set(auth).send({}),
      show: (id) => request(app).delete(`/api/v1/nutrition/suggestions/hidden/${id}`).set(auth),
    };
  };

  await t.test('requires sign-in', async () => {
    await request(app).get('/api/v1/nutrition/suggestions/hidden').expect(401);
    await request(app).put(`/api/v1/nutrition/suggestions/hidden/${TINOLA}`).send({}).expect(401);
    await request(app).delete(`/api/v1/nutrition/suggestions/hidden/${TINOLA}`).expect(401);
  });

  await t.test('hide, list newest first, hide again harmlessly, show again', async () => {
    const u = await freshUser();
    assert.deepEqual((await u.hidden().expect(200)).body.data.hidden, []);
    const one = (await u.hide(TINOLA).expect(200)).body.data.hidden;
    assert.deepEqual(one.map((h) => [h.foodId, h.name]), [[TINOLA, 'Tinolang manok']]);
    assert.match(one[0].hiddenAt, /^\d{4}-\d{2}-\d{2}T/);
    await pool.query('UPDATE user_hidden_suggestions SET hidden_at = hidden_at - INTERVAL 1 MINUTE');
    await u.hide(BANGUS).expect(200);
    await u.hide(BANGUS).expect(200);
    assert.deepEqual((await u.hidden().expect(200)).body.data.hidden.map((h) => h.foodId), [BANGUS, TINOLA]);
    assert.deepEqual((await u.show(BANGUS).expect(200)).body.data.hidden.map((h) => h.foodId), [TINOLA]);
    assert.deepEqual((await u.show(BANGUS).expect(200)).body.data.hidden.map((h) => h.foodId), [TINOLA]);
  });

  await t.test("one user's hidden dishes are theirs alone", async () => {
    const a = await freshUser();
    const b = await freshUser();
    await a.hide(TINOLA).expect(200);
    assert.deepEqual((await b.hidden().expect(200)).body.data.hidden, []);
    await b.show(TINOLA).expect(200);
    assert.equal((await a.hidden().expect(200)).body.data.hidden.length, 1);
  });

  await t.test('an unknown food, a FatSecret copy or a bad id is FOOD_NOT_FOUND', async () => {
    const u = await freshUser();
    const [copy] = await pool.query("INSERT INTO foods (name, calories) VALUES ('Jollibee chickenjoy', 300)");
    await pool.query("INSERT INTO food_sources (food_id, provider, external_id) VALUES (?, 'fatsecret', 'fs-cj')", [copy.insertId]);
    for (const id of [999999, copy.insertId, 'abc', 0, -3]) {
      const res = await u.hide(id).expect(404);
      assert.equal(res.body.error.code, 'FOOD_NOT_FOUND', String(id));
    }
  });

  await t.test('a dish the admin hid from everyone drops out of the list', async () => {
    const u = await freshUser();
    await u.hide(BANGUS).expect(200);
    await pool.query('UPDATE foods SET hidden_at = NOW() WHERE food_id = ?', [BANGUS]);
    assert.deepEqual((await u.hidden().expect(200)).body.data.hidden, []);
    await pool.query('UPDATE foods SET hidden_at = NULL WHERE food_id = ?', [BANGUS]);
    assert.equal((await u.hidden().expect(200)).body.data.hidden.length, 1);
  });
});
