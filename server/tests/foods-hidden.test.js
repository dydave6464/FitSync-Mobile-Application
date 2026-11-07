'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { TEST_JWT } = require('./helpers/admin');
const { signToken } = require('../src/lib/tokens');
const { loadMenuFoods } = require('../src/db/vision-menu');

// A hidden food (an admin's Hide, migration 045) leaves food search, Recents
// and Snap a meal's menu; logging it by id, and meals already logged, are
// unaffected.
test('hidden foods', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const insert = (name, listOrder) => pool.query(
    `INSERT INTO foods (name, category, serving_desc, calories, protein_g, carbs_g, fat_g, list_order)
     VALUES (?, 'filipino', '1 cup', 250, 5, 45, 6, ?)`,
    [name, listOrder],
  ).then(([r]) => r.insertId);
  const hidden = await insert('Halo-halo special', 1);
  const shown = await insert('Halo-halo regular', 2);

  const [u] = await pool.query(
    "INSERT INTO users (email, password_hash, full_name) VALUES ('h@example.com', 'x', 'H')",
  );
  const auth = { Authorization: `Bearer ${signToken(u.insertId, TEST_JWT)}` };
  const log = (foodId) => request(app).post('/api/v1/nutrition/entries').set(auth)
    .send({ mealType: 'snack', servings: 1, food: { source: 'local', id: foodId } });

  // Logged while still shown, the hidden food last (newest in Recents).
  await log(shown).expect(201);
  const before = (await log(hidden).expect(201)).body.data.entry;
  await pool.query('UPDATE foods SET hidden_at = NOW() WHERE food_id = ?', [hidden]);

  await t.test('food search leaves it out', async () => {
    const res = await request(app).get('/api/v1/foods/search').query({ q: 'halo' }).set(auth).expect(200);
    assert.deepEqual(res.body.data.foods.map((f) => f.id), [shown]);
  });

  await t.test('Recents leave it out', async () => {
    const res = await request(app).get('/api/v1/foods/recent').set(auth).expect(200);
    assert.deepEqual(res.body.data.foods.map((f) => f.id), [shown]);
  });

  await t.test("Snap a meal's menu leaves it out", async () => {
    const menu = await loadMenuFoods(pool);
    assert.deepEqual(menu.map((f) => f.foodId), [shown]);
  });

  await t.test('logging it by id still works, and the meal already logged reads back', async () => {
    const { entry } = (await log(hidden).expect(201)).body.data;
    assert.equal(entry.foodId, hidden);
    assert.equal(entry.name, 'Halo-halo special');
    const { day } = (await request(app).get('/api/v1/nutrition/day').set(auth).expect(200)).body.data;
    const snackIds = day.meals.snack.map((e) => e.id);
    assert.ok(snackIds.includes(before.id));
    assert.equal(day.meals.snack.find((e) => e.id === before.id).name, 'Halo-halo special');
  });
});
