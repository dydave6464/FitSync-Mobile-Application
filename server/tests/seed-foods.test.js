'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedFoods, FOODS } = require('../src/db/seed-foods');

test('the seed list is well formed', () => {
  assert.ok(FOODS.length >= 60, `expected about 60 foods, got ${FOODS.length}`);
  assert.equal(new Set(FOODS.map((f) => f.name)).size, FOODS.length, 'names must be unique');
  for (const f of FOODS) {
    assert.ok(['filipino', 'international'].includes(f.category), f.name);
    assert.ok(typeof f.source === 'string' && f.source.length > 0, `${f.name} needs a source`);
    for (const k of ['proteinG', 'carbsG', 'fatG']) assert.ok(f[k] >= 0 && f[k] < 1000, `${f.name} ${k}`);
    assert.ok(typeof f.fiberG === 'number' && f.fiberG >= 0 && f.fiberG < 100, `${f.name} fiberG`);
    // Atwater check, to catch a typo: within 40 kcal or 20 %.
    const atwater = 4 * f.proteinG + 4 * f.carbsG + 9 * f.fatG;
    assert.ok(Math.abs(atwater - f.kcal) <= Math.max(40, f.kcal * 0.2), `${f.name}: ${f.kcal} vs ${atwater}`);
  }
});

test('food seed', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  await t.test('inserts every food', async () => {
    const s = await seedFoods(testDbConfig());
    assert.equal(s.inserted, FOODS.length);
    const [[{ n }]] = await pool.query('SELECT COUNT(*) AS n FROM foods');
    assert.equal(Number(n), FOODS.length);
  });

  await t.test('seeds Ginisang monggo\'s fiber_g as 6', async () => {
    const [[row]] = await pool.query("SELECT fiber_g FROM foods WHERE name = 'Ginisang monggo'");
    assert.equal(Number(row.fiber_g), 6);
  });

  await t.test('is idempotent and reports nothing changed', async () => {
    const s = await seedFoods(testDbConfig());
    assert.deepEqual(s, { inserted: 0, updated: 0, unchanged: FOODS.length, total: FOODS.length });
  });

  await t.test('updates a changed number in place', async () => {
    await pool.query("UPDATE foods SET calories = 1 WHERE name = 'Chicken adobo'");
    const s = await seedFoods(testDbConfig());
    assert.equal(s.updated, 1);
    const [[row]] = await pool.query("SELECT calories FROM foods WHERE name = 'Chicken adobo'");
    assert.equal(row.calories, 320);
  });

  await t.test('never touches a FatSecret copy with the same name', async () => {
    const [f] = await pool.query("INSERT INTO foods (name, category, calories) VALUES ('Banana', 'international', 999)");
    await pool.query("INSERT INTO food_sources (food_id, provider, external_id) VALUES (?, 'fatsecret', 'x1')", [f.insertId]);
    await seedFoods(testDbConfig());
    const [[copy]] = await pool.query('SELECT calories FROM foods WHERE food_id = ?', [f.insertId]);
    assert.equal(copy.calories, 999);
  });
});
